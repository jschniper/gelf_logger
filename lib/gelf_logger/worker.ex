defmodule GelfLogger.Worker do
  use GenServer, restart: :temporary

  @max_size 1_047_040
  @max_packet_size 8192
  @max_payload_size 8180
  @default_name :gelf_logger

  def start_link([]) do
    GenServer.start_link(__MODULE__, [])
  end

  @impl GenServer
  def init([]) do
    {:configure, name, options} = :persistent_term.get(:gelf_logger, {:configure, @default_name, []})
    state = GelfLogger.Config.configure(name, options)
    {:ok, state}
  end

  @impl GenServer
  def handle_cast([level, msg, ts, md], state) do
    {level, msg, ts, md} = format(level, msg, ts, md, state.format)

    int_level =
      case level do
        :debug -> 7
        :info -> 6
        :notice -> 5
        :warn -> 4
        :error -> 3
        :critical -> 2
        :alert -> 1
        :emergency -> 0
      end

    fields =
      md
      |> take_metadata(state.metadata)
      |> Keyword.merge(state.tags)
      |> Map.new(fn {k, v} ->
        if is_list(v) or String.Chars.impl_for(v) == nil do
          {"_#{k}", inspect(v)}
        else
          {"_#{k}", to_string(v)}
        end
      end)

    {{year, month, day}, {hour, min, sec, milli}} = ts

    epoch_milliseconds =
      {{year, month, day}, {hour, min, sec}}
      |> NaiveDateTime.from_erl!({milli * 1_000, 0})
      |> DateTime.from_naive!("Etc/UTC")
      |> DateTime.to_unix(:millisecond)

    timestamp = Float.round(epoch_milliseconds / 1_000, 3)

    msg_formatted =
      if(is_tuple(state.format), do: msg, else: format_event(level, msg, ts, md, state))
      |> to_string()

    gelf =
      %{
        short_message: String.slice(msg_formatted, 0..79),
        full_message: msg_formatted,
        version: "1.1",
        host: state.host,
        level: int_level,
        timestamp: timestamp,
        _application: state.application
      }
      |> Map.merge(fields)

    data =
      gelf
      |> encode(state.encoder)
      |> compress(state.compression)

    size = byte_size(data)

    cond do
      msg_formatted == "" ->
        # Skip empty messages
        :ok

      size > @max_size ->
        # Ignore huge messages
        :ok

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
          state.socket,
          state.gl_host,
          state.port,
          data,
          id,
          :binary.encode_unsigned(num),
          0,
          size
        )

      true ->
        :gen_udp.send(state.socket, state.gl_host, state.port, data)
    end

    {:noreply, state}
  end

  def handle_cast({:configure, name, options}, state) do
    if state.socket do
      :gen_udp.close(state.socket)
    end

    state = GelfLogger.Config.configure(name, options)
    :persistent_term.put(:gelf_logger, {:configure, name, options})
    {:noreply, state}
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

  defp compress(data, :gzip), do: :zlib.gzip(data)
  defp compress(data, :zlib), do: :zlib.compress(data)
  defp compress(data, _), do: data

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
