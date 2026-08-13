# Changelog

All notable changes to the **resQ** project will be documented in this file.

## [Unreleased]

### Added

- Opt-in conditional-edge coverage instruments eligible `if`, `while`, and
  lazy `$` conditions without evaluating value branches. Stable branch-site and
  edge identities, hits, fallbacks, and completeness now flow through the
  canonical model, LCOV `BRDA`/`BRF`/`BRH`, detailed JSON, annotated HTML,
  complete state output, console diagnostics, and independent fail-closed
  branch/completeness gates. The production differential corpus verifies
  returns, errors, side effects, and random state before and after the combined
  statement/branch rewrite.
- Versioned execution-manifest and ordered lifecycle-event contracts now ship
  in every canonical JSON report. Stable source/test identities, source
  provenance, shard assignment, and a deterministic manifest digest are
  invariant across repeated, relocated, isolated, concurrent execution and all
  members of one shard topology.
- Trusted in-process plugins can register named event observers and end-of-run
  reporters under `.resq`. Callbacks are trapped, return values and direct
  verdict mutations are non-authoritative, and opt-in strict plugin policy
  turns callback failures into canonical error rows.
- An opt-in KX Developer `.cov` adapter can measure loaded resQ framework
  functions without using resQ's own source rewriter. Its versioned JSON and
  text artifacts are explicitly partial and non-gating, the adapter is covered
  by an external-provider contract double, and licensed nightly CI enables it
  only when AxLibraries is configured.

### Fixed

- Property tests now sum assertions executed by every generated case instead
  of reporting only the largest per-case count. Shrink probes remain diagnostic
  work and do not inflate test or run assertion totals.
- DSL-name shadowing now follows lexical lambda scopes instead of suppressing
  an alias across the whole file. An inner local such as `should` or `it` no
  longer breaks an enclosing constructor, same-line declarations are handled,
  and irreducibly ambiguous lookup errors include an explicit `.tst` hint.
- qspec migration docs now identify nested `desc` as an intentional public DSL
  difference, and getting-started docs correctly state that machine reporters
  add artifacts without replacing the human CI summary.
- The oversized-`desc` message contract is now a fast default-suite unit test;
  the real, roughly minute-long q compiler-boundary subprocess remains covered
  by nightly hardening instead of slowing every local and release-gate run.

## [1.0.0] - 2026-08-12 - Production Trust, Coverage & Observability

### Added

- Pinned, offline `strQ` and `reQ` external adoption pilots with exact source
  provenance and normal/isolated execution parity in the licensed CI gate.
- A one-command release audit now verifies the full self-suite in normal and
  concurrent-isolated modes, every machine contract, canonical coverage totals,
  hardening checks, external pilots, and emits retained JSON evidence.
- CI now has a licence-free GitHub-hosted gate for shell syntax, package layout,
  internal documentation links, JSON v2/schema fixtures, JUnit/xUnit fixtures,
  and the Python observability adapters. Licensed q execution waits for this
  contract gate to pass.
- A scheduled, manually configurable nightly workflow now expands the
  deterministic native-`\l` loader differential and statement-instrumentation
  differential corpora, validates their JSON report, and records the exact seed
  counts needed for reproduction.
- The v1 process/filesystem boundary now has an executable hostile-environment
  audit covering shell/path metacharacters, symlinked and spaced installs,
  explicit-q propagation, relative and blocked artifact destinations, private
  temp permissions, interruption, child reaping, and launcher cleanup.
- Public support, security/trust-boundary, SemVer/schema evolution, stable
  identity, and deprecation policies now define the resQ 1.x compatibility and
  maintenance contract. JSON schema v2 explicitly permits additive fields while
  retaining its required core and invariant validator.
- Coverage source manifests now inventory unloaded modules at zero hits. One
  canonical coverage model produces LCOV, detailed JSON, annotated HTML, and a
  complete state file, with independent function, line, and instrumentation-
  completeness gates that fail closed on partial line denominators.
- JSON schema v2 adds stable run/test/case identities, portable source paths,
  run/VCS/CI metadata, typed diagnostics, retry attempt history, parameter and
  property-case telemetry, benchmark results, and snapshot lifecycle events.
