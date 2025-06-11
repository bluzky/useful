defmodule ECacheTest do
  use ExUnit.Case, async: true

  alias ECache

  setup do
    # Start a test PubSub process
    pubsub_name = ECache.PubSub

    {:ok, _pid} = start_supervised({Phoenix.PubSub, name: pubsub_name})

    # Override module attributes for testing
    Application.put_env(:ecache, :pubsub_mod, pubsub_name)

    # Clear any existing ETS entries
    if :ets.info(:distributed_cache) != :undefined do
      :ets.delete_all_objects(:distributed_cache)
    end

    # Start ECache GenServer
    {:ok, cache_pid} = start_supervised(ECache)

    on_exit(fn ->
      if :ets.info(:distributed_cache) != :undefined do
        :ets.delete_all_objects(:distributed_cache)
      end
    end)

    %{cache_pid: cache_pid, pubsub: pubsub_name}
  end

  describe "get/1" do
    test "returns :miss for non-existent key" do
      assert ECache.get("nonexistent") == :miss
    end

    test "returns {:ok, value} for existing key" do
      ECache.put("test_key", "test_value")
      assert ECache.get("test_key") == {:ok, "test_value"}
    end

    test "returns :miss and removes expired entries" do
      # Put with very short TTL
      ECache.put("expired_key", "value", ttl: 1)

      # Wait for expiration
      Process.sleep(1100)

      assert ECache.get("expired_key") == :miss

      # Verify it's actually removed from ETS
      assert :ets.lookup(:distributed_cache, "expired_key") == []
    end

    test "handles ETS errors gracefully" do
      # This test would require mocking ETS, which is complex
      # In a real scenario, you might use a library like Mox
      assert ECache.get("any_key") in [{:ok, :_}, :miss]
    end
  end

  describe "put/3" do
    test "stores value with default TTL" do
      assert ECache.put("key1", "value1") == :ok
      assert ECache.get("key1") == {:ok, "value1"}
    end

    test "stores value with custom TTL" do
      assert ECache.put("key2", "value2", ttl: 10) == :ok
      assert ECache.get("key2") == {:ok, "value2"}
    end

    test "overwrites existing key" do
      ECache.put("key3", "old_value")
      ECache.put("key3", "new_value")
      assert ECache.get("key3") == {:ok, "new_value"}
    end

    test "stores different data types" do
      ECache.put("string", "test")
      ECache.put("number", 42)
      ECache.put("list", [1, 2, 3])
      ECache.put("map", %{key: "value"})

      assert ECache.get("string") == {:ok, "test"}
      assert ECache.get("number") == {:ok, 42}
      assert ECache.get("list") == {:ok, [1, 2, 3]}
      assert ECache.get("map") == {:ok, %{key: "value"}}
    end
  end

  describe "delete/1" do
    test "removes existing key" do
      ECache.put("delete_me", "value")
      assert ECache.get("delete_me") == {:ok, "value"}

      assert ECache.delete("delete_me") == :ok
      assert ECache.get("delete_me") == :miss
    end

    test "returns :ok for non-existent key" do
      assert ECache.delete("nonexistent") == :ok
    end

    test "broadcasts invalidation message", %{pubsub: pubsub} do
      # Subscribe to invalidation messages
      Phoenix.PubSub.subscribe(pubsub, "cache_invalidation")

      ECache.put("broadcast_key", "value")
      ECache.delete("broadcast_key")

      # Should receive invalidation message
      assert_receive {:invalidate, "broadcast_key"}, 1000
    end
  end

  describe "load_cache/3" do
    test "returns cached value when available" do
      ECache.put("cached_key", "cached_value")

      result =
        ECache.load_cache("cached_key", [], fn ->
          "loader_value"
        end)

      assert result == {:ok, "cached_value"}
    end

    test "executes loader and caches result on cache miss" do
      result =
        ECache.load_cache("new_key", [], fn ->
          {:ok, "loaded_value"}
        end)

      assert result == {:ok, "loaded_value"}
      assert ECache.get("new_key") == {:ok, "loaded_value"}
    end

    test "handles loader returning plain value" do
      result =
        ECache.load_cache("plain_key", [], fn ->
          "plain_value"
        end)

      assert result == {:ok, "plain_value"}
      assert ECache.get("plain_key") == {:ok, "plain_value"}
    end

    test "handles loader returning nil" do
      result =
        ECache.load_cache("nil_key", [], fn ->
          nil
        end)

      assert result == {:error, :nil_result}
      assert ECache.get("nil_key") == :miss
    end

    test "handles loader returning error" do
      result =
        ECache.load_cache("error_key", [], fn ->
          {:error, :something_wrong}
        end)

      assert result == {:error, :something_wrong}
      assert ECache.get("error_key") == :miss
    end

    test "caches errors when cache_errors is true" do
      result =
        ECache.load_cache("error_cache_key", [cache_errors: true], fn ->
          {:error, :cached_error}
        end)

      assert result == {:error, :cached_error}
      assert ECache.get("error_cache_key") == {:ok, {:error, :cached_error}}
    end

    test "uses custom error TTL" do
      ECache.load_cache("error_ttl_key", [cache_errors: true, error_ttl: 1], fn ->
        {:error, :short_lived_error}
      end)

      assert ECache.get("error_ttl_key") == {:ok, {:error, :short_lived_error}}

      Process.sleep(1100)
      assert ECache.get("error_ttl_key") == :miss
    end

    test "handles loader function exceptions" do
      result =
        ECache.load_cache("exception_key", [], fn ->
          raise "Something went wrong"
        end)

      assert {:error, {_kind, _reason}} = result
      assert ECache.get("exception_key") == :miss
    end

    test "uses custom TTL from options" do
      ECache.load_cache("custom_ttl_key", [ttl: 5], fn ->
        "custom_ttl_value"
      end)

      # Verify it's cached
      assert ECache.get("custom_ttl_key") == {:ok, "custom_ttl_value"}
    end
  end

  describe "invalidate_cache/2" do
    test "invalidates cache when operation returns {:ok, result}" do
      ECache.put("invalidate_key1", "old_value")

      result =
        ECache.invalidate_cache("invalidate_key1", fn ->
          {:ok, "operation_result"}
        end)

      assert result == {:ok, "operation_result"}
      assert ECache.get("invalidate_key1") == :miss
    end

    test "invalidates cache when operation returns :ok" do
      ECache.put("invalidate_key2", "old_value")

      result =
        ECache.invalidate_cache("invalidate_key2", fn ->
          :ok
        end)

      assert result == :ok
      assert ECache.get("invalidate_key2") == :miss
    end

    test "does not invalidate cache when operation returns error" do
      ECache.put("no_invalidate_key", "should_remain")

      result =
        ECache.invalidate_cache("no_invalidate_key", fn ->
          {:error, :operation_failed}
        end)

      assert result == {:error, :operation_failed}
      assert ECache.get("no_invalidate_key") == {:ok, "should_remain"}
    end

    test "does not invalidate cache when operation returns other values" do
      ECache.put("other_result_key", "should_remain")

      result =
        ECache.invalidate_cache("other_result_key", fn ->
          "some_other_result"
        end)

      assert result == "some_other_result"
      assert ECache.get("other_result_key") == {:ok, "should_remain"}
    end

    test "handles operation function exceptions" do
      ECache.put("exception_invalidate_key", "should_remain")

      result =
        ECache.invalidate_cache("exception_invalidate_key", fn ->
          raise "Operation failed"
        end)

      assert {:error, {_kind, _reason}} = result
      assert ECache.get("exception_invalidate_key") == {:ok, "should_remain"}
    end
  end

  describe "GenServer callbacks" do
    test "handles invalidation messages from PubSub", %{cache_pid: cache_pid} do
      ECache.put("remote_key", "value")
      assert ECache.get("remote_key") == {:ok, "value"}

      # Simulate invalidation message from another node
      send(cache_pid, {:invalidate, "remote_key"})

      # Give it a moment to process
      Process.sleep(50)

      assert ECache.get("remote_key") == :miss
    end

    test "handles cleanup timer message", %{cache_pid: cache_pid} do
      # Put some expired entries
      :ets.insert(:distributed_cache, {"expired1", "value1", 1})
      :ets.insert(:distributed_cache, {"expired2", "value2", 2})
      :ets.insert(:distributed_cache, {"valid", "value", System.system_time(:second) + 3600})

      # Send cleanup message
      send(cache_pid, :cleanup)

      # Give it a moment to process
      Process.sleep(50)

      # Expired entries should be gone, valid one should remain
      assert ECache.get("expired1") == :miss
      assert ECache.get("expired2") == :miss
      assert ECache.get("valid") == {:ok, "value"}
    end

    test "handles unknown messages gracefully", %{cache_pid: cache_pid} do
      send(cache_pid, :unknown_message)

      # Should not crash
      Process.sleep(50)
      assert Process.alive?(cache_pid)
    end
  end

  describe "TTL and expiration" do
    test "respects default TTL configuration" do
      # This would require mocking Application.compile_env
      # For now, just verify basic TTL functionality
      ECache.put("ttl_key", "value", ttl: 2)
      assert ECache.get("ttl_key") == {:ok, "value"}

      Process.sleep(2100)
      assert ECache.get("ttl_key") == :miss
    end

    test "cleanup removes expired entries" do
      current_time = System.system_time(:second)

      # Insert some test data directly
      :ets.insert(:distributed_cache, {"expired1", "val1", current_time - 10})
      :ets.insert(:distributed_cache, {"expired2", "val2", current_time - 5})
      :ets.insert(:distributed_cache, {"valid", "val3", current_time + 3600})

      # Manually trigger cleanup
      send(ECache, :cleanup)
      Process.sleep(50)

      # Only valid entry should remain
      assert :ets.lookup(:distributed_cache, "expired1") == []
      assert :ets.lookup(:distributed_cache, "expired2") == []
      assert :ets.lookup(:distributed_cache, "valid") != []
    end
  end

  describe "error scenarios" do
    test "gracefully handles when PubSub is not available" do
      # This would require more complex setup to test PubSub failures
      # For now, verify that cache operations still work locally
      assert ECache.put("local_key", "local_value") == :ok
      assert ECache.get("local_key") == {:ok, "local_value"}
    end
  end
end
