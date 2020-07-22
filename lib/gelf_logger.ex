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

  @max_size 1_047_040
  @max_packet_size 8192
  @max_payload_size 8180
  @epoch :calendar.datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}})

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
      log_event(level, msg, ts, md, state)
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
            with true <- Code.ensure_compiled?(module),
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
      cond do
        is_binary(port) ->
          {val, ""} = Integer.parse(to_string(port))

          val

        true ->
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

  defp log_event(level, msg, ts, md, state) do
    {level, msg, ts, md} = format(level, msg, ts, md, state[:format])

    int_level =
      case level do
        :debug -> 7
        :info -> 6
        :warn -> 4
        :error -> 3
      end

    fields =
      md
      |> take_metadata(state[:metadata])
      |> Keyword.merge(state[:tags])
      |> Map.new(fn {k, v} ->
        if is_list(v) or String.Chars.impl_for(v) == nil do
          {"_#{k}", inspect(v)}
        else
          {"_#{k}", to_string(v)}
        end
      end)

    {{year, month, day}, {hour, min, sec, milli}} = ts

    epoch_seconds =
      :calendar.datetime_to_gregorian_seconds({{year, month, day}, {hour, min, sec}}) - @epoch

    {timestamp, _remainder} = "#{epoch_seconds}.#{milli}" |> Float.parse()

    msg_formatted =
      if is_tuple(state[:format]), do: msg, else: format_event(level, msg, ts, md, state)

    gelf =
      %{
        short_message: String.slice(to_string(msg_formatted), 0..79),
        full_message: to_string(msg_formatted),
        version: "1.1",
        host: state[:host],
        level: int_level,
        timestamp: Float.round(timestamp, 3),
        _application: state[:application]
      }
      |> Map.merge(fields)

    data = encode(gelf, state[:encoder]) |> compress(state[:compression])

    size = byte_size(data)

    cond do
      to_string(msg_formatted) == "" ->
        # Skip empty messages
        :ok

      size > @max_size ->
        raise ArgumentError, message: "Message too large"

      size > @max_packet_size ->
        num = div(size, @max_packet_size)

        num =
          if num * @max_packet_size < size do
            num + 1
          else
            num
          end

        id = :crypto.strong_rand_bytes(8)

        send_chunks(
          state[:socket],
          state[:gl_host],
          state[:port],
          data,
          id,
          :binary.encode_unsigned(num),
          0,
          size
        )

      true ->
        :gen_udp.send(state[:socket], state[:gl_host], state[:port], data)
    end
  end

  defp format(level, message, timestamp, metadata, {module, function}) do
    apply(module, function, [level, message, timestamp, metadata])
  end

  defp format(level, message, timestamp, metadata, _),
    do: {level, message, timestamp, metadata}

  defp send_chunks(socket, host, port, data, id, num, seq, size) when size > @max_payload_size do
    <<payload::binary-size(@max_payload_size), rest::binary>> = data

    :gen_udp.send(socket, host, port, make_chunk(payload, id, num, seq))

    send_chunks(socket, host, port, rest, id, num, seq + 1, byte_size(rest))
  end

  defp send_chunks(socket, host, port, data, id, num, seq, _size) do
    :gen_udp.send(socket, host, port, make_chunk(data, id, num, seq))
  end

  defp make_chunk(payload, id, num, seq) do
    bin = :binary.encode_unsigned(seq)

    <<0x1E, 0x0F, id::binary-size(8), bin::binary-size(1), num::binary-size(1), payload::binary>>
  end

  defp encode(data, encoder) do
    :erlang.apply(encoder, :encode!, [data])
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

  # Ported from Logger.Backends.Console
  defp format_event(level, msg, ts, md, %{format: format, metadata: keys}) do
    Logger.Formatter.format(format, level, msg, ts, take_metadata(md, keys))
  end

  # Ported from Logger.Backends.Console
  defp take_metadata(metadata, :all) do
    Keyword.drop(metadata, [:crash_reason, :ancestors, :callers])
  end

  defp take_metadata(metadata, keys) do
    Enum.reduce(keys, [], fn key, acc ->
      case Keyword.fetch(metadata, key) do
        {:ok, val} -> [{key, val} | acc]
        :error -> acc
      end
    end)
  end
end
