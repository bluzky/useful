defmodule Pipeline do
  @moduledoc """
  `Pipeline` is a utility module for composing and executing sequential, named steps
  in a pipeline fashion. Each step is identified by a unique key and receives as input
  the accumulated output of all previous steps. Steps can be dynamically added, conditionally
  included, and may optionally ignore their return value.

  ## Features

    * Compose pipelines from named steps, each a function of the accumulated output.
    * Dynamically add steps with `add/3`.
    * Conditionally add steps at build time with `add_if/5`.
    * Steps may return `{:ok, value}` (stored in the result map), `:ok` (ignored), or `{:error, reason}` (halts execution).
    * Early exit on error, returning the error and the accumulated output so far.
    * Inspired by Ecto.Multi, but generalized for any sequential processing.

  ## Example

      pipeline =
        Pipeline.new()
        |> Pipeline.add("a", fn _input -> {:ok, 5} end)
        |> Pipeline.add_if(true, "b", fn input -> {:ok, input["a"] * 2} end)
        |> Pipeline.add_if(false, "c", fn _input -> {:ok, :should_not_run} end)

      {:ok, result} = Pipeline.run(pipeline)
      # result: %{"a" => 5, "b" => 10}

  """

  defstruct steps: []

  @type t :: %__MODULE__{
          steps: [{String.t(), (map() -> {:ok, any()} | {:error, any()} | :ok)}]
        }

  @doc """
  Creates an empty pipeline.

  ## Example

      pipeline = Pipeline.new()
  """
  @spec new() :: t()
  def new, do: %__MODULE__{steps: []}

  @doc """
  Creates a pipeline from a list of `{key, function}` steps.

  Each function must accept a map (the accumulated output) and return one of:
    * `{:ok, value}` — value is stored under `key` in the result map.
    * `:ok` — value is ignored, nothing is stored for `key`.
    * `{:error, reason}` — halts execution and returns error.

  ## Example

      steps = [
        {"a", fn _input -> {:ok, 1} end},
        {"b", fn input -> {:ok, input["a"] + 2} end}
      ]
      pipeline = Pipeline.new(steps)
  """
  @spec new([{String.t(), (map() -> {:ok, any()} | {:error, any()} | :ok)}]) :: t()
  def new(steps) when is_list(steps) do
    %__MODULE__{steps: steps}
  end

  @doc """
  Adds a step to the pipeline.

  The `key` must be unique in the pipeline. The `fun` must accept the accumulated output map
  and return `{:ok, value}`, `:ok`, or `{:error, reason}`.

  ## Example

      pipeline = Pipeline.add(pipeline, "c", fn input -> {:ok, input["a"] + input["b"]} end)
  """
  @spec add(t(), String.t(), (map() -> {:ok, any()} | {:error, any()} | :ok)) :: t()
  def add(%__MODULE__{steps: steps} = pipeline, key, fun)
      when is_binary(key) and is_function(fun, 1) do
    if Enum.any?(steps, fn {k, _} -> k == key end) do
      raise ArgumentError, "Step with key #{inspect(key)} already exists in the pipeline"
    end

    %__MODULE__{pipeline | steps: steps ++ [{key, fun}]}
  end

  @doc """
  Conditionally adds a step to the pipeline at build time.

  The `condition` can be:
    * a boolean — if `true`, the step is added; if `false`, it is skipped.
    * a function of arity 1 — called with the current accumulated output (`acc`), must return a boolean.

  The `acc` argument is the current accumulated output map at build time (defaults to `%{}`).

  ## Example

      # Add step "b" only if "a" is greater than 3 in the accumulated output
      pipeline = Pipeline.add_if(pipeline, fn acc -> acc["a"] > 3 end, "b", fn input -> {:ok, input["a"] * 2} end, %{"a" => 5})

      # Add step "c" only if the boolean is true
      pipeline = Pipeline.add_if(pipeline, true, "c", fn _input -> {:ok, 42} end)
  """
  @spec add_if(
          t(),
          boolean | (map() -> boolean),
          String.t(),
          (map() -> {:ok, any()} | {:error, any()} | :ok),
          map()
        ) :: t()
  def add_if(pipeline, condition, key, fun, acc \\ %{})

  def add_if(pipeline, true, key, fun, _acc), do: add(pipeline, key, fun)
  def add_if(pipeline, false, _key, _fun, _acc), do: pipeline

  def add_if(pipeline, condition, key, fun, acc) when is_function(condition, 1) do
    if condition.(acc) do
      add(pipeline, key, fun)
    else
      pipeline
    end
  end

  @doc """
  Executes the pipeline, optionally with an initial input map.

  Each step receives the accumulated output map. If a step returns:
    * `{:ok, value}` — value is stored under the step's key.
    * `:ok` — value is ignored, nothing is stored for the key.
    * `{:error, reason}` — execution halts, returns error tuple.

  ## Return values

    * `{:ok, result_map}` — all steps succeeded.
    * `{:error, key, reason, result_map}` — step `key` failed with `reason`, `result_map` is the output so far.

  ## Example

      {:ok, result} = Pipeline.run(pipeline)
      {:error, key, reason, partial_result} = Pipeline.run(pipeline)

  """
  @spec run(t(), map()) :: {:ok, map()} | {:error, String.t(), any(), map()}
  def run(%__MODULE__{steps: steps}, initial \\ %{}) when is_map(initial) do
    Enum.reduce_while(steps, initial, fn {key, fun}, acc ->
      case fun.(acc) do
        {:ok, value} ->
          {:cont, Map.put(acc, key, value)}

        :ok ->
          {:cont, acc}

        {:error, reason} ->
          {:halt, {:error, key, reason, acc}}
      end
    end)
    |> case do
      {:error, key, reason, acc} -> {:error, key, reason, acc}
      acc -> {:ok, acc}
    end
  end
end
