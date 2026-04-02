defmodule HexPort.TestingTest do
  use ExUnit.Case, async: true

  alias HexPort.Test.Greeter
  alias HexPort.Test.Counter

  # ── Handler registration API ──────────────────────────────

  describe "set_handler/2" do
    test "returns :ok" do
      assert :ok = HexPort.Testing.set_handler(Greeter, Greeter.Impl)
    end

    test "registered module handler is used by dispatch" do
      HexPort.Testing.set_handler(Greeter, Greeter.Impl)
      assert "Hello, Alice!" = Greeter.Port.greet("Alice")
    end
  end

  describe "set_fn_handler/2" do
    test "returns :ok" do
      assert :ok =
               HexPort.Testing.set_fn_handler(Greeter, fn
                 :greet, [name] -> "fn: #{name}"
               end)
    end

    test "registered fn handler is used by dispatch" do
      HexPort.Testing.set_fn_handler(Greeter, fn
        :greet, [name] -> "fn: #{name}"
      end)

      assert "fn: Bob" = Greeter.Port.greet("Bob")
    end

    test "rejects non-arity-2 function" do
      assert_raise FunctionClauseError, fn ->
        HexPort.Testing.set_fn_handler(Greeter, fn _ -> :bad end)
      end
    end
  end

  describe "set_stateful_handler/3" do
    test "returns :ok" do
      assert :ok =
               HexPort.Testing.set_stateful_handler(
                 Counter,
                 fn :increment, [n], state -> {state + n, state + n} end,
                 0
               )
    end

    test "initial state is available on first dispatch" do
      HexPort.Testing.set_stateful_handler(
        Counter,
        fn
          :get_count, [], state -> {state, state}
        end,
        42
      )

      assert 42 = Counter.Port.get_count()
    end

    test "state persists across dispatches" do
      HexPort.Testing.set_stateful_handler(
        Counter,
        fn
          :increment, [n], state -> {state + n, state + n}
          :get_count, [], state -> {state, state}
        end,
        0
      )

      Counter.Port.increment(10)
      Counter.Port.increment(5)
      assert 15 = Counter.Port.get_count()
    end

    test "rejects non-arity-3 function" do
      assert_raise FunctionClauseError, fn ->
        HexPort.Testing.set_stateful_handler(Counter, fn _, _ -> {:ok, 0} end, 0)
      end
    end
  end

  # ── Handler replacement ───────────────────────────────────

  describe "handler replacement" do
    test "setting a new handler overwrites the previous one" do
      HexPort.Testing.set_fn_handler(Greeter, fn
        :greet, [name] -> "first: #{name}"
      end)

      assert "first: X" = Greeter.Port.greet("X")

      HexPort.Testing.set_fn_handler(Greeter, fn
        :greet, [name] -> "second: #{name}"
      end)

      assert "second: X" = Greeter.Port.greet("X")
    end

    test "replacing fn handler with module handler" do
      HexPort.Testing.set_fn_handler(Greeter, fn
        :greet, [name] -> "fn: #{name}"
      end)

      assert "fn: X" = Greeter.Port.greet("X")

      HexPort.Testing.set_handler(Greeter, Greeter.Impl)
      assert "Hello, X!" = Greeter.Port.greet("X")
    end

    test "replacing module handler with stateful handler" do
      HexPort.Testing.set_handler(Counter, Greeter.Impl)

      HexPort.Testing.set_stateful_handler(
        Counter,
        fn
          :increment, [n], state -> {state + n, state + n}
          :get_count, [], state -> {state, state}
        end,
        100
      )

      assert 105 = Counter.Port.increment(5)
    end
  end

  # ── reset/0 ───────────────────────────────────────────────

  describe "reset/0" do
    test "returns :ok" do
      HexPort.Testing.set_fn_handler(Greeter, fn :greet, [_] -> "x" end)
      assert :ok = HexPort.Testing.reset()
    end

    test "clears handlers so dispatch falls through to config" do
      HexPort.Testing.set_fn_handler(Greeter, fn :greet, [_] -> "test" end)
      assert "test" = Greeter.Port.greet("X")

      HexPort.Testing.reset()

      # No handler, no config → raises
      assert_raise RuntimeError, ~r/No implementation configured/, fn ->
        Greeter.Port.greet("X")
      end
    end

    test "clears log" do
      HexPort.Testing.set_fn_handler(Greeter, fn :greet, [name] -> name end)
      HexPort.Testing.enable_log(Greeter)
      Greeter.Port.greet("X")
      assert length(HexPort.Testing.get_log(Greeter)) == 1

      HexPort.Testing.reset()
      assert [] = HexPort.Testing.get_log(Greeter)
    end

    test "clears stateful handler state" do
      HexPort.Testing.set_stateful_handler(
        Counter,
        fn
          :increment, [n], s -> {s + n, s + n}
          :get_count, [], s -> {s, s}
        end,
        0
      )

      Counter.Port.increment(50)
      assert 50 = Counter.Port.get_count()

      HexPort.Testing.reset()

      # Re-register with fresh state
      HexPort.Testing.set_stateful_handler(
        Counter,
        fn
          :get_count, [], s -> {s, s}
        end,
        0
      )

      assert 0 = Counter.Port.get_count()
    end
  end

  # ── Dispatch logging ──────────────────────────────────────

  describe "enable_log/1" do
    test "returns :ok" do
      assert :ok = HexPort.Testing.enable_log(Greeter)
    end

    test "can be called before or after setting handler" do
      # Enable log first, then set handler
      HexPort.Testing.enable_log(Greeter)

      HexPort.Testing.set_fn_handler(Greeter, fn
        :greet, [name] -> "hi #{name}"
      end)

      Greeter.Port.greet("test")
      log = HexPort.Testing.get_log(Greeter)
      assert [{Greeter, :greet, ["test"], "hi test"}] = log
    end
  end

  describe "get_log/1" do
    test "returns empty list when logging not enabled" do
      assert [] = HexPort.Testing.get_log(Greeter)
    end

    test "returns empty list when logging enabled but no dispatches" do
      HexPort.Testing.enable_log(Greeter)
      assert [] = HexPort.Testing.get_log(Greeter)
    end

    test "returns entries in dispatch order" do
      HexPort.Testing.set_fn_handler(Greeter, fn
        :greet, [name] -> "hi #{name}"
        :fetch_greeting, [name] -> {:ok, "hi #{name}"}
      end)

      HexPort.Testing.enable_log(Greeter)

      Greeter.Port.greet("first")
      Greeter.Port.fetch_greeting("second")
      Greeter.Port.greet("third")

      log = HexPort.Testing.get_log(Greeter)
      assert length(log) == 3

      assert [
               {Greeter, :greet, ["first"], _},
               {Greeter, :fetch_greeting, ["second"], _},
               {Greeter, :greet, ["third"], _}
             ] = log
    end

    test "log entries include result" do
      HexPort.Testing.set_fn_handler(Greeter, fn
        :greet, [name] -> "result: #{name}"
      end)

      HexPort.Testing.enable_log(Greeter)
      Greeter.Port.greet("check")

      [{_, _, _, result}] = HexPort.Testing.get_log(Greeter)
      assert result == "result: check"
    end

    test "logs are per-contract" do
      HexPort.Testing.set_fn_handler(Greeter, fn :greet, [n] -> n end)

      HexPort.Testing.set_stateful_handler(
        Counter,
        fn :increment, [n], s -> {s + n, s + n} end,
        0
      )

      HexPort.Testing.enable_log(Greeter)
      HexPort.Testing.enable_log(Counter)

      Greeter.Port.greet("a")
      Counter.Port.increment(1)
      Greeter.Port.greet("b")

      greeter_log = HexPort.Testing.get_log(Greeter)
      counter_log = HexPort.Testing.get_log(Counter)

      assert length(greeter_log) == 2
      assert length(counter_log) == 1
    end
  end

  # ── Async isolation ───────────────────────────────────────

  describe "async isolation" do
    test "handlers are isolated per process" do
      HexPort.Testing.set_fn_handler(Greeter, fn
        :greet, [name] -> "parent: #{name}"
      end)

      parent_result = Greeter.Port.greet("test")
      assert parent_result == "parent: test"

      # An unrelated process (not Task.async which sets $callers) cannot dispatch
      test_pid = self()

      spawn(fn ->
        result =
          try do
            Greeter.Port.greet("child")
          rescue
            e -> {:error, e}
          end

        send(test_pid, {:child_result, result})
      end)

      assert_receive {:child_result, {:error, %RuntimeError{}}}, 1000
    end

    test "different processes can have different handlers for the same contract" do
      HexPort.Testing.set_fn_handler(Greeter, fn
        :greet, [name] -> "process-1: #{name}"
      end)

      # Spawn a second process with a different handler
      test_pid = self()

      spawn(fn ->
        HexPort.Testing.set_fn_handler(Greeter, fn
          :greet, [name] -> "process-2: #{name}"
        end)

        result = Greeter.Port.greet("test")
        send(test_pid, {:process_2_result, result})
      end)

      assert "process-1: test" = Greeter.Port.greet("test")

      assert_receive {:process_2_result, "process-2: test"}, 1000
    end

    test "logs are isolated per process" do
      HexPort.Testing.set_fn_handler(Greeter, fn :greet, [n] -> n end)
      HexPort.Testing.enable_log(Greeter)
      Greeter.Port.greet("parent")

      test_pid = self()

      spawn(fn ->
        HexPort.Testing.set_fn_handler(Greeter, fn :greet, [n] -> n end)
        HexPort.Testing.enable_log(Greeter)
        Greeter.Port.greet("child")
        send(test_pid, {:child_log, HexPort.Testing.get_log(Greeter)})
      end)

      parent_log = HexPort.Testing.get_log(Greeter)
      assert length(parent_log) == 1
      assert [{_, :greet, ["parent"], _}] = parent_log

      assert_receive {:child_log, child_log}, 1000
      assert length(child_log) == 1
      assert [{_, :greet, ["child"], _}] = child_log
    end
  end

  # ── Allow / process propagation ───────────────────────────

  describe "allow/3" do
    test "returns :ok for valid allow" do
      HexPort.Testing.set_fn_handler(Greeter, fn :greet, [n] -> n end)

      task = Task.async(fn -> receive do: (:go -> Greeter.Port.greet("x")) end)

      assert :ok = HexPort.Testing.allow(Greeter, self(), task.pid)

      send(task.pid, :go)
      assert "x" = Task.await(task)
    end

    test "allowed process shares handler with owner" do
      HexPort.Testing.set_fn_handler(Greeter, fn
        :greet, [name] -> "shared: #{name}"
      end)

      task = Task.async(fn -> receive do: (:go -> Greeter.Port.greet("child")) end)
      HexPort.Testing.allow(Greeter, self(), task.pid)

      send(task.pid, :go)
      assert "shared: child" = Task.await(task)
    end

    test "allowed process shares stateful handler state" do
      HexPort.Testing.set_stateful_handler(
        Counter,
        fn
          :increment, [n], s -> {s + n, s + n}
          :get_count, [], s -> {s, s}
        end,
        0
      )

      Counter.Port.increment(10)

      task =
        Task.async(fn ->
          receive do
            :go -> Counter.Port.increment(5)
          end
        end)

      HexPort.Testing.allow(Counter, self(), task.pid)
      send(task.pid, :go)
      assert 15 = Task.await(task)

      # Parent sees the updated state
      assert 15 = Counter.Port.get_count()
    end

    test "allowed process logs are visible to owner" do
      HexPort.Testing.set_fn_handler(Greeter, fn :greet, [n] -> n end)
      HexPort.Testing.enable_log(Greeter)

      Greeter.Port.greet("parent")

      task =
        Task.async(fn ->
          receive do
            :go -> Greeter.Port.greet("child")
          end
        end)

      HexPort.Testing.allow(Greeter, self(), task.pid)
      send(task.pid, :go)
      Task.await(task)

      log = HexPort.Testing.get_log(Greeter)
      assert length(log) == 2
      operations = Enum.map(log, fn {_, _, args, _} -> args end)
      assert ["parent"] in operations
      assert ["child"] in operations
    end

    test "allow with lazy pid function" do
      HexPort.Testing.set_fn_handler(Greeter, fn :greet, [n] -> "lazy: #{n}" end)

      # Use a lazy function that returns the pid
      {:ok, agent} = Agent.start_link(fn -> nil end)

      HexPort.Testing.allow(Greeter, self(), fn -> agent end)

      # Agent should be able to dispatch through the handler via its GenServer process
      result =
        Agent.get(agent, fn _ ->
          Greeter.Port.greet("agent")
        end)

      assert "lazy: agent" = result

      Agent.stop(agent)
    end
  end

  # ── Multiple contracts in same test ───────────────────────

  describe "multiple contracts" do
    test "can register handlers for multiple contracts independently" do
      HexPort.Testing.set_fn_handler(Greeter, fn :greet, [n] -> "greet: #{n}" end)

      HexPort.Testing.set_stateful_handler(
        Counter,
        fn :get_count, [], s -> {s, s} end,
        99
      )

      assert "greet: X" = Greeter.Port.greet("X")
      assert 99 = Counter.Port.get_count()
    end

    test "resetting clears all contracts for the current process" do
      HexPort.Testing.set_fn_handler(Greeter, fn :greet, [_] -> "x" end)

      HexPort.Testing.set_stateful_handler(
        Counter,
        fn :get_count, [], s -> {s, s} end,
        0
      )

      HexPort.Testing.reset()

      assert_raise RuntimeError, ~r/No implementation/, fn -> Greeter.Port.greet("X") end
      assert_raise RuntimeError, ~r/No implementation/, fn -> Counter.Port.get_count() end
    end
  end
end
