defmodule EMCP.ResourceTemplates.UserProfile do
  @behaviour EMCP.ResourceTemplate

  @impl EMCP.ResourceTemplate
  def uri_template, do: "file:///users/{user_id}/profile"

  @impl EMCP.ResourceTemplate
  def name, do: "user_profile"

  @impl EMCP.ResourceTemplate
  def description, do: "A user profile resource template"

  @impl EMCP.ResourceTemplate
  def mime_type, do: "application/json"

  @impl EMCP.ResourceTemplate
  def read("file:///users/" <> rest) do
    case String.split(rest, "/") do
      [user_id, "profile"] ->
        {:ok,
         [
           %{
             "uri" => "file:///users/#{user_id}/profile",
             "mimeType" => mime_type(),
             "text" => JSON.encode!(%{"user_id" => user_id, "name" => "User #{user_id}"})
           }
         ]}

      _ ->
        {:error, "Resource not found"}
    end
  end

  def read(_uri), do: {:error, "Resource not found"}
end
