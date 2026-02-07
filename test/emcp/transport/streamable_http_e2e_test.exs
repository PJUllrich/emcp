defmodule EMCP.Transport.StreamableHTTPE2ETest do
  use ExUnit.Case

  setup_all do
    port = Enum.random(49152..65535)

    start_supervised!(
      {Bandit, plug: EMCP.Transport.StreamableHTTP, port: port, startup_log: false}
    )

    # Short keepalive so SSE loops exit quickly on shutdown
    Application.put_env(:emcp, :keepalive_interval, 100)
    on_exit(fn -> Application.delete_env(:emcp, :keepalive_interval) end)

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

  describe "prompts/list" do
    test "returns registered prompts", %{port: port} do
      {output, 0} = inspect_http(port, ["--method", "prompts/list"])
      result = JSON.decode!(output)

      assert %{"prompts" => prompts} = result
      assert length(prompts) == 2

      names = Enum.map(prompts, & &1["name"])
      assert "simple_greeting" in names
      assert "code_review" in names
    end
  end

  describe "prompts/get" do
    test "gets a prompt without arguments", %{port: port} do
      {output, 0} =
        inspect_http(port, [
          "--method",
          "prompts/get",
          "--prompt-name",
          "simple_greeting"
        ])

      result = JSON.decode!(output)
      assert %{"messages" => [%{"role" => "user", "content" => %{"type" => "text"}}]} = result
    end

    test "gets a prompt with arguments", %{port: port} do
      {output, 0} =
        inspect_http(port, [
          "--method",
          "prompts/get",
          "--prompt-name",
          "code_review",
          "--prompt-args",
          "code=def foo, do: :bar",
          "--prompt-args",
          "focus=security"
        ])

      result = JSON.decode!(output)
      assert %{"description" => "Code review prompt", "messages" => messages} = result
      assert length(messages) == 2

      [user_msg, assistant_msg] = messages
      assert user_msg["role"] == "user"
      assert user_msg["content"]["text"] =~ "focusing on security"
      assert user_msg["content"]["text"] =~ "def foo, do: :bar"
      assert assistant_msg["role"] == "assistant"
    end

    test "returns error for missing required argument", %{port: port} do
      {output, 1} =
        inspect_http(port, [
          "--method",
          "prompts/get",
          "--prompt-name",
          "code_review"
        ])

      assert output =~ "Missing required argument: code"
    end
  end
end
