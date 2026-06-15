defmodule DoubleDown.DynamicFacade.Meck do
  @moduledoc false

  @backup :meck_dd_backup
  @marker :__dd_meck_guard__

  @doc false
  @spec install() :: :ok
  def install do
    cond do
      not Code.ensure_loaded?(:meck) -> :ok
      meck_guarded?() -> :ok
      true -> do_install()
    end
  end

  @doc false
  def __guard__(mod_or_list) do
    mod_or_list
    |> List.wrap()
    |> Enum.each(fn mod ->
      if DoubleDown.DynamicFacade.setup?(mod) do
        raise ArgumentError, """
        :meck (with_mock/with_mocks) cannot mock #{inspect(mod)} — it is managed by a \
        DoubleDown DynamicFacade. meck's bytecode replacement would destroy the facade \
        shim VM-globally. Use DoubleDown.Double for this module instead.
        """
      end

      if mimic_managing?(mod) do
        raise ArgumentError, """
        :meck (with_mock/with_mocks) cannot mock #{inspect(mod)} — it is managed by \
        Mimic. meck's bytecode replacement would conflict with Mimic's copy of this \
        module. Use DoubleDown.Double for this module instead.
        """
      end
    end)
  end

  @doc false
  def guarded?, do: meck_guarded?()

  defp meck_guarded?, do: function_exported?(:meck, @marker, 0)

  defp do_install do
    try do
      DoubleDown.DynamicFacade.Shader.rename_module(:meck, @backup, false)
    rescue
      MatchError ->
        IO.warn(
          "DoubleDown: :meck lacks abstract_code — meck guard not installed. " <>
            "DynamicFacade modules are unprotected from meck mocking in this environment."
        )

        :ok
    else
      _ -> create_shim()
    end
  end

  defp create_shim do
    backup = @backup
    exports = backup.module_info(:exports)

    passthrough =
      Enum.reject(exports, fn
        {:module_info, 0} -> true
        {:module_info, 1} -> true
        {:new, 1} -> true
        {:new, 2} -> true
        _ -> false
      end)

    passthrough_fns =
      for {name, arity} <- passthrough do
        args = Macro.generate_arguments(arity, __MODULE__)

        quote do
          def unquote(name)(unquote_splicing(args)),
            do: apply(unquote(@backup), unquote(name), unquote(args))
        end
      end

    guarded_new = [
      quote do
        def new(mod) do
          DoubleDown.DynamicFacade.Meck.__guard__(mod)
          apply(unquote(@backup), :new, [mod])
        end
      end,
      quote do
        def new(mod, opts) do
          DoubleDown.DynamicFacade.Meck.__guard__(mod)
          apply(unquote(@backup), :new, [mod, opts])
        end
      end
    ]

    marker = [
      quote do
        def unquote(@marker)(), do: true
      end
    ]

    contents = passthrough_fns ++ guarded_new ++ marker

    prev = Code.compiler_options(ignore_module_conflict: true)

    try do
      Module.create(:meck, contents, Macro.Env.location(__ENV__))
    after
      Code.compiler_options(ignore_module_conflict: prev[:ignore_module_conflict])
    end

    :ok
  end

  defp mimic_managing?(module) do
    mimic_mod = Module.concat(Mimic, Module)
    mimic_srv = Module.concat(Mimic, Server)

    Code.ensure_loaded?(mimic_mod) and
      Code.ensure_loaded?(mimic_srv) and
      (apply(mimic_mod, :copied?, [module]) or
         apply(mimic_srv, :marked_to_copy?, [module]))
  end
end
