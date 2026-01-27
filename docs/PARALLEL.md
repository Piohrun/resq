# ⚡ Parallel Test Execution

`resQ` includes a high-performance parallel runner that distributes test files across multiple kdb+ worker processes. This is inspired by `pytest-xdist` and is designed to drastically reduce test execution time for large-scale enterprise projects.

## How it Works
The runner identifies all test files in a project and distributes them to workers using the kdb+ `peach` keyword. Each worker executes its assigned test file in isolation and returns the results to the master process for aggregation.

## Usage
To run tests in parallel, start your q session with the `-s` flag followed by the number of cores/workers.

```bash
# Run tests with 4 parallel workers (library API)
q -s 4 -e "\\\\l resq.q; .tst.runParallel[enlist `tests]"
```

### Automatic Mode Detection
The parallel runner detects if secondary processes are available:
- If `system "s"` > 0: **Parallel Mode** is activated.
- If `system "s"` = 0: **Sequential Mode** (standard execution) is used.

## Backward Compatibility (`#sequential`)
Some legacy tests may have side effects or dependencies that prevent them from running in parallel (e.g., replaying a TP log into a shared global RDB).

To force a test suite to run sequentially in the main process, add the `#sequential` tag anywhere in the file (conventionally at the top).

**Example:**
```q
/ tests/legacy_rdb.q
/ #sequential

.tst.desc["Legacy RDB Replay"]{
  should["replay logs in order"]{
    ...
  };
};
```

The Parallel Runner will automatically:
1. Scan for `#sequential` tags.
2. Run independent tests in parallel.
3. Run tagged tests sequentially in the main process *after* parallel execution completes.

## Notes
- The parallel runner is a low-level API and is not wired into the `resq.q` CLI. It returns spec results; if you need XML/JSON output, wrap it in a custom runner.

## Performance Tuning
- **Overhead**: Parallel execution has a small overhead for worker synchronization. For small test suites (< 5 files), sequential mode may be faster.
- **Varying Load**: Try to balance the size of your test files. One massive file will bottleneck the runner while others wait.
- **Worker count**: Setting `-s` to more than the available physical cores may degrade performance.
