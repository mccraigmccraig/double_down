# Double API

<!-- nav:header:start -->
[< Stateful Doubles](stateful-doubles.md) | [Up: Guides](../README.md) | [Index](../README.md) | [Repo >](repo.md)
<!-- nav:header:end -->

`DoubleDown.Double` is the primary API for setting up test doubles. Every
function takes a **contract module** as its first argument — this is the
same module used in config and facade setup, regardless of facade type:

```elixir
# Works identically across all three facade types
DoubleDown.Double.fallback(MyContract, handler)
DoubleDown.Double.expect(MyContract, :op, responder)
```

Each call writes directly to NimbleOwnership, and all functions return
the contract module for piping.

## Fallback

A fallback handles any operation without a specific `expect` or `stub`.
Setting a newer fallback replaces the previous one.

### Module fallback

Delegates to a module implementing the contract's behaviour. Override
specific operations with expects while the rest go through the module:

```elixir
MyContract
|> DoubleDown.Double.fallback(MyContract.Impl)
|> DoubleDown.Double.expect(:risky_op, fn [_] -> {:error, :timeout} end)
```

Module fallbacks run in the calling process via `Defer`, so they work with
Ecto sandboxes and other process-scoped resources. As with Mimic, internal
calls within the module that don't go through the facade are not
intercepted by expects/stubs.

For DynamicFacade modules, `DoubleDown.Double.dynamic/1` is a convenience
that installs a module fallback pointing to the original (now renamed)
module. After `DynamicFacade.setup(Module)`, the original bytecode lives at
`Module.__dd_original__` and the shim dispatches through the facade
machinery. `dynamic/1` wires the fallback to the backup module so the shim
delegates to the original implementation when no expects or stubs match:

### Stateless fallback

A 3-arity function `(contract, operation, args) -> result`:

```elixir
DoubleDown.Double.fallback(MyContract, fn _contract, operation, args ->
  case {operation, args} do
    {:get, [id]} -> {:ok, %{id: id}}
    {:list, []} -> []
  end
end)
```

Module-based stateless handlers (like `Repo.Stateless`) are used by name:

```elixir
DoubleDown.Double.fallback(DoubleDown.Repo, DoubleDown.Repo.Stateless)
```

### Stateful fallback

A 4-arity or 5-arity function with initial state. Enables read-after-write
consistency and atomic state updates:

```elixir
# 4-arity — own state only
DoubleDown.Double.fallback(Contract, fn _c, :get, [id], state ->
  {Map.get(state, id), state}
end, %{})

# 5-arity — cross-contract state access
DoubleDown.Double.fallback(Contract, fn _c, :get, [id], state, all_states ->
  repo = Map.get(all_states, DoubleDown.Repo, %{})
  {Map.get(repo, id), state}
end, %{})
```

Module-based stateful handlers are used by name, optionally with seed data
and options:

```elixir
DoubleDown.Double.fallback(DoubleDown.Repo, DoubleDown.Repo.InMemory)
DoubleDown.Double.fallback(DoubleDown.Repo, DoubleDown.Repo.InMemory,
  [%User{id: 1, name: "Alice"}],
  fallback_fn: fn _contract, :all, [User], state -> Map.values(state[User]) end
)
```

### Dynamic fallback

