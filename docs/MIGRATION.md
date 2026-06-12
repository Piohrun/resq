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

## Assertion Names

resQ uses different assertion names from qspec. The most common translations:

| qspec | resQ | Notes |
|-------|------|-------|
| `assert.equal` | `musteq` or `mustEqual` | `~`-equality |
| `assert.notEqual` | `mustne` or `mustNotEqual` | `<>`-inequality |
| `assert.true` | `must[cond; msg]` | Takes a message |
| `assert.false` | `must[not cond; msg]` | |
| (none) | `mustlt`, `mustgt` | Numeric comparisons |
| (none) | `mustlike` | Glob matching |
| (none) | `mustin`, `mustnin` | Membership |
| (none) | `mustmatch` | Synonym for `musteq` |
| (none) | `mustthrow[pat; {code}]` | Error assertion |
| (none) | `mustmatchs`, `mustmatchst` | Snapshot assertions |

Failure messages use `Got X — expected Y` wording. The FAILURE DIFF block shows
a visual diff of expected vs actual.

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

The main differences you will encounter are assertion names and the mock API
(which in resQ does not require explicit `restore[]` calls — restoration is
automatic after each `should` block).

---

## Things resQ Does Not Support from qspec

- Nested `desc` blocks (use `alt{}` for sub-grouping within a suite).
- `assert.deepEqual` — use `musteq` (which uses `~` match).
- Any qspec reporter hooks (resQ uses its own text/JUnit/JSON reporters).
