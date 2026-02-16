defmodule EMCP.SessionStore do
  @moduledoc """
  Behaviour for session storage backends.

  A session store manages MCP sessions for the HTTP transport.

  ## Sessions

  A session represents a logical connection between a client and the server.
  It is stateless — there is no process backing it. A session is simply a record
  in the store that the transport reads and writes on each request.

  It is created when a client sends an `initialize` request and persists across
  multiple HTTP requests identified by the `mcp-session-id` header. A session
  tracks when it was last active so the transport can expire stale sessions.
  It is deleted when the client sends a DELETE request or when it expires.

  ## SSE connections

  A session can optionally have an associated SSE (Server-Sent Events) connection.
  This is a long-lived HTTP connection opened by the client via a GET request.
  The connection is handled by a process that sits in a receive loop, waiting for
  messages to forward to the client. It holds no state of its own — it only
  references the session ID to clean up when the connection closes.

  When an SSE connection is registered on a session, responses to subsequent
  POST requests are routed through the SSE stream instead of being returned
  in the POST response body.

  The SSE process is independent from the session itself. A session can exist
  without an SSE connection (responses are returned in the POST response body),
  and the SSE connection can be closed and re-opened without affecting the session.
  The SSE pid is cleared automatically when the connection drops or when the client
  sends a DELETE request.

  ## Implementation

  The store must support creating, looking up, and deleting sessions, as well as
  registering and clearing SSE pids.

  EMCP ships with `EMCP.SessionStore.ETS` as the default in-memory implementation.
  For distributed or persistent setups, implement this behaviour with a backend
  like Redis or a database.
  """

  alias EMCP.Session

  @doc "Initialize the storage backend. Called once at application startup."
  @callback init() :: :ok

  @doc "Create a new session with the given ID, setting `last_seen` to the current time and `pid` to nil."
  @callback store(session_id :: String.t()) :: :ok

  @doc "Look up a session by ID. Returns the session struct or nil if not found."
  @callback lookup(session_id :: String.t()) :: Session.t() | nil

  @doc "Update the `last_seen` timestamp for the given session."
  @callback touch(session_id :: String.t()) :: :ok

  @doc "Associate an SSE connection pid with the given session."
  @callback register(session_id :: String.t(), pid :: pid()) :: :ok

  @doc "Clear the SSE connection pid from the given session. The session itself is kept."
  @callback unregister(session_id :: String.t()) :: :ok

  @doc "Return the SSE connection pid for the given session, or nil if none is registered."
  @callback get_pid(session_id :: String.t()) :: pid() | nil

  @doc "Delete the session with the given ID."
  @callback delete(session_id :: String.t()) :: :ok

  @doc "Return all sessions. Used by broadcast to send messages to all active SSE connections."
  @callback all_sessions() :: [Session.t()]
end
