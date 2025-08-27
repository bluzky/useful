defmodule DictCompactor do
  @moduledoc """
  Alternative JSON compactor using string dictionary approach.

  This implementation preserves the original data structure while extracting
  only strings and serialized atom strings into a separate dictionary for deduplication.

  ## Features
  - No structure flattening - maintains original nesting
  - String dictionary for deduplication of strings and atom strings only
  - JSON-compatible serialization for atoms, tuples, structs
  - Both key and value references for strings
  - Deterministic output with sorted keys

  ## Output Format

      %{
        data: original_structure_with_references,
        dictionary: %{
          "0" => "actual_string_value_1",
          "1" => "actual_string_value_2"
        }
      }

  ## Examples

      iex> input = %{"name" => "Alice", "role" => "admin"}
      iex> DictCompactor.compact(input)
      %{
        data: %{"0" => "1", "2" => "3"},
        dictionary: %{
          "0" => "name",
          "1" => "Alice",
          "2" => "role",
          "3" => "admin"
        }
      }

      iex> # Complex types - JSON compatible
      iex> input = %{atom: :hello, tuple: {1, 2}, user: %User{name: "Bob"}}
      iex> DictCompactor.compact(input)
      %{
        data: %{"0" => "1", "2" => ["__t__", 1, 2], "3" => %{"4" => "5", "__struct__" => "6"}},
        dictionary: %{
          "0" => "atom",
          "1" => "_:hello",
          "2" => "tuple",
          "3" => "user",
          "4" => "name",
          "5" => "Bob",
          "6" => "Elixir.User"
        }
      }
  """

  @type compacted_data :: %{
          data: any(),
          dictionary: %{String.t() => String.t()}
        }

  @type decompact_result :: {:ok, any()} | {:error, String.t()}

  # JSON-compatible serialization formats
  @atom_prefix "_:"
  @tuple_marker "__t__"

  @doc """
  Compacts data using string dictionary approach.

  Extracts all referenceable values into a dictionary while preserving
  the original structure with reference indices.
  """
  @spec compact(any()) :: compacted_data()
  def compact(data) do
    # Phase 1: Collect all referenceable values
    {dictionary, _counter} = collect_values(data, %{}, 0)

    # Phase 2: Build reverse lookup for value -> index
    value_to_index =
      dictionary
      |> Enum.map(fn {index, value} -> {value, index} end)
      |> Map.new()

    # Phase 3: Replace values with references in data
    referenced_data = replace_with_references(data, value_to_index)

    %{
      data: referenced_data,
      dictionary: dictionary
    }
  end

  @doc """
  Decompacts data from dictionary format back to original structure.
  """
  @spec decompact(compacted_data()) :: decompact_result()
  def decompact(%{data: data, dictionary: dictionary}) do
    try do
      # First deserialize all dictionary values
      deserialized_dict =
        deserialize_dictionary_values(dictionary)

      # Then replace references in data structure
      restored_data = replace_references_with_values(data, deserialized_dict)

      {:ok, restored_data}
    rescue
      e -> {:error, "Decompaction failed: #{inspect(e)}"}
    end
  end

  def decompact(_), do: {:error, "Invalid compacted data format"}

  # Phase 1: Collect all referenceable values with DFS
  defp collect_values(data, dictionary, counter) do
    case data do
      # Handle maps (including structs)
      map when is_map(map) ->
        collect_from_map(map, dictionary, counter)

      # Handle lists
      list when is_list(list) ->
        collect_from_list(list, dictionary, counter)

      # Handle tuples - serialize as JSON array (don't reference the tuple itself)
      tuple when is_tuple(tuple) ->
        tuple_list = Tuple.to_list(tuple)
        collect_from_list(tuple_list, dictionary, counter)

      # Handle atoms - serialize as string
      atom when is_atom(atom) and not is_nil(atom) and not is_boolean(atom) ->
        serialized = serialize_atom(atom)
        add_to_dictionary_if_new(serialized, dictionary, counter)

      # Handle strings
      string when is_binary(string) ->
        add_to_dictionary_if_new(string, dictionary, counter)

      # Skip primitives (numbers, booleans, nil)
      _ ->
        {dictionary, counter}
    end
  end

  defp collect_from_map(map, dictionary, counter) do
    # For structs, add struct name to collection
    {updated_dict, updated_counter} =
      if is_struct(map) do
        struct_name = Atom.to_string(map.__struct__)
        add_to_dictionary_if_new(struct_name, dictionary, counter)
      else
        {dictionary, counter}
      end

    # Convert struct to map for processing
    processed_map =
      if is_struct(map) do
        Map.from_struct(map)
      else
        map
      end

    # Process all keys and values
    processed_map
    |> Map.to_list()
    |> Enum.reduce({updated_dict, updated_counter}, fn {key, value}, {acc_dict, acc_counter} ->
      # Collect from key (convert atom keys to strings first)
      string_key = if is_atom(key), do: serialize_atom(key), else: key
      {dict_after_key, counter_after_key} = collect_values(string_key, acc_dict, acc_counter)

      # Collect from value
      collect_values(value, dict_after_key, counter_after_key)
    end)
  end

  defp collect_from_list(list, dictionary, counter) do
    Enum.reduce(list, {dictionary, counter}, fn item, {acc_dict, acc_counter} ->
      collect_values(item, acc_dict, acc_counter)
    end)
  end

  defp add_to_dictionary_if_new(value, dictionary, counter) do
    # Check if value already exists in dictionary
    existing_key =
      Enum.find_value(dictionary, fn {key, dict_value} ->
        if dict_value == value, do: key, else: nil
      end)

    if existing_key do
      # Already exists, no change
      {dictionary, counter}
    else
      key = Integer.to_string(counter)
      updated_dict = Map.put(dictionary, key, value)
      {updated_dict, counter + 1}
    end
  end

  # Phase 2: Replace values with references
  defp replace_with_references(data, value_to_index) do
    case data do
      # Handle maps (including structs)
      map when is_map(map) ->
        if is_struct(map) do
          # Convert struct to map with __struct__ field
          struct_name = Atom.to_string(map.__struct__)
          struct_map = Map.from_struct(map)

          processed_contents =
            process_map_contents(struct_map, value_to_index)

          referenced_struct_name = replace_with_references(struct_name, value_to_index)
          Map.put(processed_contents, "__struct__", referenced_struct_name)
        else
          process_map_contents(map, value_to_index)
        end

      # Handle lists
      list when is_list(list) ->
        Enum.map(list, fn item ->
          replace_with_references(item, value_to_index)
        end)

      # Handle tuples - convert to JSON array format
      tuple when is_tuple(tuple) ->
        tuple_list = Tuple.to_list(tuple)

        referenced_list =
          Enum.map(tuple_list, fn item ->
            replace_with_references(item, value_to_index)
          end)

        [@tuple_marker | referenced_list]

      # Handle atoms
      atom when is_atom(atom) and not is_nil(atom) and not is_boolean(atom) ->
        serialized = serialize_atom(atom)
        # Fallback to original if not found
        Map.get(value_to_index, serialized, atom)

      # Handle strings
      string when is_binary(string) ->
        # Fallback to original if not found
        Map.get(value_to_index, string, string)

      # Return primitives as-is
      primitive ->
        primitive
    end
  end

  defp process_map_contents(map, value_to_index) do
    map
    |> Enum.map(fn {key, value} ->
      # Process key - convert atoms to strings but preserve the atom in the key position for now
      string_key = if is_atom(key), do: serialize_atom(key), else: key
      referenced_key = replace_with_references(string_key, value_to_index)

      # Process value
      referenced_value = replace_with_references(value, value_to_index)

      {referenced_key, referenced_value}
    end)
    |> Map.new()
  end

  # Phase 3: Restoration helpers
  defp replace_references_with_values(data, dictionary) do
    case data do
      # Handle reference strings
      ref when is_binary(ref) ->
        case Map.get(dictionary, ref) do
          # Not a reference, return as-is
          nil -> ref
          # Found in dictionary, return the value
          value -> value
        end

      # Handle maps
      map when is_map(map) ->
        result =
          map
          |> Enum.map(fn {key, value} ->
            restored_key = replace_references_with_values(key, dictionary)
            restored_value = replace_references_with_values(value, dictionary)
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
        |> replace_references_with_values(dictionary)
        |> List.to_tuple()

      # Handle lists
      list when is_list(list) ->
        Enum.map(list, fn item ->
          replace_references_with_values(item, dictionary)
        end)

      # Return primitives as-is
      primitive ->
        primitive
    end
  end

  defp deserialize_dictionary_values(dictionary) do
    dictionary
    |> Enum.map(fn {key, value} ->
      deserialized_value = deserialize_value(value)
      {key, deserialized_value}
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

  defp deserialize_value(value) when is_list(value) do
    IO.inspect(value)

    case value do
      [@tuple_marker | tuple_elements] ->
        # Convert tuple array back to tuple
        deserialized_elements = Enum.map(tuple_elements, &deserialize_value/1)
        List.to_tuple(deserialized_elements)

      list ->
        Enum.map(list, &deserialize_value/1)
    end
  end

  defp deserialize_value(value) when is_map(value) do
    case Map.get(value, "__struct__") do
      nil ->
        # Regular map - convert string keys back to atoms if they were originally atoms
        value
        |> Enum.map(fn {k, v} ->
          # Try to deserialize key - if it fails, keep as string
          deserialized_key =
            try do
              deserialize_value(k)
            rescue
              _ -> k
            end

          {deserialized_key, deserialize_value(v)}
        end)
        |> Map.new()

      struct_name_ref ->
        # Reconstruct struct
        struct_name = deserialize_value(struct_name_ref)
        module = String.to_existing_atom(struct_name)
        map_without_struct = Map.delete(value, "__struct__")

        deserialized_map =
          map_without_struct
          |> Enum.map(fn {k, v} ->
            # Convert string keys back to atoms for struct fields
            atom_key =
              if is_binary(k) do
                try do
                  deserialized_k = deserialize_value(k)

                  if is_binary(deserialized_k),
                    do: String.to_existing_atom(deserialized_k),
                    else: deserialized_k
                rescue
                  _ -> if is_binary(k), do: String.to_existing_atom(k), else: k
                end
              else
                k
              end

            {atom_key, deserialize_value(v)}
          end)
          |> Map.new()

        struct!(module, deserialized_map)
    end
  end

  defp deserialize_value(value), do: value

  # JSON-compatible serialization helpers
  defp serialize_atom(atom) do
    @atom_prefix <> Atom.to_string(atom)
  end
end
