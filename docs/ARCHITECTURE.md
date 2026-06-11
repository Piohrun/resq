# resQ Namespace Architecture

## Core Namespaces

### `.tst` - Test Framework
Primary namespace for all testing functionality.

| Function | Purpose |
|----------|---------|
| `.tst.desc` / `.tst.should` | BDD DSL for test specs |
| `.tst.asserts` | Assertion registry (musteq, must, etc.) |
| `.tst.mock` / `.tst.spy` | Mocking and spying |
| `.tst.fixtures` | Fixture registry |
| `.tst.skip` / `.tst.pending` | Skip/pending test support (may be mixed freely with `should`) |
| `.tst.beforeAll` / `.tst.afterAll` | Suite-level setup/teardown hooks (run once per desc block) |
| `.tst.stackTrace` | Debug trace capture |
| `.tst.normalizeResultStatus` | Maps internal execution states to public statuses |

### `.resq` - Runner State
Runtime state and configuration.

| Key | Purpose |
|-----|---------|
| `.resq.state.results` | Test results table |
| `.resq.config` | Configuration settings |
| `.resq.VERSION` | Library version |
| `.resq.EXIT.*` | Exit code constants |

**Exit Codes**:
- `0` - PASS: All tests passed
- `1` - FAIL: One or more tests failed
- `2` - CONFIG_ERROR: Configuration/CLI error
- `3` - NO_TESTS: No tests found (strict mode)
- `4` - LOAD_ERROR: File load/syntax error, or explicitly-passed path not found
- `5` - PARTIAL: Some tests errored or were skipped

**Public result statuses**:
- `pass` - expectation completed successfully
- `fail` - assertion, fuzz, or explicit test failure
- `error` - load, hook, timeout, reporter, or unexpected execution error
- `skip` - skipped expectation
- `pending` - pending placeholder expectation

### `.utl` - Utilities
Low-level utilities and loader.

| Function | Purpose |
|----------|---------|
| `.utl.require` | Module loader |
| `.utl.pathToString` | Path normalization |
| `.utl.loaded` | Loaded modules tracking |
| `.utl.isLinux/isMac/isWindows` | OS detection |

## Root Namespace Exports
For convenience, key DSL functions are exported:
- `describe`, `should`, `it`, `before`, `after`
- `musteq`, `mustmatch`, `mustthrow`, etc.
- `mock`, `fixture`, `fixtureAs`
- `skip`, `pending`, `skipIf`

For backward compatibility, resQ can also export these helpers into `.q`. `.q` is reserved by kdb+, so this is controlled by `qNamespaceExports` in `resq.json` and defaults to enabled for existing suites. With the flag off, unqualified DSL names will not resolve inside sandboxed test files (q's namespace fallback goes through `.q`); fully-qualified `.tst.*` names are required throughout.

## File Structure

```
lib/
├── bootstrap.q      # Loader, OS utilities
├── init.q           # State, reporting
├── runner.q         # Test execution
├── config.q         # JSON config
├── cli.q            # CLI parsing
├── dsl/
│   ├── ui.q         # DSL (describe/should/skip)
│   ├── spec.q       # Spec runner
│   ├── expec.q      # Expectation runner
│   ├── assertions.q # Assertions
│   ├── fuzz.q       # Fuzz / property-based testing
│   └── internals.q  # Shared state, helpers
├── fixture.q        # Fixtures
├── mock.q           # Mocking
├── diff.q           # Deep diff
└── output/
    ├── sanitize.q   # Canonical result normalization
    ├── text.q       # Console reporter
    ├── json.q       # JSON reporter
    ├── junit.q      # JUnit XML
    └── xunit.q      # XUnit XML
```

## Testing the Framework

`tests/` contains the framework's own unit tests (`test_*.q`). In addition, `tests/golden/` holds an end-to-end golden test harness (`test_golden.q`) that runs resQ itself as a subprocess against small fixture suites (`tests/golden/fixtures/f_*.q`) and asserts exit codes, summary lines, and report-file content (JUnit XML structure, JSON via `.j.k`). Fixture files use the `f_` prefix so they are not auto-discovered by normal test runs.
