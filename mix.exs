defmodule EMCP.MixProject do
  use Mix.Project

  @version "0.1.6"
  @source_url "https://github.com/PJUllrich/emcp"

  def project do
    [
      app: :emcp,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {EMCP.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:plug, "~> 1.16"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:bandit, "~> 1.0", only: :test}
    ]
  end

  defp package do
    [
      description: "A minimal Elixir Model Context Protocol (MCP) server",
      files: ["lib", "LICENSE", "mix.exs", "README.md"],
      licenses: ["MIT"],
      maintainers: ["Peter Ullrich"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      extras: [
        "README.md",
        "LICENSE"
      ],
      main: "readme",
      source_url: @source_url,
      source_ref: "main",
      formatters: ["html"]
    ]
  end
end
