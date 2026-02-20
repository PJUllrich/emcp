defmodule EMCP.Transport.StreamableHTTPTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  defp call(conn) do
    EMCP.Transport.StreamableHTTP.call(
      conn,
      EMCP.Transport.StreamableHTTP.init(server: EMCP.TestServer)
    )
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

    test "re-creates unknown session ID transparently" do
      conn =
        post_json("/mcp", %{jsonrpc: "2.0", method: "ping", id: "1"}, "mcp-session-id": "bogus")
        |> call()

      assert conn.status == 200
      body = JSON.decode!(conn.resp_body)
      assert body["result"] == %{}
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

  describe "pre-parsed body (Phoenix Plug.Parsers)" do
    test "handles initialize when body is already parsed" do
      params = %{"jsonrpc" => "2.0", "method" => "initialize", "id" => "init"}

      conn =
        conn(:post, "/mcp", "")
        |> put_req_header("content-type", "application/json")
        |> Map.put(:body_params, params)
        |> call()

      assert conn.status == 200
      session_id = get_resp_header(conn, "mcp-session-id") |> List.first()
      assert session_id != nil

      body = JSON.decode!(conn.resp_body)
      assert body["result"]["protocolVersion"]
    end

    test "handles requests when body is already parsed" do
      # Initialize a session first (using raw body path)
      {_init_conn, session_id} = init_session()

      params = %{"jsonrpc" => "2.0", "method" => "ping", "id" => "1"}

      conn =
        conn(:post, "/mcp", "")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("mcp-session-id", session_id)
        |> Map.put(:body_params, params)
        |> call()

      assert conn.status == 200
      body = JSON.decode!(conn.resp_body)
      assert body["id"] == "1"
      assert body["result"] == %{}
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

      # Session is re-created transparently
      conn =
        post_json("/mcp", %{jsonrpc: "2.0", method: "ping", id: "1"},
          "mcp-session-id": session_id
        )
        |> call()

      assert conn.status == 200
    end

    test "returns 400 for missing session ID" do
      conn = conn(:delete, "/mcp") |> call()

      assert conn.status == 400
      body = JSON.decode!(conn.resp_body)
      assert body["error"] == "Missing session ID"
    end
  end

  describe "session expiry" do
    test "re-creates expired session transparently" do
      {_init_conn, session_id} = init_session()

      # Backdate the session timestamp to make it expired
      :ets.update_element(
        EMCP.SessionStore.ETS,
        session_id,
        {2, System.monotonic_time(:millisecond) - 700_000}
      )

      conn =
        post_json("/mcp", %{jsonrpc: "2.0", method: "ping", id: "1"},
          "mcp-session-id": session_id
        )
        |> call()

      assert conn.status == 200
      body = JSON.decode!(conn.resp_body)
      assert body["result"] == %{}
    end
  end

  describe "GET (SSE validation)" do
    test "returns 406 without Accept: text/event-stream" do
      conn =
        conn(:get, "/mcp")
        |> put_req_header("accept", "application/json")
        |> put_req_header("mcp-session-id", "some-id")
        |> call()

      assert conn.status == 406
      body = JSON.decode!(conn.resp_body)
      assert body["error"] == "Accept header must include text/event-stream"
    end

    test "returns 400 without session ID" do
      conn =
        conn(:get, "/mcp")
        |> put_req_header("accept", "text/event-stream")
        |> call()

      assert conn.status == 400
      body = JSON.decode!(conn.resp_body)
      assert body["error"] == "Missing session ID"
    end

    test "re-creates unknown session and registers SSE pid" do
      test_pid = self()

      pid =
        spawn(fn ->
          conn =
            conn(:get, "/mcp")
            |> put_req_header("accept", "text/event-stream")
            |> put_req_header("mcp-session-id", "bogus-sse")

          send(test_pid, :sse_started)
          call(conn)
        end)

      assert_receive :sse_started, 1000
      Process.sleep(50)

      assert EMCP.SessionStore.ETS.get_pid("bogus-sse") == pid

      send(pid, :close_sse)
      Process.sleep(50)

      assert EMCP.SessionStore.ETS.get_pid("bogus-sse") == nil
    end

    test "registers SSE pid for valid session" do
      {_conn, session_id} = init_session()

      test_pid = self()

      pid =
        spawn(fn ->
          conn =
            conn(:get, "/mcp")
            |> put_req_header("accept", "text/event-stream")
            |> put_req_header("mcp-session-id", session_id)

          send(test_pid, :sse_started)
          call(conn)
        end)

      assert_receive :sse_started, 1000
      Process.sleep(50)

      assert EMCP.SessionStore.ETS.get_pid(session_id) == pid

      send(pid, :close_sse)
      Process.sleep(50)

      assert EMCP.SessionStore.ETS.get_pid(session_id) == nil
    end
  end

  describe "recreate_missing_session: false (strict mode)" do
    defp call_strict(conn) do
      EMCP.Transport.StreamableHTTP.call(
        conn,
        EMCP.Transport.StreamableHTTP.init(server: EMCP.TestServer, recreate_missing_session: false)
      )
    end

    defp init_strict_session do
      conn =
        post_json("/mcp", %{jsonrpc: "2.0", method: "initialize", id: "init"})
        |> call_strict()

      session_id = get_resp_header(conn, "mcp-session-id") |> List.first()
      {conn, session_id}
    end

    test "returns 404 for unknown session ID" do
      conn =
        post_json("/mcp", %{jsonrpc: "2.0", method: "ping", id: "1"},
          "mcp-session-id": "nonexistent-strict-#{System.unique_integer([:positive])}"
        )
        |> call_strict()

      assert conn.status == 404
      body = JSON.decode!(conn.resp_body)
      assert body["error"] == "Session not found"
    end

    test "returns 404 for expired session" do
      {_init_conn, session_id} = init_strict_session()

      :ets.update_element(
        EMCP.SessionStore.ETS,
        session_id,
        {2, System.monotonic_time(:millisecond) - 700_000}
      )

      conn =
        post_json("/mcp", %{jsonrpc: "2.0", method: "ping", id: "1"},
          "mcp-session-id": session_id
        )
        |> call_strict()

      assert conn.status == 404
      body = JSON.decode!(conn.resp_body)
      assert body["error"] == "Session expired"
    end

    test "allows valid session" do
      {_init_conn, session_id} = init_strict_session()

      conn =
        post_json("/mcp", %{jsonrpc: "2.0", method: "ping", id: "1"},
          "mcp-session-id": session_id
        )
        |> call_strict()

      assert conn.status == 200
      body = JSON.decode!(conn.resp_body)
      assert body["result"] == %{}
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

  describe "Origin validation" do
    defp call_with_opts(conn, opts) do
      merged = Keyword.merge([server: EMCP.TestServer], opts)

      EMCP.Transport.StreamableHTTP.call(
        conn,
        EMCP.Transport.StreamableHTTP.init(merged)
      )
    end

    test "skips validation when validate_origin is absent" do
      conn =
        post_json("/mcp", %{jsonrpc: "2.0", method: "initialize", id: "init"})
        |> put_req_header("origin", "https://evil.com")
        |> call()

      assert conn.status == 200
    end

    test "allows requests without Origin header" do
      conn =
        post_json("/mcp", %{jsonrpc: "2.0", method: "initialize", id: "init"})
        |> call_with_opts(validate_origin: true, allowed_origins: ["https://myapp.example.com"])

      assert conn.status == 200
    end

    test "allows requests with a listed origin" do
      conn =
        post_json("/mcp", %{jsonrpc: "2.0", method: "initialize", id: "init"})
        |> put_req_header("origin", "https://myapp.example.com")
        |> call_with_opts(validate_origin: true, allowed_origins: ["https://myapp.example.com"])

      assert conn.status == 200
    end

    test "allows origin with port when base host is listed" do
      conn =
        post_json("/mcp", %{jsonrpc: "2.0", method: "initialize", id: "init"})
        |> put_req_header("origin", "https://myapp.example.com:4000")
        |> call_with_opts(validate_origin: true, allowed_origins: ["https://myapp.example.com"])

      assert conn.status == 200
    end

    test "rejects requests with an unlisted origin" do
      conn =
        post_json("/mcp", %{jsonrpc: "2.0", method: "initialize", id: "init"})
        |> put_req_header("origin", "https://evil.com")
        |> call_with_opts(validate_origin: true, allowed_origins: ["https://myapp.example.com"])

      assert conn.status == 403
      body = JSON.decode!(conn.resp_body)
      assert body["error"]["message"] == "Forbidden origin"
    end

    test "rejects all origins when allowed_origins is empty or absent" do
      conn =
        post_json("/mcp", %{jsonrpc: "2.0", method: "initialize", id: "init"})
        |> put_req_header("origin", "http://localhost")
        |> call_with_opts(validate_origin: true, allowed_origins: [])

      assert conn.status == 403

      conn =
        post_json("/mcp", %{jsonrpc: "2.0", method: "initialize", id: "init"})
        |> put_req_header("origin", "http://localhost")
        |> call_with_opts(validate_origin: true)

      assert conn.status == 403
    end

    test "validates origins correctly" do
      allowed = &EMCP.Transport.StreamableHTTP.origin_allowed?/2

      # Exact match
      assert allowed.("https://example.com", ["https://example.com"])

      # Subdomain match when listed
      assert allowed.("https://app.example.com", ["https://app.example.com"])

      # Subdomain does NOT match bare domain
      refute allowed.("https://app.example.com", ["https://example.com"])

      # Bare domain does NOT match subdomain
      refute allowed.("https://example.com", ["https://app.example.com"])

      # Port is ignored when base host is listed
      assert allowed.("https://example.com:4000", ["https://example.com"])
      assert allowed.("http://example.com:8080", ["http://example.com"])

      # Exact origin with port also matches
      assert allowed.("https://example.com:4000", ["https://example.com:4000"])

      # Scheme mismatch
      refute allowed.("http://example.com", ["https://example.com"])
      refute allowed.("https://example.com", ["http://example.com"])

      # Multiple allowed origins
      assert allowed.("https://a.com", ["https://b.com", "https://a.com"])
      refute allowed.("https://c.com", ["https://a.com", "https://b.com"])

      # Empty allowed list
      refute allowed.("https://example.com", [])

      # Malformed origins
      refute allowed.("not-a-url", ["https://example.com"])
      refute allowed.("", ["https://example.com"])

      # Deep subdomain
      assert allowed.("https://a.b.c.example.com", ["https://a.b.c.example.com"])
      refute allowed.("https://a.b.c.example.com", ["https://example.com"])

      # Bare domain in allowed list (no scheme) matches any scheme
      assert allowed.("https://example.com", ["example.com"])
      assert allowed.("http://example.com", ["example.com"])
      assert allowed.("https://example.com:4000", ["example.com"])

      # Bare domain must match exactly — no subdomain wildcard
      refute allowed.("https://app.example.com", ["example.com"])

      # Bare domain must not match suffix attacks
      refute allowed.("https://example.com.evil.com", ["example.com"])

      # Case-insensitive matching
      assert allowed.("https://EXAMPLE.COM", ["https://example.com"])
      assert allowed.("https://example.com", ["https://EXAMPLE.COM"])
      assert allowed.("https://Example.Com", ["example.com"])

      # Trailing dot (DNS root) is normalized
      assert allowed.("https://example.com.", ["https://example.com"])
      assert allowed.("https://example.com.", ["example.com"])

      # Null byte injection
      refute allowed.("https://example.com%00.evil.com", ["example.com"])

      # Path injection — path is not part of origin matching
      refute allowed.("https://evil.com/example.com", ["example.com"])

      # Whitespace padding
      refute allowed.(" https://example.com", ["https://example.com"])
      assert allowed.("https://example.com ", ["https://example.com"])

      # Fragment and query are ignored by URI parser
      assert allowed.("https://example.com#fragment", ["https://example.com"])
      assert allowed.("https://example.com?evil=true", ["https://example.com"])
      refute allowed.("https://evil.com?example.com=true", ["https://example.com"])

      # Double scheme
      refute allowed.("https://https://example.com", ["https://example.com"])

      # Missing scheme
      refute allowed.("://example.com", ["example.com"])
    end
  end
end
