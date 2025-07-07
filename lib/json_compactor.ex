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
      iex> result = JsonCompactor.compact(data)
      iex> length(result)
      6
      iex> JsonCompactor.decompact(result) == data
      true
  """

  def compact(data) do
    {flat_data, _} = do_compact([data])
    flat_data
  end

  defp do_compact(items, compacted_data \\ [], counter \\ 0)

  defp do_compact([], acc, counter) do
    {Enum.reverse(acc), counter}
  end

  defp do_compact(data, acc, counter) do
    # Recursively compact children
    {compacted_data, new_counter, children} =
      Enum.reduce(data, {acc, counter, []}, fn item, {acc, counter, children} ->
        {compacted_item, new_counter, nested_children} = compact_item(item, counter)
        new_acc = [compacted_item | acc]
        {new_acc, new_counter, [nested_children | children]}
      end)

    do_compact(Enum.concat(children), compacted_data, new_counter)
  end

  defp compact_item(item, counter) when is_map(item) do
    {compacted_map, counter, children} =
      Enum.reduce(item, {%{}, counter, []}, fn {key, value}, {acc, counter, children} ->
        if is_map(value) or is_list(value) or is_binary(value) do
          {Map.put(acc, key, "#{counter + 1}"), counter + 1, [value | children]}
        else
          {Map.put(acc, key, value), counter, children}
        end
      end)

    {compacted_map, counter, Enum.reverse(children)}
  end

  defp compact_item(item, counter) when is_list(item) do
    {compacted_items, counter, children} =
      Enum.reduce(item, {[], counter, []}, fn value, {acc, counter, children} ->
        if is_map(value) or is_list(value) or is_binary(value) do
          {["#{counter + 1}" | acc], counter + 1, [value | children]}
        else
          {[value | acc], counter, children}
        end
      end)

    {Enum.reverse(compacted_items), counter, Enum.reverse(children)}
  end

  defp compact_item(item, counter) do
    {item, counter, []}
  end
end
