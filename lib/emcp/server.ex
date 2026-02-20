defmodule EMCP.Server do
  @moduledoc "MCP server that handles JSON-RPC requests and dispatches to registered tools."

  alias __MODULE__

  require Logger

  @protocol_version "2025-03-26"

  @parse_error -32700
  @invalid_request -32600
  @method_not_found -32601
  @invalid_params -32602

  defstruct [:name, :version, :title, :description, :instructions, :tools, :prompts, :resources, :resource_templates, :session_store]

  defmacro __using__(opts) do
    quote do
      def server do
        EMCP.Server.new(unquote(opts))
      end
    end
  end

  def new(opts) do
    %Server{
      name: Keyword.fetch!(opts, :name),
      version: Keyword.fetch!(opts, :version),
      title: Keyword.get(opts, :title),
      description: Keyword.get(opts, :description),
      instructions: Keyword.get(opts, :instructions),
      tools: opts |> Keyword.get(:tools, []) |> Map.new(&{&1.name(), &1}),
      prompts: opts |> Keyword.get(:prompts, []) |> Map.new(&{&1.name(), &1}),
      resources: opts |> Keyword.get(:resources, []) |> Map.new(&{&1.uri(), &1}),
      resource_templates: Keyword.get(opts, :resource_templates, []),
      session_store: Keyword.get(opts, :session_store, EMCP.SessionStore.ETS)
    }
  end

  ## Message processing

  def handle_message(server, conn, raw) when is_binary(raw) do
    case JSON.decode(raw) do
      {:ok, request} ->
        handle_request(server, conn, request)

      {:error, _} ->
        Logger.error("Failed to parse JSON request")
        error_response(nil, @parse_error, "Parse error")
    end
  end

  def handle_message(server, conn, request) when is_map(request) do
    handle_request(server, conn, request)
  end

  defp handle_request(
         server,
         conn,
         %{"jsonrpc" => "2.0", "method" => method, "id" => id} = request
       ) do
    Logger.debug("Received request method=#{method} id=#{id}")

    case method do
      "initialize" -> handle_initialize(server, id)
      "ping" -> handle_ping(id)
      "tools/list" -> handle_list_tools(server, id)
      "tools/call" -> handle_call_tool(server, conn, id, request["params"])
      "prompts/list" -> handle_list_prompts(server, id)
      "prompts/get" -> handle_get_prompt(server, conn, id, request["params"])
      "resources/list" -> handle_list_resources(server, id)
      "resources/read" -> handle_read_resource(server, conn, id, request["params"])
      "resources/templates/list" -> handle_list_resource_templates(server, id)
      other -> error_response(id, @method_not_found, "Method not found: #{other}")
    end
  end

  defp handle_request(_server, _conn, %{"jsonrpc" => "2.0", "method" => method}) do
    Logger.debug("Received notification method=#{method}")
    nil
  end

  defp handle_request(_server, _conn, _invalid) do
    Logger.error("Received invalid request")
    error_response(nil, @invalid_request, "Invalid Request")
  end

  ## Handler functions

  defp handle_initialize(server, request_id) do
    server_info =
      %{"name" => server.name, "version" => server.version}
      |> maybe_put("title", server.title)
      |> maybe_put("description", server.description)

    result =
      %{
        "protocolVersion" => @protocol_version,
        "capabilities" => %{
          "tools" => %{"listChanged" => true},
          "prompts" => %{"listChanged" => true},
          "resources" => %{"listChanged" => true}
        },
        "serverInfo" => server_info
      }
      |> maybe_put("instructions", server.instructions)

    result_or_error(request_id, {:ok, result})
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp handle_ping(request_id) do
    result_or_error(request_id, {:ok, %{}})
  end

  defp handle_list_tools(server, request_id) do
    tools = server.tools |> Map.values() |> Enum.map(&EMCP.Tool.to_map/1)
    result_or_error(request_id, {:ok, %{"tools" => tools}})
  end

  defp handle_call_tool(server, conn, request_id, %{"name" => name} = params) do
    case Map.fetch(server.tools, name) do
      {:ok, module} ->
        args = params["arguments"] || %{}

        case EMCP.Tool.InputSchema.validate(module.input_schema(), args) do
          :ok ->
            result_or_error(request_id, {:ok, module.call(conn, args)})

          {:error, message} ->
            result_or_error(request_id, {:error, @invalid_params, message})
        end

      :error ->
        result_or_error(request_id, {:error, @invalid_params, "Tool not found: #{name}"})
    end
  end

  defp handle_list_prompts(server, request_id) do
    prompts = server.prompts |> Map.values() |> Enum.map(&EMCP.Prompt.to_map/1)
    result_or_error(request_id, {:ok, %{"prompts" => prompts}})
  end

  defp handle_get_prompt(server, conn, request_id, %{"name" => name} = params) do
    case Map.fetch(server.prompts, name) do
      {:ok, module} ->
        args = params["arguments"] || %{}

        case EMCP.Prompt.validate_arguments(module, args) do
          :ok ->
            result_or_error(request_id, {:ok, module.template(conn, args)})

          {:error, message} ->
            result_or_error(request_id, {:error, @invalid_params, message})
        end

      :error ->
        result_or_error(request_id, {:error, @invalid_params, "Prompt not found: #{name}"})
    end
  end

  defp handle_list_resources(server, request_id) do
    resources = server.resources |> Map.values() |> Enum.map(&EMCP.Resource.to_map/1)
    result_or_error(request_id, {:ok, %{"resources" => resources}})
  end

  defp handle_read_resource(server, conn, request_id, %{"uri" => uri}) do
    case Map.fetch(server.resources, uri) do
      {:ok, module} ->
        result_or_error(
          request_id,
          {:ok, %{"contents" => EMCP.Resource.to_contents(module, conn)}}
        )

      :error ->
        try_resource_templates(server.resource_templates, conn, request_id, uri)
    end
  end

  defp handle_list_resource_templates(server, request_id) do
    templates = server.resource_templates |> Enum.map(&EMCP.ResourceTemplate.to_map/1)
    result_or_error(request_id, {:ok, %{"resourceTemplates" => templates}})
  end

  defp try_resource_templates([], _conn, request_id, uri) do
    result_or_error(request_id, {:error, @invalid_params, "Resource not found: #{uri}"})
  end

  defp try_resource_templates([template | rest], conn, request_id, uri) do
    case template.read(conn, uri) do
      {:ok, text} ->
        contents = EMCP.ResourceTemplate.to_contents(template, uri, text)
        result_or_error(request_id, {:ok, %{"contents" => contents}})

      {:error, _} ->
        try_resource_templates(rest, conn, request_id, uri)
    end
  end

  ## Response helpers

  defp result_or_error(request_id, {:ok, result}) do
    %{"jsonrpc" => "2.0", "id" => request_id, "result" => result}
  end

  defp result_or_error(request_id, {:error, code, message}) do
    error_response(request_id, code, message)
  end

  defp error_response(id, code, message) do
    %{"jsonrpc" => "2.0", "id" => id, "error" => %{"code" => code, "message" => message}}
  end
end
