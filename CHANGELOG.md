# Changelog

## v0.3.2

### Enhancements

- Added `recreate_missing_session` option to `EMCP.Transport.StreamableHTTP`. When set to `false`, the transport returns `404` for unknown or expired session IDs instead of silently re-creating them. Defaults to `true` (existing behaviour).

## v0.3.1

### Enhancements

- Added origin validation to `EMCP.Transport.StreamableHTTP` to prevent DNS rebinding attacks. Enable it with `validate_origin: true` and configure `allowed_origins` in the plug opts. It's disabled by default.

## v0.3.0

### Breaking Changes

- Replaced global `:emcp` application config with a `use EMCP.Server` macro. Instead of configuring the server in `config.exs`, define a server module:

  ```elixir
  # Before (no longer supported)
  config :emcp,
    name: "my-server",
    version: "1.0",
    tools: [MyApp.Tools.Echo]

  # After
  defmodule MyApp.MCPServer do
    use EMCP.Server,
      name: "my-server",
      version: "1.0",
      tools: [MyApp.Tools.Echo]
  end
  ```

- Transports now require a `:server` option pointing to the server module:

  ```elixir
  # HTTP
  plug EMCP.Transport.StreamableHTTP, server: MyApp.MCPServer

  # STDIO
  EMCP.Transport.STDIO.start_link(server: MyApp.MCPServer)
  ```

- `conn` is now passed as the first parameter to all behaviour callbacks that handle requests:
  - `EMCP.Tool.call/1` is now `call(conn, args)`
  - `EMCP.Prompt.template/1` is now `template(conn, args)`
  - `EMCP.Resource.read/0` is now `read(conn)`
  - `EMCP.ResourceTemplate.read/1` is now `read(conn, uri)`
  - `EMCP.Server.handle_message/2` is now `handle_message(server, conn, request)`

  The `conn` is the `Plug.Conn` struct when using the HTTP transport, or `nil` when using STDIO.

- `EMCP.SessionStore` is now a behaviour. The ETS implementation has moved to `EMCP.SessionStore.ETS`. Custom backends (e.g. Redis) can be used by implementing the `EMCP.SessionStore` behaviour and passing it via `use EMCP.Server`:

  ```elixir
  defmodule MyApp.MCPServer do
    use EMCP.Server,
      name: "my-server",
      version: "1.0",
      session_store: MyApp.SessionStore.Redis
  end
  ```

  The default is `EMCP.SessionStore.ETS`.

- `EMCP.Transport.StreamableHTTP.notify/2` is now `notify(store, session_id, message)`.

- `EMCP.Transport.StreamableHTTP.broadcast/1` is now `broadcast(store, message)`.

- Added `EMCP.Session` struct with `id`, `last_seen`, and `pid` fields, replacing raw tuples.

- `EMCP.Server.new/0` has been removed. Use `EMCP.Server.new/1` or the generated `MyApp.MCPServer.server/0` instead.