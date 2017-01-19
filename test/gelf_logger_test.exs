defmodule GelfLoggerTest do
  require Logger

  use ExUnit.Case
  doctest Logger.Backends.Gelf

  Logger.add_backend({Logger.Backends.Gelf, :gelf_logger})

  setup do 
    {:ok, socket} = :gen_udp.open(12201, [:binary, {:active, false}])

    {:ok, [socket: socket]}
  end

  test "sends a message via udp", context do
    Logger.info "test"

    {:ok, {address, _port, packet}} = :gen_udp.recv(context[:socket], 0, 2000)
    
    # Should be coming from localhost
    assert address == {127,0,0,1}
    
    map = process_packet(packet)

    assert map["version"] == "1.1"
    assert map["_application"] == "myapp"
    assert map["short_message"] == "test"
    assert map["long_message"] == "test"
  end

  test "configurable source (host)", context do
    Logger.remove_backend({Logger.Backends.Gelf, :gelf_logger})

    Application.put_env(:logger, :gelf_logger,
    Application.get_env(:logger, :gelf_logger) |> Keyword.put(:hostname, 'host-dev-1'))

    Logger.add_backend({Logger.Backends.Gelf, :gelf_logger})

    Logger.info "test"

    {:ok, {address, _port, packet}} = :gen_udp.recv(context[:socket], 0, 2000)

    map = process_packet(packet)

    assert map["host"] == "host-dev-1"
  end

  test "short message should cap at 80 characters", context do
    Logger.info "This is a test string that is over eighty characters but only because I kept typing garbage long after I had run out of things to say"

    {:ok, {_address, _port, packet}} = :gen_udp.recv(context[:socket], 0, 2000)
    
     map = process_packet(packet)

    assert map["short_message"] != map["long_message"]
    assert String.length(map["short_message"]) <= 80
  end

  test "log levels are being set correctly", context do
    # DEBUG
    Logger.debug "debug"

    {:ok, {_address, _port, packet}} = :gen_udp.recv(context[:socket], 0, 2000)

    map = process_packet(packet)

    assert map["level"] == 7

    # INFO
    Logger.info "info"

    {:ok, {_address, _port, packet}} = :gen_udp.recv(context[:socket], 0, 2000)

    map = process_packet(packet)

    assert map["level"] == 6 

    # WARN
    Logger.warn "warn"

    {:ok, {_address, _port, packet}} = :gen_udp.recv(context[:socket], 0, 2000)

    map = process_packet(packet)

    assert map["level"] == 4

    # ERROR
    Logger.error "error"

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

  test "using compression", context do
    # First for gzip
    Logger.remove_backend({Logger.Backends.Gelf, :gelf_logger})

    Application.put_env(:logger, :gelf_logger,
    Application.get_env(:logger, :gelf_logger) |> Keyword.put(:compression, :gzip))

    Logger.add_backend({Logger.Backends.Gelf, :gelf_logger})

    Logger.info "test gzip"

    {:ok, {_address, _port, packet}} = :gen_udp.recv(context[:socket], 0, 2000)

    {:error, _ } = Poison.decode(packet)

    map = process_packet(packet)

    assert(map["long_message"] == "test gzip")

    # Now, for zlib
    Logger.remove_backend({Logger.Backends.Gelf, :gelf_logger})

    Application.put_env(:logger, :gelf_logger,
    Application.get_env(:logger, :gelf_logger) |> Keyword.put(:compression, :zlib))

    Logger.add_backend({Logger.Backends.Gelf, :gelf_logger})

    Logger.info "test zlib"

    {:ok, {_address, _port, packet}} = :gen_udp.recv(context[:socket], 0, 2000)

    {:error, _ } = Poison.decode(packet)

    map = process_packet(packet)

    assert(map["long_message"] == "test zlib")
  end

  defp process_packet(packet) do
    compression = Application.get_env(:logger, :gelf_logger)[:compression]

    data = case compression do
      :gzip -> :zlib.gunzip(packet)
      :zlib -> :zlib.uncompress(packet)
      _ -> packet
    end

    {:ok,  map} = Poison.decode(data |> to_string)

    map
  end
end
