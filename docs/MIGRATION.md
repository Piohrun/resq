# Migrating from qspec to resQ

resQ is test-source-compatible with qspec's public surface. The recommended
drop-in path is the `bin/qspec` launcher: it adds test mode and qspec comparison
semantics automatically, so existing test files and legacy runner options can
stay unchanged.

```bash
qspec tests/                 # existing qspec invocation, now backed by resQ
```

The promise is pinned in the repository: `tests/test_qspec_upstream.q` runs
byte-identical copies of qspec's seven public test files from commit
`9b846b68a8d808e472ba504d18c325b14b468087` through that launcher on every full
resQ test run. This guide covers the intentional boundary beyond that contract.

---

## Source-Compatible Surface

The following qspec constructs work in resQ without changes:

| qspec | resQ equivalent | Notes |
|-------|-----------------|-------|
| `.tst.desc` / `describe` | `.tst.desc` / `describe` | Identical |
| `.tst.should` / `should` | `.tst.should` / `should` | Identical |
| `it` | `it` | Alias for `should` |
| `.tst.before` / `before` | `.tst.before` / `before` | Identical |
| `.tst.after` / `after` | `.tst.after` / `after` | Identical |
| `alt` | `alt` | Hook masking and hooks declared after expectations are preserved |
| `mock` | `mock` | Same test-facing form; automatic restoration retained |
| `fixture` / `fixtureAs` | `fixture` / `fixtureAs` | File, text, splayed, and directory fixtures |
| `holds` | `holds` | Extended — see below |
| `perf` | `perf` | Opt-in with `-perf` / `-performance`, as in qspec |

---

## Assertion Names — Unchanged

**resQ uses the same assertion names as qspec.** Every qspec assertion exists in
resQ under the same name and arity:

`must`, `musteq`, `mustne`, `mustmatch`, `mustnmatch`, `mustlt`, `mustgt`,
`mustlike`, `mustin`, `mustnin`, `mustwithin`, `mustdelta`, `mustthrow`,
`mustnotthrow`.

Nothing needs renaming. resQ adds `mustmatchignoringorder`, `mustincludecols`,
`mustmatchs` / `mustmatchst` (snapshots), `mustBeFasterThan`, `mustAllocLessThan`,
`mustHaveBeenCalledWith`, and camelCase aliases (`mustEqual`, `mustNotEqual`, …).

qspec's own `test/test_assertions.q` runs unmodified under resQ and passes,
including its assertions on exact failure-message wording for
`mustthrow`/`mustnotthrow`.

Failure messages otherwise use `Got X — expected Y` wording, and a mismatch
prints a FAILURE DIFF block.

---

## Drop-in launcher and the `-qspec-compat` switch

For an existing qspec work repository, install `bin/qspec` on `PATH` and keep
the old command:

```bash
qspec tests/
```

The launcher is symlink-safe, keeps the caller's working directory, invokes
resQ's test mode, and enables `-qspec-compat`. It also accepts qspec's legacy
runner spellings: `-desc`/`-describe`, `-xunit`, `-junit`,
`-perf`/`-performance`, `-exclude`, `-only`, `-pass`, `-noquit`,
`-fuzz-display-limt`/`-fdl`, `-ff`/`-fail-fast`, and
`-fh`/`-fail-hard`.

When invoking resQ directly, enable the same comparison compatibility explicitly:

```bash
resq test tests/ -qspec-compat          # or --qspec-compat
```
or in `resq.json`:
```json
{ "qspecCompat": true }
```

It restores qspec's `musteq` (`=`) and `mustne` (`<>`) semantics while keeping
resQ improvements such as table comparison, isolation, coverage, reporters,
and `-strict`. Without it, a comparison that qspec would have accepted fails
with a message naming the difference and pointing here, so migration is
self-guiding rather than guesswork.

The launcher deliberately does **not** restore qspec false positives such as
`must[0N; ...]` or swapped `must["message"; condition]`; those tests did not
prove their condition in qspec. They fail loudly and need a local assertion fix,
not a suite rewrite.

Recommended: use `qspec` for a no-rewrite replacement. Move to `resq test`
without compatibility only when you want to adopt resQ's stricter comparisons.

---

## Assertion Semantics — Read This Before Migrating

The names match; the comparison operators and `must` validation intentionally
differ in native resQ mode. This is where a working qspec suite can go red.
Each case below was verified against both implementations.

| Expression | qspec | resQ | Why |
|---|---|---|---|
| `1 1 1 musteq 1` | pass | **fail** | qspec's `musteq` is `=` (elementwise, broadcasts a scalar); resQ's is `~` (whole-value match) |
| `1 musteq 1.0` | pass | **fail** | `~` is type-strict; `=` is not |
| `([]v:1 2) musteq ([]v:1 2)` | `'type` | pass | `~` compares tables; `=` cannot |
| `mustne[1 2 3; 1 2 4]` | fail | **pass** | qspec's `mustne` is `<>`, meaning "every element differs"; resQ's is `not ~` |
| `must[0N; …]` | pass | **fail** | a null is not a truth value |
| `must["message"; cond]` | pass | **fail** | swapped arguments — `all` mapped any non-empty string to true |

