defmodule EMCP.Tools.AllTypes do
  @behaviour EMCP.Tool

  @impl EMCP.Tool
  def name, do: "all_types"

  @impl EMCP.Tool
  def description, do: "A test tool that accepts all JSON schema types"

  @impl EMCP.Tool
  def input_schema do
    %{
      type: :object,
      properties: %{
        name: %{type: :string},
        age: %{type: :integer},
        score: %{type: :number},
        active: %{type: :boolean},
        tags: %{type: :array, items: %{type: :string}},
        metadata: %{
          type: :object,
          properties: %{
            key: %{type: :string},
            count: %{type: :integer},
            ratio: %{type: :number},
            enabled: %{type: :boolean},
            items: %{type: :array, items: %{type: :integer}},
            nested: %{
              type: :object,
              properties: %{
                inner: %{type: :string}
              }
            }
          }
        }
      },
      required: [:name, :age, :score, :active, :tags]
    }
  end

  @impl EMCP.Tool
  def call(args) do
    EMCP.Tool.response([%{"type" => "text", "text" => JSON.encode!(args)}])
  end
end
