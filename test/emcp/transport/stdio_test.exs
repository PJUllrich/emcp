defmodule EMCP.Transport.STDIOTest do
  use ExUnit.Case, async: true

  @server [
    "-e",
    "MIX_ENV=test",
    "--",
    "mix",
    "run",
    "--no-halt",
    "-e",
    "EMCP.Transport.STDIO.start_link()"
  ]

  describe "tools/list" do
    test "returns registered tools" do
      {output, 0} = MCP.Inspector.run(@server ++ ["--method", "tools/list"])

      result = JSON.decode!(output)

      assert %{"tools" => tools} = result
      assert is_list(tools)
      assert length(tools) > 0

      tool = List.first(tools)
      assert Map.has_key?(tool, "name")
      assert Map.has_key?(tool, "description")
      assert Map.has_key?(tool, "inputSchema")
    end
  end

  describe "tools/call" do
    test "calls a tool and returns the result" do
      {output, 0} =
        MCP.Inspector.run(
          @server ++
            [
              "--method",
              "tools/call",
              "--tool-name",
              "echo",
              "--tool-arg",
              "message=hello world"
            ]
        )

      result = JSON.decode!(output)

      assert %{"content" => [%{"type" => "text", "text" => text}]} = result
      assert text =~ "hello world"
    end

    test "returns an error for invalid argument types" do
      {output, 1} =
        MCP.Inspector.run(
          @server ++
            [
              "--method",
              "tools/call",
              "--tool-name",
              "echo",
              "--tool-arg",
              "message=123"
            ]
        )

      assert output =~ "message is invalid"
      assert output =~ "Expected type string but got integer"
    end

    test "calls a tool with all JSON schema types" do
      {output, 0} =
        MCP.Inspector.run(
          @server ++
            [
              "--method",
              "tools/call",
              "--tool-name",
              "all_types",
              "--tool-arg",
              "name=Alice",
              "--tool-arg",
              "age=30",
              "--tool-arg",
              "score=9.5",
              "--tool-arg",
              "active=true",
              "--tool-arg",
              ~s(tags=["elixir","mcp"]),
              "--tool-arg",
              ~s(metadata={"key":"value"})
            ]
        )

      result = JSON.decode!(output)

      assert %{"content" => [%{"type" => "text", "text" => text}]} = result
      args = JSON.decode!(text)
      assert args["name"] == "Alice"
      assert args["age"] == 30
      assert args["score"] == 9.5
      assert args["active"] == true
      assert args["tags"] == ["elixir", "mcp"]
      assert args["metadata"] == %{"key" => "value"}
    end
  end
end
