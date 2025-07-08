defmodule DataRouter do
  @moduledoc """
  A data routing module that matches incoming data against patterns
  and determines which queue to enqueue the data to.

  Uses DataMatcher for pattern matching logic.
  """

  @doc """
  Matches data against route definitions and returns the corresponding queue name.

  Routes are checked in the order they appear in the map (implementation dependent).
  Returns the first matching queue name, or an error if no routes match.

  ## Examples

      iex> routes = %{
      ...>   "user_queue" => %{type: "user"},
      ...>   "admin_queue" => %{type: "user", role: "admin"}
      ...> }
      iex> DataRouter.match_route(routes, %{type: "user", role: "admin"})
      {:ok, "admin_queue"}

      iex> routes = %{
      ...>   "js_queue" => %{skills: DataMatcher.any("javascript")},
      ...>   "elixir_queue" => %{skills: DataMatcher.any("elixir")}
      ...> }
      iex> DataRouter.match_route(routes, %{skills: ["elixir", "phoenix"]})
      {:ok, "elixir_queue"}

      iex> routes = %{"test_queue" => %{name: "test"}}
      iex> DataRouter.match_route(routes, %{name: "other"})
      {:error, "not_found"}
  """
  @spec match_route(map(), any()) :: {:ok, String.t()} | {:error, String.t()}
  def match_route(routes_definitions, data) when is_map(routes_definitions) do
    routes_definitions
    |> Enum.find(fn {_queue_name, pattern} ->
      DataMatcher.match(data, pattern)
    end)
    |> case do
      {queue_name, _pattern} -> {:ok, queue_name}
      nil -> {:error, "not_found"}
    end
  end

  def match_route(_routes_definitions, _data) do
    {:error, "invalid_routes"}
  end
end
