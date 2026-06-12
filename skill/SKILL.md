---
name: resq
description: Set up and write tests with the resQ q/kdb+ test framework. Use whenever you are adding tests to a q codebase, debugging an existing resQ suite, or wiring resQ into a new project. The framework is a BDD-style runner with assertions, mocks/spies, fixtures, snapshots, fuzz, coverage, and a watch mode. Pairs naturally with the `q-kdb` skill — load that one too for general q syntax/idioms.
---

# resQ — q/kdb+ Test Framework Skill

resQ is the q equivalent of jest / pytest / rspec: BDD-style `describe` /
`should` blocks, assertions, mocks/spies, fixtures, snapshots, fuzz,
coverage, watch mode. Single-process, no external dependencies, kdb+ 4.x.

**Tests are still q code** — the q pitfalls below apply. If the task
involves writing q itself (not just tests), also load the `q-kdb` skill.

## 1. When to use

- Add tests to a q codebase that uses resQ (look for `bin/resq`, `resq.q`
  at the repo root, or a `tests/test_*.q` pattern).
- Set up resQ in a new project.
- Debug a resQ error: "No test files found", "introduced top-level
  names", "leaked handles", a `CRITICAL LOAD ERROR`, a failing
  assertion/mock/snapshot.
- Wire resQ into CI, watch mode, or coverage.

For general (non-test) q code, this skill is the wrong one — use `q-kdb`.

## 2. Setup — pick the scenario

q must be on PATH. resQ runs as `q <home>/resq.q <args>` or via the
`bin/resq` launcher (which exports `RESQ_HOME` then execs that). Both run
from **your** CWD, so test paths you pass resolve against your project.

| Scenario | How to run |
|---|---|
| **A — Already installed on disk** (workplace case). Find it: `ls -d <dir>/bin/resq <dir>/resq.q`. | `<install>/bin/resq test tests/` **or** `q <install>/resq.q test tests/`. Both work from any CWD; no env var needed. `RESQ_HOME` is only required if you copy `resq.q` out to a launcher of your own. |
| **B — Vendor into the project** (no global install) | `git clone https://github.com/Piohrun/resq.git ./vendor/resq` then `./vendor/resq/bin/resq test tests/` |
| **C — Global install** (one resQ, many projects) | clone to `~/.local/share/resq`, then `ln -s ~/.local/share/resq/bin/resq ~/.local/bin/resq`. Now `resq test tests/` works anywhere. |

Verify with `<install>/bin/resq -version` (prints `resQ version …`).

## 3. Project layout

```
your-repo/
├── src/                  # your code
├── tests/
│   ├── test_thing.q      # discovery: test_*.q OR *_test.q (default)
│   └── __snapshots__/    # snapshot store (auto-created)
└── resq.json             # optional config
```

`resq test` with no path defaults to `./tests/` if it exists. Override
discovery globs via `resq.json` (`"testFilePatterns": ["*_spec.q"]`).

## 4. Writing a test — canonical pattern

```q
/ tests/test_calculator.q
\d .                                   / start at root namespace

/ Load the code under test relative to THIS file (survives any CWD).
.t.root: "/" sv -2 _ "/" vs $[":" = first f: string .utl.FILELOADING;
                              1 _ f; f];
system "l ", .t.root, "/src/calculator.q";

.tst.desc["Calculator"]{

    before{ `.calc.history mock () };   / reset state before EACH should

    should["adds two numbers"]{
        (.calc.add[2; 3]) musteq 5;     / parenthesise the LHS — see §6
    };

    should["records the call"]{
        .calc.add[1; 1];
        (count .calc.history) musteq 1;
    };

    after{ };                           / runs even on failure
};
```

Rules:
1. `.tst.desc[<title>; <body>]` registers a spec (suite). `describe` is
   an alias.
2. `should[<desc>; <body>]` inside it registers an expectation. `it` is
   an alias.
3. All DSL/assertion names are root-exported, so unqualified `should`,
   `musteq`, `mock` resolve inside test files (they fall through `.q`).
4. The test file's own locals live in a private sandbox namespace and
   auto-clean. **Top-level names you create** (`.foo.x: 1`) during a
   test trip the pollution guard — values are cleared to `::` (q can't
   remove top-level names). Loader assignments at file scope (like
   `.t.root` above) are fine; they happen before execution.

⚠️ **Spaced source paths**: `\l` / `system "l …"` throw `'nyi` on any
path containing a space (a q limitation, not resQ). Keep your `src/`
paths space-free. Test **files** under spaced directories are fine —
discovery handles them; only the in-file loader line is affected.

## 5. Block keywords (inside a desc body)

