defmodule EMCP.ServerGlobalConfigTest do
  use ExUnit.Case, async: false

  describe "global configuration guard" do
    test "raises when global :emcp application config is found" do
      Application.put_env(:emcp, :name, "should-not-exist")

      assert_raise RuntimeError,
                   ~r/Global :emcp application config is no longer supported/,
                   fn -> EMCP.Server.new(name: "test", version: "1.0") end
    after
      Application.delete_env(:emcp, :name)
    end
  end
end
