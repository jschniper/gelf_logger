defmodule Test.Support.LogFormatter do
  @moduledoc """
  Provides a set of test helping functions for logged message transformation.
  """

  @doc """
  Main function of the formatter.
  """
  @spec format(atom(), list(), tuple(), list()) :: {atom(), list(), tuple(), list()}
  def format(level, message, timestamp, metadata) do
    metadata = add_us_precision_timestamp_to_metadata(metadata)
    {level, message, timestamp, metadata}
  end

  # helpers
  defp add_us_precision_timestamp_to_metadata(metadata) do
    Keyword.merge(metadata, timestamp_us: :os.system_time(:micro_seconds))
  end
end
