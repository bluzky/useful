defmodule Commands do
  @moduledoc """
  A command chaining pattern for executing sequential operations with automatic error handling.

  Inspired by Ecto.Multi, Commands allows you to build a pipeline of operations where:
  - Each operation can access results from previous operations
  - Execution stops on first error with context for rollback
  - Success results are accumulated and returned together

  ## Key Differences from `with`

  Unlike Elixir's `with` construct, Commands provides access to successful results
  even when handling errors, enabling rollback operations and better error recovery.

  ## Basic Usage

      iex> Commands.new()
      ...> |> Commands.chain(:create_user, fn ->
      ...>   {:ok, %User{id: 1, name: "John"}}
      ...> end)
      ...> |> Commands.chain(:create_post, fn %{create_user: user} ->
      ...>   {:ok, %Post{id: 1, user_id: user.id, title: "Hello"}}
      ...> end)
      ...> |> Commands.exec()
      {:ok, %{create_user: %User{}, create_post: %Post{}}}

  ## Error Handling with Rollback

      Commands.new()
      |> Commands.chain(:create_user, fn -> User.create(%{name: "John"}) end)
      |> Commands.chain(:send_email, fn %{create_user: user} ->
        Email.send_welcome(user)
      end)
      |> Commands.exec()
      |> case do
        {:ok, results} ->
          {:ok, results}
        {:error, :send_email, _error, %{create_user: user}} ->
          # Email failed but user was created - clean up
          User.delete(user.id)
          {:error, "Welcome email failed"}
        {:error, :create_user, error, _} ->
          {:error, error}
      end

  ## Operation Requirements

  Operations must:
  - Return `{:ok, result}` on success or `{:error, reason}` on failure
  - Accept either no arguments (0-arity) or the accumulated results map (1-arity)

  ## Return Values

  - **Success**: `{:ok, %{operation_key => result, ...}}`
  - **Error**: `{:error, failed_operation_key, error_reason, successful_results_so_far}`

  The error tuple provides everything needed for rollback operations or partial cleanup.
  """

  alias Commands

  defstruct chains: []

  @type operation ::
          (-> {:ok, any()} | {:error, any()})
          | (map() -> {:ok, any()} | {:error, any()})
  @type t :: %Commands{chains: [{atom() | String.t(), operation()}]}
  @type exec_result :: {:ok, map()} | {:error, atom() | String.t(), any(), map()}

  @doc """
  Creates a new empty command chain.

  ## Examples

      iex> Commands.new()
      %Commands{chains: []}
  """
  @spec new() :: Commands.t()
  def new do
    %Commands{chains: []}
  end

  @doc """
  Adds an operation to the command chain.

  The operation will be executed in the order it was added. Operations can be:
  - 0-arity functions that don't need previous results
  - 1-arity functions that receive a map of all previous successful results

  ## Parameters

  - `cmd` - The command chain to add to
  - `key` - Unique identifier for this operation's result
  - `op` - Function that returns `{:ok, result}` or `{:error, reason}`

  ## Examples

      # 0-arity operation
      Commands.chain(cmd, :fetch_data, fn ->
        {:ok, "some data"}
      end)

      # 1-arity operation using previous results
      Commands.chain(cmd, :process_data, fn %{fetch_data: data} ->
        {:ok, String.upcase(data)}
      end)
  """
  @spec chain(Commands.t(), atom() | String.t(), operation()) :: Commands.t()
  def chain(%Commands{} = cmd, key, op) when is_function(op, 0) or is_function(op, 1) do
    %{cmd | chains: [{key, op} | cmd.chains]}
  end

  @doc """
  Conditionally adds an operation to the chain.

  The operation is only added if the condition evaluates to `true`.

  ## Examples

      Commands.chain_if(cmd, :send_notification, user.email_enabled?, fn ->
        Notification.send(user)
      end)
  """
  @spec chain_if(Commands.t(), atom() | String.t(), boolean(), operation()) :: Commands.t()
  def chain_if(%Commands{} = cmd, key, condition, op) do
    if condition do
      chain(cmd, key, op)
    else
      cmd
    end
  end

  @doc """
  Executes all operations in the command chain.

  Operations are executed in the order they were added. Each operation receives
  a map containing the results of all previously successful operations.

  Execution stops immediately on the first error, returning the error along with
  all successful results accumulated up to that point.

  ## Return Values

  - `{:ok, results_map}` - All operations succeeded
  - `{:error, failed_key, error_reason, partial_results}` - An operation failed

  ## Examples

      iex> Commands.new()
      ...> |> Commands.chain(:step1, fn -> {:ok, "result1"} end)
      ...> |> Commands.chain(:step2, fn -> {:ok, "result2"} end)
      ...> |> Commands.exec()
      {:ok, %{step1: "result1", step2: "result2"}}

      iex> Commands.new()
      ...> |> Commands.chain(:step1, fn -> {:ok, "result1"} end)
      ...> |> Commands.chain(:step2, fn -> {:error, "failed"} end)
      ...> |> Commands.exec()
      {:error, :step2, "failed", %{step1: "result1"}}
  """
  @spec exec(Commands.t()) :: exec_result()
  def exec(%Commands{chains: chains}) do
    chains
    |> Enum.reverse()
    |> Enum.reduce({:ok, %{}}, fn
      {key, op}, {:ok, acc} ->
        result =
          if is_function(op, 0) do
            op.()
          else
            op.(acc)
          end

        case result do
          {:ok, result} -> {:ok, Map.put(acc, key, result)}
          {:error, error} -> {:error, key, error, acc}
        end

      _, error ->
        error
    end)
  end
end
