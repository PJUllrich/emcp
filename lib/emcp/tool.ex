defmodule EMCP.Tool do
  @moduledoc "Behaviour for defining MCP tools."

  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback input_schema() :: map()
  @callback call(args :: map()) :: map()

  def response(content) when is_list(content) do
    %{"content" => content}
  end

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
