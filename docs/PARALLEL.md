# Parallel Test Execution

In-process parallel execution (`parallel_runner.q` / `.tst.runParallel`) has been **removed**.

## Why it was removed

The implementation was unreachable dead code and is architecturally unsound: q
secondary threads cannot write to global variables. A worker that executes a
test file and tries to record results into `.resq.state.results` or another
global table would lose those writes. There is no safe way to aggregate those
per-thread results into a shared table in one q process with the APIs used here.

## Local parallelism: `-isolateWorkers N`

The conclusion above applies to threads *inside one q process*. It does not apply
to `-isolate`, which has already paid for separate **processes**: every test file
runs in its own q child that owns a private scratch directory and communicates
only through files in it. There is no shared state to lose, so those children can
run concurrently.

```bash
resq test tests/ -isolate -isolateWorkers 8
```

Files run in fixed-size groups. Children in a group start together; their results
are interpreted — and printed — strictly in **file order** once the group
finishes. So parallel and sequential runs produce the same verdicts, the same
ordering, and the same exit code; only wall-clock changes. Durations, generated
report IDs, and timestamps naturally vary between runs, so complete artifact
bytes are not expected to be identical.

Speedup is bounded by the slowest single file, since no file is split. The
default is 1, so the sequential behaviour everyone already relies on is unchanged
unless you ask for more. Memory scales with worker count: N concurrent q
processes, each holding its own workspace and consuming a q runtime/licence
allocation. A group is reported after all of its children finish, so one slow
file can delay display of earlier completed files in that group.

`tests/test_isolate.q` pins the equivalence — a parallel run must reach the same
per-test verdicts, in the same order, as the sequential run over the same files.

Process isolation is not a security sandbox. Every worker inherits the invoking
user's filesystem, environment, network, and credentials. Use workers only for
trusted tests and size the count to the runner's memory and licence capacity.

## Distributing further: CI-level sharding

For scale beyond one machine — or to parallelize *across* the slowest file —
shard at the CI level as well.

Split test directories across CI jobs. Each job runs `resq test` against its
slice of the tree and emits a JUnit XML file for the CI system to merge.

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

This provides cross-machine parallelism with no shared q state and lets the CI
platform aggregate the JUnit reports.

See [CI.md](CI.md) for q runner licensing/prerequisites and the repository's
checked-in workflow.
