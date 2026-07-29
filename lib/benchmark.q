/ benchmark.q - performance profiling and diagnostics (timing, allocation, histograms)

/ Private safety budgets. They are globals so focused tests can temporarily
/ lower them without asking the benchmark code to perform hostile-sized work.
.tst.benchmark.MAX_ITERATIONS:1000000;
.tst.benchmark.MAX_WARMUP:100000;
.tst.benchmark.MAX_BUCKETS:10000;
.tst.benchmark.MAX_DATA_POINTS:1000000;
.tst.benchmark.MAX_OPTION_KEYS:32;
.tst.benchmark.MAX_OPTION_KEY_DISPLAY:64;
.tst.benchmark.MEASURE_WARMUP:3;

.tst.benchmark.fail:{[detail]
  '"Benchmark ",detail
 };

/ Integer loop counts must be finite scalar integers inside the relevant
/ private safety budget. Returns a long for `do`/allocation consistency.
.tst.benchmark.validateCount:{[x;label;minimum;cap]
  if[not type[x] in -4 -5 -6 -7h;
    .tst.benchmark.fail[label," must be a finite integer scalar"]];
  if[null x;
    .tst.benchmark.fail[label," must be a finite integer scalar"]];
  if[x in (0Wh;-0Wh;0Wi;-0Wi;0W;-0W);
    .tst.benchmark.fail[label," must be finite"]];
  if[x<minimum;
    .tst.benchmark.fail[label," must be at least ",string minimum]];
  if[x>cap;
    .tst.benchmark.fail[label," exceeds safety limit ",string cap]];
  "j"$x
 };

.tst.benchmark.validateOptions:{[opts;allowed;label]
  if[not 99h=type opts;
    .tst.benchmark.fail[label," options must be a dictionary"]];
  ks:key opts;
  if[count ks;
    if[count[ks]>.tst.benchmark.MAX_OPTION_KEYS;
      .tst.benchmark.fail[
        label," options exceed key-count safety limit ",
        string .tst.benchmark.MAX_OPTION_KEYS]];
    if[not 11h=type ks;
      .tst.benchmark.fail[label," option keys must be symbols"]];
    if[count[ks]<>count distinct ks;
      .tst.benchmark.fail[label," options must not contain duplicate keys"]];
    unknown:ks except allowed;
    if[count unknown;
      keyText:.tst.benchmark.boundedText[
        string first unknown;
        .tst.benchmark.MAX_OPTION_KEY_DISPLAY];
      .tst.benchmark.fail[
        label," options contain unknown key '",keyText,"'"]]
  ];
  opts
 };

