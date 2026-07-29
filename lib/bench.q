\d .tst

/ ============================================================================
/ Benchmarking Library for resQ
/ Provides precise performance measurement with statistical analysis
/ ============================================================================

/ Default configuration
benchDefaults:`iterations`warmup`gcBefore!(1000;100;1b);

.tst.benchmark.MAX_NAME_LENGTH:256;
.tst.benchmark.MAX_FINITE_RATIO:1.7976931348623157e308;

.tst.benchmark.validateBenchOptions:{[opts]
  allowed:`iterations`warmup`gcBefore;
  .tst.benchmark.validateOptions[
    .tst.benchDefaults;allowed;"benchmark defaults"];
  opts:.tst.benchmark.validateOptions[opts;allowed;"benchmark"];
  cfg:.tst.benchDefaults,opts;
  cfg[`iterations]:.tst.benchmark.validateCount[
    cfg`iterations;
    "benchmark iterations";
    1;
    .tst.benchmark.MAX_ITERATIONS];
  cfg[`warmup]:.tst.benchmark.validateCount[
    cfg`warmup;
    "benchmark warmup";
    0;
    .tst.benchmark.MAX_WARMUP];
  cfg[`gcBefore]:.tst.benchmark.validateBool[
    cfg`gcBefore;"benchmark gcBefore"];
  cfg
 };

.tst.benchmark.validateName:{[name;label]
  if[not type[name] in -11 10h;
    .tst.benchmark.fail[label," must be a string or symbol scalar"]];
  printable:$[-11h=type name;string name;name];
  if[not count printable;
    .tst.benchmark.fail[label," must not be empty"]];
  if[count[printable]>.tst.benchmark.MAX_NAME_LENGTH;
    .tst.benchmark.fail[
      label," exceeds safety limit ",
      string .tst.benchmark.MAX_NAME_LENGTH]];
  controls:"c"$((til 32),127);
  if[any printable in controls;
    .tst.benchmark.fail[label," must not contain control characters"]];
  name
 };

.tst.benchmark.displayName:{[name]
  $[-11h=type name;string name;name]
 };

.tst.benchmark.fixedWidth:{[text;width]
  padded:text,width#" ";
  width#padded
 };

/ Generate a histogram with N exact-once bins.
benchHistogram:{[data;nbins]
  .tst.benchmark.histogram[data;nbins]
 };

.tst.benchmark.validateHistogramTable:{[hist]
  if[not 98h=type hist;
    .tst.benchmark.fail["histogram output must be a table"]];
  required:`bucket`range_start`range_end`cnt`pct;
  if[not all required in cols hist;
    .tst.benchmark.fail[
      "histogram output must contain bucket, range_start, range_end, cnt, and pct"]];
  if[not count hist;
    .tst.benchmark.fail["histogram output must not be empty"]];
  .tst.benchmark.validateSeries[hist`bucket;"histogram buckets"];
  .tst.benchmark.validateSeries[hist`range_start;"histogram range_start"];
  .tst.benchmark.validateSeries[hist`range_end;"histogram range_end"];
  .tst.benchmark.validateSeries[hist`cnt;"histogram counts"];
  .tst.benchmark.validateSeries[hist`pct;"histogram percentages"];
  if[not type[hist`bucket] in 4 5 6 7h;
    .tst.benchmark.fail["histogram buckets must be integer values"]];
  if[not type[hist`cnt] in 4 5 6 7h;
    .tst.benchmark.fail["histogram counts must be integer values"]];
  if[not type[hist`pct] in 4 5 6 7 8 9h;
    .tst.benchmark.fail["histogram percentages must be numeric values"]];
  if[type[hist`range_start]<>type hist`range_end;
    .tst.benchmark.fail["histogram range columns must have the same type"]];
  if[any hist`bucket<0;
    .tst.benchmark.fail["histogram buckets must be non-negative"]];
  if[any hist`cnt<0;
    .tst.benchmark.fail["histogram counts must be non-negative"]];
  if[any hist`range_end<hist`range_start;
    .tst.benchmark.fail["histogram ranges must not descend"]];
  if[any (hist`pct<0) or hist`pct>100;
    .tst.benchmark.fail["histogram percentages must be between 0 and 100"]];
  hist
 };

/ Print histogram as ASCII bar chart.
benchPrintHistogram:{[hist]
  hist:.tst.benchmark.validateHistogramTable hist;
  maxPct:max hist`pct;
  if[0=maxPct;maxPct:1f];
  barWidth:30;
  {[row;maximum;width]
    pctValue:row`pct;
    barLength:"j"$floor (pctValue*width)%maximum;
    barLength:0|barLength;
    barLength:width&barLength;
    bar:barLength#"#";
    startUs:("f"$row`range_start)%1000;
    endUs:("f"$row`range_end)%1000;
    label:(string "j"$startUs)," - ",(string "j"$endUs)," us";
    -1 "  ",.tst.benchmark.fixedWidth[label;24],
      " |",bar," ",string["j"$pctValue],"%";
  }[;maxPct;barWidth] each hist;
  ()
 };

/ Print formatted benchmark results.
benchPrint:{[stats]
  -1 "";
  -1 "=== Benchmark Results ===";
  -1 "Iterations: ",string stats`iterations;
  -1 "Timing: Min=",(string `int$stats`min_us),"us Avg=",
    (string `int$stats`avg_us),"us Max=",
    (string `int$stats`max_us),"us";
  -1 "Percentiles: p50=",(string `int$stats`p50_us),
    "us p99=",(string `int$stats`p99_us),"us";
  if[not ()~stats`histogram;
    -1 "Distribution (us):";
    benchPrintHistogram stats`histogram];
  -1 "";
 };

