defmodule DictCompactorTest do
  use ExUnit.Case

  # Define a test struct
  defmodule TestUser do
    defstruct [:name, :age, :role]
  end

  describe "compact/1" do
    test "handles primitive values without referencing" do
      # Numbers, booleans, nil should not be referenced
      assert DictCompactor.compact(42) == %{
               data: 42,
               dictionary: []
             }

      assert DictCompactor.compact(true) == %{
               data: true,
               dictionary: []
             }

      assert DictCompactor.compact(nil) == %{
               data: nil,
               dictionary: []
             }
    end

    test "references strings in dictionary" do
      result = DictCompactor.compact("hello")

      assert result == %{
               data: "0",
               dictionary: ["hello"]
             }
    end

    test "references atom strings in dictionary" do
      result = DictCompactor.compact(:hello)

      assert result == %{
               data: "0",
               dictionary: ["_:hello"]
             }
    end

    test "does not reference boolean atoms" do
      assert DictCompactor.compact(true) == %{
               data: true,
               dictionary: []
             }

      assert DictCompactor.compact(false) == %{
               data: false,
               dictionary: []
             }

      assert DictCompactor.compact(nil) == %{
               data: nil,
               dictionary: []
             }
    end

    test "handles simple maps with string key and value references" do
      input = %{"name" => "Alice", "role" => "admin"}
      result = DictCompactor.compact(input)

      assert result == %{
               data: %{"0" => "1", "2" => "3"},
               dictionary: ["name", "Alice", "role", "admin"]
             }
    end

    test "handles maps with atom keys" do
      input = %{name: "Alice", role: "admin"}
      result = DictCompactor.compact(input)

      # Atom keys converted to strings and referenced
      assert result == %{
               data: %{"0" => "1", "2" => "3"},
               dictionary: ["_:name", "Alice", "_:role", "admin"]
             }
    end

    test "handles lists without referencing the list itself" do
      input = ["hello", 42, "world"]
      result = DictCompactor.compact(input)

      assert result == %{
               data: ["0", 42, "1"],
               dictionary: ["hello", "world"]
             }
    end

    test "serializes tuples as JSON arrays without referencing the array" do
      input = {1, "hello", :world}
      result = DictCompactor.compact(input)

      assert result == %{
               data: ["__t__", 1, "0", "1"],
               dictionary: ["hello", "_:world"]
             }
    end

    test "serializes structs as JSON objects without referencing the object" do
      input = %TestUser{name: "Alice", age: 30, role: :admin}
      result = DictCompactor.compact(input)

      assert result == %{
               data: %{"__struct__" => "0", "1" => 30, "2" => "3", "4" => "5"},
               dictionary: ["Elixir.DictCompactorTest.TestUser", "_:age", "_:name", "Alice", "_:role", "_:admin"]
             }
    end

    test "deduplicates identical strings" do
      input = %{
        "user1" => %{"name" => "Alice", "role" => "admin"},
        "user2" => %{"name" => "Alice", "role" => "user"}
      }

      result = DictCompactor.compact(input)

      # "Alice" should appear only once in dictionary
      alice_count = Enum.count(result.dictionary, fn v -> v == "Alice" end)

      assert alice_count == 1

      # "name" should appear only once in dictionary
      name_count = Enum.count(result.dictionary, fn v -> v == "name" end)

      assert name_count == 1
    end

    test "deduplicates identical atom strings" do
      input = [:admin, :admin, :user, :admin]
      result = DictCompactor.compact(input)

      # "_:admin" should appear only once in dictionary
      admin_count = Enum.count(result.dictionary, fn v -> v == "_:admin" end)

      assert admin_count == 1

      assert result == %{
               data: ["0", "0", "1", "0"],
               dictionary: ["_:admin", "_:user"]
             }
    end

    test "handles nested structures" do
      input = %{
        "config" => %{
          "database" => %{"host" => "localhost", "port" => 5432},
          "cache" => %{"host" => "localhost", "ttl" => 300}
        }
      }

      result = DictCompactor.compact(input)

      # "localhost" should be deduplicated
      localhost_count = Enum.count(result.dictionary, fn v -> v == "localhost" end)

      assert localhost_count == 1

      # "host" should be deduplicated
      host_count = Enum.count(result.dictionary, fn v -> v == "host" end)

      assert host_count == 1
    end

    test "produces deterministic output" do
      input = %{"b" => "second", "a" => "first", "c" => "third"}

      result1 = DictCompactor.compact(input)
      result2 = DictCompactor.compact(input)

      assert result1 == result2
    end

    test "handles empty structures" do
      assert DictCompactor.compact(%{}) == %{
               data: %{},
               dictionary: []
             }

      assert DictCompactor.compact([]) == %{
               data: [],
               dictionary: []
             }
    end
  end

  describe "decompact/1" do
    test "handles primitive values" do
      compacted = %{data: 42, dictionary: []}
      assert DictCompactor.decompact(compacted) == {:ok, 42}

      compacted = %{data: "hello", dictionary: []}
      assert DictCompactor.decompact(compacted) == {:ok, "hello"}
    end

    test "decompacts simple string references" do
      compacted = %{
        data: "0",
        dictionary: ["hello"]
      }

      assert DictCompactor.decompact(compacted) == {:ok, "hello"}
    end

    test "decompacts atom string references" do
      compacted = %{
        data: "0",
        dictionary: ["_:hello"]
      }

      assert DictCompactor.decompact(compacted) == {:ok, :hello}
    end

    test "decompacts maps with string references" do
      compacted = %{
        data: %{"0" => "1", "2" => "3"},
        dictionary: ["name", "Alice", "role", "admin"]
      }

      expected = %{"name" => "Alice", "role" => "admin"}
      assert DictCompactor.decompact(compacted) == {:ok, expected}
    end

    test "decompacts tuple arrays back to tuples" do
      compacted = %{
        data: ["__t__", 1, "0", "1"],
        dictionary: ["hello", "_:world"]
      }

      assert DictCompactor.decompact(compacted) == {:ok, {1, "hello", :world}}
    end

    test "decompacts struct objects back to structs" do
      compacted = %{
        data: %{
          "0" => "1",
          "2" => 30,
          "3" => "4",
          "__struct__" => "5"
        },
        dictionary: ["_:name", "Alice", "_:age", "_:role", "_:admin", "Elixir.DictCompactorTest.TestUser"]
      }

      expected = %TestUser{name: "Alice", age: 30, role: :admin}
      assert DictCompactor.decompact(compacted) == {:ok, expected}
    end

    test "decompacts nested structures" do
      compacted = %{
        data: %{
          "0" => %{"1" => "2", "3" => 5432},
          "4" => %{"1" => "2", "5" => 300}
        },
        dictionary: ["database", "host", "localhost", "port", "cache", "ttl"]
      }

      expected = %{
        "database" => %{"host" => "localhost", "port" => 5432},
        "cache" => %{"host" => "localhost", "ttl" => 300}
      }

      assert DictCompactor.decompact(compacted) == {:ok, expected}
    end

    test "returns error for invalid input format" do
      assert DictCompactor.decompact("not a map") == {:error, "Invalid compacted data format"}
      assert DictCompactor.decompact(%{data: "test"}) == {:error, "Invalid compacted data format"}

      assert DictCompactor.decompact(%{dictionary: []}) ==
               {:error, "Invalid compacted data format"}
    end

    test "handles missing dictionary references gracefully" do
      compacted = %{
        # "99" doesn't exist in dictionary (out of bounds)
        data: %{"0" => "99"},
        dictionary: ["name"]
      }

      # Should return the reference as-is if not found in dictionary
      assert DictCompactor.decompact(compacted) == {:ok, %{"name" => "99"}}
    end
  end

  describe "round-trip testing" do
    test "primitive round-trip" do
      primitives = ["hello", :atom, 42, true, false, nil, 3.14]

      Enum.each(primitives, fn original ->
        compacted = DictCompactor.compact(original)
        {:ok, restored} = DictCompactor.decompact(compacted)
        assert restored == original
      end)
    end

    test "simple map round-trip" do
      original = %{"name" => "Alice", "age" => 30, role: :admin}

      compacted = DictCompactor.compact(original)
      {:ok, restored} = DictCompactor.decompact(compacted)

      assert restored == original
    end

    test "tuple round-trip" do
      original = {1, "hello", :world, true, nil}

      compacted = DictCompactor.compact(original)
      {:ok, restored} = DictCompactor.decompact(compacted)

      assert restored == original
    end

    test "struct round-trip" do
      original = %TestUser{name: "Bob", age: 25, role: :developer}

      compacted = DictCompactor.compact(original)
      {:ok, restored} = DictCompactor.decompact(compacted)

      assert restored == original
    end

    test "complex nested structure round-trip" do
      original = %{
        users: [
          %TestUser{name: "Alice", age: 30, role: :admin},
          %TestUser{name: "Bob", age: 25, role: :user}
        ],
        config: %{
          database: %{host: "localhost", port: 5432},
          cache: %{host: "localhost", ttl: 300}
        },
        metadata: {
          :version,
          "1.0",
          [:feature_a, :feature_b],
          %{enabled: true, debug: false}
        }
      }

      compacted = DictCompactor.compact(original)
      {:ok, restored} = DictCompactor.decompact(compacted)

      assert restored == original
    end

    test "deduplication preservation round-trip" do
      # Create data with lots of duplication
      shared_config = %{timeout: 30, retries: 3, host: "localhost"}

      original = %{
        service_a: shared_config,
        service_b: shared_config,
        service_c: %{timeout: 30, host: "localhost", debug: true}
      }

      compacted = DictCompactor.compact(original)
      {:ok, restored} = DictCompactor.decompact(compacted)

      assert restored == original

      # Verify deduplication happened
      localhost_count = Enum.count(compacted.dictionary, fn v -> v == "localhost" end)
      # "localhost" appears only once
      assert localhost_count == 1
    end

    test "empty structures round-trip" do
      empty_map = %{}
      empty_list = []
      empty_tuple = {}

      assert {:ok, ^empty_map} =
               empty_map |> DictCompactor.compact() |> DictCompactor.decompact()

      assert {:ok, ^empty_list} =
               empty_list |> DictCompactor.compact() |> DictCompactor.decompact()

      assert {:ok, ^empty_tuple} =
               empty_tuple |> DictCompactor.compact() |> DictCompactor.decompact()
    end
  end

  describe "edge cases" do
    test "handles very deeply nested structures" do
      # Create 10-level deep nesting
      deep_structure =
        Enum.reduce(1..10, %{value: "deep"}, fn i, acc ->
          %{"level_#{i}" => acc}
        end)

      compacted = DictCompactor.compact(deep_structure)
      {:ok, restored} = DictCompactor.decompact(compacted)

      assert restored == deep_structure
    end

    test "handles large lists with duplication" do
      # Create list with repeated values
      large_list =
        Enum.flat_map(1..50, fn i ->
          ["item_#{rem(i, 5)}", :common_atom, i]
        end)

      compacted = DictCompactor.compact(large_list)
      {:ok, restored} = DictCompactor.decompact(compacted)

      assert restored == large_list

      # Verify deduplication
      common_atom_count = Enum.count(compacted.dictionary, fn v -> v == "_:common_atom" end)
      assert common_atom_count == 1
    end

    test "handles maps with string keys that look like indices" do
      original = %{
        "0" => "value_zero",
        "1" => "value_one",
        "10" => "value_ten",
        "normal_key" => "normal_value"
      }

      compacted = DictCompactor.compact(original)
      {:ok, restored} = DictCompactor.decompact(compacted)

      assert restored == original
    end

    test "handles mixed atom and string keys" do
      original = %{
        "string_key" => "string_value",
        :another_atom => :atom_value,
        atom_key: "atom_key_value"
      }

      compacted = DictCompactor.compact(original)
      {:ok, restored} = DictCompactor.decompact(compacted)

      assert restored == original
    end
  end
end
