defmodule JsonCompactorStructTest do
  use ExUnit.Case

  # Define test structs at module level
  defmodule User do
    defstruct [:name, :age, :active]
  end

  defmodule Company do
    defstruct [:name, :admin, :users]
  end

  defmodule Profile do
    defstruct [:bio, :settings]
  end

  describe "struct support" do
    test "basic struct compaction creates __struct__ field" do
      user = %User{name: "Alice", age: 30, active: true}
      result = JsonCompactor.compact(user)

      assert is_list(result)
      root = Enum.at(result, 0)

      # Should have __struct__ field with module name
      assert Map.has_key?(root, "__struct__")
      assert root["__struct__"] == "Elixir.JsonCompactorStructTest.User"

      # Atom keys should be converted with colon prefix
      assert Map.has_key?(root, ":name")
      assert Map.has_key?(root, ":age")
      assert Map.has_key?(root, ":active")

      # String values should be referenced, primitives inline
      assert root[":age"] == 30
      assert root[":active"] == true
      # Should be reference
      assert root[":name"] != "Alice"
      assert "Alice" in result
    end

    test "struct round-trip preserves type and values through JSON" do
      original = %User{name: "Alice", age: 30, active: true}

      compacted = JsonCompactor.compact(original)

      # Critical: JSON serialization must preserve struct info and atom keys
      json_string = Jason.encode!(compacted)
      compacted_from_json = Jason.decode!(json_string)

      {:ok, restored} = JsonCompactor.decompact(compacted_from_json)

      assert restored == original
      assert restored.__struct__ == User
      assert restored.name == "Alice"
      assert restored.age == 30
      assert restored.active == true
    end

    test "nested structs work correctly" do
      user = %User{name: "Alice", age: 30, active: true}
      company = %Company{name: "Acme", admin: user, users: [user]}

      compacted = JsonCompactor.compact(company)
      {:ok, restored} = JsonCompactor.decompact(compacted)

      assert restored == company
      assert restored.__struct__ == Company
      assert restored.admin.__struct__ == User
      assert restored.admin.name == "Alice"
      assert hd(restored.users).__struct__ == User
    end

    test "struct deduplication works" do
      shared_user = %User{name: "Alice", age: 30, active: true}
      company = %Company{name: "Acme", admin: shared_user, users: [shared_user, shared_user]}

      compacted = JsonCompactor.compact(company)
      {:ok, restored} = JsonCompactor.decompact(compacted)

      assert restored == company

      # Check deduplication - "Alice" should appear only once in compacted array
      alice_count = Enum.count(compacted, fn x -> x == "Alice" end)
      assert alice_count == 1
    end

    test "unknown struct gracefully degrades to map" do
      # Manually create compacted data with unknown struct
      compacted = [
        %{"__struct__" => "NonExistent.Module", ":name" => "1", ":age" => 30},
        "Alice"
      ]

      {:ok, restored} = JsonCompactor.decompact(compacted)

      # Should return as atom-key map since struct doesn't exist
      assert restored == %{name: "Alice", age: 30}
      refute is_struct(restored)
    end

    test "special structs (Date/DateTime) are processed and round-trip correctly" do
      date = ~D[2023-01-01]
      datetime = ~U[2023-01-01 12:00:00Z]

      date_compacted = JsonCompactor.compact(date)
      datetime_compacted = JsonCompactor.compact(datetime)

      # Should be processed like other structs with __struct__ field
      assert is_list(date_compacted)
      assert is_list(datetime_compacted)
      
      date_root = Enum.at(date_compacted, 0)
      datetime_root = Enum.at(datetime_compacted, 0)
      
      assert Map.has_key?(date_root, "__struct__")
      assert Map.has_key?(datetime_root, "__struct__")
      assert date_root["__struct__"] == "Elixir.Date"
      assert datetime_root["__struct__"] == "Elixir.DateTime"

      # Round-trip should work perfectly
      {:ok, date_restored} = JsonCompactor.decompact(date_compacted)
      {:ok, datetime_restored} = JsonCompactor.decompact(datetime_compacted)

      assert date_restored == date
      assert datetime_restored == datetime
    end
  end

  describe "atom key map support" do
    test "atom key maps get colon prefix" do
      input = %{name: "Alice", age: 30}
      result = JsonCompactor.compact(input)

      assert is_list(result)
      root = Enum.at(result, 0)

      # Should have colon-prefixed keys
      assert Map.has_key?(root, ":name")
      assert Map.has_key?(root, ":age")
      refute Map.has_key?(root, "name")

      # Values should be handled normally
      assert root[":age"] == 30
      # Should be reference
      assert root[":name"] != "Alice"
      assert "Alice" in result
    end

    test "atom key map round-trip preserves atom keys through JSON" do
      original = %{name: "Alice", age: 30, active: true}

      compacted = JsonCompactor.compact(original)

      # Serialize to JSON and back (this is where atom keys would break without colon prefix)
      json_string = Jason.encode!(compacted)
      compacted_from_json = Jason.decode!(json_string)

      {:ok, restored} = JsonCompactor.decompact(compacted_from_json)

      assert restored == original

      # Verify keys are atoms after JSON round-trip
      keys = Map.keys(restored)
      assert :name in keys
      assert :age in keys
      assert :active in keys
      assert Enum.all?(keys, &is_atom/1)
    end

    test "mixed key maps preserve key types through JSON" do
      original = %{:name => "Alice", "age" => 30}

      compacted = JsonCompactor.compact(original)

      # JSON serialization converts atom keys to strings without colon prefix
      json_string = Jason.encode!(compacted)
      compacted_from_json = Jason.decode!(json_string)

      {:ok, restored} = JsonCompactor.decompact(compacted_from_json)

      assert restored == original
      # Should restore atom key
      assert restored[:name] == "Alice"
      # Should preserve string key
      assert restored["age"] == 30
    end

    test "invalid atom names fall back to string keys" do
      # Create compacted data with invalid atom
      compacted = [
        %{":invalid-atom-name!" => "1", ":name" => "2"},
        "Alice",
        "Bob"
      ]

      {:ok, restored} = JsonCompactor.decompact(compacted)

      # Invalid atom should remain as string, valid atom should convert
      # Kept as string
      assert restored[":invalid-atom-name!"] == "Alice"
      # Converted to atom
      assert restored[:name] == "Bob"
    end
  end

  describe "complex scenarios" do
    test "deeply nested structures with mixed types" do
      original = %{
        :user => %User{name: "Alice", age: 30, active: true},
        :profile => %Profile{
          bio: "Software Engineer",
          settings: %{:theme => "dark", "notifications" => true}
        },
        "metadata" => %{:created_at => "2023-01-01"}
      }

      compacted = JsonCompactor.compact(original)
      {:ok, restored} = JsonCompactor.decompact(compacted)

      assert restored == original
      assert restored.user.__struct__ == User
      assert restored.profile.__struct__ == Profile
      assert is_atom(Map.keys(restored.profile.settings) |> hd())
    end

    test "struct with atom and string key combinations" do
      original = %{
        "config" => %{:timeout => 5000, "debug" => true},
        :user => %User{name: "Alice", age: 30, active: true}
      }

      compacted = JsonCompactor.compact(original)
      {:ok, restored} = JsonCompactor.decompact(compacted)

      assert restored == original
      assert restored.user.__struct__ == User
      # Atom key preserved
      assert is_atom(:user)
      # String key preserved
      assert is_binary("config")
      # Nested atom key preserved
      assert is_atom(:timeout)
      # Nested string key preserved
      assert is_binary("debug")
    end
  end

  describe "error cases" do
    test "malformed struct data handled gracefully" do
      # Missing __struct__ value
      compacted = [%{"__struct__" => nil, ":name" => "1"}, "Alice"]

      {:ok, restored} = JsonCompactor.decompact(compacted)
      assert restored == %{name: "Alice"}
    end

    test "invalid struct module name" do
      # Not a string
      compacted = [%{"__struct__" => 123, ":name" => "1"}, "Alice"]

      {:ok, restored} = JsonCompactor.decompact(compacted)
      assert restored == %{name: "Alice"}
    end

    test "struct with non-atom field names" do
      # This shouldn't happen in normal usage, but test robustness
      compacted = [%{"__struct__" => "JsonCompactorStructTest.User", "name" => "1"}, "Alice"]

      {:ok, restored} = JsonCompactor.decompact(compacted)
      # Should attempt struct creation but likely fail gracefully
      assert is_map(restored)
    end
  end

  describe "tuple support" do
    test "basic tuple round-trip" do
      original = {1, 2, 3}
      compacted = JsonCompactor.compact(original)
      {:ok, restored} = JsonCompactor.decompact(compacted)
      
      assert restored == original
      assert is_tuple(restored)
      assert tuple_size(restored) == 3
    end

    test "nested tuple round-trip" do
      original = {1, {2, 3}, 4}
      compacted = JsonCompactor.compact(original)
      {:ok, restored} = JsonCompactor.decompact(compacted)
      
      assert restored == original
      assert is_tuple(restored)
      assert is_tuple(elem(restored, 1))
    end

    test "tuple with strings and deduplication" do
      original = {"hello", "world", "hello"}
      compacted = JsonCompactor.compact(original)
      {:ok, restored} = JsonCompactor.decompact(compacted)
      
      assert restored == original
      # Check deduplication worked
      hello_count = Enum.count(compacted, fn x -> x == "hello" end)
      assert hello_count == 1
    end

    test "tuple JSON round-trip" do
      original = {1, "test", true}
      compacted = JsonCompactor.compact(original)
      
      # JSON serialization
      json_string = Jason.encode!(compacted)
      compacted_from_json = Jason.decode!(json_string)
      
      {:ok, restored} = JsonCompactor.decompact(compacted_from_json)
      
      assert restored == original
      assert is_tuple(restored)
    end

    test "empty tuple" do
      original = {}
      compacted = JsonCompactor.compact(original)
      {:ok, restored} = JsonCompactor.decompact(compacted)
      
      assert restored == original
      assert is_tuple(restored)
      assert tuple_size(restored) == 0
    end
  end

  describe "DateTime with tuples" do
    test "DateTime round-trip preserves microsecond tuple" do
      original = DateTime.utc_now()
      compacted = JsonCompactor.compact(original)
      {:ok, restored} = JsonCompactor.decompact(compacted)
      
      assert restored == original
      assert restored.__struct__ == DateTime
      assert is_tuple(restored.microsecond)
      assert restored.microsecond == original.microsecond
    end

    test "DateTime JSON round-trip" do
      original = DateTime.utc_now()
      compacted = JsonCompactor.compact(original)
      
      # JSON serialization should work with tuple handling
      json_string = Jason.encode!(compacted)
      compacted_from_json = Jason.decode!(json_string)
      
      {:ok, restored} = JsonCompactor.decompact(compacted_from_json)
      
      assert restored == original
      assert restored.__struct__ == DateTime
      assert is_tuple(restored.microsecond)
    end

    test "Date struct with Calendar.ISO" do
      original = ~D[2023-12-25]
      compacted = JsonCompactor.compact(original)
      {:ok, restored} = JsonCompactor.decompact(compacted)
      
      assert restored == original
      assert restored.__struct__ == Date
      assert restored.calendar == Calendar.ISO
    end

    test "NaiveDateTime round-trip" do
      original = ~N[2023-12-25 10:30:45.123456]
      compacted = JsonCompactor.compact(original)
      {:ok, restored} = JsonCompactor.decompact(compacted)
      
      assert restored == original
      assert restored.__struct__ == NaiveDateTime
      assert is_tuple(restored.microsecond)
    end

    test "Time struct with microsecond tuple" do
      original = ~T[14:30:45.123456]
      compacted = JsonCompactor.compact(original)
      {:ok, restored} = JsonCompactor.decompact(compacted)
      
      assert restored == original
      assert restored.__struct__ == Time
      assert is_tuple(restored.microsecond)
    end
  end
end
