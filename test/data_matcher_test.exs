defmodule DataMatcherTest do
  use ExUnit.Case
  doctest DataMatcher

  describe "match/2 - exact value matching" do
    test "matches identical primitives" do
      assert DataMatcher.match(1, 1) == true
      assert DataMatcher.match(1.5, 1.5) == true
      assert DataMatcher.match("name", "name") == true
      assert DataMatcher.match(:admin, :admin) == true
      assert DataMatcher.match(true, true) == true
      assert DataMatcher.match(false, false) == true
      assert DataMatcher.match(nil, nil) == true
    end

    test "fails on type mismatches (strict typing)" do
      assert DataMatcher.match(1, "1") == false
      assert DataMatcher.match(1, 1.0) == false
      assert DataMatcher.match(:atom, "atom") == false
      assert DataMatcher.match(true, "true") == false
      assert DataMatcher.match(nil, 0) == false
      assert DataMatcher.match(nil, false) == false
    end

    test "fails on different values of same type" do
      assert DataMatcher.match(1, 2) == false
      assert DataMatcher.match("hello", "world") == false
      assert DataMatcher.match(:admin, :user) == false
      assert DataMatcher.match(true, false) == false
    end
  end

  describe "match/2 - string pattern matching" do
    test "matches with * wildcard (zero or more chars)" do
      assert DataMatcher.match("dev-octosell", "*-octosell") == true
      assert DataMatcher.match("john-doe", "john-*") == true
      assert DataMatcher.match("test123", "test*") == true
      assert DataMatcher.match("hello", "*") == true
      assert DataMatcher.match("", "*") == true
      assert DataMatcher.match("prefix-middle-suffix", "*-middle-*") == true
    end

    test "matches with ? wildcard (single char)" do
      assert DataMatcher.match("hello", "h?llo") == true
      assert DataMatcher.match("hallo", "h?llo") == true
      assert DataMatcher.match("test1", "test?") == true
      assert DataMatcher.match("a", "?") == true
    end

    test "matches with combined wildcards" do
      assert DataMatcher.match("hello123", "h?llo*") == true
      assert DataMatcher.match("test-file.txt", "test-*.t?t") == true
    end

    test "fails string pattern matching" do
      assert DataMatcher.match("dev-octosell", "*-other") == false
      assert DataMatcher.match("john-doe", "jane-*") == false
      # too short
      assert DataMatcher.match("hello", "h?l") == false
      # too many chars
      assert DataMatcher.match("hello", "h??llo") == false
      # empty string doesn't match single char
      assert DataMatcher.match("", "?") == false
    end

    test "handles special regex characters in patterns" do
      # . should be literal
      assert DataMatcher.match("test.txt", "test.*") == true
      # [ ] should be literal
      assert DataMatcher.match("test[1]", "test[*]") == true
      # + should be literal
      assert DataMatcher.match("test+file", "test+*") == true
    end
  end

  describe "match/2 - map matching" do
    test "matches exact maps" do
      assert DataMatcher.match(%{name: "me", age: 15}, %{name: "me", age: 15}) == true
      assert DataMatcher.match(%{}, %{}) == true
    end

    test "matches subset patterns (pattern keys must exist in data)" do
      assert DataMatcher.match(%{name: "me", age: 15}, %{name: "me"}) == true

      assert DataMatcher.match(%{name: "me", age: 15, role: "admin"}, %{name: "me", age: 15}) ==
               true
    end

    test "supports string patterns in map values" do
      assert DataMatcher.match(%{team: "dev-octosell"}, %{team: "*-octosell"}) == true
      assert DataMatcher.match(%{file: "test.txt"}, %{file: "*.txt"}) == true
    end

    test "fails map matching when pattern keys missing in data" do
      assert DataMatcher.match(%{name: "me"}, %{name: "me", age: 15}) == false
      assert DataMatcher.match(%{}, %{name: "me"}) == false
    end

    test "fails map matching when values don't match" do
      assert DataMatcher.match(%{name: "me", age: 15}, %{name: "you"}) == false
      assert DataMatcher.match(%{name: "me", age: 15}, %{age: 20}) == false
    end

    test "fails when data is not a map but pattern is" do
      assert DataMatcher.match("string", %{key: "value"}) == false
      assert DataMatcher.match(123, %{key: "value"}) == false
      assert DataMatcher.match(nil, %{key: "value"}) == false
    end
  end

  describe "match/2 - list matching" do
    test "matches exact lists" do
      assert DataMatcher.match([1, 2, 3], [1, 2, 3]) == true
      assert DataMatcher.match(["a", "b"], ["a", "b"]) == true
      assert DataMatcher.match([], []) == true
    end

    test "matches lists with patterns" do
      assert DataMatcher.match(["test.txt", "doc.pdf"], ["*.txt", "*.pdf"]) == true
      assert DataMatcher.match([%{id: 1}, %{id: 2}], [%{id: 1}, %{id: 2}]) == true
    end

    test "fails when lists have different lengths" do
      assert DataMatcher.match([1, 2], [1, 2, 3]) == false
      assert DataMatcher.match([1, 2, 3], [1, 2]) == false
      assert DataMatcher.match([], [1]) == false
    end

    test "fails when list elements don't match" do
      assert DataMatcher.match([1, 2, 3], [1, 2, 4]) == false
      assert DataMatcher.match(["a", "b"], ["a", "c"]) == false
    end
  end

  describe "any/1 quantifier" do
    test "creates proper quantifier tuple" do
      assert DataMatcher.any("pattern") == {:quantifier, :any, "pattern"}
      assert DataMatcher.any(%{key: "value"}) == {:quantifier, :any, %{key: "value"}}
    end

    test "matches when at least one item matches" do
      assert DataMatcher.match(["js", "elixir"], DataMatcher.any("elixir")) == true
      assert DataMatcher.match([1, 2, 3], DataMatcher.any(2)) == true

      assert DataMatcher.match(
               [%{role: "editor"}, %{role: "admin"}],
               DataMatcher.any(%{role: "admin"})
             ) == true

      assert DataMatcher.match(["test.txt", "doc.pdf"], DataMatcher.any("*.txt")) == true
    end

    test "fails when no items match" do
      assert DataMatcher.match(["js", "python"], DataMatcher.any("elixir")) == false
      assert DataMatcher.match([1, 2, 3], DataMatcher.any(4)) == false
      assert DataMatcher.match([%{role: "editor"}], DataMatcher.any(%{role: "admin"})) == false
    end

    test "fails on empty list" do
      assert DataMatcher.match([], DataMatcher.any(1)) == false
      assert DataMatcher.match([], DataMatcher.any("anything")) == false
    end

    test "fails when data is not a list" do
      assert DataMatcher.match("string", DataMatcher.any("pattern")) == false
      assert DataMatcher.match(%{key: "value"}, DataMatcher.any("pattern")) == false
      assert DataMatcher.match(123, DataMatcher.any(123)) == false
    end
  end

  describe "all/1 quantifier" do
    test "creates proper quantifier tuple" do
      assert DataMatcher.all("pattern") == {:quantifier, :all, "pattern"}
      assert DataMatcher.all(%{key: "value"}) == {:quantifier, :all, %{key: "value"}}
    end

    test "matches when all items match" do
      assert DataMatcher.match(["admin", "admin"], DataMatcher.all("admin")) == true
      assert DataMatcher.match([1, 1, 1], DataMatcher.all(1)) == true

      assert DataMatcher.match(
               [%{active: true}, %{active: true}],
               DataMatcher.all(%{active: true})
             ) == true

      assert DataMatcher.match(["test.txt", "doc.txt"], DataMatcher.all("*.txt")) == true
    end

    test "matches empty list (vacuous truth)" do
      assert DataMatcher.match([], DataMatcher.all(1)) == true
      assert DataMatcher.match([], DataMatcher.all("anything")) == true
    end

    test "fails when some items don't match" do
      assert DataMatcher.match(["admin", "user"], DataMatcher.all("admin")) == false
      assert DataMatcher.match([1, 1, 2], DataMatcher.all(1)) == false

      assert DataMatcher.match(
               [%{active: true}, %{active: false}],
               DataMatcher.all(%{active: true})
             ) == false
    end

    test "fails when data is not a list" do
      assert DataMatcher.match("string", DataMatcher.all("pattern")) == false
      assert DataMatcher.match(%{key: "value"}, DataMatcher.all("pattern")) == false
      assert DataMatcher.match(123, DataMatcher.all(123)) == false
    end
  end

  describe "none/1 quantifier" do
    test "creates proper quantifier tuple" do
      assert DataMatcher.none("pattern") == {:quantifier, :none, "pattern"}
      assert DataMatcher.none(%{key: "value"}) == {:quantifier, :none, %{key: "value"}}
    end

    test "matches when no items match" do
      assert DataMatcher.match(["user", "guest"], DataMatcher.none("admin")) == true
      assert DataMatcher.match([1, 2, 3], DataMatcher.none(4)) == true
      assert DataMatcher.match([%{role: "user"}], DataMatcher.none(%{role: "admin"})) == true
      assert DataMatcher.match(["doc.pdf", "image.jpg"], DataMatcher.none("*.txt")) == true
    end

    test "matches empty list" do
      assert DataMatcher.match([], DataMatcher.none(1)) == true
      assert DataMatcher.match([], DataMatcher.none("anything")) == true
    end

    test "fails when any item matches" do
      assert DataMatcher.match(["user", "admin"], DataMatcher.none("admin")) == false
      assert DataMatcher.match([1, 2, 4], DataMatcher.none(4)) == false
      assert DataMatcher.match([%{role: "admin"}], DataMatcher.none(%{role: "admin"})) == false
    end

    test "fails when data is not a list" do
      assert DataMatcher.match("string", DataMatcher.none("pattern")) == false
      assert DataMatcher.match(%{key: "value"}, DataMatcher.none("pattern")) == false
      assert DataMatcher.match(123, DataMatcher.none(123)) == false
    end
  end

  describe "match/2 - complex nested examples" do
    test "nested map matching" do
      data = %{user: %{name: "john", role: "admin"}, active: true}
      pattern = %{user: %{role: "admin"}}
      assert DataMatcher.match(data, pattern) == true

      # Should fail when nested value doesn't match
      pattern = %{user: %{role: "user"}}
      assert DataMatcher.match(data, pattern) == false
    end

    test "map with list quantifier matching" do
      data = %{name: "me", skills: ["js", "elixir"]}
      pattern = %{skills: DataMatcher.any("elixir")}
      assert DataMatcher.match(data, pattern) == true

      # Should fail when no skills match
      pattern = %{skills: DataMatcher.any("python")}
      assert DataMatcher.match(data, pattern) == false
    end

    test "list of maps with nested patterns" do
      data = [
        %{user: "john", permissions: ["read", "write"]},
        %{user: "jane", permissions: ["read"]}
      ]

      pattern = DataMatcher.any(%{permissions: DataMatcher.any("write")})
      assert DataMatcher.match(data, pattern) == true

      # Should fail when no user has write permission
      pattern = DataMatcher.any(%{permissions: DataMatcher.any("delete")})
      assert DataMatcher.match(data, pattern) == false
    end

    test "complex nested structure with multiple quantifiers" do
      data = %{
        teams: [
          %{name: "dev-octosell", members: ["alice", "bob"]},
          %{name: "qa-octosell", members: ["charlie"]}
        ]
      }

      pattern = %{
        teams: DataMatcher.any(%{name: "*-octosell", members: DataMatcher.any("alice")})
      }

      assert DataMatcher.match(data, pattern) == true

      # Should fail when no team has alice
      pattern = %{
        teams: DataMatcher.any(%{name: "*-octosell", members: DataMatcher.any("david")})
      }

      assert DataMatcher.match(data, pattern) == false
    end
  end

  describe "to_json/1" do
    test "encodes simple patterns" do
      assert DataMatcher.to_json(%{name: "me"}) == "{\"name\":\"me\"}"
      assert DataMatcher.to_json(%{age: 25}) == "{\"age\":25}"
      assert DataMatcher.to_json("simple") == "\"simple\""
      assert DataMatcher.to_json(123) == "123"
      assert DataMatcher.to_json(true) == "true"
      assert DataMatcher.to_json(nil) == "null"
    end

    test "converts atoms to strings" do
      assert DataMatcher.to_json(:admin) == "\"admin\""
      assert DataMatcher.to_json(%{role: :admin}) == "{\"role\":\"admin\"}"
      assert DataMatcher.to_json(%{status: :active}) == "{\"status\":\"active\"}"
    end

    test "encodes lists" do
      assert DataMatcher.to_json([1, 2, 3]) == "[1,2,3]"
      assert DataMatcher.to_json(["a", "b"]) == "[\"a\",\"b\"]"
      assert DataMatcher.to_json([]) == "[]"
    end

    test "encodes quantifiers with proper $quantifier format" do
      pattern = DataMatcher.any(%{enabled: true})
      result = DataMatcher.to_json(pattern)
      assert result == "{\"$quantifier\":\"any\",\"pattern\":{\"enabled\":true}}"

      pattern = DataMatcher.all("admin")
      result = DataMatcher.to_json(pattern)
      assert result == "{\"$quantifier\":\"all\",\"pattern\":\"admin\"}"

      pattern = DataMatcher.none(%{role: :user})
      result = DataMatcher.to_json(pattern)
      assert result == "{\"$quantifier\":\"none\",\"pattern\":{\"role\":\"user\"}}"
    end

    test "encodes complex nested structures" do
      pattern = %{
        user: %{role: :admin},
        permissions: DataMatcher.any("write")
      }

      result = DataMatcher.to_json(pattern)

      expected =
        "{\"permissions\":{\"$quantifier\":\"any\",\"pattern\":\"write\"},\"user\":{\"role\":\"admin\"}}"

      assert result == expected
    end

    test "encodes list with quantifiers" do
      pattern = [%{role: "admin"}, DataMatcher.any(%{active: true})]
      result = DataMatcher.to_json(pattern)
      expected = "[{\"role\":\"admin\"},{\"$quantifier\":\"any\",\"pattern\":{\"active\":true}}]"
      assert result == expected
    end
  end

  describe "from_json/1" do
    test "decodes simple patterns" do
      assert DataMatcher.from_json("{\"name\":\"me\"}") == {:ok, %{"name" => "me"}}
      assert DataMatcher.from_json("{\"age\":25}") == {:ok, %{"age" => 25}}
      assert DataMatcher.from_json("\"simple\"") == {:ok, "simple"}
      assert DataMatcher.from_json("123") == {:ok, 123}
      assert DataMatcher.from_json("true") == {:ok, true}
      assert DataMatcher.from_json("null") == {:ok, nil}
    end

    test "decodes lists" do
      assert DataMatcher.from_json("[1,2,3]") == {:ok, [1, 2, 3]}
      assert DataMatcher.from_json("[\"a\",\"b\"]") == {:ok, ["a", "b"]}
      assert DataMatcher.from_json("[]") == {:ok, []}
    end

    test "decodes quantifiers from $quantifier format" do
      json = "{\"$quantifier\":\"any\",\"pattern\":{\"enabled\":true}}"
      assert DataMatcher.from_json(json) == {:ok, {:quantifier, :any, %{"enabled" => true}}}

      json = "{\"$quantifier\":\"all\",\"pattern\":\"admin\"}"
      assert DataMatcher.from_json(json) == {:ok, {:quantifier, :all, "admin"}}

      json = "{\"$quantifier\":\"none\",\"pattern\":{\"role\":\"user\"}}"
      assert DataMatcher.from_json(json) == {:ok, {:quantifier, :none, %{"role" => "user"}}}
    end

    test "decodes complex nested structures" do
      json =
        "{\"user\":{\"role\":\"admin\"},\"permissions\":{\"$quantifier\":\"any\",\"pattern\":\"write\"}}"

      expected = %{
        "user" => %{"role" => "admin"},
        "permissions" => {:quantifier, :any, "write"}
      }

      assert DataMatcher.from_json(json) == {:ok, expected}
    end

    test "preserves string keys (doesn't convert to atoms)" do
      json = "{\"key\":\"value\"}"
      {:ok, result} = DataMatcher.from_json(json)
      # Key should be string, not atom
      assert is_binary(hd(Map.keys(result)))
    end

    test "handles null values" do
      json = "{\"key\":null}"
      assert DataMatcher.from_json(json) == {:ok, %{"key" => nil}}
    end

    # Error cases
    test "returns error for invalid JSON" do
      assert {:error, "Invalid JSON"} = DataMatcher.from_json("invalid json")
      assert {:error, "Invalid JSON"} = DataMatcher.from_json("{invalid}")
      assert {:error, "Invalid JSON"} = DataMatcher.from_json("{\"key\":}")
    end

    test "returns error for empty JSON string" do
      assert DataMatcher.from_json("") == {:error, "Empty JSON string"}
    end

    test "returns error for unknown quantifier" do
      json = "{\"$quantifier\":\"invalid\",\"pattern\":{}}"
      assert {:error, error_msg} = DataMatcher.from_json(json)
      assert String.contains?(error_msg, "Unknown quantifier")
    end

    test "handles malformed quantifier structure" do
      # Missing pattern
      json = "{\"$quantifier\":\"any\"}"
      assert {:error, _} = DataMatcher.from_json(json)
    end
  end

  describe "JSON round-trip encoding/decoding" do
    test "simple patterns survive round-trip" do
      original = %{name: "test", age: 25}
      json = DataMatcher.to_json(original)
      {:ok, decoded} = DataMatcher.from_json(json)
      # Note: keys become strings after JSON round-trip
      assert decoded == %{"name" => "test", "age" => 25}
    end

    test "quantifiers survive round-trip" do
      original = DataMatcher.any(%{enabled: true})
      json = DataMatcher.to_json(original)
      {:ok, decoded} = DataMatcher.from_json(json)
      assert decoded == {:quantifier, :any, %{"enabled" => true}}
    end

    test "complex patterns survive round-trip" do
      original = %{
        user: %{role: :admin},
        permissions: DataMatcher.any("write"),
        teams: DataMatcher.all(%{active: true})
      }

      json = DataMatcher.to_json(original)
      {:ok, decoded} = DataMatcher.from_json(json)

      expected = %{
        "user" => %{"role" => "admin"},
        "permissions" => {:quantifier, :any, "write"},
        "teams" => {:quantifier, :all, %{"active" => true}}
      }

      assert decoded == expected
    end

    test "decoded patterns work in matching" do
      # Create pattern, encode to JSON, decode, and use for matching
      original_pattern = %{team: "*-octosell", members: DataMatcher.any("alice")}
      json = DataMatcher.to_json(original_pattern)
      {:ok, decoded_pattern} = DataMatcher.from_json(json)

      data = %{"team" => "dev-octosell", "members" => ["alice", "bob"]}
      assert DataMatcher.match(data, decoded_pattern) == true

      data2 = %{"team" => "dev-other", "members" => ["alice", "bob"]}
      assert DataMatcher.match(data2, decoded_pattern) == false
    end
  end

  describe "edge cases and error handling" do
    test "handles deeply nested structures" do
      data = %{a: %{b: %{c: %{d: "deep"}}}}
      pattern = %{a: %{b: %{c: %{d: "deep"}}}}
      assert DataMatcher.match(data, pattern) == true
    end

    test "handles mixed types gracefully" do
      # Should not crash on unexpected combinations
      assert DataMatcher.match([1, 2, 3], %{key: "value"}) == false
      assert DataMatcher.match(%{key: "value"}, [1, 2, 3]) == false
      assert DataMatcher.match("string", 123) == false
    end

    test "handles malformed data gracefully" do
      # Should not crash on edge cases
      assert DataMatcher.match(nil, %{key: "value"}) == false
      assert DataMatcher.match(%{key: "value"}, nil) == false
    end

    test "quantifiers with non-list data return false" do
      assert DataMatcher.match("not a list", DataMatcher.any("pattern")) == false
      assert DataMatcher.match(123, DataMatcher.all(123)) == false
      assert DataMatcher.match(%{key: "value"}, DataMatcher.none("pattern")) == false
    end
  end
end
