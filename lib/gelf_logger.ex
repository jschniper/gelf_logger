defmodule Logger.Backends.Gelf do
  use GenEvent

  @max_size 1047040
  @max_packet_size 8192
  @max_payload_size 8180

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

  ## Helpers

  defp configure(name, options) do
    config = Keyword.merge(Application.get_env(:logger, name, []), options)
    Application.put_env(:logger, name, config)

    {:ok, socket} = :gen_udp.open(0)
    
    {host, _exit_code} = System.cmd("hostname", [], [])

    {:ok, gl_host } = Keyword.get(config, :host) |> to_char_list |> :inet_parse.address
    port            = Keyword.get(config, :port)
    application     = Keyword.get(config, :application)
    level           = Keyword.get(config, :level)
    metadata        = Keyword.get(config, :metadata, [])
    compression     = Keyword.get(config, :compression, :gzip)

    %{name: name, gl_host: gl_host, host: String.strip(host), port: port, metadata: metadata, level: level, application: application, socket: socket, compression: compression}
  end

  defp log_event(level, msg, ts, md, state) do
    int_level = case level do
      :debug -> 0
      :info  -> 1
      :warn  -> 2
      :error -> 3
    end
   
    fields = Enum.reduce(Dict.take(md, state[:metadata]), %{}, fn({k,v}, accum) ->
      Map.put(accum, "_#{k}", to_string(v))
    end)

    # TODO: fix timestamp
    {{year, month, day}, {hour, min, sec, milli}} = ts

    gelf = %{
      short_message:  String.slice(to_string(msg), 0..79),
      long_message:   to_string(msg),
      version:        "1.1",
      host:           state[:host],
      level:          int_level,
      _log_time:      "#{year}-#{month}-#{day} #{hour}:#{min}:#{sec}.#{milli}",
      _application:   state[:application]
    } |> Map.merge(fields)

    data = Poison.encode!(gelf) |> compress(state[:compression])

    size = byte_size(data)

    cond do
      size > @max_size ->
        raise ArgumentError, message: "Message too large"
      size > @max_packet_size ->
        num = div(size, @max_packet_size)

        if (num * @max_packet_size) < size do
          num = num + 1
        end

        id = :crypto.rand_bytes(8)

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
    
    <<0x1e, 0x0f, id :: binary - size(8), bin :: binary - size(1), num :: binary - size(1), payload :: binary >>
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
