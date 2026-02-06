defmodule EMCP.Transport.StreamableHTTP do
  @moduledoc "MCP transport that communicates over HTTP using JSON-RPC."

  @behaviour Plug

  import Plug.Conn

  @default_session_ttl to_timeout(minute: 10)

  # Plug callbacks

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{method: "POST"} = conn, _opts), do: handle_post(conn)
  def call(%Plug.Conn{method: "DELETE"} = conn, _opts), do: handle_delete(conn)
  def call(conn, _opts), do: json_error(conn, 405, "Method not allowed")

  # POST

  defp handle_post(conn) do
    with {:ok, body, conn} <- read_body(conn),
         {:ok, request} <- decode_json(body) do
      if initialize?(request) do
        initialize_session(conn, request)
      else
        with_session(conn, fn -> dispatch(conn, request) end)
      end
    else
      {:error, message} -> json_error(conn, 400, message)
    end
  end

  defp initialize_session(conn, request) do
    session_id = generate_session_id()
    store_session(session_id)

    conn
    |> put_resp_header("mcp-session-id", session_id)
    |> json_response(200, handle_message(request))
  end

  defp dispatch(conn, request) do
    if notification?(request) do
      send_resp(conn, 202, "")
    else
      json_response(conn, 200, handle_message(request))
    end
  end

  # DELETE

  defp handle_delete(conn) do
    with_session(conn, fn session_id ->
      delete_session(session_id)
      json_response(conn, 200, %{"success" => true})
    end)
  end

  # Session validation

  defp with_session(conn, fun) do
    with {:ok, session_id} <- require_session_id(conn),
         :ok <- validate_session(session_id) do
      case Function.info(fun, :arity) do
        {:arity, 0} -> fun.()
        {:arity, 1} -> fun.(session_id)
      end
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
    case lookup_session(session_id) do
      nil ->
        {:error, 404, "Session not found"}

      last_active ->
        session_expired? = System.monotonic_time(:millisecond) - last_active > session_ttl()

        if session_expired? do
          delete_session(session_id)
          {:error, 404, "Session not found"}
        else
          touch_session(session_id)
          :ok
        end
    end
  end

  # Helpers

  defp initialize?(request), do: request["method"] == "initialize"

  defp notification?(request),
    do: Map.has_key?(request, "method") and not Map.has_key?(request, "id")

  defp handle_message(request) do
    EMCP.Server.new() |> EMCP.Server.handle_message(request)
  end

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

  # Session storage (ETS)

  @table __MODULE__.Sessions

  defp ensure_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table])
    end
  end

  defp generate_session_id do
    Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  end

  defp store_session(session_id) do
    ensure_table()
    :ets.insert(@table, {session_id, System.monotonic_time(:millisecond)})
  end

  defp lookup_session(session_id) do
    ensure_table()

    case :ets.lookup(@table, session_id) do
      [{^session_id, last_active}] -> last_active
      [] -> nil
    end
  end

  defp touch_session(session_id) do
    :ets.update_element(@table, session_id, {2, System.monotonic_time(:millisecond)})
  end

  defp delete_session(session_id) do
    ensure_table()
    :ets.delete(@table, session_id)
  end

  defp session_ttl do
    Application.get_env(:emcp, :session_ttl, @default_session_ttl)
  end
end
