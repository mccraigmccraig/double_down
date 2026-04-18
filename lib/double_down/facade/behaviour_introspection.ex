defmodule DoubleDown.Facade.BehaviourIntrospection do
  @moduledoc false

  # Extracts operation metadata from vanilla Elixir `@behaviour` modules
  # by reading their `@callback` declarations via `Code.Typespec`.
  #
  # Returns operation maps in the same format as `DoubleDown.Contract.__callbacks__/0`,
  # suitable for passing to `DoubleDown.Facade.Codegen.generate_facade/5`.
  #
  # Note: `Code.Typespec` is `@moduledoc false` in Elixir's stdlib but has
  # been stable for years and is used by IEx, dialyxir, hammox, and many
  # other tools. It is the only way to get callback type information from
  # compiled BEAM files.

  @doc false
  @spec fetch_operations!(module(), Macro.Env.t()) :: [map()]
  def fetch_operations!(behaviour, env) do
    validate_loaded!(behaviour, env)

    callbacks = fetch_callbacks!(behaviour, env)

    Enum.map(callbacks, fn {{name, _arity}, spec_clauses} ->
      # Use the first spec clause. Multiple clauses arise from
      # overloaded @callback declarations for the same name/arity,
      # which is rare but valid Elixir.
      [first_clause | _rest] = spec_clauses

      quoted_spec = Code.Typespec.spec_to_quoted(name, first_clause)

      {param_types, return_type, when_constraints} = destructure_spec(quoted_spec)
      param_names = extract_param_names(param_types)
      bare_param_types = strip_annotations(param_types)

      %{
        name: name,
        params: param_names,
        param_types: bare_param_types,
        return_type: return_type,
        when_constraints: when_constraints,
        pre_dispatch: nil,
        user_doc: nil,
        arity: length(param_names)
      }
    end)
  end

  # -------------------------------------------------------------------
  # Validation
  # -------------------------------------------------------------------

  defp validate_loaded!(behaviour, env) do
    unless Code.ensure_loaded?(behaviour) do
      raise CompileError,
        description:
          "Behaviour module #{inspect(behaviour)} is not loaded. " <>
            "Ensure it is compiled before #{inspect(env.module)}.",
        file: env.file,
        line: 0
    end
  end

  defp fetch_callbacks!(behaviour, env) do
    # Code.Typespec.fetch_callbacks/1 accepts a module atom (looks for
    # .beam on disk) or a raw beam binary. Try the module atom first,
    # fall back to :code.get_object_code/1 for the in-memory binary.
    #
    # Important: the behaviour module's .beam file must be on disk for
    # this to work. If both modules are in the same compilation unit
    # (e.g. same elixirc_paths directory), the .beam won't be written
    # yet. The behaviour must be in a directory that compiles before
    # the facade. See the @moduledoc for details.
    result =
      case Code.Typespec.fetch_callbacks(behaviour) do
        {:ok, callbacks} ->
          {:ok, callbacks}

        :error ->
          case :code.get_object_code(behaviour) do
            {^behaviour, binary, _path} ->
              Code.Typespec.fetch_callbacks(binary)

            :error ->
              :error
          end
      end

    case result do
      {:ok, []} ->
        raise CompileError,
          description:
            "#{inspect(behaviour)} has no @callback declarations. " <>
              "Cannot generate a facade for a module with no callbacks.",
          file: env.file,
          line: 0

      {:ok, callbacks} ->
        callbacks

      :error ->
        raise CompileError,
          description:
            "Could not fetch callback specs from #{inspect(behaviour)}. " <>
              "Ensure it defines @callback declarations and that its .beam " <>
              "file is on disk (the behaviour must compile in a prior " <>
              "compilation unit — see DoubleDown.BehaviourFacade docs).",
          file: env.file,
          line: 0
    end
  end

  # -------------------------------------------------------------------
  # Spec destructuring
  # -------------------------------------------------------------------

  # Spec with `when` clause:
  #   {:when, _, [{:"::", _, [{:name, _, params}, return]}, constraints]}
  # Returns {param_types, return_type, constraints} where constraints
  # is a keyword list like [input: {:term, _, []}, output: {:term, _, []}].
  defp destructure_spec({:when, _meta, [{:"::", _meta2, [call, return_type]}, constraints]}) do
    param_types = extract_call_params(call)
    {param_types, return_type, constraints}
  end

  # Normal spec:
  #   {:"::", _, [{:name, _, params}, return]}
  defp destructure_spec({:"::", _meta, [call, return_type]}) do
    param_types = extract_call_params(call)
    {param_types, return_type, nil}
  end

  # Extract params from the function call part of the spec.
  # Zero-arg: {:fun_name, meta, []}
  # With args: {:fun_name, meta, [param_type1, param_type2, ...]}
  defp extract_call_params({_name, _meta, params}) when is_list(params), do: params
  defp extract_call_params({_name, _meta, nil}), do: []

  # -------------------------------------------------------------------
  # Param name extraction
  # -------------------------------------------------------------------

  # Extract param names from param type ASTs.
  #
  # Three shapes we handle:
  # 1. Annotated params like `id :: String.t()`:
  #      {:"::", _, [{:id, _, nil}, type_ast]}
  #    → use the annotation name `:id`
  #
  # 2. Type variables from `when` clauses like `transform(input) :: ...`:
  #      {:input, _, nil}
  #    → use the variable name `:input`
  #    (Distinguished from bare types by nil context vs [] args)
  #
  # 3. Bare types like `String.t()` or `map()`:
  #      {{:., _, [String, :t]}, _, []}  or  {:map, _, []}
  #    → synthesize `arg1`, `arg2`, etc.
  defp extract_param_names(param_types) do
    param_types
    |> Enum.with_index(1)
    |> Enum.map(fn {param_type, index} ->
      case param_type do
        # Annotated: id :: String.t()
        {:"::", _meta, [{name, _name_meta, nil}, _type]} when is_atom(name) ->
          name

        # Type variable from when clause: {:input, _, nil}
        {name, _meta, nil} when is_atom(name) ->
          name

        # Bare type: synthesize name
        _bare_type ->
          String.to_atom("arg#{index}")
      end
    end)
  end

  # -------------------------------------------------------------------
  # Annotation stripping
  # -------------------------------------------------------------------

  # Strip name annotations from param types.
  # Annotated: {:"::", _, [{:name, _, nil}, actual_type]} -> actual_type
  # Bare: already just the type, pass through.
  defp strip_annotations(param_types) do
    Enum.map(param_types, fn
      {:"::", _meta, [{_name, _name_meta, nil}, type]} ->
        type

      bare_type ->
        bare_type
    end)
  end
end
