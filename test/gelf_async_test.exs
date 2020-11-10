defmodule Logger.Backends.GelfAsyncTest do
  require Logger

  use ExUnit.Case, async: false
  doctest Logger.Backends.GelfAsync

  @default_env Application.get_env(:logger, :gelf_logger)
  Logger.add_backend({Logger.Backends.GelfAsync, :gelf_logger})

  setup do
    {:ok, socket} = :gen_udp.open(0, [:binary, active: true])
    {:ok, port} = :inet.port(socket)

    {:ok, [socket: socket, port: port]}
  end

  test "sends a message via udp", context do
    reconfigure_backend(port: context[:port])

    Logger.warn("test")

    assert_receive {:udp, _socket, address, _port, packet}, 2000

    # Should be coming from localhost
    assert address == {127, 0, 0, 1}

    map = process_packet(packet)

    assert map["version"] == "1.1"
    assert map["_application"] == "myapp"
    assert map["short_message"] == "test"
    assert map["full_message"] == "test"
  end

  test "convert port from binary to integer", context do
    reconfigure_backend(port: to_string(context[:port]))

    Logger.info("test")

    assert_receive {:udp, _socket, _address, _port, packet}, 2000

    map = process_packet(packet)

    assert map["version"] == "1.1"
    assert map["_application"] == "myapp"
    assert map["short_message"] == "test"
    assert map["full_message"] == "test"
  end

  test "convert domain from list to binary", context do
    if Version.compare(System.version(), "1.10.0") in [:gt, :eq] do
      reconfigure_backend(metadata: :all, port: context[:port])

      Logger.info("test")

      assert_receive {:udp, _socket, _address, _port, packet}, 2000

      assert %{"_domain" => "[:elixir]"} = process_packet(packet)
    end
  end

  test "configurable source (host)", context do
    reconfigure_backend(hostname: "host-dev-1", port: context[:port])

    Logger.info("test")

    assert_receive {:udp, _socket, _address, _port, packet}, 2000

    map = process_packet(packet)

    assert map["host"] == "host-dev-1"
  end

  test "configurable tags", context do
    reconfigure_backend(tags: [foo: "bar", baz: "qux"], port: context[:port])

    Logger.info("test")

    assert_receive {:udp, _socket, _address, _port, packet}, 2000

    map = process_packet(packet)

    assert map["_foo"] == "bar"
    assert map["_baz"] == "qux"
  end

  test "configurable metadata", context do
    reconfigure_backend(metadata: [:this], port: context[:port])

    Logger.metadata(this: "that", something: "else")
    Logger.info("test")

    assert_receive {:udp, _socket, _address, _port, packet}, 2000

    map = process_packet(packet)

    assert map["_application"] == "myapp"
    assert map["_this"] == "that"
    assert map["_something"] == nil
  end

  test "all metadata possible", context do
    reconfigure_backend(metadata: :all, port: context[:port])

    Logger.metadata(this: "that", something: "else")
    Logger.info("test")

    assert_receive {:udp, _socket, _address, _port, packet}, 2000

    map = process_packet(packet)

    assert map["_application"] == "myapp"
    assert map["_this"] == "that"
    assert map["_something"] == "else"
  end

  test "format message", context do
    reconfigure_backend(format: "[$level] $message", port: context[:port])

    Logger.info("test")

    assert_receive {:udp, _socket, _address, _port, packet}, 2000

    map = process_packet(packet)

    assert map["short_message"] == "[info] test"
    assert map["full_message"] == "[info] test"
  end

  test "skip empty messages", context do
    reconfigure_backend(format: "", port: context[:port])

    Logger.info("test")

    refute_receive {:udp, _socket, _address, _port, _packet}, 2000
  end

  test "short message should cap at 80 characters", context do
    reconfigure_backend(port: context[:port])

    Logger.info(
      "This is a test string that is over eighty characters but only because I kept typing garbage long after I had run out of things to say"
    )

    assert_receive {:udp, _socket, _address, _port, packet}, 2000

    map = process_packet(packet)

    assert map["short_message"] != map["full_message"]
    assert String.length(map["short_message"]) <= 80
  end

  test "log levels are being set correctly", context do
    reconfigure_backend(port: context[:port])

    # DEBUG
    Logger.debug("debug")

    assert_receive {:udp, _socket, _address, _port, packet}, 2000

    map = process_packet(packet)

    assert map["level"] == 7

    # INFO
    Logger.info("info")

    assert_receive {:udp, _socket, _address, _port, packet}, 2000

    map = process_packet(packet)

    assert map["level"] == 6

    # WARN
    Logger.warn("warn")

    assert_receive {:udp, _socket, _address, _port, packet}, 2000

    map = process_packet(packet)

    assert map["level"] == 4

    # ERROR
    Logger.error("error")

    assert_receive {:udp, _socket, _address, _port, packet}, 2000

    map = process_packet(packet)

    assert map["level"] == 3
  end

  test "should ignore the log if max message size is exceeded", context do
    reconfigure_backend(port: context[:port])
    Logger.info(:crypto.strong_rand_bytes(2_000_000) |> :base64.encode())
    refute_receive {:udp, _socket, _address, _port, _packet}, 2000
  end

  test "using compression gzip", context do
    reconfigure_backend(compression: :gzip, port: context[:port])

    Logger.info("test gzip")

    assert_receive {:udp, _socket, _address, _port, packet}, 2000

    {:error, _} = Poison.decode(packet)

    map = process_packet(packet)

    assert(map["full_message"] == "test gzip")
  end

  test "using compression zlib", context do
    reconfigure_backend(compression: :zlib, port: context[:port])

    Logger.info("test zlib")

    assert_receive {:udp, _socket, _address, _port, packet}, 2000

    {:error, _} = Poison.decode(packet)

    map = process_packet(packet)

    assert(map["full_message"] == "test zlib")
  end

  test "switching JSON encoder", context do
    reconfigure_backend(json_encoder: Jason, port: context[:port])

    Logger.info("test different encoder")

    assert_receive {:udp, _socket, _address, _port, packet}, 2000

    map = process_packet(packet)

    assert(map["full_message"] == "test different encoder")
  end

  test "can use custom formatter", context do
    reconfigure_backend(
      format: {Test.Support.LogFormatter, :format},
      metadata: :all,
      port: context[:port]
    )

    Logger.info("test formatter callback")

    assert_receive {:udp, _socket, _address, _port, packet}, 2000

    map = process_packet(packet)

    assert(Map.has_key?(map, "_timestamp_us"))
  end

  test "cannot use nonexistent custom formatter", context do
    reconfigure_backend(
      format: {Test.Support.LogFormatter, :bad_format},
      metadata: :all,
      port: context[:port]
    )

    Logger.info("test bad formatter callback")

    assert_receive {:udp, _socket, _address, _port, packet}, 2000

    map = process_packet(packet)

    refute(Map.has_key?(map, "_timestamp_us"))
    assert(map["full_message"] == "test bad formatter callback")
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

  defp reconfigure_backend(new_env) do
    Logger.remove_backend({Logger.Backends.GelfAsync, :gelf_logger})
    Application.put_env(:logger, :gelf_logger, Keyword.merge(@default_env, new_env))
    Logger.add_backend({Logger.Backends.GelfAsync, :gelf_logger})
    :ok
  end
end
