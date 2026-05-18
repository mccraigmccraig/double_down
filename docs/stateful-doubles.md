# Stateful Doubles

Stateless doubles (stubs, module mocks) return canned responses — they
have no memory. Stateful doubles maintain in-memory state with atomic
updates, enabling read-after-write consistency and realistic behaviour
without a database.

## How state works

State lives inside `NimbleOwnership`, keyed by contract module. Each
handler is stored as a `DoubleDown.Dispatch.HandlerMeta.Stateful` struct
with an inline `:state` field. The dispatch machinery reads and writes
this state atomically via `NimbleOwnership.get_and_update` — every
`{result, new_state}` return from a handler is a single atomic operation.

Process isolation is handled by NimbleOwnership — each test process has
its own set of handlers and state, so `async: true` works without
cross-test interference.

## Handler arities

Stateful handlers come in two arities:

### 4-arity — own state only

```elixir
fn contract, operation, args, state -> {result, new_state} end
```

The handler receives its contract's current state and returns a new state.
This is the default for most fakes.

### 5-arity — cross-contract state access

```elixir
fn contract, operation, args, state, all_states ->
  {result, new_state}
end
```

The 5th argument is a read-only snapshot of **all** contract states, keyed
by contract module. This enables the two-contract pattern where a queries
handler reads from the Repo's in-memory store:

```elixir
%{
  DoubleDown.Repo => %{User => %{1 => %User{...}}},
  MyApp.Queries => %{...},
}
```

A sentinel key (`DoubleDown.Contract.GlobalState`) detects accidental
returns of the global map — returning `all_states` instead of your own
state raises `ArgumentError`.

The global snapshot is taken before the `get_and_update` call — it's a
point-in-time view, not a live reference. Handlers can only update their
own contract's state via the return value.

## CanonicalHandlerState

When stateful handlers are installed via `DoubleDown.Double`,
Double wraps the user's state in a `CanonicalHandlerState` struct:

```
%CanonicalHandlerState{
  fallback_state: user_state,     # The user's domain state
  expects: [...],                 # Ordered expect queue
  stubs: %{op => [...]},         # Per-operation stubs
  per_op_fakes: %{op => handler}  # Per-operation fakes
}
```

This is an internal detail — user code only sees `fallback_state`
(extracted by `get_state/1`). The wrapping is what enables layered
expects/stubs/fakes over a stateful fallback: each sub-system (expect
queue, stub registry, fallback function) is tracked within the same
canonical state, allowing dispatch priority resolution inside a single
`get_and_update` call.

## State threading

State threads through sequenced operations:

```elixir
# Fallback writes to state
DoubleDown.Double.fallback(Contract, fn _c, :put, [k, v], state ->
  {Map.put(state, k, v), Map.put(state, k, v)}
end, %{})

# Stateful expect reads what the fallback wrote
DoubleDown.Double.expect(Contract, :get, fn [k], state ->
  {Map.get(state, k), state}
end)
```

After a 1-arity expect fires (stateless), the state is unchanged — the
next expect sees whatever state the fallback left it in.

## StatefulHandler behaviour

For reusable stateful fakes, implement `DoubleDown.Dispatch.StatefulHandler`:

```elixir
defmodule MyApp.InMemoryStore do
  @behaviour DoubleDown.Dispatch.StatefulHandler

  @impl true
  def new(seed, _opts), do: seed

  @impl true
  def dispatch(_contract, :get, [id], state), do: {Map.get(state, id), state}
  def dispatch(_contract, :put, [id, val], state), do: {:ok, Map.put(state, id, val)}
end
```

Implement either `dispatch/4` or `dispatch/5` (or both — `/5` takes
priority when both are defined). Modules implementing this behaviour can
be used directly with `Double.fallback`:

```elixir
DoubleDown.Double.fallback(MyContract, MyApp.InMemoryStore)
```

## StatelessHandler behaviour

For reusable stateless stubs, implement
`DoubleDown.Dispatch.StatelessHandler`:

```elixir
defmodule MyApp.TestStore do
  @behaviour DoubleDown.Dispatch.StatelessHandler

  @impl true
  def new(fallback_fn, _opts) do
    fn contract, operation, args ->
      case {operation, args} do
        {:get, [id]} -> %{id: id}
        _ when is_function(fallback_fn) -> fallback_fn.(contract, operation, args)
        _ -> raise "unhandled: #{operation}/#{length(args)}"
      end
    end
  end
end
```

`new/2` receives an optional fallback function and options, and returns a
3-arity function `(contract, operation, args) -> result`. Used with
`Double.fallback` by module name:

```elixir
DoubleDown.Double.fallback(MyContract, MyApp.TestStore)
```

If a fallback function is also supplied, it's passed as the first argument
to `new/2`:

```elixir
DoubleDown.Double.fallback(MyContract, MyApp.TestStore,
  fn _contract, :all, [User] -> [] end
)
```