- Seeded private-PRNG ordering, stable-ID last-failed/failed-first workflows,
  deterministic file sharding, repeated/watch-mode contract tests, and thin
  NDJSON/Allure adapters complete the production developer workflow.

### Fixed

- resQ no longer exports common DSL names through reserved `.q`. Bare qspec
  syntax is bound to stable `.tst.dsl.*` helpers during test-source loading,
  including infix assertions and mocks, while file-declared locals safely
  shadow aliases. The deprecated `qNamespaceExports` key is accepted but
  ignored. This restores loading for valid application locals such as
  `before`, `after`, `mock`, `it`, `holds`, `perf`, and `must`.
- Expectation annotation now respects test-file locals that share DSL names and
  has an explicit `-no-line-annotations` /
  `"expectationLineAnnotations":false` kill switch. Isolated children inherit
  the setting. Disabling it also disables declaration-line metadata and the
  incomplete-constructor audit, which is documented rather than hidden.
- A checked-in production application corpus now loads documented, indented
  namespace source through both `system "l"` and native `\l`, using ordinary
  locals named `before`, `after`, `mock`, `it`, `holds`, `perf`, `must`,
  `should`, `fixture`, `beforeAll`, and `afterAll`. Its unchanged qspec-shaped
  tests run as a required subprocess contract.
- The qspec compatibility promise now has an explicit version-1 contract:
  guaranteed DSL/assertions/options, intentional comparison behavior, private
  API/output exclusions, upstream commit pin, and SemVer change policy. Project
  wording now says "mostly test-source-compatible replacement" rather than
  implying a strict superset.
- Every recoverable `runSpec` path now executes one independently trapped
  finalizer. `beforeAll` failures, fail-hard halts, and unexpected suite-runner
  exceptions restore application globals, close resources, restore runtime
  context, run `afterAll`, and drain registered spec cleanup before the next
  suite or reporter observes state.
- `-cov-min` now always gates on the complete discovered-function inventory.
  Previously, enabling `-cov-statements` made any available line records take
  precedence even when safe instrumentation covered only part of the source;
  this could pass CI at 88% measured lines while complete function coverage was
  70%. Measured line results remain in the console, LCOV, and JSON as a
  diagnostic, while JSON `coverage.basis` records `"functions"`.
- Isolated parent runs now preserve all JSON v2 child telemetry, including
  retry attempts, parameter/property cases, diagnostics, snapshots, and
  benchmarks, instead of merging only the legacy result columns.
- Framework and application q files now load through a cwd-restoring basename
  helper, so install/source paths containing spaces work. Isolated groups track
  timeout process groups and reap them on INT/TERM/HUP/EXIT; launcher-owned
  scratch is removed even when the foreground run is interrupted.
- Linux file-handle leak detection now inspects q's own `/proc` descriptors and
  maps them to q connection handles before closing them. Cleanup is verified by
  the following suite and remains visible in structured diagnostics.
- Default binary and text snapshot paths are anchored to the caller's project
  root rather than the framework's temporary module-loading directory.

## [0.4.0] - 2026-08-03 - qspec Drop-in, Measured Coverage & Fail-Closed Runs

A minor bump: new capabilities and fixes, no removals. Several of the fixes
are **fail-closed** and can turn a previously-green suite red — deliberately,
because each one marks a run that was passing without having proved what it
claimed. Expect to see, in rough order of likelihood:

- an under-applied DSL constructor (`holds["x"]{...}` with no properties
  argument) is now a load error instead of a silently missing test;
- a test or loaded source calling `exit` before the runner finishes now fails
  the run instead of exiting 0 with no report;
- a test that passes without running an assertion fails under `-strict`.

`bin/qspec` runs an unmodified qspec suite with qspec's comparison semantics,
so migration needs no source changes; see [MIGRATION.md](docs/MIGRATION.md).

### Added

- **Production CI gate and deployment guide.** `.github/workflows/ci.yml` runs
  strict normal and isolated suites, a coverage threshold, and independent
  JSON/XML parsing on a licensed self-hosted q runner. `docs/CI.md` documents
  runner prerequisites, reporter filenames, and sharding.
