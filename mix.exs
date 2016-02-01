defmodule GelfLogger.Mixfile do
  use Mix.Project

  def project do
    [app: :gelf_logger,
     version: "0.0.1",
     elixir: "~> 1.1",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps,
     description: description,
     package: package
   ]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [applications: [:logger]]
  end

  defp deps do
   [
     {:poison, ">= 1.0.0"}
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
