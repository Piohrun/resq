---
name: resq
description: Set up and write tests with the resQ q/kdb+ test framework. Use whenever you are adding tests to a q codebase, debugging an existing resQ suite, or wiring resQ into a new project. The framework is a BDD-style runner with assertions, mocks/spies, fixtures, snapshots, fuzz, coverage, and a watch mode. Pairs naturally with the `q-kdb` skill — load that one too for general q syntax/idioms.
---

# resQ — q/kdb+ Test Framework Skill

This skill teaches you to install, configure, and write tests with **resQ**.
It is the q equivalent of jest / pytest / rspec: BDD-style `describe` /
`should` blocks, assertions, mocks, fixtures, snapshots, fuzz, coverage,
watch mode. Single-process, no external dependencies, kdb+ 4.x.

If the user's task involves writing q itself (not just tests), also load
the `q-kdb` skill — that one covers right-to-left evaluation, atomic
functions, qSQL quirks, etc. **Tests in this framework are still q code**
and the same pitfalls apply (especially: no operator precedence, `$[…]`
doesn't work inside qSQL phrases, `each` on atomics is redundant).

---

## 1. When to use this skill

Use when the user:

- Asks to **add tests** to a q codebase that uses resQ (look for `bin/resq`, a `tests/test_*.q` pattern, or `resq.q` at the repo root).
- Asks to **set up resQ** in a new project.
- Hits a resQ-specific error: "WARNING: No test files found", "introduced top-level names", "leaked handles", `FILE_LOAD_ERROR`.
- Is debugging a failing assertion, mock, fixture, or snapshot.
- Asks to wire resQ into CI, watch mode, or coverage.

If the user is writing general q code (not tests), this skill is wrong —
use `q-kdb` instead.

---

## 2. Install / detect

### Detect an existing install

```bash
ls -d /path/to/repo/bin/resq /path/to/repo/lib/dsl 2>/dev/null
```

If both exist, resQ is already vendored or installed in that repo and
you should run it via `./bin/resq` from any CWD.

### Detect a global install

```bash
command -v resq && resq -version
```

### Install fresh into a project

Two supported patterns:

**A) Vendor into the project** (no global install):
```bash
git clone https://github.com/Piohrun/resq.git ./vendor/resq
./vendor/resq/bin/resq test tests/
```

**B) Global install** (one resQ, many projects):
```bash
git clone https://github.com/Piohrun/resq.git ~/.local/share/resq
ln -s ~/.local/share/resq/bin/resq ~/.local/bin/resq
# now `resq test tests/` works from any project
```

The `bin/resq` launcher exports `RESQ_HOME` and runs from the user's
CWD, so the framework finds its own modules independently of where the
user invokes it.

---

## 3. Project layout it expects

```
your-repo/
├── src/                       # your code
│   └── …
├── tests/                     # test files
│   ├── test_thing.q           # default discovery: test_*.q or *_test.q
│   ├── fixtures/              # any non-discovered helpers
│   └── snapshots/             # binary snapshot store (auto-created)
└── resq.json                  # optional config
```

**Default discovery convention**: files matching `test_*.q` or
`*_test.q`. Override via `resq.json` (`testFilePatterns: ["*_spec.q"]`)
for projects that use other conventions.

---

## 4. Writing a test — the canonical pattern

Every test file looks like this:

