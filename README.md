# resQ

**resQ** is a testing, benchmarking, and discovery framework for **kdb+/q**. It
extends the BDD-style foundations of `qspec` with features needed for
professional CI/CD pipelines: automated test discovery, JUnit/JSON/xUnit
reporters, property-based testing, coverage, watch mode, and rich diff output.

## Project Status

This is an **alpha** release. APIs and behaviours may change without notice.

## AI Assistance

Parts of the codebase and documentation were created or reviewed with AI
assistance.

## Key Features

- **High-Resolution Benchmarking**: Professional stats (min, max, avg, percentiles) and ASCII histograms built-in.
- **Automated Discovery**: Scans codebase for untested functions and generates boilerplate templates.
- **CI/CD Integration**: JUnit XML, xUnit XML, and JSON reporters with detailed metrics.
- **Retry support**: `retry[n; "desc"]{...}` re-runs a flaky test up to n+1 total attempts.
- **Advanced Utilities**:
  - **Fixtures**: Binary, text, and directory-based data injection.
  - **Mocking/Spies**: Clean function and variable mocking with auto-restoration.
  - **Parametrized Tests**: Run tests against a table of scenarios with `.tst.forall`.
  - **Async Testing**: Robust wait-for-condition and sleep utilities.
  - **Snapshot Testing**: Binary and text snapshots for complex data structures; text snapshots produce readable `git diff` output.
- **Coverage** (`resq cover`): Instruments functions loaded via `\l` or `system "l "` and emits LCOV, a per-function HTML report (`coverage.html`), and `coverage_state.txt`. Coverage is function-level; compiled operators and derived functions are skipped.
- **Watch mode** (`resq watch`): Polls source and test directories and re-runs affected tests on change.

---

## Installation

Clone the repo and put the `bin/resq` launcher on your `PATH`:

```bash
git clone https://github.com/Piohrun/resq.git ~/.local/share/resq
ln -s ~/.local/share/resq/bin/resq ~/.local/bin/resq   # adjust to taste
```

The launcher resolves its install location (symlink-safe) and exports
`RESQ_HOME` for `resq.q` to find its modules, so you can invoke `resq`
from any directory and have it operate on **your** project's `tests/`,
not the framework's. You can also set `RESQ_HOME` manually if you
prefer to call `q $RESQ_HOME/resq.q ...` directly.

---

## Quick Start

resQ comes with a unified CLI for all operations.

```bash
# Run tests (from your project root, after installing the launcher)
resq test tests/

# Or invoke q directly from the resq repo
q resq.q test examples/quickstart/test

# Run with HTML coverage
q resq.q cover examples/quickstart/test

# Start Discovery Engine
q resq.q discover examples/quickstart/src examples/quickstart/test
```

---

## Automated Test Discovery

Check your codebase for coverage gaps and generate boilerplate instantly.

### Usage
```bash
q resq.q discover src/ tests/
```

**Features:**
- **Visual Tree**: Instantly see which directories lack tests.
- **Smart Templates**: Generates ready-to-fill `should` blocks for untested functions.
- **Namespace Aware**: Correctly identifies functions within `\d` namespace blocks.

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
if `beforeAll` failed; a throwing `afterAll` prints a warning but does not fail
the suite.

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
| 1 | One or more tests failed or errored; also `-strict` with no executed tests |
| 3 | No test files found (empty/missing directory) |
| 4 | File load error or explicitly-passed path not found |

Use `-noquit` to suppress the exit call (interactive sessions). Use `-exit` to
force exit-on-completion even if `resq.json` has `"exit": false`.

```bash
# Standard CI invocation — exits 1 on any failure
q resq.q test tests/

# Hard stop on first failure (requires -exit for the process to actually stop)
q resq.q test tests/ -ff -exit
```

---

## Robustness Features

### Strict Mode
Prevent false positives in CI pipelines.
```bash
q resq.q test -strict my_tests/
```
If no tests are found **or executed**, this flag forces a **non-zero exit code**.
A suite where every test was skipped counts as no executed tests under `-strict`.
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
```
Isolation converts three run-killers into per-file failures instead of letting
one bad file corrupt the whole run: a test that calls `exit` (caught as
"process exited without producing results"), an infinite loop (killed at
`-isolateTimeout`, reported as a timeout — requires the `timeout` binary for
preemption), and a process-fatal error (`wsfull`/`stack`). Exit-code semantics
match the normal path (load errors → 4, any failure → 1, no files → 3).

Strict mode can also be enabled in `resq.json`:
```json
{
  "strict": true
}
```

### Namespace Isolation (Sandboxing)
Every test file is automatically loaded into a unique, isolated namespace. Tests
cannot accidentally pollute the global namespace or affect unrelated tests.

### Global Pollution Guard
The runner snapshots the global namespace before and after each test. If a test
introduces a name or modifies an existing global, resQ reports it.

For members added to existing namespaces, the runner cleans them up. For brand-new
top-level names, the runner clears the value to `::` and warns — q does not allow
removing a top-level identifier once defined, so the name persists but holds no
data. Test files are sandboxed so ordinary local variables do not leak; the guard
fires only for genuinely top-level names (e.g., bare `x:: 42` at the top level of
a file, outside any desc block).

Disable for very large sessions: `"pollutionGuard": false` in `resq.json`.

### Compatibility Exports
resQ exports DSL helpers in the root namespace and `.tst.*`. For legacy
compatibility it can also export helpers into `.q`, but `.q` is reserved by kdb+.
To disable those compatibility exports:
```json
{
  "qNamespaceExports": false
}
```

With `"qNamespaceExports": false`, unqualified DSL names (`mock`, `fixture`,
`should`, `musteq`, etc.) will **not** resolve inside sandboxed test files.
Flag-off mode requires fully-qualified `.tst.*` names throughout your test files.

### Quiet Mode
Suppress per-file load lines, the RUN AUDIT block, and per-suite output for
passing suites — failures still print fully:
```bash
q resq.q test tests/ -quiet
```

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
| `docs/API_REFERENCE.md` | Complete API — all DSL, assertions, CLI flags, config keys |
| `docs/ARCHITECTURE.md` | Namespace layout, file structure, exit codes (contributor reference) |
| `docs/COVERAGE.md` | Coverage instrumentation, LCOV output, HTML report |
| `docs/FIXTURES.md` | Fixture scopes, lifecycle hooks, dependency injection |
| `docs/PARALLEL.md` | CI-level parallelism strategy |
| `docs/PBT.md` | Property-based testing with `holds` |
| `docs/PERFORMANCE.md` | Benchmarking and performance assertions |
| `docs/SNAPSHOTS.md` | Binary and text snapshot testing |
| `docs/TROUBLESHOOTING.md` | Common errors, exit codes, debug tips |
| `docs/WATCH.md` | Watch mode configuration |
| `docs/MIGRATION.md` | Migrating from qspec to resQ |

See `docs/README.md` for a suggested reading order.

---

## Dependencies

- **kdb+ 4.x** (4.0 or newer recommended).
- No runtime dependencies beyond q itself.

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
