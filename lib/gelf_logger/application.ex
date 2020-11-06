defmodule GelfLogger.Application do
  @moduledoc false
  use Application

  @impl Application
  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: GelfLogger.Pool}
    ]

    options = [strategy: :one_for_one, name: GelfLogger.Supervisor]
    Supervisor.start_link(children, options)
  end
end
