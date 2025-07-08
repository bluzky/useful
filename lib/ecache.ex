defmodule ECache do
  @moduledoc """
  Distributed cache implementation with pluggable storage adapters (ETS or Mnesia)
  and Redis-based PubSub for cross-node invalidation.

  ## Setup

  ### 1. Add to your application supervision tree

      def start(_type, _args) do
        children = [
          # Start PubSub first
          {Phoenix.PubSub, [
            name: ECache.PubSub,
            adapter: Phoenix.PubSub.Redis,
            redis_url: System.get_env("REDIS_URL", "redis://localhost:6379")
          ]},
          # Then start the cache
          ECache,
          # ... other children
        ]

        Supervisor.start_link(children, strategy: :one_for_one)
      end

  ### 2. Configure in your config files

      # config/config.exs
      config :ecache,
        adapter: ECache.Adapters.ETS,     # or ECache.Adapters.Mnesia
        ttl: 3600,                        # Default TTL in seconds (1 hour)
        error_ttl: 60,                    # Error cache TTL in seconds (1 minute)
        pubsub_mod: ECache.PubSub

  ### 3. Add dependencies to mix.exs

      defp deps do
        [
          {:phoenix_pubsub, "~> 2.1"},
          {:phoenix_pubsub_redis, "~> 3.0"}
        ]
      end

  ## Storage Adapters

  ### ETS Adapter
  - Fast in-memory storage
  - Single node only
  - No persistence
  - Best for development and single-node deployments

  ### Mnesia Adapter
  - Distributed storage across nodes
  - Optional disk persistence
  - ACID transactions
  - Best for multi-node production deployments

  ## Usage

      # Cache with fallback
      ECache.load_cache("user:123", [], fn ->
        fetch_user_from_db(123)
      end)

      # Conditional invalidation
      ECache.invalidate_cache("user:123", fn ->
        update_user_in_db(123, changes)
      end)

      # Manual operations
      ECache.put("key", "value", ttl: 300)
      ECache.get("key")
      ECache.delete("key")
  """

  use GenServer
  require Logger

  @table_name :distributed_cache
  @topic "cache_invalidation"
  @default_ttl Application.compile_env(:ecache, :ttl, 3600)
  @default_error_ttl Application.compile_env(:ecache, :error_ttl, 60)
  @pubsub Application.compile_env(:ecache, :pubsub_mod, ECache.PubSub)
  @adapter Application.compile_env(:ecache, :adapter, ECache.Adapters.ETS)

  defp adapter(), do: Application.get_env(:ecache, :adapter, @adapter)
  defp table_name(), do: :persistent_term.get({__MODULE__, :table_name}, @table_name)

  ## Storage Adapter Behaviour

  @callback init_storage(table_name :: atom()) :: :ok | {:error, term()}
  @callback get(table_name :: atom(), key :: term()) ::
              {:ok, {value :: term(), expires_at :: integer()}} | :miss | {:error, term()}
  @callback put(table_name :: atom(), key :: term(), value :: term(), expires_at :: integer()) ::
              :ok | {:error, term()}
  @callback delete(table_name :: atom(), key :: term()) :: :ok | {:error, term()}
  @callback cleanup_expired(table_name :: atom(), current_time :: integer()) ::
              :ok | {:error, term()}
  @callback clear(table_name :: atom()) :: :ok | {:error, term()}
  @callback stats(table_name :: atom()) :: map()

  ## Public API

  @doc """
  Load cache with fallback function.
  Caches successful results and handles errors gracefully.

  ## Options

  * `:ttl` - Time to live in seconds. Defaults to configured default (3600s)
  * `:cache_errors` - Whether to cache error results. Defaults to `false`
  * `:error_ttl` - TTL for cached errors in seconds. Defaults to configured default (60s)

  ## Examples

      # Simple cache with fallback
      ECache.load_cache("user:123", [], fn ->
        Database.get_user(123)
      end)
      # => {:ok, %User{}}

      # With custom TTL
      ECache.load_cache("session:abc", [ttl: 300], fn ->
        SessionStore.get("abc")
      end)

      # Cache errors for 30 seconds
      ECache.load_cache("api:data", [cache_errors: true, error_ttl: 30], fn ->
        ExternalAPI.fetch_data()
      end)
  """
  @spec load_cache(cache_key :: term(), opts :: keyword(), loader_fn :: function()) ::
          {:ok, term()} | {:error, term()}
  def load_cache(cache_key, opts \\ [], loader_fn) do
    try do
      case get(cache_key) do
        {:ok, value} ->
          {:ok, value}

        :miss ->
          case execute_loader(loader_fn) do
            {:ok, value} ->
              put(cache_key, value, opts)
              {:ok, value}

            {:error, _} = error ->
              maybe_cache_error(cache_key, error, opts)
              error

            nil ->
              {:error, :nil_result}

            value ->
              put(cache_key, value, opts)
              {:ok, value}
          end
      end
    catch
      kind, reason ->
        Logger.error("Cache load_cache failed: #{inspect({kind, reason})}")
        {:error, {kind, reason}}
    end
  end

  @doc """
  Execute operation and conditionally invalidate cache based on result.

  Only invalidates the cache if the operation returns `:ok` or `{:ok, value}`.
  For any other result, the cache remains unchanged.

  ## Examples

      # Cache will be invalidated if update succeeds
      ECache.invalidate_cache("user:123", fn ->
        Database.update_user(123, %{name: "John"})
      end)
      # => {:ok, updated_user} (cache invalidated)

      # Cache remains if operation fails
      ECache.invalidate_cache("user:123", fn ->
        {:error, :not_found}
      end)
      # => {:error, :not_found} (cache unchanged)

      # Also works with plain :ok
      ECache.invalidate_cache("stats", fn ->
        clear_statistics()
        :ok
      end)
      # => :ok (cache invalidated)
  """
  @spec invalidate_cache(cache_key :: term(), operation_fn :: function()) :: term()
  def invalidate_cache(cache_key, operation_fn) do
    try do
      result = operation_fn.()

      case result do
        {:ok, _} ->
          delete(cache_key)
          result

        :ok ->
          delete(cache_key)
          result

        _ ->
          result
      end
    catch
      kind, reason ->
        Logger.error("Cache invalidate_cache operation failed: #{inspect({kind, reason})}")
        {:error, {kind, reason}}
    end
  end

  @doc """
  Get value from cache.

  Returns `{:ok, value}` if the key exists and hasn't expired.
  Returns `:miss` if the key doesn't exist or has expired.
  Expired entries are automatically cleaned up when accessed.

  ## Examples

      ECache.get("user:123")
      # => {:ok, %User{id: 123}}

      ECache.get("nonexistent")
      # => :miss

      ECache.get("expired_key")
      # => :miss (and removes expired entry)
  """
  @spec get(cache_key :: term()) :: {:ok, term()} | :miss
  def get(cache_key) do
    case adapter().get(table_name(), cache_key) do
      {:ok, {value, expires_at}} ->
        if System.system_time(:second) < expires_at do
          {:ok, value}
        else
          adapter().delete(table_name(), cache_key)
          :miss
        end

      :miss ->
        :miss

      {:error, reason} ->
        Logger.error("Cache get failed: #{inspect(reason)}")
        :miss
    end
  end

  @doc """
  Put value in cache with optional TTL.

  ## Options

  * `:ttl` - Time to live in seconds. Defaults to configured default (3600s)

  ## Examples

      # Use default TTL
      ECache.put("user:123", user_data)
      # => :ok

      # Custom TTL of 5 minutes
      ECache.put("session:abc", session_data, ttl: 300)
      # => :ok

      # Short-lived cache (30 seconds)
      ECache.put("temp:data", temp_value, ttl: 30)
      # => :ok
  """
  @spec put(cache_key :: term(), value :: term(), opts :: keyword()) :: :ok
  def put(cache_key, value, opts \\ []) do
    ttl = Keyword.get(opts, :ttl, @default_ttl)
    expires_at = System.system_time(:second) + ttl

    case adapter().put(table_name(), cache_key, value, expires_at) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("Cache put failed: #{inspect(cache_key)} reason: #{inspect(reason)}")
        :ok
    end
  end

  @doc """
  Delete value from cache and broadcast invalidation.

  Removes the key from storage and broadcasts an invalidation
  message to all other nodes in the cluster via PubSub.

  ## Examples

      ECache.delete("user:123")
      # => :ok (removes locally and notifies other nodes)

      ECache.delete("nonexistent")
      # => :ok (no-op, but still broadcasts)
  """
  @spec delete(cache_key :: term()) :: :ok
  def delete(cache_key) do
    case adapter().delete(table_name(), cache_key) do
      :ok ->
        broadcast_invalidation(cache_key)
        :ok

      {:error, reason} ->
        Logger.error("Cache delete failed: #{inspect(reason)}")
        :ok
    end
  end

  @doc """
  Clear all cache entries.

  ## Examples

      ECache.clear()
      # => :ok
  """
  @spec clear() :: :ok
  def clear do
    case adapter().clear(table_name()) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("Cache clear failed: #{inspect(reason)}")
        :ok
    end
  end

  @doc """
  Get cache statistics.

  ## Examples

      ECache.stats()
      # => %{size: 1234, memory: 56789}
  """
  @spec stats() :: map()
  def stats do
    adapter().stats(table_name())
  end

  @doc """
  Start the cache GenServer.

  This should be added to your application's supervision tree.
  The GenServer manages the storage, PubSub subscriptions, and cleanup tasks.

  ## Examples

      # In your application.ex
      children = [
        ECache,
        # ... other children
      ]
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  ## GenServer Callbacks

  @impl true
  def init(_opts) do
    # Initialize storage adapter
    case adapter().init_storage(table_name()) do
      :ok ->
        Logger.info("Initialized cache with #{adapter()} adapter")

      {:error, reason} ->
        Logger.error("Failed to initialize cache storage: #{inspect(reason)}")
        {:stop, reason}
    end

    # Subscribe to PubSub for invalidation messages
    Phoenix.PubSub.subscribe(@pubsub, @topic)

    # Start cleanup timer
    schedule_cleanup()

    {:ok, %{}}
  end

  @impl true
  def handle_info({:invalidate, cache_key}, state) do
    # Handle invalidation message from other nodes
    adapter().delete(table_name(), cache_key)
    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired_entries()
    schedule_cleanup()
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Cache received unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  ## Private Functions

  defp execute_loader(loader_fn) do
    try do
      loader_fn.()
    catch
      kind, reason ->
        Logger.error("Cache loader function failed: #{inspect({kind, reason})}")
        {:error, {kind, reason}}
    end
  end

  defp maybe_cache_error(cache_key, error, opts) do
    if Keyword.get(opts, :cache_errors, false) do
      error_ttl = Keyword.get(opts, :error_ttl, @default_error_ttl)
      put(cache_key, error, ttl: error_ttl)
    end
  end

  defp broadcast_invalidation(cache_key) do
    try do
      Phoenix.PubSub.broadcast(@pubsub, @topic, {:invalidate, cache_key})
    catch
      kind, reason ->
        Logger.error("Cache broadcast failed: #{inspect({kind, reason})}")
    end
  end

  defp cleanup_expired_entries do
    current_time = System.system_time(:second)

    case adapter().cleanup_expired(table_name(), current_time) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("Cache cleanup failed: #{inspect(reason)}")
    end
  end

  defp schedule_cleanup do
    # Run cleanup every 1 minute
    Process.send_after(self(), :cleanup, 60_000)
  end
end

defmodule ECache.Adapters.ETS do
  @moduledoc """
  ETS storage adapter for ECache.
  Provides fast in-memory storage for single-node deployments.
  """

  require Logger
  @behaviour ECache

  @impl true
  def init_storage(table_name) do
    try do
      :ets.new(table_name, [:set, :public, :named_table, read_concurrency: true])
      :ok
    catch
      :error, :badarg ->
        # Table might already exist
        :ok
    end
  end

  @impl true
  def get(table_name, key) do
    try do
      case :ets.lookup(table_name, key) do
        [{^key, value, expires_at}] ->
          {:ok, {value, expires_at}}

        [] ->
          :miss
      end
    catch
      kind, reason ->
        {:error, {kind, reason}}
    end
  end

  @impl true
  def put(table_name, key, value, expires_at) do
    try do
      :ets.insert(table_name, {key, value, expires_at})
      :ok
    catch
      kind, reason ->
        {:error, {kind, reason}}
    end
  end

  @impl true
  def delete(table_name, key) do
    try do
      :ets.delete(table_name, key)
      :ok
    catch
      kind, reason ->
        {:error, {kind, reason}}
    end
  end

  @impl true
  def cleanup_expired(table_name, current_time) do
    try do
      :ets.select_delete(table_name, [
        {{:_, :_, :"$1"}, [{:"=<", :"$1", current_time}], [true]}
      ])

      :ok
    catch
      kind, reason ->
        {:error, {kind, reason}}
    end
  end

  @impl true
  def clear(table_name) do
    try do
      :ets.delete_all_objects(table_name)
      :ok
    catch
      kind, reason ->
        {:error, {kind, reason}}
    end
  end

  @impl true
  def stats(table_name) do
    try do
      info = :ets.info(table_name)

      %{
        size: Keyword.get(info, :size, 0),
        memory: Keyword.get(info, :memory, 0) * :erlang.system_info(:wordsize)
      }
    catch
      _kind, _reason ->
        %{size: 0, memory: 0}
    end
  end
end

defmodule ECache.Adapters.Mnesia do
  @moduledoc """
  Mnesia storage adapter for ECache.
  Provides distributed storage with optional persistence for multi-node deployments.
  """
  require Logger
  @behaviour ECache

  @impl true
  def init_storage(table_name) do
    try do
      # Create schema if it doesn't exist
      case :mnesia.create_schema([node()]) do
        :ok ->
          Logger.info("Created Mnesia schema")

        {:error, {_, {:already_exists, _}}} ->
          :ok

        {:error, reason} ->
          Logger.warning("Mnesia schema creation issue: #{inspect(reason)}")
      end

      :ok = :mnesia.start()

      # Create table if it doesn't exist
      case :mnesia.create_table(table_name,
             attributes: [:key, :value, :expires_at],
             type: :set,
             storage_properties: [
               ets: [read_concurrency: true, write_concurrency: true]
             ]
           ) do
        {:atomic, :ok} ->
          Logger.info("Created Mnesia table: #{table_name}")
          :ok

        {:aborted, {:already_exists, ^table_name}} ->
          :ok

        {:aborted, reason} ->
          {:error, reason}
      end
    catch
      kind, reason ->
        {:error, {kind, reason}}
    end
  end

  @impl true
  def get(table_name, key) do
    try do
      case :mnesia.dirty_read(table_name, key) do
        [{^table_name, ^key, value, expires_at}] ->
          {:ok, {value, expires_at}}

        [] ->
          :miss
      end
    catch
      kind, reason ->
        {:error, {kind, reason}}
    end
  end

  @impl true
  def put(table_name, key, value, expires_at) do
    try do
      :mnesia.dirty_write(table_name, {table_name, key, value, expires_at})
      :ok
    catch
      kind, reason ->
        {:error, {kind, reason}}
    end
  end

  @impl true
  def delete(table_name, key) do
    try do
      :mnesia.dirty_delete(table_name, key)
      :ok
    catch
      kind, reason ->
        {:error, {kind, reason}}
    end
  end

  @impl true
  def cleanup_expired(table_name, current_time) do
    try do
      # Use Mnesia select to find expired keys
      match_spec = [
        {{table_name, :"$1", :"$2", :"$3"}, [{:<, :"$3", current_time}], [:"$1"]}
      ]

      expired_keys = :mnesia.dirty_select(table_name, match_spec)

      Enum.each(expired_keys, fn key ->
        :mnesia.dirty_delete(table_name, key)
      end)

      if length(expired_keys) > 0 do
        Logger.debug("Cleaned up #{length(expired_keys)} expired cache entries")
      end

      :ok
    catch
      kind, reason ->
        {:error, {kind, reason}}
    end
  end

  @impl true
  def clear(table_name) do
    try do
      :mnesia.clear_table(table_name)
      :ok
    catch
      kind, reason ->
        {:error, {kind, reason}}
    end
  end

  @impl true
  def stats(table_name) do
    try do
      info = :mnesia.table_info(table_name, :all)

      %{
        size: Keyword.get(info, :size, 0),
        memory: Keyword.get(info, :memory, 0) * :erlang.system_info(:wordsize)
      }
    catch
      _kind, _reason ->
        %{size: 0, memory: 0}
    end
  end
end
