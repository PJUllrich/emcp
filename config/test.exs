import Config

config :logger, level: :critical

config :emcp, tools: [EMCP.Tools.Echo, EMCP.Tools.AllTypes]
