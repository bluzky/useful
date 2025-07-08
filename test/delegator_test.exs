defmodule DelegatorTest do
  use ExUnit.Case

  describe "delegate_all/2 with only option" do
    test "delegates only specified functions" do
      defmodule Base1 do
        def hello(name) do
          "hello #{name}"
        end

        def bye() do
          "bye"
        end
      end

      defmodule Delegate1 do
        use Delegator
        delegate_all(Base1, only: [hello: 1])
      end

      assert Delegate1.hello("Jon") == "hello Jon"
      assert_raise UndefinedFunctionError, fn -> Delegate1.bye() end
    end
  end

  describe "delegate_all/2 with except option" do
    test "delegates all functions except specified ones" do
      defmodule Base2 do
        def hello(name) do
          "hello #{name}"
        end

        def bye() do
          "bye"
        end
      end

      defmodule Delegate2 do
        use Delegator
        delegate_all(Base2, except: [bye: 0])
      end

      assert Delegate2.hello("Jon") == "hello Jon"
      assert_raise UndefinedFunctionError, fn -> Delegate2.bye() end
    end
  end

  describe "delegate_all/2" do
    test "delegates all functions" do
      defmodule Base3 do
        def hello(name) do
          "hello #{name}"
        end

        def bye() do
          "bye"
        end
      end

      defmodule Delegate3 do
        use Delegator
        delegate_all(Base3)
      end

      assert Delegate3.hello("Jon") == "hello Jon"
      assert Delegate3.bye() == "bye"
    end
  end
end
