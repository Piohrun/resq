# Performance Testing in resQ

resQ now supports integrated performance testing and benchmarking, allowing you to enforce timing and memory constraints directly within your test suite.

## The `perf` Block

Use `perf` blocks to define dedicated benchmark tests. These tests run your code multiple times (default 10) and collect statistical data.

```q
.tst.desc["Algo Performance"]{

  / Run 500 times, ensure avg time < 10ms
  perf["Fast Lookup"; `maxTime`runs!10 500]{
    doMyLookup[]
  };

  / Ensure strict memory allocation limits
  perf["Memory Efficient"; `maxSpace!1000]{
    generateLargeList[]
  };

};
```

### Properties
- `runs`: Number of executions (three warmup runs are excluded). Default: 10.
- `maxTime`: Maximum allowed **average** execution time in milliseconds.
- `maxSpace`: Maximum allowed **average** memory allocation in bytes.
- `gc`: Run `.Q.gc[]` before every measured iteration. Default: `1b`; set
  `0b` when latency matters more than allocation repeatability.

**Note:** `perf` tests are **skipped by default**. Run with `-perf` to include them.
```bash
q resq.q test tests/ -perf
```

## Where the numbers go

Every `perf` block records its measurement, whether it passes or fails. Three
places surface it:

**Console** — a `PERFORMANCE` section after the summary:
```
PERFORMANCE (2 benchmarks):
  Algo perf: sort 1k  avg 0.2481ms (min 0.2210 / max 0.4120 / sd 0.0303) over 30 runs, 48 bytes  [limit 500.0000ms]
```

**JSON** (`-json`) — a top-level `performance` array, one object per
benchmark. In addition to the summary and budgets, each record has stable
`benchmarkId`/`testId`, repository-relative source identity, the exact workload,
all raw nanosecond/retained/heap-growth samples, environment fingerprint, and
an optional baseline comparison. The owning test row has the same identity,
samples and comparison in `benchmark`.

**In-process** — `.tst.app.perfResults`, a table with the same records.

Note that the `time` field on an ordinary test row is that test's own wall clock,
not a benchmark; the `performance` array is the measured data.

## Regression baselines and CI gates

Create a candidate report on a controlled worker, review it, then explicitly
replace the baseline. The updater is dry-run-only unless `--write` is present:

```bash
resq test tests/performance -perf -json -outDir artifacts/bench -exit
tools/update_benchmark_baseline.py artifacts/bench/test-results.json \
  --baseline benchmarks/baseline.json
tools/update_benchmark_baseline.py artifacts/bench/test-results.json \
  --baseline benchmarks/baseline.json --write
```

The updater refuses failed, filtered, rerun, and partial-shard reports. A
baseline uses the published
[`resq-benchmark-baseline-v1` schema](schema/resq-benchmark-baseline-v1.schema.json)
and retains raw samples, summaries, workload, source/test identities, VCS/run
provenance, and the environment fingerprint. Baselines do not update during a
test run.

Compare and optionally gate later runs:

```bash
resq test tests/performance -benchmark-baseline benchmarks/baseline.json \
  -benchmark-gate -json -outDir artifacts/bench -exit
```

Supplying a baseline or gate automatically includes `perf` blocks. Each
benchmark is classified as `improved`, `stable`, `inconclusive`, or `regressed`.
The gate fails only a `regressed` result, a missing/invalid baseline, a new
benchmark absent from the baseline, or a complete run that executes no
benchmarks. Workload mismatches and insufficient samples are inconclusive.
Environment mismatches are also inconclusive and non-gating; only the explicit
`-benchmark-accept-environment` flag permits their distributions to be compared.

The comparison is a two-sided, tie-corrected asymptotic Mann–Whitney U test with
a 0.5 continuity correction. resQ applies Holm–Bonferroni across all comparable
benchmarks, then requires a separate median change of at least 5% before calling
a statistically significant result improved/regressed. Defaults are alpha
`0.05`, practical effect `5%`, and five samples per side. Configure them with
`-benchmark-alpha`, `-benchmark-effect-min`, and `-benchmark-min-samples` (or
the corresponding JSON keys). The implementation is pinned against a SciPy
reference vector in `tests/test_perf.q`; raw samples make every decision
independently replayable.

For distributed runs, compare each native shard against the same baseline and
merge only a complete set with `tools/merge_shards.py`. The merger keys on
`benchmarkId`, preserves all samples, reapplies Holm correction over the global
union, and recomputes the gate. Individual multi-shard jobs mark the benchmark
gate `deferred` and do not fail locally from a partial multiple-comparison
denominator; the strict merged verdict is authoritative. A single shard is
never accepted by the baseline updater.

## Inline Assertions

You can also assert performance within standard `should` blocks using infix assertions.

### `mustBeFasterThan`
Asserts that the average execution time of a code block is less than the limit (in ms).
```q
should["be fast"]{
  { doComplexCalc[] } mustBeFasterThan 50; / 50ms limit
};
```

### `mustAllocLessThan`
Asserts that the average **retained** memory growth is less than the limit (in
bytes) — see [What the memory numbers mean](#what-the-memory-numbers-mean).
```q
should["be lean"]{
  { generateData[] } mustAllocLessThan 4096; / 4KB limit
};
```

## What the memory numbers mean

q exposes no total-allocated counter, so "allocation" has to be read carefully.
resQ records two different signals from `.Q.w[]`:

| Key | Is | Blind to |
|-----|-----|---------|
| `space` | **retained** bytes: `used` after minus before — memory the code did not give back | anything allocated *and released* during the call. A 160MB temporary vector measures ~192 bytes |
| `heapGrowth` | growth of q's **heap**, which does catch a large transient | anything below q's allocation block (64MB on x86_64), where it reads 0 — and it over-states what it does catch, since it rounds up to whole blocks |

`mustAllocLessThan` and `spaceLimitBytes` budget on `space`, so they answer *"did
this leak?"* rather than *"how much did this churn?"*. Watch `heapGrowth` for the
second question. Neither is floored below zero: code that nets a *free* reports 0,
not a spurious positive.

## Which API to use

Two entry points, one measurement core (`.tst.benchmark.sample`) — they differ
in what they give you back, not in how they measure:

| Want | Use | Gives you |
|------|-----|-----------|
| Fail the build on a budget | `perf` block, `mustBeFasterThan`, `mustAllocLessThan` | pass/fail + the recorded measurement |
| Time and **memory** statistics | `.tst.benchmark.measureOpts[n; code; opts]` | `` `time`space`heapGrowth `` stats plus raw `samples` and exact `workload` |
| Percentiles and a distribution | `.tst.bench[func; opts]` | iterations, min/max/avg/std, p50–p99, histogram, raw timings |

`bench` does not record allocation: the `.Q.w[]` calls needed for it would show
up in its own timings. Use `measureOpts` when you need memory.

## Low-Level Benchmarking

For ad-hoc profiling, access the underlying library directly:

```q
res: .tst.benchmark.measure[100; { myFunc[] }];
/ returns dictionary with `time, `space (retained) and `heapGrowth stats
/ (min/med/max/avg/dev); see "What the memory numbers mean" above

.tst.benchmark.hist[res`time; 10]; / Print ASCII histogram of timing
```