| Keyword | Signature | Notes |
|---|---|---|
| `should` / `it` | `should[desc; {body}]` | one expectation |
| `before` / `after` | `before{body}` | run around EACH expectation; `after` runs even on failure |
| `beforeAll` / `afterAll` | `beforeAll{body}` | once per desc block. Must be **inside** the block (outside → ignored, with a warning). `beforeAll` throw → block's tests skipped + one error row; `afterAll` still runs. A throwing `afterAll` warns only. |
| `skip` | `skip[reason; {body}]` | not run; reported skipped |
| `pending` | `pending[reason]` | placeholder — **NO code block** |
| `skipIf` | `skipIf[cond; reason; {body}]` | runs body unless `cond` |
| `retry` | `retry[n; desc; {body}]` | up to n+1 attempts; before/after re-run each attempt; a late pass is noted |
| `testOnly` | `testOnly[desc; {body}]` | per-suite focus: if any test in a suite is `testOnly`, only those run; siblings reported **skipped** + a `NOTE: testOnly active …` line. Focus is per-suite; other suites run normally |
| `holds` | `holds[desc; props; {[x] body}]` | property/fuzz test (§8) |
| `perf` | `perf[desc; props; {body}]` | performance test |
| `alt` | `alt[{ ...should... }]` | groups expectations sharing the surrounding before/after |

### Tagging & filtering

A `#word` token inside a **desc/suite title** becomes a tag on that
suite (tags are suite-level — `#word` inside a `should` title does not
filter). CLI filters match against suite tags:

```q
.tst.desc["Calculator #fast"]{ should["adds #unit"]{ ... }; };
```
```bash
resq test tests/ -tag fast            # run only suites tagged #fast
resq test tests/ -exclude-tag slow    # drop suites tagged #slow
resq test tests/ -only "*Calc*"       # title glob include
resq test tests/ -exclude "*slow*"    # title glob exclude
```
`-tag fast` and `-tag "#fast"` are equivalent (both forms are expanded).

## 6. Assertions

| Verb | Meaning |
|---|---|
| `must[cond; msg]` | bare boolean assertion |
| `musteq[l; r]` | `~` equality; rich FAILURE DIFF on mismatch. **Preferred.** |
| `mustmatch[l; r]` | exact synonym of `musteq` (same diff). Not "terser" — identical behaviour. |
| `mustne[l; r]` | inequality |
| `mustnmatch[l; r]` | negated `~` match |
| `mustlt`, `mustgt` | `<` / `>` |
| `mustlike[l; r]` | `l like r` (r is a glob) |
| `mustin`, `mustnin` | membership / non-membership |
| `mustwithin[l; r]` | `l within r` (r is a 2-item range) |
| `mustdelta[tol; l; r]` | **3-arg**: `l` within `±abs tol` of `r` |
| `mustthrow[pattern; {code}]` | code must throw matching `pattern` (§7) |
| `mustnotthrow[pattern; {code}]` | code must NOT throw (or not match `pattern`) |
| `mustmatchignoringorder[l; r]` | set-style equality for lists/tables |
| `mustincludecols[l; r]` | table `l` includes all columns of table `r` |
| `mustmatchs[actual; name]` | binary snapshot (`.snap`) |
| `mustmatchst[actual; name]` | text snapshot (`.snap.txt`) |
| `mustBeFasterThan[{code}; ms]` | runtime budget (20-run avg) |
| `mustAllocLessThan[{code}; bytes]` | allocation budget (20-run avg) |
| `mustHaveBeenCalledWith[name; args]` | spy assertion (§9) |

**camelCase aliases** (same behaviour as their lowercase targets):
`mustEqual`, `mustNotEqual`, `mustLessThan`, `mustGreaterThan`,
`mustMatchSnapshot`, `mustMatchTextSnapshot`, `mustMatchIgnoringOrder`.

Every verb is also available with a `.tst.` prefix.

A failing `musteq` reads: `Got <actual> — expected <expected>` (plus
type/diff/length hints), and prints a FAILURE DIFF block. If you instead
see `Error: type` on a passing-looking assertion, it is a real q error —
almost always the precedence trap below.

### Pitfall — no operator precedence (the #1 trap)

q is strictly right-to-left. The assertion verb is infix, so the **left
operand binds the whole expression to its left** unless parenthesised:

```q
first exec id from active musteq id2    / BAD: first(exec id from(active musteq id2))
(first exec id from active) musteq id2   / GOOD
2 + 2 musteq 4                           / BAD: 2 + (2 musteq 4) -> type error
(2 + 2) musteq 4                         / GOOD
```
**Rule**: if the LHS is more than a bare token or literal, parenthesise it.

### Pitfall — single-char string vs char atom

`string 0` is a 1-char *string* (`,"0"`); `"0"` is a char *atom*. `~`
rejects them as different types. Use multi-char inputs, e.g.
`f[42] musteq "42"`, not `f[0] musteq "0"`.

