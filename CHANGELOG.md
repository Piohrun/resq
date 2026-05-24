# Changelog

All notable changes to the **resQ** project will be documented in this file.

## [Unreleased]

### Fixed
- Empty test runs no longer claim "All tests passed." The reporter prints `No tests ran.` and exit code is `EXIT.NO_TESTS` (3) instead of a generic fail.
- Cleanup ordering: per-expectation `runCleanupTasks` raced the spec-level resource teardown, so a cleanup registered alongside a leaked handle silently failed on non-Linux. New `registerSpecCleanup` defers work until after handles are closed.
- "leaked new namespaces" warning was misleading — q does not allow removing a top-level identifier once defined, so the runner now reports "introduced top-level names" and clears values to `::` (skipping the warning on re-runs within the same session).
- Quickstart example's `get active users only` test errored on `exec ... from` greedy parsing; parenthesized correctly.
- README CLI examples used `-test` and `-strict` as flags; the real CLI uses positional modes (`q resq.q test path`).
- JSON / JUnit reporter no longer appends `_<pid>` to the output filename, so reruns overwrite rather than accumulate.

### Added
- `registerSpecCleanup` — cleanup hook that fires after per-spec resource teardown.
- `.tst.suppressAssertionDiff` flag, used by the fuzz runner so a failing fuzz spec no longer spams one `FAILURE DIFF` banner per iteration.
- `./bin/resq test` (no path) defaults to `tests/` when the directory exists.

### Changed
- `validateConfig` is silent; new `printConfigWarnings` is what the entry point calls. Unit tests can inspect warnings without polluting output.
- `lib/tests/` (framework DSL modules) renamed to `lib/dsl/` so it no longer collides visually with the user-facing `tests/` tree.
- Duplicate text reporter in `lib/init.q` removed; `lib/output/text.q` is now the single source of truth.

### Removed
- Watch-mode debouncing was listed under 0.2.0 but the implementation never landed — only four config vars were declared and a test that asserted their existence (not the behavior). Removed the dead vars from `lib/watch.q` and the placeholder test. The `.z.ts` handler still fires synchronously on every detected change; reinstate as a real feature if needed.

## [0.2.0] - 2026-02-07 - Hardening Release

### New Features
- **Test Execution Safety**: Per-test timeouts without session kill, improved exit codes, mock restoration warnings
- **Output Robustness**: Value truncation for large outputs, XML reporter truncation
- **Enhanced Diagnostics**: Stack traces include file/suite/test context, coverage include/exclude filters (`--cov-include`, `--cov-exclude`)
- **Developer Experience**: Watch mode debouncing, `beforeAll`/`afterAll` hooks, config validation with unknown key warnings
- **Testing Patterns**: `retry` DSL for flaky tests, `testOnly` for focused testing, improved skip/pending support

### Improved
- Stack traces now show file, suite, and test context for better debugging
- Configuration validation logs warnings for unknown keys and type mismatches
- All DSL functions exposed to root and `.q` namespaces

## [0.1.0-alpha] - 2026-01-27
- Initial public release.
- Core test runner, snapshots, fixtures, mocking/spies, performance tests, coverage, discovery, and watch mode.
