defmodule EMCP.Prompt do
  @moduledoc "Behaviour for defining MCP prompts."

  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback arguments() :: [argument()]
  @callback template(args :: map()) :: result()

  @type argument :: %{
          required(:name) => String.t(),
          optional(:description) => String.t(),
          optional(:required) => boolean()
        }

  @type message :: %{
          required(:role) => String.t(),
          required(:content) => content()
        }

  @type content :: %{
          required(:type) => String.t(),
          required(:text) => String.t()
        }

  @type result :: %{
          optional(:description) => String.t(),
          required(:messages) => [message()]
        }

  def to_map(module) do
    %{
      "name" => module.name(),
      "description" => module.description(),
      "arguments" => Enum.map(module.arguments(), &stringify_keys/1)
    }
  end

  def validate_arguments(module, args) do
    module.arguments()
    |> Enum.filter(& &1[:required])
    |> Enum.find(fn arg -> not Map.has_key?(args, to_string(arg[:name])) end)
    |> case do
      nil -> :ok
      arg -> {:error, "Missing required argument: #{arg[:name]}"}
    end
  end

  defp stringify_keys(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
