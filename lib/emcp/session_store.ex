defmodule EMCP.SessionStore do
  @moduledoc "Functions for managing MCP session storage. The ETS table is owned by the application."

  @table __MODULE__

  def store(session_id) do
    :ets.insert(@table, {session_id, System.monotonic_time(:millisecond), nil})
  end

  def lookup(session_id) do
    case :ets.lookup(@table, session_id) do
      [{^session_id, last_active, sse_pid}] -> {last_active, sse_pid}
      [] -> nil
    end
  end

  def touch(session_id) do
    :ets.update_element(@table, session_id, {2, System.monotonic_time(:millisecond)})
  end

  def register_sse(session_id, pid) do
    :ets.update_element(@table, session_id, {3, pid})
  end

  def unregister_sse(session_id) do
    :ets.update_element(@table, session_id, {3, nil})
  rescue
    ArgumentError -> false
  end

  def get_sse_pid(session_id) do
    case :ets.lookup(@table, session_id) do
      [{^session_id, _last_active, pid}] -> pid
      [] -> nil
    end
  end

  def delete(session_id) do
    :ets.delete(@table, session_id)
  end
end
