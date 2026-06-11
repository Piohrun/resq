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
- **Failing assertions now report correctly.** A failing `musteq` could previously surface as `Error: type` with no message when the diff renderer crashed; it is now classified as a failure (not an error), the real "Expected X to match Y" message is preserved, and a readable FAILURE DIFF is shown. Diff rendering errors can no longer mask the underlying assertion failure.
- **`skip` / `pending` / `skipIf` / `retry` / `testOnly` now work together in any mix.** Mixing them with `should` inside one desc block previously crashed the whole file with `FILE_LOAD_ERROR: mismatch`. All DSL constructors now share one unified expectation schema.
- **Skipped and pending tests no longer fail the run.** A suite that contains only skips exits 0 when nothing failed; skipped tests are counted as skipped in the summary.
- **JUnit/xUnit XML output now contains actual results.** Previously every report was an empty `<testsuites><testsuite name="resq"/>`. Now: real testcases, correct `failures`/`errors`/`skipped` attributes, `<skipped/>` elements, XML-escaped text, control characters (illegal in XML 1.0) stripped, ANSI colour codes stripped. Output is parseable by standard XML parsers (Jenkins/GitLab compatible). `-junit` writes `test-results.xml` in CWD (or configured `outDir`); `-xunit` writes under `test-results/`.
- **`beforeAll` / `afterAll` are now actually executed** (previously silently ignored). Semantics: `beforeAll` runs once per desc block before its tests — if it throws, the block's tests are skipped and one error result is recorded (the run fails); other desc blocks still run. `afterAll` runs after the block's tests even when `beforeAll` failed; a throwing `afterAll` prints a WARNING but does not fail the suite.
- **Test files may use q system commands** (`\l`, `\d`, etc. at column 1) without crashing. Block comments (`/ ... \`) and the lone-`\` script terminator are handled correctly.
- **Explicitly-passed paths that do not exist are now load errors (exit 4)** with a clear "Explicit test path not found" message. Previously a typo could silently produce a green CI run.
- **Sandbox namespaces no longer collide.** Per-file sandbox names now include a path hash, so `test_a.q` and `test-a.q` no longer share state.
- **`holds` (property/fuzz tests) pass by default when no inputs fail.** The default `maxFailRate` of 0 combined with a `>=` comparison made every default `holds` block fail. The comparison is now strict (`failRate > maxFailRate`); `maxFailRate: 0` means zero tolerance for failures, not "fail always".
- **Text reporter renders failure messages cleanly** — q list literals like `,"..."` no longer appear in console output.

### Added
- `registerSpecCleanup` — cleanup hook that fires after per-spec resource teardown.
- `.tst.suppressAssertionDiff` flag, used by the fuzz runner so a failing fuzz spec no longer spams one `FAILURE DIFF` banner per iteration.
- `./bin/resq test` (no path) defaults to `tests/` when the directory exists.
- `-quiet` CLI flag: suppresses `Loading Test:` lines, the RUN AUDIT block, and per-suite output for passing suites; failures still print.
- `testFilePatterns` config option (list of globs) overrides the default `test_*.q` / `*_test.q` discovery convention.
- `diffLargeTableThreshold` / `diffHugeTableThreshold` config options expose the previously-hardcoded sampling thresholds in `lib/diff.q`.
- `RESQ_HOME` environment variable: `bin/resq` exports it so `resq.q` finds its own modules regardless of CWD. Makes the framework usable as a globally-installed CLI against any project.
- One-time NOTE printed on non-Linux hosts explaining that file-handle leak detection requires `/proc` and only IPC handles are tracked on macOS/Windows.
- `skill/SKILL.md` — Claude Code skill that teaches an LLM how to set up and write tests with resQ.
- **`tests/golden/`** — golden test harness that runs resQ as a subprocess against fixture suites (`f_*.q`) and asserts exit codes, summary lines, and report-file content (JUnit XML structure, JSON via `.j.k`). Fixture files are not auto-discovered.
- **`tests/test_suite_hooks.q`** — test file covering `beforeAll`/`afterAll` semantics.
- **Snapshot CI safety**: first-run snapshot creation prints `NOTE: snapshot created: <path> - review and commit it`. Under `-strict`, a missing snapshot fails with `Snapshot missing under -strict` instead of silently creating the file.
- **Discovery robustness**: depth cap of 32 on directory recursion; unreadable entries and broken symlinks are skipped rather than fatal; symlinked directories are not followed (prevents symlink loops from multiplying or hanging discovery).

### Changed
- `validateConfig` is silent; new `printConfigWarnings` is what the entry point calls. Unit tests can inspect warnings without polluting output.
- `lib/tests/` (framework DSL modules) renamed to `lib/dsl/` so it no longer collides visually with the user-facing `tests/` tree.
- Duplicate text reporter in `lib/init.q` removed; `lib/output/text.q` is now the single source of truth.
- `getDependents` now uses a cycle-safe recursion (visited-set accumulator), so a circular `\l`/`require` graph in user code no longer blows the stack.
- `.tst.spy` builds its wrapper from a table of arity-indexed template lambdas instead of `value`-ing a constructed source string. Removes the eval surface for arities 0–7 (arity 8 still uses the fallback because q's lambda ceiling is 8 params).
- **`qNamespaceExports: false`** now also gates per-expectation `.q` exports (previously only init-time exports were gated). Note: with this flag off, unqualified DSL names will not resolve inside sandboxed test files; fully-qualified `.tst.*` names are required.
- **`testOnly`** registers and tags expectations but focus-filtering is not yet implemented — `testOnly` currently runs like a normal test. Known limitation.

### Removed
- Watch-mode debouncing was listed under 0.2.0 but the implementation never landed — only four config vars were declared and a test that asserted their existence (not the behavior). Removed the dead vars from `lib/watch.q` and the placeholder test. The `.z.ts` handler still fires synchronously on every detected change; reinstate as a real feature if needed.

## [0.2.0] - 2026-02-07 - Hardening Release

### New Features
- **Test Execution Safety**: Per-test timeouts without session kill, improved exit codes, mock restoration warnings
- **Output Robustness**: Value truncation for large outputs, XML reporter truncation
- **Enhanced Diagnostics**: Stack traces include file/suite/test context, coverage include/exclude filters (`--cov-include`, `--cov-exclude`)
- **Developer Experience**: Watch mode debouncing (later removed — not fully implemented), `beforeAll`/`afterAll` hooks (declared but silently ignored until the Unreleased overhaul), config validation with unknown key warnings
- **Testing Patterns**: `retry` DSL for flaky tests, `testOnly` for focused testing, improved skip/pending support (mixing these in one block still crashed until the Unreleased fix)

### Improved
- Stack traces now show file, suite, and test context for better debugging
- Configuration validation logs warnings for unknown keys and type mismatches
- All DSL functions exposed to root and `.q` namespaces

## [0.1.0-alpha] - 2026-01-27
- Initial public release.
- Core test runner, snapshots, fixtures, mocking/spies, performance tests, coverage, discovery, and watch mode.
