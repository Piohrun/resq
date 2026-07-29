\d .tst

/ ============================================================================
/ Benchmarking Library for resQ
/ Provides precise performance measurement with statistical analysis
/ ============================================================================

/ Default configuration
benchDefaults:`iterations`warmup`gcBefore!(1000;100;1b);

.tst.benchmark.MAX_NAME_LENGTH:256;
.tst.benchmark.MAX_FINITE_RATIO:1000000000000f;

.tst.benchmark.nameLimit:{[]
  .tst.benchmark.limit[
    `.tst.benchmark.MAX_NAME_LENGTH;
    "benchmark name length";
    1;
    256]
 };

.tst.benchmark.ratioLimit:{[]
  outcome:@[
    .tst.benchmark.captureLimit;
    `.tst.benchmark.MAX_FINITE_RATIO;
    .tst.benchmark.captureLimitError];
  if[not first outcome;
    .tst.benchmark.fail["comparison ratio safety limit is unavailable"]];
  ratioLimit:first last outcome;
  if[not type[ratioLimit] in -4 -5 -6 -7 -8 -9h;
    .tst.benchmark.fail[
      "comparison ratio safety limit must be a finite numeric scalar"]];
  if[not .tst.benchmark.isFiniteScalar ratioLimit;
    .tst.benchmark.fail[
      "comparison ratio safety limit must be a finite numeric scalar"]];
  if[ratioLimit<=0;
    .tst.benchmark.fail[
      "comparison ratio safety limit must be positive"]];
  if[ratioLimit>1000000000000f;
    .tst.benchmark.fail[
      "comparison ratio safety limit exceeds its literal ceiling"]];
  "f"$ratioLimit
 };

.tst.benchmark.validateBenchOptions:{[opts]
  allowed:`iterations`warmup`gcBefore;
  defaultsOutcome:@[
    .tst.benchmark.captureLimit;
    `.tst.benchDefaults;
    .tst.benchmark.captureLimitError];
  if[not first defaultsOutcome;
    .tst.benchmark.fail["benchmark defaults are unavailable"]];
  defaults:first last defaultsOutcome;
  .tst.benchmark.validateOptions[
    defaults;allowed;"benchmark defaults"];
  opts:.tst.benchmark.validateOptions[opts;allowed;"benchmark"];
  cfg:defaults,opts;
  cfg[`iterations]:.tst.benchmark.validateCount[
    cfg`iterations;
    "benchmark iterations";
    1;
    .tst.benchmark.iterationLimit[]];
  cfg[`warmup]:.tst.benchmark.validateCount[
    cfg`warmup;
    "benchmark warmup";
    0;
    .tst.benchmark.warmupLimit[]];
  cfg[`gcBefore]:.tst.benchmark.validateBool[
    cfg`gcBefore;"benchmark gcBefore"];
  cfg
 };

.tst.benchmark.validateName:{[name;label]
  nameLimit:.tst.benchmark.nameLimit[];
  if[not type[name] in -11 10h;
    .tst.benchmark.fail[label," must be a string or symbol scalar"]];
  if[-11h=type name;
    if[null name;
      .tst.benchmark.fail[label," must not be empty"]];
    :name];
  if[not count name;
    .tst.benchmark.fail[label," must not be empty"]];
  if[count[name]>nameLimit;
    .tst.benchmark.fail[
      label," exceeds safety limit ",
      string nameLimit]];
  controls:"c"$((til 32),127);
  if[any name in controls;
    .tst.benchmark.fail[label," must not contain control characters"]];
  name
 };

.tst.benchmark.displayName:{[name]
  name:.tst.benchmark.validateName[name;"benchmark display name"];
  $[-11h=type name;"<symbol benchmark>";name]
 };

.tst.benchmark.fixedWidth:{[text;width]
  if[not 10h=type text;
    .tst.benchmark.fail["fixed-width value must be a string"]];
  width:.tst.benchmark.validateCount[
    width;
    "fixed-width display";
    1;
    .tst.benchmark.displayWidthLimit[]];
  if[count[text]>=width; :width#text];
  text,(width-count text)#" "
 };

/ Generate a histogram with N exact-once bins.
benchHistogram:{[data;nbins]
  .tst.benchmark.histogram[data;nbins]
 };

.tst.benchmark.validateHistogramTable:{[hist]
  bucketLimit:.tst.benchmark.bucketLimit[];
  dataLimit:.tst.benchmark.dataPointLimit[];
  if[not 98h=type hist;
    .tst.benchmark.fail["histogram output must be a table"]];
  required:`bucket`range_start`range_end`cnt`pct;
  columnNames:cols hist;
  if[count[columnNames]<>count required;
    .tst.benchmark.fail[
      "histogram output must contain exactly ",
      "bucket, range_start, range_end, cnt, and pct"]];
  if[not all required in columnNames;
    .tst.benchmark.fail[
      "histogram output must contain exactly ",
      "bucket, range_start, range_end, cnt, and pct"]];
  if[not count hist;
    .tst.benchmark.fail["histogram output must not be empty"]];
  if[count[hist]>bucketLimit;
    .tst.benchmark.fail["histogram output exceeds bucket safety limit"]];
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
  if[any ((hist`bucket)<0);
    .tst.benchmark.fail["histogram buckets must be non-negative"]];
  if[any ((hist`cnt)<0);
    .tst.benchmark.fail["histogram counts must be non-negative"]];
  if[any ((hist`cnt)>dataLimit);
    .tst.benchmark.fail["histogram counts exceed data-point safety limit"]];
  totalCount:sum "f"$hist`cnt;
  if[totalCount>dataLimit;
    .tst.benchmark.fail[
      "histogram total count exceeds data-point safety limit"]];
  if[any ((hist`range_end)<hist`range_start);
    .tst.benchmark.fail["histogram ranges must not descend"]];
  if[any (((hist`pct)<0) or (hist`pct)>100);
    .tst.benchmark.fail["histogram percentages must be between 0 and 100"]];
  if[not (hist`bucket)~til count hist;
    .tst.benchmark.fail[
      "histogram buckets must be consecutive and zero-based"]];
  hist
 };

/ Print histogram as ASCII bar chart.
benchPrintHistogram:{[hist]
  printLimit:.tst.benchmark.printRowLimit[];
  displayWidth:.tst.benchmark.displayWidthLimit[];
  hist:.tst.benchmark.validateHistogramTable hist;
  if[count[hist]>printLimit;
    .tst.benchmark.fail["histogram output exceeds print-row safety limit"]];
  maxPct:max hist`pct;
  if[0=maxPct;maxPct:1f];
  barWidth:30&displayWidth;
  labelWidth:24&displayWidth;
  {[row;maximum;width;labelSize]
    pctValue:row`pct;
    barLength:"j"$floor (pctValue*width)%maximum;
    barLength:0|barLength;
    barLength:width&barLength;
    bar:barLength#"#";
    startUs:("f"$row`range_start)%1000;
    endUs:("f"$row`range_end)%1000;
    label:(string startUs)," - ",(string endUs)," us";
    -1 "  ",.tst.benchmark.fixedWidth[label;labelSize],
      " |",bar," ",string[pctValue],"%";
  }[;maxPct;barWidth;labelWidth] each hist;
  ()
 };

.tst.benchmark.validatePrintStats:{[stats]
  printLimit:.tst.benchmark.printRowLimit[];
  if[not 99h=type stats;
    .tst.benchmark.fail["print statistics must be a dictionary"]];
  required:
    `iterations`total_ns`min_ns`max_ns`avg_ns`std_ns,
    `total_us`min_us`max_us`avg_us`std_us,
    `p50_ns`p90_ns`p95_ns`p99_ns,
    `p50_us`p90_us`p95_us`p99_us,
    `histogram`raw_ns;
  statsKeys:key stats;
  if[not type[statsKeys] in 0 11h;
    .tst.benchmark.fail["print statistics field names must be symbols"]];
  if[count[statsKeys]<>count required;
    .tst.benchmark.fail[
      "print statistics must contain exactly the benchmark result fields"]];
  if[count[statsKeys]<>count distinct statsKeys;
    .tst.benchmark.fail[
      "print statistics must contain exactly the benchmark result fields"]];
  if[not all required in statsKeys;
    .tst.benchmark.fail[
      "print statistics must contain exactly the benchmark result fields"]];
  .tst.benchmark.validateCount[
    stats`iterations;
    "print statistics iterations";
    1;
    .tst.benchmark.iterationLimit[]];
  .tst.benchmark.validateFiniteNonnegative[
    ;"print statistics timing"] each
    stats `total_ns`min_ns`max_ns`avg_ns`std_ns,
      `p50_ns`p90_ns`p95_ns`p99_ns;
  .tst.benchmark.validateFiniteNonnegativeNumeric[
    ;"print statistics timing"] each
    stats `total_us`min_us`max_us`avg_us`std_us,
      `p50_us`p90_us`p95_us`p99_us;
  raw:.tst.benchmark.validateSeries[
    stats`raw_ns;
    "print statistics raw timings"];
  if[count[raw]<>stats`iterations;
    .tst.benchmark.fail[
      "print statistics raw timing count must match iterations"]];
  if[not ()~stats`histogram;
    .tst.benchmark.validateHistogramTable stats`histogram;
    if[count[stats`histogram]>printLimit;
      .tst.benchmark.fail[
        "print statistics histogram exceeds print-row safety limit"]];
    if[sum[(stats`histogram)`cnt]<>stats`iterations;
      .tst.benchmark.fail[
        "print statistics histogram count must match iterations"]]];
  stats
 };

/ Print formatted benchmark results.
benchPrint:{[stats]
  stats:.tst.benchmark.validatePrintStats stats;
  -1 "";
  -1 "=== Benchmark Results ===";
  -1 "Iterations: ",string stats`iterations;
  -1 "Timing: Min=",(string stats`min_us),"us Avg=",
    (string stats`avg_us),"us Max=",
    (string stats`max_us),"us";
  -1 "Percentiles: p50=",(string stats`p50_us),
    "us p99=",(string stats`p99_us),"us";
  if[not ()~stats`histogram;
    -1 "Distribution (us):";
    benchPrintHistogram stats`histogram];
  -1 "";
 };

/ Preserve the historical percentile rule: floor(p*n), then explicitly clamp
/ to [0,n-1]. This selects the upper middle item for even n and is stable at n=1.
.tst.benchmark.percentileIndex:{[percentile;n]
  if[not type[percentile] in -4 -5 -6 -7 -8 -9h;
    .tst.benchmark.fail["percentile must be a finite numeric scalar"]];
  if[not .tst.benchmark.isFiniteScalar percentile;
    .tst.benchmark.fail["percentile must be a finite numeric scalar"]];
  if[(percentile<0) or (percentile>1);
    .tst.benchmark.fail["percentile must be between zero and one"]];
  n:.tst.benchmark.validateCount[
    n;
    "percentile sample count";
    1;
    .tst.benchmark.dataPointLimit[]];
  index:"j"$floor percentile*n;
  index:0|index;
  (n-1)&index
 };

.tst.benchmark.addLongSafely:{[accumulator;item]
  if[item>9223372036854775806-accumulator;
    .tst.benchmark.fail[
      "benchmark statistics must be a finite non-negative value ",
      "(aggregate timing overflow)"]];
  accumulator+item
 };

.tst.benchmark.safeTimespanSum:{[spans]
  longValues:"j"$spans;
  total:.tst.benchmark.addLongSafely over 0,longValues;
  "n"$total
 };

.tst.benchmark.runBench:{[func;cfg]
  func:.tst.benchmark.validateCallable[func;"benchmark function"];
  cfg:.tst.benchmark.validateBenchOptions cfg;
  dataLimit:.tst.benchmark.dataPointLimit[];
  bucketLimit:.tst.benchmark.bucketLimit[];
  n:cfg`iterations;
  if[n>dataLimit;
    .tst.benchmark.fail[
      "benchmark iterations exceed data-point safety limit"]];
  if[10>bucketLimit;
    .tst.benchmark.fail[
      "benchmark histogram requires a bucket safety limit of at least 10"]];
  warmup:cfg`warmup;
  do[warmup;
    .tst.benchmark.call[func;"benchmark warmup"]];
  if[cfg`gcBefore;.Q.gc[]];
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
    (n;.tst.benchmark.safeTimespanSum times;
      min times;max times;avg times;deviation);
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
/ input type; symbol names use a fixed display label to avoid unbounded copies.
benchCompare:{[name1;func1;name2;func2;opts]
  ratioCeiling:.tst.benchmark.ratioLimit[];
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
  winner:$[tie or (avg1<avg2);name1;name2];
  winnerDisplay:.tst.benchmark.displayName winner;
  ratio:$[tie;1f;
    zero1;0f;
    zero2;ratioCeiling;
    avg1%avg2];
  if[(not .tst.benchmark.isFiniteScalar ratio) or
     (ratio>ratioCeiling);
    ratio:ratioCeiling];
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
          ratioCeiling;
        1f%ratio];
      if[(not .tst.benchmark.isFiniteScalar speedup) or
         (speedup>ratioCeiling);
        speedup:ratioCeiling];
      .tst.benchmark.validateComputed[speedup;"benchmark comparison speedup"];
      -1 "Winner: ",winnerDisplay," (",string[speedup],"x faster)"]];
  `stats1`stats2`ratio`winner!(stats1;stats2;ratio;winner)
 };

\d .
