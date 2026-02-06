defmodule EMCP.Transport.StreamableHTTP do
  @moduledoc "MCP transport that communicates over HTTP using JSON-RPC."

  @behaviour Plug

  import Plug.Conn

  @default_session_ttl to_timeout(minute: 10)
  @default_keepalive_interval to_timeout(second: 30)

  # Public API

  @doc "Send a notification to a specific session's SSE connection."
  def notify(session_id, message) do
    case EMCP.SessionStore.get_sse_pid(session_id) do
      nil ->
        {:error, :no_sse_connection}

      pid ->
        send(pid, {:sse_message, JSON.encode!(message)})
        :ok
    end
  end

  @doc "Broadcast a notification to all sessions with active SSE connections."
  def broadcast(message) do
    encoded = JSON.encode!(message)

    :ets.tab2list(EMCP.SessionStore)
    |> Enum.each(fn
      {_session_id, _last_active, pid} when is_pid(pid) ->
        send(pid, {:sse_message, encoded})

      _ ->
        :ok
    end)
  end

  # Plug callbacks

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{method: "GET"} = conn, _opts), do: handle_get(conn)
  def call(%Plug.Conn{method: "POST"} = conn, _opts), do: handle_post(conn)
  def call(%Plug.Conn{method: "DELETE"} = conn, _opts), do: handle_delete(conn)
  def call(conn, _opts), do: json_error(conn, 405, "Method not allowed")

  # GET — SSE streaming

  defp handle_get(conn) do
    if accepts_event_stream?(conn) do
      with_session(conn, fn session_id ->
        EMCP.SessionStore.register_sse(session_id, self())

        conn =
          conn
          |> put_resp_content_type("text/event-stream")
          |> put_resp_header("cache-control", "no-cache")
          |> send_chunked(200)

        try do
          sse_loop(conn, session_id, 0)
        after
          EMCP.SessionStore.unregister_sse(session_id)
        end
      end)
    else
      json_error(conn, 406, "Accept header must include text/event-stream")
    end
  end

  defp sse_loop(conn, session_id, event_id) do
    receive do
      {:sse_message, data} ->
        case chunk(conn, EMCP.SSEEvent.encode(data, event_id)) do
          {:ok, conn} -> sse_loop(conn, session_id, event_id + 1)
          {:error, _} -> conn
        end

      :close_sse ->
        conn
    after
      keepalive_interval() ->
        case chunk(conn, EMCP.SSEEvent.keepalive()) do
          {:ok, conn} -> sse_loop(conn, session_id, event_id)
          {:error, _} -> conn
        end
    end
  end

  # POST — JSON-RPC requests and notifications

  defp handle_post(conn) do
    case read_request(conn) do
      {:ok, request, conn} ->
        if initialize?(request) do
          initialize_session(conn, request)
        else
          with_session(conn, fn session_id -> dispatch(conn, request, session_id) end)
        end

      {:error, message} ->
        json_error(conn, 400, message)
    end
  end

  defp initialize_session(conn, request) do
    session_id = generate_session_id()
    EMCP.SessionStore.store(session_id)

    conn
    |> put_resp_header("mcp-session-id", session_id)
    |> json_response(200, handle_message(request))
  end

  defp dispatch(conn, request, session_id) do
    if notification?(request) do
      send_resp(conn, 202, "")
    else
      response = handle_message(request)

      case EMCP.SessionStore.get_sse_pid(session_id) do
        pid when is_pid(pid) ->
          send(pid, {:sse_message, JSON.encode!(response)})
          json_response(conn, 202, %{})

        nil ->
          json_response(conn, 200, response)
      end
    end
  end

  # DELETE — session termination

  defp handle_delete(conn) do
    with_session(conn, fn session_id ->
      case EMCP.SessionStore.get_sse_pid(session_id) do
        pid when is_pid(pid) -> send(pid, :close_sse)
        nil -> :ok
      end

      EMCP.SessionStore.delete(session_id)
      json_response(conn, 200, %{"success" => true})
    end)
  end

  # Session helpers

  defp with_session(conn, fun) do
    with {:ok, session_id} <- require_session_id(conn),
         :ok <- validate_session(session_id) do
      fun.(session_id)
    else
      {:error, status, message} -> json_error(conn, status, message)
    end
  end

  defp require_session_id(conn) do
    case get_req_header(conn, "mcp-session-id") do
      [session_id] -> {:ok, session_id}
      _ -> {:error, 400, "Missing session ID"}
    end
  end

  defp validate_session(session_id) do
    case EMCP.SessionStore.lookup(session_id) do
      nil ->
        {:error, 404, "Session not found"}

      {last_active, _sse_pid} ->
        session_expired? = System.monotonic_time(:millisecond) - last_active > session_ttl()

        if session_expired? do
          EMCP.SessionStore.delete(session_id)
          {:error, 404, "Session not found"}
        else
          EMCP.SessionStore.touch(session_id)
          :ok
        end
    end
  end

  defp generate_session_id do
    Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  end

  # Request helpers

  defp read_request(%{body_params: %Plug.Conn.Unfetched{}} = conn) do
    with {:ok, body, conn} <- read_body(conn),
         {:ok, request} <- decode_json(body) do
      {:ok, request, conn}
    end
  end

  defp read_request(%{body_params: params} = conn) when is_map(params) and params != %{} do
    {:ok, params, conn}
  end

  defp read_request(conn) do
    with {:ok, body, conn} <- read_body(conn),
         {:ok, request} <- decode_json(body) do
      {:ok, request, conn}
    end
  end

  defp initialize?(request), do: request["method"] == "initialize"

  defp notification?(request),
    do: Map.has_key?(request, "method") and not Map.has_key?(request, "id")

  defp handle_message(request) do
    EMCP.Server.new() |> EMCP.Server.handle_message(request)
  end

  defp accepts_event_stream?(conn) do
    conn
    |> get_req_header("accept")
    |> List.first("")
    |> String.contains?("text/event-stream")
  end

  # Response helpers

  defp decode_json(body) do
    case JSON.decode(body) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, _} -> {:error, "Invalid JSON"}
    end
  end

  defp json_response(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, JSON.encode!(body))
  end

  defp json_error(conn, status, message) do
    json_response(conn, status, %{"error" => message})
  end

  # Config

  defp session_ttl do
    Application.get_env(:emcp, :session_ttl, @default_session_ttl)
  end

  defp keepalive_interval do
    Application.get_env(:emcp, :keepalive_interval, @default_keepalive_interval)
  end
end
