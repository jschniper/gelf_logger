defmodule GelfLogger.Config do
  @moduledoc """
  Configuration state internal to be shared for the normal handle
  event in synchronous mode and every worker in asynchronous mode.
  """

  defstruct [
    :name,
    :gl_host,
    :host,
    :port,
    :metadata,
    :level,
    :application,
    :socket,
    :compression,
    :tags,
    :encoder,
    :format
  ]

  def configure(name, options) do
    config = Keyword.merge(Application.get_env(:logger, name, []), options)
    Application.put_env(:logger, name, config)

    {:ok, socket} = :gen_udp.open(0)

    {:ok, hostname} = :inet.gethostname()

    hostname = Keyword.get(config, :hostname, to_string(hostname))

    gl_host = to_charlist(Keyword.get(config, :host))
    port = Keyword.get(config, :port)
    application = Keyword.get(config, :application)
    level = Keyword.get(config, :level)
    metadata = Keyword.get(config, :metadata, [])
    compression = Keyword.get(config, :compression, :gzip)
    encoder = Keyword.get(config, :json_encoder, Poison)
    tags = Keyword.get(config, :tags, [])
    format = process_format(Keyword.get(config, :format, "$message"))
    port = process_port(port)

    %__MODULE__{
      name: name,
      gl_host: gl_host,
      host: hostname,
      port: port,
      metadata: metadata,
      level: level,
      application: application,
      socket: socket,
      compression: compression,
      tags: tags,
      encoder: encoder,
      format: format
    }
  end

  defp process_format({module, function}) when is_atom(module) and is_atom(function) do
    with true <- Code.ensure_loaded?(module),
         true <- function_exported?(module, function, 4) do
      {module, function}
    else
      _ -> Logger.Formatter.compile("$message")
    end
  end

  defp process_format(format) do
    Logger.Formatter.compile(format)
  rescue
    _ in ArgumentError ->
      Logger.Formatter.compile("$message")
  end

  defp process_port(port) when is_binary(port) do
    {val, ""} = Integer.parse(port)
    val
  end

  defp process_port(port), do: port
end
