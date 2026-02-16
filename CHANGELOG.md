# Changelog

## Unreleased

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

- `EMCP.Server.new/0` has been removed. Use `EMCP.Server.new/1` or the generated `MyApp.MCPServer.server/0` instead.



