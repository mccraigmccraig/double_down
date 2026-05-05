defmodule DoubleDown.DynamicFacade.Cover do
  @moduledoc """
  Ensures DynamicFacade-shimmed modules retain `:cover` instrumentation.

  When ExCoverall or `:cover` compiles a module with coverage instrumentation,
  `DynamicFacade.setup/1` renames the on-disk (non-instrumented) bytecode to
  `Module.__dd_original__`, stripping coverage from the backup. This module
  preserves coverage by:

    1. Exporting pre-shim coverdata
    2. Re-instrumenting the backup via `:cover.compile_beams/1`
    3. Providing `merge/1` to rewrite backup coverdata back to the original name
  """

  @doc false
  # Recompiles the `:cover` module with `:export_all` to expose
  # `compile_beams/1` (private function that accepts in-memory binaries).
  # Idempotent — checks if private functions are already exported.
  # Based on meck and Mimic's approach.
  def export_private_functions do
    if not private_functions_exported?() do
      {_, binary, _} = :code.get_object_code(:cover)

      {:ok, {_, [{_, {:raw_abstract_v1, abstract_code}}]}} =
        :beam_lib.chunks(binary, [:abstract_code])

      {:ok, module, binary} = :compile.forms(abstract_code, [:export_all])
      {:module, :cover} = :code.load_binary(module, ~c"", binary)
    end

    :ok
  end

  @doc false
  def enabled_for?(module) do
    apply(:cover, :is_compiled, [module]) != false
  end

  @doc false
  def export_coverdata!(module) do
    path = Path.expand("#{module}-#{:os.getpid()}.coverdata", ".")
    :ok = apply(:cover, :export, [String.to_charlist(path), module])
    path
  end

  @doc """
  Merge coverdata from the `__dd_original__` backup into the original module name.

  Exports coverdata for `Module.__dd_original__`, rewrites all module-name
  references back to `Module`, imports the result, and cleans up the temp file.

  Call this after all tests have completed to ensure ExCoverall sees coverage
  for DynamicFacade-shimmed modules under their original names.
  """
  def merge(module) do
    backup = Module.concat(module, :__dd_original__)
    path = export_coverdata!(backup)
    rewrite_coverdata!(path, backup, module)

    :ok = apply(:cover, :import, [String.to_charlist(path)])
    File.rm(path)
    :ok
  end

  # -- Private --

  defp private_functions_exported? do
    function_exported?(:cover, :get_term, 1)
  end

  defp rewrite_coverdata!(path, from_module, to_module) do
    terms = get_terms(path)
    terms = replace_module_name(terms, from_module, to_module)
    write_coverdata!(path, terms)
  end

  defp replace_module_name(terms, from_module, to_module) do
    Enum.map(terms, fn term -> do_replace_module_name(term, from_module, to_module) end)
  end

  defp do_replace_module_name({:file, _old, file}, from_module, to_module) do
    {:file, to_module, String.replace(file, to_string(from_module), to_string(to_module))}
  end

  defp do_replace_module_name({bump = {:bump, _mod, _, _, _, _}, value}, from_module, to_module) do
    {put_elem(bump, 2, bump_module_name(bump, from_module, to_module)), value}
  end

  defp do_replace_module_name({_mod, clauses}, from_module, to_module) do
    {to_module, replace_module_name(clauses, from_module, to_module)}
  end

  defp do_replace_module_name(clause = {_mod, _, _, _, _}, _from_module, to_module) do
    put_elem(clause, 0, to_module)
  end

  defp do_replace_module_name(other, _from_module, _to_module), do: other

  defp bump_module_name(bump, from_module, to_module) do
    case elem(bump, 1) do
      ^from_module -> to_module
      other -> other
    end
  end

  defp get_terms(path) do
    {:ok, resource} = File.open(path, [:binary, :read, :raw])
    terms = get_terms(resource, [])
    File.close(resource)
    terms
  end

  defp get_terms(resource, terms) do
    case apply(:cover, :get_term, [resource]) do
      :eof -> terms
      term -> get_terms(resource, [term | terms])
    end
  end

  defp write_coverdata!(path, terms) do
    {:ok, resource} = File.open(path, [:write, :binary, :raw])
    Enum.each(terms, fn term -> apply(:cover, :write, [term, resource]) end)
    File.close(resource)
  end
end
