defmodule DefEnum do
  @moduledoc """
  A macro-based utility for defining typed enums with Ecto integration.

  Provides a clean DSL for creating enums that automatically implement Ecto.Type
  behavior for seamless database operations, along with helper functions for
  value validation and retrieval.

  ## Features

  - Clean DSL for enum definition using `value/2` macro
  - Automatic Ecto.Type implementation with configurable storage type
  - Generated helper functions for each enum value
  - Validation of input values (supports both atoms and strings)
  - Flexible usage: inline or as separate modules

  ## Basic Usage

      defmodule Status do
        use DefEnum

        enum do
          value(:active, "active")
          value(:inactive, "inactive")
          value(:pending)  # defaults to "pending"
        end
      end

      # Generated functions
      Status.active()    # => "active"
      Status.values()    # => ["active", "inactive", "pending", :active, :inactive, :pending]

  ## Ecto Integration

      defmodule User do
        use Ecto.Schema

        schema "users" do
          field :status, Status  # Uses the enum as Ecto type
        end
      end

      # Casting works with atoms or strings
      Status.cast(:active)     # => {:ok, "active"}
      Status.cast("inactive")  # => {:ok, "inactive"}
      Status.cast("invalid")   # => :error

  ## Module Definition

      # Define enum as separate module
      enum module: UserRole do
        value(:admin, "admin")
        value(:user, "user")
      end

  ## Gettext Integration

      defmodule UserStatus do
        use DefEnum,
          gettext_module: MyApp.Gettext,
          gettext_domain: "enums"

        enum do
          value(:active, "active")
          value(:inactive, "inactive")
          value(:pending, "pending", label: "status.waiting")  # custom key
        end
      end

      # Label functions (uses Gettext)
      UserStatus.label("active")        # => MyApp.Gettext.gettext("enums.user_status.active")
      UserStatus.label("pending")       # => MyApp.Gettext.gettext("enums.status.waiting")
      UserStatus.labels()               # => %{"active" => "Active", "inactive" => "Inactive", "pending" => "Waiting"}

  ## Configuration Options

  - `:type` - Database storage type (default: `:string`)
  - `:module` - Define enum in separate module (default: `nil`)
  - `:gettext_module` - Gettext module for translations (default: `nil`)
  - `:gettext_domain` - Gettext domain for keys (default: `"default"`)
  """
  @accumulating_attrs [
    :enum_values,
    :enum_gettext_keys
  ]

  @doc false
  defmacro __using__(opts) do
    gettext_module = Keyword.get(opts, :gettext_module, nil)
    gettext_domain = Keyword.get(opts, :gettext_domain, "default")

    imports =
      if gettext_module do
        quote do
          use Gettext, backend: unquote(gettext_module)
        end
      end

    quote do
      import DefEnum, only: [enum: 1, enum: 2]

      @gettext_module unquote(gettext_module)
      @gettext_domain unquote(gettext_domain)

      unquote(imports)
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

      def values do
        @values
      end

      # Fallback for unknown values
      def label(_value), do: nil

      def labels() do
        @enum_values
        |> Enum.map(fn {_key, value} ->
          {value, label(value)}
        end)
        |> Enum.into(%{})
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

      # With custom gettext label key
      value :active, "active", label: "status.is_active"
  """
  defmacro value(name, value \\ nil, opts \\ []) do
    value = value || to_string(name)
    label_key = Keyword.get(opts, :label)

    quote bind_quoted: [name: name, value: value, label_key: label_key] do
      DefEnum.__value__(name, value, __ENV__)
      DefEnum.__label__(name, label_key, __ENV__)

      def unquote(name)(), do: unquote(value)

      # Generate label functions for this specific value
      if Module.get_attribute(__MODULE__, :gettext_module) do
        actual_label_key = label_key || DefEnum.generate_default_key(__MODULE__, name)
        gettext_domain = Module.get_attribute(__MODULE__, :gettext_domain)

        def label(unquote(value)) do
          dgettext(unquote(gettext_domain), unquote(actual_label_key))
        end
      else
        def label(unquote(value)), do: unquote(value)
      end
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

  @doc false
  def __label__(name, label_key, %Macro.Env{module: mod}) when is_atom(name) do
    Module.put_attribute(mod, :enum_gettext_keys, {name, label_key})
  end

  def __label__(name, _label_key, _env) do
    raise ArgumentError, "a enum name must be an atom, got #{inspect(name)}"
  end

  @doc false
  def generate_default_key(module, value) do
    module_name = module |> Module.split() |> List.last() |> Macro.underscore()
    "#{module_name}.#{value}"
  end
end
