defmodule HexPort.HandlerTest do
  use ExUnit.Case, async: true

  alias HexPort.Handler
  alias HexPort.Test.Greeter
  alias HexPort.Test.Counter

  # ── Builder tests ─────────────────────────────────────────

  describe "new/0" do
    test "returns empty accumulator" do
      acc = Handler.new()
      assert %Handler{contracts: %{}} = acc
    end
  end

  describe "expect/5" do
    test "appends to per-operation queue" do
      fun1 = fn [_] -> :first end
      fun2 = fn [_] -> :second end

      acc =
        Handler.new()
        |> Handler.expect(Greeter, :greet, fun1)
        |> Handler.expect(Greeter, :greet, fun2)

      assert [^fun1, ^fun2] = acc.contracts[Greeter].expects[:greet]
    end

    test "with times: n enqueues n copies" do
      fun = fn [_] -> :ok end

      acc = Handler.expect(Greeter, :greet, fun, times: 3)

      assert length(acc.contracts[Greeter].expects[:greet]) == 3
      assert Enum.all?(acc.contracts[Greeter].expects[:greet], &(&1 == fun))
    end

    test "times: 0 raises" do
      assert_raise ArgumentError, ~r/times must be >= 1/, fn ->
        Handler.expect(Greeter, :greet, fn [_] -> :ok end, times: 0)
      end
    end

    test "default first arg starts with new()" do
      acc = Handler.expect(Greeter, :greet, fn [_] -> :ok end)
      assert %Handler{} = acc
      assert Map.has_key?(acc.contracts, Greeter)
    end

    test "multiple operations on same contract" do
      acc =
        Handler.expect(Greeter, :greet, fn [_] -> "hi" end)
        |> Handler.expect(Greeter, :fetch_greeting, fn [_] -> {:ok, "hi"} end)

      assert Map.has_key?(acc.contracts[Greeter].expects, :greet)
      assert Map.has_key?(acc.contracts[Greeter].expects, :fetch_greeting)
    end

    test "multi-contract accumulation" do
      acc =
        Handler.expect(Greeter, :greet, fn [_] -> "hi" end)
        |> Handler.expect(Counter, :increment, fn [_] -> 1 end)

      assert Map.has_key?(acc.contracts, Greeter)
      assert Map.has_key?(acc.contracts, Counter)
    end
  end

  describe "stub/4" do
    test "sets stub function" do
      fun = fn [_] -> "stubbed" end

      acc = Handler.stub(Greeter, :greet, fun)

      assert acc.contracts[Greeter].stubs[:greet] == fun
    end

    test "replacing stub overwrites previous" do
      fun1 = fn [_] -> "first" end
      fun2 = fn [_] -> "second" end

      acc =
        Handler.stub(Greeter, :greet, fun1)
        |> Handler.stub(Greeter, :greet, fun2)

      assert acc.contracts[Greeter].stubs[:greet] == fun2
    end

    test "default first arg starts with new()" do
      acc = Handler.stub(Greeter, :greet, fn [_] -> :ok end)
      assert %Handler{} = acc
      assert Map.has_key?(acc.contracts, Greeter)
    end

    test "expect and stub coexist for same operation" do
      acc =
        Handler.expect(Greeter, :greet, fn [_] -> "expected" end)
        |> Handler.stub(Greeter, :greet, fn [_] -> "stubbed" end)

      assert length(acc.contracts[Greeter].expects[:greet]) == 1
      assert acc.contracts[Greeter].stubs[:greet] != nil
    end
  end

  # ── install! tests ────────────────────────────────────────

  describe "install!/1" do
    test "raises on empty accumulator" do
      assert_raise ArgumentError, ~r/no expectations or stubs/, fn ->
        Handler.install!(Handler.new())
      end
    end

    test "returns :ok on success" do
      result =
        Handler.stub(Greeter, :greet, fn [_] -> "hi" end)
        |> Handler.install!()

      assert result == :ok
    end
  end

  # ── Dispatch tests ────────────────────────────────────────

  describe "dispatch with expects" do
    test "expectations consumed in order" do
      Handler.expect(Greeter, :greet, fn [_] -> "first" end)
      |> Handler.expect(Greeter, :greet, fn [_] -> "second" end)
      |> Handler.install!()

      assert "first" = Greeter.Port.greet("Alice")
      assert "second" = Greeter.Port.greet("Bob")
    end

    test "times: n consumed across n calls" do
      Handler.expect(Greeter, :greet, fn [name] -> "hi #{name}" end, times: 3)
      |> Handler.install!()

      assert "hi A" = Greeter.Port.greet("A")
      assert "hi B" = Greeter.Port.greet("B")
      assert "hi C" = Greeter.Port.greet("C")
    end

    test "exhausted expects with no stub raises" do
      Handler.expect(Greeter, :greet, fn [_] -> "once" end)
      |> Handler.install!()

      # First call succeeds
      assert "once" = Greeter.Port.greet("Alice")

      # Second call raises — no expects left, no stub
      assert_raise RuntimeError, ~r/Unexpected call to.*greet/, fn ->
        Greeter.Port.greet("Bob")
      end
    end
  end

  describe "dispatch with stubs" do
    test "stub called any number of times" do
      Handler.stub(Greeter, :greet, fn [name] -> "stub: #{name}" end)
      |> Handler.install!()

      assert "stub: A" = Greeter.Port.greet("A")
      assert "stub: B" = Greeter.Port.greet("B")
      assert "stub: C" = Greeter.Port.greet("C")
    end

    test "stub called zero times is valid" do
      Handler.stub(Greeter, :greet, fn [_] -> "never called" end)
      |> Handler.install!()

      # Don't call it — verify should still pass
      assert :ok = Handler.verify!()
    end
  end

  describe "dispatch with expects + stubs" do
    test "expects consumed first, then stub takes over" do
      Handler.expect(Greeter, :greet, fn [_] -> "expected-1" end)
      |> Handler.expect(Greeter, :greet, fn [_] -> "expected-2" end)
      |> Handler.stub(Greeter, :greet, fn [name] -> "stub: #{name}" end)
      |> Handler.install!()

      assert "expected-1" = Greeter.Port.greet("A")
      assert "expected-2" = Greeter.Port.greet("B")
      assert "stub: C" = Greeter.Port.greet("C")
      assert "stub: D" = Greeter.Port.greet("D")
    end
  end

  describe "dispatch with unexpected operations" do
    test "operation with no expect or stub raises" do
      Handler.stub(Greeter, :greet, fn [_] -> "hi" end)
      |> Handler.install!()

      # fetch_greeting has no expect or stub
      assert_raise RuntimeError, ~r/Unexpected call to.*fetch_greeting/, fn ->
        Greeter.Port.fetch_greeting("Alice")
      end
    end

    test "error message includes remaining expectations" do
      Handler.expect(Greeter, :greet, fn [_] -> "hi" end)
      |> Handler.install!()

      # Call an operation that's not expected (fetch_greeting)
      # while greet still has expectations remaining
      error =
        assert_raise RuntimeError, fn ->
          Greeter.Port.fetch_greeting("Alice")
        end

      assert error.message =~ "greet"
      assert error.message =~ "1 expected call(s) remaining"
    end
  end

  describe "multi-contract dispatch" do
    test "each contract gets independent handler" do
      Handler.expect(Greeter, :greet, fn [name] -> "greet: #{name}" end)
      |> Handler.expect(Counter, :increment, fn [n] -> n * 10 end)
      |> Handler.stub(Counter, :get_count, fn [] -> 99 end)
      |> Handler.install!()

      assert "greet: Alice" = Greeter.Port.greet("Alice")
      assert 50 = Counter.Port.increment(5)
      assert 99 = Counter.Port.get_count()
    end
  end

  # ── verify! tests ─────────────────────────────────────────

  describe "verify!/0" do
    test "passes when all expects consumed" do
      Handler.expect(Greeter, :greet, fn [_] -> "hi" end)
      |> Handler.install!()

      Greeter.Port.greet("Alice")

      assert :ok = Handler.verify!()
    end

    test "raises when expects remain" do
      Handler.expect(Greeter, :greet, fn [_] -> "hi" end, times: 2)
      |> Handler.install!()

      # Only consume one
      Greeter.Port.greet("Alice")

      assert_raise RuntimeError, ~r/expectations not fulfilled/, fn ->
        Handler.verify!()
      end
    end

    test "error message lists contract, operation, and count" do
      Handler.expect(Greeter, :greet, fn [_] -> "hi" end, times: 3)
      |> Handler.install!()

      Greeter.Port.greet("Alice")

      error =
        assert_raise RuntimeError, fn ->
          Handler.verify!()
        end

      assert error.message =~ inspect(Greeter)
      assert error.message =~ "greet"
      assert error.message =~ "2 expected call(s) not made"
    end

    test "ignores stubs (zero calls OK)" do
      Handler.stub(Greeter, :greet, fn [_] -> "never" end)
      |> Handler.stub(Counter, :get_count, fn [] -> 0 end)
      |> Handler.install!()

      assert :ok = Handler.verify!()
    end

    test "works across multiple contracts" do
      Handler.expect(Greeter, :greet, fn [_] -> "hi" end)
      |> Handler.expect(Counter, :increment, fn [_] -> 1 end)
      |> Handler.install!()

      Greeter.Port.greet("Alice")
      Counter.Port.increment(1)

      assert :ok = Handler.verify!()
    end

    test "reports unconsumed expects across multiple contracts" do
      Handler.expect(Greeter, :greet, fn [_] -> "hi" end)
      |> Handler.expect(Counter, :increment, fn [_] -> 1 end)
      |> Handler.install!()

      # Only consume Greeter, not Counter
      Greeter.Port.greet("Alice")

      error =
        assert_raise RuntimeError, fn ->
          Handler.verify!()
        end

      assert error.message =~ inspect(Counter)
      assert error.message =~ "increment"
    end

    test "raises when called with no install" do
      assert_raise RuntimeError, ~r/no handlers were installed/, fn ->
        Handler.verify!()
      end
    end
  end

  # ── Integration tests ─────────────────────────────────────

  describe "full pipeline" do
    test "expect → stub → install! → dispatch → verify!" do
      Handler.expect(Greeter, :greet, fn [name] -> "expected: #{name}" end)
      |> Handler.stub(Greeter, :fetch_greeting, fn [name] -> {:ok, "stub: #{name}"} end)
      |> Handler.install!()

      assert "expected: Alice" = Greeter.Port.greet("Alice")
      assert {:ok, "stub: Bob"} = Greeter.Port.fetch_greeting("Bob")
      assert {:ok, "stub: Carol"} = Greeter.Port.fetch_greeting("Carol")

      assert :ok = Handler.verify!()
    end

    test "sequenced expectations with different return values" do
      Handler.expect(Greeter, :fetch_greeting, fn [_] -> {:error, :not_found} end)
      |> Handler.expect(Greeter, :fetch_greeting, fn [name] -> {:ok, "Hello, #{name}!"} end)
      |> Handler.install!()

      assert {:error, :not_found} = Greeter.Port.fetch_greeting("Alice")
      assert {:ok, "Hello, Bob!"} = Greeter.Port.fetch_greeting("Bob")

      assert :ok = Handler.verify!()
    end

    test "times option with dispatch and verify" do
      Handler.expect(Counter, :increment, fn [n] -> n end, times: 3)
      |> Handler.stub(Counter, :get_count, fn [] -> 0 end)
      |> Handler.install!()

      Counter.Port.increment(1)
      Counter.Port.increment(2)
      Counter.Port.increment(3)
      Counter.Port.get_count()

      assert :ok = Handler.verify!()
    end

    test "mix of expects and stubs on same operation" do
      Handler.expect(Greeter, :greet, fn [_] -> "first call" end)
      |> Handler.expect(Greeter, :greet, fn [_] -> "second call" end)
      |> Handler.stub(Greeter, :greet, fn [name] -> "stub: #{name}" end)
      |> Handler.install!()

      assert "first call" = Greeter.Port.greet("A")
      assert "second call" = Greeter.Port.greet("B")
      assert "stub: C" = Greeter.Port.greet("C")
      assert "stub: D" = Greeter.Port.greet("D")
      assert "stub: E" = Greeter.Port.greet("E")

      assert :ok = Handler.verify!()
    end
  end
end
