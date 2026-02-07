import Config

config :logger, level: :critical

config :emcp,
  tools: [EMCP.Tools.Echo, EMCP.Tools.AllTypes],
  prompts: [EMCP.Prompts.SimpleGreeting, EMCP.Prompts.CodeReview],
  resources: [EMCP.Resources.TestFile],
  resource_templates: [EMCP.ResourceTemplates.UserProfile]
