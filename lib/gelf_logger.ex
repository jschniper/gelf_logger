defmodule Logger.Backends.Gelf do
  @moduledoc """
  GELF Logger Backend
  # GelfLogger [![Build Status](https://travis-ci.org/jschniper/gelf_logger.svg?branch=master)](https://travis-ci.org/jschniper/gelf_logger)

  A logger backend that will generate Graylog Extended Log Format messages. The
  current version only supports UDP messages.

  ## Configuration

  In the config.exs, add gelf_logger as a backend like this:

  ```
  config :logger,
    backends: [:console, {Logger.Backends.Gelf, :gelf_logger}]
  ```

  In addition, you'll need to pass in some configuration items to the backend
  itself:

  ```
  config :logger, :gelf_logger,
    host: "127.0.0.1",
    port: 12201,
    format: "$message",
    application: "myapp",
    compression: :gzip, # Defaults to :gzip, also accepts :zlib or :raw
    metadata: [:request_id, :function, :module, :file, :line],
    hostname: "hostname-override",
    json_encoder: Poison,
    tags: [
      list: "of",
      extra: "tags"
    ]
  ```

  In addition, if you want to use your custom metadata formatter as a "callback",
  you'll need to add below configuration entry:

  ```
    format: {Module, :function}
  ```
  Please bear in mind that your formating function MUST return a tuple in following
  format: `{level, message, timestamp, metadata}`


  In addition to the backend configuration, you might want to check the
  [Logger configuration](https://hexdocs.pm/logger/Logger.html) for other
  options that might be important for your particular environment. In
  particular, modifying the `:utc_log` setting might be necessary
  depending on your server configuration.
  This backend supports `metadata: :all`.

  ### Note on the JSON encoder:

  Currently, the logger defaults to Poison but it can be switched out for any
  module that has an encode!/1 function.

  ## Usage

  Just use Logger as normal.

  ## Improvements

  - [x] Tests
  - [ ] TCP Support
  - [x] Options for compression (none, zlib)
  - [x] Send timestamp instead of relying on the Graylog server to set it
  - [x] Find a better way of pulling the hostname

  And probably many more. This is only out here because it might be useful to
  someone in its current state. Pull requests are always welcome.

  ## Notes

  Credit where credit is due, this would not exist without
  [protofy/erl_graylog_sender](https://github.com/protofy/erl_graylog_sender).
  """

  @behaviour :gen_event

  def init({__MODULE__, name}) do
    if user = Process.whereis(:user) do
      Process.group_leader(self(), user)
      {:ok, configure(name, [])}
    else
      {:error, :ignore}
    end
  end

  def handle_call({:configure, options}, state) do
    {:ok, :ok, configure(state[:name], options)}
  end

  def handle_event({_level, gl, _event}, state) when node(gl) != node() do
    {:ok, state}
  end

  def handle_event({level, _gl, {Logger, msg, ts, md}}, %{level: min_level} = state) do
    if is_nil(min_level) or Logger.compare_levels(level, min_level) != :lt do
      GelfLogger.Worker.start_child(level, msg, ts, md, state)
    end

    {:ok, state}
  end

  def handle_event(:flush, state) do
    {:ok, state}
  end

  def handle_info({:io_reply, ref, :ok}, %{ref: ref} = state) do
    Process.demonitor(ref, [:flush])
    {:ok, state}
  end

  def handle_info({:io_reply, _ref, {:error, error}}, _state) do
    raise "failure while logging gelf messages: " <> inspect(error)
  end

  def handle_info({:DOWN, ref, _, pid, reason}, %{ref: ref}) do
    raise "device #{inspect(pid)} exited: " <> Exception.format_exit(reason)
  end

  def handle_info(_, state) do
    {:ok, state}
  end

  def code_change(_old_vsn, state, _extra) do
    {:ok, state}
  end

  def terminate(_reason, _state) do
    :ok
  end

  ## Helpers

  defp configure(name, options) do
    config = Keyword.merge(Application.get_env(:logger, name, []), options)
    Application.put_env(:logger, name, config)

    {:ok, socket} = :gen_udp.open(0)

    {:ok, hostname} = :inet.gethostname()

    hostname = Keyword.get(config, :hostname, hostname)

    gl_host = Keyword.get(config, :host) |> to_charlist
    port = Keyword.get(config, :port)
    application = Keyword.get(config, :application)
    level = Keyword.get(config, :level)
    metadata = Keyword.get(config, :metadata, [])
    compression = Keyword.get(config, :compression, :gzip)
    encoder = Keyword.get(config, :json_encoder, Poison)
    tags = Keyword.get(config, :tags, [])

    format =
      try do
        format = Keyword.get(config, :format, "$message")

        case format do
          {module, function} ->
            with true <- Code.ensure_loaded?(module),
                 true <- function_exported?(module, function, 4) do
              {module, function}
            else
              _ ->
                Logger.Formatter.compile("$message")
            end

          _ ->
            Logger.Formatter.compile(format)
        end
      rescue
        _ ->
          Logger.Formatter.compile("$message")
      end

    port =
      if is_binary(port) do
        {val, ""} = Integer.parse(to_string(port))
        val
      else
        port
      end

    %{
      name: name,
      gl_host: gl_host,
      host: to_string(hostname),
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
end
