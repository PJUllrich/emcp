defmodule EMCP.Prompts.SimpleGreeting do
  @behaviour EMCP.Prompt

  @impl EMCP.Prompt
  def name, do: "simple_greeting"

  @impl EMCP.Prompt
  def description, do: "A simple greeting prompt"

  @impl EMCP.Prompt
  def arguments, do: []

  @impl EMCP.Prompt
  def template(_args) do
    %{
      "messages" => [
        %{"role" => "user", "content" => %{"type" => "text", "text" => "Say hello!"}}
      ]
    }
  end
end
