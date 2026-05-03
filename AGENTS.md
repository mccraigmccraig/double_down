# Project Norms

## 1. Coding Style

### 1.a — No Hacks

We do not implement hacky shortcuts or workarounds. When unexpected complexity
arises, stop and discuss to settle on the most appropriate solution. A
deliberate, well-reasoned fix beats a rushed patch every time.

### 1.b — Let It Crash

Take Elixir and Erlang's "let it crash" philosophy to heart. Expected domain
errors should be handled. No error should ever be silently captured and
ignored. If something is wrong, surface it.

### 1.c — Simple Code

Value simple, easy-to-reason-about code. Prefer stdlib functions where
available. Favour clarity over cleverness.

## 2. Code Hygiene

Before a piece of work is considered complete, all of the following must be
green and produce no changes:

```
mix format
mix test
mix credo
mix dialyzer
```

Fix any issues and iterate until clean. After that, add a description to the
`## [Unreleased]` section of `CHANGELOG.md` following the existing format
(`### Added`, `### Changed`, `### Fixed`, `### Improved`, `### Removed`).

**Never** add or commit files that are not explicitly part of a change you
have been working on. Research documents, issue descriptions, and
planning notes left in the working copy are not to be committed —
even if they describe work that constitutes the current change. If a
file wasn't created as part of this change and isn't already staged,
leave it alone. If in doubt about the status of a particular file, ask.

## 3. Release Process

1. All work must be complete and committed.
2. Decide the new version number:
   - **Patch** (X.Y.Z+1) — backwards-compatible bug fixes
   - **Minor** (X.Y+1.0) — backwards-compatible new functionality
   - **Major** (X+1.0.0) — incompatible API changes
3. Move the `## [Unreleased]` section contents into a new `## [X.Y.Z]` section
   in `CHANGELOG.md`.
4. Update the `VERSION` file with the new version.
5. Commit with message `vX.Y.Z` and tag the commit the same.

**Never** move a tag or change a release commit. Assume the release has been
pushed to hex.pm. If code changes are required, a patch release is needed. If
only documentation changes are required, those can be made on hex.pm without a
release.
