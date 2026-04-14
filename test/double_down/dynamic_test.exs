defmodule DoubleDown.DynamicTest do
  use ExUnit.Case, async: true

  alias DoubleDown.Double
  alias DoubleDown.Test.DynamicTarget

  # DynamicTarget is set up in test_helper.exs via Dynamic.setup/1.
  # Original functions: greet/1, add/2, zero_arity/0

  describe "Dynamic.setup?/1" do
    test "returns true for set up modules" do
      assert DoubleDown.Dynamic.setup?(DynamicTarget)
    end

    test "returns false for non-set-up modules" do
      refute DoubleDown.Dynamic.setup?(String)
    end
  end

  describe "dispatch without handler — falls through to original" do
    test "original functions work when no handler installed" do
      assert "Original: Alice" = DynamicTarget.greet("Alice")
      assert 5 = DynamicTarget.add(2, 3)
      assert :original = DynamicTarget.zero_arity()
    end
  end

  describe "dispatch with Double.stub" do
    test "fn stub overrides all operations" do
      Double.stub(DynamicTarget, fn
        :greet, [name] -> "Stubbed: #{name}"
        :add, [a, b] -> a * b
        :zero_arity, [] -> :stubbed
      end)

      assert "Stubbed: Alice" = DynamicTarget.greet("Alice")
      assert 6 = DynamicTarget.add(2, 3)
      assert :stubbed = DynamicTarget.zero_arity()
    end
  end

  describe "dispatch with Double.expect" do
    test "expects are consumed in order" do
      Double.stub(DynamicTarget, fn :greet, [name] -> "Stub: #{name}" end)

      Double.expect(DynamicTarget, :greet, fn [_] -> "First" end)
      Double.expect(DynamicTarget, :greet, fn [_] -> "Second" end)

      assert "First" = DynamicTarget.greet("Alice")
      assert "Second" = DynamicTarget.greet("Bob")
      assert "Stub: Carol" = DynamicTarget.greet("Carol")

      Double.verify!()
    end
  end

  describe "dispatch with Double.fake (stateful)" do
    test "stateful fake handles operations" do
      Double.fake(
        DynamicTarget,
        fn
          :greet, [name], state ->
            count = Map.get(state, :greet_count, 0) + 1
            {"Hello #{name} (#{count})", Map.put(state, :greet_count, count)}

          :add, [a, b], state ->
            {a + b, state}

          :zero_arity, [], state ->
            {:fake, state}
        end,
        %{}
      )

      assert "Hello Alice (1)" = DynamicTarget.greet("Alice")
      assert "Hello Bob (2)" = DynamicTarget.greet("Bob")
      assert 5 = DynamicTarget.add(2, 3)
      assert :fake = DynamicTarget.zero_arity()
    end

    test "expects layer over stateful fake" do
      Double.fake(
        DynamicTarget,
        fn
          :greet, [name], state -> {"Fake: #{name}", state}
          :add, [a, b], state -> {a + b, state}
        end,
        %{}
      )

      Double.expect(DynamicTarget, :greet, fn [_] -> "Expected" end)

      # Expect fires first
      assert "Expected" = DynamicTarget.greet("Alice")
      # Falls through to fake
      assert "Fake: Bob" = DynamicTarget.greet("Bob")

      Double.verify!()
    end
  end

  describe "dispatch with module fake (Mimic-style)" do
    test "module fake delegates unhandled operations" do
      # Use the original module as a module fake — override one operation
      Double.fake(DynamicTarget, DoubleDown.Dynamic.original_module(DynamicTarget))
      Double.expect(DynamicTarget, :greet, fn [_] -> "Overridden" end)

      assert "Overridden" = DynamicTarget.greet("Alice")
      # add falls through to the original via module fake
      assert 5 = DynamicTarget.add(2, 3)

      Double.verify!()
    end
  end

  describe "dispatch logging" do
    test "logs dispatched calls" do
      Double.stub(DynamicTarget, fn
        :greet, [name] -> "Logged: #{name}"
      end)

      DoubleDown.Testing.enable_log(DynamicTarget)

      DynamicTarget.greet("Alice")

      log = DoubleDown.Testing.get_log(DynamicTarget)
      assert [{DynamicTarget, :greet, ["Alice"], "Logged: Alice"}] = log
    end
  end

  describe "validation" do
    test "refuses DoubleDown contract modules" do
      assert_raise ArgumentError, ~r/DoubleDown contract/, fn ->
        DoubleDown.Dynamic.setup(DoubleDown.Repo)
      end
    end

    test "refuses DoubleDown internal modules" do
      assert_raise ArgumentError, ~r/DoubleDown internal/, fn ->
        DoubleDown.Dynamic.setup(DoubleDown.Dispatch)
      end
    end

    test "refuses NimbleOwnership" do
      assert_raise ArgumentError, ~r/NimbleOwnership/, fn ->
        DoubleDown.Dynamic.setup(NimbleOwnership)
      end
    end

    test "refuses Erlang modules" do
      assert_raise ArgumentError, ~r/Erlang/, fn ->
        DoubleDown.Dynamic.setup(:erlang)
      end
    end

    test "idempotent — setup twice is safe" do
      assert :ok = DoubleDown.Dynamic.setup(DynamicTarget)
    end
  end
end
