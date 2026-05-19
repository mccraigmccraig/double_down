# Boundaries

<!-- nav:header:start -->
[< DoubleDown](../README.md) | [Up: Guides](../README.md) | [Index](../README.md) | [Dispatch >](dispatch.md)
<!-- nav:header:end -->

DoubleDown separates _what you call_ from _what handles the call_. A function
call passes through four layers (note: these are conceptual layers, and are optimised away in production paths):

```
     ┌──────────────────────────────────────────────────────┐
     │                 FUNCTION CALL                        │
     │           MyApp.Repo.insert(changeset)               │
     └──────────────────────────┬───────────────────────────┘
                                │
                                ▼
     ┌──────────────────────────────────────────────────────┐
     │                  1.  CONTRACT                        │
     │              (type-level interface)                  │
     │                                                      │
     │  ┌────────────────┐ ┌──────────────┐ ┌─────────────┐ │
     │  │ defcallback    │ │  @behaviour  │ │ any module  │ │
     │  │ (explicit,     │ │  (explicit,  │ │ via Dynamic │ │
     │  │  typed, rich)  │ │   existing   │ │ Facade      │ │
     │  │                │ │   module)    │ │ (implicit)  │ │
     │  └────────┬───────┘ └──────┬───────┘ └──────┬──────┘ │
     └───────────┼────────────────┼────────────────┼────────┘
                 │                │                │
                 ▼                ▼                ▼
     ┌──────────────────────────────────────────────────────┐
     │                  2.  FACADE                          │
     │           (generated dispatch functions)             │
     │                                                      │
     │ ┌────────────────┐ ┌───────────────┐ ┌─────────────┐ │
     │ │ContractFacade  │ │BehaviourFacade│ │DynamicFacade│ │
     │ │use             │ │use            │ │setup(Mod)   │ │
     │ │ ContractFacade │ │BehaviourFacade│ │shim         │ │
     │ │defcallback...  │ │               │ │             │ │
     │ └────────┬───────┘ └──────┬────────┘ └──────┬──────┘ │
     └──────────┼────────────────┼─────────────────┼────────┘
                └────────────────┼─────────────────┘
                                 │
                                 ▼
     ┌──────────────────────────────────────────────────────┐
     │                  3.  DISPATCH                        │
     │              (call resolution)                       │
     │                                                      │
     │  ┌────────────┐  ┌──────────────┐  ┌──────────────┐  │
     │  │  Static    │  │   Runtime    │  │    Test      │  │
     │  │            │  │   Config     │  │   Handler    │  │
     │  │ compile-   │  │              │  │              │  │
     │  │ time       │  │ call_config  │  │ call/4       │  │
     │  │ inlined    │  │ /4           │  │              │  │
     │  │ direct     │  │              │  │ NimbleOwner- │  │
     │  │ call       │  │ App.get_env  │  │ ship lookup  │  │
     │  │            │  │ → apply/3    │  │ → handler    │  │
     │  │ (zero      │  │              │  │              │  │
     │  │ overhead)  │  │              │  │              │  │
     │  └─────┬──────┘  └───────┬──────┘  └───────┬──────┘  │
     └────────┼─────────────────┼─────────────────┼─────────┘
              └─────────────────┼─────────────────┘
                                │
                                ▼
     ┌──────────────────────────────────────────────────────┐
     │              4.  IMPLEMENTATION                      │
     │            (actual execution)                        │
     │                                                      │
     │  ┌──────────────────────────┐  ┌───────────────────┐ │
     │  │   Production Module      │  │   Test Double     │ │
     │  │                          │  │                   │ │
     │  │   @behaviour Contract    │  │  Module handler   │ │
     │  │   def operation(...)     │  │  Stateless fn     │ │
     │  │                          │  │  Stateful fn      │ │
     │  │   e.g. MyApp.EctoRepo    │  │  Double.expect/   │ │
     │  │                          │  │  fallback/stub    │ │
     │  └──────────────────────────┘  └───────────────────┘ │
     └──────────────────────────────────────────────────────┘

  ── Static path (prod, compile-time config):  Facade → Static → Production
  ── Config path (prod, no compile config):    Facade → Config → Production
  ── Test path (test env):                     Facade → Test   → Test Double
  ── DynamicFacade test path:                  Facade → Test   → Test Double
  ── DynamicFacade no-handler (passthrough):   Facade → (handler not found)
                                                → original module
```

## Layer 1: Contract

The contract is the type-level interface — it defines _what_ operations exist and
their type signatures, but not _how_ they're implemented.

### defcallback (explicit contract)

Use `defcallback` from `DoubleDown.Contract` when you control the interface.
It generates `@behaviour` + `@callback` + introspection metadata
(`__callbacks__/0`) from a single macro call.  `defcallback` takes the same parameters as @callback, but unlike _requires_ named
parameters (`id :: String.t()`) — and these appear in generated `@spec` and `@doc`
on the facade, giving LSP-friendly hover docs at every call site.

