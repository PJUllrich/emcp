defmodule EMCP.Tools.Annotated do
  @behaviour EMCP.Tool

  @impl EMCP.Tool
  def name, do: "annotated"

  @impl EMCP.Tool
  def description, do: "A test tool that declares annotations"

  @impl EMCP.Tool
  def input_schema do
    %{type: :object, properties: %{}, required: []}
  end

  @impl EMCP.Tool
  def annotations do
    %{
      "title" => "Annotated Test Tool",
      "readOnlyHint" => true,
      "destructiveHint" => false,
      "idempotentHint" => true,
      "openWorldHint" => false
    }
  end

  @impl EMCP.Tool
  def call(_conn, _args) do
    EMCP.Tool.response([%{"type" => "text", "text" => "ok"}])
  end
end
