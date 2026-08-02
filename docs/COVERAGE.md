# Runtime Code Coverage

resQ provides **function-level code coverage** tracking via `resq cover`. It instruments your source functions at load time and records which ones are called during the test run.

## Usage

```bash
resq cover src/ tests/
```

Pass source directories first, then test directories. resQ discovers and runs all test files and emits coverage reports when the run completes.

---

## How It Works

### Instrumentation

When a test file loads a source file via `\l path` or `system "l ", path`, the coverage-aware loader intercepts the load, instruments every named function defined in that file (wrapping it to record a hit), then makes the function available as normal. The test file does not need to be modified.

Files loaded by other mechanisms (e.g. `\l` inside a helper that is itself loaded outside the watched path, or `value` calls that eval source strings) are not instrumented.

Compiled operators and derived functions (e.g. `+/`, `each`) are skipped — they cannot be wrapped.

### Line records are derived, not measured

The LCOV output carries `DA:` line records and `LF`/`LH` totals, so standard
coverage services (Codecov, SonarQube, Coveralls, `genhtml`) accept it and show a
line percentage. **Read that number correctly:** resQ instruments whole
functions, not statements. Every executable line of a function inherits that
function's hit count — blank and comment lines are excluded, but a branch inside
a called function that never executed still reads as covered.

```
FN:5,.calc.unused
FNDA:0,.calc.unused     <- never called
DA:5,0                  <- so all its lines report 0
DA:6,0
LF:7
LH:3
```

So a line percentage from resQ answers *"how much of the code was reached at
function granularity?"*, not *"which statements ran?"*. It is a real and useful
signal — an uncalled function shows as fully uncovered — but it will read higher
than a statement-level tool would report on the same suite. Treat it as
directional, and use `FNF`/`FNH` when you want the number resQ actually measures.

### Granularity

Coverage is **function-level**: a function is marked as hit if it was called at least once during the run. Line-level coverage is not available.

---

## Output

Reports are written to `outDir` (default: `.`):

| File | Contents |
|------|----------|
| `coverage.lcov` | Standard LCOV with SF/FN/FNDA/FNF/FNH records. Consumable by `genhtml`, Codecov, Coveralls, SonarQube. |
| `coverage.html` | Per-function HTML report showing hit/miss status for each instrumented function. |
| `coverage_state.txt` | Human-readable dump of the complete coverage state at run end. |

### Generating HTML locally

```bash
genhtml coverage.lcov -o report/
open report/index.html
```

---

## CI/CD Integration

The `coverage.lcov` file is industry-standard and works with:

- **GenHTML**: `genhtml coverage.lcov -o report/`
- **Codecov / Coveralls**: Upload directly.
- **SonarQube**: Import as generic test coverage.

---

## Limitations

- **Function-level only** — no line-level data.
- **`\l` / `system "l "` only** — the loader intercepts these two forms. Custom loaders are not auto-detected unless loader hijacking is explicitly enabled (experimental, see below).
- **Compiled operators skipped** — `+/`, `each`, `':'`, etc. cannot be wrapped.

---

## Loader Hijacking (Experimental)

For codebases that load source via a custom loader function rather than `\l`, set `.tst.loaderHijackEnabled: 1b` to allow hijacking:

```q
.tst.loaderHijackEnabled: 1b;
.tst.loader.autoHijack["/opt/kdb/core"];
```

This is **off by default** and **experimental**. `resq discover` does not require it. Only enable it if your codebase is confirmed to use a custom loader and the default `\l`-interception misses significant coverage.