- **Coverage thresholds** (`-cov-min N` / `-coverage-min N` and
  `"coverageMin": N`). Coverage now prints exact line/function percentages,
  includes its decision in JSON, and fails closed when below threshold, when no
  code was measured, or when reports cannot be generated.

- **A qspec-compatible `bin/qspec` launcher and pinned upstream contract.** The
  launcher enables qspec comparison semantics automatically and accepts the
  legacy `-performance`, `-pass`, `-fuzz-display-limt` and `-fdl` options. Seven
  byte-identical public qspec test files at commit `9b846b6` now run through it
  in the normal resQ suite, covering assertions, UI, mocks, fuzzing, and file,
  directory, text, and splayed fixtures.

- **`docs/ASYNC.md`** — the async and promise helpers were shipped
  undocumented. Covers deferreds (`deferred`/`resolve`/`reject`/`await`),
  the polling helpers (`until`/`wait`/`waitEx`/`eventually`) and callback spies,
  including the behaviours that surprise: the polling helpers **signal** on
  timeout rather than returning `0b`, `eventually` treats a *throwing* condition
  as "not ready yet" and polls on, `sleep` is a busy-wait, and callback logs are
  global and persist between tests. Every example is executed by
  `tests/test_async_documented.q`.

- **Statement-level coverage** (`-cov-statements` / `"covStatements": true`,
  opt-in). Measured per-statement hits rather than derived ones: an untaken
  `if` branch inside a called function now reports zero. Probes are placed on
  top-level statements and inside `if`/`do`/`while` bodies, which evaluate every
  argument; `$[…]` is left alone because a probe among the branches of a
  conditional *expression* would change its value. It works by rewriting
  function bodies at load time, attempted per function and verified afterwards
  (must still parse, must keep the same parameter list) with the original
  restored on any failure. **Opt-in because it is a transformation of the code
  under test and is not proven safe on every construct** — instrumenting resQ's
  own `lib/loader.q` breaks it. See docs/COVERAGE.md.
- **Recorded benchmark measurements.** A `perf` block computed its averages and
  discarded them unless a budget was breached, so performance could be gated but
  never tracked. Measurements now reach a console `PERFORMANCE` section, a
  `performance` array in the JSON report (per-benchmark min/max/avg/stdev, run
  count, allocation, and the declared budgets), and `.tst.app.perfResults`.

### Fixed

- Statement coverage no longer stops at the second-to-last function in a file.
  A function's line span ran to the line before the *next* definition, so the
  last one absorbed everything after it — usually a `\d .` footer, which the
  rewriter cannot `value`, so the rewrite was rejected and that function
  silently lost its line records while still reporting `FN:`/`FNDA:`. The
  denominator was correspondingly short, making the line percentage a claim
  about fewer lines than the file actually has. The same over-reach also
  swallowed any top-level statement sitting *between* two definitions: it was
  given a probe and **re-executed** at instrumentation time, so a source file
  with side effects at top level ran them twice under `-cov-statements`. Spans
  are now closed by bracket balancing, and fail open to the old bound when a
  definition's brackets never balance.
- Tests that asserted nothing are now reported on failing runs too. The list sat
  after the `Tests FAILED.` early return, so a single real failure hid every
  vacuous test in the suite — precisely when the reader is working through that
  suite. The verdict still prints last, and green output is unchanged.
- A runtime error's backtrace now stops at the test body. The runner's own
  dispatch frames (`.tst.finishFixtureTest`, the `.Q.trp` hops, `runAll`,
  `resq.q`) are always the same and never actionable, but accounted for roughly
  30 of the ~85 lines a nested user error produced, pushing the frames that
  matter out of view; a four-frame error is now 15 lines. Only the outermost
  contiguous run of framework frames is dropped, and the count of omitted frames
  is stated. Anything bracketed by user code — including a `(.q.each)` hop
  inside the user's own call chain — is kept, and a trace with no user frames at
  all (a genuine resQ bug, where those frames are the evidence) is left intact.
