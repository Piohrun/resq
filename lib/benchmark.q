/ benchmark.q - performance profiling and diagnostics (timing, allocation, histograms)

.tst.benchmark.stats:{[data]
  `min`med`max`avg`dev!(min data; med data; max data; avg data; dev data)
 }

/ measureOpts: parametrized measurement. opts is a dict that may carry:
/   gc (boolean) - if 1b (default), .Q.gc[] before every iteration for clean
/                  space readings (slower); if 0b, skip per-iteration gc.
/ Timings are FLOAT milliseconds with nanosecond precision (no `long$ floor,
/ so sub-millisecond code no longer measures 0).
/ Run the subject once. `value` on a LAMBDA returns its internals WITHOUT
/ executing it, so measuring `value code` timed q's introspection rather than
/ the user's code: a perf block ran zero times and reported ~200ns regardless of
/ what it contained. A function must be CALLED; only a string of q source is
/ evaluated with `value`.
.tst.benchmark.invoke:{[c]
  $[(type c) within 100 104h; c[]; value c]
 }

/ ---------------------------------------------------------------------------
/ The single measurement core. Everything that times code -- perf blocks,
/ mustBeFasterThan, mustAllocLessThan, and the bench/mustbench/benchCompare
/ API -- goes through here. There used to be two independent timing loops
/ (this one and bench.q's), which could drift apart and did differ in whether
/ they executed the subject at all.
/ opts: warmup   (int)  iterations to run before measuring        [3]
/       gcBefore (bool) .Q.gc[] once before the measured loop     [1b]
/       gcEach   (bool) .Q.gc[] before EVERY iteration -- needed  [1b]
/                       for clean allocation readings, and slow
/       space    (bool) record allocation as well as time         [1b]
/ Returns raw vectors: `timesNs`space, so each caller derives its own
/ statistics rather than re-measuring.
/ ---------------------------------------------------------------------------
.tst.benchmark.sample:{[n;code;opts]
  o: (`warmup`gcBefore`gcEach`space!(3; 1b; 1b; 1b)), $[99h=type opts; opts; ()!()];
  if[0 < o`warmup; do[o`warmup; .tst.benchmark.invoke code]];
  if[o`gcBefore; .Q.gc[]];
  r: {[gcEach; wantSpace; x]
    if[gcEach; .Q.gc[]];
    s1: $[wantSpace; .Q.w[]`used; 0];
    t1: .z.p;
    .tst.benchmark.invoke x;
    t2: .z.p;
    s2: $[wantSpace; .Q.w[]`used; 0];
    ("j"$t2-t1; abs s2-s1)
  }[o`gcEach; o`space] each n # enlist code;
  `timesNs`space!(first each r; last each r)
 }

.tst.benchmark.measureOpts:{[n;code;opts]
  o: (enlist[`gc]!enlist 1b), $[99h=type opts; opts; ()!()];
  smp: .tst.benchmark.sample[n; code;
        `warmup`gcBefore`gcEach`space!(3; 1b; o`gc; 1b)];
  / Timings are FLOAT milliseconds with nanosecond precision (no `long$ floor,
  / so sub-millisecond code does not measure 0).
  `time`space!(.tst.benchmark.stats (`float$smp`timesNs) % 1000000;
               .tst.benchmark.stats smp`space)
 }

/ Backward-compatible wrapper: gc on by default. Public API unchanged.
.tst.benchmark.measure:{[n;code]
  .tst.benchmark.measureOpts[n; code; enlist[`gc]!enlist 1b]
 }

/ Histogram. bench.q owns the implementation -- benchHistogram builds the table,
/ benchPrintHistogram renders it -- and this delegates rather than carrying a
/ second bucketing routine. Kept as a named entry point because it is the
/ .tst.benchmark.* surface; it prints, as it always did.
/ bench.q loads after this file, so resolve the helpers at CALL time.
.tst.benchmark.hist:{[data;buckets]
  if[not count data; :()];
  if[not all `benchHistogram`benchPrintHistogram in key `.tst;
    :()];
  -1 "Dist:";
  .tst.benchPrintHistogram .tst.benchHistogram[data; buckets];
 }
