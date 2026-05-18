# DoubleDown

[![Test](https://github.com/mccraigmccraig/double_down/actions/workflows/test.yml/badge.svg)](https://github.com/mccraigmccraig/double_down/actions/workflows/test.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/double_down.svg)](https://hex.pm/packages/double_down)
[![Documentation](https://img.shields.io/badge/documentation-gray)](https://hexdocs.pm/double_down/)

DoubleDown is a test-double library for Elixir: mocks and fakes. It has
multiple routes to adding test boundaries to your system, and it goes beyond
mocks with stateful test doubles aka fakes. It includes an `Ecto.Repo` fake
powerful enough to run ExMachina factories without a database.

Tests that exercise database features — constraints, complex queries,
migrations — should continue to run against a real database. But unit tests
that use the database merely as an easy but slow way of getting data into
the right place can run without one. DoubleDown's `InMemory` Repo lets you
keep the factory and drop the DB.

## How it works

A function call passes through four layers:

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
     │  ┌───────────────┐ ┌──────────────┐ ┌─────────────┐  │
     │  │  defcallback  │ │  @behaviour  │ │ any module  │  │
     │  │  (explicit)   │ │  (explicit)  │ │ (implicit)  │  │
     │  └────────┬──────┘ └──────┬───────┘ └──────┬──────┘  │
     └───────────┼───────────────┼────────────────┼─────────┘
                 │               │                │
                 ▼               ▼                ▼
     ┌──────────────────────────────────────────────────────┐
     │                  2.  FACADE                          │
     │           (generated dispatch functions)             │
     │                                                      │
     │ ┌───────────────┐ ┌────────────────┐ ┌─────────────┐ │
     │ │ContractFacade │ │BehaviourFacadde│ │DynamicFacade│ │
     │ └────────┬──────┘ └────────┬───────┘ └──────┬──────┘ │
     └──────────┼─────────────────┼────────────────┼────────┘
                └─────────────────┼────────────────┘
                                  │
                                  ▼
     ┌──────────────────────────────────────────────────────┐
     │                  3.  DISPATCH                        │
     │              (call resolution)                       │
     │                                                      │
     │  ┌────────────┐  ┌──────────────┐  ┌──────────────┐  │
     │  │  Static    │  │   Runtime    │  │    Test      │  │
     │  │ (compile-  │  │   Config     │  │   Handler    │  │
     │  │  time,     │  │              │  │              │  │
     │  │  zero      │  │ App.get_env  │  │ NimbleOwner- │  │
     │  │  overhead) │  │ → apply/3    │  │ ship lookup  │  │
     │  └─────┬──────┘  └──────┬───────┘  └──────┬───────┘  │
     └────────┼────────────────┼─────────────────┼──────────┘
              └────────────────┼─────────────────┘
                               │
                               ▼
     ┌──────────────────────────────────────────────────────┐
     │              4.  IMPLEMENTATION                      │
     │            (actual execution)                        │
     │                                                      │
     │  ┌──────────────────────────┐  ┌──────────────────┐  │
     │  │   Production Module      │  │   Test Double    │  │
     │  │   (@behaviour Contract)  │  │  (stub / fake /  │  │
     │  │                          │  │   expect)        │  │
     │  └──────────────────────────┘  └──────────────────┘  │
     └──────────────────────────────────────────────────────┘
```

Three facade types let you add boundaries at different levels of control:

| Facade            | Contract                        | Best for                                  |
|-------------------|---------------------------------|-------------------------------------------|
| `ContractFacade`  | `defcallback` (explicit, typed) | New code you control                      |
| `BehaviourFacade` | existing `@behaviour`           | Third-party or legacy behaviours          |
| `DynamicFacade`   | implicit (module's public API)  | Adding boundaries without touching source |

Dispatch is uniform across all three — the same resolution mechanism, the same
`DoubleDown.Double` API for tests, the same `DoubleDown.Log` for tracing calls.
In production, dispatch can be eliminated entirely at compile time (static
dispatch inlines direct calls — zero overhead versus calling the implementation
directly).

## Installation

[![Hex.pm](https://img.shields.io/hexpm/v/double_down.svg)](https://hex.pm/packages/double_down)

Add `double_down` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:double_down, "~> 0.48"}
  ]
end
```

## Documentation

- **[Boundaries](docs/boundaries.md)** — contracts, facades, and the dispatch
  mechanism
- **[Dispatch](docs/dispatch.md)** — uniform dispatch resolution
- **[Stateful Doubles](docs/stateful-doubles.md)** — stateful fakes, handler
  state, cross-contract access
- **[Double API](docs/double-api.md)** — expect, stub, fallback, verify!,
  passthrough
- **[Repo](docs/repo.md)** — the built-in Ecto.Repo contract and its test
  doubles

Archived documentation from previous versions lives in
[docs/archive/](docs/archive/) — these cover the same concepts but may use
outdated module names.

## License

MIT License — see [LICENSE](LICENSE) for details.
