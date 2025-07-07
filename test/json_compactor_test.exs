defmodule JsonCompactorTest do
  use ExUnit.Case
  # doctest JsonCompactor

  describe "compact/1" do
    test "wraps non-referenceable values in a list without creating references" do
      assert JsonCompactor.compact(42) == [42]
      assert JsonCompactor.compact(true) == [true]
      assert JsonCompactor.compact(false) == [false]
      assert JsonCompactor.compact(nil) == [nil]
      assert JsonCompactor.compact(3.14) == [3.14]
    end

    test "creates references for strings" do
      assert JsonCompactor.compact("hello") == ["hello"]
    end

    test "wraps empty structures in a list without creating references" do
      assert JsonCompactor.compact(%{}) == [%{}]
      assert JsonCompactor.compact([]) == [[]]
    end

    test "creates references only for strings in maps" do
      input = %{"name" => "Alice", "age" => 30, "active" => true}
      result = JsonCompactor.compact(input)

      assert is_list(result)
      # Root map + "Alice" string
      assert length(result) == 2
      assert Enum.at(result, 0) == %{"name" => "1", "age" => 30, "active" => true}
      assert "Alice" in result
    end

    test "creates references only for strings in lists" do
      input = ["hello", 42, true, "world"]
      result = JsonCompactor.compact(input)

      assert is_list(result)
      # Root list + "hello" + "world"
      assert length(result) == 3
      assert Enum.at(result, 0) == ["1", 42, true, "2"]
      assert "hello" in result
      assert "world" in result
    end

    test "keeps primitives as original values in complex structures" do
      input = %{
        "numbers" => [1, 2, 3],
        "booleans" => [true, false],
        "null_value" => nil,
        "string_value" => "text"
      }

      result = JsonCompactor.compact(input)

      # Should create references for: root map, "numbers" list, "booleans" list, "text" string
      assert is_list(result)

      root = Enum.at(result, 0)
      # Numbers and booleans should stay as original values
      assert is_map(root)
      assert root["null_value"] == nil

      # But string should be referenced
      assert is_binary(root["string_value"]) and root["string_value"] != "text"
      assert "text" in result
    end

    test "deduplicates identical strings only" do
      input = ["hello", "hello", 42, 42, "world", "hello"]
      result = JsonCompactor.compact(input)

      # Should only have: root list, "hello", "world"
      # Numbers 42 should stay as original values in the list
      assert length(result) == 3
      assert Enum.at(result, 0) == ["1", "1", 42, 42, "2", "1"]
      assert "hello" in result
      assert "world" in result

      # Count occurrences - "hello" should appear only once in the array
      hello_count = Enum.count(result, fn x -> x == "hello" end)
      assert hello_count == 1

      # But 42 should appear multiple times as original values
      forty_two_count = Enum.count(Enum.at(result, 0), fn x -> x == 42 end)
      assert forty_two_count == 2
    end

    test "deduplicates identical maps and strings" do
      shared_map = %{"name" => "Alice", "role" => "admin"}

      input = %{
        "user1" => shared_map,
        "user2" => shared_map,
        "user3" => %{"name" => "Bob", "age" => 25, "manager" => shared_map},
        "user4" => %{"name" => "Bob", "age" => 25, "manager" => shared_map}
      }

      result = JsonCompactor.compact(input)

      # Should deduplicate the shared map and strings
      assert is_list(result)
      IO.inspect(result, label: "Compacted Result")

      # Find the root map
      root = Enum.at(result, 0)
      # Same map reference
      assert root["user1"] == root["user2"]
      # Different map reference
      assert root["user1"] != root["user3"]

      # Check that "Alice" string is deduplicated
      alice_count = Enum.count(result, fn x -> x == "Alice" end)
      assert alice_count == 1
    end

    test "deduplicates identical lists" do
      shared_list = [1, 2, 3]

      input = %{
        "list1" => shared_list,
        "list2" => shared_list,
        "list3" => [4, 5, 6]
      }

      result = JsonCompactor.compact(input)
      root = Enum.at(result, 0)

      # Same reference
      assert root["list1"] == root["list2"]
      # Different reference
      assert root["list1"] != root["list3"]
    end

    test "handles deeply nested structures" do
      input = %{
        "level1" => %{
          "level2" => %{
            "level3" => %{
              "value" => "deep"
            }
          }
        }
      }

      result = JsonCompactor.compact(input)

      assert result == [
               %{"level1" => "1"},
               %{"level2" => "2"},
               %{"level3" => "3"},
               %{"value" => "4"},
               "deep"
             ]
    end

    test "produces deterministic output" do
      input = %{"b" => "second", "a" => "first", "c" => "third"}

      result1 = JsonCompactor.compact(input)
      result2 = JsonCompactor.compact(input)

      assert result1 == result2
    end
  end

  describe "decompact/1" do
    test "unwraps primitive values from single-item lists" do
      assert JsonCompactor.decompact(["hello"]) == {:ok, "hello"}
      assert JsonCompactor.decompact([42]) == {:ok, 42}
      assert JsonCompactor.decompact([true]) == {:ok, true}
      assert JsonCompactor.decompact([false]) == {:ok, false}
      assert JsonCompactor.decompact([nil]) == {:ok, nil}
    end

    test "returns error for invalid input types" do
      assert JsonCompactor.decompact("not a list") == {:error, "Input must be a list"}
      assert JsonCompactor.decompact(42) == {:error, "Input must be a list"}
    end

    test "returns error for empty list" do
      assert JsonCompactor.decompact([]) == {:error, "Cannot decompact empty list"}
    end

    test "decompacts simple structures" do
      compacted = [%{"name" => "1"}, "Alice"]
      {:ok, result} = JsonCompactor.decompact(compacted)

      assert result == %{"name" => "Alice"}
    end

    test "decompacts nested structures" do
      compacted = [
        %{"user" => "1"},
        %{"profile" => "2"},
        %{"name" => "3"},
        "Alice"
      ]

      {:ok, result} = JsonCompactor.decompact(compacted)
      expected = %{"user" => %{"profile" => %{"name" => "Alice"}}}

      assert result == expected
    end

    test "handles list decompaction" do
      compacted = [["1", "2", "3"], "first", "second", "third"]
      {:ok, result} = JsonCompactor.decompact(compacted)

      assert result == ["first", "second", "third"]
    end

    test "resolves duplicate references correctly" do
      compacted = [
        %{"user1" => "1", "user2" => "1"},
        %{"name" => "2"},
        "Alice"
      ]

      {:ok, result} = JsonCompactor.decompact(compacted)

      expected = %{
        "user1" => %{"name" => "Alice"},
        "user2" => %{"name" => "Alice"}
      }

      assert result == expected
    end

    test "returns error for invalid references" do
      compacted = [%{"invalid" => "99"}, "valid"]

      assert JsonCompactor.decompact(compacted) ==
               {:error, "Reference index 99 is out of bounds for array of length 2"}
    end

    test "detects circular references in compacted data" do
      # This tests that the decompact can detect self-referential structures
      # that might occur in the compacted format
      compacted = [
        # References itself
        %{"self" => "0"},
        "other_value"
      ]

      # This should detect the circular reference and return an error
      assert JsonCompactor.decompact(compacted) ==
               {:error, "Circular reference detected at index 0"}
    end
  end

  describe "round-trip testing" do
    test "primitive round-trip" do
      primitives = ["hello", 42, true, false, nil, 3.14]

      Enum.each(primitives, fn original ->
        compacted = JsonCompactor.compact(original)
        {:ok, restored} = JsonCompactor.decompact(compacted)
        assert restored == original
      end)
    end

    test "simple round-trip" do
      original = %{"name" => "Alice", "age" => 30}

      compacted = JsonCompactor.compact(original)
      {:ok, restored} = JsonCompactor.decompact(compacted)

      assert restored == original
    end

    test "complex round-trip with deduplication" do
      shared_user = %{"name" => "Alice", "role" => "admin"}

      original = %{
        "primary_user" => shared_user,
        "backup_user" => shared_user,
        "settings" => %{"theme" => "dark", "notifications" => true}
      }

      compacted = JsonCompactor.compact(original)
      {:ok, restored} = JsonCompactor.decompact(compacted)

      assert restored == original
    end

    test "list round-trip" do
      original = [
        %{"id" => 1, "name" => "first"},
        %{"id" => 2, "name" => "second"},
        # Duplicate
        %{"id" => 1, "name" => "first"}
      ]

      compacted = JsonCompactor.compact(original)
      {:ok, restored} = JsonCompactor.decompact(compacted)

      assert restored == original
    end

    test "mixed types round-trip" do
      original = %{
        "users" => [
          %{"name" => "Alice", "active" => true},
          %{"name" => "Bob", "active" => false},
          # Duplicate
          %{"name" => "Alice", "active" => true}
        ],
        "config" => %{
          "timeout" => 30,
          "retries" => 3,
          "debug" => true
        },
        "metadata" => %{
          "version" => "1.0",
          # Duplicate value
          "timeout" => 30
        }
      }

      compacted = JsonCompactor.compact(original)
      {:ok, restored} = JsonCompactor.decompact(compacted)

      assert restored == original
    end

    test "deeply nested round-trip" do
      original = %{
        "a" => %{
          "b" => %{
            "c" => %{
              "d" => %{
                "e" => "deep_value"
              }
            }
          }
        },
        # Same as nested value
        "shared" => "deep_value"
      }

      compacted = JsonCompactor.compact(original)
      {:ok, restored} = JsonCompactor.decompact(compacted)

      assert restored == original
    end

    test "empty structures round-trip" do
      original_map = %{}
      original_list = []

      compacted_map = JsonCompactor.compact(original_map)
      {:ok, restored_map} = JsonCompactor.decompact(compacted_map)
      assert restored_map == original_map
      assert compacted_map == [%{}]

      compacted_list = JsonCompactor.compact(original_list)
      {:ok, restored_list} = JsonCompactor.decompact(compacted_list)
      assert restored_list == original_list
      assert compacted_list == [[]]
    end
  end

  describe "edge cases" do
    test "handles maps with string keys that look like indices" do
      original = %{
        "0" => "first",
        "1" => "second",
        "normal_key" => "third"
      }

      compacted = JsonCompactor.compact(original)
      {:ok, restored} = JsonCompactor.decompact(compacted)

      assert restored == original
    end

    test "handles very large structures" do
      # Generate a larger structure for performance testing
      large_list =
        Enum.map(1..100, fn i ->
          %{"id" => i, "value" => "item_#{i}", "common" => "shared_value"}
        end)

      original = %{"items" => large_list}

      compacted = JsonCompactor.compact(original)
      {:ok, restored} = JsonCompactor.decompact(compacted)

      assert restored == original

      # Should have significant deduplication due to "shared_value"
      compacted_size = length(compacted)
      # Should be much less than 100 * 3 + overhead due to deduplication
      assert compacted_size == 203
    end

    test "handles numeric string values" do
      original = %{
        "numeric_string" => "123",
        "actual_number" => 123,
        "reference_like" => "1"
      }

      compacted = JsonCompactor.compact(original)
      IO.inspect(compacted, label: "Compacted Result")
      {:ok, restored} = JsonCompactor.decompact(compacted)

      assert restored == original
      # Ensure types are preserved
      assert restored["numeric_string"] == "123"
      assert restored["actual_number"] == 123
      assert is_binary(restored["numeric_string"])
      assert is_integer(restored["actual_number"])
    end
  end
end
