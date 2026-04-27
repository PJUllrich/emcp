defmodule EMCP.ToolTest do
  use ExUnit.Case, async: true

  describe "to_map/1" do
    test "omits annotations when the tool does not implement the callback" do
      map = EMCP.Tool.to_map(EMCP.Tools.Echo)

      assert map["name"] == "echo"
      assert Map.has_key?(map, "description")
      assert Map.has_key?(map, "inputSchema")
      refute Map.has_key?(map, "annotations")
    end

    test "includes annotations when the tool implements the callback" do
      map = EMCP.Tool.to_map(EMCP.Tools.Annotated)

      assert %{
               "title" => "Annotated Test Tool",
               "readOnlyHint" => true,
               "destructiveHint" => false,
               "idempotentHint" => true,
               "openWorldHint" => false
             } = map["annotations"]
    end
  end
end
