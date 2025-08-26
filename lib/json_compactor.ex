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
          nil
          | boolean()
          | number()
          | String.t()
          | [json_value()]
          | %{String.t() => json_value()}
          | %{atom() => json_value()}
          | struct()
          | tuple()
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
    if needs_compaction_reference?(data) do
      {_compacted, lookup_table} = build_lookup_table_bfs(data)

      # Convert lookup table to array format
      array =
        lookup_table
        |> Enum.sort_by(fn {_value, index} -> index end)
        |> Enum.map(fn {value, _index} -> value end)

      array
    else
      [data]
    end
  end

  @doc """
  Decompacts a flattened array back into the original nested data structure.

  Takes a compacted array (as returned by `compact/1`) and reconstructs the original
  nested structure by resolving all string reference indices back to their actual values.

  ## Parameters

  - `compacted_data` - Either:
    - A list where the first element is the root structure and remaining elements are referenced structures
    - A primitive value (returns error)

  ## Returns

  - `{:ok, data}` - The original nested data structure with all references resolved
  - `{:error, message}` - Error message if decompaction fails

  ## Examples

      iex> JsonCompactor.decompact("hello")
      {:error, "Input must be a list"}

      iex> JsonCompactor.decompact([])
      {:error, "Cannot decompact empty list"}

      iex> compacted = [%{"nested" => "1"}, %{"inner" => "2"}, "value"]
      iex> JsonCompactor.decompact(compacted)
      {:ok, %{"nested" => %{"inner" => "value"}}}

  ## Errors

  - Reference indices are out of bounds
  - Circular references detected
  - Invalid input (not a list or empty list)

  """
  @spec decompact(compacted_array() | json_value()) :: {:ok, json_value()} | {:error, String.t()}
  def decompact([first | _rest] = array) when is_list(array) do
    if is_binary(first) do
      {:ok, first}
    else
      # Build index map for O(1) access
      index_map = build_index_map(array)

      case resolve_references(first, index_map, MapSet.new()) do
        {:ok, result} -> {:ok, result}
        {:error, message} -> {:error, message}
      end
    end
  end

  def decompact([]), do: {:error, "Cannot decompact empty list"}

  def decompact(_primitive_value), do: {:error, "Input must be a list"}

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

  # Helper function to add children to queue with batch processing
  @spec add_children_to_queue(json_value(), :queue.queue()) :: :queue.queue()
  defp add_children_to_queue(value, queue) do
    case value do
      map when is_map(map) ->
        children =
          map
          |> Map.delete(:__struct__)
          |> Map.values()

        add_children_batch(children, queue)

      list when is_list(list) ->
        add_children_batch(list, queue)

      tuple when is_tuple(tuple) ->
        add_children_batch(Tuple.to_list(tuple), queue)

      _primitive ->
        # Strings and other primitives don't have children
        queue
    end
  end

  # Batch add children to queue for better performance
  @spec add_children_batch([json_value()], :queue.queue()) :: :queue.queue()
  defp add_children_batch([], queue), do: queue

  defp add_children_batch([child | rest], queue) do
    add_children_batch(rest, :queue.in(child, queue))
  end

  # Phase 1: BFS traversal to collect values that need references (maps, lists, strings)
  @spec bfs_collect_values(:queue.queue(), map(), non_neg_integer()) :: {map(), non_neg_integer()}
  defp bfs_collect_values(queue, value_to_index, counter) do
    case :queue.out(queue) do
      {{:value, value}, remaining_queue} ->
        case Map.get(value_to_index, value) do
          nil ->
            # Check if this value needs to be stored in reference table
            if needs_reference?(value) do
              # Store value and assign index
              updated_index_map = Map.put(value_to_index, value, counter)
              new_counter = counter + 1

              # Add children to queue
              children_queue = add_children_to_queue(value, remaining_queue)
              bfs_collect_values(children_queue, updated_index_map, new_counter)
            else
              # For non-reference values (numbers, booleans, etc.), still traverse children
              children_queue = add_children_to_queue(value, remaining_queue)
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
    # Pre-compute string indices to avoid repeated conversions
    string_indices =
      Map.new(value_to_index, fn {value, index} -> {value, to_string(index)} end)

    Enum.reduce(value_to_index, %{}, fn {value, index}, acc ->
      compacted_value = compact_value(value, string_indices)
      Map.put(acc, compacted_value, index)
    end)
  end

  # Compact a single value based on its type
  @spec compact_value(json_value(), map()) :: json_value()
  defp compact_value(data, string_indices) when is_struct(data) do
    # For other structs, preserve type info and convert atom keys
    map = Map.from_struct(data)
    struct_name = to_string(data.__struct__)

    # Convert atom keys to ":atomname" and add struct marker
    converted_map =
      Map.new(map, fn {key, value} ->
        # Struct fields are always atoms
        key_str = ":" <> Atom.to_string(key)
        {key_str, value}
      end)

    base_map =
      Map.put(converted_map, "__struct__", struct_name)

    # Apply reference resolution
    resolve_map_references(base_map, string_indices, fn key ->
      # Keep struct name as-is
      key == "__struct__"
    end)
  end

  defp compact_value(map, string_indices) when is_map(map) do
    # Convert atom keys to ":atomname" format and apply reference resolution
    converted_map =
      Map.new(map, fn {key, value} ->
        # Convert key inline
        new_key = if is_atom(key), do: ":" <> Atom.to_string(key), else: key
        {new_key, value}
      end)

    resolve_map_references(converted_map, string_indices, fn _key -> false end)
  end

  defp compact_value(list, string_indices) when is_list(list) do
    # Compact list with reference resolution
    Enum.map(list, fn child_value ->
      if needs_reference?(child_value) do
        Map.get(string_indices, child_value)
      else
        child_value
      end
    end)
  end

  defp compact_value(tuple, string_indices) when is_tuple(tuple) do
    # Convert tuple to list with special marker for JSON compatibility
    tuple_list = ["__tuple__" | Tuple.to_list(tuple)]

    compact_value(tuple_list, string_indices)
  end

  defp compact_value(primitive, _string_indices) do
    primitive
  end

  # Apply reference resolution to map values with optional key preservation
  @spec resolve_map_references(map(), map(), (String.t() -> boolean())) :: map()
  defp resolve_map_references(map, string_indices, preserve_key_fn) do
    Enum.reduce(map, %{}, fn {key, child_value}, acc_map ->
      if preserve_key_fn.(key) do
        # Keep value as-is
        Map.put(acc_map, key, child_value)
      else
        if needs_reference?(child_value) do
          child_index_str = Map.get(string_indices, child_value)
          Map.put(acc_map, key, child_index_str)
        else
          Map.put(acc_map, key, child_value)
        end
      end
    end)
  end

  # Check if a value needs to be compacted (stored in reference table)
  defp needs_compaction_reference?(value) when is_map(value) and map_size(value) > 0, do: true
  defp needs_compaction_reference?(value) when is_list(value) and length(value) > 0, do: true
  defp needs_compaction_reference?(value) when is_tuple(value), do: true
  defp needs_compaction_reference?(value) when is_binary(value), do: true

  defp needs_compaction_reference?(value) when is_atom(value) and value not in [nil, true, false],
    do: true

  defp needs_compaction_reference?(_), do: false

  # Check if a value needs to be referenced (maps, lists, strings)
  @spec needs_reference?(json_value()) :: boolean()
  defp needs_reference?("__tuple__"), do: false
  defp needs_reference?(value) when is_map(value), do: true
  defp needs_reference?(value) when is_list(value), do: true
  defp needs_reference?(value) when is_tuple(value), do: true
  defp needs_reference?(value) when is_binary(value), do: true
  defp needs_reference?(value) when is_atom(value) and value not in [nil, true, false], do: true
  defp needs_reference?(_), do: false

  # Build index map for O(1) access to array elements
  @spec build_index_map(list(json_value())) :: map()
  defp build_index_map(array) do
    array
    |> Enum.with_index()
    |> Map.new(fn
      {"Elixir." <> _ = struct_name, index} ->
        {to_string(index), String.to_existing_atom(struct_name)}

      {value, index} ->
        {to_string(index), value}
    end)
  end

  # Resolve string references back to actual values with cycle detection
  @spec resolve_references(json_value() | String.t(), map(), MapSet.t()) ::
          {:ok, json_value()} | {:error, String.t()}

  defp resolve_references(data, index_map, visited) when is_binary(data) do
    case Map.fetch(index_map, data) do
      {:ok, value} ->
        # Check for circular reference
        if MapSet.member?(visited, data) do
          {:error, "Circular reference detected at index #{data}"}
        else
          new_visited = MapSet.put(visited, data)

          # If the value is a string, return it directly because string at level 0 is already a string
          if is_binary(value) do
            {:ok, value}
          else
            # If the value is not a string, resolve it recursively
            resolve_references(value, index_map, new_visited)
          end
        end

      :error ->
        {:error,
         "Reference index #{data} is out of bounds for array of length #{map_size(index_map)}"}
    end
  end

  defp resolve_references(data, index_map, visited) when is_map(data) do
    # First resolve all references and convert keys in one pass
    result =
      Enum.reduce_while(data, {:ok, %{}}, fn
        {"__struct__" = key, value}, {:ok, acc} ->
          {:cont, {:ok, Map.put(acc, key, value)}}

        {key, value}, {:ok, acc} ->
          case resolve_references(value, index_map, visited) do
            {:ok, resolved_value} ->
              # Convert key inline
              new_key =
                case key do
                  ":" <> atom_name ->
                    try do
                      String.to_existing_atom(atom_name)
                    rescue
                      # Keep as string if atom doesn't exist
                      ArgumentError -> key
                    end

                  _ ->
                    # Regular string key
                    key
                end

              {:cont, {:ok, Map.put(acc, new_key, resolved_value)}}

            {:error, message} ->
              {:halt, {:error, message}}
          end
      end)

    case result do
      {:ok, resolved_map} ->
        # Check for struct reconstruction
        if Map.has_key?(resolved_map, "__struct__") do
          {:ok, reconstruct_struct(resolved_map)}
        else
          {:ok, resolved_map}
        end

      error ->
        error
    end
  end

  defp resolve_references(["__tuple__" | elements], index_map, visited) do
    # Handle tuple reconstruction
    case resolve_list_items(elements, index_map, visited, []) do
      {:ok, resolved_elements} -> {:ok, List.to_tuple(resolved_elements)}
      error -> error
    end
  end

  defp resolve_references(data, index_map, visited) when is_list(data) do
    resolve_list_items(data, index_map, visited, [])
  end

  defp resolve_references(data, _index_map, _visited), do: {:ok, data}

  # Helper function to resolve list items without reversing
  @spec resolve_list_items([json_value()], map(), MapSet.t(), [json_value()]) ::
          {:ok, [json_value()]} | {:error, String.t()}
  defp resolve_list_items([], _index_map, _visited, acc) do
    {:ok, :lists.reverse(acc)}
  end

  defp resolve_list_items([item | rest], index_map, visited, acc) do
    case resolve_references(item, index_map, visited) do
      {:ok, resolved_item} ->
        resolve_list_items(rest, index_map, visited, [resolved_item | acc])

      {:error, message} ->
        {:error, message}
    end
  end

  # Reconstruct struct from map with __struct__ field
  defp reconstruct_struct(%{"__struct__" => struct_name} = map) do
    try do
      # Handle different formats of module names
      module =
        case struct_name do
          name when is_binary(name) ->
            String.to_existing_atom(name)

          name when is_atom(name) ->
            name

          _ ->
            nil
        end

      if module do
        # Remove struct marker and create struct
        data_map = Map.delete(map, "__struct__")
        struct!(module, data_map)
      else
        # Invalid struct name, return as regular map
        Map.delete(map, "__struct__")
      end
    rescue
      ArgumentError ->
        # Module doesn't exist, return as regular map
        Map.delete(map, "__struct__")
    end
  end
end
