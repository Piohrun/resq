# resQ

**resQ** is a much richer, mostly test-source-compatible replacement for
[`qspec`](https://github.com/nugend/qspec), plus a testing, benchmarking, and
discovery framework for **kdb+/q**. Existing qspec suites can run through the
`qspec` launcher without rewriting their DSL, assertions, fixtures, mocks, fuzz
tests, or perf blocks. resQ adds automated discovery, JUnit/JSON/xUnit reporters,
coverage, watch mode, process isolation, and rich diff output.

The compatibility promise is executable: resQ runs a pinned, unmodified copy of
qspec's seven public test files in its own test suite. qspec's private runner and
reporter internals are not compatibility APIs; the precise boundary and the few
intentional correctness differences are documented in
[qspec compatibility contract](docs/QSPEC_COMPATIBILITY.md) and
[migration guide](docs/MIGRATION.md).

## Project Status

The public qspec-compatible DSL and machine-readable result schemas are treated
as stable. The framework's own release gate runs strict normal and process-
isolated suites, its pinned upstream qspec contract, a coverage threshold, and
independent JSON/XML parsing. See [Continuous Integration](docs/CI.md).

## AI Assistance

Parts of the codebase and documentation were created or reviewed with AI
assistance.

## Key Features

- **High-Resolution Benchmarking**: Professional stats (min, max, avg, percentiles) and ASCII histograms built-in.
- **Automated Discovery**: Scans test source for unreferenced functions, writes an HTML report, and can generate boilerplate templates on request.
- **CI/CD Integration**: JUnit XML, xUnit XML, and JSON reporters with detailed metrics.
- **Retry support**: `retry[n; "desc"]{...}` re-runs a flaky test up to n+1 total attempts.
- **Advanced Utilities**:
  - **Fixtures**: Binary, text, and directory-based data injection.
  - **Mocking/Spies**: Clean function and variable mocking with auto-restoration.
  - **Parametrized Tests**: Run tests against a table of scenarios with `.tst.forall`.
  - **Async Testing**: Robust wait-for-condition and sleep utilities.
  - **Snapshot Testing**: Binary and text snapshots for complex data structures; text snapshots produce readable `git diff` output.
- **Coverage** (`resq cover`): `--source src/` inventories loaded and entirely unloaded modules, then `\l`/`system "l "` instrumentation records hits. One canonical model produces LCOV, detailed `coverage.json`, annotated HTML, and complete state output. Coverage is function-level by default; `-cov-statements` adds measured statement/line diagnostics. Independent function, line, and instrumentation-completeness gates are available, and line gates refuse partial denominators unless explicitly allowed. Compiled operators and derived functions are skipped.
- **Watch mode** (`resq watch`): Polls source and test directories and re-runs affected tests on change.

---

## Installation

Clone the repo at a release tag and put the launchers on your `PATH`:

```bash
git clone --branch v1.0.0 https://github.com/Piohrun/resq.git ~/.local/share/resq
ln -s ~/.local/share/resq/bin/resq ~/.local/bin/resq   # adjust to taste
ln -s ~/.local/share/resq/bin/qspec ~/.local/bin/qspec # drop-in qspec command
```

Pin the tag for CI. `main` moves, and a test framework that changes underneath
a pipeline turns an unrelated commit into a red build. `resq --version` reports
the release you are on; `git -C ~/.local/share/resq describe --tags` confirms
the checkout. Omit `--branch` only if you specifically want the development
tip.

The launcher resolves its install location (symlink-safe) and exports
`RESQ_HOME` for `resq.q` to find its modules, so you can invoke `resq`
from any directory and have it operate on **your** project's `tests/`,
not the framework's. It also supervises test completion: a stray `exit 0` in a
test or loaded application is forced to a failing status. You can set
`RESQ_HOME` and call `q $RESQ_HOME/resq.q ...` directly for interactive work,
but q does not let `.z.exit` change an already-requested exit code, so direct
invocation cannot provide that status guard.

The supported production baseline is kdb+/q 4.1.x on Linux x86-64. The launchers require
Bash plus `mktemp`, `chmod`, `rm`, and `rmdir` for their completion guard;
process isolation has additional command-line dependencies. See
[Getting Started](docs/GETTING_STARTED.md) for the supported path and a
CI-ready adoption sequence, and the
[compatibility matrix](docs/COMPATIBILITY_MATRIX.md) for the release gate.

---

## Quick Start

resQ comes with a unified CLI for all operations.

```bash
# Run tests (from your project root, after installing the launcher)
resq test tests/

# Run an existing qspec suite unchanged, with qspec assertion semantics
qspec tests/

# Run the bundled example
resq test examples/quickstart/test

# Run with HTML coverage
resq cover examples/quickstart/test

# Report source functions that are not referenced by tests
resq discover examples/quickstart/src examples/quickstart/test \
  -outDir artifacts/discovery
```

---

## Automated Test Discovery

Check which source-function names are referenced by test source, and optionally
generate boilerplate. This is a static name-presence audit, not proof that a
function executed; use `resq cover` for runtime coverage.

### Usage
```bash
q resq.q discover src/ tests/

# Also write stubs under artifacts/discovery/missingTests/
q resq.q discover src/ tests/ -scaffold -outDir artifacts/discovery
```

**Features:**
- **Visual Tree**: Instantly see which directories lack tests.
- **HTML report**: Always writes `coverage_report.html` to `outDir` (default `.`).
- **Smart Templates**: With `-scaffold`, generates ready-to-fill `should` blocks under `outDir/missingTests/`.
- **Namespace Aware**: Correctly identifies functions within `\d` namespace blocks.

Discovery exits 1 when any source function is unreferenced and 0 when all are
referenced. It strips q comments before scanning, but a live-code reference can
still count even if that code never executes.

---

## Benchmarking

```q
/ Simple benchmark
.tst.benchmark.hist[.tst.benchmark.measure[100; {sma[20;1000?100f]}]`time; 10];

