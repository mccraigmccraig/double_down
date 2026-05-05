defmodule DoubleDown.DynamicFacade.Shim do
  @moduledoc false

  @doc false
  def create_shim(module, functions, struct_info, behaviours, macros, backup) do
    dispatch_fns =
      for {name, arity} <- functions do
        args = Macro.generate_arguments(arity, __MODULE__)

        quote do
          def unquote(name)(unquote_splicing(args)) do
            DoubleDown.DynamicFacade.dispatch(
              unquote(module),
              unquote(name),
              unquote(args)
            )
          end
        end
      end

    behaviour_decls = generate_behaviours(behaviours)
    struct_decl = generate_struct(struct_info, backup)
    macro_decls = generate_macros(macros, backup)

    contents = behaviour_decls ++ struct_decl ++ dispatch_fns ++ macro_decls

    prev = Code.compiler_options(ignore_module_conflict: true)

    try do
      Module.create(module, contents, Macro.Env.location(__ENV__))
    after
      Code.compiler_options(ignore_module_conflict: prev[:ignore_module_conflict])
    end
  end

  @doc false
  def get_macros(backup) do
    if function_exported?(backup, :__info__, 1) do
      backup.__info__(:macros)
    else
      []
    end
  end

  @doc false
  def get_behaviours(backup) do
    backup.module_info(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
  end

  @doc false
  def get_struct_info(backup) do
    if function_exported?(backup, :__info__, 1) && backup.__info__(:struct) != nil do
      backup.__info__(:struct)
    end
  end

  # -- Private --

  defp generate_macros(macros, backup) do
    for {macro_name, arity} <- macros do
      args = Macro.generate_arguments(arity, __MODULE__)
      macro_fn = String.to_existing_atom("MACRO-#{macro_name}")

      quote do
        defmacro unquote(macro_name)(unquote_splicing(args)) do
          apply(unquote(backup), unquote(macro_fn), [__CALLER__, unquote_splicing(args)])
        end
      end
    end
  end

  defp generate_behaviours(behaviours) do
    for behaviour <- behaviours do
      quote do
        @behaviour unquote(behaviour)
      end
    end
  end

  defp generate_struct(nil, _backup), do: []

  defp generate_struct(struct_info, backup) do
    struct_template = Map.from_struct(backup.__struct__())

    required_fields =
      for %{field: field, required: true} <- struct_info, do: field

    struct_params =
      for %{field: field} <- struct_info do
        {field, Macro.escape(struct_template[field])}
      end

    enforce =
      if required_fields != [] do
        quote do
          @enforce_keys unquote(required_fields)
        end
      end

    defstruct_decl =
      quote do
        defstruct unquote(struct_params)

        defoverridable __struct__: 0, __struct__: 1
      end

    Enum.reject([enforce, defstruct_decl], &is_nil/1)
  end
end
