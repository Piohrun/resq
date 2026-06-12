
/ lib/benchmark.q - Performance profiling and diagnostics

.tst.benchmark.stats:{[data]
  `min`med`max`avg`dev!(min data; med data; max data; avg data; dev data)
 }

/ measureOpts: parametrized measurement. opts is a dict that may carry:
/   gc (boolean) - if 1b (default), .Q.gc[] before every iteration for clean
/                  space readings (slower); if 0b, skip per-iteration gc.
/ Timings are FLOAT milliseconds with nanosecond precision (no `long$ floor,
/ so sub-millisecond code no longer measures 0).
.tst.benchmark.measureOpts:{[n;code;opts]
  o: (enlist[`gc]!enlist 1b), $[99h=type opts; opts; ()!()];
  doGc: o`gc;
  do[3; .Q.gc[]; value code];
  r: {[gc;x]
    if[gc; .Q.gc[]];
    s1: .Q.w[]`used;
    t1: .z.p;
    value x;
    t2: .z.p;
    s2: .Q.w[]`used;
    ((t2-t1)%1000000; abs s2-s1)
  }[doGc] each n # enlist code;
  times: first each r;
  space: last each r;
  `time`space!(.tst.benchmark.stats times; .tst.benchmark.stats space)
 }

/ Backward-compatible wrapper: gc on by default. Public API unchanged.
.tst.benchmark.measure:{[n;code]
  .tst.benchmark.measureOpts[n; code; enlist[`gc]!enlist 1b]
 }

.tst.benchmark.hist:{[data;buckets]
  if[not count data; :()];
  minV: min data;
  maxV: max data;
  if[minV = maxV; buckets: 1];
  width: (maxV - minV) % buckets;
  if[width=0; width:1];
  lbls: minV + width * til buckets;
  cnts: {[d;l;w] sum d within (l; l+w) }[data;;width] each lbls;
  maxC: max cnts;
  scale: $[maxC=0; 1; 40 % maxC];
  -1 "Dist:";
  { [l;c;s]
    bar: (floor c * s) # "*";
    if[c=0; bar: ""];
    -1 (.Q.f[2;l]), " | ", bar, " ", string c;
  } ./: flip (lbls;cnts;scale);
 }
