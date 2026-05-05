defmodule DoubleDown.DynamicFacade.Validator do
  @moduledoc false

  @doc false
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def validate_module!(module) do
    unless Code.ensure_loaded?(module) do
      raise ArgumentError,
            "cannot set up dynamic facade for #{inspect(module)} — module is not loaded"
    end

    if function_exported?(module, :__callbacks__, 0) do
      raise ArgumentError,
            "cannot set up dynamic facade for #{inspect(module)} — " <>
              "it is a DoubleDown contract. Use `DoubleDown.ContractFacade` instead."
    end

    module_str = Atom.to_string(module)

    if String.starts_with?(module_str, "Elixir.DoubleDown.") and
         not String.starts_with?(module_str, "Elixir.DoubleDown.Test.") do
      raise ArgumentError,
            "cannot set up dynamic facade for #{inspect(module)} — " <>
              "it is a DoubleDown internal module"
    end

    if module == NimbleOwnership or String.starts_with?(module_str, "Elixir.NimbleOwnership.") do
      raise ArgumentError,
            "cannot set up dynamic facade for #{inspect(module)} — " <>
              "NimbleOwnership is required by the dispatch machinery"
    end

    unless String.starts_with?(module_str, "Elixir.") do
      raise ArgumentError,
            "cannot set up dynamic facade for #{inspect(module)} — " <>
              "Erlang/OTP modules cannot be shimmed"
    end

    unless loaded_mimic_has_expected_api?() do
      raise ArgumentError,
            "DoubleDown's Mimic conflict detection relies on " <>
              "Mimic.Module.copied?/1 and Mimic.Server.marked_to_copy?/1 " <>
              "which are not available in the installed Mimic version. " <>
              "DoubleDown may need an update to support this Mimic release."
    end

    if mimic_managing?(module) do
      raise ArgumentError,
            "cannot set up dynamic facade for #{inspect(module)} — " <>
              "Mimic is already managing this module. " <>
              "Do not use Mimic and DynamicFacade on the same module. " <>
              "Use DoubleDown.Double for all test doubles instead."
    end

    case :code.get_object_code(module) do
      :error ->
        raise ArgumentError,
              "cannot set up dynamic facade for #{inspect(module)} — " <>
                "no beam file found (module may have been defined dynamically)"

      {^module, _binary, _path} ->
        :ok
    end
  end

  defp mimic_managing?(module) do
    mimic_mod = Module.concat(Mimic, Module)
    mimic_srv = Module.concat(Mimic, Server)

    Code.ensure_loaded?(mimic_mod) and
      Code.ensure_loaded?(mimic_srv) and
      (apply(mimic_mod, :copied?, [module]) or
         apply(mimic_srv, :marked_to_copy?, [module]))
  end

  defp loaded_mimic_has_expected_api? do
    mimic_mod = Module.concat([Mimic, Module])
    mimic_srv = Module.concat([Mimic, Server])

    not Code.ensure_loaded?(mimic_srv) or
      (function_exported?(mimic_mod, :copied?, 1) and
         function_exported?(mimic_srv, :marked_to_copy?, 1))
  end
end
