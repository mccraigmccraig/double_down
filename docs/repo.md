# Repo

<!-- nav:header:start -->
[< Double API](double-api.md) | [Up: Guides](../README.md) | [Index](../README.md) | [Changelog >](../CHANGELOG.md)
<!-- nav:header:end -->

DoubleDown ships a complete `Ecto.Repo` contract and three test doubles,
letting you replace the database with an in-memory store in tests while
keeping your existing ExMachina factories and `Ecto.Multi` transactions.

## The contract

`DoubleDown.Repo` defines the full `Ecto.Repo` surface — writes, reads,
aggregates, associations, streaming, and transactions:

| Category | Operations |
|----------|-----------|
| Writes | `insert`, `update`, `delete`, `insert_or_update` + bang variants |
| Bulk | `insert_all`, `update_all`, `delete_all` |
| PK reads | `get`, `get!` |
| Non-PK reads | `get_by`, `get_by!`, `one`, `one!`, `all`, `all_by`, `exists?`, `aggregate` |
| Associations | `preload`, `load`, `reload`, `reload!` |
| Streaming | `stream` |
| Transactions | `transact`, `rollback`, `in_transaction?` |
| Raw SQL | `query`, `query!` |

## Creating a Repo facade

### With ContractFacade (recommended)

```elixir
defmodule MyApp.Repo do
  use DoubleDown.ContractFacade, contract: DoubleDown.Repo, otp_app: :my_app
end
```

```elixir
# config/config.exs
config :my_app, DoubleDown.Repo, impl: MyApp.EctoRepo
```

With the default `:static_dispatch?` setting, production dispatch compiles
away entirely — `MyApp.Repo.insert(changeset)` produces identical bytecode
to `MyApp.EctoRepo.insert(changeset)`.

### With DynamicFacade

If your Repo module has custom functions beyond the standard API, or you
don't want a facade module:

```elixir
# test/test_helper.exs
DoubleDown.DynamicFacade.setup(MyApp.EctoRepo)
ExUnit.start()
```

Then in tests, use your Ecto Repo module directly as the contract:

```elixir
DoubleDown.Double.fallback(MyApp.EctoRepo, DoubleDown.Repo.InMemory)
```

## Test doubles

| Double | Type | Reads | Best for |
|--------|------|-------|----------|
| `Repo.Stateless` | Stateless stub | Fallback only | Fire-and-forget writes |
| `Repo.InMemory` | Closed-world fake | All bare-schema reads | ExMachina, most tests |
| `Repo.OpenInMemory` | Open-world fake | PK reads only | Fine-grained fallback control |

All three validate changesets (returning `{:error, changeset}` on invalid),
autogenerate primary keys and timestamps via Ecto schema metadata, accept
both changesets and bare structs, and support `Ecto.Multi` transactions.

### Repo.Stateless

Writes succeed but store nothing. Reads raise unless you supply a fallback
function. Best for simple command-style functions:

```elixir
DoubleDown.Double.fallback(DoubleDown.Repo, DoubleDown.Repo.Stateless)
DoubleDown.Double.expect(DoubleDown.Repo, :insert, fn [changeset] ->
  {:error, Ecto.Changeset.add_error(changeset, :email, "taken")}
end)
```

### Repo.InMemory (recommended)

Closed-world semantics — the in-memory store is the complete truth. If a
record isn't in the store, it doesn't exist. All bare-schema reads
(`get`, `get_by`, `all`, `exists?`, `aggregate`) work without a fallback.

```elixir
setup do
  DoubleDown.Double.fallback(DoubleDown.Repo, DoubleDown.Repo.InMemory)
  :ok
end

test "insert then read back" do
  {:ok, user} = MyApp.Repo.insert(User.changeset(%{name: "Alice"}))
  assert ^user = MyApp.Repo.get(User, user.id)
  assert [^user] = MyApp.Repo.all(User)
end
```

Seed data can be passed as the third argument:

```elixir
DoubleDown.Double.fallback(DoubleDown.Repo, DoubleDown.Repo.InMemory,
  [%User{id: 1, name: "Alice"}])
```

