# resQ Troubleshooting Guide

Common issues and their solutions when using the resQ testing framework.

---

## Table of Contents

1. [Test Loading Errors](#1-test-loading-errors)
2. [Assertion Failures](#2-assertion-failures)
3. [Mock and Spy Issues](#3-mock-and-spy-issues)
4. [Fixture Problems](#4-fixture-problems)
5. [Async and Timing Issues](#5-async-and-timing-issues)
6. [Property-Based Testing](#6-property-based-testing)
7. [Snapshot Testing](#7-snapshot-testing)
8. [CI/CD Integration](#8-cicd-integration)
9. [Performance Issues](#9-performance-issues)
10. [q Language Limitations](#10-q-language-limitations)

---

## 1. Test Loading Errors

### Error: "CRITICAL LOAD ERROR" with backslash

**Symptom:**
```
CRITICAL LOAD ERROR in tests/mytest.q: "\l lib/mock.q"
```

**Cause:** String containing `\l` is being interpreted as a system command during `value` evaluation.

**Solution:** Escape the backslash in strings:
```q
/ Wrong
testContent: "\l lib/mock.q";

/ Correct
testContent: "\\l lib/mock.q";
```

---

### Error: "/" during test loading

**Symptom:**
```
CRITICAL LOAD ERROR in tests/mytest.q: /
```

**Cause:** Forward slashes in symbol literals are being interpreted as comments during `value` evaluation.

**Solution:** Construct symbols from strings instead:
```q
/ Wrong
expected: `lib/mock.q`lib/fixture.q;

/ Correct
expected: (`$"lib/mock.q"; `$"lib/fixture.q");
```

---

### Error: "type" error when loading test file

**Symptom:**
```
!!! HALTING FAILURE !!!
Suite: My Test Suite
Error: type
```

**Cause:** Multi-line function definitions with nested code blocks can fail to parse when evaluated via `value`. This is a q language limitation.

**Solution:** Simplify the test structure or split into separate tests:
```q
/ Problematic pattern (nested code blocks in multi-line function)
should["complex test"]{
    `s mock .tst.desc["Inner"]{
        .tst.alt {
            should["nested"]{};
        };
    };
};

/ Better: Test the components separately
should["test alt behavior"]{
    / Simpler test without deep nesting
};
```

---

### Error: Test file not found

**Symptom:**
```
Error loading test: tests/mytest.q not found
```

**Cause:** Path is incorrect or file doesn't exist.

**Solutions:**
1. Verify the file exists: `ls tests/mytest.q`
2. Use absolute paths or paths relative to project root
3. Check file extension is `.q`

---

## 2. Assertion Failures

### Unexpected type mismatch

**Symptom:**
```
Type mismatch
  Expected type: -7h
  Actual type:   -6h
```

**Cause:** Comparing int (type -6h) with long (type -7h).

**Solution:** Ensure consistent types:
```q
/ Problem
42 musteq 42j;  / int vs long

/ Solutions
42j musteq 42j;          / Both long
(`long$42) musteq 42j;   / Cast to match
```

---

### Float comparison fails

**Symptom:**
```
Expected 3.14159 to match 3.14159
```

**Cause:** Floating point precision differences.

**Solution:** Use `mustdelta` for floating point comparisons:
```q
/ Problem
result musteq 3.14159;

/ Solution
mustdelta[0.00001; result; 3.14159];
```

---

### Table comparison shows no obvious difference

**Symptom:** Tables look identical but `musteq` fails.

**Cause:** Could be column order, key differences, or metadata.

**Solutions:**
```q
/ Check column order
cols expected
cols actual

/ Check if keyed
type expected  / 98h = unkeyed, 99h = keyed

/ Use order-ignoring comparison
mustmatchignoringorder[actual; expected];

/ Compare specific columns only
actual mustincludecols expected;
```

---

### "Expected X to be greater than 0" when value is 0

**Symptom:**
```
Expected 0 to be greater than 0
```

**Cause:** The value being tested is actually 0, not what you expected.

**Solutions:**
1. Debug the actual value:
```q
should["test something"]{
    result: .myFunc[];
    -1 "DEBUG: result = ", .Q.s1 result;  / Add debug output
    count result mustgt 0;
};
```

2. Check if the function is being mocked incorrectly
3. Verify test setup is correct

---

## 3. Mock and Spy Issues

### Mock not being restored

**Symptom:** Mock value persists after test, affecting other tests.

**Cause:** Test may have failed before `.tst.restore[]` was called, or manual restore was forgotten.

**Solution:** resQ automatically restores mocks after each test. If you see this issue:
1. Check if test is using `failHard` mode
2. Manually call `.tst.restore[]` if needed
3. Ensure mock names use correct namespace prefix

---

### Mock creates wrong variable location

**Symptom:** Global variable `foo` becomes `.tst.foo` instead.

**Cause:** When running in `.tst` namespace, `foo set value` creates `.tst.foo`.

**Solution:** This is fixed in resQ. If you see this in custom code, use:
```q
/ For global variables, use functional form
@[`.;`foo;:;value];

/ Or use the full mock function which handles this
`foo mock value;
```

---

### Spy not recording calls

**Symptom:** `.tst.callCount` returns 0 even though function was called.

**Causes and Solutions:**

1. **Function was called before spy was set up:**
```q
/ Wrong order
.myFunc[];  / Called before spy
.tst.spy[`.myFunc; ::];

/ Correct order
.tst.spy[`.myFunc; ::];
.myFunc[];  / Now calls are tracked
```

2. **Wrong function name:**
```q
/ Check the exact name
.tst.spy[`.module.func; ::];  / Note the leading dot and full path
```

3. **Function doesn't exist:**
```q
/ Verify function exists before spying
type `.module.func  / Should return 100h for functions
```

---

### "Cannot mock a system namespace"

**Symptom:**
```
'Cannot mock a system namespace
```

**Cause:** Attempting to mock `.q`, `.Q`, `.z`, `.h`, `.j`, `.tst`, `.resq`, or `.utl`.

**Solution:** Create a wrapper function instead:
```q
/ Wrong
`.Q.s mock {x};

/ Correct: wrap the system function
.myModule.serialize: .Q.s;
/ Then mock your wrapper
`.myModule.serialize mock {x};
```

---

## 4. Fixture Problems

### "Fixture not found"

**Symptom:**
```
'Error loading fixture 'mydata', not found in /path/to/tests
```

**Causes and Solutions:**

1. **File doesn't exist:** Create the fixture file
2. **Wrong location:** Place fixture in:
   - Same directory as test file
   - `fixtures/` subdirectory of test directory
3. **Wrong name:**
```q
/ If file is "users.json", use:
fixture[`users];  / or
.tst.fixtureAs[`users; `myUsers];
```

---

### Fixture not being cleaned up

**Symptom:** Temporary files or resources persist after tests.

**Solution:** Register fixture with teardown:
```q
.tst.registerFixtureWithOpts[`tempFile; "/tmp/test.txt";
    `scope`teardown!(
        `test;  / Cleanup after each test
        {[path] system "rm -f ",path}
    )
];
```

---

### Session fixture runs multiple times

**Symptom:** Expensive setup runs for every test.

**Cause:** Fixture scope is `test` (default) instead of `session`.

**Solution:**
```q
.tst.registerFixtureWithOpts[`dbConn; (::);
    `scope`setup`teardown!(
        `session;  / Only run once
        {hopen `:localhost:5000};
        {[h] hclose h}
    )
];
```

---

## 5. Async and Timing Issues

### "Eventually timed out"

**Symptom:**
```
'Eventually timed out after 5000ms
```

**Causes and Solutions:**

1. **Condition never becomes true:**
```q
/ Debug by checking condition manually
-1 "Condition result: ", string myCondition[];
```

2. **Timeout too short:**
```q
/ Increase timeout
.tst.eventually[condition; 30000; 100];  / 30 seconds
```

3. **Condition throws instead of returning false:**
```q
/ Wrap in error handler
safeCond: {[c] @[c; ::; {0b}]};
.tst.eventually[safeCond condition; 5000; 100];
```

---

### Async test passes locally but fails in CI

**Symptom:** Tests pass on developer machine but fail in CI.

**Causes:**
1. CI machines are slower
2. Network latency differences
3. Resource contention

**Solutions:**
```q
/ Increase timeouts for CI
timeout: $[`CI in key .z.e; 30000; 5000];
.tst.eventually[condition; timeout; 100];

/ Or use environment-based config
.tst.await[id; getenv[`TEST_TIMEOUT] ^ 5000];
```

---

### Promise in unexpected state

**Symptom:**
```
'Promise in unexpected state
```

**Cause:** Awaiting a promise that was neither resolved nor rejected.

**Solution:** Ensure async operations always call resolve or reject:
```q
.async.operation:{[id]
    @[{
        result: doWork[];
        .tst.resolve[id; result];
    }; ::; {[id;e]
        .tst.reject[id; e];
    }[id]];
};
```

---

## 6. Property-Based Testing

### "Over max failure rate"

**Symptom:**
```
Over max failure rate. Shrunk: [minimal case]
```

**Cause:** Too many generated inputs failed the property.

**Solutions:**

1. **Property is too strict:**
```q
/ Relax the property or add preconditions
holds["positive sqrt"; `vars!`float]{[x]
    if[x < 0; :()];  / Skip negative inputs
    (sqrt x) * (sqrt x) mustwithin (x-0.0001; x+0.0001);
};
```

2. **Increase allowed failure rate:**
```q
holds["occasionally fails"; `maxFailRate`vars!(0.05; `int)]{[x]
    / Allow 5% failure rate
};
```

---

### Shrinking produces unhelpful minimal case

**Symptom:** Shrunk case is not actually minimal or is confusing.

**Cause:** Current shrinking only does binary search on lists.

**Solution:** Manually investigate the failure:
```q
/ Test the shrunk case directly
testProperty[shrunkCase];

/ Or add debug output
holds["debug"; `vars!`int]{[x]
    -1 "Testing: ", string x;
    / ... property ...
};
```

---

### Fuzz test is slow

**Symptom:** Property tests take too long.

**Solutions:**
```q
/ Reduce number of runs
holds["fast test"; `runs`vars!(10; `int)]{[x] ...};

/ Use simpler generators
holds["simple"; `vars!(`a`b`c)]{[x] ...};  / Pick from 3 values
```

---

## 7. Snapshot Testing

### Snapshot mismatch on different machines

**Symptom:** Snapshots match locally but fail in CI.

**Causes:**
1. Line ending differences (Windows vs Unix)
2. Floating point representation
3. Timestamp or date differences
4. Dictionary/table key ordering

**Solutions:**
```q
/ Normalize data before snapshot
normalized: asc data;  / Sort for consistent order
normalized mustmatchs "snapshot";

/ For timestamps, use relative or mock
`now mock 2024.01.01D00:00:00;
```

---

### How to update snapshots

**Solution:**
```q
/ In test file or before running
.tst.setUpdateSnaps[1b];

/ Or delete the snapshot file and re-run
system "rm tests/snapshots/mytest.snap";
```

---

### Snapshot directory not created

**Symptom:**
```
WARNING: Failed to create directory ./tests/snapshots
```

**Solution:** Manually create the directory or check permissions:
```bash
mkdir -p tests/snapshots
chmod 755 tests/snapshots
```

---

## 8. CI/CD Integration

### Exit code is always 0

**Symptom:** CI doesn't fail even when tests fail.

**Cause:** Missing `-exit` flag.

**Solution:**
```bash
q resq.q -test tests/ -exit
```

---

### JUnit XML not generated

**Symptom:** No XML file in output directory.

**Solutions:**
```bash
# Ensure flags are set
q resq.q -test tests/ -junit -outDir reports/ -exit

# Check directory exists
mkdir -p reports/
```

---

### Tests timeout in CI

**Symptom:** Tests complete locally but timeout in CI.

**Solutions:**
1. Increase CI timeout
2. Use `-ff` (fail-fast) to stop on first failure
3. Run subsets of tests in parallel jobs
4. Profile slow tests and optimize

---

### Tests pass locally but fail in CI (general)

**Checklist:**
1. **q version:** Ensure CI uses same q version
2. **Timezone:** Tests with dates/times may be affected
3. **File paths:** Use relative paths, not absolute
4. **Environment variables:** Check all required vars are set
5. **Randomness:** Seed random generators for reproducibility
6. **Resource limits:** CI may have memory/CPU constraints

---

## 9. Performance Issues

### Tests are slow

**Diagnosis:**
```bash
# Run with timing
q resq.q -test tests/ -perf
```

**Solutions:**
1. **Use session-scoped fixtures** for expensive setup
2. **Mock slow dependencies** (databases, APIs)
3. **Reduce fuzz test iterations** in CI
4. **Run tests in parallel** (when implemented)

---

### Memory usage is high

**Causes:**
1. Large fixtures not being cleaned up
2. Spy logs accumulating
3. Coverage tracking on large codebase

**Solutions:**
```q
/ Clear spy logs periodically
.tst.clearSpyLogs[];

/ Use test-scoped fixtures instead of session
/ Disable coverage for memory-constrained environments
```

---

## 10. q Language Limitations

### Multi-line strings in code blocks

**Problem:** q doesn't support multi-line strings in lambdas loaded via `value`.

**Workaround:**
```q
/ Instead of multi-line:
should["test"]{
    sql: "SELECT *
          FROM users";  / This can fail
};

/ Use concatenation:
should["test"]{
    sql: "SELECT * FROM users";
    / Or
    sql: "SELECT * ","FROM users";
};
```

---

### Nested function definitions

**Problem:** Deeply nested function definitions can fail during parsing.

**Workaround:** Define helper functions at module level:
```q
/ Instead of:
should["test"]{
    helper: {[x] {[y] x+y}[x]};  / Nested
};

/ Define at top level:
myHelper: {[x;y] x+y};
should["test"]{
    helper: myHelper[;someValue];
};
```

---

### Cannot mock operators

**Problem:** Cannot mock `+`, `-`, etc.

**Workaround:** Wrap operations in functions:
```q
.math.add: {x+y};
`.math.add mock {[x;y] 0};  / Now mockable
```

---

## Quick Reference: Common Error Messages

| Error | Likely Cause | Quick Fix |
|-------|--------------|-----------|
| `'type` | Type mismatch in comparison | Check types with `type` |
| `'rank` | Wrong number of arguments | Check function arity |
| `'length` | List length mismatch | Check `count` of operands |
| `'nyi` | Feature not yet implemented | Use alternative approach |
| `'` (empty) | Assignment to undefined variable | Define before use |
| `'domain` | Invalid input to function | Validate inputs |
| `'limit` | Exceeded q limits | Reduce data size |
| `Cannot mock` | Mocking system namespace | Use wrapper function |
| `Fixture not found` | Wrong path or name | Check location |
| `Eventually timed out` | Condition never true | Increase timeout or fix condition |

---

## Getting Help

1. **Check the API Reference:** `documentation/API_REFERENCE.md`
2. **Review examples:** `examples/quickstart/`
3. **Read the docs:** `docs/` directory
4. **File an issue:** [GitHub Issues](https://github.com/your-org/resq/issues)

---

## Debug Mode

Enable debug output for more information:

```q
.utl.DEBUG: 1b;
/ Then run your tests
```

Or from command line:
```bash
q resq.q -test tests/ -debug
```

---

*Generated for resQ v0.1.0-alpha*
