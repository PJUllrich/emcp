defmodule EMCP.Resources.TestFile do
  @behaviour EMCP.Resource

  @impl EMCP.Resource
  def uri, do: "file:///test/hello.txt"

  @impl EMCP.Resource
  def name, do: "test_file"

  @impl EMCP.Resource
  def description, do: "A test text file resource"

  @impl EMCP.Resource
  def mime_type, do: "text/plain"

  @impl EMCP.Resource
  def read, do: "Hello from resource!"
end
