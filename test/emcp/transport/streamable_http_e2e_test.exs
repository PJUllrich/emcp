defmodule EMCP.Transport.StreamableHTTPE2ETest do
  use ExUnit.Case

  setup_all do
    port = Enum.random(49152..65535)

    start_supervised!(
      {Bandit, plug: EMCP.Transport.StreamableHTTP, port: port, startup_log: false}
    )

    {:ok, port: port}
  end

  defp inspect_http(port, args) do
    MCP.Inspector.run(["--transport", "http", "http://localhost:#{port}/mcp" | args])
  end

  describe "tools/list" do
    test "returns registered tools", %{port: port} do
      {output, 0} = inspect_http(port, ["--method", "tools/list"])
      result = JSON.decode!(output)

      assert %{"tools" => tools} = result
      assert length(tools) > 0

      names = Enum.map(tools, & &1["name"])
      assert "echo" in names
      assert "all_types" in names
    end
  end

  describe "tools/call" do
    test "calls echo tool", %{port: port} do
      {output, 0} =
        inspect_http(port, [
          "--method",
          "tools/call",
          "--tool-name",
          "echo",
          "--tool-arg",
          "message=hello from http"
        ])

      result = JSON.decode!(output)
      assert %{"content" => [%{"type" => "text", "text" => "hello from http"}]} = result
    end

    test "calls all_types tool", %{port: port} do
      {output, 0} =
        inspect_http(port, [
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
          ~s(tags=["elixir"]),
          "--tool-arg",
          ~s(metadata={"key":"value"})
        ])

      result = JSON.decode!(output)
      assert %{"content" => [%{"text" => text}]} = result
      args = JSON.decode!(text)
      assert args["name"] == "Alice"
      assert args["age"] == 30
      assert args["score"] == 9.5
      assert args["active"] == true
      assert args["tags"] == ["elixir"]
      assert args["metadata"] == %{"key" => "value"}
    end

    test "returns error for invalid arguments", %{port: port} do
      {output, 1} =
        inspect_http(port, [
          "--method",
          "tools/call",
          "--tool-name",
          "echo",
          "--tool-arg",
          "message=123"
        ])

      assert output =~ "message is invalid"
      assert output =~ "Expected type string but got integer"
    end
  end
end
