defmodule JsonCompactorBench do
  @moduledoc """
  Benchmark tests for JsonCompactor module to measure performance of
  compact and decompact operations across various data structures.
  """

  # Generate test data of various sizes and complexities
  defp generate_simple_data(size) do
    Enum.into(1..size, %{}, fn i ->
      {"key_#{i}", "value_#{i}"}
    end)
  end

  defp generate_nested_data(depth) do
    Enum.reduce(1..depth, %{"value" => "deep_value"}, fn i, acc ->
      %{"level_#{i}" => acc}
    end)
  end

  defp generate_duplicate_data(size) do
    shared_user = %{"name" => "Alice", "role" => "admin", "department" => "Engineering"}
    shared_config = %{"timeout" => 30, "retries" => 3, "debug" => true}
    
    %{
      "users" => Enum.map(1..size, fn i ->
        if rem(i, 3) == 0 do
          shared_user
        else
          %{"name" => "User_#{i}", "role" => "user", "department" => "Engineering"}
        end
      end),
      "configs" => Enum.map(1..div(size, 2), fn i ->
        if rem(i, 2) == 0 do
          shared_config
        else
          %{"timeout" => 15, "retries" => 1, "debug" => false}
        end
      end),
      "metadata" => %{
        "version" => "1.0",
        "created_by" => "system",
        "shared_user" => shared_user,
        "shared_config" => shared_config
      }
    }
  end

  defp generate_mixed_data(size) do
    %{
      "strings" => Enum.map(1..size, fn i -> "string_#{i}" end),
      "numbers" => Enum.to_list(1..size),
      "booleans" => Enum.map(1..size, fn i -> rem(i, 2) == 0 end),
      "nested_maps" => Enum.into(1..div(size, 4), %{}, fn i ->
        {"map_#{i}", %{
          "id" => i,
          "name" => "item_#{i}",
          "config" => %{"enabled" => true, "priority" => rem(i, 5)}
        }}
      end),
      "mixed_list" => Enum.map(1..size, fn i ->
        case rem(i, 4) do
          0 -> i
          1 -> "item_#{i}"
          2 -> %{"id" => i, "value" => "nested_#{i}"}
          3 -> [i, "sub_#{i}", true]
        end
      end)
    }
  end

  defp generate_large_structure(size) do
    # Generate a structure that will stress the deduplication capabilities
    common_strings = ["active", "inactive", "pending", "completed", "error"]
    common_maps = [
      %{"type" => "user", "permissions" => ["read", "write"]},
      %{"type" => "admin", "permissions" => ["read", "write", "delete"]},
      %{"type" => "guest", "permissions" => ["read"]}
    ]
    
    %{
      "records" => Enum.map(1..size, fn i ->
        %{
          "id" => i,
          "status" => Enum.at(common_strings, rem(i, length(common_strings))),
          "user_type" => Enum.at(common_maps, rem(i, length(common_maps))),
          "metadata" => %{
            "created_at" => "2024-01-#{rem(i, 28) + 1}",
            "tags" => Enum.take(common_strings, rem(i, 3) + 1),
            "priority" => rem(i, 5) + 1
          }
        }
      end),
      "summary" => %{
        "total" => size,
        "common_strings" => common_strings,
        "common_maps" => common_maps
      }
    }
  end

  defp generate_user_list(size) do
    # Generate a realistic list of user records with repeated field keys
    departments = ["Engineering", "Marketing", "Sales", "Support", "HR"]
    roles = ["admin", "user", "manager", "intern"]
    locations = ["San Francisco", "New York", "London", "Tokyo", "Berlin"]
    
    Enum.map(1..size, fn i ->
      %{
        "id" => i,
        "name" => "User#{i}",
        "email" => "user#{i}@company.com",
        "role" => Enum.at(roles, rem(i, length(roles))),
        "department" => Enum.at(departments, rem(i, length(departments))),
        "location" => Enum.at(locations, rem(i, length(locations))),
        "active" => rem(i, 4) != 0,  # 75% active users
        "created_at" => "2024-#{rem(i, 12) + 1}-01",
        "profile" => %{
          "avatar_url" => "https://example.com/avatar#{rem(i, 10)}.jpg",
          "bio" => "Bio for user #{i}",
          "preferences" => %{
            "theme" => (if rem(i, 2) == 0, do: "dark", else: "light"),
            "notifications" => rem(i, 3) == 0,
            "language" => (if rem(i, 5) == 0, do: "es", else: "en")
          }
        }
      }
    end)
  end

  # Benchmark scenarios
  def run do
    IO.puts("Running JsonCompactor benchmarks...")
    IO.puts("=" <> String.duplicate("=", 50))

    # Test data sets
    small_simple = generate_simple_data(10)
    medium_simple = generate_simple_data(100)
    large_simple = generate_simple_data(1000)

    nested_shallow = generate_nested_data(3)
    nested_medium = generate_nested_data(8)
    nested_deep = generate_nested_data(15)

    duplicate_small = generate_duplicate_data(20)
    duplicate_medium = generate_duplicate_data(100)
    duplicate_large = generate_duplicate_data(500)

    mixed_small = generate_mixed_data(20)
    mixed_medium = generate_mixed_data(100)
    mixed_large = generate_mixed_data(500)

    large_structure_small = generate_large_structure(50)
    large_structure_medium = generate_large_structure(200)
    large_structure_large = generate_large_structure(1000)

    user_list_small = generate_user_list(25)
    user_list_medium = generate_user_list(100)
    user_list_large = generate_user_list(250)

    IO.puts("\n1. Simple Map Compaction Benchmarks")
    IO.puts("-" <> String.duplicate("-", 40))
    
    Benchee.run(
      %{
        "compact_small_simple (10 items)" => fn -> JsonCompactor.compact(small_simple) end,
        "compact_medium_simple (100 items)" => fn -> JsonCompactor.compact(medium_simple) end,
        "compact_large_simple (1000 items)" => fn -> JsonCompactor.compact(large_simple) end
      },
      time: 3,
      memory_time: 1
    )

    IO.puts("\n2. Nested Structure Compaction Benchmarks")
    IO.puts("-" <> String.duplicate("-", 40))
    
    Benchee.run(
      %{
        "compact_nested_shallow (3 levels)" => fn -> JsonCompactor.compact(nested_shallow) end,
        "compact_nested_medium (8 levels)" => fn -> JsonCompactor.compact(nested_medium) end,
        "compact_nested_deep (15 levels)" => fn -> JsonCompactor.compact(nested_deep) end
      },
      time: 3,
      memory_time: 1
    )

    IO.puts("\n3. Duplicate Data Compaction Benchmarks")
    IO.puts("-" <> String.duplicate("-", 40))
    
    Benchee.run(
      %{
        "compact_duplicate_small (20 users)" => fn -> JsonCompactor.compact(duplicate_small) end,
        "compact_duplicate_medium (100 users)" => fn -> JsonCompactor.compact(duplicate_medium) end,
        "compact_duplicate_large (500 users)" => fn -> JsonCompactor.compact(duplicate_large) end
      },
      time: 3,
      memory_time: 1
    )

    IO.puts("\n4. Mixed Data Type Compaction Benchmarks")
    IO.puts("-" <> String.duplicate("-", 40))
    
    Benchee.run(
      %{
        "compact_mixed_small (20 items)" => fn -> JsonCompactor.compact(mixed_small) end,
        "compact_mixed_medium (100 items)" => fn -> JsonCompactor.compact(mixed_medium) end,
        "compact_mixed_large (500 items)" => fn -> JsonCompactor.compact(mixed_large) end
      },
      time: 3,
      memory_time: 1
    )

    IO.puts("\n5. Large Structure with High Deduplication Benchmarks")
    IO.puts("-" <> String.duplicate("-", 40))
    
    Benchee.run(
      %{
        "compact_large_struct_small (50 records)" => fn -> JsonCompactor.compact(large_structure_small) end,
        "compact_large_struct_medium (200 records)" => fn -> JsonCompactor.compact(large_structure_medium) end,
        "compact_large_struct_large (1000 records)" => fn -> JsonCompactor.compact(large_structure_large) end
      },
      time: 3,
      memory_time: 1
    )

    IO.puts("\n6. User List Compaction Benchmarks (Field Key Deduplication)")
    IO.puts("-" <> String.duplicate("-", 40))
    
    Benchee.run(
      %{
        "compact_user_list_small (25 users)" => fn -> JsonCompactor.compact(user_list_small) end,
        "compact_user_list_medium (100 users)" => fn -> JsonCompactor.compact(user_list_medium) end,
        "compact_user_list_large (250 users)" => fn -> JsonCompactor.compact(user_list_large) end
      },
      time: 3,
      memory_time: 1
    )

    # Pre-compact data for decompaction benchmarks
    compacted_simple_large = JsonCompactor.compact(large_simple)
    compacted_nested_deep = JsonCompactor.compact(nested_deep)
    compacted_duplicate_large = JsonCompactor.compact(duplicate_large)
    compacted_mixed_large = JsonCompactor.compact(mixed_large)
    compacted_large_struct_large = JsonCompactor.compact(large_structure_large)
    compacted_user_list_medium = JsonCompactor.compact(user_list_medium)
    compacted_user_list_large = JsonCompactor.compact(user_list_large)

    IO.puts("\n7. Decompaction Benchmarks")
    IO.puts("-" <> String.duplicate("-", 40))
    
    Benchee.run(
      %{
        "decompact_simple_large (1000 items)" => fn -> JsonCompactor.decompact(compacted_simple_large) end,
        "decompact_nested_deep (15 levels)" => fn -> JsonCompactor.decompact(compacted_nested_deep) end,
        "decompact_duplicate_large (500 users)" => fn -> JsonCompactor.decompact(compacted_duplicate_large) end,
        "decompact_mixed_large (500 items)" => fn -> JsonCompactor.decompact(compacted_mixed_large) end,
        "decompact_large_struct_large (1000 records)" => fn -> JsonCompactor.decompact(compacted_large_struct_large) end,
        "decompact_user_list_medium (100 users)" => fn -> JsonCompactor.decompact(compacted_user_list_medium) end,
        "decompact_user_list_large (250 users)" => fn -> JsonCompactor.decompact(compacted_user_list_large) end
      },
      time: 3,
      memory_time: 1
    )

    IO.puts("\n8. Round-trip Benchmarks (Compact + Decompact)")
    IO.puts("-" <> String.duplicate("-", 40))
    
    Benchee.run(
      %{
        "roundtrip_simple_large" => fn -> 
          compacted = JsonCompactor.compact(large_simple)
          JsonCompactor.decompact(compacted)
        end,
        "roundtrip_duplicate_large" => fn ->
          compacted = JsonCompactor.compact(duplicate_large)
          JsonCompactor.decompact(compacted)
        end,
        "roundtrip_mixed_large" => fn ->
          compacted = JsonCompactor.compact(mixed_large)
          JsonCompactor.decompact(compacted)
        end,
        "roundtrip_large_struct_large" => fn ->
          compacted = JsonCompactor.compact(large_structure_large)
          JsonCompactor.decompact(compacted)
        end,
        "roundtrip_user_list_medium" => fn ->
          compacted = JsonCompactor.compact(user_list_medium)
          JsonCompactor.decompact(compacted)
        end,
        "roundtrip_user_list_large" => fn ->
          compacted = JsonCompactor.compact(user_list_large)
          JsonCompactor.decompact(compacted)
        end
      },
      time: 3,
      memory_time: 1
    )

    # Compression ratio analysis
    IO.puts("\n9. Compression Ratio Analysis")
    IO.puts("-" <> String.duplicate("-", 40))
    
    analyze_compression_ratio("Simple Large", large_simple)
    analyze_compression_ratio("Duplicate Large", duplicate_large)
    analyze_compression_ratio("Mixed Large", mixed_large)
    analyze_compression_ratio("Large Structure", large_structure_large)
    analyze_compression_ratio("User List Medium (100 users)", user_list_medium)
    analyze_compression_ratio("User List Large (250 users)", user_list_large)

    IO.puts("\nBenchmark completed!")
  end

  defp analyze_compression_ratio(name, data) do
    original_json = Jason.encode!(data)
    compacted = JsonCompactor.compact(data)
    compacted_json = Jason.encode!(compacted)
    
    original_size = byte_size(original_json)
    compacted_size = byte_size(compacted_json)
    compression_ratio = Float.round((1 - compacted_size / original_size) * 100, 2)
    
    IO.puts("#{name}:")
    IO.puts("  Original JSON size: #{original_size} bytes")
    IO.puts("  Compacted JSON size: #{compacted_size} bytes")
    IO.puts("  Compression ratio: #{compression_ratio}%")
    IO.puts("  Space saved: #{original_size - compacted_size} bytes")
    IO.puts("")
  end
end

# Run when called with: mix run bench/json_compactor_bench.exs
JsonCompactorBench.run()