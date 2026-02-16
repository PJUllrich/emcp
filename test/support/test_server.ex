defmodule EMCP.TestServer do
  use EMCP.Server,
    name: "emcp-test",
    version: "0.1.0",
    tools: [EMCP.Tools.Echo, EMCP.Tools.AllTypes],
    prompts: [EMCP.Prompts.SimpleGreeting, EMCP.Prompts.CodeReview],
    resources: [EMCP.Resources.TestFile],
    resource_templates: [EMCP.ResourceTemplates.UserProfile]
end
