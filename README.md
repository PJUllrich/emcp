# EMCP

An minimal Elixir MCP (Model Context Protocol) server.

## Limitations (for now)

- **No resources.** Only tools and prompts are supported.

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

Add the StreamableHTTP transport to your Phoenix router. Mount it outside any pipeline since EMCP handles content negotiation itself:

```elixir
scope "/mcp" do
  forward "/", EMCP.Transport.StreamableHTTP
end
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

## Prompts

Prompts are reusable templates that return structured messages. Define a prompt module, then register it in your config:

```elixir
defmodule MyApp.Prompts.CodeReview do
  @behaviour EMCP.Prompt

  @impl EMCP.Prompt
  def name, do: "code_review"

  @impl EMCP.Prompt
  def description, do: "Reviews code with optional focus area"

  @impl EMCP.Prompt
  def arguments do
    [
      %{name: "code", description: "The code to review", required: true},
      %{name: "focus", description: "Optional area to focus on"}
    ]
  end

  @impl EMCP.Prompt
  def template(%{"code" => code} = args) do
    focus = args["focus"]

    user_text =
      if focus,
        do: "Review this code, focusing on #{focus}:\n\n#{code}",
        else: "Review this code:\n\n#{code}"

    %{
      "description" => "Code review prompt",
      "messages" => [
        %{"role" => "user", "content" => %{"type" => "text", "text" => user_text}},
        %{"role" => "assistant", "content" => %{"type" => "text", "text" => "I'll review the code you've provided."}}
      ]
    }
  end
end
```

```elixir
# config/config.exs
config :emcp,
  prompts: [MyApp.Prompts.CodeReview]
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
