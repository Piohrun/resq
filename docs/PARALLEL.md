# Parallel Test Execution

In-process parallel execution (`parallel_runner.q` / `.tst.runParallel`) has been **removed**.

## Why it was removed

The implementation was unreachable dead code and is architecturally unsound: q secondary threads cannot write to global variables. A worker that executes a test file and tries to record results into `.resq.state.results` or any other global table would silently lose those writes. There is no safe way to aggregate per-thread results back into a shared table in a single q process without a locking mechanism that q does not expose.

## Local isolation is resilient, but sequential

`resq test tests/ -isolate` already uses a separate q subprocess for every test
file and aggregates their JSON results. This contains `exit`, hangs, and fatal
resource errors, but files are launched sequentially so result ordering stays
deterministic and resource usage is bounded. It is a resilience mode, not a
local parallel scheduler.

## Recommended parallel approach: CI-level sharding

Split your test directories across multiple CI jobs. Each job runs a sequential `resq test` against its slice of the test tree and emits a JUnit XML file. Your CI system merges the reports.

**Example (GitHub Actions matrix):**

```yaml
strategy:
  matrix:
    suite: [tests/unit, tests/integration, tests/golden]
steps:
  - run: resq test ${{ matrix.suite }} -strict -isolate -junit -outDir reports/
  - uses: actions/upload-artifact@v4
    with:
      name: test-results-${{ matrix.suite }}
      path: reports/test-results.xml
```

This gives true parallelism with no shared state, full result aggregation via the CI platform's built-in JUnit merge, and no framework changes required.

See [CI.md](CI.md) for q runner licensing/prerequisites and the repository's
checked-in workflow.
