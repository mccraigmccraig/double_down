# DoubleDown

[![Test](https://github.com/mccraigmccraig/double_down/actions/workflows/test.yml/badge.svg)](https://github.com/mccraigmccraig/double_down/actions/workflows/test.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/double_down.svg)](https://hex.pm/packages/double_down)
[![Documentation](https://img.shields.io/badge/documentation-gray)](https://hexdocs.pm/double_down/)

Builds on the Mox pattern — generates behaviours and dispatch facades
from `defcallback` declarations — and adds stateful test doubles powerful
enough to test Ecto.Repo operations without a database.

## Why DoubleDown?

DoubleDown extends the Mox pattern:

- **Explicit contracts, zero boilerplate** — Jose Valim's
  [Mocks and explicit contracts](https://dashbit.co/blog/mocks-and-explicit-contracts)
  makes the case for clear boundaries between components, but the
  Mox pattern requires a contract behaviour, a dispatch facade, and
  config wiring for each boundary. `defcallback` generates all three
  from a single declaration — the behaviour, facade, and typespecs
  are always in sync.
- **Zero-cost production dispatch** — in production, facades are
  compiled to inlined direct function calls to the configured
  implementation. `MyContract.do_thing(args)` compiles to exactly
  the same bytecode as `DirectImpl.do_thing(args)` — the facade
  disappears entirely after BEAM inlining. Contract boundaries are
  a pure architectural decision with no runtime cost.
- **Stubs are not always enough** — modelling stateful dependencies
  like a database with plain mocks is verbose and fragile, so most
  projects just hit the real DB and accept the speed penalty.
  DoubleDown's stateful fakes maintain in-memory state with atomic
  updates, enabling read-after-write consistency without
  a database — fast enough for property-based testing.
- **Fakes with expectations** — testing "what happens when the second
  insert fails with a constraint violation?" means either a real DB
  or a mock that responds to each Repo call individually — verbose and
  brittle. DoubleDown lets you layer expects over a stateful fake:
  the first insert writes to an in-memory store, the second returns
  an error, and subsequent reads find the first record.
- **Dispatch logging** — when test doubles do real computation
  (changeset validation, PK autogeneration, timestamps), the results
  are worth asserting on. DoubleDown logs the full
  `{contract, operation, args, result}` tuple for every call, and
  `DoubleDown.Log` provides structured pattern matching over those
  logs.

## What DoubleDown provides

### System boundaries (the Mox pattern, automated)

| Feature                | Description                                                     |
|------------------------|-----------------------------------------------------------------|
| `defcallback` declarations | Typed function signatures with parameter names and return types |
| Contract behaviour generation   | Standard `@behaviour` + `@callback` — fully Mox-compatible            |
| Dispatch facades       | Config-dispatched caller functions, generated automatically     |
| Zero-cost static dispatch | Inlined direct calls in production — no overhead vs calling the impl directly |
| LSP-friendly           | `@doc` and `@spec` on every generated function                  |

### Test doubles (beyond Mox)

| Feature                            | Description                                                                |
|------------------------------------|----------------------------------------------------------------------------|
| Mox-style expect/stub              | `DoubleDown.Double` — ordered expectations, call counting, `verify!`      |
| Stateful fakes                     | In-memory state with atomic updates via NimbleOwnership                    |
| Expect + fake composition          | Layer expects over a stateful fake for failure simulation                  |
| `:passthrough` expects             | Count calls without changing behaviour                                     |
| Stubs and fakes as fallbacks       | Dispatch priority chain: expects > stubs > fake > raise                    |
| Dispatch logging                   | Record `{contract, op, args, result}` for every call                       |
| Structured log matching            | `DoubleDown.Log` — pattern-match on logged results                         |
| Built-in Ecto Repo                 | Full Ecto.Repo contract with `Repo.Test` and `Repo.InMemory` fakes        |
| Async-safe                         | Process-scoped isolation via NimbleOwnership, `async: true` out of the box |

## Quick example

### Define contracts

Use the built-in `DoubleDown.Repo` contract for database operations,
and define domain-specific contracts for business logic:

```elixir
# Repo facade — wraps your Ecto Repo
defmodule MyApp.Repo do
  use DoubleDown.Facade, contract: DoubleDown.Repo, otp_app: :my_app
end

# Domain contract — queries specific to your domain
defmodule MyApp.Todos do
  use DoubleDown.Facade, otp_app: :my_app

  defcallback active_todos(tenant_id :: String.t()) :: [Todo.t()]
  defcallback todo_exists?(tenant_id :: String.t(), title :: String.t()) :: boolean()
end
```

### Write orchestration code

Orchestration code uses both contracts — Repo for writes, Todos for
domain queries:

```elixir
defmodule MyApp.CreateTodo do
  def call(tenant_id, params) do
    if MyApp.Todos.todo_exists?(tenant_id, params.title) do
      {:error, :duplicate}
    else
      MyApp.Repo.insert(Todo.changeset(%Todo{tenant_id: tenant_id}, params))
    end
  end
end
```

### Wire up production implementations

```elixir
# config/config.exs
config :my_app, DoubleDown.Repo, impl: MyApp.EctoRepo
config :my_app, MyApp.Todos, impl: MyApp.Todos.Ecto
```

### Test without a database

Start the ownership server in `test/test_helper.exs`:

```elixir
DoubleDown.Testing.start()
```

Test the orchestration with fakes and stubs — no database, full
async isolation:

```elixir
setup do
  # InMemory Repo for writes — read-after-write consistency
  DoubleDown.Double.fake(DoubleDown.Repo, DoubleDown.Repo.InMemory)

  # Stub domain queries
  DoubleDown.Double.stub(MyApp.Todos, fn
    :active_todos, [_tenant] -> []
    :todo_exists?, [_tenant, _title] -> false
  end)

  :ok
end

test "creates a todo when no duplicate exists" do
  assert {:ok, todo} = MyApp.CreateTodo.call("t1", %{title: "Ship it"})
  assert todo.tenant_id == "t1"

  # Read-after-write: InMemory serves from store
  assert ^todo = MyApp.Repo.get(Todo, todo.id)
end

test "rejects duplicate todos" do
  # Override the stub for this specific test
  DoubleDown.Double.expect(MyApp.Todos, :todo_exists?, fn [_tenant, _title] -> true end)

  assert {:error, :duplicate} = MyApp.CreateTodo.call("t1", %{title: "Existing"})
  DoubleDown.Double.verify!()
end
```

### Testing failure scenarios

Layer expects over the InMemory Repo to simulate database failures:

```elixir
setup do
  DoubleDown.Double.fake(DoubleDown.Repo, DoubleDown.Repo.InMemory)
  DoubleDown.Double.stub(MyApp.Todos, fn :todo_exists?, [_, _] -> false end)
  :ok
end

test "handles constraint violation on insert" do
  # First insert fails with constraint error
  DoubleDown.Double.expect(DoubleDown.Repo, :insert, fn [changeset] ->
    {:error, Ecto.Changeset.add_error(changeset, :title, "taken")}
  end)

  assert {:error, cs} = MyApp.CreateTodo.call("t1", %{title: "Conflict"})
  assert {"taken", _} = cs.errors[:title]

  # Second call succeeds — expect consumed, InMemory handles it
  assert {:ok, _} = MyApp.CreateTodo.call("t1", %{title: "Conflict"})
end
```

## Documentation

- **[Getting Started](docs/getting-started.md)** — contracts, facades,
  dispatch resolution, terminology
- **[Testing](docs/testing.md)** — Double expect/stub/fake, stateful
  responders, cross-contract state access
- **[Logging](docs/logging.md)** — dispatch logging, Log matchers,
  structured log assertions
- **[Process Sharing](docs/process-sharing.md)** — async safety, allow,
  global mode, supervision tree testing
- **[Repo](docs/repo.md)** — built-in Ecto Repo contract, `Repo.Test`,
  `Repo.InMemory`, failure scenario testing
- **[Migration](docs/migration.md)** — incremental adoption, coexisting
  with direct Ecto.Repo calls

## Installation

Add `double_down` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:double_down, "~> 0.25"}
  ]
end
```

Ecto is an optional dependency — add it to your own deps if you want
the built-in Repo contract.

## Relationship to Skuld

DoubleDown extracts the contract and test double system from
[Skuld](https://github.com/mccraigmccraig/skuld) (algebraic effects
for Elixir) into a standalone library. You get typed contracts,
async-safe test doubles, and dispatch logging without needing Skuld's
effect system. Skuld depends on DoubleDown and layers effectful dispatch
on top.

## License

MIT License - see [LICENSE](LICENSE) for details.
