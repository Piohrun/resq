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
q resq.q -test tests/ -perf
```

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
Asserts that the average memory allocation is less than the limit (in bytes).
```q
should["be lean"]{
  { generateData[] } mustAllocLessThan 4096; / 4KB limit
};
```

## Low-Level Benchmarking

For ad-hoc profiling, access the underlying library directly:

```q
res: .tst.benchmark.measure[100; { myFunc[] }];
/ returns dictionary with `time and `space stats (min/med/max/avg/dev)

.tst.benchmark.hist[res`time; 10]; / Print ASCII histogram of timing
```
