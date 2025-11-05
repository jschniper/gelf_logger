defmodule GelfLogger.Application do
  @moduledoc false
  use Application

  @default_pool_size 5

  defp pool_size() do
    Application.get_env(:logger, :gelf_logger)[:pool_size] || @default_pool_size
  end

  @impl Application
  def start(_type, _args) do
    children = [
      {DynamicSupervisor, strategy: :one_for_one, name: GelfLogger.Pool},
      {GelfLogger.Balancer, [pool_size: pool_size()]}
    ]

    options = [strategy: :one_for_one, name: GelfLogger.Supervisor]
    Supervisor.start_link(children, options)
  end
end