```q
/ tests/test_calculator.q
\d .                                      / always start at root namespace

/ Load the code under test from THIS file's location, not CWD.
/ This pattern survives the user invoking from any directory.
.t.projectRoot: "/" sv -2 _ "/" vs $[":" = first f: string .utl.FILELOADING;
                                       1 _ f; f];
system "l ", .t.projectRoot, "/src/calculator.q";

.tst.desc["Calculator"]{

    before{ `.calc.history mock () };       / reset state per expectation

    should["add two numbers"]{
        (.calc.add[2; 3]) musteq 5;
    };

    should["record the call in history"]{
        .calc.add[1; 1];
        count[.calc.history] musteq 1;
    };

    after{ /* runs even on failure; restore env if needed */ };
};
```

Key rules for a test file:

1. **Top-level `.tst.desc[<title>; <body>]`** registers a spec.
2. **`should[<desc>; <body>]` inside the desc body** registers an expectation.
3. **`before` / `after`** hooks run around *each* expectation.
4. **All `.tst.*` and DSL names** are available globally (assertion verbs are root-exported).
5. **The test file's own variables** live in a private sandbox namespace
   (`.sandbox_S…`) — they auto-clean.
6. **Top-level names you create** (e.g. `.foo.x: 1`) trigger the pollution
   guard. Either don't create them, or use `registerSpecCleanup` to wipe them.

---

## 5. Assertions cheat sheet

| Verb | Meaning |
|---|---|
| `must[cond; msg]` | Bare boolean assertion |
| `musteq[l; r]` | `~` equality with rich diff on failure |
| `mustmatch[l; r]` | Alias of `musteq` (terser) |
| `mustne[l; r]` | Inequality |
| `mustnmatch[l; r]` | Negated match |
| `mustlt`, `mustgt`, `mustlike`, `mustin`, `mustnin`, `mustwithin`, `mustdelta` | Comparators |
| `mustthrow[pattern; code]` | Code must throw an error matching pattern |
| `mustnotthrow[ignored; code]` | Code must NOT throw |
| `mustmatchignoringorder[l; r]` | Set-style equality for lists/tables |
| `mustincludecols[l; r]` | Table `l` includes all columns of table `r` |
| `mustmatchs[actual; name]` | Binary snapshot match (`.snap` file) |
| `mustmatchst[actual; name]` | Text snapshot match (`.snap.txt` file) |
| `mustBeFasterThan[code; ms]` | Performance budget |
| `mustHaveBeenCalledWith[name; args]` | Spy assertion |

All assertions are also available with a `.tst.` prefix.

### Pitfall — q's operator precedence in assertions

q is strictly right-to-left with **no operator precedence**. This burns
test authors over and over:

```q
/ BAD: parses as `first (exec id from (active musteq id2))`
first exec id from active musteq id2;

/ GOOD: parens around the left operand
(first exec id from active) musteq id2;

/ BAD: parses as `2 + (2 musteq 4)` -> type error
2 + 2 musteq 4;

