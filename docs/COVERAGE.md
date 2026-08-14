# Runtime Code Coverage

resQ provides function coverage plus opt-in measured statement/line and
conditional-edge coverage via `resq cover`. It instruments source functions at
load time and records function entries, statement probes, and branch outcomes.

**Line coverage requires `-cov-statements`.** Without it resQ reports function
coverage only and emits no line records at all — see below for why.

**Branch coverage requires `-cov-branches`.** It measures the true/false edges
of `if[...]`, `while[...]`, and every condition in lazy `$[...]` expressions.

## Usage

```bash
resq cover tests/ --source src/
```

Test paths remain positional. Declare the production source inventory separately
with `--source` (or `-source`); pass multiple files/directories as a comma-separated
value. resQ recursively inventories every `.q` file below those roots before it
runs tests. Statically discoverable functions in modules that are never loaded
are seeded at zero and therefore remain in the denominator and every coverage
artifact.

Configuration-file equivalent:

```json
{"coverageSources": ["src", "shared"]}
```

An explicit source declaration that resolves to no `.q` files is an error. This
fail-closed behavior prevents a misspelled path from producing a green 0/0 run.

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

Before loading tests, `--source` builds the static function inventory. When a
test file then loads a source file via `\l path` or `system "l ", path`, the
coverage-aware loader intercepts the load, instruments every named function
defined in that file (wrapping it to record a hit), then makes the function
available as normal. The test file does not need to be modified.

Files loaded by other mechanisms (e.g. `\l` inside a helper that is itself loaded outside the watched path, or `value` calls that eval source strings) are not instrumented.

Compiled operators and derived functions (e.g. `+/`, `each`) are skipped — they cannot be wrapped.

### Coverage lifecycle and watch mode

Each coverage run owns the wrappers it installs. At finalization resQ disables
probes, restores owned originals in reverse installation order, and clears the
session's hit/probe state. `initCoverage` performs the same idempotent stop first,
so embedded callers may safely repeat init/run/stop cycles.

If a live definition is no longer the wrapper resQ installed, resQ leaves that
foreign value untouched and fails the coverage lifecycle closed. A failed
assignment retains only the affected wrapper/original pair so the function
remains callable and a later `stopCoverage[]` can retry it.

`resq watch` starts a fresh coverage session immediately before every changed-
file rerun and tears it down in the run finalizer. The idle watcher therefore
holds no instrumentation wrappers, and hit counts do not leak between cycles.

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

Probes go on every top-level statement, eligible statements inside anonymous
lambdas, and statements inside `if[…]`, `do[…]` and `while[…]`, which evaluate
each argument in turn. `$[…]` is deliberately left alone: it is a conditional
*expression* whose branches are values, and a probe among them would change what
it returns. LCOV still rolls sites up by source line; detailed JSON and HTML
retain stable per-site identities, anonymous-lambda ownership, and hit counts.

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
runs the same seeded random stream, and requires identical return values,
errors, side effects, and post-call random state. Each generated function goes
through the full file pipeline: statement/branch rewrite, function wrapper, hit
accounting, and canonical-model projection must all succeed. It
runs a fixed corpus plus 75 seeded random functions on every suite run, and was
swept clean to seed 400. Reintroducing the line-start insertion defect makes it fail, so it
demonstrably catches the class of bug it exists for.

Even with that, it remains a transformation of the code under test. **resQ cannot instrument itself**: with
its own `lib/` instrumented the framework stops running tests, because the code
being rewritten is the code doing the rewriting. Turn statement coverage on
deliberately, and confirm your suite still passes with it on before trusting the
numbers.

### Conditional-edge coverage (`-cov-branches`, opt-in)

Branch mode wraps only each condition, then returns the condition value
unchanged to q's original control form:

```q
.calc.grade:{[s]
    if[s<0; :`invalid];
    $[s>90; `A;
      s>80; `B;
      s>70; `C;
      `F]
 };
