defmodule ECache do
  @moduledoc """
  Distributed cache implementation using local ETS storage with Redis-based PubSub
  for cross-node invalidation.

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
        ttl: 3600,              # Default TTL in seconds (1 hour)
        error_ttl: 60,          # Error cache TTL in seconds (1 minute)
        pubsub_mod: ECache.PubSub

  ### 3. Add dependencies to mix.exs

      defp deps do
        [
          {:phoenix_pubsub, "~> 2.1"},
          {:phoenix_pubsub_redis, "~> 3.0"}
        ]
      end

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
    try do
      case :ets.lookup(@table_name, cache_key) do
        [{^cache_key, value, expires_at}] ->
          if System.system_time(:second) < expires_at do
            {:ok, value}
          else
            :ets.delete(@table_name, cache_key)
            :miss
          end

        [] ->
          :miss
      end
    catch
      kind, reason ->
        Logger.error("Cache get failed: #{inspect({kind, reason})}")
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
    try do
      ttl = Keyword.get(opts, :ttl, @default_ttl)
      expires_at = System.system_time(:second) + ttl
      :ets.insert(@table_name, {cache_key, value, expires_at})
      :ok
    catch
      kind, reason ->
        Logger.error("Cache put failed: #{inspect({kind, reason})}")
        :ok
    end
  end

  @doc """
  Delete value from cache and broadcast invalidation.

  Removes the key from local ETS storage and broadcasts an invalidation
  message to all other nodes in the cluster via PubSub.

  ## Examples

      ECache.delete("user:123")
      # => :ok (removes locally and notifies other nodes)

      ECache.delete("nonexistent")
      # => :ok (no-op, but still broadcasts)
  """
  @spec delete(cache_key :: term()) :: :ok
  def delete(cache_key) do
    try do
      :ets.delete(@table_name, cache_key)
      broadcast_invalidation(cache_key)
      :ok
    catch
      kind, reason ->
        Logger.error("Cache delete failed: #{inspect({kind, reason})}")
        :ok
    end
  end

  @doc """
  Start the cache GenServer.

  This should be added to your application's supervision tree.
  The GenServer manages the ETS table, PubSub subscriptions, and cleanup tasks.

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
    # Create ETS table
    :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])

    # Subscribe to PubSub for invalidation messages
    Phoenix.PubSub.subscribe(@pubsub, @topic)

    # Start cleanup timer
    schedule_cleanup()

    {:ok, %{}}
  end

  @impl true
  def handle_info({:invalidate, cache_key}, state) do
    # Handle invalidation message from other nodes
    :ets.delete(@table_name, cache_key)
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
    try do
      current_time = System.system_time(:second)

      :ets.select_delete(@table_name, [
        {{:_, :_, :"$1"}, [{:<, :"$1", current_time}], [true]}
      ])
    catch
      kind, reason ->
        Logger.error("Cache cleanup failed: #{inspect({kind, reason})}")
    end
  end

  defp schedule_cleanup do
    # Run cleanup every 1 minutes
    Process.send_after(self(), :cleanup, 60_000)
  end
end
