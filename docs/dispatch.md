# Dispatch

<!-- nav:header:start -->
[< Boundaries](boundaries.md) | [Up: Guides](../README.md) | [Index](../README.md) | [Stateful Doubles >](stateful-doubles.md)
<!-- nav:header:end -->

Dispatch is the uniform call-resolution mechanism that sits between every
facade and its implementation. All three facade types (`ContractFacade`,
`BehaviourFacade`, `DynamicFacade`) use the same dispatch infrastructure —
there is one mechanism, one set of handler types, one logging system.

## Dispatch paths

The dispatch path for each facade is selected at **compile time** via the
`:test_dispatch?` and `:static_dispatch?` options:

```
                         ┌─────────────────┐
                         │  Function call   │
                         │  facade.op(args) │
                         └────────┬────────┘
                                  │
                    ┌─────────────┴─────────────┐
                    │  test_dispatch? true?     │
                    │  (default: not prod)      │
                    └─────────────┬─────────────┘
                     yes          │          no
                ┌────────────────┴────────────────┐
                ▼                                 ▼
     ┌──────────────────┐              ┌──────────────────┐
     │  call/4          │              │  static_dispatch │
     │                  │              │  ? true?         │
     │  1. NimbleOwner- │              │  (default: prod) │
     │     ship lookup   │              └────────┬─────────┘
     │  2. App.get_env   │           yes         │        no
     │  3. Raise         │           ▼           │        ▼
     └──────────────────┘   ┌────────────┐  ┌──────────────┐
                            │  Inlined   │  │ call_config  │
                            │  direct    │  │ /4           │
                            │  call to   │  │              │
                            │  impl      │  │ App.get_env  │
                            │  (zero     │  │ → apply/3    │
                            │  overhead) │  │ → Raise      │
                            └────────────┘  └──────────────┘
```

### Static dispatch

When `static_dispatch?: true` (default in `:prod`) and the implementation is
available in config at compile time, the facade generates inlined direct
function calls to the implementation module. No `NimbleOwnership`, no
`Application.get_env` — the call compiles to identical bytecode as calling
the impl directly. Falls back to `call_config/4` if the config isn't
available at compile time.

### Runtime config dispatch

`DoubleDown.Dispatch.call_config/4` reads
`Application.get_env(otp_app, contract)[:impl]` and calls
`apply(impl, operation, args)`. Used in production when static dispatch
isn't available, and when `test_dispatch?: false`.

### Test handler dispatch

`DoubleDown.Dispatch.call/4` checks NimbleOwnership for a process-scoped
test handler, falling back to config. This is the default in non-prod
environments and is what makes `DoubleDown.Double` work.

### DynamicFacade dispatch

`DynamicFacade.dispatch/3` is a parallel dispatch path — it checks
NimbleOwnership for a test handler, falling back to the original
(backed-up) module. There is no config-based resolution because there is
no contract module to configure.

## Handler types

When `call/4` resolves a test handler, it matches one of three handler
types stored in NimbleOwnership:

| Handler | Installed via | Dispatch logic |
|---------|--------------|----------------|
| **Module** | `Double.fallback(contract, module)` | `apply(impl, operation, args)` |
| **Stateless** | `Double.fallback(contract, fn)` | `fun.(contract, operation, args)` |
| **Stateful** | `Double.fallback(contract, fn, state)` | `fun.(contract, operation, args, state)` — runs inside `NimbleOwnership.get_and_update` for atomic state updates |

All three return `{contract, operation, normalize_args(args)}` from
`key/3` and support `Defer` for re-entrant dispatch.

### 5-arity stateful handlers

Stateful handlers can also accept a 5th argument — a read-only snapshot of
all contract states — for cross-contract state access:

```
# 4-arity (default)
fn contract, operation, args, state -> {result, new_state} end

# 5-arity — cross-contract state
fn contract, operation, args, state, all_states -> {result, new_state} end
```

The `all_states` map is keyed by contract module. Handlers can inspect
another contract's state but only update their own via the return value.

## Defer — re-entrant dispatch

Stateful handler functions run inside `NimbleOwnership.get_and_update`,
which holds a lock on the ownership GenServer. If a handler calls another
facade directly, it deadlocks — the second call re-enters the same
GenServer.

`DoubleDown.Dispatch.Defer` solves this. Return a `Defer` from a handler
and the deferred function runs after the lock is released:

```elixir
{DoubleDown.Dispatch.Defer.new(fn ->
  # Runs outside the lock — safe to call other facades
  {:ok, record} = MyApp.Repo.insert(changeset)
  record
end), new_state}
```

`DoubleDown.Double.defer/1` is a convenience wrapper.

## Public API

| Function | Purpose |
|----------|---------|
| `call/4` | Test-aware dispatch (NimbleOwnership → config) |
| `call_config/4` | Config-only dispatch |
| `key/3` | Canonical key for test stub matching (normalized args) |
| `get_state/1` | Read current stateful handler state for a contract |
| `restore_state/3` | Replace a contract's stateful handler state |
| `handler_active?/1` | Check if a test handler is installed for a contract |

<!-- nav:footer:start -->

---

[< Boundaries](boundaries.md) | [Up: Guides](../README.md) | [Index](../README.md) | [Stateful Doubles >](stateful-doubles.md)
<!-- nav:footer:end -->
