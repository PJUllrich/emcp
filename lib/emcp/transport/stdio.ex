defmodule EMCP.Transport.STDIO do
  @moduledoc "MCP transport that communicates over standard input/output."

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(opts) do
    server = opts[:server].server()
    send(self(), :read)
    {:ok, server}
  end

  @impl GenServer
  def handle_info(:read, server) do
    case IO.read(:stdio, :line) do
      :eof ->
        {:stop, :normal, server}

      {:error, _reason} ->
        {:stop, :normal, server}

      line ->
        line
        |> String.trim()
        |> then(&EMCP.Server.handle_message(server, &1))
        |> send_response()

        send(self(), :read)
        {:noreply, server}
    end
  end

  defp send_response(nil), do: :ok

  defp send_response(response) do
    IO.puts(JSON.encode!(response))
  end
end
