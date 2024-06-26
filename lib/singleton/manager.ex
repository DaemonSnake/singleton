defmodule Singleton.Manager do
  @moduledoc """

  Singleton watchdog process

  Each node that the singleton runs on, runs this process. It is
  responsible for starting the singleton process (with the help of
  Erlang's 'global' module).

  When starting the singleton process fails, it instead monitors the
  process, so that in case it dies, it will try to start it locally.

  The singleton process is started using the `GenServer.start_link`
  call, with the given module and args.

  """

  use GenServer, restart: :transient

  require Logger

  @doc """
  Start the manager process, registering it under a unique name.
  """
  def start_link(spec) do
    GenServer.start_link(
      __MODULE__,
      [spec[:mod], spec[:args], spec[:name], spec[:on_conflict]],
      name: spec[:child_name]
    )
  end

  defmodule State do
    @moduledoc false
    defstruct pid: nil, mod: nil, args: nil, name: nil, on_conflict: nil
  end

  @doc false
  def init([mod, args, name, on_conflict]) do
    state = %State{mod: mod, args: args, name: name, on_conflict: on_conflict}

    try do
      {:ok, restart(state)}
    rescue
      err ->
        Logger.error(
          "Failed to start singleton manager: #{inspect(err, pretty: true)}"
        )

        raise err
    end
  end

  @doc false
  def handle_info({:DOWN, _, :process, pid, :normal}, state = %State{pid: pid}) do
    # Managed process exited normally. Shut manager down as well.
    {:stop, :normal, state}
  end

  def handle_info({:DOWN, _, :process, pid, reason}, state = %State{pid: pid}) do
    # Managed process exited with an error. Try restarting, after a delay
    Logger.error(
      "Singleton process #{state.name} died: #{inspect(reason, pretty: true)}"
    )

    Process.sleep(:rand.uniform(5_000) + 5_000)
    {:noreply, restart(state)}
  end

  defp restart(state) do
    start_result =
      GenServer.start_link(state.mod, state.args, name: {:global, state.name})

    pid =
      case start_result do
        {:ok, pid} ->
          pid

        {:error, {:already_started, pid}} ->
          state.on_conflict && state.on_conflict.()
          pid
      end

    Process.monitor(pid)
    %State{state | pid: pid}
  end
end