For DynamicFacade modules only — see [Module fallback](#module-fallback) above
for how `dynamic/1` works under the hood. Shorthand for wiring the shim to
the original module's behaviour:

```elixir
SomeClient
|> DoubleDown.Double.dynamic()
|> DoubleDown.Double.expect(:fetch, fn [_] -> {:error, :not_found} end)
```

## Expect

Expectations are consumed in order and verified by `verify!/0`.

```elixir
MyContract
|> DoubleDown.Double.expect(:get, fn [id] -> {:ok, %{id: id}} end)
|> DoubleDown.Double.expect(:get, fn [_] -> {:error, :not_found} end)

# First call returns {:ok, ...}, second returns {:error, :not_found}
```

### Repeated expectations

```elixir
DoubleDown.Double.expect(MyContract, :ping, fn [_] -> :pong end, times: 3)
```

### Passthrough expects

Delegate to the fallback while still consuming the expect for `verify!`
counting:

```elixir
DoubleDown.Double.expect(MyContract, :get, :passthrough, times: 2)
```

### Stateful expects

When a stateful fallback is configured, expects can be 2-arity (own state)
or 3-arity (own state + cross-contract snapshot):

```elixir
# 1-arity — stateless (default)
fn [args] -> result end

# 2-arity — reads/modifies the fallback's state
fn [args], state -> {result, new_state} end

# 3-arity — same + read-only all_states snapshot
fn [args], state, all_states -> {result, new_state} end
```

`DoubleDown.Double.passthrough()` can be returned from a stateful responder
to delegate to the fallback without duplicating its logic.

### Dispatch priority

Expects > per-operation stubs > per-operation fakes > fallback > raise.

## Stub

Like `expect` but applies to every call indefinitely — not consumed, not
verified:

```elixir
DoubleDown.Double.stub(MyContract, :list, fn [_] -> [] end)
```

Per-operation stubs take priority over the fallback but are overridden by
expects. Stateful stubs (2/3-arity) are supported when a stateful fallback
is configured.

## Fakes (per-operation)

Override a single operation with a stateful handler while the rest of the
contract delegates to the fallback. A stateful fallback must be configured
first. Available as 2-arity and 3-arity:

```elixir
DoubleDown.Repo
|> DoubleDown.Double.fallback(DoubleDown.Repo.InMemory)
|> DoubleDown.Double.fake(:insert, fn [changeset], state ->
  existing = state |> Map.get(User, %{}) |> Map.values() |> Enum.map(& &1.email)
  if Ecto.Changeset.get_field(changeset, :email) in existing do
    {{:error, Ecto.Changeset.add_error(changeset, :email, "taken")}, state}
  else
    DoubleDown.Double.passthrough()
  end
end)
```

Unlike expects, fakes are permanent — they handle every call, not just
one.

## Passthrough and Defer

Two return sentinels for special dispatch behaviour:

**`DoubleDown.Double.passthrough()`** — delegates the call to the
fallback/fake. Usable from stateful expects, stubs, and fakes. The expect
is consumed for `verify!` counting; the result comes from the fallback.

**`DoubleDown.Double.defer(fn -> ... end)`** — runs the function after
the NimbleOwnership lock is released. Necessary when a handler needs to
call another facade (which would otherwise deadlock). The deferred
function's return value is what the caller receives.

## Verification

`verify!/0` checks that all expectations in the current process have been
consumed. Stubs and fakes are not checked — zero calls is valid.

```elixir
# Inline — explicit
test "creates a todo" do
  # ...
  DoubleDown.Double.verify!()
end

# Setup hook — automatic
setup :verify_on_exit!

# Equivalent:
setup do
  DoubleDown.Double.verify_on_exit!()
end
```

`verify_on_exit!/0` registers an `on_exit` callback that runs `verify!`,
so you can't forget.

## Process sharing

Test doubles are process-scoped. `Task.async` children inherit doubles
automatically via `$callers`. Other processes need explicit sharing:

```elixir
DoubleDown.Double.allow(MyContract, self(), agent_pid)
DoubleDown.Double.allow(MyContract, fn -> GenServer.whereis(MyWorker) end)
```

For supervision trees where pids aren't accessible, use global mode
(`async: false` required):

```elixir
setup do
  DoubleDown.Testing.set_mode_to_global()
  on_exit(fn -> DoubleDown.Testing.set_mode_to_private() end)
  :ok
end
```

## Log integration

Double and `DoubleDown.Log` work together — Double for controlling return
values and counting calls, Log for asserting on what actually happened:

```elixir
setup do
  MyContract
  |> DoubleDown.Double.expect(:create, fn [p] -> {:ok, struct!(Thing, p)} end)

  DoubleDown.Testing.enable_log(MyContract)
  :ok
end

test "logs the create call" do
  MyModule.do_work(params)

  DoubleDown.Double.verify!()

  DoubleDown.Log.match(:create, fn {_, _, _, {:ok, %Thing{}}} -> true end)
  |> DoubleDown.Log.verify!(MyContract)
end
```

<!-- nav:footer:start -->

---

[< Stateful Doubles](stateful-doubles.md) | [Up: Guides](../README.md) | [Index](../README.md) | [Repo >](repo.md)
<!-- nav:footer:end -->
