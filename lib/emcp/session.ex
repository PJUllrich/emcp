defmodule EMCP.Session do
  @moduledoc "Struct representing an MCP session."

  defstruct [:id, :last_seen, :pid]

  @type t :: %__MODULE__{
          id: String.t(),
          last_seen: integer(),
          pid: pid() | nil
        }
end
