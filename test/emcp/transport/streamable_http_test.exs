defmodule EMCP.Transport.StreamableHTTPTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  defp call(conn) do
    EMCP.Transport.StreamableHTTP.call(conn, EMCP.Transport.StreamableHTTP.init([]))
  end

  defp post_json(path, body, headers \\ []) do
    conn =
      conn(:post, path, JSON.encode!(body))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json, text/event-stream")

    Enum.reduce(headers, conn, fn {key, value}, conn ->
      put_req_header(conn, to_string(key), value)
    end)
  end

  defp init_session do
    conn =
      post_json("/mcp", %{jsonrpc: "2.0", method: "initialize", id: "init"})
      |> call()

    session_id = get_resp_header(conn, "mcp-session-id") |> List.first()
    {conn, session_id}
  end

  describe "POST initialize" do
    test "returns protocol version and session ID" do
      {conn, session_id} = init_session()

      assert conn.status == 200
      assert session_id != nil

      body = JSON.decode!(conn.resp_body)
      assert body["jsonrpc"] == "2.0"
      assert body["id"] == "init"
      assert body["result"]["protocolVersion"]
      assert body["result"]["serverInfo"]
    end
  end

  describe "POST requests" do
    test "handles ping with session ID" do
      {_init_conn, session_id} = init_session()

      conn =
        post_json("/mcp", %{jsonrpc: "2.0", method: "ping", id: "1"},
          "mcp-session-id": session_id
        )
        |> call()

      assert conn.status == 200
      body = JSON.decode!(conn.resp_body)
      assert body["id"] == "1"
    end

    test "returns 400 for missing session ID on non-initialize request" do
      conn =
        post_json("/mcp", %{jsonrpc: "2.0", method: "ping", id: "1"})
        |> call()

      assert conn.status == 400
      body = JSON.decode!(conn.resp_body)
      assert body["error"] == "Missing session ID"
    end

    test "returns 404 for invalid session ID" do
      conn =
        post_json("/mcp", %{jsonrpc: "2.0", method: "ping", id: "1"}, "mcp-session-id": "bogus")
        |> call()

      assert conn.status == 404
      body = JSON.decode!(conn.resp_body)
      assert body["error"] == "Session not found"
    end

    test "returns 400 for invalid JSON" do
      conn =
        conn(:post, "/mcp", "not json")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json, text/event-stream")
        |> call()

      assert conn.status == 400
      body = JSON.decode!(conn.resp_body)
      assert body["error"] == "Invalid JSON"
    end

    test "handles notifications with 202" do
      {_init_conn, session_id} = init_session()

      conn =
        post_json("/mcp", %{jsonrpc: "2.0", method: "notifications/initialized"},
          "mcp-session-id": session_id
        )
        |> call()

      assert conn.status == 202
    end

    test "calls a tool" do
      {_init_conn, session_id} = init_session()

      conn =
        post_json(
          "/mcp",
          %{
            jsonrpc: "2.0",
            method: "tools/call",
            id: "2",
            params: %{name: "echo", arguments: %{message: "hello"}}
          },
          "mcp-session-id": session_id
        )
        |> call()

      assert conn.status == 200
      body = JSON.decode!(conn.resp_body)
      assert body["id"] == "2"
      assert %{"content" => [%{"text" => "hello"}]} = body["result"]
    end
  end

  describe "DELETE" do
    test "deletes a session" do
      {_init_conn, session_id} = init_session()

      conn =
        conn(:delete, "/mcp")
        |> put_req_header("mcp-session-id", session_id)
        |> call()

      assert conn.status == 200
      body = JSON.decode!(conn.resp_body)
      assert body["success"] == true

      # Session is gone now
      conn =
        post_json("/mcp", %{jsonrpc: "2.0", method: "ping", id: "1"},
          "mcp-session-id": session_id
        )
        |> call()

      assert conn.status == 404
    end

    test "returns 400 for missing session ID" do
      conn = conn(:delete, "/mcp") |> call()

      assert conn.status == 400
      body = JSON.decode!(conn.resp_body)
      assert body["error"] == "Missing session ID"
    end
  end

  describe "session expiry" do
    test "returns 404 for expired session" do
      {_init_conn, session_id} = init_session()

      # Backdate the session timestamp to make it expired
      table = EMCP.Transport.StreamableHTTP.Sessions
      :ets.update_element(table, session_id, {2, System.monotonic_time(:millisecond) - 700_000})

      conn =
        post_json("/mcp", %{jsonrpc: "2.0", method: "ping", id: "1"},
          "mcp-session-id": session_id
        )
        |> call()

      assert conn.status == 404
      body = JSON.decode!(conn.resp_body)
      assert body["error"] == "Session not found"
    end
  end

  describe "unsupported methods" do
    test "returns 405 for PUT" do
      conn = conn(:put, "/mcp") |> call()

      assert conn.status == 405
      body = JSON.decode!(conn.resp_body)
      assert body["error"] == "Method not allowed"
    end
  end
end
