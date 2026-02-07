defmodule EMCP.Prompts.CodeReview do
  @behaviour EMCP.Prompt

  @impl EMCP.Prompt
  def name, do: "code_review"

  @impl EMCP.Prompt
  def description, do: "Reviews code with optional focus area"

  @impl EMCP.Prompt
  def arguments do
    [
      %{name: "code", description: "The code to review", required: true},
      %{name: "focus", description: "Optional area to focus on"}
    ]
  end

  @impl EMCP.Prompt
  def template(args) do
    code = args["code"]
    focus = args["focus"]

    user_text =
      if focus,
        do: "Review this code, focusing on #{focus}:\n\n#{code}",
        else: "Review this code:\n\n#{code}"

    %{
      "description" => "Code review prompt",
      "messages" => [
        %{"role" => "user", "content" => %{"type" => "text", "text" => user_text}},
        %{
          "role" => "assistant",
          "content" => %{
            "type" => "text",
            "text" => "I'll review the code you've provided."
          }
        }
      ]
    }
  end
end
