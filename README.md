# EMCP

An minimal Elixir MCP (Model Context Protocol) server.

## Limitations (for now)

- **No SSE support.** The StreamableHTTP transport does not support Server-Sent Events (GET requests). This means the server cannot push notifications to clients, such as `notifications/tools/list_changed`, `notifications/resources/list_changed`, or `notifications/prompts/list_changed`. In practice, this only matters if you dynamically register or remove tools at runtime. For servers with a fixed set of tools, this has no impact.
- **No resources or prompts.** Only tools are supported.

## Usage

### 1. Define a tool

```elixir
defmodule MyApp.Tools.Echo do
  @behaviour EMCP.Tool

  @impl EMCP.Tool
  def name, do: "echo"

  @impl EMCP.Tool
  def description, do: "Echoes back the provided message"

  @impl EMCP.Tool
  def input_schema do
    %{
      type: :object,
      properties: %{
        message: %{type: :string},
        count: %{type: :integer},
        temperature: %{type: :number},
        verbose: %{type: :boolean},
        tags: %{type: :array, items: %{type: :string}},
        options: %{
          type: :object,
          properties: %{
            format: %{type: :string}
          }
        }
      },
      required: [:message]
    }
  end

  @impl EMCP.Tool
  def call(%{"message" => message}) do
    EMCP.Tool.response([%{"type" => "text", "text" => message}])
  end

  # Return errors with:
  # EMCP.Tool.error("something went wrong")
end
```

### 2. Configure the server

```elixir
# config/config.exs
config :emcp,
  name: "my-app",
  version: "1.0.0",
  tools: [MyApp.Tools.Echo]
```

### 3. Mount the transport

Add the StreamableHTTP transport to your Phoenix router:

```elixir
forward "/mcp", EMCP.Transport.StreamableHTTP
```

Sessions are managed automatically with a configurable TTL (default 60 minutes):

```elixir
config :emcp, session_ttl: to_timeout(minute: 60)
```

## STDIO Transport

For local development or CLI tools, you can use the STDIO transport instead. It reads JSON-RPC messages from stdin and writes responses to stdout.

Add it to your supervision tree:

```elixir
children = [
  EMCP.Transport.STDIO
]
```

Configure it in Claude Code via `.claude/settings.json`:

```json
{
  "mcpServers": {
    "my-app": {
      "command": "mix",
      "args": ["run", "--no-halt"],
      "cwd": "/path/to/your/elixir/project"
    }
  }
}
```

## Acknowledgements

Based on the official [Ruby MCP SDK](https://github.com/modelcontextprotocol/ruby-sdk) reference implementation.

## Development

The e2e tests use the [MCP Inspector](https://github.com/modelcontextprotocol/inspector) CLI. Install it before running tests:

```bash
cd test/inspector && bun install
```

Then run the tests:

```bash
mix test
```
