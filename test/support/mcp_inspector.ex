defmodule MCP.Inspector do
  @bin Path.join([File.cwd!(), "test/inspector/node_modules/.bin/mcp-inspector"])

  def run(args) when is_list(args) do
    System.cmd(@bin, ["--cli" | args], stderr_to_stdout: true)
  end
end
