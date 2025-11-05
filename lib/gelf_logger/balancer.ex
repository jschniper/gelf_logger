defmodule GelfLogger.Balancer do
  use GenServer

  @supervisor GelfLogger.Pool
  @worker GelfLogger.Worker

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def start_new_child() do
    DynamicSupervisor.start_child(@supervisor, @worker)
  end

  def configure(name, options) do
    if Process.whereis(__MODULE__) do
      GenServer.cast(__MODULE__, {:configure, name, options})
    else
      :persistent_term.put(:gelf_logger, {:configure, name, options})
    end
  end

  def cast(level, msg, ts, md) do
    GenServer.cast(__MODULE__, {:cast, level, msg, ts, md})
  end

  @impl GenServer
  def init(opts) do
    pool_size =
      opts[:pool_size] ||
        raise """
        Gelf Logger: Not provided pool_size configuration!
        """

    pids =
      for _ <- 1..pool_size do
        {:ok, pid} = start_new_child()
        Process.monitor(pid)
        pid
      end

    {:ok, pids}
  end

  @impl GenServer
  def handle_cast({:cast, level, msg, ts, md}, [pid | pids]) do
    :ok = GenServer.cast(pid, [level, msg, ts, md])
    {:noreply, pids ++ [pid]}
  end

  def handle_cast({:configure, name, options}, pids) do
    for pid <- pids, do: GenServer.cast(pid, {:configure, name, options})
    {:noreply, pids}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, old_pid, _reason}, pids) do
    {:ok, new_pid} = start_new_child()
    {:noreply, [new_pid | pids -- [old_pid]]}
  end

  @impl GenServer
  def terminate(_reason, pids) do
    Enum.each(pids, &GenServer.stop/1)
    :ok
  end
end
