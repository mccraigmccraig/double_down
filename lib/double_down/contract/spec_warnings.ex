# Compile-time spec mismatch detection.
#
# Compares defcallback type specs against the production implementation's
# @spec declarations and raises errors (or emits warnings) on mismatch.
# Private module — not part of DoubleDown's public API.
#
defmodule DoubleDown.Contract.SpecWarnings do
  @moduledoc false

  @doc """
  Check all operations against the impl module's specs.

  For each operation, fetches the impl's @spec, converts it to Elixir AST,
  and compares param types and return type against the defcallback declaration.
  Raises CompileError on mismatch (or emits IO.warn if warn_on_typespec_mismatch?
  is set on the operation).

  Skips gracefully if the impl has no specs or the module can't be loaded.
  """
  @spec check_specs!(module(), module(), [map()], Macro.Env.t()) :: :ok
  def check_specs!(facade_module, impl_module, operations, env) do
    impl_specs = fetch_impl_specs(impl_module)

    if impl_specs do
      Enum.each(operations, fn op ->
        check_operation!(facade_module, impl_module, op, impl_specs, env)
      end)
    end

    :ok
  end

  # -- Impl spec fetching --

  defp fetch_impl_specs(impl_module) do
    if Code.ensure_loaded?(impl_module) do
      case Code.Typespec.fetch_specs(impl_module) do
        {:ok, specs} -> specs
        :error -> nil
      end
    else
      nil
    end
  end

  # -- Per-operation checking --

  defp check_operation!(facade_module, impl_module, operation, impl_specs, env) do
    %{
      name: name,
      params: param_names,
      param_types: callback_param_types,
      return_type: callback_return_type,
      arity: arity,
      warn_on_typespec_mismatch?: warn_only?
    } = operation

    case find_impl_spec(impl_specs, name, arity) do
      nil ->
        # No spec on impl for this operation — skip
        :ok

      impl_spec_ast ->
        {impl_param_types, impl_return_type} = extract_types_from_spec(impl_spec_ast)

        check_param_types!(
          facade_module,
          impl_module,
          name,
          arity,
          param_names,
          callback_param_types,
          impl_param_types,
          warn_only?,
          env
        )

        check_return_type!(
          facade_module,
          impl_module,
          name,
          arity,
          callback_return_type,
          impl_return_type,
          warn_only?,
          env
        )
    end
  end

  # -- Spec lookup and extraction --

  defp find_impl_spec(specs, name, arity) do
    case Enum.find(specs, fn {{n, a}, _} -> n == name and a == arity end) do
      nil ->
        nil

      {{_name, _arity}, [spec_ast | _rest]} ->
        # Take the first spec clause (most modules have only one)
        spec_ast
    end
  end

  defp extract_types_from_spec(spec_ast) do
    # spec_to_quoted returns {:"::", _, [call_ast, return_type_ast]}
    # where call_ast is {name, meta, param_type_asts}
    {:"::", _, [call_ast, return_type_ast]} = Code.Typespec.spec_to_quoted(:_, spec_ast)

    param_types =
      case call_ast do
        {_name, _meta, nil} -> []
        {_name, _meta, params} when is_list(params) -> params
      end

    {param_types, return_type_ast}
  end

  # -- Param type comparison --

  defp check_param_types!(
         facade_module,
         impl_module,
         name,
         arity,
         param_names,
         callback_types,
         impl_types,
         warn_only?,
         env
       ) do
    Enum.zip([param_names, callback_types, impl_types])
    |> Enum.each(fn {param_name, callback_type, impl_type} ->
      unless types_equal?(callback_type, impl_type) do
        message = """
        defcallback #{name}/#{arity} param type mismatch in #{inspect(facade_module)}
          param:   #{param_name}
          facade:  #{Macro.to_string(callback_type)}
          impl:    #{Macro.to_string(impl_type)}
          impl module: #{inspect(impl_module)}
          The facade type differs from the production implementation.
          Callers passing valid impl arguments may fail type checking.\
        """

        report_mismatch!(message, warn_only?, env)
      end
    end)
  end

  # -- Return type comparison --

  defp check_return_type!(
         facade_module,
         impl_module,
         name,
         arity,
         callback_type,
         impl_type,
         warn_only?,
         env
       ) do
    unless types_equal?(callback_type, impl_type) do
      message = """
      defcallback #{name}/#{arity} return type mismatch in #{inspect(facade_module)}
        facade:  #{Macro.to_string(callback_type)}
        impl:    #{Macro.to_string(impl_type)}
        impl module: #{inspect(impl_module)}
        The facade return type differs from the production implementation.\
      """

      report_mismatch!(message, warn_only?, env)
    end
  end

  # -- Reporting --

  defp report_mismatch!(message, true = _warn_only?, env) do
    IO.warn(message, Macro.Env.stacktrace(env))
  end

  defp report_mismatch!(message, false = _warn_only?, env) do
    raise CompileError,
      description: message,
      file: env.file,
      line: 0
  end

  # -- Type AST equality --
  #
  # Compares two Elixir type ASTs for structural equality, ignoring
  # line numbers, column info, and other metadata. Walks both trees
  # in parallel and compares the structural elements only.

  @doc false
  def types_equal?(ast1, ast2) do
    normalize(ast1) == normalize(ast2)
  end

  # Normalize a type AST by stripping all metadata (line numbers, etc.)
  # and canonicalizing structural differences between Elixir source AST
  # and Erlang-converted spec AST, so that structural equality works.
  #
  # Key difference: Elixir source `{:ok, String.t()}` becomes the keyword
  # pair `{:ok, ast}` (a 2-tuple), while Code.Typespec.spec_to_quoted
  # produces `{:{}, meta, [:ok, ast]}` (explicit 3-element tuple AST).
  # We normalize both to the `{:{}, [], [...]}` form.

  # list(inner) in source becomes {:list, _, [inner]} in AST, but
  # spec_to_quoted produces [inner] (a literal list). Normalize to [inner].
  defp normalize({:list, _meta, [inner]}) do
    [normalize(inner)]
  end

  # 3-tuple: standard Elixir AST node {form, meta, args}
  defp normalize({form, _meta, args}) when is_atom(form) and is_list(args) do
    {form, [], Enum.map(args, &normalize/1)}
  end

  defp normalize({form, _meta, atom}) when is_atom(form) and is_atom(atom) do
    {form, [], atom}
  end

  # 3-tuple with non-atom form (e.g. {:., meta, [Module, :t]} calls)
  defp normalize({form, _meta, args}) when is_list(args) do
    {normalize(form), [], Enum.map(args, &normalize/1)}
  end

  defp normalize({form, _meta, atom}) when is_atom(atom) do
    {normalize(form), [], atom}
  end

  # 2-tuple: keyword pair or plain pair.
  # Elixir source `{:ok, inner}` is a 2-tuple in the AST. Normalize it
  # to the canonical `{:{}, [], [:ok, inner]}` form that spec_to_quoted uses.
  defp normalize({left, right}) do
    {:{}, [], [normalize(left), normalize(right)]}
  end

  defp normalize(list) when is_list(list) do
    Enum.map(list, &normalize/1)
  end

  defp normalize(atom) when is_atom(atom) do
    atom
  end

  defp normalize(other) do
    other
  end
end
