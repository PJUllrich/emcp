defmodule EMCP.Transport.StreamableHTTPE2ETest do
  use ExUnit.Case

  setup_all do
    port = Enum.random(49152..65535)

    start_supervised!(
      {Bandit, plug: EMCP.Transport.StreamableHTTP, port: port, startup_log: false}
    )

    # Short keepalive so SSE loops exit quickly on shutdown
    Application.put_env(:emcp, :keepalive_interval, 100)
    on_exit(fn -> Application.delete_env(:emcp, :keepalive_interval) end)

    {:ok, port: port}
  end

  defp inspect_http(port, args) do
    MCP.Inspector.run(["--transport", "http", "http://localhost:#{port}/mcp" | args])
  end

  # Raw HTTP/SSE helpers for notify/broadcast tests

  defp http_request(port, method, path, headers, body) do
    {:ok, conn} = :gen_tcp.connect(~c"localhost", port, [:binary, active: false])
    body_str = body || ""

    header_lines =
      [
        "#{method} #{path} HTTP/1.1",
        "Host: localhost:#{port}",
        "Content-Length: #{byte_size(body_str)}"
        | Enum.map(headers, fn {k, v} -> "#{k}: #{v}" end)
      ]
      |> Enum.join("\r\n")

    :ok = :gen_tcp.send(conn, header_lines <> "\r\n\r\n" <> body_str)
    {:ok, response} = recv_until_complete(conn, "")
    :gen_tcp.close(conn)
    parse_http_response(response)
  end

  defp recv_until_complete(conn, acc) do
    case :gen_tcp.recv(conn, 0, 5000) do
      {:ok, data} ->
        acc = acc <> data

        if response_complete?(acc),
          do: {:ok, acc},
          else: recv_until_complete(conn, acc)

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
              [_, len] -> byte_size(body) >= String.to_integer(len)
              nil -> true
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
      status_line |> String.split(" ", parts: 3) |> Enum.at(1) |> String.to_integer()

    headers =
      Enum.map(header_lines, fn line ->
        [key, value] = String.split(line, ": ", parts: 2)
        {String.downcase(key), value}
      end)

    body =
      if List.keyfind(headers, "transfer-encoding", 0) == {"transfer-encoding", "chunked"},
        do: decode_chunked(body),
        else: body

    {status, headers, body}
  end

  defp decode_chunked(body), do: decode_chunks(body, "")
  defp decode_chunks("0\r\n" <> _, acc), do: acc

  defp decode_chunks(data, acc) do
    case String.split(data, "\r\n", parts: 2) do
      [hex_size, rest] ->
        {size, _} = Integer.parse(hex_size, 16)

        if size == 0,
          do: acc,
          else:
            (
              <<chunk::binary-size(size), "\r\n", rest::binary>> = rest
              decode_chunks(rest, acc <> chunk)
            )

      _ ->
        acc
    end
  end

  defp init_session(port) do
    body = JSON.encode!(%{jsonrpc: "2.0", method: "initialize", id: "init", params: %{}})

    {200, headers, _} =
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
      {"mcp-session-id", v} -> v
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
    _headers = recv_sse_headers(socket, "")
    socket
  end

  defp recv_sse_headers(socket, acc) do
    receive do
      {:tcp, ^socket, data} ->
        acc = acc <> data
        if String.contains?(acc, "\r\n\r\n"), do: acc, else: recv_sse_headers(socket, acc)
    after
      5000 -> raise "Timed out waiting for SSE headers"
    end
  end

  defp receive_sse_event(socket, timeout \\ 2000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    receive_sse_event_loop(socket, deadline)
  end

  defp receive_sse_event_loop(socket, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:tcp, ^socket, data} ->
        if String.contains?(data, "event:"),
          do: data,
          else: receive_sse_event_loop(socket, deadline)

      {:tcp_closed, ^socket} ->
        ""
    after
      remaining -> ""
    end
  end

  defp decode_sse_data(raw) do
    raw
    |> String.split("\n")
    |> Enum.find(&String.starts_with?(&1, "data: "))
    |> String.trim_leading("data: ")
    |> JSON.decode!()
  end

  defp close_sse(socket) do
    :gen_tcp.close(socket)
    Process.sleep(200)
  end

  describe "tools/list" do
    test "returns registered tools", %{port: port} do
      {output, 0} = inspect_http(port, ["--method", "tools/list"])
      result = JSON.decode!(output)

      assert %{"tools" => tools} = result
      assert length(tools) > 0

      names = Enum.map(tools, & &1["name"])
      assert "echo" in names
      assert "all_types" in names
    end
  end

  describe "tools/call" do
    test "calls echo tool", %{port: port} do
      {output, 0} =
        inspect_http(port, [
          "--method",
          "tools/call",
          "--tool-name",
          "echo",
          "--tool-arg",
          "message=hello from http"
        ])

      result = JSON.decode!(output)
      assert %{"content" => [%{"type" => "text", "text" => "hello from http"}]} = result
    end

    test "calls all_types tool", %{port: port} do
      {output, 0} =
        inspect_http(port, [
          "--method",
          "tools/call",
          "--tool-name",
          "all_types",
          "--tool-arg",
          "name=Alice",
          "--tool-arg",
          "age=30",
          "--tool-arg",
          "score=9.5",
          "--tool-arg",
          "active=true",
          "--tool-arg",
          ~s(tags=["elixir"]),
          "--tool-arg",
          ~s(metadata={"key":"value"})
        ])

      result = JSON.decode!(output)
      assert %{"content" => [%{"text" => text}]} = result
      args = JSON.decode!(text)
      assert args["name"] == "Alice"
      assert args["age"] == 30
      assert args["score"] == 9.5
      assert args["active"] == true
      assert args["tags"] == ["elixir"]
      assert args["metadata"] == %{"key" => "value"}
    end

    test "returns error for invalid arguments", %{port: port} do
      {output, 1} =
        inspect_http(port, [
          "--method",
          "tools/call",
          "--tool-name",
          "echo",
          "--tool-arg",
          "message=123"
        ])

      assert output =~ "message is invalid"
      assert output =~ "Expected type string but got integer"
    end
  end

  describe "prompts/list" do
    test "returns registered prompts", %{port: port} do
      {output, 0} = inspect_http(port, ["--method", "prompts/list"])
      result = JSON.decode!(output)

      assert %{"prompts" => prompts} = result
      assert length(prompts) == 2

      names = Enum.map(prompts, & &1["name"])
      assert "simple_greeting" in names
      assert "code_review" in names
    end
  end

  describe "prompts/get" do
    test "gets a prompt without arguments", %{port: port} do
      {output, 0} =
        inspect_http(port, [
          "--method",
          "prompts/get",
          "--prompt-name",
          "simple_greeting"
        ])

      result = JSON.decode!(output)
      assert %{"messages" => [%{"role" => "user", "content" => %{"type" => "text"}}]} = result
    end

    test "gets a prompt with arguments", %{port: port} do
      {output, 0} =
        inspect_http(port, [
          "--method",
          "prompts/get",
          "--prompt-name",
          "code_review",
          "--prompt-args",
          "code=def foo, do: :bar",
          "--prompt-args",
          "focus=security"
        ])

      result = JSON.decode!(output)
      assert %{"description" => "Code review prompt", "messages" => messages} = result
      assert length(messages) == 2

      [user_msg, assistant_msg] = messages
      assert user_msg["role"] == "user"
      assert user_msg["content"]["text"] =~ "focusing on security"
      assert user_msg["content"]["text"] =~ "def foo, do: :bar"
      assert assistant_msg["role"] == "assistant"
    end

    test "returns error for missing required argument", %{port: port} do
      {output, 1} =
        inspect_http(port, [
          "--method",
          "prompts/get",
          "--prompt-name",
          "code_review"
        ])

      assert output =~ "Missing required argument: code"
    end
  end

  describe "resources/list" do
    test "returns registered resources", %{port: port} do
      {output, 0} = inspect_http(port, ["--method", "resources/list"])
      result = JSON.decode!(output)

      assert %{"resources" => resources} = result
      assert length(resources) == 1

      [resource] = resources
      assert resource["uri"] == "file:///test/hello.txt"
      assert resource["name"] == "test_file"
      assert resource["description"] == "A test text file resource"
      assert resource["mimeType"] == "text/plain"
    end
  end

  describe "resources/read" do
    test "reads a resource by URI", %{port: port} do
      {output, 0} =
        inspect_http(port, [
          "--method",
          "resources/read",
          "--uri",
          "file:///test/hello.txt"
        ])

      result = JSON.decode!(output)

      assert %{"contents" => [content]} = result
      assert content["uri"] == "file:///test/hello.txt"
      assert content["mimeType"] == "text/plain"
      assert content["text"] == "Hello from resource!"
    end

    test "reads a resource via template match", %{port: port} do
      {output, 0} =
        inspect_http(port, [
          "--method",
          "resources/read",
          "--uri",
          "file:///users/42/profile"
        ])

      result = JSON.decode!(output)

      assert %{"contents" => [content]} = result
      assert content["uri"] == "file:///users/42/profile"
      assert content["mimeType"] == "application/json"

      data = JSON.decode!(content["text"])
      assert data["user_id"] == "42"
      assert data["name"] == "User 42"
    end

    test "returns error for unknown resource URI", %{port: port} do
      {output, 1} =
        inspect_http(port, [
          "--method",
          "resources/read",
          "--uri",
          "file:///nonexistent"
        ])

      assert output =~ "Resource not found"
    end
  end

  describe "resources/templates/list" do
    test "returns registered resource templates", %{port: port} do
      {output, 0} = inspect_http(port, ["--method", "resources/templates/list"])
      result = JSON.decode!(output)

      assert %{"resourceTemplates" => templates} = result
      assert length(templates) == 1

      [template] = templates
      assert template["uriTemplate"] == "file:///users/{user_id}/profile"
      assert template["name"] == "user_profile"
      assert template["description"] == "A user profile resource template"
      assert template["mimeType"] == "application/json"
    end
  end

  describe "notify/2" do
    test "delivers a notification to a session with active SSE", %{port: port} do
      session_id = init_session(port)
      socket = open_sse(port, session_id)
      Process.sleep(100)

      notification = %{
        "jsonrpc" => "2.0",
        "method" => "notifications/resources/list_changed"
      }

      assert :ok = EMCP.Transport.StreamableHTTP.notify(session_id, notification)

      data = receive_sse_event(socket)
      message = decode_sse_data(data)
      assert message["jsonrpc"] == "2.0"
      assert message["method"] == "notifications/resources/list_changed"

      close_sse(socket)
    end

    test "returns error when session has no SSE connection", %{port: port} do
      session_id = init_session(port)

      assert {:error, :no_sse_connection} =
               EMCP.Transport.StreamableHTTP.notify(session_id, %{"test" => true})
    end
  end

  describe "broadcast/1" do
    test "delivers a notification to all sessions with active SSE", %{port: port} do
      session_id1 = init_session(port)
      session_id2 = init_session(port)

      socket1 = open_sse(port, session_id1)
      socket2 = open_sse(port, session_id2)
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
