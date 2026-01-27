
/ lib/benchmark.q - Performance profiling and diagnostics

.tst.benchmark.stats:{[data]
  `min`med`max`avg`dev!(min data; med data; max data; avg data; dev data)
 }

.tst.benchmark.measure:{[n;code]
  do[3; .Q.gc[]; value code];
  r: {
    .Q.gc[]; 
    s1: .Q.w[]`used;
    t1: .z.p;
    value x;
    t2: .z.p;
    s2: .Q.w[]`used;
    (`long$(t2-t1)%1000000; abs s2-s1)
  } each n # enlist code;
  times: first each r;
  space: last each r;
  `time`space!(.tst.benchmark.stats times; .tst.benchmark.stats space)
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
    bar: (floor c * s) # "∎";
    if[c=0; bar: ""];
    -1 (.Q.f[2;l]), " | ", bar, " ", string c;
  } ./: flip (lbls;cnts;scale);
 }
