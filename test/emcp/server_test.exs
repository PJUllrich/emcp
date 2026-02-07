defmodule EMCP.ServerTest do
  use ExUnit.Case, async: true

  setup do
    server = EMCP.Server.new()
    {:ok, server: server}
  end

  defp call_tool(server, name, args) do
    request = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "tools/call",
      "params" => %{"name" => name, "arguments" => args}
    }

    EMCP.Server.handle_message(server, JSON.encode!(request))
  end

  defp valid_args(overrides \\ %{}) do
    Map.merge(
      %{
        "name" => "Alice",
        "age" => 30,
        "score" => 9.5,
        "active" => true,
        "tags" => ["elixir"],
        "metadata" => %{
          "key" => "value",
          "count" => 5,
          "ratio" => 0.75,
          "enabled" => false,
          "items" => [1, 2, 3],
          "nested" => %{"inner" => "deep"}
        }
      },
      overrides
    )
  end

  defp assert_tool_result(response) do
    assert %{"result" => %{"content" => [%{"text" => text}]}} = response
    JSON.decode!(text)
  end

  defp assert_tool_error(response, expected_message) do
    assert %{"error" => %{"code" => -32602, "message" => message}} = response
    assert message == expected_message
  end

  describe "handle_message/2 with pre-decoded map" do
    test "accepts an already-decoded map", %{server: server} do
      request = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "ping"
      }

      response = EMCP.Server.handle_message(server, request)
      assert %{"jsonrpc" => "2.0", "id" => 1, "result" => %{}} = response
    end

    test "dispatches tool calls from a map", %{server: server} do
      request = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "echo", "arguments" => %{"message" => "hi"}}
      }

      response = EMCP.Server.handle_message(server, request)
      assert %{"result" => %{"content" => [%{"text" => "hi"}]}} = response
    end

    test "returns error for invalid map request", %{server: server} do
      response = EMCP.Server.handle_message(server, %{"bad" => "request"})
      assert %{"error" => %{"code" => -32600}} = response
    end
  end

  describe "type validation: string" do
    test "rejects non-string value", %{server: server} do
      response = call_tool(server, "all_types", valid_args(%{"name" => 123}))
      assert_tool_error(response, "name is invalid. Expected type string but got integer")
    end

    test "accepts string value", %{server: server} do
      response = call_tool(server, "all_types", valid_args())
      result = assert_tool_result(response)
      assert result["name"] == "Alice"
    end
  end

  describe "type validation: integer" do
    test "rejects non-integer value", %{server: server} do
      response = call_tool(server, "all_types", valid_args(%{"age" => "thirty"}))
      assert_tool_error(response, "age is invalid. Expected type integer but got string")
    end

    test "accepts integer value", %{server: server} do
      response = call_tool(server, "all_types", valid_args())
      result = assert_tool_result(response)
      assert result["age"] == 30
    end
  end

  describe "type validation: number" do
    test "rejects non-number value", %{server: server} do
      response = call_tool(server, "all_types", valid_args(%{"score" => "high"}))
      assert_tool_error(response, "score is invalid. Expected type number but got string")
    end

    test "accepts number value", %{server: server} do
      response = call_tool(server, "all_types", valid_args())
      result = assert_tool_result(response)
      assert result["score"] == 9.5
    end
  end

  describe "type validation: boolean" do
    test "rejects non-boolean value", %{server: server} do
      response = call_tool(server, "all_types", valid_args(%{"active" => "yes"}))
      assert_tool_error(response, "active is invalid. Expected type boolean but got string")
    end

    test "accepts boolean value", %{server: server} do
      response = call_tool(server, "all_types", valid_args())
      result = assert_tool_result(response)
      assert result["active"] == true
    end
  end

  describe "type validation: array" do
    test "rejects non-array value", %{server: server} do
      response = call_tool(server, "all_types", valid_args(%{"tags" => "not_an_array"}))
      assert_tool_error(response, "tags is invalid. Expected type array but got string")
    end

    test "accepts array value", %{server: server} do
      response = call_tool(server, "all_types", valid_args())
      result = assert_tool_result(response)
      assert result["tags"] == ["elixir"]
    end
  end

  describe "type validation: object" do
    test "rejects non-object value", %{server: server} do
      response = call_tool(server, "all_types", valid_args(%{"metadata" => "not_an_object"}))
      assert_tool_error(response, "metadata is invalid. Expected type object but got string")
    end

    test "accepts object value", %{server: server} do
      response = call_tool(server, "all_types", valid_args())
      result = assert_tool_result(response)
      assert result["metadata"] == valid_metadata()
    end
  end

  describe "type validation: array items" do
    test "rejects array with invalid item types", %{server: server} do
      response = call_tool(server, "all_types", valid_args(%{"tags" => ["valid", 123]}))
      assert_tool_error(response, "tags[1] is invalid. Expected type string but got integer")
    end

    test "accepts array with valid item types", %{server: server} do
      response = call_tool(server, "all_types", valid_args(%{"tags" => ["elixir", "mcp"]}))
      result = assert_tool_result(response)
      assert result["tags"] == ["elixir", "mcp"]
    end
  end

  describe "type validation: nested object properties" do
    test "rejects nested string with invalid type", %{server: server} do
      response =
        call_tool(
          server,
          "all_types",
          valid_args(%{"metadata" => %{valid_metadata() | "key" => 999}})
        )

      assert_tool_error(response, "metadata.key is invalid. Expected type string but got integer")
    end

    test "rejects nested integer with invalid type", %{server: server} do
      response =
        call_tool(
          server,
          "all_types",
          valid_args(%{"metadata" => %{valid_metadata() | "count" => "five"}})
        )

      assert_tool_error(
        response,
        "metadata.count is invalid. Expected type integer but got string"
      )
    end

    test "rejects nested number with invalid type", %{server: server} do
      response =
        call_tool(
          server,
          "all_types",
          valid_args(%{"metadata" => %{valid_metadata() | "ratio" => true}})
        )

      assert_tool_error(
        response,
        "metadata.ratio is invalid. Expected type number but got boolean"
      )
    end

    test "rejects nested boolean with invalid type", %{server: server} do
      response =
        call_tool(
          server,
          "all_types",
          valid_args(%{"metadata" => %{valid_metadata() | "enabled" => "yes"}})
        )

      assert_tool_error(
        response,
        "metadata.enabled is invalid. Expected type boolean but got string"
      )
    end

    test "rejects nested array with invalid type", %{server: server} do
      response =
        call_tool(
          server,
          "all_types",
          valid_args(%{"metadata" => %{valid_metadata() | "items" => "not_array"}})
        )

      assert_tool_error(response, "metadata.items is invalid. Expected type array but got string")
    end

    test "rejects nested array with invalid item types", %{server: server} do
      response =
        call_tool(
          server,
          "all_types",
          valid_args(%{"metadata" => %{valid_metadata() | "items" => [1, "two"]}})
        )

      assert_tool_error(
        response,
        "metadata.items[1] is invalid. Expected type integer but got string"
      )
    end

    test "rejects nested object with invalid type", %{server: server} do
      response =
        call_tool(
          server,
          "all_types",
          valid_args(%{"metadata" => %{valid_metadata() | "nested" => 42}})
        )

      assert_tool_error(
        response,
        "metadata.nested is invalid. Expected type object but got integer"
      )
    end

    test "rejects nested object with invalid property type", %{server: server} do
      response =
        call_tool(
          server,
          "all_types",
          valid_args(%{"metadata" => %{valid_metadata() | "nested" => %{"inner" => 123}}})
        )

      assert_tool_error(
        response,
        "metadata.nested.inner is invalid. Expected type string but got integer"
      )
    end

    test "accepts object with all valid property types", %{server: server} do
      response = call_tool(server, "all_types", valid_args())
      result = assert_tool_result(response)
      assert result["metadata"]["key"] == "value"
      assert result["metadata"]["count"] == 5
      assert result["metadata"]["ratio"] == 0.75
      assert result["metadata"]["enabled"] == false
      assert result["metadata"]["items"] == [1, 2, 3]
      assert result["metadata"]["nested"] == %{"inner" => "deep"}
    end
  end

  describe "required fields" do
    test "rejects missing required field", %{server: server} do
      args = valid_args() |> Map.delete("name")
      response = call_tool(server, "all_types", args)
      assert_tool_error(response, "name is required")
    end

    test "rejects each missing required field", %{server: server} do
      for field <- ["name", "age", "score", "active", "tags"] do
        args = valid_args() |> Map.delete(field)
        response = call_tool(server, "all_types", args)
        assert_tool_error(response, "#{field} is required")
      end
    end

    test "accepts missing optional field", %{server: server} do
      args = valid_args() |> Map.delete("metadata")
      response = call_tool(server, "all_types", args)
      result = assert_tool_result(response)
      refute Map.has_key?(result, "metadata")
    end
  end

  defp valid_metadata do
    %{
      "key" => "value",
      "count" => 5,
      "ratio" => 0.75,
      "enabled" => false,
      "items" => [1, 2, 3],
      "nested" => %{"inner" => "deep"}
    }
  end

  # -- Prompt helpers --

  defp list_prompts(server) do
    request = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "prompts/list",
      "params" => %{}
    }

    EMCP.Server.handle_message(server, JSON.encode!(request))
  end

  defp get_prompt(server, name, args \\ %{}) do
    request = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "prompts/get",
      "params" => %{"name" => name, "arguments" => args}
    }

    EMCP.Server.handle_message(server, JSON.encode!(request))
  end

  describe "prompts/list" do
    test "returns all registered prompts", %{server: server} do
      response = list_prompts(server)
      assert %{"result" => %{"prompts" => prompts}} = response
      assert length(prompts) == 2

      names = Enum.map(prompts, & &1["name"]) |> Enum.sort()
      assert names == ["code_review", "simple_greeting"]
    end

    test "includes prompt metadata", %{server: server} do
      response = list_prompts(server)
      %{"result" => %{"prompts" => prompts}} = response

      greeting = Enum.find(prompts, &(&1["name"] == "simple_greeting"))
      assert greeting["description"] == "A simple greeting prompt"
      assert greeting["arguments"] == []

      review = Enum.find(prompts, &(&1["name"] == "code_review"))
      assert review["description"] == "Reviews code with optional focus area"
      assert length(review["arguments"]) == 2

      code_arg = Enum.find(review["arguments"], &(&1["name"] == "code"))
      assert code_arg["description"] == "The code to review"
      assert code_arg["required"] == true

      focus_arg = Enum.find(review["arguments"], &(&1["name"] == "focus"))
      assert focus_arg["description"] == "Optional area to focus on"
      refute Map.has_key?(focus_arg, "required")
    end
  end

  describe "prompts/get" do
    test "returns messages for a prompt without arguments", %{server: server} do
      response = get_prompt(server, "simple_greeting")
      assert %{"result" => %{"messages" => messages}} = response
      assert length(messages) == 1

      assert [%{"role" => "user", "content" => %{"type" => "text", "text" => "Say hello!"}}] =
               messages
    end

    test "returns messages for a prompt with arguments", %{server: server} do
      response = get_prompt(server, "code_review", %{"code" => "def foo, do: :bar"})
      assert %{"result" => result} = response
      assert result["description"] == "Code review prompt"
      assert length(result["messages"]) == 2

      [user_msg, assistant_msg] = result["messages"]
      assert user_msg["role"] == "user"
      assert user_msg["content"]["text"] =~ "def foo, do: :bar"
      assert assistant_msg["role"] == "assistant"
    end

    test "passes optional arguments through", %{server: server} do
      response = get_prompt(server, "code_review", %{"code" => "x = 1", "focus" => "security"})
      assert %{"result" => %{"messages" => [user_msg | _]}} = response
      assert user_msg["content"]["text"] =~ "focusing on security"
    end

    test "returns error for missing required argument", %{server: server} do
      response = get_prompt(server, "code_review", %{})
      assert %{"error" => %{"code" => -32602, "message" => message}} = response
      assert message == "Missing required argument: code"
    end

    test "returns error for unknown prompt", %{server: server} do
      response = get_prompt(server, "nonexistent")
      assert %{"error" => %{"code" => -32602, "message" => message}} = response
      assert message == "Prompt not found: nonexistent"
    end
  end

  describe "initialize capabilities include prompts" do
    test "reports prompts capability", %{server: server} do
      request = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "initialize",
        "params" => %{}
      }

      response = EMCP.Server.handle_message(server, request)
      assert %{"result" => %{"capabilities" => capabilities}} = response
      assert capabilities["prompts"] == %{"listChanged" => true}
    end
  end
end
