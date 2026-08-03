# Runtime Code Coverage

resQ provides function coverage and opt-in measured statement/line coverage via
`resq cover`. It instruments source functions at load time and records which
functions or injected statement probes execute.

**Line coverage requires `-cov-statements`.** Without it resQ reports function
coverage only and emits no line records at all — see below for why.

## Usage

```bash
resq cover src/ tests/
```

Pass source directories first, then test directories. resQ discovers and runs all test files and emits coverage reports when the run completes.

### Include and exclude filters

Coverage filters match each normalized absolute source path using q `like`
patterns. Pass comma-separated patterns:

```bash
resq cover tests/ \
  -cov-include "/work/project/src/*" \
  -cov-exclude "/work/project/src/generated/*"
```

An include list admits only matching files; excludes are then removed. Quote
patterns so the shell does not expand them. q `like` does not support arbitrary
regular expressions and can signal `nyi` for patterns with several `*`
wildcards, so prefer an absolute path prefix followed by one `*`.

Without an explicit include, resQ excludes its own `<RESQ_HOME>/lib/*` modules
while allowing application sources elsewhere (including the bundled examples).
An explicit include overrides that framework exclusion, which is primarily
useful when testing resQ itself.

---

## How It Works

### Instrumentation

When a test file loads a source file via `\l path` or `system "l ", path`, the coverage-aware loader intercepts the load, instruments every named function defined in that file (wrapping it to record a hit), then makes the function available as normal. The test file does not need to be modified.

Files loaded by other mechanisms (e.g. `\l` inside a helper that is itself loaded outside the watched path, or `value` calls that eval source strings) are not instrumented.

Compiled operators and derived functions (e.g. `+/`, `each`) are skipped — they cannot be wrapped.

### Statement-level coverage (`-cov-statements`, opt-in)

By default there are no line records at all (see below). Pass `-cov-statements`
— or set `"covStatements": true` — for **measured** per-statement coverage:

```bash
resq cover tests/ -cov-statements
```

```q
.calc.classify:{[x]          / classify[5] only
    if[x < 0;                DA:2,1
        :`negative           DA:3,0   <- branch not taken
    ];
    if[x = 0;                DA:5,1
        :`zero               DA:6,0   <- branch not taken
    ];
    `positive                DA:8,1
 };                          LF:5  LH:3  -> 60%
```

Probes go on every top-level statement and on statements inside `if[…]`,
`do[…]` and `while[…]`, which evaluate each argument in turn. `$[…]` is
deliberately left alone: it is a conditional *expression* whose branches are
values, and a probe among them would change what it returns. Only lines carrying
a probe are counted, so `LF` is the number of statements, not the number of
lines.

**Why this is opt-in.** It works by rewriting your function bodies at load time
and re-evaluating them in their original namespace. Each function is attempted
independently and verified afterwards — the rewritten definition must parse, and
must keep the same parameters, locals and referenced globals, or the original is
restored and that function reports at function level only (no line records).

Behaviour preservation is checked by execution, not by argument:
`tests/test_coverage_differential.q` generates q functions from a grammar of the
constructs that make instrumentation hard — guards with early return, loops,
conditional expressions, nested lambdas, strings holding semicolons, comments,
multi-line brackets — then calls each one before and after instrumenting it and
requires identical return values *and* identical side effects. It runs a fixed
corpus plus seeded random functions on every suite run, and was swept clean to
seed 400. Reintroducing the line-start insertion defect makes it fail, so it
demonstrably catches the class of bug it exists for.

Even with that, it remains a transformation of the code under test. **resQ cannot instrument itself**: with
its own `lib/` instrumented the framework stops running tests, because the code
being rewritten is the code doing the rewriting. Turn statement coverage on
deliberately, and confirm your suite still passes with it on before trusting the
numbers.

### Line records are emitted only where lines were measured

Default mode instruments **whole functions**. It knows "this function ran" and
nothing finer, so it emits `FN`/`FNDA`/`FNF`/`FNH` and **no `DA`/`LF`/`LH`
records**:

```
SF:/proj/src/calc.q
FN:1,.calc.classify
FNDA:1,.calc.classify   <- called; which branches ran is unknown
FN:15,.calc.unused
FNDA:0,.calc.unused     <- never called
FNF:2
FNH:1
end_of_record
```

resQ used to derive line records here by giving every line of a called function
that function's hit count. That was actively misleading: a 13-line function with
three branches, of which a test exercised one, emitted `LF:13 LH:13` — **100%
line coverage** in Codecov, Coveralls, SonarQube and `genhtml`, and a *passing*
`-cov-min 90`. An absent record reads as "not measured"; a fabricated one reads
as "measured and fine". Only the second can hide a gap.

With `-cov-statements`, line records come from executed statement probes and are
real measurements:

```
DA:2,1
DA:4,0     <- branch not taken
LF:9
LH:5
```

### Granularity

| Mode | Measures | LCOV records | `-cov-min` gates on |
|------|----------|--------------|---------------------|
| default | function entered at least once | `FN`/`FNDA`/`FNF`/`FNH` | function % |
| `-cov-statements` | each statement probe | the above plus `DA`/`LF`/`LH` | line % |

A function-level 100% means every function was entered, **not** that every branch
inside them ran. The console says so explicitly when reporting on that basis.

### What `-cov-statements` can still miss

A function whose statements cannot be rewritten safely keeps its `FN`/`FNDA`
records and contributes **no** `DA` lines — it drops out of the line
denominator rather than being counted as covered. Rewrites are rejected when
the body cannot be re-evaluated, or when re-evaluating it would change the
function's parameters, locals, or the globals it binds. So a line percentage is
always a statement about the code that was actually instrumented; compare `LF`
against the file's real statement count if you need to know how much that is.
The function percentage, reported alongside, covers every discovered function
either way.

---

## Output

Reports are written to `outDir` (default: `.`):

| File | Contents |
|------|----------|
| `coverage.lcov` | Standard LCOV with SF/FN/FNDA/FNF/FNH records, plus DA/LF/LH under `-cov-statements`. Consumable by `genhtml`, Codecov, Coveralls, SonarQube. |
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

Gate a build with an integer percentage from 0 through 100:

```bash
resq cover tests/ -strict -cov-min 80 -json -outDir artifacts/coverage
```

`-cov-min` compares the LCOV line percentage when line records exist
(`-cov-statements`) and otherwise the function percentage; the console names
which basis it used, and says explicitly when statement execution was not
measured. The run exits 1 when it misses the threshold, measures no
executable code, or cannot generate its reports. The JSON report includes the
exact counts, percentage, threshold, basis, and pass/fail decision under its
`coverage` object. Configuration-file equivalent: `"coverageMin": 80`.

---

## Limitations

- **No line data by default** — default mode is function-level and emits no
  `DA`/`LF`/`LH` records, so `-cov-min` gates on function coverage. Use
  `-cov-statements` when branch/statement execution matters, and validate that
  source transformation against your code.
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