/ Assert performance thresholds
perf["Fast SMA"; `maxTime`runs!(10; 100)]{
  sma[10;data];
};
```

---

## Writing Tests

### Basic Spec
```q
.tst.desc["Math Ops"]{
  should["add numbers correctly"]{
    (1 + 1) musteq 2;
  };
};
```

### Skip, Pending, and Conditional Skip
```q
.tst.desc["Feature Tests"]{
  skip["not implemented yet"]{
    .myFunc[] musteq 42;
  };

  pending["will implement later"];

  skipIf[.z.o like "w*"; "skip on Windows"]{
    .myFunc[] musteq 42;
  };
};
```

### Suite-Level Setup and Teardown (`beforeAll` / `afterAll`)
```q
.tst.desc["Database Suite"]{
  beforeAll{
    `conn mock hopen `:localhost:5000;
  };

  afterAll{
    hclose conn;
  };

  should["query returns rows"]{
    (count conn "select from trade") mustgt 0;
  };
};
```

`beforeAll` runs once before all expectations in the block. If it throws, the
block's tests are skipped and one error result is recorded (the run fails), but
other desc blocks still run. `afterAll` runs once after the block's tests even
if `beforeAll` failed. A throwing `afterAll` is recorded as a structured cleanup
error and fails the run; other cleanup tasks and suites still get a chance to
run.

---

## Running Specific Tests

Filter which suites or tests run without editing files:

```bash
# Run only suites whose title matches a pattern (glob, case-sensitive)
q resq.q test tests/ -only "Order*"

# Exclude matching suites
q resq.q test tests/ -exclude "*slow*"

# Run only suites tagged #fast (tags are #word tokens in the desc title)
q resq.q test tests/ -tag fast

# Exclude by tag
q resq.q test tests/ -exclude-tag slow

# List suites and tests without running them (exits 0)
q resq.q test tests/ -desc

# Run each test FILE in its own q subprocess (opt-in process isolation)
q resq.q test tests/ -isolate
q resq.q test tests/ -isolate -isolateTimeout 120   # per-file wall-clock cap (s)
q resq.q test tests/ -isolate -isolateWorkers 4     # bounded concurrent children

# Expose order-dependent tests reproducibly (does not touch q's global seed)
q resq.q test tests/ -random-order -seed 4242

# Tighten the local feedback loop using stable test IDs
q resq.q test tests/ -last-failed        # alias: -lf
q resq.q test tests/ -failed-first

# Split files across three CI jobs (zero-based)
q resq.q test tests/ -shard-index 0 -shard-count 3
```

Tags are `#word` tokens embedded in the suite title string:
```q
.tst.desc["Price validation suite #fast #unit"]{
  ...
};
```

---

## CI/CD and Exit Codes

resQ exits with a meaningful code by default — no extra flag is needed:

