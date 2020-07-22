defmodule GelfLoggerTest do
  require Logger

  use ExUnit.Case, async: true
  doctest Logger.Backends.Gelf

  @default_env Application.get_env(:logger, :gelf_logger)
  Logger.add_backend({Logger.Backends.Gelf, :gelf_logger})

  setup do
    {:ok, socket} = :gen_udp.open(12201, [:binary, {:active, false}])

    {:ok, [socket: socket]}
  end

  test "sends a message via udp", context do
    reconfigure_backend()

    Logger.info("test")

    {:ok, {address, _port, packet}} = :gen_udp.recv(context[:socket], 0, 2000)

    # Should be coming from localhost
    assert address == {127, 0, 0, 1}

    map = process_packet(packet)

    assert map["version"] == "1.1"
    assert map["_application"] == "myapp"
    assert map["short_message"] == "test"
    assert map["long_message"] == "test"
  end

  test "convert port from binary to integer", context do
    reconfigure_backend(port: "12201")

    Logger.info("test")

    {:ok, {_address, _port, packet}} = :gen_udp.recv(context[:socket], 0, 2000)

    map = process_packet(packet)

    assert map["version"] == "1.1"
    assert map["_application"] == "myapp"
    assert map["short_message"] == "test"
    assert map["long_message"] == "test"
  end

  test "convert domain from list to binary", context do
    reconfigure_backend(metadata: :all)

    Logger.info("test")
    {:ok, {_address, _port, packet}} = :gen_udp.recv(context[:socket], 0, 2000)

    assert %{"_domain" => "[:elixir]"} = process_packet(packet)
  end

  test "configurable source (host)", context do
    reconfigure_backend(hostname: 'host-dev-1')

    Logger.info("test")

    {:ok, {_address, _port, packet}} = :gen_udp.recv(context[:socket], 0, 2000)

    map = process_packet(packet)

    assert map["host"] == "host-dev-1"
  end

  test "configurable tags", context do
    reconfigure_backend(tags: [foo: "bar", baz: "qux"])

    Logger.info("test")

    {:ok, {_address, _port, packet}} = :gen_udp.recv(context[:socket], 0, 2000)

    map = process_packet(packet)

    assert map["_foo"] == "bar"
    assert map["_baz"] == "qux"
  end

  test "configurable metadata", context do
    reconfigure_backend(metadata: [:this])

    Logger.metadata(this: "that", something: "else")
    Logger.info("test")

    {:ok, {_address, _port, packet}} = :gen_udp.recv(context[:socket], 0, 2000)

    map = process_packet(packet)

    assert map["_application"] == "myapp"
    assert map["_this"] == "that"
    assert map["_something"] == nil
  end

  test "all metadata possible", context do
    reconfigure_backend(metadata: :all)

    Logger.metadata(this: "that", something: "else")
    Logger.info("test")

    {:ok, {_address, _port, packet}} = :gen_udp.recv(context[:socket], 0, 2000)

    map = process_packet(packet)

    assert map["_application"] == "myapp"
    assert map["_this"] == "that"
    assert map["_something"] == "else"
  end

  test "format message", context do
    reconfigure_backend(format: "[$level] $message")

    Logger.info("test")

    {:ok, {_address, _port, packet}} = :gen_udp.recv(context[:socket], 0, 2000)

    map = process_packet(packet)

    assert map["short_message"] == "[info] test"
    assert map["long_message"] == "[info] test"
  end

  test "skip empty messages", context do
    reconfigure_backend(format: "")

    Logger.info("test")

    assert {:error, :timeout} == :gen_udp.recv(context[:socket], 0, 1000)
  end

  test "short message should cap at 80 characters", context do
    reconfigure_backend()

    Logger.info(
      "This is a test string that is over eighty characters but only because I kept typing garbage long after I had run out of things to say"
    )

    {:ok, {_address, _port, packet}} = :gen_udp.recv(context[:socket], 0, 2000)

    map = process_packet(packet)

    assert map["short_message"] != map["long_message"]
    assert String.length(map["short_message"]) <= 80
  end

  test "log levels are being set correctly", context do
    reconfigure_backend()

    # DEBUG
    Logger.debug("debug")

    {:ok, {_address, _port, packet}} = :gen_udp.recv(context[:socket], 0, 2000)

    map = process_packet(packet)

    assert map["level"] == 7

    # INFO
    Logger.info("info")

    {:ok, {_address, _port, packet}} = :gen_udp.recv(context[:socket], 0, 2000)

    map = process_packet(packet)

    assert map["level"] == 6

    # WARN
    Logger.warn("warn")

    {:ok, {_address, _port, packet}} = :gen_udp.recv(context[:socket], 0, 2000)

    map = process_packet(packet)

    assert map["level"] == 4

    # ERROR
    Logger.error("error")

    {:ok, {_address, _port, packet}} = :gen_udp.recv(context[:socket], 0, 2000)

    map = process_packet(packet)

    assert map["level"] == 3
  end

  # The Logger module truncates all messages over 8192 bytes so this can't be tested
  test "should raise error if max message size is exceeded" do
    # assert_raise(ArgumentError, "Message too large", fn ->
    #   Logger.info :crypto.rand_bytes(1000000) |> :base64.encode
    # end)
  end

  test "using compression gzip", context do
    reconfigure_backend(compression: :gzip)

    Logger.info("test gzip")

    {:ok, {_address, _port, packet}} = :gen_udp.recv(context[:socket], 0, 2000)

    {:error, _} = Poison.decode(packet)

    map = process_packet(packet)

    assert(map["long_message"] == "test gzip")
  end

  test "using compression zlib", context do
    reconfigure_backend(compression: :zlib)

    Logger.info("test zlib")

    {:ok, {_address, _port, packet}} = :gen_udp.recv(context[:socket], 0, 2000)

    {:error, _} = Poison.decode(packet)

    map = process_packet(packet)

    assert(map["long_message"] == "test zlib")
  end

  test "switching JSON encoder", context do
    reconfigure_backend(json_encoder: Jason)

    Logger.info("test different encoder")

    {:ok, {_address, _port, packet}} = :gen_udp.recv(context[:socket], 0, 2000)

    map = process_packet(packet)

    assert(map["long_message"] == "test different encoder")
  end

  test "can use custom formatter", context do
    reconfigure_backend(
      format: {Test.Support.LogFormatter, :format},
      metadata: :all
    )

    Logger.info("test formatter callback")

    {:ok, {_address, _port, packet}} = :gen_udp.recv(context[:socket], 0, 2000)

    map = process_packet(packet)

    assert(Map.has_key?(map, "_timestamp_us"))
  end

  test "cannot use nonexistent custom formatter", context do
    reconfigure_backend(
      format: {Test.Support.LogFormatter, :bad_format},
      metadata: :all
    )

    Logger.info("test bad formatter callback")

    {:ok, {_address, _port, packet}} = :gen_udp.recv(context[:socket], 0, 2000)

    map = process_packet(packet)

    refute(Map.has_key?(map, "_timestamp_us"))
    assert(map["long_message"] == "test bad formatter callback")
  end

  defp process_packet(packet) do
    compression = Application.get_env(:logger, :gelf_logger)[:compression]

    data =
      case compression do
        :gzip -> :zlib.gunzip(packet)
        :zlib -> :zlib.uncompress(packet)
        _ -> packet
      end

    {:ok, map} = Poison.decode(data |> to_string)

    map
  end

  defp reconfigure_backend(new_env \\ []) do
    Logger.remove_backend({Logger.Backends.Gelf, :gelf_logger})
    Application.put_env(:logger, :gelf_logger, Keyword.merge(@default_env, new_env))
    Logger.add_backend({Logger.Backends.Gelf, :gelf_logger})
    :ok
  end
end
