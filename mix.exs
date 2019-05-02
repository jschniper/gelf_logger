defmodule GelfLogger.Mixfile do
  use Mix.Project

  def project do
    [app: :gelf_logger,
     version: "0.9.0",
     elixir: "~> 1.2",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     elixirc_paths: elixirc_paths(Mix.env()),
     deps: deps(),
     description: description(),
     package: package(),

     # Docs
     name: "GELF Logger",
     source_url: "https://github.com/jschniper/gelf_logger",
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
    [applications: [:logger]]
  end

  defp deps do
   [
     {:ex_doc, "~> 0.14", only: :dev},
     {:jason, ">= 1.0.0", only: [:dev, :test]},
     {:poison, ">= 1.0.0", only: [:dev, :test]},
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
      maintainers: ["Joshua Schniper"],
      licenses: ["MIT"],
      links: %{"Github": "https://github.com/jschniper/gelf_logger"}
    ]
  end
end
