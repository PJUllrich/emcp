defmodule EMCP.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    :ets.new(EMCP.SessionStore, [:set, :public, :named_table])

    Supervisor.start_link([], strategy: :one_for_one, name: EMCP.Supervisor)
  end
end
