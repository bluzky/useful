defmodule Useful.MixProject do
  use Mix.Project

  def project do
    [
      app: :useful,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      included_applications: [:mnesia]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
      {:ecto, "~> 3.9"},
      {:jason, "~> 1.4"},
      {:plug_cowboy, "~> 2.0"},
      {:skema, "~> 0.2.2"},
      {:redix, "~> 1.5"},
      {:phoenix_pubsub, "~> 2.1"},
      {:phoenix_pubsub_redis, "~> 3.0"},
      {:benchee, "~> 1.0", only: :dev},
      {:gettext, "~> 0.26", only: [:dev, :test]}
    ]
  end
end