- Isolated runs no longer forward a failing child's own report. The captured
  transcript kept the child's per-suite listing, SUMMARY box, verdict line and
  `JSON Report written to <private scratch>` line, so every failing file
  duplicated the parent's summary and advertised a scratch directory deleted
  moments later. Because that path comes from `mktemp`, it also made two runs of
  the same failing suite differ, breaking the byte-stable output
  `docs/PARALLEL.md` promises. The child now marks where its report begins and
  the parent cuts there, keeping test-produced output (`show`, `-1`, library
  chatter) and the structural diff in the console, JSON and JUnit `system-out`.
- Source-loaded DSL declarations now fail at load time when a constructor is
  under-applied and leaves a q projection (for example,
  `holds["property"]{...}`). All line-annotated constructors, including
  explicit `.tst.*` calls, participate in the arity audit instead of silently
  registering fewer tests than were written.
- Isolated suite/tag filtering now treats a valid, filtered-empty child file as
  neutral. The parent computes the verdict after aggregating all files, so a
  filter that selects tests in another file passes while a filter that matches
  nothing globally still fails.
- The `resq` and `qspec` launchers now supervise test-run completion. A test or
  loaded application calling `exit 0` before the runner finishes is forced to
  exit 1, even if it replaces `.z.exit`; ordinary completed runs retain their
  granular exit status. Isolation children cannot complete the parent marker.
- Runtime errors now use `.Q.trp` at the test/hook execution boundary and format
  the original frames with `.Q.sbt`, retaining nested function names and source
  snippets after fixture teardown instead of reporting only file/suite/test
  context.
- Process isolation now retains a bounded head/tail transcript of a failing
  child's combined stdout/stderr, replays it in the parent console, and exposes
  it as JSON `output`, JUnit `<system-out>`, and xUnit `<output>`. Passing child
  output is still discarded, and one transcript is attached per failing file to
  avoid multiplying logs across result rows.
- Reporters now compose without filename collisions, preserve file/line and skip
  metadata, expose aggregate JSON `assertionCount`, use stable JSON field types,
  and fail the run on serialization or
  write errors after attempting every selected reporter. A requested reporter
  module that is missing or fails to load also fails closed after the available
  formats have been written.
- Parametrized assertions execute every row, retain assertion diffs and parameter
  values, and remain failures rather than being converted into generic errors.
- `-maxTestTime` is consistently milliseconds and reports a post-execution
  budget breach precisely; process isolation remains the preemptive timeout.
- Isolated children that die after printing `wsfull`, stack overflow, allocation,
  or crash diagnostics are now labeled as fatal q/runtime failures instead of
  being misleadingly described as a probable call to `exit`.
- Process isolation retries a child up to three times only when captured output
  proves q was rejected by a temporarily unavailable KX license daemon. Test
  failures and all other process exits remain single-attempt.

- Repeated in-process runs (`watch` and `-noquit`) now reset load errors,
  benchmark rows, halt/assertion/dependency state, and reactivate compatibility
  exports without losing genuine pre-resQ `.q` values.
- `perf` now defaults to ten measured runs with per-iteration GC; the previous
  `10b` literal was a two-element boolean vector and silently meant one run
  with GC disabled. Non-positive iteration counts are rejected clearly.
- Exit policy now has one owner: `resq.json` `"exit": false` is honoured,
  `-exit` overrides it while retaining granular exit codes, and `-ff -exit`
  keeps its explicit immediate-stop behavior.
- The documented relative `q resq.q ...` entrypoint canonicalizes `.resq.HOME`,
  avoiding `/.` path keys in coverage and other normalized registries.
- Isolation children receive effective suite/tag filters, fail-fast and qspec
  compatibility settings. `-pass -isolate` is silent at the parent boundary.
- `-pass` suppresses assertion diff banners in addition to result reporters.
- Watch mode now detects deletions and uses the same configurable test-file
  patterns as discovery, including both `test_*.q` and `*_test.q` by default.
- An `alt{}` block after ordinary expectations failed while loading with
  `'mismatch` because q cannot join expectation tables before and after hook
  columns are attached. The merge now adds placeholder hook columns without
  changing qspec's late-hook behavior; the original file/splayed fixture test
  is restored and passing.
- Performance expectations are again opt-in, matching qspec: they are filtered
  unless `-perf`/`-performance` or `runPerformance:true` is selected.

- `docs/API_REFERENCE.md` documented the wrong properties for `perf`
  (`iterations`/`warmup`, which belong to the low-level bench API) where the
  block actually reads `runs`/`maxTime`/`maxSpace`.


