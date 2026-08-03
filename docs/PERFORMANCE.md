# Performance Testing in resQ

resQ now supports integrated performance testing and benchmarking, allowing you to enforce timing and memory constraints directly within your test suite.

## The `perf` Block

Use `perf` blocks to define dedicated benchmark tests. These tests run your code multiple times (default 100) and collect statistical data.

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
- `runs`: Number of executions (warmup runs are excluded). Default: 100.
- `maxTime`: Maximum allowed **average** execution time in milliseconds.
- `maxSpace`: Maximum allowed **average** memory allocation in bytes.
- `gc`: Not currently exposed in the `perf` block (garbage collection is handled internally by the benchmark runner).

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

**JSON** (`-json`) — a `performance` array alongside `tests`, one object per
benchmark with `suite`, `description`, `runs`, `avgTimeMs`, `minTimeMs`,
`maxTimeMs`, `devTimeMs`, `avgSpaceBytes`, `maxSpaceBytes`, and the declared
`timeLimitMs` / `spaceLimitBytes` (null when no budget was set). This is the
format to feed a dashboard if you want to chart a function's latency across
releases.

**In-process** — `.tst.app.perfResults`, a table with the same columns.

Note that the `time` field on an ordinary test row is that test's own wall clock,
not a benchmark; the `performance` array is the measured data.

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
| Time and **memory** statistics | `.tst.benchmark.measureOpts[n; code; opts]` | `` `time`space`heapGrowth `` each with min/med/max/avg/dev |
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
