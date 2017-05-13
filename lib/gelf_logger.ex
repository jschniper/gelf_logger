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
    application: "myapp",
    compression: :gzip, # Defaults to :gzip, also accepts :zlib or :raw
    metadata: [:request_id, :function, :module, :file, :line],
    hostname: "hostname-override",
    tags: [
      list: "of",
      extra: "tags"
    ]
  ```

  In addition to the backend configuration, you might want to check the
  [Logger configuration](https://hexdocs.pm/logger/Logger.html) for other
  options that might be important for your particular environment. In
  particular, modifying the `:utc_log` setting might be necessary
  depending on your server configuration.

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

  use GenEvent

  @max_size 1047040
  @max_packet_size 8192
  @max_payload_size 8180
  @epoch :calendar.datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}})

  def init({__MODULE__, name}) do
    if user = Process.whereis(:user) do
      Process.group_leader(self(), user)
      handle_startup()
    else
      {:error, :ignore}
    end
  end

  def handle_info(:restart, [name]) do
    handle_startup()
    {:noreply, []}
  end

  defp handle_startup do
    result = configure(name, [])
    case result do
      {:ok, pid} -> result
      {:error, _} ->
         Process.send_after(self(), :restart, 10_000)
         {:ok, [name]}
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
      log_event(level, msg, ts, md, state)
    end
    {:ok, state}
  end

  ## Helpers

  defp configure(name, options) do
    config = Keyword.merge(Application.get_env(:logger, name, []), options)
    Application.put_env(:logger, name, config)

    {:ok, socket} = :gen_udp.open(0)

    {:ok, hostname} = :inet.gethostname

    hostname = Keyword.get(config, :hostname, hostname)

    gl_host         = Keyword.get(config, :host) |> to_char_list
    port            = Keyword.get(config, :port)
    application     = Keyword.get(config, :application)
    level           = Keyword.get(config, :level)
    metadata        = Keyword.get(config, :metadata, [])
    compression     = Keyword.get(config, :compression, :gzip)
    tags            = Keyword.get(config, :tags, [])

    port = 
      cond do
        is_binary(port) ->
          {val, ""} = Integer.parse(to_string(port))
          
          val
        true ->
          port
      end

    %{name: name, gl_host: gl_host, host: to_string(hostname), port: port, metadata: metadata, level: level, application: application, socket: socket, compression: compression, tags: tags}
  end

  defp log_event(level, msg, ts, md, state) do
    int_level =
      case level do
        :debug -> 7
        :info  -> 6
        :warn  -> 4
        :error -> 3
      end

    fields =
      md
      |> Keyword.take(state[:metadata])
      |> Keyword.merge(state[:tags])
      |> Map.new(fn({k,v}) -> {"_#{k}", to_string(v)} end)

    {{year, month, day}, {hour, min, sec, milli}} = ts

    epoch_seconds = :calendar.datetime_to_gregorian_seconds({{year, month, day}, {hour, min, sec}}) - @epoch

    {timestamp, _remainder} = "#{epoch_seconds}.#{milli}" |> Float.parse

    gelf = %{
      short_message:  String.slice(to_string(msg), 0..79),
      long_message:   to_string(msg),
      version:        "1.1",
      host:           state[:host],
      level:          int_level,
      timestamp:      Float.round(timestamp, 3),
      _application:   state[:application]
    } |> Map.merge(fields)

    data = Poison.encode!(gelf) |> compress(state[:compression])

    size = byte_size(data)

    cond do
      size > @max_size ->
        raise ArgumentError, message: "Message too large"
      size > @max_packet_size ->
        num = div(size, @max_packet_size)

        num =
          if (num * @max_packet_size) < size do
            num + 1
          else
            num
          end

        id = :crypto.strong_rand_bytes(8)

        send_chunks(state[:socket], state[:gl_host], state[:port], data, id, :binary.encode_unsigned(num), 0, size)
      true ->
        :gen_udp.send(state[:socket], state[:gl_host], state[:port], data)
    end
  end

  defp send_chunks(socket, host, port, data, id, num, seq, size) when size > @max_payload_size do
    <<payload :: binary - size(@max_payload_size), rest :: binary >> = data

    :gen_udp.send(socket, host, port, make_chunk(payload, id, num, seq))

    send_chunks(socket, host, port, rest, id, num, seq + 1, byte_size(rest))
  end

  defp send_chunks(socket, host, port, data, id, num, seq, _size) do
    :gen_udp.send(socket, host, port, make_chunk(data, id, num, seq))
  end

  defp make_chunk(payload, id, num, seq) do
    bin = :binary.encode_unsigned(seq)

    << 0x1e, 0x0f, id :: binary - size(8), bin :: binary - size(1), num :: binary - size(1), payload :: binary >>
  end

  defp compress(data, type) do
    case type do
      :gzip ->
        :zlib.gzip(data)
      :zlib ->
        :zlib.compress(data)
      _ ->
        data
    end
  end
end
