defmodule JsonCompactorQuickBench do
  @moduledoc """
  Quick benchmark for JsonCompactor to demonstrate performance improvements.
  """

  # Generate test data
  defp generate_simple_data(size) do
    Enum.into(1..size, %{}, fn i ->
      {"key_#{i}", "value_#{i}"}
    end)
  end

  defp generate_duplicate_data(size) do
    shared_user = %{"name" => "Alice", "role" => "admin", "department" => "Engineering"}
    
    %{
      "users" => Enum.map(1..size, fn i ->
        if rem(i, 3) == 0 do
          shared_user
        else
          %{"name" => "User_#{i}", "role" => "user", "department" => "Engineering"}
        end
      end),
      "metadata" => %{
        "version" => "1.0",
        "shared_user" => shared_user
      }
    }
  end

  def run do
    IO.puts("JsonCompactor Quick Benchmark")
    IO.puts("=" <> String.duplicate("=", 30))

    # Test data
    simple_data = generate_simple_data(100)
    duplicate_data = generate_duplicate_data(50)
    
    # Compact benchmarks
    IO.puts("\nCompaction Benchmarks:")
    Benchee.run(
      %{
        "compact_simple_100" => fn -> JsonCompactor.compact(simple_data) end,
        "compact_duplicate_50" => fn -> JsonCompactor.compact(duplicate_data) end
      },
      time: 1,
      memory_time: 0.5,
      print: [fast_warning: false]
    )

    # Pre-compact for decompaction test
    compacted_simple = JsonCompactor.compact(simple_data)
    compacted_duplicate = JsonCompactor.compact(duplicate_data)

    # Decompact benchmarks  
    IO.puts("\nDecompaction Benchmarks:")
    Benchee.run(
      %{
        "decompact_simple_100" => fn -> JsonCompactor.decompact(compacted_simple) end,
        "decompact_duplicate_50" => fn -> JsonCompactor.decompact(compacted_duplicate) end
      },
      time: 1,
      memory_time: 0.5,
      print: [fast_warning: false]
    )

    # Compression analysis
    IO.puts("\nCompression Analysis:")
    analyze_compression("Simple Data", simple_data)
    analyze_compression("Duplicate Data", duplicate_data)
    
    IO.puts("\nBenchmark completed!")
  end

  defp analyze_compression(name, data) do
    original_json = Jason.encode!(data)
    compacted = JsonCompactor.compact(data)
    compacted_json = Jason.encode!(compacted)
    
    original_size = byte_size(original_json)
    compacted_size = byte_size(compacted_json)
    compression_ratio = Float.round((1 - compacted_size / original_size) * 100, 2)
    
    IO.puts("#{name}:")
    IO.puts("  Original: #{original_size} bytes")
    IO.puts("  Compacted: #{compacted_size} bytes")
    IO.puts("  Compression: #{compression_ratio}%")
  end
end

JsonCompactorQuickBench.run()