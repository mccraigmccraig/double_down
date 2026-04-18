defmodule DoubleDown.Contract.SpecWarningsTest do
  use ExUnit.Case, async: false

  # async: false because Code.compile_string defines modules globally
  # and we need to control Application.put_env for config-based dispatch.

  # Impl modules are in test/support/spec_warning_impls.ex so they
  # have beam files on disk (required by Code.Typespec.fetch_specs/1).

  describe "spec matching — no error when types match" do
    test "matching param and return types compile without error" do
      Application.put_env(
        :double_down,
        DoubleDown.Test.SpecMatch.Contract,
        impl: DoubleDown.Test.SpecImpl.Matching
      )

      Code.compile_string("""
      defmodule DoubleDown.Test.SpecMatch.Contract do
        use DoubleDown.Contract
        defcallback greet(name :: String.t()) :: {:ok, String.t()} | {:error, term()}
      end

      defmodule DoubleDown.Test.SpecMatch.Facade do
        use DoubleDown.ContractFacade,
          contract: DoubleDown.Test.SpecMatch.Contract,
          otp_app: :double_down,
          test_dispatch?: false,
          static_dispatch?: true
      end
      """)
    after
      Application.delete_env(:double_down, DoubleDown.Test.SpecMatch.Contract)
      purge([DoubleDown.Test.SpecMatch.Contract, DoubleDown.Test.SpecMatch.Facade])
    end
  end

  describe "spec mismatch — compile error by default" do
    test "raises CompileError when param type differs" do
      Application.put_env(
        :double_down,
        DoubleDown.Test.SpecMismatch.Contract,
        impl: DoubleDown.Test.SpecImpl.ParamMismatch
      )

      assert_raise CompileError, ~r/param type mismatch/, fn ->
        Code.compile_string("""
        defmodule DoubleDown.Test.SpecMismatch.Contract do
          use DoubleDown.Contract
          defcallback greet(name :: String.t()) :: {:ok, String.t()} | {:error, term()}
        end

        defmodule DoubleDown.Test.SpecMismatch.Facade do
          use DoubleDown.ContractFacade,
            contract: DoubleDown.Test.SpecMismatch.Contract,
            otp_app: :double_down,
            test_dispatch?: false,
            static_dispatch?: true
        end
        """)
      end
    after
      Application.delete_env(:double_down, DoubleDown.Test.SpecMismatch.Contract)
      purge([DoubleDown.Test.SpecMismatch.Contract, DoubleDown.Test.SpecMismatch.Facade])
    end

    test "raises CompileError when return type differs" do
      Application.put_env(
        :double_down,
        DoubleDown.Test.SpecReturnMismatch.Contract,
        impl: DoubleDown.Test.SpecImpl.ReturnMismatch
      )

      assert_raise CompileError, ~r/return type mismatch/, fn ->
        Code.compile_string("""
        defmodule DoubleDown.Test.SpecReturnMismatch.Contract do
          use DoubleDown.Contract
          defcallback greet(name :: String.t()) :: {:ok, String.t()} | {:error, term()}
        end

        defmodule DoubleDown.Test.SpecReturnMismatch.Facade do
          use DoubleDown.ContractFacade,
            contract: DoubleDown.Test.SpecReturnMismatch.Contract,
            otp_app: :double_down,
            test_dispatch?: false,
            static_dispatch?: true
        end
        """)
      end
    after
      Application.delete_env(:double_down, DoubleDown.Test.SpecReturnMismatch.Contract)

      purge([
        DoubleDown.Test.SpecReturnMismatch.Contract,
        DoubleDown.Test.SpecReturnMismatch.Facade
      ])
    end
  end

  describe "spec mismatch — warn_on_typespec_mismatch? opt-out" do
    test "emits warning instead of error when opt-out is set" do
      Application.put_env(
        :double_down,
        DoubleDown.Test.SpecWarnOnly.Contract,
        impl: DoubleDown.Test.SpecImpl.ParamMismatch
      )

      warnings =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Code.compile_string("""
          defmodule DoubleDown.Test.SpecWarnOnly.Contract do
            use DoubleDown.Contract
            defcallback greet(name :: String.t()) :: {:ok, String.t()} | {:error, term()},
              warn_on_typespec_mismatch?: true
          end

          defmodule DoubleDown.Test.SpecWarnOnly.Facade do
            use DoubleDown.ContractFacade,
              contract: DoubleDown.Test.SpecWarnOnly.Contract,
              otp_app: :double_down,
              test_dispatch?: false,
              static_dispatch?: true
          end
          """)
        end)

      assert warnings =~ "param type mismatch"
    after
      Application.delete_env(:double_down, DoubleDown.Test.SpecWarnOnly.Contract)
      purge([DoubleDown.Test.SpecWarnOnly.Contract, DoubleDown.Test.SpecWarnOnly.Facade])
    end
  end

  describe "spec checking — graceful skip" do
    test "no error when impl has no specs" do
      Application.put_env(
        :double_down,
        DoubleDown.Test.SpecNoSpec.Contract,
        impl: DoubleDown.Test.SpecImpl.NoSpec
      )

      Code.compile_string("""
      defmodule DoubleDown.Test.SpecNoSpec.Contract do
        use DoubleDown.Contract
        defcallback greet(name :: String.t()) :: {:ok, String.t()} | {:error, term()}
      end

      defmodule DoubleDown.Test.SpecNoSpec.Facade do
        use DoubleDown.ContractFacade,
          contract: DoubleDown.Test.SpecNoSpec.Contract,
          otp_app: :double_down,
          test_dispatch?: false,
          static_dispatch?: true
      end
      """)
    after
      Application.delete_env(:double_down, DoubleDown.Test.SpecNoSpec.Contract)
      purge([DoubleDown.Test.SpecNoSpec.Contract, DoubleDown.Test.SpecNoSpec.Facade])
    end

    test "no error when test_dispatch is enabled (no static impl)" do
      Code.compile_string("""
      defmodule DoubleDown.Test.SpecTestDispatch.Contract do
        use DoubleDown.Contract
        defcallback greet(name :: String.t()) :: {:ok, String.t()} | {:error, term()}
      end

      defmodule DoubleDown.Test.SpecTestDispatch.Facade do
        use DoubleDown.ContractFacade,
          contract: DoubleDown.Test.SpecTestDispatch.Contract,
          otp_app: :double_down,
          test_dispatch?: true,
          static_dispatch?: false
      end
      """)
    after
      purge([DoubleDown.Test.SpecTestDispatch.Contract, DoubleDown.Test.SpecTestDispatch.Facade])
    end

    test "no error when impl has spec for some operations but not others" do
      Application.put_env(
        :double_down,
        DoubleDown.Test.SpecPartial.Contract,
        impl: DoubleDown.Test.SpecImpl.Matching
      )

      Code.compile_string("""
      defmodule DoubleDown.Test.SpecPartial.Contract do
        use DoubleDown.Contract
        defcallback greet(name :: String.t()) :: {:ok, String.t()} | {:error, term()}
        defcallback list_all() :: list(String.t())
      end

      defmodule DoubleDown.Test.SpecPartial.Facade do
        use DoubleDown.ContractFacade,
          contract: DoubleDown.Test.SpecPartial.Contract,
          otp_app: :double_down,
          test_dispatch?: false,
          static_dispatch?: true
      end
      """)
    after
      Application.delete_env(:double_down, DoubleDown.Test.SpecPartial.Contract)
      purge([DoubleDown.Test.SpecPartial.Contract, DoubleDown.Test.SpecPartial.Facade])
    end
  end

  # -------------------------------------------------------------------
  # Unit tests for types_equal?
  # -------------------------------------------------------------------

  describe "types_equal?" do
    alias DoubleDown.Contract.SpecWarnings

    test "same type with different line numbers are equal" do
      ast1 = {:string, [line: 1], []}
      ast2 = {:string, [line: 99], []}
      assert SpecWarnings.types_equal?(ast1, ast2)
    end

    test "different types are not equal" do
      ast1 = {:string, [], []}
      ast2 = {:integer, [], []}
      refute SpecWarnings.types_equal?(ast1, ast2)
    end

    test "complex types with same structure are equal" do
      ast1 =
        {:|, [line: 1],
         [
           ok: {{:., [line: 1], [String, :t]}, [line: 1], []},
           error: {:term, [line: 1], []}
         ]}

      ast2 =
        {:|, [line: 50],
         [
           ok: {{:., [line: 50], [String, :t]}, [line: 50], []},
           error: {:term, [line: 50], []}
         ]}

      assert SpecWarnings.types_equal?(ast1, ast2)
    end

    test "keyword() and list() are not equal" do
      ast1 = {:keyword, [line: 1], []}
      ast2 = {:list, [line: 1], []}
      refute SpecWarnings.types_equal?(ast1, ast2)
    end
  end

  # -------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------

  defp purge(modules) do
    Enum.each(modules, fn mod ->
      :code.purge(mod)
      :code.delete(mod)
    end)
  end
end
