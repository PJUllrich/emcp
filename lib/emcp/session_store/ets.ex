defmodule EMCP.SessionStore.ETS do
  @moduledoc "ETS-backed session storage."

  @behaviour EMCP.SessionStore

  @table __MODULE__

  @impl EMCP.SessionStore
  def init do
    :ets.new(@table, [:set, :public, :named_table])
    :ok
  end

  @impl EMCP.SessionStore
  def store(session_id) do
    :ets.insert(@table, {session_id, System.monotonic_time(:millisecond), nil})
    :ok
  end

  @impl EMCP.SessionStore
  def lookup(session_id) do
    case :ets.lookup(@table, session_id) do
      [{^session_id, last_seen, pid}] ->
        %EMCP.Session{id: session_id, last_seen: last_seen, pid: pid}

      [] ->
        nil
    end
  end

  @impl EMCP.SessionStore
  def touch(session_id) do
    :ets.update_element(@table, session_id, {2, System.monotonic_time(:millisecond)})
    :ok
  end

  @impl EMCP.SessionStore
  def register(session_id, pid) do
    :ets.update_element(@table, session_id, {3, pid})
    :ok
  end

  @impl EMCP.SessionStore
  def unregister(session_id) do
    :ets.update_element(@table, session_id, {3, nil})
    :ok
  rescue
    ArgumentError -> :ok
  end

  @impl EMCP.SessionStore
  def get_pid(session_id) do
    case :ets.lookup(@table, session_id) do
      [{^session_id, _last_seen, pid}] -> pid
      [] -> nil
    end
  end

  @impl EMCP.SessionStore
  def delete(session_id) do
    :ets.delete(@table, session_id)
    :ok
  end

  @impl EMCP.SessionStore
  def all_sessions do
    :ets.tab2list(@table)
    |> Enum.map(fn {id, last_seen, pid} ->
      %EMCP.Session{id: id, last_seen: last_seen, pid: pid}
    end)
  end
end
