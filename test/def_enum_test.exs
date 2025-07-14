defmodule DefEnumTest do
  use ExUnit.Case
  doctest DefEnum

  describe "basic enum functionality" do
    test "generates value functions" do
      assert SimpleStatus.active() == "active"
      assert SimpleStatus.inactive() == "inactive"
      assert SimpleStatus.pending() == "pending"
    end

    test "generates values list" do
      values = SimpleStatus.values()
      assert "active" in values
      assert "inactive" in values
      assert "pending" in values
    end

    test "works with separate module definition" do
      assert WrapperForExternalStatus.ExternalStatus.online() == "online"
      assert WrapperForExternalStatus.ExternalStatus.offline() == "offline"
    end
  end

  describe "Ecto.Type integration" do
    test "implements type behavior" do
      assert SimpleStatus.type() == :string
    end

    test "casts valid values" do
      assert SimpleStatus.cast("active") == {:ok, "active"}
      assert SimpleStatus.cast(:active) == {:ok, "active"}
      assert SimpleStatus.cast("invalid") == :error
    end

    test "loads valid data" do
      assert SimpleStatus.load("active") == {:ok, "active"}
      # load accepts any string
      assert SimpleStatus.load("invalid") == {:ok, "invalid"}
    end

    test "dumps valid values" do
      assert SimpleStatus.dump("active") == {:ok, "active"}
      assert SimpleStatus.dump(:active) == {:ok, "active"}
      assert SimpleStatus.dump({}) == :error
    end
  end

  describe "label functions without Gettext" do
    test "returns enum values as labels" do
      assert SimpleStatus.label("active") == "active"
      assert SimpleStatus.label("inactive") == "inactive"
      assert SimpleStatus.label("pending") == "pending"
    end

    test "returns nil for unknown values" do
      assert SimpleStatus.label("unknown") == nil
    end

    test "returns enum values as labels when no Gettext" do
      assert SimpleStatus.label("active") == "active"
    end

    test "returns all labels" do
      labels = SimpleStatus.labels()
      assert labels["active"] == "active"
      assert labels["inactive"] == "inactive"
      assert labels["pending"] == "pending"
    end
  end

  describe "label functions with Gettext" do
    test "uses gettext for labels" do
      assert UserStatus.label("active") == "Active"
      assert UserStatus.label("inactive") == "Inactive"
    end

    test "uses custom label keys" do
      assert UserStatus.label("pending") == "Waiting"
    end

    test "returns nil for unknown values" do
      assert UserStatus.label("unknown") == nil
    end

    test "returns all labels with gettext" do
      labels = UserStatus.labels()
      assert labels["active"] == "Active"
      assert labels["inactive"] == "Inactive"
      assert labels["pending"] == "Waiting"
    end
  end

  describe "configuration options" do
    test "supports different types" do
      defmodule IntegerEnum do
        use DefEnum

        enum type: :integer do
          value(:first, 1)
          value(:second, 2)
        end
      end

      assert IntegerEnum.type() == :integer
      assert IntegerEnum.cast(1) == {:ok, 1}
      assert IntegerEnum.cast("1") == {:ok, 1}
    end

    test "supports custom gettext domain" do
      assert CustomDomainEnum.label("test") == "Test Label"
    end
  end

  describe "key generation" do
    test "generates default keys from module and value names" do
      key = DefEnum.generate_default_key(DefEnumTest.UserStatus, :active)
      assert key == "user_status.active"
    end

    test "handles nested module names" do
      key = DefEnum.generate_default_key(Some.Nested.ModuleName, :value)
      assert key == "module_name.value"
    end
  end

  describe "error handling" do
    test "raises error for duplicate enum values" do
      assert_raise ArgumentError, ~r/the enum :duplicate is already set/, fn ->
        defmodule DuplicateEnum do
          use DefEnum

          enum do
            value(:duplicate, "first")
            value(:duplicate, "second")
          end
        end
      end
    end

    test "raises error for non-atom enum names" do
      assert_raise ArgumentError, ~r/a enum name must be an atom/, fn ->
        defmodule InvalidEnum do
          use DefEnum

          enum do
            value("invalid", "value")
          end
        end
      end
    end
  end
end
