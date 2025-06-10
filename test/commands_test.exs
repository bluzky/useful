defmodule CommandsTest do
  use ExUnit.Case, async: true
  alias Commands

  describe "new/0" do
    test "creates empty command chain" do
      cmd = Commands.new()
      assert %Commands{chains: []} = cmd
    end
  end

  describe "chain/3" do
    test "adds 0-arity function to chain" do
      cmd =
        Commands.new()
        |> Commands.chain(:test, fn -> {:ok, "result"} end)

      assert %Commands{chains: [{:test, op}]} = cmd
      assert is_function(op, 0)
    end

    test "adds 1-arity function to chain" do
      cmd =
        Commands.new()
        |> Commands.chain(:test, fn _acc -> {:ok, "result"} end)

      assert %Commands{chains: [{:test, op}]} = cmd
      assert is_function(op, 1)
    end

    test "adds multiple operations in correct order" do
      cmd =
        Commands.new()
        |> Commands.chain(:first, fn -> {:ok, 1} end)
        |> Commands.chain(:second, fn -> {:ok, 2} end)
        |> Commands.chain(:third, fn -> {:ok, 3} end)

      # Operations are stored in reverse order
      assert %Commands{chains: [{:third, _}, {:second, _}, {:first, _}]} = cmd
    end

    test "accepts string keys" do
      cmd =
        Commands.new()
        |> Commands.chain("string_key", fn -> {:ok, "result"} end)

      assert %Commands{chains: [{"string_key", _}]} = cmd
    end

    test "raises error for invalid function arity" do
      assert_raise FunctionClauseError, fn ->
        Commands.new()
        |> Commands.chain(:test, fn _a, _b -> {:ok, "result"} end)
      end
    end
  end

  describe "chain_if/4" do
    test "adds operation when condition is true" do
      cmd =
        Commands.new()
        |> Commands.chain_if(:test, true, fn -> {:ok, "result"} end)

      assert %Commands{chains: [{:test, _}]} = cmd
    end

    test "skips operation when condition is false" do
      cmd =
        Commands.new()
        |> Commands.chain_if(:test, false, fn -> {:ok, "result"} end)

      assert %Commands{chains: []} = cmd
    end
  end

  describe "exec/1" do
    test "executes empty chain successfully" do
      result =
        Commands.new()
        |> Commands.exec()

      assert {:ok, %{}} = result
    end

    test "executes single 0-arity operation" do
      result =
        Commands.new()
        |> Commands.chain(:test, fn -> {:ok, "success"} end)
        |> Commands.exec()

      assert {:ok, %{test: "success"}} = result
    end

    test "executes single 1-arity operation" do
      result =
        Commands.new()
        |> Commands.chain(:test, fn _acc -> {:ok, "success"} end)
        |> Commands.exec()

      assert {:ok, %{test: "success"}} = result
    end

    test "executes multiple operations in correct order" do
      result =
        Commands.new()
        |> Commands.chain(:first, fn -> {:ok, 1} end)
        |> Commands.chain(:second, fn %{first: val} -> {:ok, val + 1} end)
        |> Commands.chain(:third, fn %{first: a, second: b} -> {:ok, a + b} end)
        |> Commands.exec()

      assert {:ok, %{first: 1, second: 2, third: 3}} = result
    end

    test "stops execution on first error from 0-arity function" do
      result =
        Commands.new()
        |> Commands.chain(:success, fn -> {:ok, "good"} end)
        |> Commands.chain(:failure, fn -> {:error, "bad"} end)
        |> Commands.chain(:never_called, fn -> {:ok, "never"} end)
        |> Commands.exec()

      assert {:error, :failure, "bad", %{success: "good"}} = result
    end

    test "stops execution on first error from 1-arity function" do
      result =
        Commands.new()
        |> Commands.chain(:success, fn -> {:ok, "good"} end)
        |> Commands.chain(:failure, fn _acc -> {:error, "bad"} end)
        |> Commands.chain(:never_called, fn _acc -> {:ok, "never"} end)
        |> Commands.exec()

      assert {:error, :failure, "bad", %{success: "good"}} = result
    end

    test "error on first operation returns empty accumulator" do
      result =
        Commands.new()
        |> Commands.chain(:immediate_failure, fn -> {:error, "failed"} end)
        |> Commands.chain(:never_called, fn -> {:ok, "never"} end)
        |> Commands.exec()

      assert {:error, :immediate_failure, "failed", %{}} = result
    end

    test "accumulates results correctly" do
      result =
        Commands.new()
        |> Commands.chain(:step1, fn -> {:ok, %{id: 1, name: "user"}} end)
        |> Commands.chain(:step2, fn %{step1: user} ->
          {:ok, %{user_id: user.id, title: "post"}}
        end)
        |> Commands.chain(:step3, fn acc ->
          {:ok, "User #{acc.step1.name} created post #{acc.step2.title}"}
        end)
        |> Commands.exec()

      expected = %{
        step1: %{id: 1, name: "user"},
        step2: %{user_id: 1, title: "post"},
        step3: "User user created post post"
      }

      assert {:ok, ^expected} = result
    end

    test "handles complex error scenarios with partial rollback data" do
      result =
        Commands.new()
        |> Commands.chain(:create_user, fn -> {:ok, %{id: 1, name: "John"}} end)
        |> Commands.chain(:create_profile, fn %{create_user: user} ->
          {:ok, %{user_id: user.id, bio: "Developer"}}
        end)
        |> Commands.chain(:send_email, fn _acc -> {:error, "SMTP server down"} end)
        |> Commands.chain(:log_activity, fn _acc -> {:ok, "logged"} end)
        |> Commands.exec()

      assert {:error, :send_email, "SMTP server down", partial_results} = result
      assert %{create_user: %{id: 1, name: "John"}} = partial_results
      assert %{create_profile: %{user_id: 1, bio: "Developer"}} = partial_results
      refute Map.has_key?(partial_results, :log_activity)
    end

    test "works with different result types" do
      result =
        Commands.new()
        |> Commands.chain(:string, fn -> {:ok, "text"} end)
        |> Commands.chain(:number, fn -> {:ok, 42} end)
        |> Commands.chain(:list, fn -> {:ok, [1, 2, 3]} end)
        |> Commands.chain(:map, fn -> {:ok, %{key: "value"}} end)
        |> Commands.chain(:atom, fn -> {:ok, :success} end)
        |> Commands.exec()

      expected = %{
        string: "text",
        number: 42,
        list: [1, 2, 3],
        map: %{key: "value"},
        atom: :success
      }

      assert {:ok, ^expected} = result
    end

    test "handles nil results" do
      result =
        Commands.new()
        |> Commands.chain(:nil_result, fn -> {:ok, nil} end)
        |> Commands.chain(:use_nil, fn %{nil_result: nil_val} ->
          {:ok, "got #{inspect(nil_val)}"}
        end)
        |> Commands.exec()

      assert {:ok, %{nil_result: nil, use_nil: "got nil"}} = result
    end
  end

  describe "integration tests" do
    test "realistic user creation workflow" do
      # Simulate successful user creation workflow
      result =
        Commands.new()
        |> Commands.chain(:validate_input, fn ->
          {:ok, %{email: "test@example.com", name: "John"}}
        end)
        |> Commands.chain(:create_user, fn %{validate_input: data} ->
          {:ok, %{id: 123, email: data.email, name: data.name}}
        end)
        |> Commands.chain(:create_profile, fn %{create_user: user} ->
          {:ok, %{user_id: user.id, created_at: ~D[2024-01-01]}}
        end)
        |> Commands.chain(:send_welcome_email, fn %{create_user: user} ->
          {:ok, "Email sent to #{user.email}"}
        end)
        |> Commands.exec()

      assert {:ok, results} = result
      assert %{id: 123, email: "test@example.com", name: "John"} = results.create_user
      assert %{user_id: 123} = results.create_profile
      assert "Email sent to test@example.com" = results.send_welcome_email
    end

    test "realistic workflow with failure and rollback data" do
      # Simulate workflow where email sending fails
      result =
        Commands.new()
        |> Commands.chain(:create_user, fn ->
          {:ok, %{id: 456, email: "test@example.com"}}
        end)
        |> Commands.chain(:charge_credit_card, fn %{create_user: user} ->
          {:ok, %{charge_id: "ch_123", user_id: user.id, amount: 1000}}
        end)
        |> Commands.chain(:send_receipt, fn _acc ->
          {:error, "Email service unavailable"}
        end)
        |> Commands.exec()

      assert {:error, :send_receipt, "Email service unavailable", rollback_data} = result

      # We have the data needed to rollback the charge and delete the user
      assert %{id: 456} = rollback_data.create_user
      assert %{charge_id: "ch_123", amount: 1000} = rollback_data.charge_credit_card
    end

    test "conditional operations based on data" do
      # Test with premium user
      result_premium =
        Commands.new()
        |> Commands.chain(:get_user, fn -> {:ok, %{id: 1, premium: true}} end)
        |> Commands.chain_if(:premium_feature, true, fn %{get_user: user} ->
          {:ok, "Premium feature enabled for user #{user.id}"}
        end)
        |> Commands.exec()

      assert {:ok, %{premium_feature: "Premium feature enabled for user 1"}} = result_premium

      # Test with regular user
      result_regular =
        Commands.new()
        |> Commands.chain(:get_user, fn -> {:ok, %{id: 2, premium: false}} end)
        |> Commands.chain_if(:premium_feature, false, fn %{get_user: user} ->
          {:ok, "Premium feature enabled for user #{user.id}"}
        end)
        |> Commands.exec()

      assert {:ok, %{get_user: %{id: 2, premium: false}}} = result_regular
      refute Map.has_key?(result_regular |> elem(1), :premium_feature)
    end
  end
end
