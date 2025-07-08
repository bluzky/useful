defmodule ECache.Adapters.ETSTest do
  use ExUnit.Case, async: true

  alias ECache.Adapters.ETS

  describe "init_storage/1" do
    test "creates ETS table with correct configuration" do
      table_name = :"test_table_#{:erlang.unique_integer([:positive])}"

      assert ETS.init_storage(table_name) == :ok

      # Verify table exists and has correct properties
      assert :ets.info(table_name) != :undefined
      assert :ets.info(table_name, :type) == :set
      assert :ets.info(table_name, :protection) == :public
      assert :ets.info(table_name, :named_table) == true
      assert :ets.info(table_name, :read_concurrency) == true

      # Cleanup
      :ets.delete(table_name)
    end

    test "succeeds when table already exists" do
      table_name = :"test_table_#{:erlang.unique_integer([:positive])}"

      # Create table first
      :ets.new(table_name, [:set, :public, :named_table])

      # Should still return :ok
      assert ETS.init_storage(table_name) == :ok

      # Cleanup
      :ets.delete(table_name)
    end

    test "handles table creation with same name multiple times" do
      table_name = :"test_table_#{:erlang.unique_integer([:positive])}"

      assert ETS.init_storage(table_name) == :ok
      assert ETS.init_storage(table_name) == :ok
      assert ETS.init_storage(table_name) == :ok

      # Cleanup
      :ets.delete(table_name)
    end
  end

  describe "get/2" do
    setup do
      table_name = :"test_table_#{:erlang.unique_integer([:positive])}"
      ETS.init_storage(table_name)

      on_exit(fn ->
        if :ets.info(table_name) != :undefined do
          :ets.delete(table_name)
        end
      end)

      {:ok, table_name: table_name}
    end

    test "returns :miss for non-existent key", %{table_name: table_name} do
      assert ETS.get(table_name, "nonexistent") == :miss
    end

    test "returns stored value with expiration time", %{table_name: table_name} do
      key = "test_key"
      value = "test_value"
      expires_at = 1_234_567_890

      :ets.insert(table_name, {key, value, expires_at})

      assert ETS.get(table_name, key) == {:ok, {value, expires_at}}
    end

    test "handles complex keys and values", %{table_name: table_name} do
      key = {:user, 123, "profile"}
      value = %{name: "John", age: 30, tags: ["admin", "user"]}
      expires_at = System.system_time(:second) + 3600

      :ets.insert(table_name, {key, value, expires_at})

      assert ETS.get(table_name, key) == {:ok, {value, expires_at}}
    end

    test "returns :miss for empty table", %{table_name: table_name} do
      assert ETS.get(table_name, "any_key") == :miss
      assert ETS.get(table_name, 123) == :miss
      assert ETS.get(table_name, {:complex, "key"}) == :miss
    end

    test "handles binary keys and values", %{table_name: table_name} do
      key = <<1, 2, 3, 4>>
      value = <<255, 254, 253>>
      expires_at = System.system_time(:second) + 1000

      :ets.insert(table_name, {key, value, expires_at})

      assert ETS.get(table_name, key) == {:ok, {value, expires_at}}
    end

    test "handles error when table doesn't exist" do
      nonexistent_table = :nonexistent_table_123

      assert {:error, {:error, :badarg}} = ETS.get(nonexistent_table, "key")
    end
  end

  describe "put/4" do
    setup do
      table_name = :"test_table_#{:erlang.unique_integer([:positive])}"
      ETS.init_storage(table_name)

      on_exit(fn ->
        if :ets.info(table_name) != :undefined do
          :ets.delete(table_name)
        end
      end)

      {:ok, table_name: table_name}
    end

    test "stores key-value pair with expiration", %{table_name: table_name} do
      key = "test_key"
      value = "test_value"
      expires_at = System.system_time(:second) + 3600

      assert ETS.put(table_name, key, value, expires_at) == :ok

      # Verify it was stored
      assert :ets.lookup(table_name, key) == [{key, value, expires_at}]
    end

    test "overwrites existing key", %{table_name: table_name} do
      key = "test_key"
      value1 = "first_value"
      value2 = "second_value"
      expires_at1 = System.system_time(:second) + 1800
      expires_at2 = System.system_time(:second) + 3600

      assert ETS.put(table_name, key, value1, expires_at1) == :ok
      assert ETS.put(table_name, key, value2, expires_at2) == :ok

      # Should have the second value
      assert :ets.lookup(table_name, key) == [{key, value2, expires_at2}]
    end

    test "handles complex data structures", %{table_name: table_name} do
      key = {:user, 123}

      value = %{
        profile: %{name: "Alice", email: "alice@example.com"},
        settings: %{theme: "dark", notifications: true},
        permissions: ["read", "write", "admin"]
      }

      expires_at = System.system_time(:second) + 7200

      assert ETS.put(table_name, key, value, expires_at) == :ok
      assert ETS.get(table_name, key) == {:ok, {value, expires_at}}
    end

    test "handles nil values", %{table_name: table_name} do
      key = "nil_key"
      value = nil
      expires_at = System.system_time(:second) + 3600

      assert ETS.put(table_name, key, value, expires_at) == :ok
      assert ETS.get(table_name, key) == {:ok, {nil, expires_at}}
    end

    test "handles large values", %{table_name: table_name} do
      key = "large_key"
      value = String.duplicate("x", 10_000)
      expires_at = System.system_time(:second) + 3600

      assert ETS.put(table_name, key, value, expires_at) == :ok
      assert ETS.get(table_name, key) == {:ok, {value, expires_at}}
    end

    test "handles concurrent writes to same key", %{table_name: table_name} do
      key = "concurrent_key"
      expires_at = System.system_time(:second) + 3600

      # Simulate concurrent writes
      tasks =
        Enum.map(1..10, fn i ->
          Task.async(fn ->
            ETS.put(table_name, key, "value_#{i}", expires_at + i)
          end)
        end)

      results = Task.await_many(tasks)

      # All writes should succeed
      assert Enum.all?(results, &(&1 == :ok))

      # Should have one of the values
      assert {:ok, {value, _}} = ETS.get(table_name, key)
      assert String.starts_with?(value, "value_")
    end

    test "handles error when table doesn't exist" do
      nonexistent_table = :nonexistent_table_123

      assert {:error, {:error, :badarg}} =
               ETS.put(nonexistent_table, "key", "value", 123_456)
    end
  end

  describe "delete/2" do
    setup do
      table_name = :"test_table_#{:erlang.unique_integer([:positive])}"
      ETS.init_storage(table_name)

      on_exit(fn ->
        if :ets.info(table_name) != :undefined do
          :ets.delete(table_name)
        end
      end)

      {:ok, table_name: table_name}
    end

    test "removes existing key", %{table_name: table_name} do
      key = "test_key"
      value = "test_value"
      expires_at = System.system_time(:second) + 3600

      ETS.put(table_name, key, value, expires_at)
      assert ETS.get(table_name, key) == {:ok, {value, expires_at}}

      assert ETS.delete(table_name, key) == :ok
      assert ETS.get(table_name, key) == :miss
    end

    test "succeeds for non-existent key", %{table_name: table_name} do
      assert ETS.delete(table_name, "nonexistent") == :ok
    end

    test "only removes specified key", %{table_name: table_name} do
      expires_at = System.system_time(:second) + 3600

      ETS.put(table_name, "key1", "value1", expires_at)
      ETS.put(table_name, "key2", "value2", expires_at)
      ETS.put(table_name, "key3", "value3", expires_at)

      assert ETS.delete(table_name, "key2") == :ok

      assert ETS.get(table_name, "key1") == {:ok, {"value1", expires_at}}
      assert ETS.get(table_name, "key2") == :miss
      assert ETS.get(table_name, "key3") == {:ok, {"value3", expires_at}}
    end

    test "handles complex keys", %{table_name: table_name} do
      key = {:user, 123, "session", "abc-def"}
      value = %{data: "session_data"}
      expires_at = System.system_time(:second) + 3600

      ETS.put(table_name, key, value, expires_at)
      assert ETS.get(table_name, key) == {:ok, {value, expires_at}}

      assert ETS.delete(table_name, key) == :ok
      assert ETS.get(table_name, key) == :miss
    end

    test "handles concurrent deletes", %{table_name: table_name} do
      expires_at = System.system_time(:second) + 3600

      # Insert keys
      Enum.each(1..10, fn i ->
        ETS.put(table_name, "key_#{i}", "value_#{i}", expires_at)
      end)

      # Concurrent deletes
      tasks =
        Enum.map(1..10, fn i ->
          Task.async(fn ->
            ETS.delete(table_name, "key_#{i}")
          end)
        end)

      results = Task.await_many(tasks)

      # All deletes should succeed
      assert Enum.all?(results, &(&1 == :ok))

      # All keys should be gone
      Enum.each(1..10, fn i ->
        assert ETS.get(table_name, "key_#{i}") == :miss
      end)
    end

    test "handles error when table doesn't exist" do
      nonexistent_table = :nonexistent_table_123

      assert {:error, {:error, :badarg}} = ETS.delete(nonexistent_table, "key")
    end
  end

  describe "cleanup_expired/2" do
    setup do
      table_name = :"test_table_#{:erlang.unique_integer([:positive])}"
      ETS.init_storage(table_name)

      on_exit(fn ->
        if :ets.info(table_name) != :undefined do
          :ets.delete(table_name)
        end
      end)

      {:ok, table_name: table_name}
    end

    test "removes only expired entries", %{table_name: table_name} do
      current_time = System.system_time(:second)

      # Insert expired entries
      ETS.put(table_name, "expired1", "value1", current_time - 100)
      ETS.put(table_name, "expired2", "value2", current_time - 50)

      # Insert valid entries
      ETS.put(table_name, "valid1", "value3", current_time + 100)
      ETS.put(table_name, "valid2", "value4", current_time + 200)

      # Insert entry that expires exactly at current time
      ETS.put(table_name, "boundary", "value5", current_time)

      assert ETS.cleanup_expired(table_name, current_time) == :ok

      # Expired entries should be gone
      assert ETS.get(table_name, "expired1") == :miss
      assert ETS.get(table_name, "expired2") == :miss
      assert ETS.get(table_name, "boundary") == :miss

      # Valid entries should remain
      assert ETS.get(table_name, "valid1") == {:ok, {"value3", current_time + 100}}
      assert ETS.get(table_name, "valid2") == {:ok, {"value4", current_time + 200}}
    end

    test "handles empty table", %{table_name: table_name} do
      current_time = System.system_time(:second)

      assert ETS.cleanup_expired(table_name, current_time) == :ok
      assert :ets.info(table_name, :size) == 0
    end

    test "handles table with no expired entries", %{table_name: table_name} do
      current_time = System.system_time(:second)

      # Insert only valid entries
      ETS.put(table_name, "key1", "value1", current_time + 100)
      ETS.put(table_name, "key2", "value2", current_time + 200)

      assert ETS.cleanup_expired(table_name, current_time) == :ok

      # All entries should remain
      assert ETS.get(table_name, "key1") == {:ok, {"value1", current_time + 100}}
      assert ETS.get(table_name, "key2") == {:ok, {"value2", current_time + 200}}
    end

    test "handles table with all expired entries", %{table_name: table_name} do
      current_time = System.system_time(:second)

      # Insert only expired entries
      ETS.put(table_name, "key1", "value1", current_time - 100)
      ETS.put(table_name, "key2", "value2", current_time - 200)
      ETS.put(table_name, "key3", "value3", current_time - 300)

      assert ETS.cleanup_expired(table_name, current_time) == :ok

      # All entries should be gone
      assert ETS.get(table_name, "key1") == :miss
      assert ETS.get(table_name, "key2") == :miss
      assert ETS.get(table_name, "key3") == :miss
      assert :ets.info(table_name, :size) == 0
    end

    test "handles large number of expired entries efficiently", %{table_name: table_name} do
      current_time = System.system_time(:second)

      # Insert 1000 expired entries
      Enum.each(1..1000, fn i ->
        ETS.put(table_name, "expired_#{i}", "value_#{i}", current_time - i)
      end)

      # Insert 100 valid entries
      Enum.each(1..100, fn i ->
        ETS.put(table_name, "valid_#{i}", "value_#{i}", current_time + i)
      end)

      assert :ets.info(table_name, :size) == 1100

      assert ETS.cleanup_expired(table_name, current_time) == :ok

      # Should have only 100 valid entries remaining
      assert :ets.info(table_name, :size) == 100

      # Verify some entries
      assert ETS.get(table_name, "expired_1") == :miss
      assert ETS.get(table_name, "expired_500") == :miss
      assert ETS.get(table_name, "valid_1") == {:ok, {"value_1", current_time + 1}}
      assert ETS.get(table_name, "valid_50") == {:ok, {"value_50", current_time + 50}}
    end

    test "handles error when table doesn't exist" do
      nonexistent_table = :nonexistent_table_123
      current_time = System.system_time(:second)

      assert {:error, {:error, :badarg}} =
               ETS.cleanup_expired(nonexistent_table, current_time)
    end
  end

  describe "clear/1" do
    setup do
      table_name = :"test_table_#{:erlang.unique_integer([:positive])}"
      ETS.init_storage(table_name)

      on_exit(fn ->
        if :ets.info(table_name) != :undefined do
          :ets.delete(table_name)
        end
      end)

      {:ok, table_name: table_name}
    end

    test "removes all entries from table", %{table_name: table_name} do
      expires_at = System.system_time(:second) + 3600

      # Insert multiple entries
      ETS.put(table_name, "key1", "value1", expires_at)
      ETS.put(table_name, "key2", "value2", expires_at)
      ETS.put(table_name, "key3", "value3", expires_at)

      assert :ets.info(table_name, :size) == 3

      assert ETS.clear(table_name) == :ok

      assert :ets.info(table_name, :size) == 0
      assert ETS.get(table_name, "key1") == :miss
      assert ETS.get(table_name, "key2") == :miss
      assert ETS.get(table_name, "key3") == :miss
    end

    test "succeeds on empty table", %{table_name: table_name} do
      assert :ets.info(table_name, :size) == 0
      assert ETS.clear(table_name) == :ok
      assert :ets.info(table_name, :size) == 0
    end

    test "handles large tables efficiently", %{table_name: table_name} do
      expires_at = System.system_time(:second) + 3600

      # Insert 10,000 entries
      Enum.each(1..10_000, fn i ->
        ETS.put(table_name, "key_#{i}", "value_#{i}", expires_at)
      end)

      assert :ets.info(table_name, :size) == 10_000

      assert ETS.clear(table_name) == :ok

      assert :ets.info(table_name, :size) == 0
    end

    test "table remains usable after clear", %{table_name: table_name} do
      expires_at = System.system_time(:second) + 3600

      # Insert and clear
      ETS.put(table_name, "key1", "value1", expires_at)
      ETS.clear(table_name)

      # Should be able to use table normally
      ETS.put(table_name, "key2", "value2", expires_at)
      assert ETS.get(table_name, "key2") == {:ok, {"value2", expires_at}}
    end

    test "handles error when table doesn't exist" do
      nonexistent_table = :nonexistent_table_123

      assert {:error, {:error, :badarg}} = ETS.clear(nonexistent_table)
    end
  end

  describe "stats/1" do
    setup do
      table_name = :"test_table_#{:erlang.unique_integer([:positive])}"
      ETS.init_storage(table_name)

      on_exit(fn ->
        if :ets.info(table_name) != :undefined do
          :ets.delete(table_name)
        end
      end)

      {:ok, table_name: table_name}
    end

    test "returns correct stats for empty table", %{table_name: table_name} do
      stats = ETS.stats(table_name)

      assert is_map(stats)
      assert Map.has_key?(stats, :size)
      assert Map.has_key?(stats, :memory)
      assert stats.size == 0
      assert is_integer(stats.memory)
      assert stats.memory >= 0
    end

    test "returns updated stats after adding entries", %{table_name: table_name} do
      initial_stats = ETS.stats(table_name)
      expires_at = System.system_time(:second) + 3600

      # Add entries
      ETS.put(table_name, "key1", "value1", expires_at)
      ETS.put(table_name, "key2", "value2", expires_at)
      ETS.put(table_name, "key3", "value3", expires_at)

      new_stats = ETS.stats(table_name)

      assert new_stats.size == 3
      assert new_stats.memory > initial_stats.memory
    end

    test "memory increases with larger values", %{table_name: table_name} do
      expires_at = System.system_time(:second) + 3600

      # Add small value
      ETS.put(table_name, "small", "x", expires_at)
      small_stats = ETS.stats(table_name)

      # Add large value
      large_value = String.duplicate("x", 10_000)
      ETS.put(table_name, "large", large_value, expires_at)
      large_stats = ETS.stats(table_name)

      assert large_stats.size == 2
      assert large_stats.memory > small_stats.memory
    end

    test "stats update after deletions", %{table_name: table_name} do
      expires_at = System.system_time(:second) + 3600

      # Add entries
      Enum.each(1..10, fn i ->
        ETS.put(table_name, "key_#{i}", "value_#{i}", expires_at)
      end)

      full_stats = ETS.stats(table_name)
      assert full_stats.size == 10

      # Delete some entries
      Enum.each(1..5, fn i ->
        ETS.delete(table_name, "key_#{i}")
      end)

      partial_stats = ETS.stats(table_name)
      assert partial_stats.size == 5
      assert partial_stats.memory < full_stats.memory
    end

    test "stats after clear", %{table_name: table_name} do
      expires_at = System.system_time(:second) + 3600

      # Add entries
      Enum.each(1..100, fn i ->
        ETS.put(table_name, "key_#{i}", "value_#{i}", expires_at)
      end)

      full_stats = ETS.stats(table_name)
      assert full_stats.size == 100

      ETS.clear(table_name)

      empty_stats = ETS.stats(table_name)
      assert empty_stats.size == 0
      assert empty_stats.memory < full_stats.memory
    end

    test "handles stats for non-existent table" do
      nonexistent_table = :nonexistent_table_123

      stats = ETS.stats(nonexistent_table)

      assert stats == %{size: 0, memory: 0}
    end

    test "memory calculation includes word size", %{table_name: table_name} do
      expires_at = System.system_time(:second) + 3600
      word_size = :erlang.system_info(:wordsize)

      ETS.put(table_name, "key", "value", expires_at)
      stats = ETS.stats(table_name)

      # Memory should be a multiple of word size
      assert rem(stats.memory, word_size) == 0
      assert stats.memory > 0
    end
  end

  describe "edge cases and stress tests" do
    setup do
      table_name = :"test_table_#{:erlang.unique_integer([:positive])}"
      ETS.init_storage(table_name)

      on_exit(fn ->
        if :ets.info(table_name) != :undefined do
          :ets.delete(table_name)
        end
      end)

      {:ok, table_name: table_name}
    end

    test "handles very large keys", %{table_name: table_name} do
      large_key = String.duplicate("key", 1000)
      value = "value"
      expires_at = System.system_time(:second) + 3600

      assert ETS.put(table_name, large_key, value, expires_at) == :ok
      assert ETS.get(table_name, large_key) == {:ok, {value, expires_at}}
      assert ETS.delete(table_name, large_key) == :ok
      assert ETS.get(table_name, large_key) == :miss
    end

    test "handles negative expiration times", %{table_name: table_name} do
      key = "negative_exp"
      value = "value"
      expires_at = -1000

      assert ETS.put(table_name, key, value, expires_at) == :ok
      assert ETS.get(table_name, key) == {:ok, {value, expires_at}}
    end

    test "handles zero expiration time", %{table_name: table_name} do
      key = "zero_exp"
      value = "value"
      expires_at = 0

      assert ETS.put(table_name, key, value, expires_at) == :ok
      assert ETS.get(table_name, key) == {:ok, {value, expires_at}}
    end

    test "handles concurrent operations", %{table_name: table_name} do
      num_workers = 50
      operations_per_worker = 100

      tasks =
        Enum.map(1..num_workers, fn worker_id ->
          Task.async(fn ->
            Enum.map(1..operations_per_worker, fn op_id ->
              key = "worker_#{worker_id}_op_#{op_id}"
              value = "value_#{worker_id}_#{op_id}"
              expires_at = System.system_time(:second) + 3600

              # Mix of operations
              case rem(op_id, 4) do
                0 -> ETS.put(table_name, key, value, expires_at)
                1 -> ETS.get(table_name, key)
                2 -> ETS.delete(table_name, key)
                3 -> ETS.cleanup_expired(table_name, System.system_time(:second))
              end
            end)
          end)
        end)

      results = Task.await_many(tasks, 10_000)

      # All tasks should complete without errors
      assert length(results) == num_workers
      assert Enum.all?(results, &is_list/1)
    end
  end
end
