defmodule DefEnum do
  @moduledoc """
  This module provides a macro to define an enum.

  ## Example

      defmodule MyEnum do
        use DefEnum

        enum do
          value(:value1, "value1")
          value(:value2, "value2")
          value(:value3, "value3")
        end
      end
  """
  @accumulating_attrs [
    :enum_values
  ]

  @doc false
  defmacro __using__(_) do
    quote do
      import DefEnum, only: [enum: 1, enum: 2]
    end
  end

  @default_opts [module: nil, type: :string]
  defmacro enum(opts \\ [], do: block) do
    opts = Keyword.merge(@default_opts, opts)
    ast = DefEnum.__def_enum__(block)
    type_ast = DefEnum.__enum_type__(opts[:type])
    method_ast = DefEnum.__default_functions__()

    case opts[:module] do
      nil ->
        quote do
          # Create a lexical scope.
          (fn -> unquote(ast) end).()
          unquote(method_ast)
          unquote(type_ast)
        end

      module ->
        quote do
          defmodule unquote(module) do
            unquote(ast)

            unquote(method_ast)
            unquote(type_ast)
          end
        end
    end
  end

  # defmacro enum(do: block) do
  #   enum(opts: [], do: block)
  # end

  # default functions for enum
  def __default_functions__ do
    quote do
      @values Keyword.values(@enum_values)
      @string_values Enum.map(@values, &to_string/1)
      @all_values Enum.concat(@values, @string_values)
      def values do
        @all_values
      end
    end
  end

  # implement methods for supporting Ecto.Type
  def __enum_type__(type) do
    quote bind_quoted: [type: type] do
      use Ecto.Type

      def type, do: unquote(type)

      def cast(value) when is_atom(value) do
        value
        |> to_string()
        |> cast()
      end

      def cast(value) do
        with {:ok, value} <- Ecto.Type.cast(type(), value),
             true <- value in values() do
          {:ok, value}
        else
          _ -> :error
        end
      end

      def load(data) when is_binary(data) or is_integer(data) do
        {:ok, data}
      end

      def load(_), do: :error

      def dump(value) when is_binary(value) or is_integer(value), do: {:ok, value}
      def dump(value) when is_atom(value), do: {:ok, to_string(value)}
      def dump(_), do: :error
    end
  end

  @doc false
  def __def_enum__(block) do
    quote do
      import DefEnum

      Enum.each(unquote(@accumulating_attrs), fn attr ->
        Module.register_attribute(__MODULE__, attr, accumulate: true)
      end)

      unquote(block)
    end
  end

  @doc """
  Defines a field in a typed struct.

  ## Example

      # A field named :example of type String.t()
      value :elixir, "Elixir"

      value :erlang
      # is equivalent to
      value :erlang, "erlang"
  """
  defmacro value(name, value \\ nil) do
    value = value || to_string(name)

    quote bind_quoted: [name: name, value: value] do
      DefEnum.__value__(name, value, __ENV__)

      def unquote(name)(), do: unquote(value)
    end
  end

  @doc false
  def __value__(name, value, %Macro.Env{module: mod}) when is_atom(name) do
    if mod |> Module.get_attribute(:enum_values) |> Keyword.has_key?(name) do
      raise ArgumentError, "the enum #{inspect(name)} is already set"
    end

    Module.put_attribute(mod, :enum_values, {name, value})
  end

  def __value__(name, _type, _env) do
    raise ArgumentError, "a enum name must be an atom, got #{inspect(name)}"
  end
end
