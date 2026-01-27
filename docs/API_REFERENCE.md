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

---

## 1. Test DSL

The test DSL provides a BDD-style syntax for writing tests.

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
| `props` | dict | Configuration: `runs`, `vars`, `maxFailRate` |
| `code` | function | Property to verify (receives generated values) |

**Example:**
```q
holds["sorting is idempotent"; `runs`vars!(100;`int$())]{[xs]
    (asc xs) musteq asc asc xs;
};

holds["addition is commutative"; `vars!(`int;`int)]{[a;b]
    (a+b) musteq (b+a);
};
```

**Props Dictionary:**
| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `runs` | int | 100 | Number of test iterations |
| `vars` | any | required | Type specification for generated values |
| `maxFailRate` | float | 0.0 | Maximum allowed failure rate (0.0-1.0) |

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

**Example:**
```q
perf["sorting 10000 elements"; `iterations`warmup!(1000;100)]{
    asc 10000?1000;
};
```

---

## 2. Assertions

All assertions are available in the root namespace for convenience.

### must

```q
must[condition; message]
```

Assert that a condition is true.

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `condition` | boolean | Condition to verify |
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

Assert values are not equal.

**Example:**
```q
userId mustne 0;
result mustne `;
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
- Pattern uses `like` matching (wildcards: `*`, `?`)
- Code can be a function or `(function; arg1; arg2; ...)` list
- Multiple patterns: throws if ANY pattern matches

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

**Examples:**
```q
/ Single integer parameter
holds["positive"; `vars!`int]{[x] x+1 mustgt x};

/ Integer list
holds["sorted"; `vars!(`int$())]{[xs] (asc xs) musteq asc asc xs};

/ Multiple parameters
holds["commutative"; `vars!`a`b!(`int;`int)]{[a;b] (a+b) musteq (b+a)};

/ Custom generator
holds["even"; `vars!{2*1?1000}]{[x] 0 musteq x mod 2};

/ Choice from list
holds["valid status"; `vars!`pending`active`done]{[s] s mustin `pending`active`done};
```

---

### pickFuzz

```q
.tst.pickFuzz[spec; runs]
```

Generate random values according to specification.

**Returns:** List of generated values

---

### shrink

```q
.tst.shrink[code; typeCode; value]
```

Shrink a failing input to minimal reproducing case.

**Notes:**
- Automatically called when a fuzz test fails
- Works by binary search on lists
- Minimal case is printed to console

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

Wait for a deferred to settle.

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `id` | symbol | Deferred ID |
| `timeoutMs` | long | Timeout in milliseconds |

**Returns:** Resolved value

**Throws:** Error if rejected or timeout

**Example:**
```q
id: .tst.deferred[];
/ Start async operation that will call .tst.resolve[id; result]
result: .tst.await[id; 5000];
```

---

### eventually

```q
.tst.eventually[condition; timeoutMs; intervalMs]
```

Poll a condition until it succeeds or times out.

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

## 8. Snapshots

### mustmatchSnap

```q
.tst.mustmatchSnap[actual; name]
actual mustmatchs name
```

Assert value matches stored binary snapshot.

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `actual` | any | Value to compare |
| `name` | string/symbol | Snapshot name |

**Behavior:**
- If snapshot doesn't exist: creates it
- If `updateSnaps` is true: overwrites snapshot
- Otherwise: compares and fails on mismatch

**Example:**
```q
result mustmatchs "query_output";
```

---

### mustmatchTxtSnap

```q
.tst.mustmatchTxtSnap[actual; name]
actual mustmatchst name
```

Assert value matches stored text snapshot (uses `.Q.s1` serialization).

---

### setSnapDir

```q
.tst.setSnapDir[directory]
```

Set snapshot storage directory.

**Default:** `{cwd}/tests/snapshots`

---

### setUpdateSnaps

```q
.tst.setUpdateSnaps[bool]
```

Enable/disable snapshot update mode.

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
| `p50/p90/p95/p99_ns/us` | Percentiles |
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
.tst.toString 1b         / "true"
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
q resq.q [mode] [options] [paths...]
```

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
| `-junit` | Output JUnit XML |
| `-xunit` | Output XUnit XML |
| `-perf` | Include performance tests |
| `-cov` / `-coverage` | Enable coverage |
| `-ff` / `--fail-fast` | Stop on first failure |
| `-fh` / `--fail-hard` | Hard stop (no cleanup) |
| `-desc` / `--describe` | List tests without running |
| `-only PATTERN` | Run only matching specs |
| `-exclude PATTERN` | Skip matching specs |
| `-outDir DIR` | Output directory |
| `-noquit` | Don't exit after tests |
| `-exit` | Exit with status code |
| `-v` / `-version` | Print version |

**Examples:**
```bash
# Run all tests
q resq.q -test tests/

# Run with JUnit output
q resq.q -test tests/ -junit -outDir reports/

# Run only integration tests
q resq.q -test tests/ -only "*integration*"

# Run with coverage
q resq.q cover src/ tests/

# Watch mode
q resq.q watch src/ tests/
```

---

## Configuration File

Create `resq.json` in project root:

```json
{
    "fmt": "console",
    "outDir": "./reports",
    "xmlOutput": false,
    "runPerformance": false,
    "excludeSpecs": "",
    "runSpecs": "",
    "failFast": false,
    "failHard": false,
    "fuzzLimit": 100,
    "exit": true
}
```

CLI arguments override configuration file values.

---

*Generated for resQ v0.1.0-alpha*
