defmodule DataMatcher do
  @moduledoc """
  A flexible data matching module that supports pattern matching for primitives,
  collections, and nested structures with string patterns and quantifiers.

  Also supports storing and loading patterns from JSON format.
  """

  @doc """
  Compares data against patterns with support for nested structures and flexible matching rules.

  ## Examples

      iex> DataMatcher.match(1, 1)
      true

      iex> DataMatcher.match("dev-octosell", "*-octosell")
      true

      iex> DataMatcher.match(%{name: "me", age: 15}, %{name: "me"})
      true

      iex> DataMatcher.match(["js", "elixir"], DataMatcher.any("elixir"))
      true
  """
  @spec match(any(), any()) :: boolean()
  def match(data, pattern) do
    do_match(data, pattern)
  end

  @doc """
  Creates a quantifier pattern that matches if at least one item in a list matches the pattern.

  ## Examples

      iex> DataMatcher.match([1, 2, 3], DataMatcher.any(2))
      true

      iex> DataMatcher.match([], DataMatcher.any(1))
      false
  """
  @spec any(any()) :: {:quantifier, :any, any()}
  def any(pattern), do: {:quantifier, :any, pattern}

  @doc """
  Creates a quantifier pattern that matches if all items in a list match the pattern.

  ## Examples

      iex> DataMatcher.match([1, 1, 1], DataMatcher.all(1))
      true

      iex> DataMatcher.match([], DataMatcher.all(1))
      true
  """
  @spec all(any()) :: {:quantifier, :all, any()}
  def all(pattern), do: {:quantifier, :all, pattern}

  @doc """
  Creates a quantifier pattern that matches if no items in a list match the pattern.

  ## Examples

      iex> DataMatcher.match([1, 2, 3], DataMatcher.none(4))
      true

      iex> DataMatcher.match([], DataMatcher.none(1))
      true
  """
  @spec none(any()) :: {:quantifier, :none, any()}
  def none(pattern), do: {:quantifier, :none, pattern}

  # Main matching logic
  defp do_match(data, pattern) do
    case pattern do
      # Handle quantifiers
      {:quantifier, quantifier_type, sub_pattern} ->
        handle_quantifier(data, quantifier_type, sub_pattern)

      # Handle maps
      pattern when is_map(pattern) and is_map(data) ->
        match_maps(data, pattern)

      # Handle lists (without quantifiers)
      pattern when is_list(pattern) and is_list(data) ->
        match_lists(data, pattern)

      # Handle string patterns
      pattern when is_binary(pattern) and is_binary(data) ->
        match_strings(data, pattern)

      # Handle exact matches (primitives, including nil)
      pattern ->
        data === pattern
    end
  rescue
    # Return false for any errors to avoid exceptions
    _ -> false
  end

  # Handle quantifier matching
  defp handle_quantifier(data, quantifier_type, pattern) when is_list(data) do
    case quantifier_type do
      :any ->
        case data do
          [] -> false
          _ -> Enum.any?(data, &do_match(&1, pattern))
        end

      :all ->
        case data do
          # vacuous truth - empty list means all elements match
          [] -> true
          _ -> Enum.all?(data, &do_match(&1, pattern))
        end

      :none ->
        case data do
          [] -> true
          _ -> not Enum.any?(data, &do_match(&1, pattern))
        end
    end
  end

  # Quantifiers only work on lists
  defp handle_quantifier(_data, _quantifier_type, _pattern), do: false

  # Map matching: pattern is subset of data
  defp match_maps(data, pattern) do
    Enum.all?(pattern, fn {key, pattern_value} ->
      case Map.get(data, key, :__not_found__) do
        :__not_found__ -> false
        data_value -> do_match(data_value, pattern_value)
      end
    end)
  end

  # List matching: exact length and element-wise matching
  defp match_lists(data, pattern) do
    length(data) == length(pattern) and
      Enum.zip(data, pattern)
      |> Enum.all?(fn {data_item, pattern_item} ->
        do_match(data_item, pattern_item)
      end)
  end

  # String pattern matching with * and ? wildcards
  defp match_strings(data, pattern) do
    # If pattern contains wildcards, use pattern matching
    if String.contains?(pattern, ["*", "?"]) do
      match_string_pattern(data, pattern)
    else
      # Exact string match
      data == pattern
    end
  end

  # String pattern matching implementation
  defp match_string_pattern(data, pattern) do
    # Convert pattern to regex-like matching
    # Escape special regex chars first, then replace our wildcards
    regex_pattern =
      pattern
      |> Regex.escape()
      # Restore our wildcards after escaping
      |> String.replace("\\*", ".*")
      |> String.replace("\\?", ".")

    # Create regex with anchors to match entire string
    case Regex.compile("^#{regex_pattern}$") do
      {:ok, regex} -> Regex.match?(regex, data)
      {:error, _} -> false
    end
  end
