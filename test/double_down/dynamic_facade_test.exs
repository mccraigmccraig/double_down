defmodule DoubleDown.DynamicFacadeTest do
  use ExUnit.Case, async: true

  alias DoubleDown.Double
  alias DoubleDown.Test.DynamicTarget

  # DynamicTarget is set up in test_helper.exs via Dynamic.setup/1.
  # Original functions: greet/1, add/2, zero_arity/0

  describe "Dynamic.setup?/1" do
    test "returns true for set up modules" do
      assert DoubleDown.DynamicFacade.setup?(DynamicTarget)
    end

    test "returns false for non-set-up modules" do
      refute DoubleDown.DynamicFacade.setup?(String)
    end
  end

  describe "dispatch without handler — falls through to original" do
    test "original functions work when no handler installed" do
      assert "Original: Alice" = DynamicTarget.greet("Alice")
      assert 5 = DynamicTarget.add(2, 3)
      assert :original = DynamicTarget.zero_arity()
    end
  end

  describe "dispatch with Double.fallback" do
    test "fn fallback overrides all operations" do
      Double.fallback(DynamicTarget, fn _contract, operation, args ->
        case {operation, args} do
          {:greet, [name]} -> "Stubbed: #{name}"
          {:add, [a, b]} -> a * b
          {:zero_arity, []} -> :stubbed
        end
      end)

      assert "Stubbed: Alice" = DynamicTarget.greet("Alice")
      assert 6 = DynamicTarget.add(2, 3)
      assert :stubbed = DynamicTarget.zero_arity()
    end
  end

  describe "dispatch with Double.expect" do
    test "expects are consumed in order" do
      Double.fallback(DynamicTarget, fn _contract, :greet, [name] -> "Stub: #{name}" end)

      Double.expect(DynamicTarget, :greet, fn [_] -> "First" end)
      Double.expect(DynamicTarget, :greet, fn [_] -> "Second" end)

      assert "First" = DynamicTarget.greet("Alice")
      assert "Second" = DynamicTarget.greet("Bob")
      assert "Stub: Carol" = DynamicTarget.greet("Carol")

      Double.verify!()
    end
  end

  describe "dispatch with Double.fallback (stateful)" do
    test "stateful fallback handles operations" do
      Double.fallback(
        DynamicTarget,
        fn
          _contract, :greet, [name], state ->
            count = Map.get(state, :greet_count, 0) + 1
            {"Hello #{name} (#{count})", Map.put(state, :greet_count, count)}

          _contract, :add, [a, b], state ->
            {a + b, state}

          _contract, :zero_arity, [], state ->
            {:fake, state}
        end,
        %{}
      )

      assert "Hello Alice (1)" = DynamicTarget.greet("Alice")
      assert "Hello Bob (2)" = DynamicTarget.greet("Bob")
      assert 5 = DynamicTarget.add(2, 3)
      assert :fake = DynamicTarget.zero_arity()
    end

    test "expects layer over stateful fallback" do
      Double.fallback(
        DynamicTarget,
        fn
          _contract, :greet, [name], state -> {"Fake: #{name}", state}
          _contract, :add, [a, b], state -> {a + b, state}
        end,
        %{}
      )

      Double.expect(DynamicTarget, :greet, fn [_] -> "Expected" end)

      # Expect fires first
      assert "Expected" = DynamicTarget.greet("Alice")
      # Falls through to fallback
      assert "Fake: Bob" = DynamicTarget.greet("Bob")

      Double.verify!()
    end
  end

  describe "Double.dynamic/1" do
    test "delegates to original, allows expects on top" do
      DynamicTarget
      |> Double.dynamic()
      |> Double.expect(:greet, fn [_] -> "Overridden" end)

      assert "Overridden" = DynamicTarget.greet("Alice")
      # add falls through to the original via module fake
      assert 5 = DynamicTarget.add(2, 3)
      # second greet falls through to original
      assert "Original: Bob" = DynamicTarget.greet("Bob")

      Double.verify!()
    end

    test "raises for modules not set up with Dynamic.setup" do
      assert_raise ArgumentError, ~r/has not been set up/, fn ->
        Double.dynamic(String)
      end
    end
  end

  describe "dispatch logging" do
    test "logs dispatched calls" do
      Double.fallback(DynamicTarget, fn _contract, :greet, [name] ->
        "Logged: #{name}"
      end)

      DoubleDown.Testing.enable_log(DynamicTarget)

      DynamicTarget.greet("Alice")

      log = DoubleDown.Testing.get_log(DynamicTarget)
      assert [{DynamicTarget, :greet, ["Alice"], "Logged: Alice"}] = log
    end
  end

  describe "passthrough expects" do
    test ":passthrough expect delegates to original" do
      Double.fallback(
        DynamicTarget,
        fn _contract, :greet, [name], state -> {"Fake: #{name}", state} end,
        %{}
      )
      |> Double.expect(:greet, :passthrough)

      # Passthrough delegates to the fake (which is the fallback)
      assert "Fake: Alice" = DynamicTarget.greet("Alice")
      # Second call goes to fake directly
      assert "Fake: Bob" = DynamicTarget.greet("Bob")

      Double.verify!()
    end

    test "Double.passthrough() from stateful responder delegates to fallback" do
      Double.fallback(
        DynamicTarget,
        fn _contract, :greet, [name], state -> {"Fake: #{name}", state} end,
        %{}
      )
      |> Double.expect(:greet, fn [name], _state ->
        if name == "special" do
          {"Special!", %{}}
        else
          Double.passthrough()
        end
      end)

      # "special" is handled by the expect
      assert "Special!" = DynamicTarget.greet("special")
      # "Alice" passes through to the fake
      assert "Fake: Alice" = DynamicTarget.greet("Alice")
    end
  end

  describe "stateful expect responders with dynamic facade" do
    test "2-arity expect reads and updates fallback state" do
      Double.fallback(
        DynamicTarget,
        fn
          _contract, :greet, [name], state -> {"Fake: #{name}", state}
          _contract, :zero_arity, [], state -> {state[:count] || 0, state}
        end,
        %{count: 0}
      )
      |> Double.expect(:greet, fn [name], state ->
        count = (state[:count] || 0) + 1
        {"Counted(#{count}): #{name}", %{state | count: count}}
      end)

      assert "Counted(1): Alice" = DynamicTarget.greet("Alice")
      # State was updated — verify via zero_arity
      assert 1 = DynamicTarget.zero_arity()
    end
  end

  describe "cross-contract state access with dynamic facade" do
    test "4-arity fallback on dynamic module reads contract-based Repo state" do
      alias DoubleDown.Repo
      alias DoubleDown.Test.Repo, as: TestRepo
      alias DoubleDown.Test.SimpleUser

      # Set up Repo with InMemory
      Double.fallback(Repo, Repo.OpenInMemory)

      # Insert a record via Repo
      {:ok, _user} = TestRepo.insert(SimpleUser.changeset(%{name: "Alice"}))

      # Set up dynamic module with 4-arity fallback that reads Repo state
      Double.fallback(
        DynamicTarget,
        fn _contract, :greet, [_name], state, all_states ->
          repo_state = Map.get(all_states, Repo, %{})
          users = repo_state |> Map.get(SimpleUser, %{}) |> Map.values()
          names = Enum.map(users, & &1.name)
          {names, state}
        end,
        %{}
      )

      assert ["Alice"] = DynamicTarget.greet("ignored")
    end
  end

  describe "per-operation stubs with dynamic facade" do
    test "per-op stub overrides specific operation" do
      Double.fallback(DynamicTarget, fn _contract, operation, args ->
        case {operation, args} do
          {:greet, [name]} -> "Fallback: #{name}"
          {:add, [a, b]} -> a + b
          {:zero_arity, []} -> :fallback
        end
      end)
      |> Double.stub(:greet, fn [name] -> "Stubbed: #{name}" end)

      assert "Stubbed: Alice" = DynamicTarget.greet("Alice")
      assert 5 = DynamicTarget.add(2, 3)
    end
  end

  describe "behaviour modules" do
    alias DoubleDown.Test.DynamicBehaviourTarget

    # DynamicBehaviourTarget is set up in test_helper.exs via Dynamic.setup/1.
    # It implements @behaviour DoubleDown.Test.DynamicBehaviour.

    test "@behaviour attribute is preserved on shim" do
      behaviours =
        DynamicBehaviourTarget.module_info(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert DoubleDown.Test.DynamicBehaviour in behaviours
    end

    test "original functions work through shim" do
      assert "Hello, Alice" = DynamicBehaviourTarget.greet("Alice")
      assert "Goodbye, Bob" = DynamicBehaviourTarget.farewell("Bob")
    end

    test "fallback overrides work on behaviour module" do
      Double.fallback(DynamicBehaviourTarget, fn
        _contract, :greet, [name] -> "Fake hello, #{name}"
        _contract, :farewell, [name] -> "Fake bye, #{name}"
      end)

      assert "Fake hello, Alice" = DynamicBehaviourTarget.greet("Alice")
      assert "Fake bye, Bob" = DynamicBehaviourTarget.farewell("Bob")
    end
  end

  describe "macro modules" do
    # DynamicMacroTarget is set up in test_helper.exs via Dynamic.setup/1.
    # It defines: defmacro with_prefix/2 and def greet/1.
    require DoubleDown.Test.DynamicMacroTarget, as: DynamicMacroTarget

    test "macro works through shim" do
      result = DynamicMacroTarget.with_prefix("INFO", do: "hello")
      assert result == "[INFO] hello"
    end

    test "regular functions still work alongside macros" do
      assert "Hello, Alice" = DynamicMacroTarget.greet("Alice")
    end

    test "regular functions can be overridden via fallback" do
      Double.fallback(DynamicMacroTarget, fn
        _contract, :greet, [name] -> "Fake: #{name}"
      end)

      assert "Fake: Alice" = DynamicMacroTarget.greet("Alice")
    end
  end

  describe "struct modules" do
    alias DoubleDown.Test.DynamicStructTarget

    # DynamicStructTarget is set up in test_helper.exs via Dynamic.setup/1.
    # It defines: @enforce_keys [:name], defstruct [:name, age: 0, role: "user"],
    # and greet/1.

    test "__struct__/0 is proxied through shim (no handler)" do
      result = DynamicStructTarget.__struct__()
      assert is_map(result)
      assert result.__struct__ == DynamicStructTarget
      assert result.name == nil
      assert result.age == 0
      assert result.role == "user"
    end

    test "__struct__/1 is proxied through shim (no handler)" do
      result = DynamicStructTarget.__struct__(name: "Alice", age: 30)
      assert is_map(result)
      assert result.__struct__ == DynamicStructTarget
      assert result.name == "Alice"
      assert result.age == 30
      assert result.role == "user"
    end

    test "__info__(:struct) returns correct field metadata" do
      info = DynamicStructTarget.__info__(:struct)
      assert is_list(info)

      fields = Enum.map(info, & &1.field)
      assert :name in fields
      assert :age in fields
      assert :role in fields
    end

    test "@enforce_keys are preserved in shim" do
      assert_raise ArgumentError, ~r/keys must also be given/, fn ->
        DynamicStructTarget.__struct__([])
      end
    end

    test "struct literal syntax works at compile time" do
      s = %DynamicStructTarget{name: "Alice"}
      assert s.name == "Alice"
      assert s.age == 0
      assert s.role == "user"
    end

    test "default values are preserved" do
      s = DynamicStructTarget.__struct__(name: "Alice")
      assert s.age == 0
      assert s.role == "user"
    end

    test "__struct__/0 can be overridden via fallback" do
      Double.fallback(DynamicStructTarget, fn
        _contract, :__struct__, [] ->
          %{__struct__: DynamicStructTarget, name: "Default", age: 0, role: "admin"}

        _contract, :__struct__, [kv] ->
          struct(%{__struct__: DynamicStructTarget, name: "Default", age: 0, role: "admin"}, kv)

        _contract, :greet, [name] ->
          "Fake: #{name}"
      end)

      result = DynamicStructTarget.__struct__()
      assert result.name == "Default"
      assert result.age == 0
      assert result.role == "admin"
    end

    test "__struct__/1 can be overridden via fallback" do
      Double.fallback(DynamicStructTarget, fn
        _contract, :__struct__, [] ->
          %{__struct__: DynamicStructTarget, name: "Default", age: 0, role: "admin"}

        _contract, :__struct__, [kv] ->
          struct(%{__struct__: DynamicStructTarget, name: "Default", age: 0, role: "admin"}, kv)

        _contract, :greet, [name] ->
          "Fake: #{name}"
      end)

      result = DynamicStructTarget.__struct__(name: "Override")
      assert result.name == "Override"
    end

    test "greet/1 still works on struct module" do
      assert "Original: Alice" = DynamicStructTarget.greet("Alice")
    end

    test "Dynamic.dynamic/1 works with struct modules" do
      DynamicStructTarget
      |> Double.dynamic()
      |> Double.expect(:greet, fn [_] -> "Overridden" end)

      assert "Overridden" = DynamicStructTarget.greet("Alice")
      # __struct__ falls through to original
      result = DynamicStructTarget.__struct__()
      assert result.__struct__ == DynamicStructTarget
      # second greet falls through to original
      assert "Original: Bob" = DynamicStructTarget.greet("Bob")

      Double.verify!()
    end
  end

  describe "validation" do
    test "refuses DoubleDown contract modules" do
      assert_raise ArgumentError, ~r/DoubleDown contract/, fn ->
        DoubleDown.DynamicFacade.setup(DoubleDown.Repo)
      end
    end

    test "refuses DoubleDown internal modules" do
      assert_raise ArgumentError, ~r/DoubleDown internal/, fn ->
        DoubleDown.DynamicFacade.setup(DoubleDown.Contract.Dispatch)
      end
    end

    test "refuses NimbleOwnership" do
      assert_raise ArgumentError, ~r/NimbleOwnership/, fn ->
        DoubleDown.DynamicFacade.setup(NimbleOwnership)
      end
    end

    test "refuses Erlang modules" do
      assert_raise ArgumentError, ~r/Erlang/, fn ->
        DoubleDown.DynamicFacade.setup(:erlang)
      end
    end

    test "idempotent — setup twice is safe" do
      assert :ok = DoubleDown.DynamicFacade.setup(DynamicTarget)
    end
  end
end