## [0.3.0] - 2026-08-01 - Isolation & Reporting Integrity

### Changed

- **`mustne` compares whole values.** It used `<>`, which is elementwise in q, so
  any non-atom produced a boolean vector rather than an atom: `must` then applied
  `all`, giving it the meaning "every element differs" (`1 2 3` vs `9 2 3`
  reported a failure), and tables/ragged operands signalled `'type`/`'length`.
  It now uses `not l~r`, making it the exact inverse of `musteq` — including
  type strictness, so `1 mustne 1.0` passes where `1 musteq 1.0` fails.
  Previously both failed at once.
- **`must` requires a boolean condition.** `all` maps `5`, `0N` and any non-empty
  string to true, so `must[0N; …]` and a swapped `must["message"; cond]` passed
  silently. A non-boolean is now a failure naming the offending type. Boolean
  vectors are unchanged; an empty one still passes ("all of zero items hold").
- **`-xunit` writes to `outDir`**, like `-junit` and `-json`. It previously forced
  `outDir` to `test-results`, so it alone wrote into a subdirectory. An explicit
  `-outDir` was already honoured and still is.
- **`skipIf` keeps one stable test name.** It registered `"SKIP: <reason>"` when it
  skipped but `"<reason>"` when it ran, so an environment-gated test appeared under
  a different name in different environments, breaking CI test history and
  flaky-test tracking. Both branches now use the plain reason. Explicit
  `skip[]`/`pending[]` keep their `SKIP:`/`PENDING:` prefix.

### Added

- **Zero-assertion tests are reported.** A `should` block's return value is ignored,
  so a bare expression (`0 < count warnings;`) is discarded rather than checked and
  the test passes however broken the code is. The text reporter now lists any test
  that passed while running zero assertions (shown under `-quiet` too; silent when
  there are none). 17 such tests in this suite were found and given real assertions.
- **`resq cover` warns when it instruments nothing.** An empty LCOV looks like
  success while measuring nothing; the usual cause is loading the code under test
  with a loader the hook does not see (only `\l` and `system "l "` are intercepted).
- **Reporter XML is covered by tests** — per-test results, distinct failure/error/
  skipped elements, suite-level counts, escaping, and output locations. None of it
  was pinned before.
- **Process isolation mode: `resq test -isolate [-isolateTimeout N]`.** Each test file runs in its own q subprocess (sequentially); the parent aggregates results from per-file JSON reports and drives the normal reporting/exit pipeline. A test that calls `exit` is reported as an error ("process exited without producing results") instead of silently ending — or faking — the run; an infinite loop is killed after `isolateTimeout` seconds (default 300, requires the `timeout` binary) and the remaining files still run; a process-fatal error (`'wsfull`, stack) fails only its file.
- **Generative differential loader testing** (`tests/test_loader_differential.q`): seeded random q scripts (comments, block comments, continuations, namespaces, terminators, CRLF) are loaded via native `\l` and via resQ's preprocessor in separate processes and the resulting definitions compared. Runs a fixed corpus of historical regressions plus deterministic seeds in-suite; swept clean to seed 400.

### Fixed

- **xUnit tests carry a `result` attribute.** `<test>` elements had none, which is
  how an xUnit v2 consumer determines per-test status — so every test was
  indeterminate and a red run could be read as green. Tests now report
  `result="Pass"/"Fail"/"Skip"` and the assembly reports `passed`/`failed`.
- **A throwing `before[]`/`after[]` reaches the report.** The per-spec error trap
  recorded no expectation, so the run summarised as "0 total tests" and the JUnit
  document was an empty `<testsuites></testsuites>`: a pipeline reading the report
  saw no tests and no failures. A spec that fails to run now produces an error
  testcase, as the `beforeAll` failure path already did.
- **`parametrize` streams the Cartesian product** instead of materializing it via
  `cross over`, which could exhaust the heap on a handful of parameters. Ordering
  is unchanged and the cardinality is overflow-checked. Verified on an 8,000,000-case product.
- **Snapshot names are contained.** A name went straight into a path, so `"../x"`
  escaped the snapshot root. Both binary and text paths now validate the name as a
  bare leaf before any filesystem access.
