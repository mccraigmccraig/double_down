defmodule DoubleDown.DynamicFacade.Shader do
  @moduledoc false

  @doc false
  def rename_module(module, new_name, cover_enabled?) do
    beam_code =
      case :code.get_object_code(module) do
        {^module, binary, _path} -> binary
        :error -> raise "Failed to get object code for #{inspect(module)}"
      end

    {:ok, {_, [{:abstract_code, {:raw_abstract_v1, forms}}]}} =
      :beam_lib.chunks(beam_code, [:abstract_code])

    forms = rename_module_attribute(forms, new_name)

    compiler_opts =
      module.module_info(:compile)
      |> Keyword.get(:options, [])
      |> Enum.filter(&(&1 != :from_core))
      |> then(&[:return_errors, :debug_info | &1])

    binary =
      case :compile.forms(forms, compiler_opts) do
        {:ok, _module_name, binary} -> binary
        {:ok, _module_name, binary, _warnings} -> binary
      end

    {:module, ^new_name} = :code.load_binary(new_name, ~c"", binary)

    if cover_enabled? do
      apply(:cover, :compile_beams, [[{new_name, binary}]])
    end
  end

  defp rename_module_attribute([{:attribute, line, :module, {_, vars}} | t], new_name) do
    [{:attribute, line, :module, {new_name, vars}} | t]
  end

  defp rename_module_attribute([{:attribute, line, :module, _} | t], new_name) do
    [{:attribute, line, :module, new_name} | t]
  end

  defp rename_module_attribute([h | t], new_name) do
    [h | rename_module_attribute(t, new_name)]
  end

  defp rename_module_attribute([], _new_name), do: []
end