/ Preserve the historical percentile rule: floor(p*n), then explicitly clamp
/ to [0,n-1]. This selects the upper middle item for even n and is stable at n=1.
.tst.benchmark.percentileIndex:{[percentile;n]
  index:"j"$floor percentile*n;
  index:0|index;
  (n-1)&index
 };

.tst.benchmark.runBench:{[func;cfg]
  warmup:cfg`warmup;
  do[warmup;
    .tst.benchmark.call[func;"benchmark warmup"]];
  if[cfg`gcBefore;.Q.gc[]];
  n:cfg`iterations;
  times:n#0D00:00:00.000000000;
  idx:0;
  do[n;
    start:.tst.benchmark.now[];
    .tst.benchmark.call[func;"benchmark iteration"];
    elapsed:.tst.benchmark.now[]-start;
    .tst.benchmark.validateFiniteNonnegative[
      elapsed;"benchmark elapsed time"];
    times[idx]:elapsed;
    idx+:1];

  deviation:$[1=n;0f;dev times];
  result:`iterations`total_ns`min_ns`max_ns`avg_ns`std_ns!
    (n;sum times;min times;max times;avg times;deviation);
  .tst.benchmark.validateFiniteNonnegative[;"benchmark statistics"] each
    value result;

  / Convert spans to float us/ms for easier use.
  result[`total_us]:("f"$result`total_ns)%1000;
  result[`min_us]:("f"$result`min_ns)%1000;
  result[`max_us]:("f"$result`max_ns)%1000;
  result[`avg_us]:("f"$result`avg_ns)%1000;
  result[`std_us]:("f"$result`std_ns)%1000;
  .tst.benchmark.validateFiniteNonnegativeNumeric[
    ;"benchmark converted statistics"] each
    result `total_us`min_us`max_us`avg_us`std_us;

  sorted:asc times;
  result[`p50_ns]:sorted .tst.benchmark.percentileIndex[0.50;n];
  result[`p90_ns]:sorted .tst.benchmark.percentileIndex[0.90;n];
  result[`p95_ns]:sorted .tst.benchmark.percentileIndex[0.95;n];
  result[`p99_ns]:sorted .tst.benchmark.percentileIndex[0.99;n];
  .tst.benchmark.validateFiniteNonnegative[;"benchmark percentiles"] each
    result `p50_ns`p90_ns`p95_ns`p99_ns;
  result[`p50_us]:("f"$result`p50_ns)%1000;
  result[`p90_us]:("f"$result`p90_ns)%1000;
  result[`p95_us]:("f"$result`p95_ns)%1000;
  result[`p99_us]:("f"$result`p99_ns)%1000;
  .tst.benchmark.validateFiniteNonnegativeNumeric[
    ;"benchmark converted percentiles"] each
    result `p50_us`p90_us`p95_us`p99_us;
  result[`histogram]:benchHistogram[times;10];
  result[`raw_ns]:times;
  result
 };