Unchanged from qspec: `must[count x; …]` and any other numeric condition
(non-zero is true, exactly as q's `if` treats it), `must` on booleans, and every
comparison assertion on atoms.

**The one to grep for is scalar broadcast.** `someVector musteq someScalar` is
the common qspec idiom that silently stops passing:

```q
counts: 0 0 0;
counts musteq 0                        / qspec: 0 0 0 = 0 -> 111b -> passes
                                       / resQ:  vector ~ atom     -> FAILS
must[all counts = 0; "all zero"];      / works in both
counts musteq 3 # 0;                   / or compare like-for-like
```

`~` was chosen deliberately: it compares tables and dictionaries (which `=`
signals `'type` on), and it does not silently equate `1` with `1.0`. The
trade-off is that broadcast comparisons must be written explicitly — or run
with `-qspec-compat`, which accepts both.

---

## Mocking

resQ's mock API:
```q
`name mock value;        / infix form (most common)
.tst.mock[`name; value]; / function form
```

Mocks are automatically restored after each `should` block.

The mock guard blocks bare system namespace symbols (`.q`, `.Q`, `.z`, etc.).
Individual members like `.Q.s` are not blocked — but mocking framework internals
is inadvisable. Wrap any system function you need to control:
```q
.myMod.fmt: .Q.s;
`.myMod.fmt mock {x};   / mock the wrapper, not .Q.s directly
```

---

## Fixture API

resQ uses `registerFixture` (2-arg, simple value) and `registerFixtureWithOpts`
(3-arg, with lifecycle):
```q
/ Simple value fixture
.tst.registerFixture[`myData; ([] a:1 2 3)];

/ Fixture with lifecycle (setup/teardown/scope)
.tst.registerFixtureWithOpts[`hdbConn; 0i;
    `scope`setup`teardown!(
        `session;
        {[h] hopen `:localhost:5000};
        {[h] hclose h}
    )
];
```

Fixture injection: add the fixture name as a function argument to `should`:
```q
should["uses fixture"]{[myData]
  count[myData] mustgt 0;
};
```

---

## Sandboxed Loading

resQ loads each test file into a unique isolated namespace. Consequences:
- Local variables defined at file top-level are contained within the sandbox.
- `\l path` inside a test file is supported.
- `\d .ns` namespace switches work inside test files.
- Unqualified names (`mock`, `should`, `musteq`) resolve via `.q` namespace
  fallback (default) or via root aliases. If you set `"qNamespaceExports": false`
  in `resq.json`, you must use fully-qualified `.tst.*` names.

---

## Worked Before/After Example

**qspec-style file:**
```q
.tst.desc["User Service"]{
  before{
    `db mock .db.connect[];
  };
  after{
    .db.close db;
  };
  should["create user"]{
    id: .user.create["alice"];
    id mustgt 0;
  };
};
```

**Same file in resQ** (no changes needed — the above is already valid resQ):
```q
.tst.desc["User Service"]{
  before{
    `db mock .db.connect[];
  };
  after{
    .db.close db;
  };
  should["create user"]{
    id: .user.create["alice"];
    id mustgt 0;
  };
};
```

The differences you will actually encounter are the three assertion semantics
above and the mock API (resQ needs no explicit `restore[]` — restoration is
automatic after each `should` block, including when the test throws or fails).

### Suggested migration order

1. Put `bin/qspec` on `PATH` and run the existing command. The suite should load
   and execute unchanged.
2. Adopt resQ-only features while retaining the compatibility launcher.
3. Optionally switch to `resq test` and fix any `vector musteq scalar`
   comparisons that the stricter native semantics flag.
4. Run once with `-strict`, which additionally fails any test that executed no
   assertion. qspec had no such check, so a long-lived suite usually has a few
   tests that never verified anything.

---

## Things resQ Does Not Support from qspec

These are qspec's **internal** APIs — the ones for building tools on top of
qspec, not for writing tests. Every test-writing construct is supported; a
suite of test files does not touch these.

- Nested `desc` blocks (use `alt{}` for sub-grouping within a suite).
- qspec's reporter hooks (resQ has its own text/JUnit/xUnit/JSON reporters).
- `.tst.runExpec` / `.tst.getExpec` / `.tst.contextHelper` — qspec's internal
  expectation-runner API. resQ reimplemented the runner (process isolation,
  retries, timeouts), so these do not exist.
- Spec-runner context handling. qspec leaves the namespace and file path
  changed after a spec; resQ restores them, because it sandboxes each file.
- File-discovery return types. `.tst.findTests` and friends return symbols in
  resQ, strings in qspec.

The pinned public contract passes unchanged: `test_assertions` 7/7,
`test_ui` 8/8, `test_mock` 6/6, `test_fuzz` 12/12, file fixtures 4/4,
directory fixtures 5/5, and text fixtures 2/2. qspec's internal runner tests are
not vendored as a compatibility contract because they exercise the private APIs
listed above rather than test-source compatibility.
