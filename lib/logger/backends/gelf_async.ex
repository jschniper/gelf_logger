defmodule Logger.Backends.GelfAsync do
  @moduledoc """
  GELF Logger Backend Async

  A logger backend that will generate Graylog Extended Log Format messages. The
  current version only supports UDP messages. This module specify an async way
  to send the messages avoiding a bottleneck.

  ## Configuration

  In the config.exs, add gelf_logger as a backend like this:

  ```
  config :logger,
    backends: [:console, {Logger.Backends.GelfAsync, :gelf_logger}]
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

  defdelegate init(args), to: Logger.Backends.Gelf

  defdelegate handle_call(message, state), to: Logger.Backends.Gelf

  def handle_event({_level, gl, _event}, state) when node(gl) != node() do
    {:ok, state}
  end

  def handle_event({level, _gl, {Logger, msg, ts, md}}, %{level: min_level} = state) do
    if is_nil(min_level) or Logger.compare_levels(level, min_level) != :lt do
      GelfLogger.Worker.run([level, msg, ts, md, state])
    end

    {:ok, state}
  end

  def handle_event(:flush, state) do
    {:ok, state}
  end

  defdelegate handle_info(message, state), to: Logger.Backends.Gelf

  defdelegate code_change(old_vsn, state, extra), to: Logger.Backends.Gelf

  defdelegate terminate(reason, state), to: Logger.Backends.Gelf
end
