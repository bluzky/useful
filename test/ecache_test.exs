defmodule ECacheTest do
  # Changed to false due to PubSub setup
  use ExUnit.Case, async: false

  # Import test helpers
  import ExUnit.CaptureLog

  # Module setup - start PubSub once for all tests
  setup_all do
    # Start a single PubSub instance for all tests
    pubsub_name = ECache.PubSub

    {:ok, _pid} = start_supervised({Phoenix.PubSub, name: pubsub_name}, id: :test_pubsub)

    # Set the PubSub module for all tests
    Application.put_env(:ecache, :pubsub_mod, pubsub_name)

    on_exit(fn ->
      Application.delete_env(:ecache, :pubsub_mod)
    end)

    {:ok, pubsub_name: pubsub_name}
  end

  # Test module setup
  setup do
    # Create unique table name for each test to avoid conflicts
    table_name = :"test_cache_#{:erlang.unique_integer([:positive])}"

    # Override the table name for this test
    :persistent_term.put({ECache, :table_name}, table_name)

    # Initialize ETS table directly for testing
    ECache.Adapters.ETS.init_storage(table_name)

    # Clean up after test
    on_exit(fn ->
      :persistent_term.erase({ECache, :table_name})

      if :ets.info(table_name) != :undefined do
        :ets.delete(table_name)
      end
    end)

    {:ok, table_name: table_name}
  end

  describe "ECache.Adapters.ETS" do
    test "init_storage/1 creates ETS table", %{table_name: table_name} do
      assert :ets.info(table_name) != :undefined
      assert :ets.info(table_name, :type) == :set
      assert :ets.info(table_name, :protection) == :public
    end

    test "get/2 returns :miss for non-existent key", %{table_name: table_name} do
      assert ECache.Adapters.ETS.get(table_name, "nonexistent") == :miss
    end

    test "put/4 and get/2 basic operations", %{table_name: table_name} do
      key = "test_key"
      value = "test_value"
      expires_at = System.system_time(:second) + 3600

      assert ECache.Adapters.ETS.put(table_name, key, value, expires_at) == :ok
      assert ECache.Adapters.ETS.get(table_name, key) == {:ok, {value, expires_at}}
    end

    test "delete/2 removes key from storage", %{table_name: table_name} do
      key = "test_key"
      value = "test_value"
      expires_at = System.system_time(:second) + 3600

      ECache.Adapters.ETS.put(table_name, key, value, expires_at)
      assert ECache.Adapters.ETS.get(table_name, key) == {:ok, {value, expires_at}}

      assert ECache.Adapters.ETS.delete(table_name, key) == :ok
      assert ECache.Adapters.ETS.get(table_name, key) == :miss
    end

    test "cleanup_expired/2 removes expired entries", %{table_name: table_name} do
      current_time = System.system_time(:second)

      # Insert expired entry
      ECache.Adapters.ETS.put(table_name, "expired", "value", current_time - 1)
      # Insert valid entry
      ECache.Adapters.ETS.put(table_name, "valid", "value", current_time + 3600)

      assert ECache.Adapters.ETS.get(table_name, "expired") == {:ok, {"value", current_time - 1}}
      assert ECache.Adapters.ETS.get(table_name, "valid") == {:ok, {"value", current_time + 3600}}

      assert ECache.Adapters.ETS.cleanup_expired(table_name, current_time) == :ok

      assert ECache.Adapters.ETS.get(table_name, "expired") == :miss
      assert ECache.Adapters.ETS.get(table_name, "valid") == {:ok, {"value", current_time + 3600}}
    end

    test "clear/1 removes all entries", %{table_name: table_name} do
      ECache.Adapters.ETS.put(table_name, "key1", "value1", System.system_time(:second) + 3600)
      ECache.Adapters.ETS.put(table_name, "key2", "value2", System.system_time(:second) + 3600)

      assert ECache.Adapters.ETS.get(table_name, "key1") != :miss
      assert ECache.Adapters.ETS.get(table_name, "key2") != :miss

      assert ECache.Adapters.ETS.clear(table_name) == :ok

      assert ECache.Adapters.ETS.get(table_name, "key1") == :miss
      assert ECache.Adapters.ETS.get(table_name, "key2") == :miss
    end

    test "stats/1 returns table statistics", %{table_name: table_name} do
      stats = ECache.Adapters.ETS.stats(table_name)

      assert is_map(stats)
      assert Map.has_key?(stats, :size)
      assert Map.has_key?(stats, :memory)
      assert stats.size == 0

      # Add some data and check stats change
      ECache.Adapters.ETS.put(table_name, "key1", "value1", System.system_time(:second) + 3600)
      new_stats = ECache.Adapters.ETS.stats(table_name)

      assert new_stats.size == 1
      assert new_stats.memory > stats.memory
    end
  end

  describe "ECache high-level API" do
    test "get/1 returns :miss for non-existent key" do
      assert ECache.get("nonexistent") == :miss
    end

    test "put/2 and get/1 basic operations" do
      key = "test_key"
      value = "test_value"

      assert ECache.put(key, value) == :ok
      assert ECache.get(key) == {:ok, value}
    end

    test "put/3 with custom TTL" do
      key = "test_key"
      value = "test_value"

      assert ECache.put(key, value, ttl: 1) == :ok
      assert ECache.get(key) == {:ok, value}

      # Wait for expiration
      Process.sleep(1100)
      assert ECache.get(key) == :miss
    end

    test "get/1 automatically removes expired entries" do
      key = "test_key"
      value = "test_value"

      # Put with 1 second TTL
      assert ECache.put(key, value, ttl: 1) == :ok
      assert ECache.get(key) == {:ok, value}

      # Wait for expiration
      Process.sleep(1100)

      # Should return :miss and remove the expired entry
      assert ECache.get(key) == :miss
      # Verify it's actually removed
      assert ECache.get(key) == :miss
    end

    test "delete/1 removes key from cache" do
      key = "test_key"
      value = "test_value"

      ECache.put(key, value)
      assert ECache.get(key) == {:ok, value}

      assert ECache.delete(key) == :ok
      assert ECache.get(key) == :miss
    end

    test "clear/0 removes all entries" do
      ECache.put("key1", "value1")
      ECache.put("key2", "value2")

      assert ECache.get("key1") == {:ok, "value1"}
      assert ECache.get("key2") == {:ok, "value2"}

      assert ECache.clear() == :ok

      assert ECache.get("key1") == :miss
      assert ECache.get("key2") == :miss
    end

    test "stats/0 returns cache statistics" do
      stats = ECache.stats()

      assert is_map(stats)
      assert Map.has_key?(stats, :size)
      assert Map.has_key?(stats, :memory)
    end
  end

  describe "ECache.load_cache/3" do
    test "returns cached value when available" do
      key = "test_key"
      cached_value = "cached_value"

      ECache.put(key, cached_value)

      result =
        ECache.load_cache(key, [], fn ->
          "fresh_value"
        end)

      assert result == {:ok, cached_value}
    end

    test "executes loader function on cache miss" do
      key = "test_key"
      fresh_value = "fresh_value"

      result =
        ECache.load_cache(key, [], fn ->
          fresh_value
        end)

      assert result == {:ok, fresh_value}
      assert ECache.get(key) == {:ok, fresh_value}
    end

    test "handles loader function returning {:ok, value}" do
      key = "test_key"
      fresh_value = "fresh_value"

      result =
        ECache.load_cache(key, [], fn ->
          {:ok, fresh_value}
        end)

      assert result == {:ok, fresh_value}
      assert ECache.get(key) == {:ok, fresh_value}
    end

    test "handles loader function returning {:error, reason}" do
      key = "test_key"
      error_reason = :not_found

      result =
        ECache.load_cache(key, [], fn ->
          {:error, error_reason}
        end)

      assert result == {:error, error_reason}
      # Errors not cached by default
      assert ECache.get(key) == :miss
    end

    test "handles loader function returning nil" do
      key = "test_key"

      result =
        ECache.load_cache(key, [], fn ->
          nil
        end)

      assert result == {:error, :nil_result}
      assert ECache.get(key) == :miss
    end

    test "caches errors when cache_errors: true" do
      key = "test_key"
      error_result = {:error, :not_found}

      result =
        ECache.load_cache(key, [cache_errors: true, error_ttl: 3600], fn ->
          error_result
        end)

      assert result == error_result
      assert ECache.get(key) == {:ok, error_result}
    end

    test "uses custom TTL option" do
      key = "test_key"
      value = "test_value"

      ECache.load_cache(key, [ttl: 1], fn ->
        value
      end)

      assert ECache.get(key) == {:ok, value}

      # Wait for expiration
      Process.sleep(1100)
      assert ECache.get(key) == :miss
    end

    test "handles loader function exceptions" do
      key = "test_key"

      result =
        ECache.load_cache(key, [], fn ->
          raise "something went wrong"
        end)

      assert {:error, {:error, %RuntimeError{}}} = result
      assert ECache.get(key) == :miss
    end
  end

  describe "ECache.invalidate_cache/2" do
    test "invalidates cache when operation returns {:ok, value}" do
      key = "test_key"
      cached_value = "cached_value"

      ECache.put(key, cached_value)
      assert ECache.get(key) == {:ok, cached_value}

      result =
        ECache.invalidate_cache(key, fn ->
          {:ok, "operation_result"}
        end)

      assert result == {:ok, "operation_result"}
      assert ECache.get(key) == :miss
    end

    test "invalidates cache when operation returns :ok" do
      key = "test_key"
      cached_value = "cached_value"

      ECache.put(key, cached_value)
      assert ECache.get(key) == {:ok, cached_value}

      result =
        ECache.invalidate_cache(key, fn ->
          :ok
        end)

      assert result == :ok
      assert ECache.get(key) == :miss
    end

    test "does not invalidate cache when operation returns error" do
      key = "test_key"
      cached_value = "cached_value"

      ECache.put(key, cached_value)
      assert ECache.get(key) == {:ok, cached_value}

      result =
        ECache.invalidate_cache(key, fn ->
          {:error, :not_found}
        end)

      assert result == {:error, :not_found}
      # Cache unchanged
      assert ECache.get(key) == {:ok, cached_value}
    end

    test "does not invalidate cache when operation returns other values" do
      key = "test_key"
      cached_value = "cached_value"

      ECache.put(key, cached_value)
      assert ECache.get(key) == {:ok, cached_value}

      result =
        ECache.invalidate_cache(key, fn ->
          "some_other_result"
        end)

      assert result == "some_other_result"
      # Cache unchanged
      assert ECache.get(key) == {:ok, cached_value}
    end

    test "handles operation function exceptions" do
      key = "test_key"
      cached_value = "cached_value"

      ECache.put(key, cached_value)
      assert ECache.get(key) == {:ok, cached_value}

      result =
        ECache.invalidate_cache(key, fn ->
          raise "something went wrong"
        end)

      assert {:error, {:error, %RuntimeError{}}} = result
      # Cache unchanged on exception
      assert ECache.get(key) == {:ok, cached_value}
    end
  end

  describe "ECache PubSub invalidation" do
    test "delete/1 broadcasts invalidation message" do
      key = "test_key"
      topic = "cache_invalidation"
      pubsub_name = ECache.PubSub

      # Subscribe to the invalidation topic
      Phoenix.PubSub.subscribe(pubsub_name, topic)

      # Put a value in cache
      ECache.put(key, "value")
      assert ECache.get(key) == {:ok, "value"}

      # Delete should broadcast invalidation
      ECache.delete(key)

      # Should receive invalidation message
      assert_receive {:invalidate, ^key}, 1000

      # Key should be deleted locally
      assert ECache.get(key) == :miss
    end

    test "handles PubSub broadcast failures gracefully" do
      key = "test_key"

      # Temporarily set an invalid PubSub name to simulate failure
      old_pubsub = Application.get_env(:ecache, :pubsub_mod)
      Application.put_env(:ecache, :pubsub_mod, :nonexistent_pubsub)

      # Put a value in cache
      ECache.put(key, "value")
      assert ECache.get(key) == {:ok, "value"}

      # Delete should still work even if broadcast fails
      assert ECache.delete(key) == :ok
      assert ECache.get(key) == :miss

      # Restore original PubSub
      Application.put_env(:ecache, :pubsub_mod, old_pubsub)
    end
  end

  describe "ECache error handling" do
    test "get/1 handles adapter errors gracefully" do
      # Mock a failing adapter by deleting the table
      table_name = :persistent_term.get({ECache, :table_name})
      :ets.delete(table_name)

      # Should return :miss instead of crashing
      assert ECache.get("any_key") == :miss
    end

    test "put/2 handles adapter errors gracefully" do
      # Mock a failing adapter by deleting the table
      table_name = :persistent_term.get({ECache, :table_name})
      :ets.delete(table_name)

      # Should return :ok instead of crashing (logged internally)
      assert ECache.put("key", "value") == :ok
    end

    test "delete/1 handles adapter errors gracefully" do
      # Mock a failing adapter by deleting the table
      table_name = :persistent_term.get({ECache, :table_name})
      :ets.delete(table_name)

      # Should return :ok instead of crashing (logged internally)
      assert ECache.delete("key") == :ok
    end
  end
end
