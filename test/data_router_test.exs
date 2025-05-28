defmodule DataRouterTest do
  use ExUnit.Case
  doctest DataRouter

  describe "match_route/2" do
    test "returns first matching queue" do
      routes = %{
        "user_queue" => %{type: "user"},
        "admin_queue" => %{type: "admin"}
      }

      assert DataRouter.match_route(routes, %{type: "user"}) == {:ok, "user_queue"}
      assert DataRouter.match_route(routes, %{type: "admin"}) == {:ok, "admin_queue"}
    end

    test "matches subset patterns" do
      routes = %{
        "basic_user" => %{type: "user"},
        "admin_user" => %{type: "user", role: "admin"}
      }

      # Data with extra fields matches basic pattern
      assert DataRouter.match_route(routes, %{type: "user", name: "john"}) == {:ok, "basic_user"}

      # More specific data might match either pattern (depends on enumeration order)
      result = DataRouter.match_route(routes, %{type: "user", role: "admin"})

      assert result in [
               {:ok, "basic_user"},
               {:ok, "admin_user"}
             ]
    end

    test "returns not_found when no patterns match" do
      routes = %{
        "user_queue" => %{type: "user"},
        "admin_queue" => %{type: "admin"}
      }

      assert DataRouter.match_route(routes, %{type: "guest"}) == {:error, "not_found"}
      assert DataRouter.match_route(routes, %{name: "john"}) == {:error, "not_found"}
    end

    test "handles empty routes" do
      assert DataRouter.match_route(%{}, %{type: "user"}) == {:error, "not_found"}
    end

    test "works with DataMatcher quantifiers" do
      routes = %{
        "js_queue" => %{skills: DataMatcher.any("javascript")},
        "elixir_queue" => %{skills: DataMatcher.any("elixir")}
      }

      assert DataRouter.match_route(routes, %{skills: ["javascript", "react"]}) ==
               {:ok, "js_queue"}

      assert DataRouter.match_route(routes, %{skills: ["elixir", "phoenix"]}) ==
               {:ok, "elixir_queue"}

      assert DataRouter.match_route(routes, %{skills: ["python"]}) == {:error, "not_found"}
    end

    test "returns error for invalid routes" do
      assert DataRouter.match_route("not a map", %{type: "user"}) == {:error, "invalid_routes"}
      assert DataRouter.match_route(nil, %{type: "user"}) == {:error, "invalid_routes"}
    end

    test "handles various data gracefully" do
      routes = %{"test_queue" => %{type: "user"}}

      assert DataRouter.match_route(routes, "string") == {:error, "not_found"}
      assert DataRouter.match_route(routes, 123) == {:error, "not_found"}
      assert DataRouter.match_route(routes, nil) == {:error, "not_found"}
    end
  end
end
