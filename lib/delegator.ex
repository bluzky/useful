defmodule Delegator do
  @moduledoc """
  Borrowed from https://github.com/rill-project/delegate/tree/master

  Provides  `delegate_all` which allows delegating to all the functions on
  the target module

  `use Delegate.Function` provides all macros (require + import)
  """

  @type delegate_all_opts ::
          {:only, [{atom(), arity()}]} | {:except, [{atom(), arity()}]}

  @doc ~S"""
  Creates delegates for each function on the `:to` module

  ## Arguments
  - `to` module to delegate to and to find the list of functions to delegate
  - `opts` is a keyword:
    - `:only` (optional) functions that will be delegated, excluding everything
      else
    - `:except` (optional) all functions will be delegated except those listed
      in this argument

  ## Examples

  ```elixir
  defmodule Base do
    def hello(name) do
      "hello #{unquote(name)}"
    end

    def bye() do
      "bye"
    end
  end

  defmodule DelegateFun do
    use Delegate.Function

    delegate_all(Base)

    # Function `hello/1` and `bye/0` are defined in this module
  end

  DelegateFun.hello("Jon")
  DelegateFun.bye()
  ```
  """
  @spec delegate_all(
          to :: module(),
          opts :: [delegate_all_opts()]
        ) :: term()
  defmacro delegate_all(to, opts \\ []) do
    quote do
      require Delegator
      Delegator.defdelegatetype(:functions, unquote(to), unquote(opts))
    end
  end

  defmacro __using__(_opts \\ []) do
    quote do
      require unquote(__MODULE__)
      import unquote(__MODULE__)
    end
  end

  defmacro defdelegatetype(type, to, opts \\ []) when type == :functions do
    {delegator_module, delegator_macro} = {Kernel, :defdelegate}
    only = Keyword.get(opts, :only)
    except = Keyword.get(opts, :except, [])

    definitions =
      if is_nil(only) do
        to
        |> Macro.expand(__CALLER__)
        |> Kernel.apply(:__info__, [type])
      else
        only
      end

    definitions =
      Enum.reduce(except, definitions, fn definition, new_definitions ->
        {name, arity} = definition

        if Keyword.get(new_definitions, name) == arity do
          Keyword.delete(new_definitions, name)
        else
          new_definitions
        end
      end)

    header =
      quote do
        require unquote(delegator_module)
      end

    infinity_enum = Stream.iterate(1, &(&1 + 1))

    defs =
      Enum.map(definitions, fn definition ->
        {name, arity} = definition

        args =
          infinity_enum
          |> Stream.take(arity)
          |> Stream.map(&String.to_atom("arg#{&1}"))
          |> Enum.map(fn arg -> {arg, [], nil} end)

        quote do
          unquote(delegator_module).unquote(delegator_macro)(
            unquote(name)(unquote_splicing(args)),
            to: unquote(to)
          )
        end
      end)

    [header | defs]
  end
end