### Pitfall — `` `key!`sym `` shorthand

`` `a!`b `` is parsed as `enum`, not a dict. For a single-entry dict
with a symbol value use `` (enlist `foo)!enlist `bar ``. `` `foo!5 ``
(sym!int) is fine.

## 7. `mustthrow` — patterns are q `like` GLOBS

The pattern is matched against the error message with `like`, so a
**bare substring fails** unless it happens to be the whole message. Use
glob wildcards:

```q
mustthrow["*type*"; {1 + `a}];        / infix match — recommended
mustthrow["typ*"; {1 + `a}];          / prefix glob
mustthrow[`type; {1 + `a}];           / symbol pattern (coerced to string)
mustthrow[("*type*"; "*len*"); {…}];  / LIST of patterns: any match passes
```

Accepts a string, a symbol, a symbol vector, or a list of string
patterns. **Misuse guard**: passing code first (e.g. writing it infix
`{code} mustthrow "pat"`) raises:
`mustthrow expects [pattern; code] — got code first; did you call it infix? Use mustthrow[pattern; {code}]`.

## 8. Fuzz / property tests (`holds`)

```q
.tst.desc["sort is idempotent"]{
    holds["asc twice == asc once"; (enlist `runs)!enlist 50]{[x]
        (asc asc x) musteq asc x;
    };
};
```

`props` is a dict (a single-entry `` (enlist `k)!enlist v `` is the
safe build form). Known keys:
- `runs` — iteration count.
- `maxFailRate` — tolerate up to this failure fraction (strict `>`).
- `vars` — a dict mapping var names to generators; each iteration's `x`
  is a dict keyed by those names. A generator is a type-name symbol
  (`` `symbol``, `` `int``…), a value list to pick from, or a function:

```q
holds["typed inputs"; `runs`vars!(20; `a`b!(`symbol; 1 2 3))]{[x]
    / x`a is a random symbol, x`b is one of 1 2 3
    (type x`a) musteq -11h;
};
```

## 9. Mock vs spy — decide by what you assert

| You need to… | Use | Records calls? |
|---|---|---|
| swap an implementation / stub a return value | `name mock impl` | **No** |
| assert call count / args (`callCount`, `lastCall`, `mustHaveBeenCalledWith`) | `.tst.spy[name; impl]` | **Yes** |

`mock` alone does **not** record — `.tst.callCount` stays `0` after a
plain `mock`. To record, use `spy`. Both auto-restore between
expectations (the runner calls `.tst.restore[]` after each); no manual
cleanup.

```q
should["mock just swaps the impl"]{
    `.svc.compute mock {99};
    (.svc.compute[]) musteq 99;
};

should["spy records AND returns"]{
    .tst.spy[`.api.send; {[req] (`spied; req)}];   / real-or-fake impl
    (.api.send[`hi]) musteq (`spied; `hi);          / spy returns impl's value
    (.tst.callCount[`.api.send]) musteq 1;
    (.tst.lastCall[`.api.send]) musteq enlist `hi;  / args tuple (1-arg -> enlist)
    `.api.send mustHaveBeenCalledWith enlist `hi;
};

should["pass-through spy: record without changing behaviour"]{
    .tst.spy[`.user.logEvent; (::)];                / (::) means "keep original impl"
    .user.create[`alice];
    (.tst.callCount[`.user.logEvent]) musteq 1;
};
```

`.tst.spy` signature: `spy[name; impl]`. `impl` is a function used as
the replacement; `(::)` keeps the original. `lastCall` returns the args
as a list (1 arg → `enlist arg`; 2+ → the tuple). Constraints:
- Up to arity-8 functions (q's lambda ceiling).
- Cannot mock/spy names in reserved namespaces: `.q .Q .z .h .j .tst
  .resq .utl` (raises "Cannot mock a system namespace").

> Meta-test note: anything that calls `.tst.restore[]` mid-body (e.g.
> `.tst.runAllPhase.finalCleanup`) wipes your mocks. Only framework
> self-tests hit this — use explicit save/restore there. See
> `docs/ARCHITECTURE.md`.

## 10. Fixtures & cleanup

```q
should["temp file auto-cleans"]{
    out: .tst.tempFile ".csv";              / hdel'd when this expectation ends
    (hsym `$out) 0: enlist "data";
    must[.utl.isFile out; "written"];
};
```

Two cleanup scopes: expectation-scope `.tst.registerCleanup` (or just
`tempFile`), and spec-scope `.tst.registerSpecCleanup[fn; args]` — use
the latter only when the cleanup must run **after** the runner's handle
teardown (e.g. `hdel`ing a file whose handle you left open in the same
expectation). Richer lifecycle fixtures live in `.tst.registerFixtureWithOpts`
+ `.tst.getFixture` — see `docs/FIXTURES.md`.

## 11. Running & CI

```bash
resq test tests/                       # discover under tests/
resq test tests/test_calculator.q      # one file
resq test tests/ -quiet                # failures + summary only
resq test tests/ -junit -outDir reports/   # JUnit -> reports/test-results.xml
resq test tests/ -strict               # 0 EXECUTED tests => failure
resq test tests/ -desc                 # LIST tests, do not run them (exit 0)
resq cover src/ tests/                 # coverage: LCOV + HTML in outDir
resq watch src/ tests/                 # re-run on change
```

Other true facts:
- **Color** auto-disables when `NO_COLOR` is set or output is not a TTY.
- A **syntax error** in a test file reports `CRITICAL LOAD ERROR in <file>
  near line N: …`.
- **Text snapshots**: first run prints `NOTE: text snapshot created …`
  (review & commit). Under `-strict`, a missing snapshot **fails**
  instead of being created.

### Exit codes (verified)

| Code | When |
|---|---|
| **0** | all pass; also skips-with-passes, and `-desc` listing |
| **1** | any failure or error; **also** `-strict` + 0 executed tests, and `-strict` + all-skipped |
| **3** | no tests discovered (without `-strict`) |
| **4** | load/syntax error, or an explicitly-passed path not found |

There is no `2` or `5` — those were removed. Note: with `-strict`, a
no-tests run inserts a synthetic error row and exits **1**, not 3.

## 12. Config (`resq.json`)

All keys optional; CLI flags win over the file. Common ones:
`"testFilePatterns": ["*_spec.q"]`, `"strict": true`, `"failFast": true`,
`"outDir": "reports"`, `"fmt": "text"|"junit"|"json"`,
`"pollutionGuard": false` (skip namespace snapshotting),
`"qNamespaceExports": false` (**caveat**: then unqualified DSL names like
`should`/`musteq` no longer resolve — you must use `.tst.*` everywhere).

## 13. Common errors

| Symptom | Cause / fix |
|---|---|
| `WARNING: No test files found` | files don't match `test_*.q` / `*_test.q`; rename or set `testFilePatterns`. `resq test` (no path) looks for `./tests/`. |
| `CRITICAL LOAD ERROR … near line N: assign` | assigned to a q builtin name (`abs:`, `count:`, `key:`…). Rename. |
| `CRITICAL LOAD ERROR … near line N: [` or `}` | bracket/syntax error near that line. |
| `'nyi` during a `\l`/`system "l"` load | spaced path in the loader line (§4). Remove spaces from the src path. |
| `Error: type` on a passing-looking assertion | q precedence — parenthesise the LHS (§6). A genuinely failing `musteq` shows a FAILURE DIFF, not a type error. |
| `mustthrow expects [pattern; code] — got code first…` | you called it infix / code-first. Use `mustthrow[pattern; {code}]`. |
| `Explicit test path not found: <path>` | a CLI path doesn't exist (exit 4). Fix the typo. |
| `Snapshot missing under -strict` | run once without `-strict` to create + commit the snapshot. |
| `WARNING: Test '<t>' introduced top-level names: <list>` | the test made a top-level name; q can't remove it (cleared to `::`). Restructure or accept. |
| `WARNING: … leaked handles: <list>` | a handle was left open; runner closed it. Add cleanup or accept. |

## 14. Pre-emit checklist (before returning code)

- [ ] Every assertion LHS is a bare token or parenthesised (precedence).
- [ ] No `` `key!`sym `` shorthand dicts (parsed as enum).
- [ ] No assignment to a q builtin (`abs count key value type set get like in each over scan first last enlist`…).
- [ ] `mustthrow` patterns are **globs** (`"*x*"`/`"x*"`), and called as `mustthrow[pattern; {code}]` (pattern first).
- [ ] `mustdelta` is 3-arg `[tol; l; r]`.
- [ ] Asserting on call count/args ⇒ used **`.tst.spy`**, not plain `mock`.
- [ ] No mock/spy on `.q .Q .z .h .j .tst .resq .utl`.
- [ ] Tests creating files use `tempFile` / `registerCleanup` (or `registerSpecCleanup` if a held handle blocks the `hdel`).
- [ ] SUT loaded via `.utl.FILELOADING`-derived path, not CWD; src path has no spaces.
- [ ] Tags that should filter are in the **suite (desc) title**, as `#word`.

## 15. Deeper docs

`docs/API_REFERENCE.md`, `ARCHITECTURE.md`, `COVERAGE.md`, `MIGRATION.md`
(qspec migration), `FIXTURES.md`, `PBT.md` (fuzz), `SNAPSHOTS.md`,
`TROUBLESHOOTING.md`, `WATCH.md`; `docs/README.md` is the index.
`CHANGELOG.md` tracks behaviour changes.