/ GOOD
(2 + 2) musteq 4;
```

**Rule of thumb**: if your assertion's left-hand-side is anything more
than a bare identifier or literal, parenthesise it.

### Pitfall — single-char strings vs char atoms

`string 0` returns a single-character *string* (`,"0"`). `"0"` is a *char
atom*. `~` rejects them as different types. Use multi-char inputs in
tests:

```q
.tst._covNumStr[0] musteq "0"      / FAILS: ,"0" ≁ "0"
.tst._covNumStr[42] musteq "42"    / passes
```

### Pitfall — `` `key!`sym `` shorthand

`` `a!`b `` between two symbols is parsed as `enum`, not dict. Build
single-entry dicts explicitly when the value is a symbol:

```q
(enlist `foo)!enlist `bar          / correct
`foo!`bar                          / 'type error
`foo!5                             / OK (sym!int is fine)
```

---

## 6. Mocking and spying

```q
should["call the underlying API once"]{
    `.api.send mock {[req] (`mocked; req)};   / replace
    .my.workflow[];
    .tst.callCount[`.api.send] musteq 1;
};

should["restore originals automatically"]{
    `.svc.compute mock {99};
    .svc.compute[] musteq 99;
    / .tst.restore[] is called between expectations -- no manual cleanup.
};
```

Spies record every call and let you assert on them:

```q
should["pass the right args to logEvent"]{
    .tst.spy[`.user.logEvent; (::)];          / pass-through spy
    .user.create[`alice; `$"alice@example.com"; `user];
    `.user.logEvent mustHaveBeenCalledWith (`userCreated; 1);
};
```

**Constraints**:
- `.tst.spy` supports up to arity 8 functions (q's lambda ceiling).
- Cannot mock identifiers in reserved namespaces (`.q`, `.Q`, `.z`, `.h`, `.j`, `.tst`, `.resq`, `.utl`).
- Mock restore is automatic at the end of each expectation.

### Mock state and framework internals — one sharp edge

`mock` records originals so they can be put back by `.tst.restore[]`,
which the framework calls between expectations. Most tests never need to
think about this — restoration just works.

**But:** anything you invoke inside a test body that *itself* calls
`.tst.restore[]` will wipe your mocks out from under you. In practice
the only thing in the public API that does this is
`.tst.runAllPhase.finalCleanup` (the end-of-run cleanup phase — it
restores mocks as part of its job). If you ever write a test that calls
`finalCleanup` directly (most likely a meta-test of the framework
itself), don't use `mock` in the `before` hook — do explicit save /
restore for just the keys that test perturbs, with a comment noting
why. The pattern:

```q
should["finalCleanup transitions executionState"]{
    / Manual save / restore: finalCleanup calls .tst.restore[] mid-body,
    / which would undo any `before`-hook mocks before the assertion runs.
    saved: .tst.app.executionState;
    .tst.app.executionState: `running;
    .tst.runAllPhase.finalCleanup[];
    .tst.app.executionState musteq `completed;
    .tst.app.executionState: saved;
};
```

Two `tests/test_runner.q` specs use this pattern; everything else in the
codebase uses mock and is fine.

---

## 7. Fixtures and cleanup

Two cleanup hooks. Pick by scope:

```q
should["clean up at expectation end"]{
    out: .tst.tempFile ".csv";              / auto-cleanup via registerCleanup
    (hsym `$out) 0: enlist "data";
    must[.utl.isFile out; "should write"];
    / out is hdel'd as this expectation finishes
};

should["clean up after the spec's resource teardown"]{
    fn: "scratch.txt";
    / Use spec scope when the cleanup needs the runner's handle teardown
    / to have run first (e.g. unlinking a file whose handle is leaked).
    .tst.registerSpecCleanup[{[p] @[hdel; hsym `$p; {}]}; enlist fn];
    hsym[`$fn] 0: enlist "data";
    h: hopen hsym `$fn;
    / Leave h open. Runner closes it, then the cleanup hdel's the file.
};
```

**Rule**: if your cleanup `hdel`s a file whose handle is held open
inside the same expectation, you need `registerSpecCleanup`. Otherwise
expectation-scope `registerCleanup` (or just `tempFile`) is fine.

For richer fixtures (setup/teardown lifecycle, scopes, injection):

```q
.tst.registerFixtureWithOpts[`database; ();
    `scope`setup`teardown!(
        `session;                           / one connection for the whole run
        {[_] hopen `:localhost:5000};
        {[h] hclose h}
    )
];

should["query the database"]{
    h: .tst.getFixture[`database];
    rows: h "select count i from trade";
    rows mustgt 0;
};
```

---

## 8. Running the suite

```bash
# Default: discover under tests/
resq test tests/

# A single file
resq test tests/test_calculator.q

# Junit XML for CI
resq test tests/ -junit -outDir reports/

# Coverage (LCOV + HTML in outDir)
resq cover src/ tests/

# Quiet mode (only failures + summary)
resq test tests/ -quiet

# Strict mode (no tests = non-zero exit)
resq test tests/ -strict

# Watch mode
resq watch src/ tests/

# Filter by tag, pattern, or spec name
resq test tests/ -only "*integration*"
resq test tests/ -exclude "*slow*"
resq test tests/ -tag fast,unit
```

### Exit codes (granular, for CI)

| Code | Meaning |
|---|---|
| 0 | PASS |
| 1 | FAIL — at least one test failed |
| 2 | CONFIG_ERROR |
| 3 | NO_TESTS — none discovered (with `-strict` this is reliable) |
| 4 | LOAD_ERROR — a test file failed to load |
| 5 | PARTIAL — some tests errored or were skipped |

---

## 9. Config file (`resq.json`)

All keys are optional; defaults shown:

```json
{
    "fmt": "text",
    "outDir": ".",
    "exit": false,
    "strict": false,
    "failFast": false,
    "failHard": false,
    "pollutionGuard": true,
    "qNamespaceExports": true,
    "fuzzLimit": 100,
    "maxTestTime": 0,
    "reportLimit": 50000,
    "reportListLimit": 1000,
    "testFilePatterns": ["test_*.q", "*_test.q"],
    "diffLargeTableThreshold": 1000,
    "diffHugeTableThreshold": 10000
}
```

Common overrides:
- `testFilePatterns`: BDD shops set `["*_spec.q"]`, xUnit shops `["*Test.q"]`.
- `pollutionGuard: false`: opt out of deep namespace snapshotting for very large sessions.
- `qNamespaceExports: false`: avoid writing helper aliases into the reserved `.q` namespace.
- `diffLargeTableThreshold` / `diffHugeTableThreshold`: tune adaptive table-diff sampling.

CLI flags always win over config file.

---

## 10. Common errors and how to read them

| Symptom | Likely cause |
|---|---|
| `WARNING: No test files found` | Your files don't match `test_*.q` / `*_test.q`. Either rename or set `testFilePatterns`. Default `resq test` (no path) looks for `./tests/`. |
| `CRITICAL LOAD ERROR in tests/foo.q: assign` | You assigned to a q built-in name (e.g. `abs:`, `key:`, `count:`). Rename. |
| `CRITICAL LOAD ERROR in tests/foo.q: [` | Bracket / syntax error somewhere in the file, often a missing `]` or `}`. |
| `[error]` with `Error: type` on a passing-looking assertion | Almost always q precedence; parenthesise the left operand. See §5. |
| `WARNING: Test '<title>' introduced top-level names: <list>` | The test created a top-level identifier (e.g. `.foo.x: 1`). q can't remove top-level names; values are cleared to `::`. Either restructure the test or accept the warning. |
| `WARNING: Test Suite '<title>' leaked handles: <list>` | The test opened a handle and didn't close it. Runner closed it for you. Cleanup the test or accept the warning. |
| `NOTE: file-handle leak detection requires Linux /proc; …` | You're on macOS/Windows. Leak detection only sees IPC handles. File leaks go undetected. |

---

## 11. Adding resQ to an existing q codebase — step-by-step

Use this checklist when bootstrapping a new test suite.

1. **Install** resQ (see §2). Verify `resq -version` works.
2. **Create `tests/`** at the repo root (or wherever your project keeps tests).
3. **Pick a discovery convention.** If your codebase already uses one (look for `*_spec.q`, `*_test.q`, `tests/*.q`), pick a `testFilePatterns` that matches and put it in `resq.json`. Otherwise stick with the default.
4. **Write a smoke test** (`tests/test_smoke.q`):
   ```q
   .tst.desc["Smoke"]{
       should["the runner is alive"]{ 1 musteq 1 };
   };
   ```
5. **Run** `resq test tests/`. You should see one passing test. If you don't, check §10.
6. **Add a real test** loading one of your source files using the relative-to-test pattern in §4. Run again.
7. **Wire CI.** Use `-junit -outDir reports/ -exit` so the JUnit XML lands in `reports/test-results.xml` and the process exits with the suite status.
8. **(Optional)** Add `resq.json` for repo-level defaults.
9. **(Optional)** Set up coverage: `resq cover src/ tests/` writes LCOV + HTML to `outDir`.

---

## 12. Pre-emit verification (use before returning code to the user)

- [ ] Every assertion's left operand is a bare token or parenthesised. (q precedence trap)
- [ ] No `\`key!\`sym` shorthand dicts. (Parsed as enum.)
- [ ] No assignment to a q built-in name. (`abs`, `count`, `key`, `value`, `type`, `set`, `get`, `like`, `in`, `each`, `over`, `scan`, `prior`, `first`, `last`, `enlist`, etc.)
- [ ] If a test creates files, either `tempFile` or one of the `registerCleanup` hooks is used.
- [ ] If a test leaks a handle deliberately (to test the runner), the file cleanup is `registerSpecCleanup` (spec scope), not `registerCleanup`.
- [ ] No test mocks anything in `.q`, `.Q`, `.z`, `.h`, `.j`, `.tst`, `.resq`, `.utl` — mock will refuse.
- [ ] If loading the SUT, the path is derived from `.utl.FILELOADING` (test-file location), not from CWD.
- [ ] If asserting that something "doesn't exist," remember q can't remove top-level names — `not \`foo in key \`` will return `1b` only if no test ever created `.foo` in this session.
- [ ] If the test calls `.tst.runAllPhase.finalCleanup` (or anything else that triggers `.tst.restore[]` mid-body), the `before` hook is NOT using `mock` for the keys under test — `finalCleanup` would wipe them. Use manual save/restore for those specs only.

---

## 13. Pointers for deeper questions

The repository's `docs/` directory has long-form references:

| Topic | File |
|---|---|
| Full API reference | `docs/API_REFERENCE.md` |
| Architecture | `docs/ARCHITECTURE.md` |
| Coverage | `docs/COVERAGE.md` |
| Discovery engine | `docs/DISCOVERY.md` |
| Fixtures | `docs/FIXTURES.md` |
| Parallel execution | `docs/PARALLEL.md` |
| Property-based / fuzz | `docs/PBT.md` |
| Performance | `docs/PERFORMANCE.md` |
| Snapshots | `docs/SNAPSHOTS.md` |
| Troubleshooting | `docs/TROUBLESHOOTING.md` |
| Watch mode | `docs/WATCH.md` |

CHANGELOG.md tracks behaviour changes per release.
