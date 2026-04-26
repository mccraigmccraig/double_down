defmodule DoubleDown.Contract.DispatchTest do
  use ExUnit.Case, async: true

  alias DoubleDown.Test.Greeter
  alias DoubleDown.Test.Counter

  # -- Module handler dispatch --

  describe "module handler" do
    test "dispatches to a module implementing the behaviour" do
      DoubleDown.Testing.set_module_handler(Greeter, Greeter.Impl)

      assert "Hello, Alice!" = Greeter.Port.greet("Alice")
    end

    test "dispatches fetch_greeting with ok tuple" do
      DoubleDown.Testing.set_module_handler(Greeter, Greeter.Impl)

      assert {:ok, "Hello, Bob!"} = Greeter.Port.fetch_greeting("Bob")
    end
  end

  # -- Fn handler dispatch --

  describe "fn handler" do
    test "dispatches to a function handler" do
      DoubleDown.Testing.set_stateless_handler(Greeter, fn _contract, operation, args ->
        case {operation, args} do
          {:greet, [name]} -> "Howdy, #{name}!"
          {:fetch_greeting, [name]} -> {:ok, "Howdy, #{name}!"}
        end
      end)

      assert "Howdy, Alice!" = Greeter.Port.greet("Alice")
      assert {:ok, "Howdy, Bob!"} = Greeter.Port.fetch_greeting("Bob")
    end
  end

  # -- Stateful handler dispatch --

  describe "stateful handler" do
    test "threads state across dispatches" do
      DoubleDown.Testing.set_stateful_handler(
        Counter,
        fn
          _contract, :increment, [amount], count -> {count + amount, count + amount}
          _contract, :get_count, [], count -> {count, count}
        end,
        0
      )

      assert 5 = Counter.Port.increment(5)
      assert 8 = Counter.Port.increment(3)
      assert 8 = Counter.Port.get_count()
    end
  end

  # -- Config dispatch --

  describe "config dispatch" do
    test "dispatches to impl from Application config" do
      Application.put_env(:double_down, Greeter, impl: Greeter.Impl)
      on_exit(fn -> Application.delete_env(:double_down, Greeter) end)

      # No test handler set — should fall through to config
      assert "Hello, Charlie!" = Greeter.Port.greet("Charlie")
    end
  end

  # -- No handler raises --

  describe "no handler" do
    test "raises when no test handler and no config" do
      # Ensure no config
      Application.delete_env(:double_down, Greeter)

      assert_raise RuntimeError, ~r/No test handler set/, fn ->
        Greeter.Port.greet("Nobody")
      end
    end

    test "raises with test-oriented message mentioning set_stateless_handler" do
      Application.delete_env(:double_down, Greeter)

      assert_raise RuntimeError, ~r/set_stateless_handler/, fn ->
        Greeter.Port.greet("Nobody")
      end
    end

    test "raises when config exists but missing :impl key" do
      Application.put_env(:double_down, Greeter, [])
      on_exit(fn -> Application.delete_env(:double_down, Greeter) end)

      assert_raise RuntimeError, ~r/No test handler set/, fn ->
        Greeter.Port.greet("Nobody")
      end
    end
  end

  # -- Dispatch logging --

  describe "dispatch logging" do
    test "logs dispatches when logging is enabled" do
      DoubleDown.Testing.set_stateless_handler(Greeter, fn _contract, operation, args ->
        case {operation, args} do
          {:greet, [name]} -> "Hi, #{name}!"
          {:fetch_greeting, [name]} -> {:ok, "Hi, #{name}!"}
        end
      end)

      DoubleDown.Testing.enable_log(Greeter)

      Greeter.Port.greet("Alice")
      Greeter.Port.fetch_greeting("Bob")

      log = DoubleDown.Testing.get_log(Greeter)

      assert [
               {Greeter, :greet, ["Alice"], "Hi, Alice!"},
               {Greeter, :fetch_greeting, ["Bob"], {:ok, "Hi, Bob!"}}
             ] = log
    end

    test "returns empty log when logging not enabled" do
      DoubleDown.Testing.set_stateless_handler(Greeter, fn
        _contract, :greet, [name] -> "Hi, #{name}!"
      end)

      Greeter.Port.greet("Alice")

      assert [] = DoubleDown.Testing.get_log(Greeter)
    end

    test "logs stateful handler dispatches" do
      DoubleDown.Testing.set_stateful_handler(
        Counter,
        fn
          _contract, :increment, [amount], count -> {count + amount, count + amount}
          _contract, :get_count, [], count -> {count, count}
        end,
        0
      )

      DoubleDown.Testing.enable_log(Counter)

      Counter.Port.increment(10)
      Counter.Port.get_count()

      log = DoubleDown.Testing.get_log(Counter)

      assert [
               {Counter, :increment, [10], 10},
               {Counter, :get_count, [], 10}
             ] = log
    end
  end

  # -- Key normalization --

  describe "key/3" do
    test "builds a canonical key" do
      assert {Greeter, :greet, ["Alice"]} =
               DoubleDown.Contract.Dispatch.key(Greeter, :greet, ["Alice"])
    end

    test "normalizes map argument order" do
      key1 = DoubleDown.Contract.Dispatch.key(Greeter, :greet, [%{b: 2, a: 1}])
      key2 = DoubleDown.Contract.Dispatch.key(Greeter, :greet, [%{a: 1, b: 2}])
      assert key1 == key2
    end

    test "normalizes keyword list order" do
      key1 = DoubleDown.Contract.Dispatch.key(Greeter, :greet, [[b: 2, a: 1]])
      key2 = DoubleDown.Contract.Dispatch.key(Greeter, :greet, [[a: 1, b: 2]])
      assert key1 == key2
    end
  end

  # -- Allow child processes --

  describe "allow/3" do
    test "allows a child Task to use the parent's handler" do
      DoubleDown.Testing.set_stateless_handler(Greeter, fn
        _contract, :greet, [name] -> "Hello from parent, #{name}!"
      end)

      task =
        Task.async(fn ->
          Greeter.Port.greet("Child")
        end)

      DoubleDown.Testing.allow(Greeter, self(), task.pid)

      assert "Hello from parent, Child!" = Task.await(task)
    end

    test "allowed child process can use stateful handler" do
      DoubleDown.Testing.set_stateful_handler(
        Counter,
        fn
          _contract, :increment, [amount], count -> {count + amount, count + amount}
          _contract, :get_count, [], count -> {count, count}
        end,
        0
      )

      Counter.Port.increment(5)

      task =
        Task.async(fn ->
          Counter.Port.increment(3)
        end)

      DoubleDown.Testing.allow(Counter, self(), task.pid)

      assert 8 = Task.await(task)
      assert 8 = Counter.Port.get_count()
    end
  end

  # -- handler_active?/1 --

  describe "handler_active?/1" do
    test "returns false when no handler is installed" do
      refute DoubleDown.Contract.Dispatch.handler_active?(Greeter)
    end

    test "returns true after a fn handler is installed" do
      DoubleDown.Testing.set_stateless_handler(Greeter, fn
        _contract, :greet, [name] -> "Hi, #{name}!"
      end)

      assert DoubleDown.Contract.Dispatch.handler_active?(Greeter)
    end

    test "returns true after Double.fallback/2 is called" do
      DoubleDown.Double.fallback(Greeter, Greeter.Impl)

      assert DoubleDown.Contract.Dispatch.handler_active?(Greeter)
    end

    test "respects $callers chain — handler visible in spawned child" do
      DoubleDown.Testing.set_stateless_handler(Greeter, fn
        _contract, :greet, [name] -> "Hi, #{name}!"
      end)

      # Task.async sets $callers to [self()], so the child can see
      # the parent's handler via resolve_test_handler's callers walk.
      result =
        Task.async(fn ->
          DoubleDown.Contract.Dispatch.handler_active?(Greeter)
        end)
        |> Task.await()

      assert result == true
    end

    test "returns false for a different contract with no handler" do
      DoubleDown.Testing.set_stateless_handler(Greeter, fn
        _contract, :greet, [name] -> "Hi, #{name}!"
      end)

      # Greeter has a handler, but Counter does not
      assert DoubleDown.Contract.Dispatch.handler_active?(Greeter)
      refute DoubleDown.Contract.Dispatch.handler_active?(Counter)
    end
  end

  # -- get_state --

  describe "get_state" do
    test "returns nil when no handler installed" do
      assert DoubleDown.Contract.Dispatch.get_state(Greeter) == nil
    end

    test "returns state from current process" do
      DoubleDown.Double.fallback(DoubleDown.Repo, DoubleDown.Repo.InMemory)
      state = DoubleDown.Contract.Dispatch.get_state(DoubleDown.Repo)
      assert is_map(state)
    end

    test "returns state from child process via $callers chain" do
      DoubleDown.Double.fallback(DoubleDown.Repo, DoubleDown.Repo.InMemory)

      parent_state = DoubleDown.Contract.Dispatch.get_state(DoubleDown.Repo)

      child_state =
        Task.async(fn ->
          DoubleDown.Contract.Dispatch.get_state(DoubleDown.Repo)
        end)
        |> Task.await()

      assert child_state == parent_state
    end
  end

  # ── Stateful handler exception safety ──────────────────────

  describe "stateful handler exceptions don't crash the ownership server" do
    test "raise inside stateful handler is transported to calling process" do
      handler = fn _contract, :greet, [_name], state ->
        raise RuntimeError, "boom from handler"
        {nil, state}
      end

      DoubleDown.Testing.set_stateful_handler(Greeter, handler, %{})

      assert_raise RuntimeError, ~r/boom from handler/, fn ->
        Greeter.Port.greet("Alice")
      end

      # Ownership server is still alive — reset and reinstall works
      DoubleDown.Testing.reset()

      DoubleDown.Testing.set_stateless_handler(Greeter, fn _contract, :greet, [name] ->
        "Hello #{name}"
      end)

      assert "Hello Bob" = Greeter.Port.greet("Bob")
    end

    test "throw inside stateful handler is transported to calling process" do
      handler = fn _contract, :greet, [_name], state ->
        throw(:boom_throw)
        {nil, state}
      end

      DoubleDown.Testing.set_stateful_handler(Greeter, handler, %{})

      assert catch_throw(Greeter.Port.greet("Alice")) == :boom_throw

      # Ownership server is still alive — reset and reinstall works
      DoubleDown.Testing.reset()

      DoubleDown.Testing.set_stateless_handler(Greeter, fn _contract, :greet, [name] ->
        "Hello #{name}"
      end)

      assert "Hello Bob" = Greeter.Port.greet("Bob")
    end

    test "exit inside stateful handler is transported to calling process" do
      handler = fn _contract, :greet, [_name], state ->
        exit(:boom_exit)
        {nil, state}
      end

      DoubleDown.Testing.set_stateful_handler(Greeter, handler, %{})

      assert catch_exit(Greeter.Port.greet("Alice")) == :boom_exit

      # Ownership server is still alive — reset and reinstall works
      DoubleDown.Testing.reset()

      DoubleDown.Testing.set_stateless_handler(Greeter, fn _contract, :greet, [name] ->
        "Hello #{name}"
      end)

      assert "Hello Bob" = Greeter.Port.greet("Bob")
    end
  end

  # ── 5-arity stateful handlers (global state access) ────────

  describe "5-arity stateful handlers" do
    alias DoubleDown.Test.Counter

    test "5-arity handler receives global state snapshot" do
      DoubleDown.Testing.set_stateful_handler(
        Greeter,
        fn _contract, :greet, [name], state -> {"Hello #{name}", state} end,
        %{greeter: true}
      )

      DoubleDown.Testing.set_stateful_handler(
        Counter,
        fn _contract, :get_count, [], state, all_states ->
          greeter_state = Map.get(all_states, Greeter)
          {greeter_state, state}
        end,
        %{counter: true}
      )

      result = Counter.Port.get_count()
      assert result == %{greeter: true}
    end

    test "global state contains sentinel key" do
      DoubleDown.Testing.set_stateful_handler(
        Greeter,
        fn _contract, :greet, [_name], _state, all_states ->
          {all_states, %{}}
        end,
        %{}
      )

      result = Greeter.Port.greet("Alice")
      assert Map.has_key?(result, DoubleDown.Contract.GlobalState)
      assert result[DoubleDown.Contract.GlobalState] == true
    end

    test "global state includes this contract's own state" do
      DoubleDown.Testing.set_stateful_handler(
        Greeter,
        fn _contract, :greet, [_name], _state, all_states ->
          {Map.get(all_states, Greeter), %{}}
        end,
        %{my_data: 42}
      )

      assert %{my_data: 42} = Greeter.Port.greet("Alice")
    end

    test "4-arity handlers still work unchanged" do
      DoubleDown.Testing.set_stateful_handler(
        Greeter,
        fn _contract, :greet, [name], state ->
          {"Hello #{name}", Map.put(state, :called, true)}
        end,
        %{}
      )

      assert "Hello Alice" = Greeter.Port.greet("Alice")
    end

    test "raises when handler returns global state map (sentinel detection)" do
      DoubleDown.Testing.set_stateful_handler(
        Greeter,
        fn _contract, :greet, [_name], _state, all_states ->
          {"oops", all_states}
        end,
        %{}
      )

      assert_raise ArgumentError, ~r/returned the global state map/, fn ->
        Greeter.Port.greet("Alice")
      end
    end

    test "cross-contract state read: handler reads another contract's state" do
      alias DoubleDown.Repo
      alias DoubleDown.Test.Repo, as: TestRepo
      alias DoubleDown.Test.SimpleUser

      DoubleDown.Testing.set_stateful_handler(
        Repo,
        &Repo.OpenInMemory.dispatch/4,
        Repo.OpenInMemory.new()
      )

      {:ok, _user} = TestRepo.insert(SimpleUser.changeset(%{name: "Alice"}))

      DoubleDown.Testing.set_stateful_handler(
        Greeter,
        fn _contract, :greet, [_name], state, all_states ->
          repo_state = Map.get(all_states, Repo, %{})
          users = repo_state |> Map.get(SimpleUser, %{}) |> Map.values()
          {users, state}
        end,
        %{}
      )

      users = Greeter.Port.greet("ignored")
      assert [%SimpleUser{name: "Alice"}] = users
    end
  end
end