`Ecto.Query` operations that InMemory can't evaluate natively delegate to
an optional `fallback_fn`:

```elixir
DoubleDown.Double.fallback(DoubleDown.Repo, DoubleDown.Repo.InMemory, [],
  fallback_fn: fn
    _contract, :all, [%Ecto.Query{}], _state -> []
  end
)
```

### Repo.OpenInMemory

Open-world semantics — the store may be incomplete. PK reads hit the store
first then fall through to a user-supplied fallback. All other reads
always go through the fallback. Use when you need fine-grained control
over which reads are served from state:

```elixir
DoubleDown.Double.fallback(DoubleDown.Repo, DoubleDown.Repo.OpenInMemory, [],
  fallback_fn: fn
    _contract, :get_by, [User, [email: email]], _state -> %User{email: email}
    _contract, :all, [User], state -> state |> Map.get(User, %{}) |> Map.values()
  end
)
```

## ExMachina integration

Point ExMachina at your Repo facade (not your Ecto Repo):

```elixir
defmodule MyApp.Factory do
  use ExMachina.Ecto, repo: MyApp.Repo

  def user_factory do
    %User{name: sequence(:name, &"User #{&1}"), email: sequence(:email, &"user#{&1}@example.com")}
  end
end
```

With `Repo.InMemory` installed, factory inserts land in the in-memory
store and all bare-schema reads find them:

```elixir
setup do
  DoubleDown.Double.fallback(DoubleDown.Repo, DoubleDown.Repo.InMemory)
  :ok
end

test "factory-inserted records are readable" do
  insert(:user, name: "Alice")
  insert(:user, name: "Bob")

  assert [_, _] = MyApp.Repo.all(User)
  assert %User{name: "Alice"} = MyApp.Repo.get_by(User, name: "Alice")
  assert 2 = MyApp.Repo.aggregate(User, :count, :id)
end
```

## Transactions and rollback

`transact/2` mirrors `Ecto.Repo.transact/2` — accepts a function or an
`Ecto.Multi`:

```elixir
# Function
MyApp.Repo.transact(fn ->
  {:ok, user} = MyApp.Repo.insert(user_changeset)
  {:ok, profile} = MyApp.Repo.insert(profile_changeset(user))
  {:ok, {user, profile}}
end, [])

# Ecto.Multi
Ecto.Multi.new()
|> Ecto.Multi.insert(:user, user_changeset)
|> Ecto.Multi.run(:profile, fn repo, %{user: user} ->
  repo.insert(profile_changeset(user))
end)
|> MyApp.Repo.transact([])
```

`rollback/1` aborts the transaction and restores the pre-transaction state
in `Repo.InMemory` and `Repo.OpenInMemory`:

```elixir
MyApp.Repo.transact(fn repo ->
  {:ok, _} = repo.insert(user_changeset)
  if problem?, do: repo.rollback(:constraint_violated)
  {:ok, user}
end, [])
# Returns {:error, :constraint_violated}; insert is undone
```

Only the Repo contract's state is restored on rollback — other contracts'
state modified during the transaction is unaffected. The in-memory
adapters do not provide full ACID isolation (sub-operations are
individually atomic but not grouped). For true ACID, use the real Ecto
adapter in integration tests.

## What stays on the database

Tests that exercise database-specific behaviour should continue to run
against a real database:

- **Query correctness** — `Ecto.Query` expressions can't be fully
  evaluated in memory
- **Constraint validation** — unique indexes, foreign keys, check
  constraints
- **Transaction isolation** — concurrent writes, rollback interaction
- **Migrations** — schema changes

The goal isn't to eliminate DB tests — it's to move the ~3/4 of tests that
use the database merely as a slow data-fixture mechanism to run DB-free.

<!-- nav:footer:start -->

---

[< Double API](double-api.md) | [Up: Guides](../README.md) | [Index](../README.md) | [Changelog >](../CHANGELOG.md)
<!-- nav:footer:end -->
