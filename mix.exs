defmodule GelfLogger.Mixfile do
  use Mix.Project

  def project do
    [app: :gelf_logger,
     version: "0.10.0",
     elixir: "~> 1.8",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     elixirc_paths: elixirc_paths(Mix.env()),
     deps: deps(),
     description: description(),
     package: package(),

     # Docs
     name: "GELF Logger",
     source_url: "https://github.com/manuel-rubio/gelf_logger",
     docs: [
       main: "Logger.Backends.Gelf",
       extras: ["README.md"]
     ]
   ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [
      extra_applications: [:logger],
      mod: {GelfLogger.Application, []}
    ]
  end

  defp deps do
   [
     {:ex_doc, "~> 0.23", only: :dev},
     {:jason, "~> 1.2", optional: true},
     {:poison, "~> 4.0", optional: true}
   ]
  end

  defp description do
    """
      A Logger backend that will generate Graylog Extended Log Format messages and
      send them to a compatible server.
    """
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README*", "LICENSE" ],
      licenses: ["MIT"],
      links: %{"Github": "https://github.com/jschniper/gelf_logger"}
    ]
  end
end
