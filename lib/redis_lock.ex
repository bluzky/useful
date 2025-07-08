defmodule RedisLock do
  @moduledoc """
  This module provide mechanism to lock resource using Redis within given TTL

  ## How to use

  1. Add RedisLock.Connection to `application.ex`

      def start(_type, _args) do
        children = [
          {RedisLock.Connection, ["redis://localhost:6379/3]}
        ]

        opts = [strategy: :one_for_one, name: MyApp.Supervisor]
        Supervisor.start_link(children, opts)
      end


  2. Acquire lock and release manually

      with {:ok, mutex} <- RedisLock.lock("update_order", order.id, 60) do
        MyApp.update_order(order, attrs)
        RedisLock.unlock(mutex)
      end

  3. Use `with_lock()` to wrap your execution code and it will handle exception

      RedisLock.with_lock("update_order", order.id, 60, fn ->
        MyApp.update_order(order, attrs)
      end)
  """

  @connection Opollo.Service.RedisLock.Connection
  @prefix "global_lock"

  @unlock_script """
  if redis.call("get", KEYS[1]) == ARGV[1] then
    return redis.call("del", KEYS[1])
  else
    return 0
  end
  """

  @doc """
  Lock resource using redis for given ttl in seconds

  ## Example

     lock("order", "SPP1", 60)
  """
  def lock(name_space, id, ttl) when is_integer(ttl) and ttl > 0 do
    key = build_key(name_space, id)
    random = :rand.uniform(999_999_999)

    case Redix.command(@connection, ["SET", key, random, "NX", "EX", ttl]) do
      {:ok, "OK"} ->
        {:ok, {key, random}}

      _err ->
        remaining_time =
          case Redix.command(@connection, ["TTL", key]) do
            {:ok, val} when val > 0 -> val
            _ -> :unknown
          end

        {:error,
         "Failed to acquired lock on #{inspect({name_space, id})}. Unlocking in #{remaining_time}s"}
    end
  end

  @doc """
  Unlock given mutex resource, with muxte return by `lock/3`

  ## Example

     mutex = lock("order", "SPE", 60)
     # do something with resource
     unlock(mutex)
  """
  def unlock({key, value}) do
    case Redix.command!(@connection, ["EVAL", @unlock_script, 1, key, value]) do
      1 -> :ok
      0 -> {:error, "Failed to unlock resource #{key}. Invalid mutex value"}
    end
  end

  @doc """
  Force release lock and ignore mutex value
  """
  def force_unlock(name_space, id) do
    key = build_key(name_space, id)

    case Redix.command(@connection, ["DEL", key]) do
      {:ok, _} -> :ok
      _ -> :error
    end
  end

  @doc """
  Try acquire lock, if succeeded, then execute given function.
  This helper function ensure to unlock resource after invoking function successfully or any exception occurs
  """
  def with_lock(name_space, id, ttl, func) do
    with {:ok, mutex} <- lock(name_space, id, ttl) do
      try do
        func.()
      after
        unlock(mutex)
      end
    end
  end

  # build redis key from namespace and id
  defp build_key(name_space, id) do
    if name_space in [nil, ""] or id in [nil, ""] do
      raise("[RedisLock] in valid namespace or id: #{inspect({name_space, id})}")
    else
      "#{@prefix}:#{name_space}_#{id}"
    end
  end
end

defmodule RedisLock.Connection do
  @moduledoc """
  This module connects to the Redis instance.
  """

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, opts},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  def start_link(uri) when is_binary(uri) do
    Redix.start_link(uri, name: __MODULE__, sync_connect: true)
  end

  def start_link(uri, opts) when is_list(opts) do
    opts = Keyword.merge([name: __MODULE__, sync_connect: true], opts)
    Redix.start_link(uri, opts)
  end
end
