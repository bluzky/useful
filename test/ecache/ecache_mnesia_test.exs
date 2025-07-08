defmodule ECacheMnesiaTest do
  # Mnesia operations must be sequential
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
    Application.put_env(:ecache, :adapter, ECache.Adapters.Mnesia)

    on_exit(fn ->
      Application.delete_env(:ecache, :pubsub_mod)
      Application.delete_env(:ecache, :adapter)
    end)

    {:ok, pubsub_name: pubsub_name}
  end

  setup do
    # Clean Mnesia state before each test
    cleanup_mnesia()

    # Create unique table name for each test to avoid conflicts
    table_name = :"test_cache_#{:erlang.unique_integer([:positive])}"

    # Override the table name for this test
    :persistent_term.put({ECache, :table_name}, table_name)

    # Initialize Mnesia table directly for testing
    ECache.Adapters.Mnesia.init_storage(table_name)

    # Clean up after test
    on_exit(fn ->
      :persistent_term.erase({ECache, :table_name})
      cleanup_table(table_name)
    end)

    {:ok, table_name: table_name}
  end

  defp cleanup_mnesia do
    try do
      # Stop mnesia if running
      case :mnesia.system_info(:is_running) do
        :yes -> :mnesia.stop()
        _ -> :ok
      end
    catch
      :exit, _ -> :ok
    end

    # Wait a bit for mnesia to fully stop
    Process.sleep(50)

    # Clean up schema files
    schema_dir = "Mnesia.#{node()}"

    if File.exists?(schema_dir) do
      File.rm_rf!(schema_dir)
    end
  end

  defp cleanup_table(table_name) do
    try do
      if table_name in :mnesia.system_info(:tables) do
        :mnesia.delete_table(table_name)
      end
    catch
      _, _ -> :ok
    end
  end

  describe "ECache high-level API with Mnesia adapter" do
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

    test "handles complex data structures" do
      key = "complex_data"

      value = %{
        user: %{id: 123, name: "Alice"},
        settings: %{theme: "dark", notifications: true},
        tags: ["admin", "user"],
        metadata: %{created_at: ~U[2024-01-01 00:00:00Z]}
      }

      assert ECache.put(key, value) == :ok
      assert ECache.get(key) == {:ok, value}
    end

    test "handles large values" do
      key = "large_data"

      value = %{
        data: String.duplicate("x", 5_000),
        metadata: Enum.map(1..50, fn i -> {"field_#{i}", "value_#{i}"} end) |> Map.new()
      }

      assert ECache.put(key, value) == :ok
      assert ECache.get(key) == {:ok, value}
    end
  end

  describe "ECache.load_cache/3 with Mnesia adapter" do
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

    test "loads complex data structures via loader" do
      key = "user_profile"

      user_data = %{
        id: 456,
        profile: %{name: "Bob", email: "bob@example.com"},
        permissions: ["read", "write"],
        last_login: System.system_time(:second)
      }

      result =
        ECache.load_cache(key, [], fn ->
          # Simulate database fetch
          Process.sleep(10)
          user_data
        end)

      assert result == {:ok, user_data}
      assert ECache.get(key) == {:ok, user_data}
    end
  end

  describe "ECache.invalidate_cache/2 with Mnesia adapter" do
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

    test "conditional invalidation with database update" do
      key = "user_123"
      original_data = %{name: "Alice", email: "alice@example.com"}

      ECache.put(key, original_data)
      assert ECache.get(key) == {:ok, original_data}

      # Simulate successful database update
      updated_data = %{name: "Alice Smith", email: "alice.smith@example.com"}

      result =
        ECache.invalidate_cache(key, fn ->
          # Simulate database update
          Process.sleep(5)
          {:ok, updated_data}
        end)

      assert result == {:ok, updated_data}
      # Cache invalidated
      assert ECache.get(key) == :miss
    end
  end

  describe "ECache PubSub invalidation with Mnesia adapter" do
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

  describe "ECache error handling with Mnesia adapter" do
    test "get/1 handles adapter errors gracefully" do
      # Stop mnesia to simulate adapter failure
      :mnesia.stop()

      # Should return :miss instead of crashing
      assert ECache.get("any_key") == :miss
    end

    test "put/2 handles adapter errors gracefully" do
      # Stop mnesia to simulate adapter failure
      :mnesia.stop()

      # Should return :ok instead of crashing (logged internally)
      assert ECache.put("key", "value") == :ok
    end

    test "delete/1 handles adapter errors gracefully" do
      # Stop mnesia to simulate adapter failure
      :mnesia.stop()

      # Should return :ok instead of crashing (logged internally)
      assert ECache.delete("key") == :ok
    end
  end

  describe "Mnesia-specific features" do
    test "data persists across cache operations" do
      # This test verifies that Mnesia provides persistence
      # (compared to ETS which is memory-only)

      key = "persistent_key"
      value = "persistent_value"

      ECache.put(key, value)
      assert ECache.get(key) == {:ok, value}

      # Simulate some operations that might affect persistence
      ECache.put("other_key", "other_value")
      ECache.delete("other_key")

      # Original data should still be there
      assert ECache.get(key) == {:ok, value}
    end

    test "handles concurrent operations safely" do
      # Mnesia provides ACID properties for concurrent access
      base_key = "concurrent_test"
      num_workers = 10

      # Spawn concurrent workers
      tasks =
        Enum.map(1..num_workers, fn worker_id ->
          Task.async(fn ->
            key = "#{base_key}_#{worker_id}"
            value = "value_#{worker_id}"

            # Each worker does some operations
            ECache.put(key, value)
            retrieved = ECache.get(key)
            ECache.delete(key)

            {worker_id, retrieved}
          end)
        end)

      # Wait for all workers to complete
      results = Task.await_many(tasks, 5000)

      # All workers should have succeeded
      assert length(results) == num_workers

      Enum.each(results, fn {worker_id, retrieved} ->
        expected_value = "value_#{worker_id}"
        assert retrieved == {:ok, expected_value}
      end)
    end

    test "stats show Mnesia memory characteristics" do
      initial_stats = ECache.stats()

      # Add some data
      Enum.each(1..20, fn i ->
        ECache.put("key_#{i}", "value_#{i}")
      end)

      new_stats = ECache.stats()

      # Memory should have increased
      assert new_stats.size == 20
      assert new_stats.memory >= initial_stats.memory

      # Clear and verify memory decreases
      ECache.clear()
      final_stats = ECache.stats()

      assert final_stats.size == 0
      assert final_stats.memory < new_stats.memory
    end

    test "TTL cleanup works with Mnesia storage" do
      current_time = System.system_time(:second)

      # Put entries with different expiration times
      # Already expired
      ECache.put("expired1", "value1", ttl: -100)
      # Valid for 1 hour
      ECache.put("valid1", "value2", ttl: 3600)
      # Already expired
      ECache.put("expired2", "value3", ttl: -50)

      # Force cleanup by calling the adapter directly
      table_name = :persistent_term.get({ECache, :table_name})
      ECache.Adapters.Mnesia.cleanup_expired(table_name, current_time)

      # Only valid entries should remain
      assert ECache.get("expired1") == :miss
      assert ECache.get("valid1") == {:ok, "value2"}
      assert ECache.get("expired2") == :miss
    end

    test "handles table schema correctly" do
      # Verify that the Mnesia table has the correct schema
      table_name = :persistent_term.get({ECache, :table_name})

      # Check table exists and has correct attributes
      assert table_name in :mnesia.system_info(:tables)
      assert :mnesia.table_info(table_name, :attributes) == [:key, :value, :expires_at]
      assert :mnesia.table_info(table_name, :type) == :set
    end
  end

  describe "Mnesia adapter integration scenarios" do
    test "cache-aside pattern with simulated database" do
      # Simulate a common caching pattern
      user_id = 123
      cache_key = "user:#{user_id}"

      # Simulate database fetch function
      db_fetch = fn ->
        # Simulate DB latency
        Process.sleep(10)

        %{
          id: user_id,
          name: "Test User",
          email: "test@example.com",
          created_at: ~U[2024-01-01 00:00:00Z]
        }
      end

      # First call should hit the database
      start_time = System.monotonic_time(:millisecond)
      result1 = ECache.load_cache(cache_key, [ttl: 300], db_fetch)
      first_duration = System.monotonic_time(:millisecond) - start_time

      # Second call should hit the cache (much faster)
      start_time = System.monotonic_time(:millisecond)
      result2 = ECache.load_cache(cache_key, [ttl: 300], db_fetch)
      second_duration = System.monotonic_time(:millisecond) - start_time

      # Results should be the same
      assert result1 == result2
      assert {:ok, user_data} = result1
      assert user_data.id == user_id

      # Second call should be faster (cached)
      assert second_duration < first_duration
    end

    test "write-through pattern with cache invalidation" do
      user_id = 456
      cache_key = "user:#{user_id}"

      # Initial data
      original_data = %{id: user_id, name: "Original Name", version: 1}
      ECache.put(cache_key, original_data)

      # Simulate updating user data
      updated_data = %{id: user_id, name: "Updated Name", version: 2}

      result =
        ECache.invalidate_cache(cache_key, fn ->
          # Simulate database update
          Process.sleep(5)
          # Return success to trigger cache invalidation
          {:ok, updated_data}
        end)

      assert result == {:ok, updated_data}
      # Cache invalidated
      assert ECache.get(cache_key) == :miss

      # Next load_cache call would fetch fresh data
      fresh_result =
        ECache.load_cache(cache_key, [], fn ->
          updated_data
        end)

      assert fresh_result == {:ok, updated_data}
    end

    test "session cache with expiration" do
      session_id = "session_abc123"
      cache_key = "session:#{session_id}"

      session_data = %{
        user_id: 789,
        csrf_token: "token123",
        last_activity: System.system_time(:second),
        permissions: ["read", "write"]
      }

      # Store session with 2-second TTL for testing
      ECache.put(cache_key, session_data, ttl: 2)

      # Should be available immediately
      assert ECache.get(cache_key) == {:ok, session_data}

      # Still available after 1 second
      Process.sleep(1100)
      assert ECache.get(cache_key) == {:ok, session_data}

      # Should expire after 2+ seconds
      Process.sleep(1100)
      assert ECache.get(cache_key) == :miss
    end
  end
end
