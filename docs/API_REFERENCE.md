# resQ API Reference

Complete reference documentation for the resQ testing framework.

---

## Table of Contents

1. [Test DSL](#1-test-dsl)
2. [Assertions](#2-assertions)
3. [Mocking & Spying](#3-mocking--spying)
4. [Fixtures](#4-fixtures)
5. [Parametrized Testing](#5-parametrized-testing)
6. [Property-Based Testing (Fuzz)](#6-property-based-testing-fuzz)
7. [Async & Promises](#7-async--promises)
8. [Snapshots](#8-snapshots)
9. [Benchmarking](#9-benchmarking)
10. [Utilities](#10-utilities)
11. [CLI Options](#cli-options)
12. [Configuration File](#configuration-file)

---

## 1. Test DSL

The test DSL provides a BDD-style syntax for writing tests.

### retry

```q
retry[n; description; code]
```

Define a test that is allowed to fail up to `n` times before being recorded as failed. Total attempts: `n + 1`.

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `n` | int | Maximum number of retries (total attempts = n+1) |
| `description` | string | Test description |
| `code` | function | Test implementation |

**Behaviour:**
- `before`/`after` hooks re-run around each attempt.
- The first passing attempt wins: one `pass` result row is recorded and no further attempts are made.
- A late pass (not on the first attempt) prints `NOTE: '<description>' passed on attempt k of m` so flakiness remains visible in the log.
- If all attempts fail, the result is recorded as failed with the message "failed after m attempts".
- Exactly one result row is recorded regardless of how many attempts were made.

**Example:**
```q
retry[3; "flaky network call"]{
    result: .api.fetch[];
    result mustne `;
};
```

---

### .tst.desc

```q
.tst.desc[title; block]
```

Define a test suite (specification). Also available as `describe` alias in root namespace.

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `title` | string/symbol | Suite title (can include tags like `#slow`) |
| `block` | function | Code block containing test definitions |

**Example:**
```q
.tst.desc["User Service"]{
    should["create users"]{
        userId: .user.create["alice"];
        userId mustgt 0;
    };
};
```

**Notes:**
- Tags in the title (e.g., `#integration`) can be used for filtering
- The function captures the current namespace context
- Nested describes are not supported; use `alt` for grouping
- `describe` is an alias for `.tst.desc` for convenience
- Source-loaded DSL declarations are arity-audited. An under-applied
  constructor that would otherwise become a discarded q projection is a load
  error naming the constructor and source line.

---

### should

```q
should[description; code]
```

Define a test case (expectation).

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `description` | string/symbol | Test description |
| `code` | function | Test implementation |

**Example:**
```q
should["return empty list for no results"]{
    results: .search.query["nonexistent"];
    0 musteq count results;
};
```

**Notes:**
- Each `should` runs with fresh assertion state
- `before` and `after` hooks apply to each `should`

---

### before

```q
before[code]
```

Define setup code that runs before each test in the current scope.

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `code` | function | Setup code |

**Example:**
```q
.tst.desc["Database Tests"]{
    before{
        `db mock .db.connect[];
    };

    should["query users"]{
        users: .db.query[db; "SELECT * FROM users"];
        users mustgt 0;
    };
};
```

---

### after

```q
after[code]
```

Define teardown code that runs after each test in the current scope.

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `code` | function | Teardown code |

**Example:**
```q
after{
    .db.close db;
};
```

---

### beforeAll / afterAll

```q
beforeAll[code]
afterAll[code]
```

Define suite-level setup and teardown for the current `desc` block. `beforeAll`
runs once before its expectations. If it throws, the suite records an error and
does not execute those expectations; later suites still run. `afterAll` runs
once after every suite that started, including after a failed `beforeAll`, a
fail-hard stop, or another recoverable suite-runner error.

A throwing `afterAll` is a structured cleanup error and fails the run. The
runner continues with the remaining cleanup work so one teardown error does not
hide another.

```q
.tst.desc["Database"]{
    beforeAll{ .db.testConn::hopen `:localhost:5000 };
    afterAll{ hclose .db.testConn };

    should["answer a query"]{
        count[.db.testConn "select from trade"] mustgt 0;
    };
};
```

---

### alt

```q
alt[block]
```

Define an alternative block with its own `before`/`after` scope.

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `block` | function | Code block with tests and hooks |

**Example:**
```q
.tst.desc["API Tests"]{
    alt{
        before{ `server mock .test.startServer[] };
        after{ .test.stopServer server };

        should["handle GET requests"]{...};
        should["handle POST requests"]{...};
    };

    should["work without server"]{...};
};
```

---

### holds

```q
holds[description; props; code]
```

Define a property-based (fuzz) test.

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `description` | string/symbol | Property description |
| `props` | dict | Configuration: `runs`, `vars`, failure tolerance, seed, and shrink limits |
| `code` | function | Property to verify (receives generated values) |

**Example:**
```q
/ Each holds call in its own desc block when vars types differ (see note below)

.tst.desc["sorting"]{
  holds["sorting is idempotent"; `runs`vars!(100; `int$())]{[xs]
    (asc xs) musteq asc asc xs
  };
};

/ Multi-var: vars is a dict; function receives ONE dict — access keys with x[`key]
.tst.desc["commutative"]{
  holds["addition is commutative"; `runs`vars!(100; `a`b!(`int;`int))]{[x]
    (x[`a]+x[`b]) musteq (x[`b]+x[`a])
  };
};
```

**Note:** Each `holds` call in the same `.tst.desc` block must use a compatible
`vars` type. Mixing a simple type spec (`` `int ``) with a dict spec
(`` `a`b!(`int;`int) ``) in one block throws a `'type` load error because q
cannot build a uniform expectation table. Put holds with different var shapes in
separate desc blocks.

**Props Dictionary:**
| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `runs` | int | 100 | Number of test iterations |
| `vars` | any | required | Type specification for generated values |
| `maxFailRate` | float | 0.0 | Maximum allowed failure rate (0.0-1.0) |
| `seed` | long | stable test-derived | Private deterministic sampling seed |
| `shrinkSteps` | long | 100 | Maximum accepted shrink steps |
| `shrinkCandidates` | long | 1000 | Maximum candidates executed by shrinking |
| `shrinkTimeMs` | float | 1000 | Maximum shrink wall time in milliseconds |

---

### perf

```q
perf[description; props; code]
```

Define a performance test.

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `description` | string/symbol | Test description |
| `props` | dict | Benchmark configuration |
| `code` | function | Code to benchmark |

Supported `props` keys:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `runs` | positive int | `10` | Number of measured executions |
| `gc` | boolean | `1b` | Run GC before each measured execution |
| `maxTime` | number | none | Maximum average wall-clock time in milliseconds |
| `maxSpace` | number | none | Maximum average allocation in bytes |

**Example:**
```q
perf["sorting 10000 elements"; `runs`maxTime!(1000; 50)]{
    asc 10000?1000;
};
```

---

### skip / pending / skipIf

```q
skip[reason; code]
pending[reason]
skipIf[condition; reason; code]
```

Mark a test as skipped, pending, or conditionally skipped. Skipped and pending
tests are reported in the summary but do not cause the run to fail.

**Parameters:**
| Function | Parameters | Description |
|----------|-----------|-------------|
| `skip` | `reason` (string); `code` (function) | Skip with a reason; code is not run |
| `pending` | `reason` (string) | Placeholder with no code |
| `skipIf` | `condition` (bool); `reason`; `code` | Skip when condition is true; otherwise runs as a normal `should` |

**Example:**
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

**Notes:**
- All three mix freely with `should`, `holds`, `retry`, and each other in the same `desc` block.
- Under `-strict`, skipped tests do not count as executed — an all-skip suite fails `-strict`.

---

## 2. Assertions

All assertions are available unqualified in test source. The loader binds those
tokens to stable `.tst.dsl.*` helpers; resQ does not add reserved members to
`.q`. Explicit `.tst.musteq`-style calls remain available.

### Assertion Cheat-Sheet

| Name | Args | Meaning | Example |
|------|------|---------|---------|
| `must` | `condition; message` | condition is true | `must[x > 0; "positive"]` |
| `musteq` / `mustEqual` | `actual; expected` | `actual ~ expected` (match) | `result musteq 42` |
| `mustmatch` | `actual; expected` | same as `musteq` | `(asc t) mustmatch expected` |
| `mustne` / `mustNotEqual` | `actual; expected` | `not actual ~ expected` (exact inverse of `musteq`) | `userId mustne 0` |
| `mustlt` / `mustLessThan` | `actual; expected` | `actual < expected` | `latency mustlt 100` |
| `mustgt` / `mustGreaterThan` | `actual; expected` | `actual > expected` | `count users mustgt 0` |
| `mustlike` | `actual; pattern` | `actual like pattern` | `email mustlike "*@*.com"` |
| `mustin` | `actual; list` | `actual in list` | `status mustin \`a\`b\`c` |
| `mustnin` | `actual; list` | `not actual in list` | `x mustnin \`bad` |
| `mustnmatch` | `actual; expected` | `not actual ~ expected` | `a mustnmatch b` |
| `mustwithin` | `actual; range` | `actual within range` | `score mustwithin 0 100` |
| `mustdelta` | `tol; actual; expected` | within ±tolerance | `mustdelta[0.001; r; 3.14]` |
| `mustthrow` | `pattern; code` | code signals matching error | `mustthrow["*nyi*"; {.f[]}]` |
| `mustnotthrow` | `pattern; code` | code does not throw | `mustnotthrow[""; {.f[]}]` |
| `mustmatchignoringorder` / `mustMatchIgnoringOrder` | `actual; expected` | equal ignoring order | `mustmatchignoringorder[r; e]` |
| `mustincludecols` | `actual; expected` | table contains expected cols | `t mustincludecols exp` |
| `mustmatchs` / `mustMatchSnapshot` | `actual; name` | matches binary snapshot | `r mustmatchs "snap1"` |
| `mustmatchst` / `mustMatchTextSnapshot` | `actual; name` | matches text snapshot | `r mustmatchst "snap1"` |
| `mustBeFasterThan` | `code; limitMs` | avg time under limit | `mustBeFasterThan[{f[]}; 10]` |
| `mustAllocLessThan` | `code; limitBytes` | allocation under limit | `mustAllocLessThan[{f[]}; 1e6]` |
| `mustHaveBeenCalledWith` | `name; args` | spy received these args | `mustHaveBeenCalledWith[\`.f; enlist 42]` |

camelCase aliases (`mustEqual`, `mustNotEqual`, `mustLessThan`, `mustGreaterThan`,
`mustMatchSnapshot`, `mustMatchTextSnapshot`, `mustMatchIgnoringOrder`) are
additive aliases for the lowercase forms — both spellings are identical in
behaviour and are exposed through test-source binding and `.tst.asserts`.

### must

```q
must[condition; message]
```

Assert that a condition is true.

A failing assertion past the first reports its position in the test —
`... (assertion #3 in this test)` — so a multi-assertion test says which check
failed. q provides no file/line for a failing assertion: nothing throws, and
test bodies are evaluated via `value` so they carry no source position.

The condition must be a boolean. A non-boolean is reported as a failure naming
the offending type, rather than being coerced — `all` treats `5`, `0N` and any
non-empty string as true, so a null result or a swapped `must["message"; cond]`
would otherwise pass silently. A boolean vector passes when every element is
true; an empty one passes ("all of zero items hold").

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `condition` | boolean (atom or vector) | Condition to verify |
| `message` | string | Error message if assertion fails |

**Example:**
```q
must[count users > 0; "Expected at least one user"];
must[result`status ~ `ok; "Status should be ok"];
```

---

### musteq / mustmatch

```q
actual musteq expected
mustmatch[actual; expected]
```

Assert semantic equality with detailed diff on failure.

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `actual` | any | Actual value |
| `expected` | any | Expected value |

**Example:**
```q
result musteq 42;
result`name musteq "alice";
(asc data) mustmatch expected;
```

**Notes:**
- Uses `~` (match) for comparison
- Displays detailed diff showing exactly what differs
- `musteq` and `mustmatch` are synonyms

---

### mustne

```q
actual mustne expected
```

Assert values are not equal. This is the exact inverse of `musteq`: it compares
whole values with `~`, so it works on vectors, strings, dictionaries and tables,
and it is type-strict (`1 mustne 1.0` passes, just as `1 musteq 1.0` fails).

**Example:**
```q
userId mustne 0;
result mustne `;
(select from trades where sym=`AAPL) mustne ();
```

---

### mustlt

```q
actual mustlt expected
```

Assert actual is less than expected.

**Example:**
```q
latencyMs mustlt 100;
errorCount mustlt 5;
```

---

### mustgt

```q
actual mustgt expected
```

Assert actual is greater than expected.

**Example:**
```q
count users mustgt 0;
revenue mustgt 1000.0;
```

---

### mustlike

```q
actual mustlike pattern
```

Assert string matches pattern (using `like`).

**Example:**
```q
email mustlike "*@example.com";
filename mustlike "report_*.csv";
```

---

### mustin

```q
actual mustin list
```

Assert value is in list.

**Example:**
```q
status mustin `pending`active`complete;
role mustin ("admin";"user";"guest");
```

---

### mustnin

```q
actual mustnin list
```

Assert value is NOT in list.

**Example:**
```q
status mustnin `deleted`archived;
```

---

### mustwithin

```q
actual mustwithin range
```

Assert value is within range (inclusive).

**Example:**
```q
score mustwithin 0 100;
temperature mustwithin -40 50;
```

---

### mustdelta

```q
mustdelta[tolerance; actual; expected]
```

Assert actual is within tolerance of expected.

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `tolerance` | numeric | Allowed deviation |
| `actual` | numeric | Actual value |
| `expected` | numeric | Expected value |

**Example:**
```q
mustdelta[0.001; result; 3.14159];
mustdelta[1; latencyMs; 50];
```

---

### mustthrow

```q
mustthrow[pattern; code]
```

Assert that code throws an error matching the pattern.

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `pattern` | string/list | Error pattern(s) to match (supports wildcards) |
| `code` | function/list | Code to execute |

**Example:**
```q
mustthrow["*not found*"; {.user.get[`nonexistent]}];
mustthrow["type"; {1 + "a"}];
mustthrow[("*invalid*";"*error*"); {.api.call[]}];

/ With arguments
mustthrow["*negative*"; (.math.sqrt; -1)];
```

**Notes:**
- Pattern matching uses q's `like` operator: `"type"` matches exactly `"type"`;
  for substring matching use `"*type*"`. A bare `"type"` does NOT match an error
  message like `"oh no, type mismatch"` — add `*` wildcards for substring semantics.
- Pattern can be: a string, a symbol (stringified internally), a symbol vector, or
  a list of strings. Symbols are coerced to strings before matching.
- Multiple patterns: passes if ANY pattern matches the thrown error.
- `code` can be a zero-arg function or `(function; arg1; arg2; ...)` list.
- Argument-order guard: passing code as the first argument (infix style) gives a
  guidance error instead of a raw `'type`.

```q
mustthrow["*not found*"; {.user.get[`nonexistent]}];
mustthrow["type"; {1 + "a"}];           / exact match for the 'type error
mustthrow[("*invalid*";"*error*"); {.api.call[]}];

/ With arguments
mustthrow["*negative*"; (.math.sqrt; -1)];

/ Symbol pattern (stringified internally)
mustthrow[`type; {1 + "a"}];

/ Wrong: code first (infix) triggers guidance error
/ {.user.get[`nonexistent]} mustthrow "*not found*";  / DON'T do this
```

---

### mustnotthrow

```q
mustnotthrow[pattern; code]
```

Assert that code does NOT throw an error matching the pattern.

**Example:**
```q
mustnotthrow["*timeout*"; {.api.healthCheck[]}];
```

---

### mustmatchignoringorder

```q
mustmatchignoringorder[actual; expected]
```

Assert equality ignoring element order (for lists/tables).

**Example:**
```q
mustmatchignoringorder[results; expected];
/ `c`a`b ~ `a`b`c  -> passes
```

---

### mustincludecols

```q
mustincludecols[actual; expected]
```

Assert table includes expected columns with matching values.

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `actual` | table | Table to check |
| `expected` | table | Expected columns and values |

**Example:**
```q
users mustincludecols ([] name:`alice`bob; active:11b);
/ Passes even if `users` has additional columns
```

---

### mustmatchs

```q
actual mustmatchs snapshotName
```

Assert value matches binary snapshot. Alias for `mustmatchSnap`.

**Example:**
```q
result mustmatchs "user_query_result";
```

---

### mustmatchst

```q
actual mustmatchst snapshotName
```

Assert value matches text snapshot.

**Example:**
```q
report mustmatchst "monthly_report";
```

---

### mustBeFasterThan

```q
mustBeFasterThan[code; limitMs]
```

Assert code execution average time is under threshold.

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `code` | function | Code to benchmark |
| `limitMs` | numeric | Maximum average time in milliseconds |

**Example:**
```q
mustBeFasterThan[{.cache.get`key}; 10];
```

---

### mustAllocLessThan

```q
mustAllocLessThan[code; limitBytes]
```

Assert code allocates less than threshold bytes.

**Example:**
```q
mustAllocLessThan[{.process.data[]}; 1000000];
```

---

### mustHaveBeenCalledWith

```q
mustHaveBeenCalledWith[name; args]
```

Assert a spied function was called with specific arguments.

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `name` | symbol | Spy function name |
| `args` | list | Expected arguments |

**Example:**
```q
.tst.spy[`.logger.info; ::];
.myFunc[];
mustHaveBeenCalledWith[`.logger.info; enlist "User created"];
```

---

## 3. Mocking & Spying

### mock

```q
`name mock value
.tst.mock[name; value]
```

Replace a function or variable with a mock value.

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `name` | symbol | Variable/function name to mock |
| `value` | any | Replacement value |

**Example:**
```q
/ Mock a function
`.db.query mock {[q] ([] id:1 2 3)};

/ Mock a variable
`config mock `debug`timeout!(1b;5000);

/ Mock in current namespace context
`localVar mock 42;
```

**Notes:**
- Original value is automatically saved and restored after test
- Use backtick prefix for namespaced names: `` `.ns.func ``
- Global variables (no namespace) are handled specially for correct scoping

---

### partialMock

```q
.tst.partialMock[name; partialValue]
```

Merge partial values into an existing dictionary.

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `name` | symbol | Dictionary variable name |
| `partialValue` | dict | Values to merge |

**Example:**
```q
/ Original: config: `host`port`debug!("localhost";8080;0b)
.tst.partialMock[`config; `debug!(1b)];
/ Result: config is now `host`port`debug!("localhost";8080;1b)
```

**Notes:**
- If `name` does not refer to an existing variable, `partialMock` signals a clear error: `"target not defined: <name>"`. Previously this surfaced as a raw q name error.

---

### spy

```q
.tst.spy[name; impl]
```

Wrap a function to track calls while optionally replacing implementation.

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `name` | symbol | Function name to spy on |
| `impl` | function/:: | Replacement implementation, or `::` to keep original |

**Example:**
```q
/ Spy while keeping original behavior
.tst.spy[`.logger.info; ::];

/ Spy with custom implementation
.tst.spy[`.db.save; {[data] `mock_id}];

/ Run code
.myService.process[];

/ Check calls
.tst.callCount[`.logger.info] mustgt 0;
.tst.calledWith[`.logger.info; enlist "Processing started"];
```

---

### calledWith

```q
.tst.calledWith[name; args]
```

Check if spy was called with specific arguments.

**Returns:** `1b` if called with those args, `0b` otherwise

**Example:**
```q
.tst.calledWith[`.api.post; ("http://api.com"; `data!(1))]
```

---

### callCount

```q
.tst.callCount[name]
```

Get number of times spy was called.

**Returns:** Integer count

**Example:**
```q
.tst.callCount[`.logger.error] musteq 0;
```

---

### lastCall

```q
.tst.lastCall[name]
```

Get arguments from last spy call.

**Returns:** List of arguments

**Example:**
```q
.tst.lastCall[`.db.insert] musteq (tableName; record);
```

---

### mockSequence

```q
.tst.mockSequence[name; values]
```

Mock a function to return different values on successive calls.

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `name` | symbol | Function name |
| `values` | list | Values to return in order |

**Example:**
```q
.tst.mockSequence[`.api.fetch; (1; 2; 3)];
.api.fetch[] / returns 1
.api.fetch[] / returns 2
.api.fetch[] / returns 3
.api.fetch[] / throws "Mock sequence exhausted"
```

**Notes:**
- If `name` does not refer to an existing variable, `mockSequence` signals a clear error: `"target not defined: <name>"`. Previously this surfaced as a raw q name error.

---

### restore

```q
.tst.restore[]
```

Restore all mocked values to originals.

**Notes:**
- Called automatically after each test
- Clears all spy logs
- Removes variables that were created by mocks

---

### clearSpyLogs

```q
.tst.clearSpyLogs[]
```

Clear all spy call logs without restoring mocks.

---

## 4. Fixtures

### fixtureAs

```q
.tst.fixtureAs[fixtureName; varName]
fixture[fixtureName]
```

Load a fixture file and optionally bind to a variable name.

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `fixtureName` | symbol/string | Fixture file name |
| `varName` | symbol | Variable name to bind (use `` ` `` for default) |

**Example:**
```q
/ Load fixture from test directory or fixtures/ subdirectory
.tst.fixtureAs[`users; `testUsers];  / binds to `testUsers
fixture[`sample_data];                / binds to `sample_data
```

**Fixture Search Path:**
1. Same directory as test file
2. `fixtures/` subdirectory of test directory

---

### registerFixture

```q
.tst.registerFixture[name; value]
```

Register a fixture value programmatically.

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `name` | symbol | Fixture name |
| `value` | any | Fixture value |

**Example:**
```q
.tst.registerFixture[`testConfig; `host`port!("localhost";5000)];
```

---

### registerCleanup / registerSpecCleanup

```q
.tst.registerCleanup[func; args]       / fires after the current expectation
.tst.registerSpecCleanup[func; args]   / fires after the spec, after handle teardown
```

Queue a cleanup callable to run once the test scope finishes. `func` is invoked
with `args` (a list — single-arg cleanups still pass `enlist value`). Failures
are trapped, converted to structured error rows, and fail the run. One bad
cleanup does not abort the remaining expectation-, spec-, fixture-, or session-
scope cleanup work.

Choose the scope by **what the cleanup depends on**:

- **`registerCleanup`** (expectation scope): runs at the end of the *current* `should` block, before any sibling expectations. Use for state that should not survive into the next expectation (temp values, mock state, expectation-local files). `.tst.tempFile` uses this scope.
- **`registerSpecCleanup`** (spec scope): runs at the end of the *current* `desc` block, *after* the runner has closed any handles the spec leaked. Use when the cleanup needs the runner to have torn down resources first — e.g. deleting a file whose handle was deliberately leaked to test the resource guard. Required for cross-platform correctness; expectation-scope `hdel` of an open file works on Linux but not macOS/Windows.

**Examples:**
```q
should["leak a handle and have the runner close it"]{
    fn: "scratch.txt";
    / Spec scope — runs AFTER the runner closes the leaked handle.
    .tst.registerSpecCleanup[{[p] @[hdel; hsym `$p; {}]}; enlist fn];
    hsym[`$fn] 0: enlist "data";
    h: hopen hsym `$fn;
    / Leave h open intentionally.
};

should["produce a temp artifact only this expectation needs"]{
    out: .tst.tempFile ".csv";   / auto-cleaned at expectation end via registerCleanup
    (hsym `$out) 0: enlist "a,b,c";
    must[.utl.isFile out; "should write file"];
};
```

---

### registerFixtureWithOpts

```q
.tst.registerFixtureWithOpts[name; value; opts]
```

Register a fixture with lifecycle options.

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `name` | symbol | Fixture name |
| `value` | any | Initial fixture value |
| `opts` | dict | Lifecycle options |

**Options Dictionary:**
| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `scope` | symbol | `test | `` `test `` (per-test) or `` `session `` (once) |
| `setup` | function | `{}` | Transform value before use |
| `teardown` | function | `{}` | Cleanup after use |

**Example:**
```q
.tst.registerFixtureWithOpts[`tempFile; "/tmp/test.txt";
    `scope`setup`teardown!(
        `test;
        {[path] path 0: enlist "init"; path};
        {[path] system "rm ",path}
    )
];
```

---

### getFixture

```q
.tst.getFixture[name]
```

Get a fixture value (runs setup if needed).

**Returns:** Fixture value after setup

**Example:**
```q
config: .tst.getFixture[`testConfig];
```

---

### teardownFixture

```q
.tst.teardownFixture[name; value]
```

Run teardown for a specific fixture.

---

### cleanupAllFixtures

```q
.tst.cleanupAllFixtures[]
```

Run teardown for all session-scoped fixtures.

---

## 5. Parametrized Testing

### shouldEach

```q
shouldEach[description; cases]{[caseColumns...; fixtures...] testBody }
```

Declare a table of independently discoverable parameter cases. The table is
evaluated while the suite is loaded, but `testBody` is not. Each row becomes a
top-level execution with the same parent `testId`, a stable row-specific
`caseId`, and an object-valued `parameters` field in JSON.

```q
.tst.registerFixture[`taxRate; 0.2];

.tst.desc["invoice totals"]{
    shouldEach["calculates each band";
        ([] net:100 250f; expected:120 300f)]{
        [net;expected;taxRate]
        (net * 1 + taxRate) musteq expected;
    };
};
```

Table columns bind the leading body parameters in column order. Any remaining
parameters are resolved as registered fixtures and are installed/torn down for
each row. A non-table or empty value, or a body whose leading parameters do not
match the columns, is rejected during discovery. Use `shouldEach` when cases
must be visible to `-desc`, machine reports, or `-shard-unit case` before test
execution begins.

The existing runtime helpers below remain compatible and atomic: their cases
are created only after the enclosing test body starts, so they cannot be split
across shards and remain nested under `parameterCases[]`.

### forall

```q
.tst.forall[data; func]
```

Run a test function for each row of a table.

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `data` | table | Test data with columns matching function parameters |
| `func` | function | Test function |

**Example:**
```q
testCases: ([] input: (1;2;3); expected: (2;4;6));
.tst.forall[testCases; {[input;expected]
    (.math.double input) musteq expected;
}];
```

**Notes:**
- A precedence bug that caused the first row to spuriously fail when prior assertion state contained failures has been fixed. Each row now evaluates independently of prior assertion state.
- Assertion failures are accumulated across every row, retain their original
  diagnostic, and include the row's parameter values. A runtime error still
  stops the loop and is reported as an error with parameter context.

---

### parametrize

```q
.tst.parametrize[paramDict; func]
```

Generate and run all combinations of parameters (Cartesian product).

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `paramDict` | dict | Parameter names to value lists |
| `func` | function | Test function |

**Example:**
```q
/ Generates 6 test cases: (1,a), (1,b), (2,a), (2,b), (3,a), (3,b)
.tst.parametrize[`x`y!(1 2 3; `a`b); {[x;y]
    result: .process[x;y];
    result mustgt 0;
}];
```

All combinations run even when an earlier combination fails an assertion. Each
failure retains the assertion message and is suffixed with its parameter values.
Runtime errors remain fail-fast and are reported as errors.

---

## 6. Property-Based Testing (Fuzz)

### Type Specifications for `vars`

| Type | Specification | Generated Values |
|------|---------------|------------------|
| Boolean | `` `boolean `` | `0b`, `1b` |
| GUID | `` `guid `` | Random GUIDs |
| Byte | `` `byte `` | 0x00-0xFF |
| Short | `` `short `` | Random shorts |
| Int | `` `int `` | Random ints up to 2B |
| Long | `` `long `` | Random longs |
| Real | `` `real `` | Random reals |
| Float | `` `float `` | Random floats |
| Char | `` `char `` | a-z characters |
| Symbol | `` `symbol `` | `` `a`b`c`d`e`f`g `` |
| List | `()` or typed empty list | Random length lists |
| Choice | `` `opt1`opt2`opt3 `` | Random selection |
| Function | `{...}` | Custom generator |
| Dict | `` `a`b!(`int;`float) `` | Multiple params |
| Protocol generator | `.resq.gen.*` | Deterministic composable generator |

**Examples:**

Each `holds` call occupies its own `.tst.desc` block when its `vars` type differs from sibling
`holds` calls (mixing a symbol var with a dict-var form in one block causes a `'type` error
because q cannot build a uniform expectation table with incompatible column types).

```q
/ Single integer parameter — use `runs`vars!(N; `type) form
.tst.desc["positive"]{
  holds["positive"; `runs`vars!(100; `int)]{[x]
    (x+1) mustgt x
  };
};

/ Integer list parameter
.tst.desc["sorted"]{
  holds["sorted is idempotent"; `runs`vars!(100; `int$())]{[xs]
    (asc xs) musteq asc asc xs
  };
};

/ Multiple named parameters — function receives ONE dict; access keys with x[`key]
.tst.desc["commutative"]{
  holds["commutative"; `runs`vars!(100; `a`b!(`int;`int))]{[x]
    (x[`a]+x[`b]) musteq (x[`b]+x[`a])
  };
};

/ Custom generator — must return a SCALAR (1?N returns a list; use `first`)
.tst.desc["even"]{
  holds["even number"; `runs`vars!(100; {first 2*1?1000})]{[x]
    0 musteq x mod 2
  };
};

/ Choice from list
.tst.desc["status"]{
  holds["valid status"; `runs`vars!(100; `pending`active`done)]{[s]
    s mustin `pending`active`done
  };
};
```

---

### pickFuzz

```q
.tst.pickFuzz[spec; runs]
```

Generate random values according to specification.

**Returns:** List of generated values

Legacy random helpers remain for qspec compatibility. `holds` adapts `vars` to
the public deterministic protocol and samples through `.resq.gen`; new code
should use that API directly.

---

### `.resq.gen` protocol

```q
g:.resq.gen.scalar[`int;-100;100];
.resq.gen.sample[g;seed;counter;stream]
.resq.gen.sampleList[g;runs;seed;stream]
.resq.gen.shrinkCandidates[g;value]
.resq.gen.replay[g;"resq-pbt-v1/4242/17"]
```

All protocol generators are dictionaries with `protocol`, `kind`, and
`options`; `protocol` is `resq-generator-v1`. Sampling is a pure function of
the four arguments and built-ins never consume q's global random stream.

| Constructor | Signature |
|-------------|-----------|
| Typed value | `.resq.gen.typed typeName` |
| Bounded scalar | `.resq.gen.scalar[typeName;lower;upper]` |
| Boundary choice | `.resq.gen.boundary values` |
| Weighted choice | `.resq.gen.weightedChoice[values;weights]` |
| Nullable | `.resq.gen.nullable[generator;nullRate]` |
| Collection | `.resq.gen.list[generator;minLength;maxLength]` |
| Dictionary | `.resq.gen.dictionary generators` (alias `dict`) |
| Tuple | `.resq.gen.tuple generators` |
| Table | `.resq.gen.table[schema;minRows;maxRows]` |
| Map | `.resq.gen.map[generator;function]` |
| Filter | `.resq.gen.filter[generator;predicate;maxAttempts]` |
| Custom | `.resq.gen.custom[label;sampleFunction;shrinkFunction]` |

The custom sample function receives `[seed;counter;stream]`; the custom shrink
function receives the current value and returns ordered candidates. A filter
throws if no value satisfies its predicate within `maxAttempts`. Built-in
symbols come only from a fixed seven-symbol pool, avoiding unbounded symbol
interning. Typed integer and floating defaults deliberately include null/boundary
values (including signed zero and infinities for floating types); use `scalar`
or a bounded filter when a property requires finite values. See
[Property-Based Testing](PBT.md) for the exact type domains, composite examples,
determinism boundaries, replay stability, and shrinking behavior.

---

### shrink

```q
.tst.shrink[code; typeCode; value]
```

Backward-compatible wrapper that shrinks a failing input to a reproducing case.

**Notes:**
- Automatically called when a fuzz test fails
- New property runs use `.tst.shrinkTree` and `.resq.gen.shrinkCandidates` for
  deterministic type-aware trees.
- Only candidates preserving the original failure signature are accepted.
- `shrinkSteps`, `shrinkCandidates`, and `shrinkTimeMs` independently bound work.
- Console and JSON report original/minimal inputs, replay token, work counts,
  duration, signature, and `minimal`/`stepLimit`/`candidateLimit`/`timeLimit`.

---

## 7. Async & Promises

### deferred

```q
.tst.deferred[]
```

Create a deferred (promise-like) object.

**Returns:** Symbol ID for the deferred

**Example:**
```q
id: .tst.deferred[];
/ ... async operation ...
.tst.resolve[id; result];
```

---

### resolve

```q
.tst.resolve[id; value]
```

Resolve a deferred with a value.

---

### reject

```q
.tst.reject[id; error]
```

Reject a deferred with an error.

---

### await

```q
.tst.await[id; timeoutMs]
```

Wait for a deferred to settle by polling inside the current q call.

This is not an event-loop await. Its busy sleep cannot dispatch IPC or ordinary
timer callbacks, so the deferred must be settled synchronously, before the
call, or by work that does not require q event-loop progress. See
[Async and promises](ASYNC.md) for the polling-only support boundary.

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `id` | long (legacy `` `def_N `` symbol accepted) | Opaque deferred handle |
| `timeoutMs` | long | Timeout in milliseconds |

**Returns:** Resolved value

**Throws:** Error if rejected or timeout. When a promise is rejected with a string reason, `await` signals that string as the error (e.g. `'connection refused`). Previously, string rejection reasons raised `'stype` instead of the actual reason.

**Example:**
```q
id: .tst.deferred[];
/ Code under test invokes a synchronous completion callback.
.tst.resolve[id; "TXN-42"];
result: .tst.await[id; 5000];
```

---

### eventually

```q
.tst.eventually[condition; timeoutMs; intervalMs]
```

Poll a condition until it succeeds or times out.

Polling remains inside the current q call and does not dispatch IPC or timer
callbacks. Use `waitEx[...,1b]` only when explicitly calling `.z.ts[]` between
polls is sufficient; it is not general asynchronous execution.

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `condition` | function | Niladic function returning boolean |
| `timeoutMs` | long | Timeout in milliseconds |
| `intervalMs` | long | Polling interval in milliseconds |

**Example:**
```q
/ Wait for file to appear
.tst.eventually[{.utl.pathExists "/tmp/output.csv"}; 10000; 100];

/ Wait for queue to drain
.tst.eventually[{0 = count .queue.pending[]}; 5000; 50];
```

---

### getState

```q
.tst.getState[id]
```

Get current state of a deferred.

**Returns:** Dict with `state`, `val`, `err` keys

---

### isSettled

```q
.tst.isSettled[id]
```

Check if deferred is settled (resolved or rejected).

**Returns:** Boolean

---

### callbackSpy

```q
.tst.callbackSpy[name]
```

Create a callback that logs invocations.

**Returns:** Function that logs calls

**Example:**
```q
cb: .tst.callbackSpy[`onComplete];
.async.process[data; cb];
/ Later...
calls: .tst.getCallbackCalls[`onComplete];
```

---

### getCallbackCalls

```q
.tst.getCallbackCalls[name]
```

Get list of (timestamp; args) for callback invocations.

---

### clearCallbackLogs

```q
.tst.clearCallbackLogs[]
```

Clear all callback logs.

---

### Async API summary

Full guide with worked examples: [`ASYNC.md`](ASYNC.md).

| Function | Signature | Notes |
|----------|-----------|-------|
| `.tst.deferred` | `[]` → long | Create an opaque pending-deferred handle |
| `.tst.resolve` | `id; value` | Settle successfully; throws if already settled |
| `.tst.reject` | `id; reason` | Settle as failed; reason may be a string or symbol |
| `.tst.await` | `id; timeoutMs` | Returns the value, or throws the rejection reason. `0N` → 5000ms. Throws on timeout |
| `.tst.isSettled` | `id` → boolean | `0b` for an unknown id — never throws |
| `.tst.getState` | `id` → dict | `` `state`val`err ``; throws on an unknown id |
| `.tst.until` | `cond` → `1b` | Poll; fixed 1000ms timeout, 100ms interval. **Throws** on timeout |
| `.tst.wait` | `cond; timeoutMs; intervalMs` | As `until` with explicit timings |
| `.tst.waitEx` | `cond; timeoutMs; intervalMs; heartbeat` | `heartbeat=1b` fires `.z.ts` each interval |
| `.tst.eventually` | `cond; timeoutMs; intervalMs` | A **throwing** condition counts as "not yet". `0N` → 5000/100 |
| `.tst.sleep` | `ms` | Busy-wait — spins, does not yield |
| `.tst.callbackSpy` | `name` → function | One-arg callback recording `(timestamp; args)`, returns args |
| `.tst.getCallbackCalls` | `name` → list | Recorded calls; `()` if never spied |
| `.tst.clearCallbackLogs` | `[]` | Logs are global and persist across tests — clear them |

---

## 8. Snapshots

See `docs/SNAPSHOTS.md` for a full guide. Brief reference below.

### mustmatchSnap (binary)

```q
.tst.mustmatchSnap[actual; name]
actual mustmatchs name
```

Assert value matches stored binary snapshot (q `set`/`get` serialisation).

**Storage:** `tests/snapshots/<name>.snap` — override with `.tst.setSnapDir`

**Behavior:**
- Missing snapshot + no `-strict`: creates file and prints `NOTE: snapshot created: <name> (<dir>) - review and commit it`
- Missing snapshot + `-strict`: fails with `Snapshot missing under -strict`
- `setUpdateSnaps[1b]`: overwrites and passes
- Existence is determined by **file presence** — empty lists, dicts, and tables are valid.

**Example:**
```q
result mustmatchs "query_output";
```

---

### mustmatchTxtSnap (text)

```q
.tst.mustmatchTxtSnap[actual; name]
actual mustmatchst name
```

Assert value matches a schema-v2 text snapshot. Equality uses the complete
canonical payload; the JSON envelope carries a full human-readable rendering,
codec/q-build metadata, and integrity digests for reviewable `git diff` output.

**Storage:** `tests/__snapshots__/<name>.snap.txt` — override with `.tst.setSnapTxtDir`

**Behavior:** Same first-run and `-strict` semantics as binary snapshots.
Unversioned/v1 text is rejected as untrusted evidence and must be rewritten
through explicit `setUpdateSnaps[1b]` mode. Codec or q-build changes likewise
require explicit migration.

**Example:**
```q
report mustmatchst "monthly_report";
```

---

### setSnapDir / setSnapTxtDir

```q
.tst.setSnapDir[directory]     / binary snapshots (default: {cwd}/tests/snapshots)
.tst.setSnapTxtDir[directory]  / text snapshots   (default: {cwd}/tests/__snapshots__)
```

---

### setUpdateSnaps

```q
.tst.setUpdateSnaps[bool]
```

Enable/disable snapshot update mode.

### Snapshot inventory and gate

```bash
resq test tests -strict -snapshot-audit -json -outDir artifacts
resq test tests -strict -snapshot-gate  -json -outDir artifacts
```

`-snapshot-audit` writes a versioned `snapshot-manifest.json` and the identical
top-level JSON `snapshotInventory`. It classifies both backends as referenced,
missing, obsolete, or unverified. Filtered, selected, sharded, failed,
interrupted, and describe-only runs are partial and cannot label files
obsolete. `-snapshot-gate` implies audit and rejects partial, missing, obsolete,
or unsafe inventories.

Declare dynamically generated identities explicitly:

```q
.resq.snapshot.declare[`text; ("region-eu"; "region-us")]
.resq.snapshot.declare[`binary; "risk-grid"]
```

Preview obsolete moves with
`tools/prune_snapshots.py artifacts/snapshot-manifest.json`; add `--write` only
after review. Files move under `.resq/trash/snapshots` and remain recoverable.
Runtime and pruning both refuse symlink roots/leaves and escaping paths.

---

### loadSnap / saveSnap

```q
.tst.loadSnap[name]
.tst.saveSnap[name; data]
```

Low-level snapshot read/write.

---

## 9. Benchmarking

### bench

```q
.tst.bench[func; opts]
```

Run a benchmark and collect statistics.

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `func` | function | Code to benchmark |
| `opts` | dict | Configuration options |

**Options:**
| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `iterations` | int | 1000 | Number of timed runs |
| `warmup` | int | 100 | Warmup iterations |
| `gcBefore` | bool | `1b` | Garbage collect before timing |

**Returns:** Dictionary with timing statistics

**Result Keys:**
| Key | Description |
|-----|-------------|
| `iterations` | Number of runs |
| `total_ns/us` | Total time |
| `min_ns/us` | Minimum time |
| `max_ns/us` | Maximum time |
| `avg_ns/us` | Average time |
| `std_ns/us` | Standard deviation |
| `p50/p90/p95/p99_ns/us` | Linear-interpolated percentiles |
| `histogram` | Distribution table |
| `raw_ns` | All raw timings |

**Example:**
```q
stats: .tst.bench[{asc 10000?1000}; `iterations!(500)];
stats`avg_us  / average microseconds
```

---

### mustbench

```q
.tst.mustbench[func; thresholdUs; opts]
```

Assert average benchmark time is under threshold.

**Example:**
```q
.tst.mustbench[{.cache.get`key}; 100; ()!()];
```

---

### benchCompare

```q
.tst.benchCompare[name1; func1; name2; func2; opts]
```

Compare two implementations.

**Returns:** Dict with `stats1`, `stats2`, `ratio`, `winner`

**Example:**
```q
result: .tst.benchCompare["bubble"; bubbleSort; "quick"; quickSort; ()!()];
result`winner  / e.g., `quick
```

---

### benchPrint

```q
.tst.benchPrint[stats]
```

Print formatted benchmark results to console.

---

### benchHistogram

```q
.tst.benchHistogram[data; bins]
```

Generate histogram table from timing data.

Percentiles use linear interpolation at zero-based position `(n - 1) * p`,
with `p` clamped to `0..1`. This keeps singleton and small-sample percentiles in
range. The percentile helper returns `0n` for an empty sample vector.

---

## 10. Utilities

### diff

```q
.tst.diff[expected; actual]
```

Generate human-readable diff between values.

**Returns:** List of strings describing differences, or empty if equal

**Example:**
```q
diffs: .tst.diff[`a`b`c!1 2 3; `a`b`c!1 2 4];
/ ("Value mismatch"; "  Expected: `a`b`c!1 2 3"; "  Actual:   `a`b`c!1 2 4")
```

---

### toString

```q
.tst.toString[value]
```

Convert any value to string safely.

**Example:**
```q
.tst.toString `symbol    / "symbol"
.tst.toString "string"   / "string"
.tst.toString 123        / "123"
.tst.toString 1b         / ,"1"  (single-char string, not "true")
```

---

### sleep

```q
.tst.sleep[ms]
```

Busy-wait sleep for specified milliseconds.

---

### deleteVar

```q
.tst.deleteVar[sym]
```

Properly delete a variable by symbol (handles namespaces).

---

## CLI Options

```bash
resq [mode] [options] [paths...]
```

The launcher is the production entry point. It preserves the granular q exit
codes and additionally forces status 1 if q exits successfully before a test
run completes. A direct `q resq.q ...` invocation cannot enforce that final
status because q's `.z.exit` callback cannot change an existing `exit 0`.

**Modes:**
| Mode | Description |
|------|-------------|
| `test` (default) | Run tests |
| `cover` | Run with coverage |
| `discover` | Test discovery |
| `watch` | Watch mode |

**Options:**
| Flag | Description |
|------|-------------|
| `-junit` / `-xml` | Output JUnit XML (single format: `test-results.xml`; multi-format: `test-results.junit.xml`) |
| `-xunit` | Output xUnit v2 XML (single format: `test-results.xml`; multi-format: `test-results.xunit.xml`) |
| `-json` | Output JSON report to `outDir/test-results.json` |
| `-perf` | Include performance tests |
| `-pass` | qspec compatibility: run and preserve exit status, but suppress resQ result reporters/artifacts and loading/audit chatter. Application/test writes and q runtime diagnostics are not intercepted |
| `-cov` / `-coverage` | Enable coverage |
| `-strict` | Fail when no tests are found or executed, or when a test runs no assertions |
| `-qspec-compat` | Restore qspec's `musteq` (`=`) and `mustne` (`<>`) semantics for an unported qspec suite |
| `-cov-statements` | Measured per-statement coverage (rewrites function bodies at load time; opt-in) |
| `-cov-branches` | Measure true/false edges for eligible `if`, `while`, and lazy `$` conditions (opt-in rewrite) |
| `-cov-contexts` | Attribute function/statement/branch hits to stable test/declarative-case execution IDs without changing aggregates or gates |
| `-cov-attempt-contexts` | As above, but create a stable context for every retry attempt; implies `-cov-contexts` |
| `-cov-context-max N` | Maximum real test/attempt contexts retained (default 10,000); excess contexts fold into `overflow` |
| `-cov-context-entry-max N` | Maximum unique context/metric pairs retained (default 250,000); truncation is disclosed |
| `-no-line-annotations` | Disable expectation source-line rewriting if a suite hits an unsupported lexical edge case; file/line fields become unavailable and incomplete-constructor auditing is disabled |
| `-cov-min N` / `-coverage-min N` | Enable coverage and fail below integer percentage N (0..100); uses the complete function inventory (`-cov-statements` line data remains diagnostic) |
| `-cov-functions-min N` | Gate complete static function reachability at N% |
| `-cov-lines-min N` | Enable statement measurement and gate measured statements at N%; partial instrumentation fails closed |
| `-cov-completeness-min N` | Enable statement measurement and require N% of eligible functions to be instrumented |
| `-cov-branches-min N` | Enable branch measurement and gate conditional-edge coverage at N%; partial site instrumentation fails closed |
| `-cov-branch-completeness-min N` | Enable branch measurement and require N% of eligible branch sites to be instrumented |
| `-cov-allow-partial` | Explicitly allow `-cov-lines-min` to use an incomplete statement denominator |
| `--source PATHS` / `--coverage-source PATHS` | Comma-separated source files/directories forming the coverage inventory; unloaded functions are counted at zero |
| `-cov-include PATS` | Comma-separated source-path patterns to include in coverage |
| `-cov-exclude PATS` | Comma-separated source-path patterns to exclude from coverage |
| `-ff` / `--fail-fast` | Stop scheduling remaining expectations after the first failure while still running mandatory cleanup; `-exit` additionally terminates the process at completion |
| `-fh` / `--fail-hard` | Halt remaining expectations and suites on first failure; mandatory cleanup still runs |
| `-random-order` / `--randomOrder` | Deterministically permute files, suites, and expectations with resQ's private PRNG |
| `-seed N` | Non-negative replay seed for `-random-order` (default `0`); recorded in report metadata |
| `-last-failed` / `-lf` | Run only tests whose stable IDs failed or errored in the previous run; missing/empty history safely falls back to the full selection |
| `-failed-first` | Run previous failures first, then the rest, preserving the current deterministic order within each cohort |
| `-state-file PATH` | Override the versioned rerun cache path (default `.resq/last-run.json`) |
| `-flake-history PATH` | Override bounded observation history (default `.resq/flake-history.json`; shard-suffixed) |
| `-quarantine-file PATH` | Read reviewed quarantine policy (default `.resq/quarantine.json`) |
| `-flake-proposal-file PATH` | Override read-only proposal output (default `.resq/quarantine-proposals.json`) |
| `-flake-evidence-min N` | Minimum observations before classification (default 3, minimum 2) |
| `-flake-failure-min N` | Failures required for suspect classification (default 2) |
| `-flake-window N` | Maximum observations retained per stable test ID (default 20) |
| `-flake-proposals` | Write suspect proposals without changing the quarantine manifest |
| `-quarantine-non-blocking` | Let active, unexpired quarantines not block; raw failures remain visible |
| `-snapshot-audit` | Publish complete/partial snapshot inventory without changing the verdict |
| `-snapshot-gate` | Imply audit and fail on partial, missing, obsolete, or unsafe inventory |
| `-benchmark-baseline PATH` | Include `perf` blocks and compare raw timing distributions with a versioned baseline |
| `-benchmark-gate` | Include `perf` blocks and fail on a significant practical regression or unusable baseline |
| `-benchmark-accept-environment` | Explicitly compare despite an environment fingerprint mismatch (otherwise inconclusive/non-gating) |
| `-benchmark-alpha N` | Statistical significance percentage, 1..100 (default 5) |
| `-benchmark-effect-min N` | Minimum absolute median change percentage for improved/regressed (default 5) |
| `-benchmark-min-samples N` | Minimum samples on both sides of a comparison (default 5, minimum 2) |
| `-shard-index I` | Select zero-based native shard `I` |
| `-shard-count N` | Partition the selected shard unit across `N > 0` shards (default `1`) |
| `-shard-unit U` | Select `file` (default), `test`, or declarative `case` assignment |
| `-report-profile P` | JSON evidence profile: `full` (default), `results`, or `telemetry`; sharded/release runs require `full` |
| `-final-diffs` | Repeat retained structural diffs in the final human failure listing |
| `-final-diff-limit N` | Total character budget for `-final-diffs` (default 4000) |
| `-labels JSON` | Overlay a bounded string-to-string `run.labels` object; CLI wins over `RESQ_LABELS_JSON` and config |
| `-no-vcs` | Disable the single cached Git context probe and record VCS status `disabled` |
| `-plugin FILES` | Load comma-separated trusted q plugin files before discovery; files register public observers/reporters under `.resq` |
| `-strict-plugins` | Turn a trapped plugin callback error into a canonical error row and failing exit status (default: warning only) |
| `-desc` / `--describe` | List suites and tests without running; exits 0 (or 4 on load error) |
| `-only PATTERN` | Run only suites whose title matches the `like` glob pattern |
| `-exclude PATTERN` | Skip suites whose title matches the `like` glob pattern |
| `-tag TAG` | Run only suites tagged with TAG (`#TAG` in the title) |
| `-exclude-tag TAG` | Exclude suites tagged with TAG |
| `-maxTestTime N` | Mark a returned test as over-budget after N milliseconds (post-execution; does not interrupt hangs) |
| `-fuzzLimit N` | Limit fuzz failure reporting |
| `-isolate` | Run each test FILE in its own `q` subprocess; the parent aggregates results, reporters, and exit codes (a test calling `exit`, an infinite loop, or a fatal error becomes a per-file failure instead of killing the whole run). This is fault containment, not a security sandbox |
| `-isolateTimeout N` | Per-FILE wall-clock cap in seconds under `-isolate` (default 300; needs the `timeout` binary to preempt a hang) |
| `-isolateWorkers N` | Run N isolated files concurrently (default 1, i.e. sequential). Verdicts, ordering and exit codes are identical to a sequential run; only wall-clock changes. Each worker consumes a q runtime/licence allocation |
| `-outDir DIR` | Output directory for reports and coverage files |
| `-noquit` | Suppress exit call (process stays running; useful interactively) |
| `-exit` | Force exit-on-completion (overrides `"exit": false` in `resq.json`) |
| `-quiet` | Suppress `Loading Test:` lines, the RUN AUDIT block, and per-suite output for passing suites. Failures still print fully. |
| `-v` / `-version` | Print version |
| `--help` / `-usage` / `--usage` | Print usage and exit 0 (`resq -h` works via the launcher; q claims bare `-h` for itself) |
| `-debug` | Enable verbose internal diagnostics |
| `-interactive` | `discover` only: use the interactive discovery wizard |
| `-scaffold` | `discover` only: in addition to `coverage_report.html`, write the `missingTests/` stub tree under `outDir` |

Reporter flags compose. A run with more than one selected format uses
schema-specific filenames so JUnit and xUnit never overwrite one another.
JUnit rows carry `file`/`line`; xUnit v2 rows carry
`source-file`/`source-line`; JSON schema version 2 keeps `message` and `output`
scalar, keeps `failures` list-valued, and places aggregate counts under
`summary`. It also records stable identity, run metadata, retries, cases,
property seeds, lifecycle data, and typed diagnostics. Under `-isolate`, the
first failed/error row from each file
owns its bounded combined child stdout/stderr in `output`; JUnit publishes the
same value as `<system-out>` and xUnit v2 as `<output>`. A reporter error fails
the run after every selected reporter has been attempted.

JSON additionally embeds execution-manifest schema v3 and lifecycle-event
schema v2 (while validators continue to accept legacy event v1). Event v2 uses
recorded test/attempt/case intervals rather than run-boundary projections.
Its manifest publication event carries linkage metadata and counts rather than
duplicating the top-level manifest. JSON declares `profile` and exact
`completeness` omissions; `full` is the compatible release/shard default,
`results` omits non-result sections, and `telemetry` additionally normalizes
test rows to bounded ingestion fields.
Trusted plugins can consume the same canonical stream through
`.resq.registerObserver` and `.resq.registerReporter`; callback return values
are ignored and direct verdict-state mutations are restored. See
[Lifecycle events, execution manifests, and plugins](EVENTS_AND_PLUGINS.md).

Selecting a machine reporter writes that artifact in addition to the final text
summary. Other progress and diagnostic lines can still be written to
stdout/stderr unless `-quiet` suppresses them. See
[Test reporting](REPORTING.md) for filenames, the JSON schema, XML mappings, and
size limits.

Every run that executes at least one real test atomically replaces the
versioned rerun cache at `stateFile`. State schema v2 records the identity-v3
algorithm and exact q codec envelope. Collection/framework-only failures and
describe-only runs leave prior history intact. `-last-failed` and
`-failed-first` use the report's stable `testId`; missing, empty, corrupt, or
unsupported history falls back to the complete current selection and emits a
typed rerun diagnostic; identity-mismatched state is preserved beside the
cache for explicit migration. The default `.resq/` cache directory should remain
uncommitted. Multi-shard runs suffix this cache per shard to avoid concurrent
writers.

Flake history and quarantine policy use the same stable identity but remain
separate authorities. A first failure is always insufficient evidence; only a
reviewed manifest entry can quarantine a test. Quarantined tests continue to
run and retain their raw status. They remain blocking unless
`-quarantine-non-blocking` is explicitly selected, and expiry restores blocking
automatically. See [Flake evidence and quarantine](QUARANTINE.md).

File sharding sorts canonical paths, assigns file position `mod shardCount`,
and only then applies optional seeded ordering. `test` and `case` sharding use a
stable-ID weighted hash: test units keep all declarative rows under their parent,
while case units distribute those rows independently. Ordinary tests and
runtime `.tst.parametrize`/`.tst.forall` calls remain atomic. Shards never
overlap, their complete union equals the unsharded execution inventory, and
normal/isolated runs select the same entities. A valid empty shard exits
successfully even under `-strict`; a globally empty discovery still returns the
ordinary no-tests exit code. Merge complete JSON shard sets with
`bin/resq-merge ... --out-dir DIR`; it rejects incomplete or inconsistent sets.

Coverage runs additionally write `coverage.lcov`, `coverage.json`,
`coverage.html`, and `coverage_state.txt`. All four are projections of one
canonical coverage model. `coverage.json` schema v2 contains aggregate measurement and
instrumentation totals plus per-file, per-function, measured-line, stable
statement-site, anonymous-lambda owner, branch-site, and edge records; see
[Runtime code coverage](COVERAGE.md). With `-cov-contexts`, its
`contextMeasurement` adds stable test/case/attempt attribution, reserved
`unattributed`/`overflow` buckets, explicit bounds/truncation, and metrics that
can be deterministically merged by `.tst.mergeCoverageContexts`.

**Filtering examples:**
```bash
# Run only matching suites (glob on title)
q resq.q test tests/ -only "Order*"

# Exclude slow suites
q resq.q test tests/ -exclude "*slow*"

# Run suites tagged #fast
q resq.q test tests/ -tag fast

# List all suites and tests without running
q resq.q test tests/ -desc

# Hard-stop on first failure
q resq.q test tests/ -ff -exit
```

Tags are `#word` tokens in the suite title string:
```q
.tst.desc["Price validation suite #fast #unit"]{
    ...
};
```

**Examples:**
```bash
# Run all tests
q resq.q test tests/

# Run with JUnit output
q resq.q test tests/ -junit -outDir reports/

# Run only integration tests
q resq.q test tests/ -only "*integration*"

# Run with coverage over a complete source inventory
q resq.q cover tests/ --source src/ -cov-statements -cov-branches

# Watch mode
q resq.q watch src/ tests/

# Watch with a declared coverage inventory (fresh coverage per rerun)
q resq.q watch tests/ -coverage --source src/
```

---

## Configuration File

Create `resq.json` in project root:

```json
{
    "fmt": "text",
    "outDir": "./reports",
    "xmlOutput": false,
    "runPerformance": false,
    "excludeSpecs": "",
    "runSpecs": "",
    "strict": false,
    "failFast": false,
    "failHard": false,
    "randomOrder": false,
    "seed": 0,
    "lastFailed": false,
    "failedFirst": false,
    "stateFile": ".resq/last-run.json",
    "flakeHistoryFile": ".resq/flake-history.json",
    "quarantineFile": ".resq/quarantine.json",
    "flakeProposalFile": ".resq/quarantine-proposals.json",
    "flakeEvidenceMin": 3,
    "flakeFailureMin": 2,
    "flakeWindow": 20,
    "flakeProposals": false,
    "quarantineNonBlocking": false,
    "snapshotAudit": false,
    "snapshotGate": false,
    "benchmarkBaseline": "",
    "benchmarkGate": false,
    "benchmarkAcceptEnvironment": false,
    "benchmarkAlphaPercent": 5,
    "benchmarkEffectMin": 5,
    "benchmarkMinSamples": 5,
    "shardIndex": 0,
    "shardCount": 1,
    "shardUnit": "file",
    "reportProfile": "full",
    "labels": {
        "environment": "staging",
        "service": "orders"
    },
    "vcsProbe": true,
    "strictPlugins": false,
    "pluginFiles": [],
    "pollutionGuard": true,
    "fuzzLimit": 100,
    "maxTestTime": 0,
    "coverageMin": 0,
    "coverageFunctionMin": 0,
    "coverageLineMin": 0,
    "coverageCompletenessMin": 0,
    "covBranches": false,
    "coverageBranchMin": 0,
    "coverageBranchCompletenessMin": 0,
    "allowPartialLineCoverage": false,
    "coverageSources": ["src"],
    "covStatements": false,
    "reportLimit": 50000,
    "reportListLimit": 1000,
    "qNamespaceExports": false,
    "expectationLineAnnotations": true,
    "exit": true,
    "testFilePatterns": ["test_*.q", "*_test.q"],
    "diffLargeTableThreshold": 1000,
    "diffHugeTableThreshold": 10000
}
```

| Key | Default | Purpose |
|-----|---------|---------|
| `fmt` | `"text"` | Default single reporter: `text`, `junit`, `xunit`, or `json` (`console`/`xml` are legacy aliases) |
| `outDir` | `"."` | Report, coverage, and discovery artifact directory |
| `describeOnly` | `false` | Discover and list suites/tests without executing them |
| `xmlOutput` | `false` | Legacy switch that selects JUnit when `fmt` is `text` |
| `runPerformance` | `false` | Include `perf` blocks |
| `excludeSpecs` | empty | Suite-title glob(s) to exclude |
| `runSpecs` | empty | Suite-title glob(s) to include |
| `passOnly` | `false` | qspec-compatible silent result reporting |
| `exit` | `true` | Exit the q process with the run status |
| `strict` | `false` | Fail empty, all-skipped, and assertion-free runs/tests |
| `fuzzLimit` | `100` | Maximum displayed fuzz failures |
| `failFast` | `false` | Enable fail-fast behavior |
| `failHard` | `false` | Halt remaining expectations and suites after failure; mandatory cleanup still runs |
| `randomOrder` | `false` | Deterministically permute files, suites, and expectations |
| `seed` | `0` | Non-negative replay seed used by randomized execution order |
| `lastFailed` | `false` | Select only failures from the previous stable-ID state |
| `failedFirst` | `false` | Prioritize failures from the previous stable-ID state |
| `stateFile` | `.resq/last-run.json` | Versioned, atomically replaced local rerun cache |
| `flakeHistoryFile` | `.resq/flake-history.json` | Bounded, atomically replaced outcome observations |
| `quarantineFile` | `.resq/quarantine.json` | Reviewed owner/reason/evidence/issue/creation/expiry policy |
| `flakeProposalFile` | `.resq/quarantine-proposals.json` | Read-only suspect proposal artifact |
| `flakeEvidenceMin` | `3` | Observations required before classification; minimum 2 |
| `flakeFailureMin` | `2` | Failures required for a mixed pass/fail suspect |
| `flakeWindow` | `20` | Maximum observations retained per stable ID |
| `flakeProposals` | `false` | Emit proposals without mutating policy |
| `quarantineNonBlocking` | `false` | Let active, unexpired quarantine failures not block the exit code |
| `snapshotAudit` | `false` | Publish the versioned snapshot inventory |
| `snapshotGate` | `false` | Fail closed on incomplete or unhealthy snapshot topology |
| `benchmarkBaseline` | `""` | Versioned baseline path; a nonempty value includes `perf` blocks and enables comparison |
| `benchmarkGate` | `false` | Fail on significant practical regressions or an unusable/missing baseline |
| `benchmarkAcceptEnvironment` | `false` | Allow comparison across a recorded fingerprint mismatch |
| `benchmarkAlphaPercent` | `5` | Mann–Whitney/Holm significance percentage (1..100) |
| `benchmarkEffectMin` | `5` | Practical median-change threshold percentage (0..100) |
| `benchmarkMinSamples` | `5` | Minimum raw samples in current and baseline distributions (minimum 2) |
| `shardIndex` | `0` | Zero-based native shard index |
| `shardCount` | `1` | Number of deterministic shards |
| `shardUnit` | `"file"` | Assignment unit: `file`, `test`, or declarative `case` |
| `reportProfile` | `"full"` | JSON evidence profile: `full`, `results`, or `telemetry`; sharded runs require `full` |
| `labels` | `{}` | Bounded string-to-string run context; config is overlaid by `RESQ_LABELS_JSON`, then `-labels JSON` |
| `vcsProbe` | `true` | Run one cached Git context probe; use `false` or `-no-vcs` to disable |
| `strictPlugins` | `false` | Fail the run when a registered plugin callback throws |
| `pluginFiles` | empty | Trusted q plugin file path or list of paths, loaded before discovery |
| `pollutionGuard` | `true` | Detect and restore application-namespace changes per suite |
| `maxTestTime` | `0` | Post-execution per-test budget in milliseconds (`0` disables) |
| `reportLimit` | `50000` | Maximum rendered failure/error message characters |
| `reportListLimit` | `1000` | Compatibility setting; no separate list cap is currently enforced |
| `qNamespaceExports` | `false` | Deprecated compatibility key; accepted but ignored, and `.q` is never modified |
| `expectationLineAnnotations` | `true` | Rewrite expectation constructors to capture source lines and detect incomplete declarations; set `false` as a loader kill switch |
| `diffLargeTableThreshold` | `1000` | Start adaptive table-diff sampling above this row count |
| `diffHugeTableThreshold` | `10000` | Add random table-diff sampling above this row count |
| `testFilePatterns` | `test_*.q`, `*_test.q` | Basename patterns used during directory discovery |
| `qspecCompat` | `false` | Use qspec comparison semantics for `musteq` / `mustne` |
| `finalDiffs` | `false` | Repeat structural diffs in the final human failure listing |
| `finalDiffLimit` | `4000` | Total character budget for final repeated diffs |
| `covStatements` | `false` | Enable measured statement/line instrumentation |
| `coverageMin` | `0` | Coverage gate percentage (`0` disables the threshold) |
| `coverageFunctionMin` | `0` | Independent complete-function threshold |
| `coverageLineMin` | `0` | Independent measured-statement threshold |
| `coverageCompletenessMin` | `0` | Statement-instrumentation completeness threshold |
| `covBranches` | `false` | Enable conditional-edge instrumentation for `if`, `while`, and `$` |
| `coverageBranchMin` | `0` | Independent conditional-edge threshold; partial instrumentation fails closed |
| `coverageBranchCompletenessMin` | `0` | Eligible branch-site instrumentation threshold |
| `allowPartialLineCoverage` | `false` | Allow a line gate to use a partial denominator |
| `coverageSources` | empty | Source files/directories forming the complete coverage inventory |

Supported `fmt` values are `text`, `console`, `junit`, `xunit`, and `json`. `console` is normalized to `text`.

`reportLimit` caps rendered failure/error messages in machine reports.
`reportListLimit` is accepted and retained for compatibility, but the current
reporters do not enforce a separate list-element limit.

`coverageMin` is an integer from 0 through 100. A positive value enables
coverage and applies the same function-based, fail-closed threshold as
`-cov-min`. Set `covStatements` to `true` to add measured statement probes;
their line result is diagnostic because unsafe rewrites can be excluded from
its denominator.

The independent thresholds are integers from 0 through 100. A positive
line or completeness threshold enables statement instrumentation. Line gates
fail when instrumentation completeness is below 100%, regardless of the
measured line percentage, unless `allowPartialLineCoverage` is explicitly true.
Positive branch or branch-completeness thresholds enable branch
instrumentation. A branch percentage gate refuses empty or partial eligible-site
measurement; no opt-out weakens that denominator.

`coverageSources` accepts a path string or list of path strings/symbols. It is
the configuration equivalent of `--source`: directories are scanned
recursively, every `.q` file is represented in the artifacts, and statically
discoverable functions in unloaded modules count as zero hits. A nonempty
declaration that resolves to no `.q` files fails coverage initialization.

`qNamespaceExports` is deprecated. It remains a validated boolean so existing
configuration files continue to load, but both values are safe and equivalent:
resQ never writes DSL names into reserved `.q`. Bare public DSL names in test
source are bound to stable `.tst.dsl.*` helpers; explicit `.tst.*` APIs also work.

`expectationLineAnnotations:false` (or `-no-line-annotations`) disables the
lexical constructor rewrite. Tests and bare DSL bindings still work, but
reporters cannot attach declaration lines and resQ cannot detect a constructor
whose final code argument was accidentally omitted. Use it only to unblock a
suite while reporting a reproducible loader case.

`pollutionGuard` controls deep namespace snapshot/restore checks around each
suite. It defaults to `true`. Snapshotting retains references and unchanged
globals compare by identity, so cost primarily scales with namespace-member
count; keep it enabled for production runs. Disable it only when you knowingly
accept cross-suite state leakage and have measured a project-specific need.

`testFilePatterns` is the list of glob patterns the loader matches against base filenames when scanning a directory. Defaults to `test_*.q` / `*_test.q`. Override for codebases that use other conventions (e.g. `["*_spec.q"]` for BDD, `["*Test.q"]` for xUnit). Explicit `.q` file paths passed on the command line are always honoured regardless of patterns.

`diffLargeTableThreshold` / `diffHugeTableThreshold` control adaptive sampling in `lib/diff.q`. Tables larger than the *large* threshold trigger head/middle/tail sampling instead of a full row scan; tables larger than the *huge* threshold add a random sample on top. Increase both for systems with very large reference tables; decrease for stricter (but slower) diff coverage.

Where a CLI option is supplied, it takes precedence over the corresponding
configuration value. Boolean CLI flags enable behavior; there are no `--no-*`
forms for disabling a configured feature.

Unknown keys and invalid values produce `CONFIG WARNING` lines and are ignored;
the valid/default value remains in effect.

---

*Generated for resQ v2.0.1*
