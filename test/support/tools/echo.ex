defmodule EMCP.Tools.Echo do
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
        message: %{type: :string, description: "The message to echo back"}
      },
      required: [:message]
    }
  end

  @impl EMCP.Tool
  def call(%{"message" => message}) do
    EMCP.Tool.response([%{"type" => "text", "text" => message}])
  end
end
