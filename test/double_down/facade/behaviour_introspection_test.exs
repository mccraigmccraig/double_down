defmodule DoubleDown.Facade.BehaviourIntrospectionTest do
  use ExUnit.Case, async: true

  alias DoubleDown.Facade.BehaviourIntrospection

  # A fake env for compile error tests
  defp fake_env do
    %Macro.Env{
      module: __MODULE__,
      file: __ENV__.file,
      line: __ENV__.line
    }
  end

  describe "fetch_operations!/2 with annotated params" do
    test "extracts operations from a simple vanilla behaviour" do
      ops = BehaviourIntrospection.fetch_operations!(DoubleDown.Test.VanillaBehaviour, fake_env())

      assert length(ops) == 3

      op_names = Enum.map(ops, & &1.name) |> Enum.sort()
      assert op_names == [:create_item, :get_item, :list_items]
    end

    test "extracts param names from annotated types" do
      ops = BehaviourIntrospection.fetch_operations!(DoubleDown.Test.VanillaBehaviour, fake_env())

      get_item = Enum.find(ops, &(&1.name == :get_item))
      assert get_item.params == [:id]
      assert get_item.arity == 1

      create_item = Enum.find(ops, &(&1.name == :create_item))
      assert create_item.params == [:attrs, :opts]
      assert create_item.arity == 2
    end

    test "extracts zero-arg callbacks" do
      ops = BehaviourIntrospection.fetch_operations!(DoubleDown.Test.VanillaBehaviour, fake_env())

      list_items = Enum.find(ops, &(&1.name == :list_items))
      assert list_items.params == []
      assert list_items.arity == 0
    end

    test "param_types contain bare types (annotations stripped)" do
      ops = BehaviourIntrospection.fetch_operations!(DoubleDown.Test.VanillaBehaviour, fake_env())

      get_item = Enum.find(ops, &(&1.name == :get_item))
      # Should be String.t() not id :: String.t()
      [param_type] = get_item.param_types
      assert Macro.to_string(param_type) == "String.t()"
    end

    test "return types are preserved" do
      ops = BehaviourIntrospection.fetch_operations!(DoubleDown.Test.VanillaBehaviour, fake_env())

      get_item = Enum.find(ops, &(&1.name == :get_item))
      return_str = Macro.to_string(get_item.return_type)
      assert return_str == "{:ok, map()} | {:error, term()}"

      list_items = Enum.find(ops, &(&1.name == :list_items))
      return_str = Macro.to_string(list_items.return_type)
      assert return_str == "[map()]"
    end
  end

  describe "fetch_operations!/2 with bare (unannotated) params" do
    test "synthesizes param names as arg1, arg2, ..." do
      ops =
        BehaviourIntrospection.fetch_operations!(DoubleDown.Test.BareTypesBehaviour, fake_env())

      fetch = Enum.find(ops, &(&1.name == :fetch))
      assert fetch.params == [:arg1, :arg2]
      assert fetch.arity == 2
    end

    test "preserves bare param types" do
      ops =
        BehaviourIntrospection.fetch_operations!(DoubleDown.Test.BareTypesBehaviour, fake_env())

      fetch = Enum.find(ops, &(&1.name == :fetch))
      type_strings = Enum.map(fetch.param_types, &Macro.to_string/1)
      assert type_strings == ["String.t()", "keyword()"]
    end
  end

  describe "fetch_operations!/2 with when clauses" do
    test "handles specs with bounded type variables" do
      ops =
        BehaviourIntrospection.fetch_operations!(DoubleDown.Test.WhenClauseBehaviour, fake_env())

      transform = Enum.find(ops, &(&1.name == :transform))
      assert transform.params == [:input]
      assert transform.arity == 1
    end

    test "extracts param types from when-clause specs" do
      ops =
        BehaviourIntrospection.fetch_operations!(DoubleDown.Test.WhenClauseBehaviour, fake_env())

      transform = Enum.find(ops, &(&1.name == :transform))
      # The param type is the type variable `input` (not `term()` — that's in the constraint)
      [param_type] = transform.param_types
      assert Macro.to_string(param_type) == "input"
    end
  end

  describe "fetch_operations!/2 with mixed annotated and bare params" do
    test "extracts real names where annotated, synthesizes where bare" do
      ops =
        BehaviourIntrospection.fetch_operations!(DoubleDown.Test.MixedParamsBehaviour, fake_env())

      mixed = Enum.find(ops, &(&1.name == :mixed))
      assert mixed.params == [:name, :arg2, :opts]
      assert mixed.arity == 3
    end
  end

  describe "fetch_operations!/2 with zero-arg-only behaviours" do
    test "handles behaviours with only zero-arg callbacks" do
      ops = BehaviourIntrospection.fetch_operations!(DoubleDown.Test.ZeroArgBehaviour, fake_env())

      assert length(ops) == 2

      ping = Enum.find(ops, &(&1.name == :ping))
      assert ping.params == []
      assert ping.arity == 0
      assert Macro.to_string(ping.return_type) == ":pong"

      health = Enum.find(ops, &(&1.name == :health_check))
      assert health.params == []
      assert health.arity == 0
    end
  end

  describe "fetch_operations!/2 common operation fields" do
    test "pre_dispatch is always nil for vanilla behaviours" do
      ops = BehaviourIntrospection.fetch_operations!(DoubleDown.Test.VanillaBehaviour, fake_env())

      for op <- ops do
        assert op.pre_dispatch == nil
      end
    end

    test "user_doc is always nil for vanilla behaviours" do
      ops = BehaviourIntrospection.fetch_operations!(DoubleDown.Test.VanillaBehaviour, fake_env())

      for op <- ops do
        assert op.user_doc == nil
      end
    end
  end

  describe "fetch_operations!/2 error cases" do
    test "raises for unloaded modules" do
      assert_raise CompileError, ~r/not loaded/, fn ->
        BehaviourIntrospection.fetch_operations!(DoesNotExist.AtAll, fake_env())
      end
    end

    test "raises for modules with no callbacks" do
      assert_raise CompileError, ~r/no @callback declarations/, fn ->
        BehaviourIntrospection.fetch_operations!(DoubleDown.Test.NotABehaviour, fake_env())
      end
    end
  end
end