| Code | Meaning |
|------|---------|
| 0 | All tests passed |
| 1 | One or more tests failed or errored; also `-strict` with no executed tests, or `-strict` with a test that ran no assertions |
| 3 | No test files found (empty/missing directory) |
| 4 | File load error or explicitly-passed path not found |

Use `-noquit` to suppress the exit call (interactive sessions). Use `-exit` to
force exit-on-completion even if `resq.json` has `"exit": false`.

```bash
# Standard CI invocation — exits 1 on any failure
resq test tests/ -strict -isolate -isolateTimeout 120 \
  -junit -json -outDir artifacts/tests

# Hard stop on first failure (requires -exit for the process to actually stop)
q resq.q test tests/ -ff -exit
```

Run coverage separately because coverage instrumentation and process isolation
cannot be combined:

```bash
resq cover tests/ --source src/ -strict -cov-min 80 -json -outDir artifacts/coverage
```

See [Continuous Integration](docs/CI.md) for reporter filenames, q runner
licensing/prerequisites, and the checked-in GitHub Actions workflow.

---

## Robustness Features

### Strict Mode
Prevent false positives in CI pipelines.
```bash
q resq.q test -strict my_tests/
```
If no tests are found **or executed**, this flag forces a **non-zero exit code**.
A suite where every test was skipped counts as no executed tests under `-strict`.
Under `-strict`, a test that passes without running a single assertion is also a
failure: a `should` block's return value is ignored, so a bare expression such as
`0 < count warnings;` is discarded rather than checked. Wrap it as
`must[0 < count warnings; "..."]`. Without `-strict` these are listed after the
summary but do not fail the run.
Without `-strict`, an all-skipped suite still exits 0.

Under `-strict`, a snapshot that does not yet exist on disk is treated as a
**failure** rather than silently creating the file.

### Process Isolation (`-isolate`)
Run each discovered test **file** in its own `q` subprocess; the parent
aggregates the per-file results and applies the normal summary, reporters
(`-junit`/`-xunit`/`-json`), and exit codes.
```bash
q resq.q test tests/ -isolate
q resq.q test tests/ -isolate -isolateTimeout 120   # per-file timeout, default 300s
q resq.q test tests/ -isolate -isolateWorkers 4     # default 1; preserves file order
```
Isolation converts three run-killers into per-file failures instead of letting
one bad file corrupt the whole run: a test that calls `exit` (caught as
"process exited without producing results"), an infinite loop (killed at
`-isolateTimeout`, reported as a timeout — requires the `timeout` binary for
preemption), and a process-fatal error (`wsfull`/`stack`). Exit-code semantics
match the normal path (load errors → 4, any failure → 1, no files → 3).

Isolation is a resilience boundary, not a security sandbox. Child processes
inherit the invoking user's filesystem, environment, network, and credentials;
only run trusted test code. Each concurrent child also consumes memory and a q
runtime/licence allocation. See [Parallel execution](docs/PARALLEL.md).

Strict mode can also be enabled in `resq.json`:
```json
{
  "strict": true
}
```

### Namespace Isolation (Sandboxing)
Every test file is loaded into a unique generated namespace, which contains its
ordinary top-level declarations. Explicit writes to root/application namespaces,
external services, or the filesystem remain shared state; use fixtures, cleanup,
and process isolation where those effects matter.

At end of run, resQ empties the sandboxes it created, releasing whatever the test
files declared. It tracks them by registration, so a namespace of your own that
merely starts with `sandbox_` is never touched — which matters under `-noquit`,
watch mode, or when resQ is embedded in a longer-lived process. q cannot remove a
namespace, so the (now empty) names persist, exactly as for top-level names.

### Global Pollution Guard
The runner snapshots application namespaces before and after each `desc` suite.
If a suite introduces a name or modifies an existing global, resQ reports it.

For members added to existing namespaces, the runner cleans them up. For brand-new
top-level names, the runner clears the value to `::` and warns — q does not allow
removing a top-level identifier once defined, so the name persists but holds no
data. Test files are sandboxed so ordinary local variables do not leak; the guard
fires only for genuinely top-level names (e.g., bare `x:: 42` at the top level of
a file, outside any desc block).

Disable for very large sessions: `"pollutionGuard": false` in `resq.json`.

### Safe DSL Bindings
resQ keeps the implementation under `.tst.*` and never writes test helpers into
kdb+'s reserved `.q` namespace. During test-file loading, bare public DSL names
(`mock`, `fixture`, `should`, `musteq`, etc.) are bound to stable
`.tst.dsl.*` helpers. Explicit `.tst.*` calls remain supported, and a test-local
assignment or lambda parameter with the same spelling wins over the DSL.

