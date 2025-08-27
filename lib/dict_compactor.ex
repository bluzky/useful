defmodule DictCompactor do
  @moduledoc """
  Alternative JSON compactor using string dictionary approach with single-pass optimization.

  This implementation preserves the original data structure while extracting
  only strings and serialized atom strings into a separate dictionary for deduplication.
  Uses a single-pass algorithm that simultaneously collects referenceable values and
  replaces them with dictionary indices for optimal performance.

  ## Features
  - Single-pass compaction algorithm - traverse data only once
  - No structure flattening - maintains original nesting
  - String dictionary for deduplication of strings and atom strings only
  - JSON-compatible serialization for atoms, tuples, structs
  - Both key and value references for strings
  - Automatic deduplication with O(1) reference lookup
  - Memory efficient - no intermediate data structures

  ## Output Format

      %{
        data: original_structure_with_references,
        dictionary: [
          "actual_string_value_1",  # index 0
          "actual_string_value_2"   # index 1
        ]
      }

  ## Type Handling

      # JSON-Compatible Serialization
      atom: :hello → "_:hello"                    # String with prefix (referenceable)
      tuple: {1, 2} → ["__t__", 1, 2]            # Array with marker (NOT referenceable)
      struct: %User{name: "hi"} → %{"__struct__" => "Elixir.User", "name" => "hi"} (NOT referenceable)

      # Referenceable Types (go in dictionary)
      - Strings (always)
      - Serialized atoms: "_:atom_name" 
      - String map keys

      # Non-Referenceable Types (preserved as-is)
      - Numbers, booleans, nil
      - Arrays (including tuple arrays)
      - Objects (including struct objects)

  ## Examples

      iex> # Simple map with string deduplication
      iex> input = %{"name" => "Alice", "role" => "admin"}
      iex> DictCompactor.compact(input)
      %{
        data: %{"0" => "1", "2" => "3"},
        dictionary: [
          "name",     # index 0
          "Alice",    # index 1
          "role",     # index 2
          "admin"     # index 3
        ]
      }

      iex> # Atom keys and values with deduplication
      iex> input = %{name: "Alice", role: :admin}
      iex> DictCompactor.compact(input)
      %{
        data: %{"0" => "1", "2" => "3"},
        dictionary: [
          "_:name",   # index 0
          "Alice",    # index 1
          "_:role",   # index 2
          "_:admin"   # index 3
        ]
      }

      iex> # Complex types with JSON-compatible serialization
      iex> input = %{atom: :hello, tuple: {1, :two}, struct: %User{name: "Bob"}}
      iex> DictCompactor.compact(input)
      %{
        data: %{"0" => "1", "2" => ["__t__", 1, "3"], "4" => %{"5" => "6", "__struct__" => "7"}},
        dictionary: [
          "_:atom",      # index 0
          "_:hello",     # index 1
          "_:tuple",     # index 2
          "_:two",       # index 3
          "_:struct",    # index 4
          "_:name",      # index 5
          "Bob",         # index 6
          "Elixir.User"  # index 7
        ]
      }

      iex> # Deduplication in action
      iex> input = %{user1: %{name: "Alice"}, user2: %{name: "Alice"}}
      iex> result = DictCompactor.compact(input)
      iex> # "Alice" appears only once in dictionary despite being used twice
      iex> Enum.count(result.dictionary, fn v -> v == "Alice" end)
      1

  ## Performance

  The single-pass algorithm provides significant performance benefits:
  - **Time Complexity**: O(n) where n = total elements in data structure
  - **Space Complexity**: O(u) where u = unique referenceable values
  - **Memory Usage**: No intermediate collections, direct reference replacement
  - **Compaction**: O(1) deduplication lookup, O(1) dictionary prepend operations
  - **Decompaction**: O(1) reference lookup via pre-built index map
  """

  @type compacted_data :: %{
          data: any(),
          dictionary: [String.t()]
        }

  @type decompact_result :: {:ok, any()} | {:error, String.t()}

  # JSON-compatible serialization formats
  @atom_prefix "_:"
  @tuple_marker "__t__"

  @doc """
  Compacts data using single-pass string dictionary approach.

  Simultaneously extracts referenceable values into a dictionary and replaces
  them with reference indices in the original structure. Only strings and
  serialized atom strings are referenced for optimal JSON compatibility.

  ## Algorithm
  - Single traversal of the data structure
  - Immediate deduplication using O(1) hash map lookup
  - Direct reference replacement during traversal
  - Preserves original nesting and structure
  - Efficient O(1) prepend operations for dictionary construction

  ## Returns
  A map with `:data` (structure with references) and `:dictionary` (index → value mapping).
  """
  @spec compact(any()) :: compacted_data()
  def compact(data) do
    # Single pass: collect values and replace with references simultaneously
    {referenced_data, dictionary_list, _value_to_index, _counter} = compact_recursive(data, [], %{}, 0)

    %{
      data: referenced_data,
      dictionary: Enum.reverse(dictionary_list)
    }
  end

  @doc """
  Decompacts data from dictionary format back to original structure.
  
  Builds an index map once at the beginning for O(1) reference lookups
  during the restoration process, making decompaction very efficient.
  """
  @spec decompact(compacted_data()) :: decompact_result()
  def decompact(%{data: data, dictionary: dictionary_list}) do
    try do
      # First deserialize all dictionary values and build index map
      index_map = build_index_map(dictionary_list)

      # Then replace references in data structure
      restored_data = replace_references_with_values(data, index_map)

      {:ok, restored_data}
    rescue
      e -> {:error, "Decompaction failed: #{inspect(e)}"}
    end
  end

  def decompact(_), do: {:error, "Invalid compacted data format"}

  # Single-pass recursive compaction
  defp compact_recursive(data, dictionary_list, value_to_index, counter) do
    case data do
      # Handle maps (including structs)
      map when is_map(map) ->
        compact_map(map, dictionary_list, value_to_index, counter)

      # Handle lists
      list when is_list(list) ->
        compact_list(list, dictionary_list, value_to_index, counter)

      # Handle tuples - convert to JSON array format
      tuple when is_tuple(tuple) ->
        tuple_list = Tuple.to_list(tuple)
        {referenced_list, updated_dict, updated_index, final_counter} = 
          compact_list(tuple_list, dictionary_list, value_to_index, counter)
        {[@tuple_marker | referenced_list], updated_dict, updated_index, final_counter}

      # Handle atoms - serialize as string and reference
      atom when is_atom(atom) and not is_nil(atom) and not is_boolean(atom) ->
        serialized = serialize_atom(atom)
        get_or_add_reference(serialized, dictionary_list, value_to_index, counter)

      # Handle strings - reference them
      string when is_binary(string) ->
        get_or_add_reference(string, dictionary_list, value_to_index, counter)

      # Return primitives as-is
      primitive ->
        {primitive, dictionary_list, value_to_index, counter}
    end
  end

  defp compact_map(map, dictionary_list, value_to_index, counter) do
    # Handle struct name first if it's a struct
    {struct_dict, struct_index, struct_counter, struct_name_ref} = 
      if is_struct(map) do
        struct_name = Atom.to_string(map.__struct__)
        {ref, dict, idx, cnt} = get_or_add_reference(struct_name, dictionary_list, value_to_index, counter)
        {dict, idx, cnt, ref}
      else
        {dictionary_list, value_to_index, counter, nil}
      end

    # Convert struct to map for processing
    processed_map = if is_struct(map), do: Map.from_struct(map), else: map

    # Process all key-value pairs
    {result_map, final_dict, final_index, final_counter} = 
      processed_map
      |> Enum.reduce({%{}, struct_dict, struct_index, struct_counter}, 
        fn {key, value}, {acc_map, acc_dict, acc_index, acc_counter} ->
          # Process key
          string_key = if is_atom(key), do: serialize_atom(key), else: key
          {referenced_key, dict_after_key, index_after_key, counter_after_key} = 
            compact_recursive(string_key, acc_dict, acc_index, acc_counter)

          # Process value
          {referenced_value, dict_after_value, index_after_value, counter_after_value} = 
            compact_recursive(value, dict_after_key, index_after_key, counter_after_key)

          updated_map = Map.put(acc_map, referenced_key, referenced_value)
          {updated_map, dict_after_value, index_after_value, counter_after_value}
        end)

    # Add __struct__ field if this was a struct
    final_map = if struct_name_ref do
      Map.put(result_map, "__struct__", struct_name_ref)
    else
      result_map
    end

    {final_map, final_dict, final_index, final_counter}
  end

  defp compact_list(list, dictionary_list, value_to_index, counter) do
    {result_list, final_dict, final_index, final_counter} = 
      list
      |> Enum.reduce({[], dictionary_list, value_to_index, counter}, 
        fn item, {acc_list, acc_dict, acc_index, acc_counter} ->
          {referenced_item, dict_after_item, index_after_item, counter_after_item} = 
            compact_recursive(item, acc_dict, acc_index, acc_counter)
          {[referenced_item | acc_list], dict_after_item, index_after_item, counter_after_item}
        end)

    {Enum.reverse(result_list), final_dict, final_index, final_counter}
  end

  defp get_or_add_reference(value, dictionary_list, value_to_index, counter) do
    case Map.get(value_to_index, value) do
      nil ->
        # Add new reference (prepend for O(1) performance)
        index = Integer.to_string(counter)
        updated_dict = [value | dictionary_list]
        updated_index = Map.put(value_to_index, value, index)
        {index, updated_dict, updated_index, counter + 1}
      
      existing_index ->
        # Return existing reference
        {existing_index, dictionary_list, value_to_index, counter}
    end
  end

  # Phase 3: Restoration helpers
  defp replace_references_with_values(data, index_map) do
    case data do
      # Handle reference strings
      ref when is_binary(ref) ->
        case Map.get(index_map, ref) do
          nil -> ref  # Not a reference, return as-is
          value -> value  # Found in index map, return the value
        end

      # Handle maps
      map when is_map(map) ->
        result =
          map
          |> Enum.map(fn {key, value} ->
            restored_key = replace_references_with_values(key, index_map)
            restored_value = replace_references_with_values(value, index_map)
            {restored_key, restored_value}
          end)
          |> Map.new()

        try do
          struct_name = result["__struct__"]
          struct_module = String.to_existing_atom(struct_name)
          struct(struct_module, result)
        rescue
          _ -> result
        end

      [@tuple_marker | tuple_data] ->
        tuple_data
        |> replace_references_with_values(index_map)
        |> List.to_tuple()

      # Handle lists
      list when is_list(list) ->
        Enum.map(list, fn item ->
          replace_references_with_values(item, index_map)
        end)

      # Return primitives as-is
      primitive ->
        primitive
    end
  end

  defp build_index_map(dictionary_list) do
    dictionary_list
    |> Enum.with_index()
    |> Enum.map(fn {value, index} ->
      {Integer.to_string(index), deserialize_value(value)}
    end)
    |> Map.new()
  end

  defp deserialize_value(value) when is_binary(value) do
    if String.starts_with?(value, @atom_prefix) do
      atom_string = String.slice(value, String.length(@atom_prefix)..-1//1)
      String.to_existing_atom(atom_string)
    else
      value
    end
  end

  defp deserialize_value(value), do: value


  # JSON-compatible serialization helpers
  defp serialize_atom(atom) do
    @atom_prefix <> Atom.to_string(atom)
  end
end
