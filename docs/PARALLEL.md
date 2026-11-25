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

Files run through a pool of N workers: the next file starts the moment a
worker is free, so a slow file holds one worker and nothing else. Results are
interpreted — and printed — strictly in **file order**, each as soon as that
file and every file before it has finished. So parallel and sequential runs
produce the same verdicts, the same ordering, and the same exit code; only
wall-clock changes. Durations, generated report IDs, and timestamps naturally
vary between runs, so complete artifact bytes are not expected to be identical.

The unit of concurrency is the file: resQ does not run tests inside a file
concurrently. Each active worker consumes one q process, its workspace and
memory, and one q runtime/licence allocation; choose the worker count from the
smaller of the machine-capacity and licence-capacity limits.

Speedup is bounded by the slowest single file, since no file is split. The
default is 1, so the sequential behaviour everyone already relies on is unchanged
unless you ask for more. Memory scales with worker count: N concurrent q
processes, each holding its own workspace and consuming a q runtime/licence
allocation. Because output is in file order, a slow file delays the display,
not the running, of the files after it.

The pool needs a `sleep` that accepts fractions of a second (GNU, BSD and
macOS do; some minimal busybox builds do not). Without one, files run in
groups of N: the next group starts when the slowest file of the current one
has finished. `resq mutate` runs its mutants in such groups everywhere.

Isolation needs a `timeout` command on `PATH` that takes `-k` (kill after a
grace period): GNU coreutils of any age, or a recent busybox. resQ checks that
it can stop a busy process before it starts, and refuses to run with a message
if it cannot. Where `timeout` also has `--verbose` (coreutils 8.29 and later)
resQ uses it to tell its own timeout from any other death of the child;
without it, exit status 124 is taken as the timeout.
`-isolateTimeout N` caps each whole file, not each test; timing out abandons any
later tests in that file. The failure names the test that was running, and
tests that had already finished keep their results; the same applies to a child
that exits or is killed. The child checkpoints its report as it runs, spaced so
the cost stays linear, so in a large file the last few finished tests can fall
after the final checkpoint. The failure message states how many were lost.

When an isolated file finishes, resQ terminates any background process the
file started and left running (anything still in the child's process group)
and prints a warning naming the file and the first three processes found.
Stop such processes in `after` or
`afterAll` instead of relying on this. A process that moved itself to another
session (`setsid`, a daemon) is not reached. `-maxTestTime N` is an observational post-return test
budget and cannot stop a hang. Coverage instrumentation does not compose with
child isolation, so production uses paired isolated-correctness and
non-isolated-coverage lanes.

`tests/test_isolate.q` pins the equivalence — a parallel run must reach the same
per-test verdicts, in the same order, as the sequential run over the same files.

Process isolation is not a security sandbox. Every worker inherits the invoking
user's filesystem, environment, network, and credentials. Use workers only for
trusted tests and size the count to the runner's memory and licence capacity.

## Distributing further: CI-level sharding

For scale beyond one machine — or to parallelize *across* the slowest file —
use resQ's native execution manifest and CI-level shards. File sharding is the
default. `-shard-unit test` assigns whole tests, while `case` independently
assigns declarative `shouldEach` rows; dynamic `.tst.parametrize`/`.tst.forall`
cases remain atomic with their parent.

**Example (GitHub Actions matrix):**

```yaml
strategy:
  matrix:
    shard: [0, 1, 2]
steps:
  - run: >-
      resq test tests -strict -isolate -json -junit
      -shard-unit test -shard-index ${{ matrix.shard }} -shard-count 3
      -outDir reports/${{ matrix.shard }}
  - uses: actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4
    with:
      name: test-results-${{ matrix.shard }}
      path: reports/${{ matrix.shard }}/
```

Once all artifacts are downloaded, merge the JSON contracts before publishing
the combined verdict:

```bash
bin/resq-merge reports/*/test-results.json --out-dir reports/merged
```

This provides cross-machine parallelism with no shared q state. The merger
fails closed for a missing index, provenance/configuration mismatch, duplicate
or missing execution, snapshot/benchmark ownership conflict, or partial
coverage artifact set. Valid aggregate and per-context coverage hits are summed
by stable identity. Snapshot completeness and unverified evidence are folded
from every required member rather than inferred from the merged entry union.
Empty shards are valid; fail-fast-incomplete shards are not.

See [CI.md](CI.md) for q runner licensing/prerequisites and the repository's
checked-in workflow.