.tst.benchmark.boundedText:{[text;limit]
  if[count[text]<=limit; :text];
  (limit#text),"..."
 };

.tst.benchmark.validateBool:{[x;label]
  if[not -1h=type x;
    .tst.benchmark.fail[label," must be a boolean scalar"]];
  x
 };

.tst.benchmark.isCallable:{[x]
  type[x] in 100 104h
 };

/ resQ's perf expectation runner historically passes the narrow parse-tree
/ form (function;::). Retain that internal compatibility while requiring all
/ public direct values to be genuine callables.
.tst.benchmark.isInvocation:{[x]
  if[not 0h=type x; :0b];
  if[not 2=count x; :0b];
  (.tst.benchmark.isCallable first x) and (::)~last x
 };

.tst.benchmark.validateCallable:{[x;label]
  if[not (.tst.benchmark.isCallable[x] or .tst.benchmark.isInvocation x);
    .tst.benchmark.fail[label," must be a callable function"]];
  x
 };

.tst.benchmark.invoke:{[code]
  $[.tst.benchmark.isCallable code; code[]; value code]
 };

.tst.benchmark.now:{[] .z.p};

/ Invoke user code with phase context while preserving its original error text.
.tst.benchmark.call:{[code;phase]
  @[.tst.benchmark.invoke;code;
    {[p;e] .tst.benchmark.fail[p," failed: ",e]}[phase;]]
 };

.tst.benchmark.isFiniteScalar:{[x]
  if[not type[x] in -4 -5 -6 -7 -8 -9 -16h; :0b];
  if[null x; :0b];
  not x in
    (0Wh;-0Wh;0Wi;-0Wi;0W;-0W;0We;-0We;0w;-0w;0Wn;-0Wn)
 };

.tst.benchmark.isNegativeScalar:{[x]
  not (-8!x)~-8!abs x
 };

.tst.benchmark.isZeroScalar:{[x]
  zero:x-x;
  (-8!x)~-8!zero
 };

.tst.benchmark.validateFiniteNonnegative:{[x;label]
  if[not .tst.benchmark.isFiniteScalar x;
    .tst.benchmark.fail[
      label," must be a finite non-negative numeric or timespan scalar"]];
  if[.tst.benchmark.isNegativeScalar x;
    .tst.benchmark.fail[
      label," must be a finite non-negative numeric or timespan scalar"]];
  x
 };

.tst.benchmark.validateFiniteNonnegativeNumeric:{[x;label]
  if[not type[x] in -4 -5 -6 -7 -8 -9h;
    .tst.benchmark.fail[label," must be a finite non-negative numeric scalar"]];
  if[not .tst.benchmark.isFiniteScalar x;
    .tst.benchmark.fail[label," must be a finite non-negative numeric scalar"]];
  if[.tst.benchmark.isNegativeScalar x;
    .tst.benchmark.fail[label," must be a finite non-negative numeric scalar"]];
  x
 };

/ Histograms and statistics require a non-empty, homogeneous numeric vector.
/ Timespans are accepted because `.tst.bench` exposes raw nanosecond spans.
.tst.benchmark.validateSeries:{[data;label]
  if[not count data;
    .tst.benchmark.fail[label," must not be empty"]];
  if[not type[data] in 4 5 6 7 8 9 16h;
    .tst.benchmark.fail[
      label," must be a homogeneous numeric or timespan vector"]];
  if[count[data]>.tst.benchmark.MAX_DATA_POINTS;
    .tst.benchmark.fail[
      label," exceeds safety limit ",
      string .tst.benchmark.MAX_DATA_POINTS]];
  if[not all .tst.benchmark.isFiniteScalar each data;
    .tst.benchmark.fail[label," must contain only finite values"]];
  data
 };

.tst.benchmark.validateComputed:{[x;label]
  if[not .tst.benchmark.isFiniteScalar x;
    .tst.benchmark.fail[label," produced a non-finite value"]];
  x
 };

.tst.benchmark.stats:{[data]
  data:.tst.benchmark.validateSeries[data;"statistics data"];
  deviation:$[1=count data;0f;dev data];
  result:`min`med`max`avg`dev!
    (min data;med data;max data;avg data;deviation);
  .tst.benchmark.validateComputed[; "statistics"] each value result;
  result
 };

/ Build half-open bins, except that the final bin includes the maximum.
/ Index clamping absorbs floating-point rounding at the upper boundary.
.tst.benchmark.histogram:{[data;buckets]
  buckets:.tst.benchmark.validateCount[
    buckets;"histogram bucket count";1;.tst.benchmark.MAX_BUCKETS];
  data:.tst.benchmark.validateSeries[data;"histogram data"];
  inputMin:min data;
  inputMax:max data;
  constant:inputMin~inputMax;
  if[constant;
    :([] bucket:enlist 0;
        range_start:enlist inputMin;
        range_end:enlist inputMax;
        cnt:enlist count data;
        pct:enlist 100f)];
  / Normalize integer and span vectors before subtraction. Non-constant range
  / columns were already floats in q because `%buckets` produces a float; doing
  / the cast first also prevents finite extreme integers wrapping on subtraction.
  values:$[type[data] in 4 5 6 7 16h;"f"$data;data];
  minV:min values;
  maxV:max values;
  range:maxV-minV;
  .tst.benchmark.validateComputed[range;"histogram range"];
  width:range%buckets;
  .tst.benchmark.validateComputed[width;"histogram bucket width"];
  if[(.tst.benchmark.isNegativeScalar width) or
     .tst.benchmark.isZeroScalar width;
    .tst.benchmark.fail["histogram bucket width must be positive"]];
  relative:(values-minV)%width;
  if[not all .tst.benchmark.isFiniteScalar each relative;
    .tst.benchmark.fail["histogram bin calculation was non-finite"]];
  bins:"j"$floor relative;
  bins:0|bins;
  bins:(buckets-1)&bins;
  counts:@[buckets#0;bins;+;1];
  if[count[values]<>sum counts;
    .tst.benchmark.fail["histogram did not conserve input count"]];
  starts:minV+width*til buckets;
  ends:starts+width;
  ends[buckets-1]:maxV;
  ([] bucket:til buckets;
      range_start:starts;
      range_end:ends;
      cnt:counts;
      pct:100f*counts%count values)
 };

/ measureOpts: parametrized measurement. opts is a dict carrying only:
/   gc (boolean) - if 1b (default), .Q.gc[] before warmup/measurement calls.
/ Timings are FLOAT milliseconds with nanosecond precision.
.tst.benchmark.measureOpts:{[n;code;opts]
  n:.tst.benchmark.validateCount[
    n;"measurement iterations";1;.tst.benchmark.MAX_ITERATIONS];
  code:.tst.benchmark.validateCallable[code;"measurement code"];
  opts:.tst.benchmark.validateOptions[opts;enlist `gc;"measurement"];
  doGc:.tst.benchmark.validateBool[
    $[`gc in key opts;opts`gc;1b];"measurement gc"];
  warmup:.tst.benchmark.validateCount[
    .tst.benchmark.MEASURE_WARMUP;
    "measurement warmup";0;.tst.benchmark.MAX_WARMUP];
  do[warmup;
    if[doGc;.Q.gc[]];
    .tst.benchmark.call[code;"measurement warmup"]];
  times:n#0f;
  space:n#0j;
  idx:0;
  do[n;
    if[doGc;.Q.gc[]];
    s1:.Q.w[]`used;
    t1:.tst.benchmark.now[];
    .tst.benchmark.call[code;"measurement iteration"];
    elapsed:(.tst.benchmark.now[]-t1)%1000000;
    s2:.Q.w[]`used;
    .tst.benchmark.validateFiniteNonnegative[
      elapsed;"measurement elapsed time"];
    times[idx]:elapsed;
    space[idx]:abs s2-s1;
    idx+:1];
  `time`space!
    (.tst.benchmark.stats times;.tst.benchmark.stats space)
 };

/ Backward-compatible wrapper: gc on by default.
.tst.benchmark.measure:{[n;code]
  .tst.benchmark.measureOpts[n;code;enlist[`gc]!enlist 1b]
 };

/ Print a validated exact-once histogram. Returns generic null after output.
.tst.benchmark.hist:{[data;buckets]
  hist:.tst.benchmark.histogram[data;buckets];
  maxC:max hist`cnt;
  scale:$[0=maxC;1f;40f%maxC];
  -1 "Dist:";
  {[row;s]
    label:string row`range_start;
    countValue:row`cnt;
    bar:(floor countValue*s)#"*";
    -1 label," | ",bar," ",string countValue;
  }[;scale] each hist;
  ()
 };
