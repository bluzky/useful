# pipeline_test.exs

defmodule PipelineTest do
  use ExUnit.Case
  doctest Pipeline

  test "creates an empty pipeline" do
    pipeline = Pipeline.new()
    assert pipeline.steps == []
  end

  test "creates a pipeline from a list of steps" do
    steps = [
      {"a", fn _ -> {:ok, 1} end},
      {"b", fn input -> {:ok, input["a"] + 2} end}
    ]

    pipeline = Pipeline.new(steps)
    assert length(pipeline.steps) == 2
    assert Enum.map(pipeline.steps, &elem(&1, 0)) == ["a", "b"]
  end

  test "adds a step to the pipeline" do
    pipeline =
      Pipeline.new()
      |> Pipeline.add("a", fn _ -> {:ok, 1} end)

    assert Enum.map(pipeline.steps, &elem(&1, 0)) == ["a"]
  end

  test "raises when adding a step with duplicate key" do
    pipeline =
      Pipeline.new()
      |> Pipeline.add("a", fn _ -> {:ok, 1} end)

    assert_raise ArgumentError, ~r/Step with key "a" already exists/, fn ->
      Pipeline.add(pipeline, "a", fn _ -> {:ok, 2} end)
    end
  end

  test "conditionally adds a step with boolean" do
    pipeline =
      Pipeline.new()
      |> Pipeline.add_if(true, "a", fn _ -> {:ok, 1} end)
      |> Pipeline.add_if(false, "b", fn _ -> {:ok, 2} end)

    assert Enum.map(pipeline.steps, &elem(&1, 0)) == ["a"]
  end

  test "conditionally adds a step with function and acc" do
    acc = %{"a" => 5}

    pipeline =
      Pipeline.new()
      |> Pipeline.add("a", fn _ -> {:ok, 5} end)
      |> Pipeline.add_if(
        fn acc -> acc["a"] > 3 end,
        "b",
        fn input -> {:ok, input["a"] * 2} end,
        acc
      )
      |> Pipeline.add_if(fn acc -> acc["a"] < 3 end, "c", fn _ -> {:ok, :should_not_run} end, acc)

    assert Enum.map(pipeline.steps, &elem(&1, 0)) == ["a", "b"]
  end

  test "runs pipeline and accumulates results" do
    pipeline =
      Pipeline.new()
      |> Pipeline.add("a", fn _ -> {:ok, 1} end)
      |> Pipeline.add("b", fn input -> {:ok, input["a"] + 2} end)
      |> Pipeline.add("c", fn input -> {:ok, input["a"] * input["b"]} end)

    assert Pipeline.run(pipeline) == {:ok, %{"a" => 1, "b" => 3, "c" => 3}}
  end

  test "runs pipeline with initial input" do
    pipeline =
      Pipeline.new()
      |> Pipeline.add("b", fn input -> {:ok, input["a"] + 2} end)

    assert Pipeline.run(pipeline, %{"a" => 10}) == {:ok, %{"a" => 10, "b" => 12}}
  end

  test "halts pipeline on error and returns partial result" do
    pipeline =
      Pipeline.new()
      |> Pipeline.add("a", fn _ -> {:ok, 1} end)
      |> Pipeline.add("b", fn _ -> {:error, "fail"} end)
      |> Pipeline.add("c", fn _ -> {:ok, :should_not_run} end)

    assert Pipeline.run(pipeline) == {:error, "b", "fail", %{"a" => 1}}
  end

  test "step can return :ok to ignore result" do
    pipeline =
      Pipeline.new()
      |> Pipeline.add("a", fn _ -> {:ok, 1} end)
      |> Pipeline.add("b", fn _ -> :ok end)
      |> Pipeline.add("c", fn input -> {:ok, input["a"] + 10} end)

    assert Pipeline.run(pipeline) == {:ok, %{"a" => 1, "c" => 11}}
  end

  test "complex pipeline with mixed step types and conditions" do
    acc = %{"a" => 2}

    pipeline =
      Pipeline.new()
      |> Pipeline.add("a", fn _ -> {:ok, 2} end)
      |> Pipeline.add_if(
        fn acc -> acc["a"] > 1 end,
        "b",
        fn input -> {:ok, input["a"] * 3} end,
        acc
      )
      |> Pipeline.add("c", fn input -> if input["b"], do: {:ok, input["b"] + 1}, else: :ok end)
      |> Pipeline.add("d", fn _ -> :ok end)
      |> Pipeline.add("e", fn input -> {:ok, (input["c"] || 0) + 5} end)

    assert Pipeline.run(pipeline) == {:ok, %{"a" => 2, "b" => 6, "c" => 7, "e" => 12}}
  end
end
