defmodule GelfLoggerTest do
  use ExUnit.Case
  doctest Logger.Backends.Gelf

  test "the truth" do
    assert 1 + 1 == 2
  end
end
