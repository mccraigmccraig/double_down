defmodule DoubleDown.DynamicFacade do
  @moduledoc """
  Dynamic dispatch facades for existing modules.

  Enables Mimic-style bytecode interception — replace any module with
  a dispatch shim at test time, then use the full `DoubleDown.Double`
  API (expects, stubs, fakes, stateful responders, passthrough) without
  defining a contract or facade.

  ## Setup

  Call `setup/1` in `test/test_helper.exs` **before** `ExUnit.start()`:

      DoubleDown.DynamicFacade.setup(MyApp.EctoRepo)
      DoubleDown.DynamicFacade.setup(SomeThirdPartyModule)

      ExUnit.start()

  ## Usage in tests

      setup do
        DoubleDown.Double.fallback(MyApp.EctoRepo, DoubleDown.Repo.OpenInMemory)
        :ok
      end

      test "insert then get" do
        {:ok, user} = MyApp.EctoRepo.insert(User.changeset(%{name: "Alice"}))
        assert ^user = MyApp.EctoRepo.get(User, user.id)
      end

  Tests that don't install a handler get the original module's
  behaviour — zero impact on unrelated tests.

  ## Struct modules

  If the original module defines a struct (`defstruct`), the shim
  preserves full struct support:

    * `%Module{}` literal syntax works at compile time in tests
    * `__info__(:struct)` returns correct field metadata
    * `@enforce_keys` and default values are preserved
    * `__struct__/0` and `__struct__/1` calls route through
      `dispatch/3`, so `Double.fallback` / `Double.expect` handlers
      can intercept struct construction at runtime

  ## Behaviour and macro modules

    * **`@behaviour` declarations** are copied from the original
      module to the shim, so behaviour-based dispatch and compliance
      checks work correctly.
    * **Macros** (`defmacro`) are proxied via `defmacro` wrappers
      that delegate to the original implementation. Macros expand at
      compile time so they always use the original — they cannot be
      intercepted by `Double` handlers.

  ## Constraints

  - Call `setup/1` before tests start (in `test_helper.exs`). Bytecode
    replacement is VM-global; calling it during async tests may cause
    flaky behaviour.
  - Cannot set up dynamic facades for DoubleDown contracts (use
    `DoubleDown.ContractFacade` instead), DoubleDown internals,
    NimbleOwnership, or Erlang/OTP modules.

  ## See also

    * `DoubleDown.ContractFacade` — dispatch facades for `defcallback` contracts
      (typed, LSP-friendly, recommended for new code).
    * `DoubleDown.BehaviourFacade` — dispatch facades for vanilla
      `@behaviour` modules (typed, but no pre_dispatch or combined
      contract + facade).
  """

  @registry_key __MODULE__

  # -- Public API --

  @doc """
  Set up a dynamic dispatch facade for a module.

  Copies the original module to a backup (`Module.__dd_original__`)
  and replaces it with a shim that dispatches through
  `DoubleDown.DynamicFacade.dispatch/3`.

  Call this in `test/test_helper.exs` **before** `ExUnit.start()`.
  Bytecode replacement is VM-global — calling during async tests may
  cause flaky behaviour.

  After setup, use the full `DoubleDown.Double` API:

      DoubleDown.Double.fallback(MyModule, handler)
      DoubleDown.Double.expect(MyModule, :op, fn [args] -> result end)

  Tests that don't install a handler get the original module's
  behaviour automatically.
  """
  @spec setup(module()) :: :ok
  def setup(module) do
    if setup?(module) do
      :ok
    else
      DoubleDown.DynamicFacade.Validator.validate_module!(module)
      do_setup(module)
      register_module(module)
      :ok
    end
  end

  @doc """
  Check whether a module has been set up for dynamic dispatch.
  """
  @spec setup?(module()) :: boolean()
  def setup?(module) do
    module in registered_modules()
  end

  @doc """
  Dispatch a call through the dynamic facade.

  Called by generated shims. Checks NimbleOwnership for a test
  handler, falls back to the original module (`Module.__dd_original__`).
  """
  @spec dispatch(module(), atom(), [term()]) :: term()
  def dispatch(module, operation, args) do
    case DoubleDown.Contract.Dispatch.resolve_test_handler(module) do
      {:ok, owner_pid, handler} ->
        result =
          DoubleDown.Contract.Dispatch.invoke_handler(handler, owner_pid, module, operation, args)

        DoubleDown.Contract.Dispatch.maybe_log(owner_pid, module, operation, args, result)
        result

      :none ->
        original = original_module(module)
        apply(original, operation, args)
    end
  end

  # -- Bytecode manipulation --
  #
  # Approach adapted from Mimic (https://github.com/edgurgel/mimic):
  # 1. Rename the original module by editing its abstract code and
  #    recompiling — this preserves the full original bytecode
  # 2. Create a shim module at the original name that dispatches
  #    through Dynamic.dispatch/3

  defp do_setup(module) do
    backup = original_module(module)
    cover_enabled? = DoubleDown.DynamicFacade.Cover.enabled_for?(module)

    if cover_enabled? do
      DoubleDown.DynamicFacade.Cover.export_coverdata!(module)
      DoubleDown.DynamicFacade.Cover.export_private_functions()
    end

    # 1. Rename the original module's beam to the backup name
    rename_module(module, backup, cover_enabled?)

    # 2. Get the public function exports (from the now-backup module)
    functions = backup.module_info(:exports)
    internal = [__info__: 1, module_info: 0, module_info: 1]
    functions = Enum.reject(functions, &(&1 in internal))

    # 3. If the module defines a struct, capture struct info for metadata
    struct_info = get_struct_info(backup)

    # 4. Capture @behaviour declarations from the original module
    behaviours = get_behaviours(backup)

    # 5. Detect macros and exclude their MACRO- functions from dispatch wrappers
    macros = get_macros(backup)

    macro_fns =
      for {name, arity} <- macros do
        {String.to_atom("MACRO-#{name}"), arity + 1}
      end

    functions = Enum.reject(functions, &(&1 in macro_fns))

    # 6. Create the dispatch shim at the original module name
    #    Note: __struct__/0 and __struct__/1 are kept as dispatch wrappers
    #    so they route through Double handlers. The defstruct declaration
    #    only provides __info__(:struct) metadata and compile-time support.
    create_shim(module, functions, struct_info, behaviours, macros, backup)
  end

  defp rename_module(module, new_name, cover_enabled?) do
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

  defp create_shim(module, functions, struct_info, behaviours, macros, backup) do
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
    # behaviour_decls first, then struct_decl, then dispatch_fns, then macros.
    # dispatch_fns after struct_decl so dispatch __struct__/0,/1
    # wrappers override the defstruct-generated ones.
    contents = behaviour_decls ++ struct_decl ++ dispatch_fns ++ macro_decls

    prev = Code.compiler_options(ignore_module_conflict: true)

    try do
      Module.create(module, contents, Macro.Env.location(__ENV__))
    after
      Code.compiler_options(ignore_module_conflict: prev[:ignore_module_conflict])
    end
  end

  # -- Macro support --
  #
  # If the original module exports macros, we generate defmacro wrappers
  # that delegate to the backup module's macro implementation. Macros
  # expand at compile time so they cannot be dispatched through the
  # runtime Double handler — they always use the original implementation.
  # Adapted from Mimic.Module.generate_mimic_macros/1.

  defp get_macros(backup) do
    if function_exported?(backup, :__info__, 1) do
      backup.__info__(:macros)
    else
      []
    end
  end

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

  # -- Behaviour support --
  #
  # Copy @behaviour declarations from the original module to the shim
  # so that behaviour-based dispatch and checks work correctly.
  # Adapted from Mimic.Module.generate_mimic_behaviours/1.

  defp get_behaviours(backup) do
    backup.module_info(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
  end

  defp generate_behaviours(behaviours) do
    for behaviour <- behaviours do
      quote do
        @behaviour unquote(behaviour)
      end
    end
  end

  # -- Struct support --
  #
  # If the original module defines a struct, we re-declare `defstruct`
  # in the shim so that `__info__(:struct)` returns correct metadata
  # and `%Module{}` literal syntax works at compile time.
  # Adapted from Mimic.Module.generate_mimic_struct/1.

  defp get_struct_info(backup) do
    if function_exported?(backup, :__info__, 1) && backup.__info__(:struct) != nil do
      backup.__info__(:struct)
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

        # Mark __struct__/0 and __struct__/1 as overridable so the
        # dispatch wrappers (generated after this block) take precedence.
        # This preserves __info__(:struct) metadata from defstruct while
        # routing actual calls through DynamicFacade.dispatch/3.
        defoverridable __struct__: 0, __struct__: 1
      end

    Enum.reject([enforce, defstruct_decl], &is_nil/1)
  end

  # -- Registry --

  @doc false
  # NOTE: This has a theoretical TOCTOU race — two concurrent calls could
  # both read the list, both pass the `unless` check, and both prepend,
  # resulting in a duplicate. In practice this is harmless because setup/1
  # is called sequentially in test_helper.exs before ExUnit.start().
  def register_module(module) do
    modules = registered_modules()

    unless module in modules do
      :persistent_term.put(@registry_key, [module | modules])
    end
  end

  defp registered_modules do
    :persistent_term.get(@registry_key, [])
  end

  @doc false
  def original_module(module) do
    Module.concat(module, :__dd_original__)
  end
end