```

This inventories four sites (one `if`, three `$` conditions) and eight edges.
Calling `grade 95` hits the false edge of the `if` and the true edge of the
first `$` condition; later `$` conditions remain unevaluated, proving their
values stayed lazy. `while` records a true edge for iterations and its final
false edge on termination. Each site has a stable `branch_<hash>` identity,
source line/column, condition index, and two stable `edge_<hash>` identities.

The runtime uses q's own conditional truthiness (including numeric atoms) to
classify an edge, then passes the original value through. A value that q cannot
use as a control condition credits neither edge and still reaches the original
control form, which raises its original error. The differential corpus pins
return/error behavior, namespace bindings, side effects, and RNG state.

Use it independently or with statement coverage:

```bash
resq cover tests/ --source src/ -cov-statements -cov-branches
```

LCOV receives standard `BRDA`, `BRF`, and `BRH` records. The metric is
conditional-edge coverage—not path coverage, MC/DC, or proof that every value
expression was evaluated. `do[...]` is not a boolean branch and is not counted.
Conditions inside eligible anonymous lambdas are instrumented in the same
atomic rewrite. They retain the enclosing named function plus a stable
`lambdaId`, depth, and source location. LCOV emits their `BRDA` records under
the source file and line but deliberately emits no invented `FN`/`FNDA` name.

### Nested lambdas and atomic rollback

resQ inventories each anonymous lambda under its enclosing named function.
Stable `statement_<hash>`, `branch_<hash>`, `edge_<hash>`, and `lambda_<hash>`
identities are checkout-relative and appear in detailed JSON, HTML, and state.
The named function remains the only LCOV function identity.

The entire named definition—including every nested probe—is evaluated and
accepted as one unit. Binding-shape verification recursively compares
parameters, locals, and globals for the outer and compiled nested lambdas after
normalizing only resQ's probe helpers. If any level fails to parse or changes
bindings, resQ restores the original named function and excludes every site in
that definition from the measured denominator. No partially rewritten nested
lambda can remain installed.

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

| Mode | Measures | LCOV records | Available gates |
|------|----------|--------------|-----------------|
| default | function entered at least once | `FN`/`FNDA`/`FNF`/`FNH` | `-cov-min`, `-cov-functions-min` |
| `-cov-statements` | each safely instrumented statement probe | the above plus `DA`/`LF`/`LH` | the above plus `-cov-lines-min`, `-cov-completeness-min` |
| `-cov-branches` | true/false edges for eligible `if`, `while`, and `$` conditions | function records plus `BRDA`/`BRF`/`BRH` | function gates plus `-cov-branches-min`, `-cov-branch-completeness-min` |
| both | statements and conditional edges in one verified rewrite | all records above | all independent gates above |

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

resQ reports statement instrumentation completeness as
`instrumented functions / eligible functions`. Each function that lacks probes
has one canonical fallback reason:

- `statement_mode_disabled`: statement instrumentation was not requested;
- `source_not_loaded`: present in `--source`, but never loaded during the run;
- `function_wrapper_unavailable`: loaded, but no safe callable wrapper exists;
- `rewrite_rejected`: function coverage works, but the statement rewrite was
  rejected by parsing or shape-preservation checks.

These counts appear in JSON as `coverage.fallbackCounts`; completeness appears
as `statementFunctionsInstrumented`, `statementFunctionsEligible`, and
`statementInstrumentationPercent`.

Branch completeness is site-based. `branchSitesEligible`,
`branchSitesInstrumented`, `branchInstrumentationPercent`, and
`branchInstrumentationComplete` reveal the denominator directly. Eligible
sites in unloaded manifest files remain at zero hits with
`source_not_loaded`; a loaded function whose whole rewrite is rejected uses
`rewrite_rejected`. Ineligible nested sites remain visible but do not inflate
`BRF`. A branch gate refuses an empty or partial eligible-site denominator.

---

## Output

Reports are written to `outDir` (default: `.`):

| File | Contents |
|------|----------|
| `coverage.lcov` | Standard LCOV function records, `DA`/`LF`/`LH` under statement mode, and `BRDA`/`BRF`/`BRH` under branch mode. |
| `coverage.json` | [Schema v2](schema/resq-coverage-v2.schema.json) detailed canonical model: totals, eligibility/completeness, fallbacks, files, functions, line roll-ups, stable statement sites, anonymous owners, branch sites, edges, hits, and optional bounded contexts. |
| `coverage.html` | Annotated source/function tables plus branch-site locations, edge hits, completeness, fallbacks, and optional context detail. |
| `coverage_state.txt` | Grep-friendly v5 `F` function, `S` statement-site, `B` branch-site, `E` edge, `C` context, and `M` attributed-metric records, including zero-hit and anonymous-owner state. |

LCOV, detailed JSON, HTML, and state are rendered from the same in-memory
coverage snapshot. The self-suite parses their outputs and requires function,
statement, and branch totals to agree. `test-results.json` embeds the same
aggregate summary and independent gate decisions; `coverage.json` carries the
detailed model.

`tools/validate_coverage.py coverage.json --report test-results.json` performs
dependency-free semantic validation beyond the structural schema: every
percentage is recomputed, aggregate rows are reconciled with their children,
covered flags must agree with hits, and context metrics must join to known
functions, sites, and edges. CI additionally runs an isolated correctness lane
and uses `tools/reconcile_coverage.py` to require the same manifest, execution
inventory, verdicts, and assertion counts from the non-isolated coverage lane.
Only run identity/timing, isolation metadata, coverage configuration, and
coverage artifacts are permitted to differ.

### Per-test and per-attempt attribution (opt-in)

`-cov-contexts` records the function, statement, and branch hits produced while
each test attempt is active and groups retries under the stable execution ID:
`caseId` for a declarative row, otherwise `testId`.
`-cov-attempt-contexts` implies it and instead records one stable context per
attempt. LCOV and every aggregate counter/gate are unchanged: aggregate probes
are updated first and context accounting is a separate trapped data plane.

```bash
resq cover tests/ --source src/ -cov-statements -cov-branches \
  -cov-contexts -cov-context-max 10000 \
  -cov-context-entry-max 250000
