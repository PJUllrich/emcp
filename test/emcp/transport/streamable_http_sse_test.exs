defmodule EMCP.Transport.StreamableHTTPSSETest do
  use ExUnit.Case

  @default_test_keepalive 100

  setup_all do
    port = Enum.random(49152..65535)

    start_supervised!(
      {Bandit, plug: EMCP.Transport.StreamableHTTP, port: port, startup_log: false}
    )

    # Use a short keepalive so server-side SSE loops detect closed
    # connections quickly and don't block test teardown
    Application.put_env(:emcp, :keepalive_interval, @default_test_keepalive)

    on_exit(fn ->
      Application.delete_env(:emcp, :keepalive_interval)
    end)

    {:ok, port: port}
  end

  # Raw HTTP helpers using :gen_tcp

  defp http_request(port, method, path, headers, body \\ nil) do
    {:ok, conn} = :gen_tcp.connect(~c"localhost", port, [:binary, active: false])

    body_str = if body, do: body, else: ""

    header_lines =
      [
        "#{method} #{path} HTTP/1.1",
        "Host: localhost:#{port}",
        "Content-Length: #{byte_size(body_str)}"
        | Enum.map(headers, fn {k, v} -> "#{k}: #{v}" end)
      ]
      |> Enum.join("\r\n")

    request = header_lines <> "\r\n\r\n" <> body_str
    :ok = :gen_tcp.send(conn, request)

    {:ok, response} = recv_full_response(conn, "")
    :gen_tcp.close(conn)

    parse_http_response(response)
  end

  defp recv_full_response(conn, acc) do
    case :gen_tcp.recv(conn, 0, 5000) do
      {:ok, data} ->
        acc = acc <> data

        if response_complete?(acc) do
          {:ok, acc}
        else
          recv_full_response(conn, acc)
        end

      {:error, :closed} ->
        {:ok, acc}
    end
  end

  defp response_complete?(data) do
    case String.split(data, "\r\n\r\n", parts: 2) do
      [headers, body] ->
        cond do
          String.contains?(headers, "transfer-encoding: chunked") ->
            String.contains?(body, "0\r\n")

          true ->
            case Regex.run(~r/content-length: (\d+)/i, headers) do
              [_, len_str] ->
                {len, _} = Integer.parse(len_str)
                byte_size(body) >= len

              nil ->
                true
            end
        end

      _ ->
        false
    end
  end

  defp parse_http_response(response) do
    [header_section, body] = String.split(response, "\r\n\r\n", parts: 2)
    [status_line | header_lines] = String.split(header_section, "\r\n")

    status =
      status_line
      |> String.split(" ", parts: 3)
      |> Enum.at(1)
      |> String.to_integer()

    headers =
      Enum.map(header_lines, fn line ->
        [key, value] = String.split(line, ": ", parts: 2)
        {String.downcase(key), value}
      end)

    body =
      if List.keyfind(headers, "transfer-encoding", 0) == {"transfer-encoding", "chunked"} do
        decode_chunked(body)
      else
        body
      end

    {status, headers, body}
  end

  defp decode_chunked(body), do: decode_chunks(body, "")

  defp decode_chunks("0\r\n" <> _, acc), do: acc

  defp decode_chunks(data, acc) do
    case String.split(data, "\r\n", parts: 2) do
      [hex_size, rest] ->
        {size, _} = Integer.parse(hex_size, 16)

        if size == 0 do
          acc
        else
          <<chunk::binary-size(size), "\r\n", rest::binary>> = rest
          decode_chunks(rest, acc <> chunk)
        end

      _ ->
        acc
    end
  end

  defp init_session(port) do
    body = JSON.encode!(%{jsonrpc: "2.0", method: "initialize", id: "init", params: %{}})

    {200, headers, _resp_body} =
      http_request(
        port,
        "POST",
        "/mcp",
        [
          {"content-type", "application/json"},
          {"accept", "application/json, text/event-stream"}
        ],
        body
      )

    headers
    |> Enum.find_value(fn
      {"mcp-session-id", value} -> value
      _ -> nil
    end)
  end

  defp open_sse(port, session_id) do
    {:ok, socket} = :gen_tcp.connect(~c"localhost", port, [:binary, active: true])

    request =
      "GET /mcp HTTP/1.1\r\n" <>
        "Host: localhost:#{port}\r\n" <>
        "Accept: text/event-stream\r\n" <>
        "mcp-session-id: #{session_id}\r\n" <>
        "\r\n"

    :ok = :gen_tcp.send(socket, request)

    headers = recv_headers(socket, "")
    {socket, headers}
  end

  defp recv_headers(socket, acc) do
    receive do
      {:tcp, ^socket, data} ->
        acc = acc <> data

        if String.contains?(acc, "\r\n\r\n") do
          acc
        else
          recv_headers(socket, acc)
        end
    after
      5000 -> raise "Timed out waiting for SSE headers"
    end
  end

  defp close_sse(socket) do
    :gen_tcp.close(socket)
    # Wait long enough for the server-side SSE loop to detect the closed
    # connection on its next keepalive write attempt
    Process.sleep(200)
  end

  defp post_request(port, session_id, body) do
    encoded = JSON.encode!(body)

    http_request(
      port,
      "POST",
      "/mcp",
      [
        {"content-type", "application/json"},
        {"accept", "application/json, text/event-stream"},
        {"mcp-session-id", session_id}
      ],
      encoded
    )
  end

  # Extracts and decodes the JSON from an SSE data line in raw TCP data.
  defp decode_sse_data(raw) do
    raw
    |> String.split("\n")
    |> Enum.find(&String.starts_with?(&1, "data: "))
    |> String.trim_leading("data: ")
    |> JSON.decode!()
  end

  # Receives a single SSE event from the socket.
  # Drains any keepalive chunks and returns the first chunk containing "event:".
  defp receive_sse_event(socket, timeout \\ 2000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    receive_sse_event_loop(socket, deadline)
  end

  defp receive_sse_event_loop(socket, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:tcp, ^socket, data} ->
        if String.contains?(data, "event:") do
          data
        else
          receive_sse_event_loop(socket, deadline)
        end

      {:tcp_closed, ^socket} ->
        ""
    after
      remaining -> ""
    end
  end

  describe "SSE streaming" do
    test "GET establishes SSE connection with correct headers", %{port: port} do
      session_id = init_session(port)
      {socket, headers} = open_sse(port, session_id)

      assert headers =~ "HTTP/1.1 200"
      assert headers =~ "content-type: text/event-stream"
      assert headers =~ "cache-control: no-cache"

      close_sse(socket)
    end

    test "POST routes response through SSE stream when connected", %{port: port} do
      session_id = init_session(port)
      {socket, _headers} = open_sse(port, session_id)
      Process.sleep(100)

      {status, _headers, _resp_body} =
        post_request(port, session_id, %{jsonrpc: "2.0", method: "ping", id: "1"})

      assert status == 202

      data = receive_sse_event(socket)
      assert data =~ "event: message"

      response = decode_sse_data(data)
      assert response["id"] == "1"
      assert response["result"] == %{}

      close_sse(socket)
    end

    test "POST returns inline JSON when no SSE connection", %{port: port} do
      session_id = init_session(port)

      {status, _headers, resp_body} =
        post_request(port, session_id, %{jsonrpc: "2.0", method: "ping", id: "1"})

      assert status == 200
      response = JSON.decode!(resp_body)
      assert response["id"] == "1"
      assert response["result"] == %{}
    end

    test "SSE receives keepalive pings", %{port: port} do
      session_id = init_session(port)
      {socket, _headers} = open_sse(port, session_id)

      # Keepalive interval is 100ms (set in setup_all)
      assert_receive {:tcp, ^socket, keepalive_data}, 1000
      assert keepalive_data =~ "keepalive"

      close_sse(socket)
    end

    test "DELETE closes SSE connection", %{port: port} do
      session_id = init_session(port)
      {socket, _headers} = open_sse(port, session_id)
      Process.sleep(100)

      {200, _, _} =
        http_request(port, "DELETE", "/mcp", [{"mcp-session-id", session_id}])

      receive do
        {:tcp, ^socket, "0\r\n\r\n"} -> :ok
        {:tcp_closed, ^socket} -> :ok
      after
        2000 ->
          close_sse(socket)
          flunk("SSE connection did not close after DELETE")
      end
    end

    test "client disconnect cleans up SSE pid on next keepalive", %{port: port} do
      session_id = init_session(port)
      {socket, _headers} = open_sse(port, session_id)
      Process.sleep(100)

      assert EMCP.SessionStore.get_sse_pid(session_id) != nil

      close_sse(socket)
      Process.sleep(300)

      assert EMCP.SessionStore.get_sse_pid(session_id) == nil
      assert EMCP.SessionStore.lookup(session_id) != nil
    end

    test "tools/call response is streamed via SSE", %{port: port} do
      session_id = init_session(port)
      {socket, _headers} = open_sse(port, session_id)
      Process.sleep(100)

      {status, _headers, _resp_body} =
        post_request(port, session_id, %{
          jsonrpc: "2.0",
          method: "tools/call",
          id: "tool-1",
          params: %{name: "echo", arguments: %{message: "hello via sse"}}
        })

      assert status == 202

      data = receive_sse_event(socket)

      response = decode_sse_data(data)
      assert response["id"] == "tool-1"
      assert %{"content" => [%{"text" => "hello via sse"}]} = response["result"]

      close_sse(socket)
    end
  end

  describe "notify/2" do
    test "sends notification to session with active SSE", %{port: port} do
      session_id = init_session(port)
      {socket, _headers} = open_sse(port, session_id)
      Process.sleep(100)

      notification = %{
        "jsonrpc" => "2.0",
        "method" => "notifications/tools/list_changed"
      }

      assert :ok = EMCP.Transport.StreamableHTTP.notify(session_id, notification)

      data = receive_sse_event(socket)

      message = decode_sse_data(data)
      assert message["method"] == "notifications/tools/list_changed"

      close_sse(socket)
    end

    test "returns error when no SSE connection", %{port: port} do
      session_id = init_session(port)

      assert {:error, :no_sse_connection} =
               EMCP.Transport.StreamableHTTP.notify(session_id, %{"test" => true})
    end
  end

  describe "broadcast/1" do
    test "sends to all sessions with active SSE", %{port: port} do
      session_id1 = init_session(port)
      session_id2 = init_session(port)

      {socket1, _} = open_sse(port, session_id1)
      {socket2, _} = open_sse(port, session_id2)
      Process.sleep(100)

      notification = %{
        "jsonrpc" => "2.0",
        "method" => "notifications/tools/list_changed"
      }

      EMCP.Transport.StreamableHTTP.broadcast(notification)

      data1 = receive_sse_event(socket1)
      assert data1 =~ "notifications/tools/list_changed"

      data2 = receive_sse_event(socket2)
      assert data2 =~ "notifications/tools/list_changed"

      close_sse(socket1)
      close_sse(socket2)
    end
  end
end
