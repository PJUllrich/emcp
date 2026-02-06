defmodule EMCP.SessionStore do
  @moduledoc "Functions for managing MCP session storage. The ETS table is owned by the application."

  @table __MODULE__

  def store(session_id) do
    :ets.insert(@table, {session_id, System.monotonic_time(:millisecond)})
  end

  def lookup(session_id) do
    case :ets.lookup(@table, session_id) do
      [{^session_id, last_active}] -> last_active
      [] -> nil
    end
  end

  def touch(session_id) do
    :ets.update_element(@table, session_id, {2, System.monotonic_time(:millisecond)})
  end

  def delete(session_id) do
    :ets.delete(@table, session_id)
  end
end