end

defmodule DataMatcher.JSON do
  @doc """
  Encode patterns to JSON string for storage/transmission.

  ## Examples

      iex> DataMatcher.JSON.encode(%{name: "me"})
      "{\\"name\\":\\"me\\"}"

      iex> DataMatcher.JSON.encode(DataMatcher.any(%{enabled: true}))
      "{\\"$quantifier\\":\\"any\\",\\"pattern\\":{\\"enabled\\":true}}"

  """
  @spec encode(any()) :: String.t()
  def encode(pattern) do
    pattern
    |> convert_pattern_to_json()
    |> Jason.encode!()
  end

  @doc """
  Load patterns from JSON string.

  ## Examples

      iex> DataMatcher.JSON.decode("{\\"name\\":\\"me\\"}")
      {:ok, %{"name" => "me"}}


      iex> DataMatcher.JSON.decode("invalid json")
      {:error, "Invalid JSON"}
  """
  @spec decode(String.t()) :: {:ok, any()} | {:error, String.t()}
  def decode(json_string) do
    cond do
      json_string == "" ->
        {:error, "Empty JSON string"}

      true ->
        case Jason.decode(json_string) do
          {:ok, decoded} ->
            convert_json_to_pattern(decoded)

          {:error, %Jason.DecodeError{}} ->
            {:error, "Invalid JSON"}

          {:error, error} ->
            {:error, "JSON decode error: #{inspect(error)}"}
        end
    end
  end

  # Convert internal pattern format to JSON-serializable format
  defp convert_pattern_to_json({:quantifier, type, sub_pattern}) do
    %{
      "$quantifier" => Atom.to_string(type),
      "pattern" => convert_pattern_to_json(sub_pattern)
    }
  end

  defp convert_pattern_to_json(pattern) when is_map(pattern) do
    pattern
    |> Enum.map(fn {key, value} ->
      json_key = if is_atom(key), do: Atom.to_string(key), else: key
      {json_key, convert_pattern_to_json(value)}
    end)
    |> Enum.into(%{})
  end

  defp convert_pattern_to_json(pattern) when is_list(pattern) do
    Enum.map(pattern, &convert_pattern_to_json/1)
  end

  defp convert_pattern_to_json(pattern)
       when is_atom(pattern) and pattern not in [true, false, nil] do
    Atom.to_string(pattern)
  end

  defp convert_pattern_to_json(pattern), do: pattern

  # Convert JSON representation back to internal pattern format
  defp convert_json_to_pattern(data) when is_map(data) do
    case data do
      %{"$quantifier" => type, "pattern" => pattern} ->
        case type do
          "any" ->
            case convert_json_to_pattern(pattern) do
              {:ok, converted_pattern} -> {:ok, {:quantifier, :any, converted_pattern}}
              error -> error
            end

          "all" ->
            case convert_json_to_pattern(pattern) do
              {:ok, converted_pattern} -> {:ok, {:quantifier, :all, converted_pattern}}
              error -> error
            end

          "none" ->
            case convert_json_to_pattern(pattern) do
              {:ok, converted_pattern} -> {:ok, {:quantifier, :none, converted_pattern}}
              error -> error
            end

          _ ->
            {:error, "Unknown quantifier: #{type}"}
        end

      %{"$quantifier" => _type} ->
        # Quantifier without pattern key is malformed
        {:error, "Malformed quantifier: missing 'pattern' key"}

      regular_map ->
        converted_map =
          Enum.reduce_while(regular_map, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
            case convert_json_to_pattern(value) do
              {:ok, converted_value} -> {:cont, {:ok, Map.put(acc, key, converted_value)}}
              error -> {:halt, error}
            end
          end)

        converted_map
    end
  end

  defp convert_json_to_pattern(data) when is_list(data) do
    Enum.reduce_while(data, {:ok, []}, fn item, {:ok, acc} ->
      case convert_json_to_pattern(item) do
        {:ok, converted_item} -> {:cont, {:ok, [converted_item | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, reversed_list} -> {:ok, Enum.reverse(reversed_list)}
      error -> error
    end
  end

  defp convert_json_to_pattern(data), do: {:ok, data}
end
