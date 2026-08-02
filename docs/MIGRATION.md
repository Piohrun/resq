# Migrating from qspec to resQ

resQ's core DSL is source-compatible with qspec for the most common patterns.
This guide covers what works unchanged, what differs, and what to watch for.

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
| `holds` | `holds` | Extended — see below |

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

## Assertion Semantics — Read This Before Migrating

The names match; three **behaviours** differ. This is where a working qspec
suite can go red on resQ. Verified by running each case against both
implementations.

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
trade-off is that broadcast comparisons must be written explicitly.

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

1. Point resQ at the existing suite and run it. The DSL loads as-is.
2. Fix any `vector musteq scalar` comparisons — this is the bulk of real
   breakage. They fail loudly, so the run tells you where they are.
3. Run once with `-strict`, which additionally fails any test that executed no
   assertion. qspec had no such check, so a long-lived suite usually has a few
   tests that never verified anything.

---

## Things resQ Does Not Support from qspec

- Nested `desc` blocks (use `alt{}` for sub-grouping within a suite).
- Any qspec reporter hooks (resQ uses its own text/JUnit/JSON reporters).
