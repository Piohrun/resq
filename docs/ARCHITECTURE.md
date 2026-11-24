# resQ Namespace Architecture
<!-- Internal/contributor reference document. Users can skip this; see API_REFERENCE.md instead. -->

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

**Exit Codes** (see the authoritative table in TROUBLESHOOTING.md § CI/CD Integration):
- `0` - PASS: All tests passed
- `1` - FAIL: One or more tests failed or errored
- `3` - NO_TESTS: No test files found and no results (without `-strict`)
- `4` - LOAD_ERROR: File load/syntax error, or explicitly-passed path not found

Codes 2 (CONFIG_ERROR) and 5 (PARTIAL) were removed — no code path emits them.

**Public result statuses**:
- `pass` - expectation completed successfully
- `fail` - assertion, fuzz, or explicit test failure
- `error` - load, hook, timeout, reporter, or unexpected execution error
- `skip` - skipped expectation
- `pending` - pending placeholder expectation

### `.resq.util` - Utilities
Low-level utilities and loader. resQ reads nothing from `.utl`, which belongs
to qutil and to many teams' own code. For test code written against the old
names, each helper is also offered as `.utl.<name>` where that name is free.

| Function | Purpose |
|----------|---------|
| `.resq.require` (`.utl.require`) | Module loader |
| `.resq.util.pathToString` | Path normalization |
| `.resq.util.loadQFile` | Load a file as `\l` does, also when its path has spaces |
| `.resq.util.shellQuote` | Quote a path for a shell command |
| `.resq.util.isDir/isFile/pathExists` | File system checks |
| `.resq.util.isLinux/isMac/isWindows` | OS detection |
| `.resq.loaded` | Loaded modules tracking |

## Root Namespace Exports
For convenience, key DSL functions are exported:
- `describe`, `should`, `it`, `before`, `after`
- `musteq`, `mustmatch`, `mustthrow`, etc.
- `mock`, `fixture`, `fixtureAs`
- `skip`, `pending`, `skipIf`

Test-source preprocessing binds unqualified public names to stable
`.tst.dsl.*` helpers. This preserves qspec syntax without writing into reserved
`.q`, so ordinary application locals such as `before`, `after`, `mock`, or `it`
remain legal. Explicit `.tst.*` calls stay available and intentionally remain
mockable. The legacy `qNamespaceExports` key is deprecated and ignored.

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