/ Run a zero-argument callable N times and collect timing data.
bench:{[func;opts]
  func:.tst.benchmark.validateCallable[func;"benchmark function"];
  cfg:.tst.benchmark.validateBenchOptions opts;
  .tst.benchmark.runBench[func;cfg]
 };

/ Assertion: function average time must be under a finite threshold.
mustbench:{[func;thresholdUs;opts]
  thresholdUs:.tst.benchmark.validateFiniteNonnegativeNumeric[
    thresholdUs;"benchmark threshold"];
  func:.tst.benchmark.validateCallable[func;"benchmark function"];
  cfg:.tst.benchmark.validateBenchOptions opts;
  stats:.tst.benchmark.runBench[func;cfg];
  if[stats[`avg_us]>thresholdUs;
    '"Benchmark failed: avg above threshold: ",string stats`avg_us];
  stats
 };

/ Compare two implementations. `ratio` retains stats1/stats2 semantics. When
/ stats2 is exactly zero, it saturates at a finite maximum instead of producing
/ infinity. A tie deterministically selects name1. Winner preserves the selected
/ input type, avoiding unbounded symbol interning for string names.
benchCompare:{[name1;func1;name2;func2;opts]
  name1:.tst.benchmark.validateName[name1;"first benchmark name"];
  name2:.tst.benchmark.validateName[name2;"second benchmark name"];
  if[type[name1]<>type name2;
    .tst.benchmark.fail[
      "benchmark names must both be strings or both be symbols"]];
  func1:.tst.benchmark.validateCallable[func1;"first benchmark function"];
  func2:.tst.benchmark.validateCallable[func2;"second benchmark function"];
  cfg:.tst.benchmark.validateBenchOptions opts;
  display1:.tst.benchmark.displayName name1;
  display2:.tst.benchmark.displayName name2;
  -1 "Comparing: ",display1," vs ",display2;
  stats1:.tst.benchmark.runBench[func1;cfg];
  stats2:.tst.benchmark.runBench[func2;cfg];
  avg1:"f"$.tst.benchmark.validateFiniteNonnegativeNumeric[
    stats1`avg_us;"first benchmark average"];
  avg2:"f"$.tst.benchmark.validateFiniteNonnegativeNumeric[
    stats2`avg_us;"second benchmark average"];
  -1 display1,": Avg=",string[avg1],"us";
  -1 display2,": Avg=",string[avg2],"us";

  zero1:.tst.benchmark.isZeroScalar avg1;
  zero2:.tst.benchmark.isZeroScalar avg2;
  tie:avg1~avg2;
  winner:$[tie or avg1<avg2;name1;name2];
  winnerDisplay:.tst.benchmark.displayName winner;
  ratio:$[tie;1f;
    zero1;0f;
    zero2;.tst.benchmark.MAX_FINITE_RATIO;
    avg1%avg2];
  if[not .tst.benchmark.isFiniteScalar ratio;
    ratio:.tst.benchmark.MAX_FINITE_RATIO];
  .tst.benchmark.validateComputed[ratio;"benchmark comparison ratio"];
  if[tie;
    -1 "Tie: ",display1," selected deterministically"];
  if[not tie;
    zeroCase:zero1 or zero2;
    if[zeroCase;
      -1 "Winner: ",winnerDisplay," (zero-time baseline)"];
    if[not zeroCase;
      speedup:$[ratio>1f;ratio;
        .tst.benchmark.isZeroScalar ratio;
          .tst.benchmark.MAX_FINITE_RATIO;
        1f%ratio];
      if[not .tst.benchmark.isFiniteScalar speedup;
        speedup:.tst.benchmark.MAX_FINITE_RATIO];
      .tst.benchmark.validateComputed[speedup;"benchmark comparison speedup"];
      -1 "Winner: ",winnerDisplay," (",string[speedup],"x faster)"]];
  `stats1`stats2`ratio`winner!(stats1;stats2;ratio;winner)
 };

\d .
