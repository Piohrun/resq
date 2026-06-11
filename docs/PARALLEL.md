# Parallel Test Execution

In-process parallel execution (`parallel_runner.q` / `.tst.runParallel`) has been **removed**.

## Why it was removed

The implementation was unreachable dead code and is architecturally unsound: q secondary threads cannot write to global variables. A worker that executes a test file and tries to record results into `.resq.state.results` or any other global table would silently lose those writes. There is no safe way to aggregate per-thread results back into a shared table in a single q process without a locking mechanism that q does not expose.

## Recommended approach: CI-level parallelism

Split your test directories across multiple CI jobs. Each job runs a sequential `resq test` against its slice of the test tree and emits a JUnit XML file. Your CI system merges the reports.

**Example (GitHub Actions matrix):**

```yaml
strategy:
  matrix:
    suite: [tests/unit, tests/integration, tests/golden]
steps:
  - run: resq test ${{ matrix.suite }} -junit -outDir reports/ -exit
  - uses: actions/upload-artifact@v4
    with:
      name: test-results-${{ matrix.suite }}
      path: reports/test-results.xml
```

This gives true parallelism with no shared state, full result aggregation via the CI platform's built-in JUnit merge, and no framework changes required.
