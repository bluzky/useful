defmodule PingEndpoint do
  @moduledoc """
  Dummy endpoint to check if service deploy success or not
  """
  use Plug.Router
  plug(Plug.Logger)
  plug(:match)
  plug(:dispatch)

  def child_spec() do
    Plug.Cowboy.child_spec(
      scheme: :http,
      plug: PingEndpoint,
      options: [port: get_port("PORT", 4014)]
    )
  end

  def get_port(key, default) do
    if value = System.get_env(key) do
      case Integer.parse(value) do
        {number, _} -> number
        _ -> default
      end
    else
      default
    end
  end

  # A simple route to test that the server is up
  # Note, all routes must return a connection as per the Plug spec.
  get "/ping" do
    send_resp(conn, 200, "pong")
  end
end
