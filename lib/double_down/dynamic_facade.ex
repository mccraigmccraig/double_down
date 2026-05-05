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
    DoubleDown.DynamicFacade.Shader.rename_module(module, backup, cover_enabled?)

    # 2. Get the public function exports (from the now-backup module)
    functions = backup.module_info(:exports)
    internal = [__info__: 1, module_info: 0, module_info: 1]
    functions = Enum.reject(functions, &(&1 in internal))

    alias DoubleDown.DynamicFacade.Shim

    # 3. If the module defines a struct, capture struct info for metadata
    struct_info = Shim.get_struct_info(backup)

    # 4. Capture @behaviour declarations from the original module
    behaviours = Shim.get_behaviours(backup)

    # 5. Detect macros and exclude their MACRO- functions from dispatch wrappers
    macros = Shim.get_macros(backup)

    macro_fns =
      for {name, arity} <- macros do
        {String.to_atom("MACRO-#{name}"), arity + 1}
      end

    functions = Enum.reject(functions, &(&1 in macro_fns))

    # 6. Create the dispatch shim at the original module name
    Shim.create_shim(module, functions, struct_info, behaviours, macros, backup)
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

  @doc false
  def registered_modules do
    :persistent_term.get(@registry_key, [])
  end

  @doc false
  def original_module(module) do
    Module.concat(module, :__dd_original__)
  end
end
