defmodule DoubleDown.DynamicFacade.CoverTest do
  use ExUnit.Case

  alias DoubleDown.DynamicFacade
  alias DoubleDown.DynamicFacade.Cover

  setup_all do
    case cover_start() do
      :ok ->
        cover_stop()
        :ok

      :unavailable ->
        :ok
    end
  end

  setup do
    cover_start()

    on_exit(fn ->
      cover_stop()
    end)
  end

  defp cover_available?, do: is_tuple(:code.is_loaded(:cover))

  defp cover_start do
    if cover_available?() do
      apply(:cover, :start, [])
      :ok
    else
      :unavailable
    end
  end

  defp cover_stop do
    if cover_available?() do
      apply(:cover, :stop, [])
    end
  end

  defp cover_compile_beam(path), do: apply(:cover, :compile_beam, [path])
  defp cover_analyse(mod, type, scope), do: apply(:cover, :analyse, [mod, type, scope])
  defp code_which(mod), do: apply(:code, :which, [mod])

  describe "Cover.export_private_functions/0" do
    test "is idempotent" do
      if cover_available?() do
        assert :ok = Cover.export_private_functions()
        assert :ok = Cover.export_private_functions()
      end
    end

    test "exposes :cover.compile_beams/1" do
      if cover_available?() do
        Cover.export_private_functions()
        assert function_exported?(:cover, :compile_beams, 1)
      end
    end
  end

  describe "Cover.enabled_for?/1" do
    test "returns false for a non-cover-compiled module" do
      refute Cover.enabled_for?(DoubleDown.Test.SimpleUser)
    end

    test "returns true after cover-compiling a module" do
      if cover_available?() do
        beam_path = code_which(DoubleDown.Test.SimpleUser)
        {:ok, _} = cover_compile_beam(beam_path)
        assert Cover.enabled_for?(DoubleDown.Test.SimpleUser)
      end
    end
  end

  describe "coverage data flow through DynamicFacade" do
    test "coverdata preserved for __dd_original__ backup" do
      if cover_available?() do
        target = DoubleDown.Test.SimpleUser
        beam_path = code_which(target)

        {:ok, _} = cover_compile_beam(beam_path)
        assert Cover.enabled_for?(target)

        DynamicFacade.setup(target)

        backup = Module.concat(target, :__dd_original__)
        assert Code.ensure_loaded?(backup)

        assert Cover.enabled_for?(backup)

        struct_empty = apply(target, :__struct__, [])
        struct_filled = apply(target, :__struct__, name: "test")

        assert apply(backup, :__struct__, []) == struct_empty
        assert apply(backup, :__struct__, name: "test") == struct_filled
      end
    end
  end

  describe "Cover.merge/1" do
    test "rewrites backup coverdata to original module name" do
      if cover_available?() do
        target = DoubleDown.Test.SimpleUser
        beam_path = code_which(target)

        {:ok, _} = cover_compile_beam(beam_path)

        DynamicFacade.setup(target)

        backup = Module.concat(target, :__dd_original__)
        assert Cover.enabled_for?(backup)

        apply(backup, :__struct__, [])

        :ok = Cover.merge(target)

        coverage = cover_analyse(target, :calls, :function)
        assert is_list(coverage)
      end
    end
  end
end