```

The active interval includes the expectation's `before`, body, fixture
teardown, and `after`. Source loading, `beforeAll`/`afterAll`, retry cleanup,
registered/final teardown, and work that runs after the attempt boundary (for
example a timer callback) are stored under the reserved `unattributed` context.
Contexts beyond `-cov-context-max` are folded into `overflow`. After
`-cov-context-entry-max` unique context/metric pairs, existing pairs continue
counting but new pairs are dropped. `contextMeasurement.summary` exposes
`overflowActivations`, `droppedMetricHits`, and `truncated`; loss is never
silent. Configuration keys are `covContexts`, `covAttemptContexts`,
`coverageContextMax`, and `coverageContextEntryMax`.

`.tst.mergeCoverageContexts` merges coverage JSON `contextMeasurement`
documents by stable context and metric identity. It validates detail modes and
metadata, sums duplicate hits, applies the lowest declared bounds after stable
sorting, and is commutative. `bin/resq-merge` applies the same identity contract
while summing aggregate function/statement/branch records from a complete shard
topology and writes merged `coverage.json` plus LCOV. Coverage itself remains a
separate non-isolated command because in-process instrumentation cannot observe
isolated children.

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

For a trustworthy project-wide gate, add the source inventory:

```bash
resq cover tests/ --source src/ -strict -cov-min 80 -json -outDir artifacts/coverage
```

`-cov-min` compares the complete function percentage, including when
`-cov-statements` produces line records. Statement instrumentation can reject
unsafe rewrites, so its denominator may cover only part of the function
inventory; using that partial denominator for a legacy gate could produce a
false green. The console reports measured lines as a diagnostic and names the
function basis used by the gate. The run exits 1 when it misses the threshold, measures no
executable code, or cannot generate its reports. The JSON report includes the
exact counts, percentage, threshold, basis, and pass/fail decision under its
`coverage` object. Configuration-file equivalents: `"coverageMin": 80` and
`"coverageSources": ["src"]`.

### Independent coverage gates

For new CI, prefer the explicit thresholds:

```bash
resq cover tests/ --source src/ -cov-statements \
  -cov-branches \
  -cov-functions-min 80 \
  -cov-lines-min 75 \
  -cov-completeness-min 95 \
  -cov-branches-min 70 \
  -cov-branch-completeness-min 100
```

- `-cov-functions-min N` gates the complete static function inventory.
- `-cov-lines-min N` gates only statements carrying real probes.
- `-cov-completeness-min N` gates the percentage of inventoried functions that
  were safely statement-instrumented.
- `-cov-branches-min N` gates eligible true/false edges.
- `-cov-branch-completeness-min N` gates safely instrumented eligible sites.

A line gate fails closed when statement instrumentation is incomplete, even if
the measured subset exceeds its threshold. The checked quickstart contract
currently measures 48 of 59 source lines and 51 of 72 statement sites, with all
20 eligible functions instrumented; its line basis is therefore complete. To
knowingly gate an incomplete measured subset, add `-cov-allow-partial` (configuration:
`"allowPartialLineCoverage": true`). JSON exposes each decision under
`coverage.gates.functions`, `.lines`, and `.completeness`, plus the overall
`coverage.passed` verdict. Branch decisions are `.branches` and
`.branchCompleteness`. Branch percentage gates always fail closed on partial
site instrumentation; there is deliberately no branch equivalent of
`-cov-allow-partial`.

---

## Limitations

- **Line data is diagnostic** — default mode emits no `DA`/`LF`/`LH` records.
  `-cov-statements` adds measured records for safely rewritten functions, but
  the legacy `-cov-min` gate stays function-based. `-cov-lines-min` is available
  for CI and refuses partial instrumentation unless explicitly acknowledged.
- **`\l` / `system "l "` only** — the loader intercepts these two forms. Custom loaders are not auto-detected unless loader hijacking is explicitly enabled (experimental, see below).
- **Compiled operators skipped** — `+/`, `each`, `':'`, etc. cannot be wrapped.
- **Branch coverage is conditional-edge coverage** — no path or MC/DC records.
  Eligible anonymous-lambda conditions are included under their enclosing
  function; dynamically constructed source and compiled operators remain out of
  scope.

---

## Loader Hijacking (Experimental)

For codebases that load source via a custom loader function rather than `\l`, set `.tst.loaderHijackEnabled: 1b` to allow hijacking:

```q
.tst.loaderHijackEnabled: 1b;
.tst.loader.autoHijack["/opt/kdb/core"];
```

This is **off by default** and **experimental**. `resq discover` does not require it. Only enable it if your codebase is confirmed to use a custom loader and the default `\l`-interception misses significant coverage.
