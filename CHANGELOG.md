# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `HexPort.Repo.Contract.insert_all/3` — standalone bulk insert
  operation, dispatched via fallback in both test adapters.
- `HexPort.Testing.set_mode_to_global/0` and `set_mode_to_private/0`
  — global handler mode for testing through supervision trees,
  Broadway pipelines, and other process trees where individual pids
  are not accessible. Uses NimbleOwnership shared mode. Incompatible
  with `async: true`.
- `HexPort.Repo.Autogenerate` — shared helper module for
  autogenerating primary keys and timestamps in test adapters.
  Handles `:id` (integer auto-increment), `:binary_id` (UUID),
  parameterized types (`Ecto.UUID`, `Uniq.UUID`, etc.), and
  `@primary_key false` schemas.
- `docs/migration.md` — incremental adoption guide covering the
  two-contract pattern, coexisting with direct Ecto.Repo calls, and
  the fail-fast test config pattern.
- Process-testing patterns in `docs/testing.md` — decision table,
  GenServer example, supervision tree example.

### Changed

- Test adapters (`Repo.Test`, `Repo.InMemory`) now check
  `changeset.valid?` before applying changes — invalid changesets
  return `{:error, changeset}`, matching real Ecto.Repo behaviour.
- Test adapters now populate `inserted_at`/`updated_at` timestamps
  via Ecto's `__schema__(:autogenerate)` metadata. Custom field
  names and timestamp types are handled automatically.
- 1-arity `transact` functions now receive the facade module instead
  of `nil`, enabling `fn repo -> repo.insert(cs) end` patterns.
- The internal opts key for threading the facade module through
  transact was renamed from `:repo_facade` to `HexPort.Repo.Facade`
  for proper namespacing.
- Primary key autogeneration is now metadata-driven — supports
  `:binary_id` (UUID), `Ecto.UUID`, and other parameterized types.
  Raises `ArgumentError` when autogeneration is not configured and
  no PK value is provided.
- Autogeneration logic extracted from `Repo.Test` and
  `Repo.InMemory` into shared `HexPort.Repo.Autogenerate` module.
- Repo contract now has 16 operations (was 15).

### Fixed

- Invalid changesets passed to `Repo.Test` or `Repo.InMemory`
  `insert`/`update` no longer silently succeed — they return
  `{:error, changeset}`.
- `Repo.InMemory` store is unchanged after a failed insert/update
  with an invalid changeset.

## [0.13.0]

### Added

- Fail-fast documentation for `impl: nil` test configuration.

### Changed

- Improved error messages when no implementation is configured in
  test mode.

## [0.12.0]

### Changed

- Removed unused Ecto wrapper macro.
- Version now read from `VERSION` file.

## [0.11.1]

### Changed

- Documentation improvements (README, hexdocs, testing guide).
- Removed unnecessary `reset` calls from test examples.

## [0.11.0]

### Fixed

- Fixed compiler warnings.

## [0.10.0]

### Added

- `Facade` without implicit `Contract` — `use HexPort.Facade` with
  an explicit `:contract` option for separate contract modules.
- Documentation explaining why `defport` is used instead of standard
  `@callback` declarations.

## [0.9.0]

### Added

- Single-module `Contract + Facade` — `use HexPort.Facade` without
  a `:contract` option implicitly sets up the contract in the same
  module.

### Changed

- Dispatch references the contract module, not the facade.

## [0.8.0]

### Added

- `HexPort.Repo.Contract` — built-in 15-operation Ecto Repo
  contract with `Repo.Test` (stateless) and `Repo.InMemory`
  (stateful) test doubles.
- `MultiStepper` for stepping through `Ecto.Multi` operations
  without a database.

### Changed

- Renamed `Port` to `Facade` throughout.
- Removed separate `.Behaviour` module — behaviours are generated
  directly on the contract module.

## [0.7.0]

### Changed

- `Repo.InMemory` fallback function now receives state as a third
  argument `(operation, args, state)`, enabling fallbacks that
  compose canned data with records inserted during the test.

## [0.6.0]

### Fixed

- Made `HexPort.Contract.__using__/1` idempotent — safe to `use`
  multiple times.

## [0.5.0]

### Changed

- Improved `Repo.Test` stateless handler.

## [0.4.0]

### Added

- `Repo.InMemory` — stateful in-memory Repo implementation with
  read-after-write consistency for PK-based lookups.
- NimbleOwnership-based process-scoped handler isolation for
  `async: true` tests.

## [0.3.1]

### Fixed

- Expand type aliases at macro time in `defport` to resolve
  Dialyzer `unknown_type` errors.

## [0.3.0]

### Added

- `transact` defport with `{:defer, fn}` support for stateful
  dispatch — avoids NimbleOwnership deadlocks.
- `Repo.transact!` for `Ecto.Multi` operations.

## [0.2.0]

### Changed

- Split `HexPort` into `HexPort.Contract` and `HexPort.Port`
  (later renamed to `Facade`).

## [0.1.0]

### Added

- Initial release — `defport` macro, `HexPort.Contract`,
  `HexPort.Testing` with NimbleOwnership, `Repo.Test` stateless
  adapter, CI setup, Credo, Dialyzer.

[Unreleased]: https://github.com/mccraigmccraig/hex_port/compare/v0.13.0...HEAD
[0.13.0]: https://github.com/mccraigmccraig/hex_port/compare/v0.12.0...v0.13.0
[0.12.0]: https://github.com/mccraigmccraig/hex_port/compare/v0.11.1...v0.12.0
[0.11.1]: https://github.com/mccraigmccraig/hex_port/compare/v0.11.0...v0.11.1
[0.11.0]: https://github.com/mccraigmccraig/hex_port/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/mccraigmccraig/hex_port/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/mccraigmccraig/hex_port/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/mccraigmccraig/hex_port/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/mccraigmccraig/hex_port/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/mccraigmccraig/hex_port/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/mccraigmccraig/hex_port/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/mccraigmccraig/hex_port/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/mccraigmccraig/hex_port/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/mccraigmccraig/hex_port/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/mccraigmccraig/hex_port/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/mccraigmccraig/hex_port/releases/tag/v0.1.0
