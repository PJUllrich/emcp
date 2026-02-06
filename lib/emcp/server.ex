defmodule EMCP.Server do
  @moduledoc "MCP server that handles JSON-RPC requests and dispatches to registered tools."

  @protocol_version "2025-03-26"

  @parse_error -32700
  @invalid_request -32600
  @method_not_found -32601
  @invalid_params -32602

  defstruct [:name, :version, :tools]

  def new do
    tools =
      :emcp
      |> Application.get_env(:tools, [])
      |> Map.new(fn mod -> {mod.name(), mod} end)

    %__MODULE__{
      name: Application.get_env(:emcp, :name, "emcp"),
      version: Application.get_env(:emcp, :version, "0.1.0"),
      tools: tools
    }
  end

  def handle_message(server, raw) when is_binary(raw) do
    case JSON.decode(raw) do
      {:ok, request} -> handle_request(server, request)
      {:error, _} -> error_response(nil, @parse_error, "Parse error")
    end
  end

  def handle_message(server, request) when is_map(request) do
    handle_request(server, request)
  end

  defp handle_request(server, %{"jsonrpc" => "2.0", "method" => method, "id" => id} = request) do
    case dispatch(server, method, request["params"]) do
      {:ok, result} -> success_response(id, result)
      {:error, code, message} -> error_response(id, code, message)
    end
  end

  # Notifications — no id, no response
  defp handle_request(_server, %{"jsonrpc" => "2.0", "method" => _method}) do
    nil
  end

  defp handle_request(_server, _invalid) do
    error_response(nil, @invalid_request, "Invalid Request")
  end

  defp dispatch(server, "initialize", _params) do
    {:ok,
     %{
       "protocolVersion" => @protocol_version,
       "capabilities" => %{"tools" => %{"listChanged" => true}},
       "serverInfo" => %{
         "name" => server.name,
         "version" => server.version
       }
     }}
  end

  defp dispatch(_server, "ping", _params) do
    {:ok, %{}}
  end

  defp dispatch(server, "tools/list", _params) do
    tools = server.tools |> Map.values() |> Enum.map(&EMCP.Tool.to_map/1)
    {:ok, %{"tools" => tools}}
  end

  defp dispatch(server, "tools/call", %{"name" => name} = params) do
    case Map.fetch(server.tools, name) do
      {:ok, module} ->
        args = params["arguments"] || %{}

        case EMCP.Tool.InputSchema.validate(module.input_schema(), args) do
          :ok ->
            {:ok, module.call(args)}

          {:error, message} ->
            {:error, @invalid_params, message}
        end

      :error ->
        {:error, @invalid_params, "Tool not found: #{name}"}
    end
  end

  defp dispatch(_server, method, _params) do
    {:error, @method_not_found, "Method not found: #{method}"}
  end

  defp success_response(id, result) do
    %{"jsonrpc" => "2.0", "id" => id, "result" => result}
  end

  defp error_response(id, code, message) do
    %{"jsonrpc" => "2.0", "id" => id, "error" => %{"code" => code, "message" => message}}
  end
end