```elixir
defmodule MyApp.Todos do
  use DoubleDown.Contract

  defcallback get_todo(tenant_id :: String.t(), id :: String.t()) ::
    {:ok, Todo.t()} | {:error, term()}

  defcallback list_todos(tenant_id :: String.t()) :: [Todo.t()]
end
```

### @behaviour (explicit contract - existing @behaviour module)

Any existing Elixir `@behaviour` module works as a contract — see
`DoubleDown.BehaviourFacade`.  Use this for behaviours you don't control:
third-party libraries, existing codebase behaviours, or any module with
`@callback` declarations.

### Implicit (DynamicFacade)

With `DoubleDown.DynamicFacade`, no separate contract module exists at
all — the target module's public API implicitly becomes the contract.
The module is shimmed at test time via bytecode replacement, so any call
can be intercepted.

## Layer 2: Facade

The facade is what callers actually invoke.  It generates wrapper functions for
each contract operation that delegate to the dispatch layer.

### ContractFacade

For `defcallback` contracts.  Supports combined contract + facade
(one module - the default) or separate modules.  Options control 
dispatch behaviour at compile time.

```elixir
# Combined contract + facade
defmodule MyApp.Todos do
  use DoubleDown.ContractFacade, otp_app: :my_app

  defcallback get_todo(id :: String.t()) :: {:ok, Todo.t()} | {:error, term()}
end
```

### BehaviourFacade

For vanilla `@behaviour` modules.  The behaviour must be compiled before the
facade — they live in separate modules.

```elixir
defmodule MyApp.Todos.Facade do
  use DoubleDown.BehaviourFacade, behaviour: MyApp.Todos.Behaviour, otp_app: :my_app
end
```

### DynamicFacade

Mimic-style bytecode interception.  Call `setup/1` in `test_helper.exs` before
`ExUnit.start()`.  The module is backed up and replaced with a dispatch shim.
Tests that _don't_ install a handler get the original module's behaviour.

```elixir
# test/test_helper.exs
DoubleDown.DynamicFacade.setup(MyApp.EctoRepo)
ExUnit.start()
```

## Layer 3: Dispatch

Dispatch resolves which implementation handles a given call.  The resolution
strategy is selected at compile time and/or call time per-facade via
options.

### Static dispatch

When `static_dispatch?: true` and the implementation is available in config at
compile time, the facade function calls the implementation module directly.
No `Application.get_env`, no `NimbleOwnership` — the call inlines to identical
bytecode as calling the impl directly.  This is the default in `:prod`.

### Runtime config dispatch

`DoubleDown.Dispatch.call_config/4` reads `Application.get_env(otp_app, contract)[:impl]`
and calls `apply(impl, operation, args)`.  Used in production when static
dispatch isn't available, and in non-prod when `test_dispatch?: false`.

### Test handler dispatch

`DoubleDown.Dispatch.call/4` checks NimbleOwnership for a process-scoped test
handler before falling back to config.  This is the default in non-prod
environments — it's what makes `DoubleDown.Double.fallback/2`, `expect/3`, etc.
work in tests.

### DynamicFacade dispatch

`DynamicFacade.dispatch/3` checks NimbleOwnership for a test handler, falling
back to the original (backed-up) module.  This is always the path for
a DynamicFacade (which is only ever set up under test) — there's no config-based resolution because there's no contract
module to configure.

## Layer 4: Implementation

The implementation is the module or function that actually executes the
operation.

### Production

A module implementing the contract's `@behaviour`, wired via config:

```elixir
# config/config.exs
config :my_app, MyApp.Todos, impl: MyApp.Todos.Ecto
```
If this config is available at compile-time, and `static_dispatch?: true`
(the default) then `ContractFacade` and `BehaviourFacade` will use the
compile-time target and inline calls - there will be zero
runtime overhead for the contract boundary.

### Test doubles

Installed via `DoubleDown.Double` (recommended) or `DoubleDown.Testing`:

- **Module handler** — delegates to a module via `@behaviour`
- **Stateless handler** — `fn contract, operation, args -> result end`
- **Stateful handler** — `fn contract, operation, args, state -> {result, new_state} end`
  (4-arity) or `fn contract, operation, args, state, all_states -> {result, new_state} end`
  (5-arity, with cross-contract state access)

See `DoubleDown.Double` for the recommended API and
`DoubleDown.Dispatch.StatefulHandler` for the behaviour.

<!-- nav:footer:start -->

---

[< DoubleDown](../README.md) | [Up: Guides](../README.md) | [Index](../README.md) | [Dispatch >](dispatch.md)
<!-- nav:footer:end -->
