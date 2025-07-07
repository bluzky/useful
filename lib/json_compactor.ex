defmodule JsonCompactor do
  @moduledoc """
  Compacts and decompacts JSON-like data structures by flattening nested maps and lists
  into arrays with reference indices, providing memory efficiency and deduplication.

  This module implements a serialization technique that extracts nested structures into
  a flat array and replaces them with string indices, similar to how some databases
  and serialization libraries optimize storage and transmission of complex data.

  ## Benefits

  - **Memory Efficiency**: Identical structures are stored only once
  - **Deduplication**: Eliminates redundant nested objects
  - **Smaller Payloads**: Reduces JSON size for network transmission
  - **Referential Consistency**: Updates to shared structures affect all references

  ## Example

      iex> data = %{
      ...>   "user" => %{"name" => "Alice", "role" => "admin"},
      ...>   "backup_user" => %{"name" => "Alice", "role" => "admin"},
      ...>   "settings" => %{"theme" => "dark"}
      ...> }
      iex> compacted = JsonCompactor.compact(data)
      iex> compacted
      [
        %{
          "user" => "1",
          "backup_user" => "1",
          "settings" => "4"
        },
        %{"name" => "2", "role" => "3"},
        "Alice",
        "admin",
        %{"theme" => "5"},
        "dark"
      ]
      iex> JsonCompactor.decompact(compacted) == data
      true

  In this example, all values are extracted and deduplicated - identical user maps
  reference the same object at index "1", and repeated strings like "Alice" and
  "admin" are also deduplicated.
  """

  @type json_value ::
          nil | boolean() | number() | String.t() | [json_value()] | %{String.t() => json_value()}
  @type compacted_array :: [json_value() | String.t()]

  @doc """
  Compacts a data structure by extracting maps, lists, and strings into a flat array
  and replacing them with string reference indices. Other data types are kept as original values.

  ## Parameters

  - `data` - The data structure to compact (any JSON value)

  ## Returns

  A list where:
  - For simple values (numbers, booleans, nil, dates): `[original_value]`
  - For complex structures:
    - First element: The root structure with maps/lists/strings replaced by string indices
    - Remaining elements: The extracted maps/lists/strings in order of their indices

  ## Examples

      iex> JsonCompactor.compact(%{"a" => 1})
      [%{"a" => 1}]

      iex> JsonCompactor.compact(%{"a" => "hello"})
      [%{"a" => "1"}, "hello"]

      iex> JsonCompactor.compact(%{"name" => "Alice", "age" => 30, "active" => true})
      [%{"name" => "1", "age" => 30, "active" => true}, "Alice"]

      iex> JsonCompactor.compact([1, "hello", true])
      [["1", 1, true], "hello"]

  Complex nesting with deduplication:

      iex> data = %{
      ...>   "user" => %{"name" => "Alice", "role" => "admin"},
      ...>   "backup_user" => %{"name" => "Alice", "role" => "admin"},
      ...>   "settings" => %{"theme" => "dark"}
      ...> }
      iex> JsonCompactor.compact(data)
      [
        %{
          "user" => "1",
          "backup_user" => "1",
          "settings" => "4"
        },
        %{"name" => "2", "role" => "3"},
        "Alice",
        "admin",
        %{"theme" => "5"},
        "dark"
      ]

  """
  @spec compact(json_value()) :: compacted_array()
  def compact(data) do
    # Always return a list
    case needs_compaction_reference?(data) do
      false ->
        [data]

      true ->
        {_compacted, lookup_table} = build_lookup_table_bfs(data)

        # Convert lookup table to array format
        array =
          lookup_table
          |> Enum.sort_by(fn {_value, index} -> index end)
          |> Enum.map(fn {value, _index} -> value end)

        array
    end
  end

  @doc """
  Decompacts a flattened array back into the original nested data structure.

  Takes a compacted array (as returned by `compact/1`) and reconstructs the original
  nested structure by resolving all string reference indices back to their actual values.
  If the input is not a list, it's returned as-is (primitive values).

  ## Parameters

  - `compacted_data` - Either:
    - A list where the first element is the root structure and remaining elements are referenced structures
    - A primitive value (returned unchanged)

  ## Returns

  The original nested data structure with all references resolved.

  ## Examples

      iex> JsonCompactor.decompact("hello")
      "hello"

      iex> JsonCompactor.decompact(42)
      42

      iex> compacted = [%{"nested" => "1"}, %{"inner" => "2"}, "value"]
      iex> JsonCompactor.decompact(compacted)
      %{"nested" => %{"inner" => "value"}}

  ## Raises

  - `ArgumentError` if reference indices are out of bounds

  """
  @spec decompact(compacted_array() | json_value()) :: json_value()
  def decompact([first | _rest] = array) when is_list(array) do
    resolve_references(first, array)
  end

  def decompact(primitive_value), do: primitive_value

  # Build lookup table using breadth-first search
  @spec build_lookup_table_bfs(json_value()) :: {String.t() | json_value(), map()}
  defp build_lookup_table_bfs(root) do
    # Phase 1: BFS to collect all unique values and assign indices
    queue = :queue.in(root, :queue.new())
    {value_to_index, _} = bfs_collect_values(queue, %{}, 0)

    # Phase 2: Build compacted versions of complex structures
    final_lookup = build_compacted_structures(value_to_index)

    root_index = Map.get(value_to_index, root)
    {Integer.to_string(root_index), final_lookup}
  end

  # Phase 1: BFS traversal to collect values that need references (maps, lists, strings)
  @spec bfs_collect_values(:queue.queue(), map(), non_neg_integer()) :: {map(), non_neg_integer()}
  defp bfs_collect_values(queue, value_to_index, counter) do
    case :queue.out(queue) do
      {{:value, value}, remaining_queue} ->
        case Map.get(value_to_index, value) do
          nil ->
            # Check if this value needs to be stored in reference table
            case needs_reference?(value) do
              true ->
                # Store value and assign index
                updated_index_map = Map.put(value_to_index, value, counter)
                new_counter = counter + 1

                # Add children to queue
                children_queue =
                  case value do
                    map when is_map(map) ->
                      Enum.reduce(Map.values(map), remaining_queue, fn child, acc_queue ->
                        :queue.in(child, acc_queue)
                      end)

                    list when is_list(list) ->
                      Enum.reduce(list, remaining_queue, fn child, acc_queue ->
                        :queue.in(child, acc_queue)
                      end)

                    _string ->
                      # Strings don't have children
                      remaining_queue
                  end

                bfs_collect_values(children_queue, updated_index_map, new_counter)

              false ->
                # For non-reference values (numbers, booleans, etc.), still traverse children
                children_queue =
                  case value do
                    map when is_map(map) ->
                      Enum.reduce(Map.values(map), remaining_queue, fn child, acc_queue ->
                        :queue.in(child, acc_queue)
                      end)

                    list when is_list(list) ->
                      Enum.reduce(list, remaining_queue, fn child, acc_queue ->
                        :queue.in(child, acc_queue)
                      end)

                    _primitive ->
                      remaining_queue
                  end

                bfs_collect_values(children_queue, value_to_index, counter)
            end

          _existing_index ->
            # Value already seen, skip and continue
            bfs_collect_values(remaining_queue, value_to_index, counter)
        end

      {:empty, _} ->
        {value_to_index, counter}
    end
  end

  # Phase 2: Build compacted versions of complex structures
  @spec build_compacted_structures(map()) :: map()
  defp build_compacted_structures(value_to_index) do
    Enum.reduce(value_to_index, %{}, fn {value, index}, acc ->
      compacted_value =
        case value do
          map when is_map(map) ->
            Enum.reduce(map, %{}, fn {key, child_value}, acc_map ->
              case needs_reference?(child_value) do
                true ->
                  child_index = Map.get(value_to_index, child_value)
                  Map.put(acc_map, key, Integer.to_string(child_index))

                false ->
                  Map.put(acc_map, key, child_value)
              end
            end)

          list when is_list(list) ->
            Enum.map(list, fn child_value ->
              case needs_reference?(child_value) do
                true ->
                  child_index = Map.get(value_to_index, child_value)
                  Integer.to_string(child_index)

                false ->
                  child_value
              end
            end)

          primitive ->
            primitive
        end

      Map.put(acc, compacted_value, index)
    end)
  end

  # Check if a value needs to be compacted (stored in reference table)
  @spec needs_compaction_reference?(json_value()) :: boolean()
  defp needs_compaction_reference?(value) when is_map(value) and map_size(value) > 0, do: true
  defp needs_compaction_reference?(value) when is_list(value) and length(value) > 0, do: true
  defp needs_compaction_reference?(value) when is_binary(value), do: true
  defp needs_compaction_reference?(_), do: false

  # Check if a value needs to be referenced (maps, lists, strings)
  @spec needs_reference?(json_value()) :: boolean()
  defp needs_reference?(value) when is_map(value), do: true
  defp needs_reference?(value) when is_list(value), do: true
  defp needs_reference?(value) when is_binary(value), do: true
  defp needs_reference?(_), do: false

  # Resolve string references back to actual values
  @spec resolve_references(json_value() | String.t(), list(json_value())) :: json_value()
  defp resolve_references(data, array) when is_binary(data) do
    case Integer.parse(data) do
      {index, ""} when index >= 0 and index < length(array) ->
        array
        |> Enum.at(index)
        |> resolve_references(array)

      {index, ""} ->
        raise ArgumentError,
              "Reference index #{index} is out of bounds for array of length #{length(array)}"

      _ ->
        data
    end
  end

  defp resolve_references(data, array) when is_map(data) do
    data
    |> Enum.map(fn {key, value} -> {key, resolve_references(value, array)} end)
    |> Enum.into(%{})
  end

  defp resolve_references(data, array) when is_list(data) do
    Enum.map(data, fn item -> resolve_references(item, array) end)
  end

  defp resolve_references(data, _array), do: data
end
