defmodule DefConfig do
  @moduledoc """
  This module define macro to define configuration with type and default value

  ## How to use
  1. Import this module in your module
  2. Use `def_config` macro to define configuration

  ```elixir
  defmodule MyConfig do
    use DefConfig

    def_config "timeout", type: :integer, default: 1000
    def_config "api_key", type: :string
    def_config "site_config", type: %{
        title: [type: :string],
        logo: [type: :string, default: "http://image.com/logo.png"]
      }
  end

  # cast to db value
  {:ok, value} = MyConfig.cast_config("timeout", "1500")

  # load from db value
  {:ok, value} = MyConfig.load_config("timeout", "1000")
  ```
  """

  # these are extra attributes that will be ignored when casting config
  @extra_attrs [:app]

  @doc false
  defmacro __using__(opts) do
    app = opts[:app]

    if is_nil(app) do
      raise "App is required"
    end

    quote do
      import DefConfig, only: [def_config: 2]
      Module.register_attribute(__MODULE__, :configs, accumulate: true)
      @before_compile DefConfig
      @app unquote(to_string(app))
    end
  end

  @doc """
  Define configuration with type and default value

  ## Parameters
  - `config_key`: key of configuration

  ## Options
  - `code`: code of configuration, default is value of `config_key`
  - other options are taken from Tarams schema

  ## Example
  ```elixir
  def_config :system_timeout, type: :integer, default: 1000
  ```

  This will define 3 functions:
  - `system_timeout/0`: return value of `system_timeout`
  - `default_config("system_timeout")`: return value of `default_value`
  - `type("sytem_timeout")`: return value of `config_type`

  Example with option `code`:
  ```elixir
  def_config "timeout", type: :integer, default: 1000, code: :my_timeout
  ```
  This will define 3 functions:
  - `timeout/0`: return value of `my_timeout`
  - `default_config("timeout")`: return value of `default_value`
  - `type("timeout")`: return value of `config_type`

  In case of duplicated key, it will raise `ArgumentError`.
  """
  defmacro def_config(config_key, definition) do
    {code, definition} = Keyword.pop(definition, :code)
    doc = Keyword.get(definition, :doc)
    definition = Macro.escape(definition)
    code = to_string(code || config_key)

    # force document
    if doc in [nil, ""] do
      raise "Document for `#{code}` is missing"
    end

    quote bind_quoted: [
            code: code,
            key: config_key,
            definition: definition
          ],
          location: :keep do
      duplicated =
        __MODULE__
        |> Module.get_attribute(:configs)
        |> Enum.any?(fn {k, _} -> k == code end)

      if duplicated do
        raise ArgumentError, "config #{inspect(code)} is already defined"
      end

      definition = Keyword.put_new(definition, :app, Module.get_attribute(__MODULE__, :app))

      Module.put_attribute(__MODULE__, :configs, {code, definition})

      def unquote(key)() do
        unquote(code)
      end

      def definition(unquote(code)) do
        unquote(definition)
      end
    end
  end

  # define function to return all configs and default configs
  defmacro __before_compile__(_env) do
    quote do
      # dumb definition
      def definition(_), do: nil

      def __attr__(:app), do: @app

      @doc """
      Decode input string and load to config schema
      """
      # get default value if config value is nil
      def load_config(code, nil), do: {:ok, default_config(code)}
      def load_config(code, ""), do: {:ok, default_config(code)}

      def load_config(code, input) do
        DefConfig.cast_value(definition(code), input)
      end

      def default_config(code) do
        DefConfig.default_value(definition(code))
      end

      @doc """
      Return all config. Each item is a tuple of {code, definition}
      """
      def configs do
        @configs
      end

      @doc """
      Return map of default config of all config key
      """
      def default_configs() do
        @configs
        |> Enum.map(fn {code, _} ->
          {code, default_config(code)}
        end)
        |> Enum.into(%{})
      end
    end
  end

  def default_value([{:type, %{}} | _] = definition) do
    Keyword.get(definition, :default) || cast_value!(definition, %{})
  end

  def default_value(definition) do
    Keyword.get(definition, :default)
  end

  @doc """
  Cast value from input
  """
  def cast_value(definition, input) do
    definition = scrub_definition(definition)

    Skema.cast(%{data: input}, %{data: definition})
    |> case do
      {:ok, output} -> {:ok, output[:data]}
      {:error, %{changes: %{data: error}}} -> {:error, error}
      {:error, %{errors: [data: {message, _}]}} -> {:error, message}
    end
  end

  def cast_value!(definition, input) do
    case cast_value(definition, input) do
      {:ok, value} -> value
      {:error, _} -> raise "Invalid value for #{inspect(definition)}"
    end
  end

  # remove extra attributes
  defp scrub_definition(definition) do
    Enum.reject(definition, fn {key, _} -> key in @extra_attrs end)
  end
end