The legacy `qNamespaceExports` configuration key is accepted for migration but
is deprecated and ignored; both values leave `.q` unchanged.

`-no-line-annotations` is the fail-safe for an unsupported constructor-rewrite
edge case. It preserves DSL execution but removes declaration line metadata and
the incomplete-constructor audit for that run.

### Quiet Mode
Suppress per-file load lines, the RUN AUDIT block, and per-suite output for
passing suites — failures still print fully:
```bash
q resq.q test tests/ -quiet
```

Output written directly by test code or benchmark helpers is not intercepted.

### Custom Test-File Discovery
Default discovery matches `test_*.q` and `*_test.q`. Override via `resq.json`:
```json
{
  "testFilePatterns": ["*_spec.q", "*Test.q"]
}
```

### Color Output
Console output is colorized when stdout is a TTY (Linux: `/dev/pts/*` or
`/dev/tty*` auto-detected; macOS defaults to color-on). Disable with:
- `NO_COLOR=1` environment variable (https://no-color.org)
- `.tst.diffColors:0b` in a test helper loaded before the run

---

## Documentation

See `docs/` for detailed guides:

| Guide | Purpose |
|-------|---------|
| `docs/GETTING_STARTED.md` | Installation, first test, qspec replacement, production adoption |
| `docs/API_REFERENCE.md` | Complete API — all DSL, assertions, CLI flags, config keys |
| `docs/REPORTING.md` | Console, JSON schema, JUnit/xUnit mappings, artifact names |
| `docs/OBSERVABILITY.md` | Stable dimensions and dashboard/ingestion guidance |
| `docs/ADAPTERS.md` | Stateless NDJSON and Allure 2 report adapters |
| `docs/ARCHITECTURE.md` | Namespace layout, file structure, exit codes (contributor reference) |
| `docs/COVERAGE.md` | Coverage instrumentation, LCOV output, HTML report |
| `docs/CI.md` | Production CI invocation, runner prerequisites, artifacts |
| `docs/COMPATIBILITY_MATRIX.md` | Supported q runtime and execution-mode parity gate |
| `docs/HARDENING_AUDIT.md` | Shell, path, temp, interrupt, and artifact hardening contract |
| `docs/SUPPORT.md` | Supported runtime/releases and defect severity |
| `docs/VERSIONING.md` | Public SemVer and deprecation policy |
| `docs/IDENTITY.md` | Stable test/case identity contract |
| `SECURITY.md` | Vulnerability reporting and execution trust boundary |
| `docs/FIXTURES.md` | Fixture scopes, lifecycle hooks, dependency injection |
| `docs/PARALLEL.md` | CI-level parallelism strategy |
| `docs/PBT.md` | Property-based testing with `holds` |
| `docs/PERFORMANCE.md` | Benchmarking and performance assertions |
| `docs/SNAPSHOTS.md` | Binary and text snapshot testing |
| `docs/TROUBLESHOOTING.md` | Common errors, exit codes, debug tips |
| `docs/WATCH.md` | Watch mode configuration |
| `docs/MIGRATION.md` | Migrating from qspec to resQ |
| `docs/QSPEC_COMPATIBILITY.md` | Versioned public qspec compatibility boundary |

See `docs/README.md` for a suggested reading order.

---

## Dependencies

- **Core in-process runner:** kdb+/q 4.1.x on Linux x86-64.
- **Launchers:** Bash plus `mktemp`, `chmod`, `rm`, and `rmdir` for the private
  completion marker.
- **Process isolation:** GNU `timeout` with `-k` and `sh` in addition to the
  launcher dependencies. These are not required when invoking q directly.

See [Continuous Integration](docs/CI.md#runner-requirements) for licences,
runner provisioning, and the security boundary.

## LLM Skill

`skill/SKILL.md` is a single-file Claude Code skill that teaches an LLM how to
set up resQ in a new project, write idiomatic tests, and avoid q-specific pitfalls.
Install with:

```bash
mkdir -p ~/.claude/skills/resq
cp skill/SKILL.md ~/.claude/skills/resq/SKILL.md
```

See `skill/README.md` for what it covers and how to keep it in sync.

## Acknowledgements

The BDD-style DSL (`desc` / `should` / `before` / `after`) is inspired by
`qspec` (MIT) — https://github.com/nugend/qspec — but resQ does not depend on it
at runtime.

## License
MIT License.
