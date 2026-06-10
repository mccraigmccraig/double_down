defmodule DoubleDown.DispatchConfigTest do
  use ExUnit.Case, async: false

  alias DoubleDown.Test.ConfigGreeter, as: Contract
  alias DoubleDown.Test.ConfigGreeter.Impl, as: ContractImpl
  alias DoubleDown.Test.ConfigGreeter.Port

  # -- Config dispatch --

  describe "config dispatch" do
    test "dispatches to impl from Application config" do
      Application.put_env(:double_down, Contract, impl: ContractImpl)

      assert "Hello, Charlie!" = Port.greet("Charlie")

      Application.delete_env(:double_down, Contract)
    end
  end

  # -- No handler raises --

  describe "no handler" do
    test "raises when no test handler and no config" do
      Application.delete_env(:double_down, Contract)

      assert_raise RuntimeError, ~r/No test handler set/, fn ->
        Port.greet("Nobody")
      end
    end

    test "raises with test-oriented message mentioning set_stateless_handler" do
      Application.delete_env(:double_down, Contract)

      assert_raise RuntimeError, ~r/set_stateless_handler/, fn ->
        Port.greet("Nobody")
      end
    end

    test "raises when config exists but missing :impl key" do
      Application.put_env(:double_down, Contract, [])

      assert_raise RuntimeError, ~r/No test handler set/, fn ->
        Port.greet("Nobody")
      end

      Application.delete_env(:double_down, Contract)
    end
  end

  # -- test_dispatch? false (ContractFacade-level) --

  describe "test_dispatch? false" do
    test "uses config impl, ignores test handler" do
      Code.compile_string("""
      defmodule DoubleDown.Test.ConfigOnlyPort do
        use DoubleDown.ContractFacade,
          contract: DoubleDown.Test.ConfigGreeter,
          otp_app: :double_down,
          test_dispatch?: false
      end
      """)

      mod = DoubleDown.Test.ConfigOnlyPort

      DoubleDown.Testing.set_stateless_handler(Contract, fn _contract, :greet, [name] ->
        "test-handler: #{name}"
      end)

      Application.put_env(:double_down, Contract, impl: ContractImpl)
      assert "Hello, Alice!" = apply(mod, :greet, ["Alice"])
      Application.delete_env(:double_down, Contract)
    end

    test "uses config impl with fn -> false, ignores test handler" do
      Code.compile_string("""
      defmodule DoubleDown.Test.TestDispatchFnFalse do
        use DoubleDown.ContractFacade,
          contract: DoubleDown.Test.ConfigGreeter,
          otp_app: :double_down,
          test_dispatch?: fn -> false end
      end
      """)

      mod = DoubleDown.Test.TestDispatchFnFalse

      DoubleDown.Testing.set_stateless_handler(Contract, fn _contract, :greet, [name] ->
        "fn-false-handler: #{name}"
      end)

      Application.put_env(:double_down, Contract, impl: ContractImpl)
      assert "Hello, Dave!" = apply(mod, :greet, ["Dave"])
      Application.delete_env(:double_down, Contract)
    end
  end
end