- **Load directives are located in masked source.** The scanner matched `like`
  patterns against raw lines, so a require named in a comment or string became a
  real graph edge; it compensated with a heuristic that skipped any line containing
  `"like"`, which also dropped genuine requires. Comments, strings, block comments
  and post-terminator text are now masked before detection, and a concatenated
  tail stays distinguishable from a standalone absolute target.
- **Loader evaluation now matches q's line-buffered `\l` semantics.** Found by the differential harness: evaluating a file as one `value` blob diverged from native `\l` for bare continuation lines, standalone comment lines between a statement and its continuation, and trailing inline comments without `;`. Files are now evaluated statement-by-statement after comment-line removal; error reporting ("near line N") and partial-spec rollback are unchanged.
- **`retry[n; "desc"]{...}` now actually retries.** Previously a silent no-op; now makes up to n+1 total attempts. `before`/`after` hooks re-run per attempt. The first passing attempt wins and records one result row. A late pass prints `NOTE: '<desc>' passed on attempt k of m` for flake visibility. Exhausted retries report "failed after m attempts".
- **Block-comment parsing matches real q.** A line containing only `/` always opens a block comment closed by a lone `\`; a lone `\` outside a block terminates the script. The previous heuristic diverged on the common single-`/` banner idiom.
- **Duplicate path spellings are deduped.** Passing the same file as `./x.q` and `x.q` now runs it once (canonical absolute-path dedup).
- **`.tst.forall` first-row false failure fixed.** A precedence bug caused the first row to spuriously fail when prior assertion state contained failures.
- **`await` on rejected promises raises the actual reason.** String rejection reasons are now signalled correctly; previously raised `'stype`.
- **`partialMock`/`mockSequence` give clear errors on typos.** A target that is not yet defined now emits `"target not defined: <name>"` instead of a raw q name error.
- **`resq.json` validation is authoritative.** Invalid values (wrong type, unparseable numbers, unknown keys) are warned AND ignored — defaults remain in effect. Previously bad values were applied after the warning.
- **`-strict` counts only executed tests.** A suite where every test was skipped now fails under `-strict` with "skipped tests do not count under -strict". Without `-strict`, all-skipped still exits 0.
- **Empty snapshots validate correctly.** An empty list, dict, or table is no longer mistaken for "missing" — file presence is the existence check. Empty values compare like any other snapshot and work under `-strict`.
- **Report messages are clean and bounded.** Failure messages in JUnit/xUnit/JSON are newline-joined plain text (no q literal artifacts), capped at `reportLimit` (default 50000) with a truncation marker. `time` attributes are never empty (null durations → 0). Empty classnames fall back to the suite name. ANSI stripping no longer risks eating text after malformed escape sequences.
- **`resq cover` is now functional.** Instruments functions loaded by test files via `\l` or simple `system "l ", path` forms through a coverage-aware loader. Emits real LCOV (SF/FN/FNDA/FNF/FNH records), a per-function HTML report, and a complete `coverage_state.txt`. Limitations: compiled operators/derived functions are skipped; coverage is function-level (hit counts per function), not line-level; files loaded by other mechanisms are not instrumented.
- **`resq watch` is now functional.** Change detection uses file size+mtime fingerprints. Test-file classification no longer errors. Works without a TTY (redirected stdin/CI). Uses a foreground poll loop instead of `.z.ts`. Poll interval configurable via `.tst.watch.interval` (seconds, default 1).
- **Loader hijacking gated behind explicit flag.** `.tst.loader.hijack`/`autoHijack` refuse to run unless `.tst.loaderHijackEnabled: 1b` is set. Also now handles namespaced loaders and has a lower false-positive detection rate. Status: experimental, off by default. `resq discover` does not require it.
- **Static analysis / discover fixes.** `name: {...}` (space after colon) is now detected. `\d .` namespace resets are handled correctly; generated templates no longer contain invalid `..name` identifiers.
- **`deps.q` dependency graph is traversable.** Dependency targets resolve to the same absolute paths as graph keys; self-referential pattern matches are excluded.
- **`.q` namespace exports lifecycle is honest.** Disabling (`qNamespaceExports:false` or restore) neutralises resq-added `.q` keys (sets them to `::`) rather than claiming removal. The original-value snapshot is taken before resQ writes anything. Existing caveat stands: with exports disabled, unqualified DSL names won't resolve inside sandboxed test files.
- Empty test runs no longer claim "All tests passed." The reporter prints `No tests ran.` and exit code is `EXIT.NO_TESTS` (3) instead of a generic fail.
- Cleanup ordering: per-expectation `runCleanupTasks` raced the spec-level resource teardown, so a cleanup registered alongside a leaked handle silently failed on non-Linux. New `registerSpecCleanup` defers work until after handles are closed.
- "leaked new namespaces" warning was misleading — q does not allow removing a top-level identifier once defined, so the runner now reports "introduced top-level names" and clears values to `::` (skipping the warning on re-runs within the same session).
- Quickstart example's `get active users only` test errored on `exec ... from` greedy parsing; parenthesized correctly.
- README CLI examples used `-test` and `-strict` as flags; the real CLI uses positional modes (`q resq.q test path`).
- JSON / JUnit reporter no longer appends `_<pid>` to the output filename, so reruns overwrite rather than accumulate.
- **Failing assertions now report correctly.** A failing `musteq` could previously surface as `Error: type` with no message when the diff renderer crashed; it is now classified as a failure (not an error), and the message reads `Got X — expected Y`. A readable FAILURE DIFF is shown. Diff rendering errors can no longer mask the underlying assertion failure.
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
- **Additive camelCase assertion aliases**: `mustEqual`, `mustNotEqual`, `mustLessThan`, `mustGreaterThan`, `mustMatchSnapshot`, `mustMatchTextSnapshot`, `mustMatchIgnoringOrder`. These are identical to their lowercase counterparts and are exported to root and `.tst.asserts`.
- **CLI filtering works end-to-end**: `-only PATTERN`, `-exclude PATTERN`, `-tag TAG`, `-exclude-tag TAG`, `-maxTestTime N` all filter correctly. Patterns are `like` globs (title matching); tags are `#word` tokens embedded in suite titles.
- **`-desc` / `--describe`** prints a clean suite/test listing and exits 0 (exits 4 if a file had a load error).
- **Load errors report "near line N"** for syntax errors, so the failing construct is locatable without manual scanning.
- **Text snapshots (`mustmatchst`) have full parity with binary snapshots**: first-run prints `NOTE: text snapshot created: ...`; under `-strict`, a missing text snapshot fails with `Snapshot missing under -strict`.
- **`mustmatch` produces the same rich FAILURE DIFF as `musteq`** — it routes through the same diff body.
- **`mustthrow` misuse guard**: passing code as the first argument (infix style) now gives a guidance error instead of a raw `'type`.
- **Exit codes 2 (`CONFIG_ERROR`) and 5 (`PARTIAL`) removed.** No code path emitted them; the remaining codes are 0 (pass), 1 (fail/error), 3 (no tests), 4 (load error).
- **New test files**: `tests/test_retry.q`, `tests/test_watch.q`, `tests/test_strict_behavior.q`, `tests/test_promise_reject.q`. The golden harness gained scenarios for block comments, duplicate-path spelling, coverage LCOV content, strict snapshots, `beforeAll`-junit, and graceful degradation when the `timeout` binary is absent (macOS).
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
- **`testOnly` focus-filtering is now implemented (per-suite).** If any test in a `describe` block is a `testOnly`, only the `testOnly` tests in that block run; the rest are reported as **skipped** (visible in CI output) rather than silently dropped. Focus is per-suite — other suites run normally. A `NOTE: testOnly active in suite '<title>': running N of M tests` line is printed once per focused suite. Under `-strict`, a focused-and-passing suite still counts as executed (skips do not).

### Removed
- **`parallel_runner.q` removed.** The file was unreachable dead code and architecturally unsound — q threads cannot write globals. Use CI-level parallelism (split test directories across jobs) instead. See `docs/PARALLEL.md`.
- Watch-mode debouncing was listed under 0.2.0 but the implementation never landed — only four config vars were declared and a test that asserted their existence (not the behavior). Removed the dead vars from `lib/watch.q` and the placeholder test.

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
