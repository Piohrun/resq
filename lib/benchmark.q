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
  if[not (type n) in -5 -6 -7h; '"benchmark iterations must be a positive integer"];
  if[(null n) or n <= 0; '"benchmark iterations must be a positive integer"];
  o: (`warmup`gcBefore`gcEach`space!(3; 1b; 1b; 1b)), $[99h=type opts; opts; ()!()];
  if[0 < o`warmup; do[o`warmup; .tst.benchmark.invoke code]];
  if[o`gcBefore; .Q.gc[]];
  / Two DIFFERENT memory signals, because q exposes no total-allocated counter
  / and neither one alone is "bytes allocated":
  /   used delta -> bytes still held after the call (RETAINED). Blind to anything
  /                 the call allocated and released: a 160MB temporary vector
  /                 measures as ~160 bytes here.
  /   heap delta -> growth of q's heap, which captures a large TRANSIENT, but is
  /                 quantized to q's allocation blocks (64MB on x86_64), so it
  /                 reads 0 for anything smaller and over-states what it catches.
  / `space` stays the retained figure (the budget metric mustAllocLessThan uses);
  / `heapGrowth` is reported alongside so a big transient is not invisible.
  / Both are floored at 0 rather than abs'd -- the old `abs s2-s1` reported code
  / that NET FREED memory as though it had allocated that much.
  r: {[gcEach; wantSpace; x]
    if[gcEach; .Q.gc[]];
    w1: $[wantSpace; .Q.w[]; `used`heap!0 0];
    t1: .z.p;
    .tst.benchmark.invoke x;
    t2: .z.p;
    w2: $[wantSpace; .Q.w[]; `used`heap!0 0];
    ("j"$t2-t1; 0 | w2[`used]-w1`used; 0 | w2[`heap]-w1`heap)
  }[o`gcEach; o`space] each n # enlist code;
  `timesNs`space`heapGrowth!(r[;0]; r[;1]; r[;2])
 }

.tst.benchmark.measureOpts:{[n;code;opts]
  o: (enlist[`gc]!enlist 1b), $[99h=type opts; opts; ()!()];
  workload:`runs`warmup`gcBefore`gcEach`space!("j"$n;3j;1b;o`gc;1b);
  smp: .tst.benchmark.sample[n; code;
        `warmup`gcBefore`gcEach`space!(workload`warmup;workload`gcBefore;
          workload`gcEach;workload`space)];
  / Timings are FLOAT milliseconds with nanosecond precision (no `long$ floor,
  / so sub-millisecond code does not measure 0).
  samples:`timeNs`retainedBytes`heapGrowthBytes!(
      "j"$smp`timesNs;"j"$smp`space;"j"$smp`heapGrowth);
  `time`space`heapGrowth`samples`workload!(
      .tst.benchmark.stats (`float$smp`timesNs) % 1000000;
      .tst.benchmark.stats smp`space;
      .tst.benchmark.stats smp`heapGrowth;
      samples;workload)
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
