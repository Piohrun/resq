\d .tst

/ ============================================================================
/ Benchmarking Library for resQ
/ Provides precise performance measurement with statistical analysis
/ ============================================================================

/ Default configuration
benchDefaults: `iterations`warmup`gcBefore!(1000; 100; 1b);

/ Generate histogram with N bins
benchHistogram:{[data;nbins]
  minV: min data;
  maxV: max data;
  range: maxV - minV;
  binWidth: range % nbins;
  if[binWidth=0; binWidth: 1];
  bins: floor (data - minV) % binWidth;
  bins: bins & nbins-1;
  counts: @[nbins#0; bins; +; 1];
  ([] bucket: til nbins; range_start: minV + binWidth * til nbins; range_end: minV + binWidth * 1 + til nbins; cnt: counts; pct: 100 * counts % count data)
 };

/ Linear-interpolated percentile over a sorted zero-based sample vector. The
/ position is clamp[p;0;1] * (n-1), so endpoints are always in range and small
/ samples do not return null merely because p is close to 1. Empty input has no
/ percentile and returns the float null 0n.
benchPercentile:{[data;p]
  if[0=count data; :0n];
  sorted: asc "f"$data;
  probability: 0f | 1f & "f"$p;
  position: probability * (count[sorted] - 1);
  lo: "j"$floor position;
  hi: "j"$ceiling position;
  weight: position - lo;
  (sorted lo) + weight * (sorted hi) - sorted lo
 };

/ Print histogram as ASCII bar chart
benchPrintHistogram:{[hist]
  maxPct: max hist`pct;
  if[maxPct=0; maxPct: 1];
  barWidth: 30;
  {[h;maxPct;barWidth]
    pctVal: h`pct;
    barLen: `int$pctVal * barWidth % maxPct;
    bar: barLen#"#";
    / Two decimals, not `int$: sub-microsecond work is the common case and
    / integer microseconds collapsed every bucket to the same "1 - 1 us".
    lbl: (.Q.f[2; (`float$h`range_start)%1000])," - ",(.Q.f[2; (`float$h`range_end)%1000])," us";
    -1 "  ", (24$lbl), " |", bar, " ", (string `int$pctVal), "%";
  }[;maxPct;barWidth] each hist;
 };

/ Print formatted benchmark results
benchPrint:{[stats]
  -1 "";
  -1 "=== Benchmark Results ===";
  -1 "Iterations: ", string stats`iterations;
  -1 "Timing: Min=", (string `int$stats`min_us), "us Avg=", (string `int$stats`avg_us), "us Max=", (string `int$stats`max_us), "us";
  -1 "Percentiles: p50=", (string `int$stats`p50_us), "us p99=", (string `int$stats`p99_us), "us";
  if[not ()~stats`histogram; -1 "Distribution (us):"; benchPrintHistogram stats`histogram];
  -1 "";
 };

/ Run a function N times and collect timing data.
/ Measurement itself is delegated to .tst.benchmark.sample -- the single timing
/ core shared with perf blocks and the performance assertions. This file used to
/ carry its OWN loop, which meant two implementations that could drift apart;
/ they already differed in whether they executed the subject. What stays here is
/ the richer presentation this API adds: percentiles and a histogram.
/ Allocation is not recorded (space:0b): the .Q.w[] calls it needs would show up
/ in these timings, and callers wanting memory use measureOpts.
bench:{[func;opts]
  cfg: benchDefaults, $[99h=type opts; opts; ()!()];
  n: cfg`iterations;
  smp: .tst.benchmark.sample[n; func;
        `warmup`gcBefore`gcEach`space!(cfg`warmup; cfg`gcBefore; 0b; 0b)];
  times: smp`timesNs;
  result: `iterations`total_ns`min_ns`max_ns`avg_ns`std_ns!(n; sum times; min times; max times; avg times; dev times);
  / Convert spans to float us/ms for easier use
  result[`total_us]: (`float$result`total_ns) % 1000;
  result[`min_us]: (`float$result`min_ns) % 1000;
  result[`max_us]: (`float$result`max_ns) % 1000;
  result[`avg_us]: (`float$result`avg_ns) % 1000;
  result[`std_us]: (`float$result`std_ns) % 1000;
  result[`p50_ns]: benchPercentile[times; 0.50];
  result[`p90_ns]: benchPercentile[times; 0.90];
  result[`p95_ns]: benchPercentile[times; 0.95];
  result[`p99_ns]: benchPercentile[times; 0.99];
  result[`p50_us]: (`float$result`p50_ns) % 1000;
  result[`p90_us]: (`float$result`p90_ns) % 1000;
  result[`p95_us]: (`float$result`p95_ns) % 1000;
  result[`p99_us]: (`float$result`p99_ns) % 1000;
  result[`histogram]: benchHistogram[times; 10];
  result[`raw_ns]: times;
  result
 };

/ Assertion: function average time must be under threshold
mustbench:{[func;thresholdUs;opts]
  stats: bench[func; opts];
  if[stats[`avg_us] > thresholdUs; '"Benchmark failed: avg above threshold: ",(string stats`avg_us)];
  stats
 };

/ Compare two implementations
benchCompare:{[name1;func1;name2;func2;opts]
  -1 "Comparing: ", name1, " vs ", name2;
  stats1: bench[func1; opts];
  stats2: bench[func2; opts];
  -1 name1, ": Avg=", (string `int$stats1`avg_us), "us";
  -1 name2, ": Avg=", (string `int$stats2`avg_us), "us";
  ratio: stats1[`avg_us] % stats2[`avg_us];
  winner: $[ratio > 1; name2; name1];
  sup: $[ratio > 1; ratio; 1 % ratio];
  -1 "Winner: ",winner," (", (string sup),"x faster)";
  `stats1`stats2`ratio`winner!(stats1; stats2; ratio; `$winner)
 };

\d .
