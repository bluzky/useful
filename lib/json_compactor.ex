defmodule JsonCompactor do
  @moduledoc """
  Compacts and decompacts JSON-like data structures by flattening nested maps and lists
  into arrays with reference indices, providing memory efficiency and deduplication.

  This module implements a serialization technique that extracts nested structures and
  field keys into a flat array and replaces them with string indices, similar to how
  some databases and serialization libraries optimize storage and transmission of complex data.

  ## Benefits

  - **Memory Efficiency**: Identical structures and field keys are stored only once
  - **Field Key Deduplication**: Repeated map keys (like "name", "email") are deduplicated automatically
  - **Value Deduplication**: Eliminates redundant nested objects and strings
  - **Smaller Payloads**: Significant JSON size reduction for network transmission
  - **Referential Consistency**: Updates to shared structures affect all references

  ## Field Key Referencing

  The compactor automatically deduplicates repeated field keys, providing significant
  compression benefits for structured data like API responses, database results, and
  configuration objects where field names are repeated across many records.

  ## Example

      iex> data = %{
      ...>   "user" => %{"name" => "Alice", "role" => "admin"},
      ...>   "backup_user" => %{"name" => "Alice", "role" => "admin"},
      ...>   "settings" => %{"theme" => "dark"}
      ...> }
      iex> compacted = JsonCompactor.compact(data)
      iex> compacted
      [
        %{"1" => "4", "2" => "5", "3" => "4"},  # Root with referenced keys
        "backup_user",                          # Field keys stored once
        "settings",
        "user", 
        %{"6" => "8", "7" => "9"},             # Nested map with referenced keys
        %{"10" => "11"},                       # Settings map
        "name",                                # Repeated field keys deduplicated
        "role",
        "Alice",                               # Values deduplicated
        "admin",
        "theme",
        "dark"
      ]
      iex> JsonCompactor.decompact(compacted) == data
      true

  In this example, both field keys and values are extracted and deduplicated:
  - Field keys like "name" and "role" are stored once at indices 6 and 7
  - Identical user maps reference the same object at index "4"  
  - Repeated strings like "Alice" and "admin" are also deduplicated
  - The root map keys "user", "backup_user", "settings" are also referenced
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
  Compacts a data structure by extracting maps, lists, field keys, and strings into a flat array
  and replacing them with string reference indices. Other data types are kept as original values.

  Both map field keys and values are automatically deduplicated, providing significant compression
  benefits for structured data with repeated field names.

  ## Parameters

  - `data` - The data structure to compact (any JSON value)

  ## Returns

  A list where:
  - For simple values (numbers, booleans, nil, dates): `[original_value]`
  - For complex structures:
    - First element: The root structure with field keys, maps, lists, and strings replaced by indices
    - Remaining elements: The extracted field keys, maps, lists, and strings in order of their indices

  ## Examples

  Simple map with field key referencing:

      iex> JsonCompactor.compact(%{"a" => 1})
      [%{"1" => 1}, "a"]

  Field keys and string values both referenced:

      iex> JsonCompactor.compact(%{"a" => "hello"})
      [%{"1" => "2"}, "a", "hello"]

  Multiple field keys referenced:

      iex> JsonCompactor.compact(%{"name" => "Alice", "age" => 30, "active" => true})
      [%{"1" => true, "2" => 30, "3" => "4"}, "active", "age", "name", "Alice"]

  List with string value referencing:

      iex> JsonCompactor.compact([1, "hello", true])
      [[1, "1", true], "hello"]

  Complex nesting with field key and value deduplication:

      iex> data = %{
      ...>   "user" => %{"name" => "Alice", "role" => "admin"},
      ...>   "backup_user" => %{"name" => "Alice", "role" => "admin"},
      ...>   "settings" => %{"theme" => "dark"}
      ...> }
      iex> JsonCompactor.compact(data)
      [
        %{"1" => "4", "2" => "5", "3" => "4"},  # Root with referenced keys
        "backup_user",                          # Field keys deduplicated
        "settings",
        "user",
        %{"6" => "8", "7" => "9"},             # Nested map with referenced keys
        %{"10" => "11"},                       # Settings map
        "name",                                # Field key "name" stored once
        "role",                                # Field key "role" stored once  
        "Alice",                               # Value "Alice" stored once
        "admin",                               # Value "admin" stored once
        "theme",
        "dark"
      ]

  """
  @spec compact(json_value()) :: compacted_array()
  def compact(data) do
    # Always return a list
    if needs_compaction_reference?(data) do
      {_compacted, lookup_table} = build_lookup_table_dfs(data)

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

  # Build lookup table using depth-first search
  @spec build_lookup_table_dfs(json_value()) :: {String.t() | json_value(), map()}
  defp build_lookup_table_dfs(root) do
    # Phase 1: DFS to collect all unique values and assign indices
    stack = [root]
    {value_to_index, _} = dfs_collect_values(stack, %{}, 0)

    # Phase 2: Build compacted versions of complex structures
    final_lookup = build_compacted_structures(value_to_index)

    root_index = Map.get(value_to_index, root)
    {Integer.to_string(root_index), final_lookup}
  end

  # Helper function to add children to stack 
  @spec add_children_to_stack(json_value(), [json_value()]) :: [json_value()]
  defp add_children_to_stack(value, stack) do
    case value do
      map when is_map(map) ->
        clean_map = Map.delete(map, :__struct__)
        
        # Collect both string keys and values for referencing
        keys = Map.keys(clean_map) |> Enum.filter(&is_binary/1)
        values = Map.values(clean_map)
        children = keys ++ values

        # Prepend children to stack (DFS order)
        children ++ stack

      list when is_list(list) ->
        # Prepend list items to stack
        list ++ stack

      tuple when is_tuple(tuple) ->
        # Prepend tuple elements to stack
        Tuple.to_list(tuple) ++ stack

      _primitive ->
        # Strings and other primitives don't have children
        stack
    end
  end

  # Phase 1: DFS traversal to collect values that need references (maps, lists, strings)
  @spec dfs_collect_values([json_value()], map(), non_neg_integer()) :: {map(), non_neg_integer()}
  defp dfs_collect_values([], value_to_index, counter) do
    # Empty stack - traversal complete
    {value_to_index, counter}
  end

  defp dfs_collect_values([value | remaining_stack], value_to_index, counter) do
    case Map.get(value_to_index, value) do
      nil ->
        # Check if this value needs to be stored in reference table
        if needs_reference?(value) do
          # Store value and assign index
          updated_index_map = Map.put(value_to_index, value, counter)
          new_counter = counter + 1

          # Add children to stack
          children_stack = add_children_to_stack(value, remaining_stack)
          dfs_collect_values(children_stack, updated_index_map, new_counter)
        else
          # For non-reference values (numbers, booleans, etc.), still traverse children
          children_stack = add_children_to_stack(value, remaining_stack)
          dfs_collect_values(children_stack, value_to_index, counter)
        end

      _existing_index ->
        # Value already seen, skip and continue
        dfs_collect_values(remaining_stack, value_to_index, counter)
    end
  end

  # Phase 2: Build compacted versions of complex structures in single pass
  @spec build_compacted_structures(map()) :: map()
  defp build_compacted_structures(value_to_index) do
    # Pre-compute all string indices once
    string_indices = Map.new(value_to_index, fn {value, index} -> {value, to_string(index)} end)
    
    # Single pass to build compacted structures
    Map.new(value_to_index, fn {value, index} ->
      compacted_value = compact_value(value, string_indices)
      {compacted_value, index}
    end)
  end

  # Compact a single value based on its type
  @spec compact_value(json_value(), map()) :: json_value()
  defp compact_value(data, string_indices) when is_struct(data) do
    # Reuse map logic for struct fields, then add __struct__ key
    map = Map.from_struct(data)
    struct_name = to_string(data.__struct__)
    
    # Process struct fields using the same logic as regular maps
    compacted_map = compact_value(map, string_indices)
    
    # Add __struct__ key (preserved as-is, not referenced)
    Map.put(compacted_map, "__struct__", struct_name)
  end

  defp compact_value(map, string_indices) when is_map(map) do
    # Single iteration: convert atom keys and apply reference resolution
    Enum.reduce(map, %{}, fn {key, child_value}, acc_map ->
      # Convert atom key to ":atomname" format
      converted_key = if is_atom(key), do: ":" <> Atom.to_string(key), else: key
      
      # Reference the KEY if it needs referencing
      referenced_key = if needs_reference?(converted_key) do
        Map.get(string_indices, converted_key, converted_key)
      else
        converted_key
      end
      
      # Reference the VALUE if it needs referencing  
      referenced_value = if needs_reference?(child_value) do
        Map.get(string_indices, child_value, child_value)
      else
        child_value
      end
      
      Map.put(acc_map, referenced_key, referenced_value)
    end)
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
      # Handle struct module names that were serialized as strings during compaction.
      # These are safe to convert back to atoms since they came from existing structs.
      {"Elixir." <> _module_suffix = struct_name, index} when is_binary(struct_name) ->
        try do
          {to_string(index), String.to_existing_atom(struct_name)}
        rescue
          ArgumentError ->
            # If atom doesn't exist, treat as regular string (safety fallback)
            {to_string(index), struct_name}
        end

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
          # RESOLVE KEY if it's a reference
          resolved_key_result = if is_binary(key) and Map.has_key?(index_map, key) do
            resolve_references(key, index_map, visited)
          else
            {:ok, key}
          end
          
          case resolved_key_result do
            {:ok, resolved_key} ->
              # RESOLVE VALUE
              case resolve_references(value, index_map, visited) do
                {:ok, resolved_value} ->
                  # Convert atom keys if needed
                  final_key =
                    case resolved_key do
                      ":" <> atom_name ->
                        try do
                          String.to_existing_atom(atom_name)
                        rescue
                          # Keep as string if atom doesn't exist
                          ArgumentError -> resolved_key
                        end

                      _ ->
                        # Regular string key
                        resolved_key
                    end

                  {:cont, {:ok, Map.put(acc, final_key, resolved_value)}}

                {:error, message} ->
                  {:halt, {:error, message}}
              end
            
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
