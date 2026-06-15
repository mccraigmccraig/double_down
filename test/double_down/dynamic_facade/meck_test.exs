defmodule DoubleDown.DynamicFacade.MeckTest do
  use ExUnit.Case, async: false

  alias DoubleDown.DynamicFacade.Meck
  alias DoubleDown.Test.DynamicTarget

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
        Meck.__guard__([DynamicTarget, String])
      end
    end

    test "does not raise for a non-registered module" do
      assert :ok = Meck.__guard__(String)
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
        :meck.new([DynamicTarget, String])
      end
    end

    test "refuses a registered DynamicFacade with opts via new/2" do
      message = ~r/cannot mock.*#{inspect(DynamicTarget)}/

      assert_raise ArgumentError, message, fn ->
        :meck.new(DynamicTarget, [:passthrough])
      end
    end
  end

  describe "passthrough intact" do
    test ":meck.expect, :meck.validate, :meck.called, :meck.unload work for non-facade modules" do
      :meck.new(String, [:passthrough])

      try do
        :meck.expect(String, :reverse, fn _ -> "reversed" end)

        assert "reversed" = String.reverse("hello")
        assert :meck.called(String, :reverse, ["hello"])
        assert :meck.validate(String)
      after
        :meck.unload(String)
      end
    end
  end

  describe "facade survives meck cycle on a different module" do
    test "dynamic facade still dispatches after mocking and unloading an unrelated module" do
      :meck.new(String, [:passthrough])

      try do
        :meck.expect(String, :reverse, fn _ -> "fake" end)
        assert "fake" = String.reverse("hello")
      after
        :meck.unload(String)
      end

      assert "Original: Alice" = DynamicTarget.greet("Alice")
    end
  end
end
