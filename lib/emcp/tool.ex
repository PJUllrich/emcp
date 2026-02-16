defmodule EMCP.Tool do
  @moduledoc "Behaviour for defining MCP tools."

  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback input_schema() :: map()
  @callback call(conn :: Plug.Conn.t() | nil, args :: map()) :: map()

  @doc """
  Wraps a list of content items into a tool response map.

  The MCP protocol supports several content types:

  **Text content:**

      EMCP.Tool.response([
        %{"type" => "text", "text" => "Hello world"}
      ])

  **Image content** (base64-encoded):

      EMCP.Tool.response([
        %{"type" => "image", "data" => base64_data, "mimeType" => "image/png"}
      ])

  **Embedded resource:**

      EMCP.Tool.response([
        %{"type" => "resource", "resource" => %{
          "uri" => "file:///path/to/output.json",
          "mimeType" => "application/json",
          "text" => ~s({"key": "value"})
        }}
      ])

  You can mix multiple content types in a single response:

      EMCP.Tool.response([
        %{"type" => "text", "text" => "Here's the chart you requested:"},
        %{"type" => "image", "data" => chart_base64, "mimeType" => "image/png"}
      ])
  """
  def response(content) when is_list(content) do
    %{"content" => content}
  end

  @doc """
  Wraps an error message into a tool response map with the `isError` flag set.

      EMCP.Tool.error("Something went wrong")
  """
  def error(message) when is_binary(message) do
    %{"content" => [%{"type" => "text", "text" => message}], "isError" => true}
  end

  def to_map(module) do
    %{
      "name" => module.name(),
      "description" => module.description(),
      "inputSchema" => module.input_schema()
    }
  end
end
