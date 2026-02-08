defmodule EMCP.Resource do
  @moduledoc "Behaviour for defining MCP resources."

  @callback uri() :: String.t()
  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback mime_type() :: String.t()
  @callback read() :: String.t()

  def to_map(module) do
    %{
      "uri" => module.uri(),
      "name" => module.name(),
      "description" => module.description(),
      "mimeType" => module.mime_type()
    }
  end

  def to_contents(module) do
    [%{"uri" => module.uri(), "mimeType" => module.mime_type(), "text" => module.read()}]
  end
end
