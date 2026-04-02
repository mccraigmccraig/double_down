# Getting Started

[Up: README](../README.md) | [Testing >](testing.md)

## Defining a contract

A port contract declares the operations that cross a boundary. HexPort
uses `defport` to capture typed signatures with parameter names,
return types, and optional metadata — all available at compile time via
`__port_operations__/0`.

### Combined contract + facade (recommended)

The simplest pattern puts the contract and dispatch facade in one
module. When `HexPort.Facade` is used without a `:contract` option,
it implicitly sets up the contract in the same module:

```elixir
defmodule MyApp.Todos do
  use HexPort.Facade, otp_app: :my_app

  defport create_todo(params :: map()) ::
    {:ok, Todo.t()} | {:error, Ecto.Changeset.t()}

  defport get_todo(id :: String.t()) ::
    {:ok, Todo.t()} | {:error, :not_found}

  defport list_todos(tenant_id :: String.t()) :: [Todo.t()]
end
```

This module is now three things at once:

1. **Contract** — `@callback` declarations and `__port_operations__/0`
2. **Behaviour** — implementations use `@behaviour MyApp.Todos`
3. **Facade** — caller functions like `MyApp.Todos.create_todo/1` that
   dispatch to the configured implementation

### Separate contract and facade

When the contract lives in a different package or needs to be shared
across multiple apps with different facades, define them separately:

```elixir
defmodule MyApp.Todos.Contract do
  use HexPort.Contract

  defport create_todo(params :: map()) ::
    {:ok, Todo.t()} | {:error, Ecto.Changeset.t()}

  defport get_todo(id :: String.t()) ::
    {:ok, Todo.t()} | {:error, :not_found}
end
```

```elixir
# In a separate file (contract must compile first)
defmodule MyApp.Todos do
  use HexPort.Facade, contract: MyApp.Todos.Contract, otp_app: :my_app
end
```

This is how the built-in `HexPort.Repo.Contract` works — it defines
the contract, and your app creates a facade that binds it to your
`otp_app`. See [Repo](repo.md).

## `defport` syntax

```elixir
defport function_name(param :: type(), ...) :: return_type(), opts
```

The return type and parameter types are captured as typespecs on the
generated `@callback` declarations.

### Bang variants

`defport` auto-generates bang variants (`name!`) for operations whose
return type contains `{:ok, T} | {:error, ...}`. The bang unwraps
`{:ok, value}` and raises on `{:error, reason}`.

Control this with the `:bang` option:

| Value | Behaviour |
|-------|-----------|
| *(omitted)* | Auto-detect: generate bang if return type has `{:ok, T}` |
| `true` | Force standard `{:ok, v}` / `{:error, r}` unwrapping |
| `false` | Suppress bang generation |
| `unwrap_fn` | Generate bang using a custom unwrap function |

Example — a function that already raises, so no bang is needed:

```elixir
defport get_todo!(id :: String.t()) :: Todo.t(), bang: false
```

Example — custom unwrap for a non-standard return shape:

```elixir
defport fetch(key :: atom()) :: {:found, term()} | :missing,
  bang: fn
    {:found, v} -> v
    :missing -> raise "not found"
  end
```

## Implementing a contract

Write a module that implements the behaviour. Use `@behaviour` and
`@impl true`:

```elixir
defmodule MyApp.Todos.Ecto do
  @behaviour MyApp.Todos

  @impl true
  def create_todo(params) do
    %Todo{}
    |> Todo.changeset(params)
    |> MyApp.Repo.insert()
  end

  @impl true
  def get_todo(id) do
    case MyApp.Repo.get(Todo, id) do
      nil -> {:error, :not_found}
      todo -> {:ok, todo}
    end
  end

  @impl true
  def list_todos(tenant_id) do
    MyApp.Repo.all(from t in Todo, where: t.tenant_id == ^tenant_id)
  end
end
```

The compiler will warn if your implementation is missing callbacks or
has mismatched arities.

## Configuration

Point the facade at its implementation via application config:

```elixir
# config/config.exs
config :my_app, MyApp.Todos, impl: MyApp.Todos.Ecto
```

Different environments can use different implementations:

```elixir
# config/test.exs
config :my_app, MyApp.Todos, impl: MyApp.Todos.Mock
```

## Dispatch resolution

When you call `MyApp.Todos.get_todo("42")`, `HexPort.Dispatch.call/4`
resolves the handler in order:

1. **Test handler** — NimbleOwnership process-scoped lookup. Zero-cost
   in production: `GenServer.whereis` returns `nil` when the ownership
   server isn't started.
2. **Application config** — `Application.get_env(otp_app, contract)[:impl]`
3. **Raise** — clear error message if nothing is configured.

This means test handlers always take priority over config, and config
is the production path.

## Key helpers

Facade modules also generate `key/2` helper functions for building
test stub keys:

```elixir
MyApp.Todos.key(:get_todo, "42")
# => {MyApp.Todos, :get_todo, ["42"]}
```

These are used with Skuld's `Port.with_test_handler/2` for effectful
testing. For plain HexPort testing, use the handler modes described
in [Testing](testing.md).

## Why `defport` instead of plain `@callback`?

HexPort could in principle generate a facade from any Elixir behaviour,
but there are practical limitations:

- **Parameter names may not be available.** A `@callback` declaration
  like `@callback get(term(), term()) :: term()` has no parameter names.
- **`Code.Typespec.fetch_callbacks/1` has limitations.** It only works
  on compiled modules with beam files on disk, not on modules being
  compiled in the same project.
- **No place for additional metadata.** `defport` supports options like
  `bang:` that control bang variant generation. Plain `@callback` has
  no mechanism for this.

`defport` captures all metadata at macro expansion time in a
structured form (`__port_operations__/0`), avoiding these limitations.

---

[Up: README](../README.md) | [Testing >](testing.md)
