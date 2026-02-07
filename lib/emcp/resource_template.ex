defmodule EMCP.ResourceTemplate do
  @moduledoc "Behaviour for defining MCP resource templates."

  @callback uri_template() :: String.t()
  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback mime_type() :: String.t()
  @callback read(uri :: String.t()) :: {:ok, [content()]} | {:error, String.t()}

  @type content :: %{
          required(:uri) => String.t(),
          required(:mime_type) => String.t(),
          optional(:text) => String.t(),
          optional(:blob) => String.t()
        }

  def to_map(module) do
    %{
      "uriTemplate" => module.uri_template(),
      "name" => module.name(),
      "description" => module.description(),
      "mimeType" => module.mime_type()
    }
  end
end
