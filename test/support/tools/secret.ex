defmodule EMCP.Tools.Secret do
  @behaviour EMCP.Tool

  @impl EMCP.Tool
  def name, do: "secret"

  @impl EMCP.Tool
  def description, do: "A secret tool that should be filterable"

  @impl EMCP.Tool
  def input_schema do
    %{
      type: :object,
      properties: %{},
      required: []
    }
  end

  @impl EMCP.Tool
  def call(_conn, _args) do
    EMCP.Tool.response([%{"type" => "text", "text" => "secret data"}])
  end
end
