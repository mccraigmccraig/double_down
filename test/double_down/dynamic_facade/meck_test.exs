defmodule DoubleDown.DynamicFacade.MeckTest do
  use ExUnit.Case, async: false

  alias DoubleDown.DynamicFacade.Meck
  alias DoubleDown.Test.DynamicTarget
  alias DoubleDown.Test.MeckTarget

  describe "install/0" do
    test "returns :ok and marks :meck as guarded" do
      assert :ok = Meck.install()
      assert function_exported?(:meck, :__dd_meck_guard__, 0)
    end

    test "is idempotent" do
      assert :ok = Meck.install()
      assert :ok = Meck.install()
      assert function_exported?(:meck, :__dd_meck_guard__, 0)
    end
  end

  describe "__guard__/1" do
    test "raises for a registered DynamicFacade module (atom)" do
      message = ~r/cannot mock.*#{inspect(DynamicTarget)}/

      assert_raise ArgumentError, message, fn ->
        Meck.__guard__(DynamicTarget)
      end
    end

    test "raises for a list containing a registered DynamicFacade" do
      message = ~r/cannot mock.*#{inspect(DynamicTarget)}/

      assert_raise ArgumentError, message, fn ->
        Meck.__guard__([DynamicTarget, MeckTarget])
      end
    end

    test "does not raise for a non-registered module" do
      assert :ok = Meck.__guard__(MeckTarget)
    end

    test "does not raise for an empty list" do
      assert :ok = Meck.__guard__([])
    end
  end

  describe "guarded :meck.new/1,2" do
    test "refuses to mock a registered DynamicFacade via new/1" do
      message = ~r/cannot mock.*#{inspect(DynamicTarget)}/

      assert_raise ArgumentError, message, fn ->
        :meck.new(DynamicTarget)
      end
    end

    test "refuses to mock a list containing a registered DynamicFacade via new/1" do
      message = ~r/cannot mock.*#{inspect(DynamicTarget)}/

      assert_raise ArgumentError, message, fn ->
        :meck.new([DynamicTarget, MeckTarget])
      end
    end

    test "refuses a registered DynamicFacade with opts via new/2" do
      message = ~r/cannot mock.*#{inspect(DynamicTarget)}/

      assert_raise ArgumentError, message, fn ->
        :meck.new(DynamicTarget, [:passthrough])
      end
    end
  end
end
