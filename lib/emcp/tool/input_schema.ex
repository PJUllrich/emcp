defmodule EMCP.Tool.InputSchema do
  @moduledoc "Validates tool call arguments against a JSON Schema definition."

  def validate(schema, args) do
    validate_properties(nil, schema, args)
  end

  defp validate_properties(path, schema, args) do
    required = schema[:required] || []

    with :ok <- validate_required(path, required, args) do
      properties = schema[:properties] || %{}

      Enum.reduce_while(properties, :ok, fn {name, property_schema}, :ok ->
        case Map.fetch(args, to_string(name)) do
          {:ok, value} ->
            child_path = if path, do: "#{path}.#{name}", else: "#{name}"

            case validate_value(child_path, value, property_schema) do
              :ok -> {:cont, :ok}
              {:error, _} = error -> {:halt, error}
            end

          :error ->
            {:cont, :ok}
        end
      end)
    end
  end

  defp validate_required(_path, [], _args), do: :ok

  defp validate_required(path, required, args) do
    Enum.reduce_while(required, :ok, fn name, :ok ->
      if Map.has_key?(args, to_string(name)) do
        {:cont, :ok}
      else
        field = if path, do: "#{path}.#{name}", else: "#{name}"
        {:halt, {:error, "#{field} is required"}}
      end
    end)
  end

  defp validate_value(path, value, %{type: type} = schema) do
    if expected_type?(type, value) do
      validate_nested(path, value, schema)
    else
      {:error, "#{path} is invalid. Expected type #{type} but got #{actual_type(value)}"}
    end
  end

  defp validate_nested(path, items, %{type: :array, items: item_schema}) do
    items
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {item, index}, :ok ->
      case validate_value("#{path}[#{index}]", item, item_schema) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp validate_nested(path, object, %{type: :object} = schema) do
    validate_properties(path, schema, object)
  end

  # Fallback for all non-nested values like integers, booleans, etc.
  defp validate_nested(_path, _value, %{type: type})
       when type in [:string, :integer, :number, :boolean] do
    :ok
  end

  defp expected_type?(:string, value), do: is_binary(value)
  defp expected_type?(:integer, value), do: is_integer(value)
  defp expected_type?(:number, value), do: is_number(value)
  defp expected_type?(:boolean, value), do: is_boolean(value)
  defp expected_type?(:array, value), do: is_list(value)
  defp expected_type?(:object, value), do: is_map(value)

  defp actual_type(value) when is_binary(value), do: "string"
  defp actual_type(value) when is_integer(value), do: "integer"
  defp actual_type(value) when is_float(value), do: "float"
  defp actual_type(value) when is_boolean(value), do: "boolean"
  defp actual_type(value) when is_list(value), do: "array"
  defp actual_type(value) when is_map(value), do: "object"
  defp actual_type(_), do: "unknown"
end
