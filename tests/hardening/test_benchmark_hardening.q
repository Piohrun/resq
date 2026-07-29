.tst.testState.benchmarkProbe:0;
.tst.testState.withBenchmarkCaps:{[caps;code]
  original:`iterations`warmup`buckets`dataPoints!(
    .tst.benchmark.MAX_ITERATIONS;
    .tst.benchmark.MAX_WARMUP;
    .tst.benchmark.MAX_BUCKETS;
    .tst.benchmark.MAX_DATA_POINTS);
  `.tst.benchmark.MAX_ITERATIONS set caps`iterations;
  `.tst.benchmark.MAX_WARMUP set caps`warmup;
  `.tst.benchmark.MAX_BUCKETS set caps`buckets;
  `.tst.benchmark.MAX_DATA_POINTS set caps`dataPoints;
  outcome:@[
    {[f] (`ok;f[])};
    code;
    {[e] (`error;e)}];
  `.tst.benchmark.MAX_ITERATIONS set original`iterations;
  `.tst.benchmark.MAX_WARMUP set original`warmup;
  `.tst.benchmark.MAX_BUCKETS set original`buckets;
  `.tst.benchmark.MAX_DATA_POINTS set original`dataPoints;
  if[`error~first outcome; 'last outcome];
  last outcome
 };

.tst.desc["benchmark input hardening"]{
  should["reject invalid iteration counts before calling user code"]{
    .tst.testState.benchmarkProbe:0;
    invalid:(0;-1;0N;0W;-0W;1b;1.5;0n;0w;"2";enlist 2);
    {
      mustthrow[
        "*measurement iterations*";
        (.tst.benchmark.measure;x;{.tst.testState.benchmarkProbe+:1})]
    } each invalid;
    {
      opts:(enlist `iterations)!enlist x;
      mustthrow[
        "*benchmark iterations*";
        (.tst.bench;{.tst.testState.benchmarkProbe+:1};opts)]
    } each invalid;
    .tst.testState.benchmarkProbe musteq 0;
  };

  should["reject invalid warmup and boolean options before calling user code"]{
    .tst.testState.benchmarkProbe:0;
    invalidWarmup:(-1;0N;0W;-0W;1b;1.5;0n;0w;"2");
    {
      opts:`iterations`warmup`gcBefore!(1;x;0b);
      mustthrow[
        "*benchmark warmup*";
        (.tst.bench;{.tst.testState.benchmarkProbe+:1};opts)]
    } each invalidWarmup;

    invalidBool:(0;1;0N;"yes";enlist 1b;(::));
    {
      opts:`iterations`warmup`gcBefore!(1;0;x);
      mustthrow[
        "*benchmark gcBefore*";
        (.tst.bench;{.tst.testState.benchmarkProbe+:1};opts)]
    } each invalidBool;
    {
      opts:(enlist `gc)!enlist x;
      mustthrow[
        "*measurement gc*";
        (.tst.benchmark.measureOpts;
          1;
          {.tst.testState.benchmarkProbe+:1};
          opts)]
    } each invalidBool;
    .tst.testState.benchmarkProbe musteq 0;
  };

  should["reject malformed and unknown option dictionaries before invocation"]{
    .tst.testState.benchmarkProbe:0;
    malformed:(
      ();
      1;
      `iterations!(1);
      (enlist "iterations")!enlist 1;
      `iterations`iterations!(1;2);
      (enlist `unknown)!enlist 1);
    {
      mustthrow[
        "*option*";
        (.tst.bench;{.tst.testState.benchmarkProbe+:1};x)]
    } each malformed;

    measureMalformed:(
      ();
      1;
      (enlist "gc")!enlist 1b;
      `gc`gc!(1b;0b);
      (enlist `unknown)!enlist 1);
    {
      mustthrow[
        "*option*";
        (.tst.benchmark.measureOpts;
          1;
          {.tst.testState.benchmarkProbe+:1};
          x)]
    } each measureMalformed;

    manyKeys:(1+.tst.benchmark.MAX_OPTION_KEYS)#`iterations;
    manyOptions:manyKeys!(count manyKeys)#1;
    mustthrow[
      "*key-count safety limit*";
      (.tst.bench;
        {.tst.testState.benchmarkProbe+:1};
        manyOptions)];
    .tst.benchmark.boundedText[100#"x";8] mustmatch "xxxxx...";
    .tst.testState.benchmarkProbe musteq 0;
  };

  should["validate callables and thresholds before benchmark execution"]{
    .tst.testState.benchmarkProbe:0;
    invalidCode:(42;"code";()!();([] x:enlist 1);({1};1));
    {
      mustthrow[
        "*callable function*";
        (.tst.benchmark.measure;1;x)]
    } each invalidCode;
    {
      mustthrow[
        "*callable function*";
        (.tst.bench;x;`iterations`warmup!(1;0))]
    } each invalidCode;

    invalidThreshold:(
      -1;
      -0.1;
      -1e-308;
      0N;
      0W;
      -0W;
      0n;
      0w;
      0Ne;
      0We;
      -0We;
      1b;
      0D00:00:00.000000001;
      "1");
    {
      mustthrow[
        "*benchmark threshold*";
        (.tst.mustbench;
          {.tst.testState.benchmarkProbe+:1};
          x;
          `iterations`warmup!(1;0))]
    } each invalidThreshold;

    mustthrow[
      "*first benchmark function*";
      (.tst.benchCompare;
        "left";
        42;
        "right";
        {.tst.testState.benchmarkProbe+:1};
        `iterations`warmup!(1;0))];
    .tst.testState.benchmarkProbe musteq 0;
  };

  should["validate safe comparison names before either function runs"]{
    .tst.testState.benchmarkProbe:0;
    left:{.tst.testState.benchmarkProbe+:1};
    right:{.tst.testState.benchmarkProbe+:1};
    opts:`iterations`warmup!(1;0);
    mustthrow[
      "*must not be empty*";
      (.tst.benchCompare;"";left;"right";right;opts)];
    mustthrow[
      "*control characters*";
      (.tst.benchCompare;"bad\nname";left;"right";right;opts)];
    mustthrow[
      "*string or symbol*";
      (.tst.benchCompare;42;left;"right";right;opts)];
    mustthrow[
      "*exceeds safety limit*";
      (.tst.benchCompare;
        (1+.tst.benchmark.MAX_NAME_LENGTH)#"x";
        left;
        "right";
        right;
        opts)];
    mustthrow[
      "*names must both be strings or both be symbols*";
      (.tst.benchCompare;"left";left;`right;right;opts)];
    .tst.testState.benchmarkProbe musteq 0;
  };

  should["enforce private safety caps without performing large work"]{
    original:`iterations`warmup`buckets`dataPoints!(
      .tst.benchmark.MAX_ITERATIONS;
      .tst.benchmark.MAX_WARMUP;
      .tst.benchmark.MAX_BUCKETS;
      .tst.benchmark.MAX_DATA_POINTS);
    caps:`iterations`warmup`buckets`dataPoints!(2;1;2;3);
    .tst.testState.benchmarkProbe:0;
    checks:{
      mustthrow[
        "*measurement iterations*";
        (.tst.benchmark.measure;
          3;
          {.tst.testState.benchmarkProbe+:1})];
      mustthrow[
        "*measurement warmup*";
        (.tst.benchmark.measure;
          1;
          {.tst.testState.benchmarkProbe+:1})];
      mustthrow[
        "*benchmark iterations*";
        (.tst.bench;
          {.tst.testState.benchmarkProbe+:1};
          `iterations`warmup!(3;0))];
      mustthrow[
        "*benchmark warmup*";
        (.tst.bench;
          {.tst.testState.benchmarkProbe+:1};
          `iterations`warmup!(1;2))];
      mustthrow[
        "*bucket count*";
        (.tst.benchHistogram;0 1f;3)];
      mustthrow[
        "*exceeds safety limit*";
        (.tst.benchHistogram;0 1 2 3f;2)];
      ()
    };
    .tst.testState.withBenchmarkCaps[caps;checks];
    .tst.testState.benchmarkProbe musteq 0;

    mustthrow[
      "*intentional cap body failure*";
      (.tst.testState.withBenchmarkCaps;
        caps;
        {'"intentional cap body failure"})];
    .tst.benchmark.MAX_ITERATIONS musteq original[`iterations];
    .tst.benchmark.MAX_WARMUP musteq original[`warmup];
    .tst.benchmark.MAX_BUCKETS musteq original[`buckets];
    .tst.benchmark.MAX_DATA_POINTS musteq original[`dataPoints];
  };

  should["honour warmup counts incrementally and retain long allocation values"]{
    .tst.testState.benchmarkProbe:0;
    stats:.tst.bench[
      {.tst.testState.benchmarkProbe+:1};
      `iterations`warmup`gcBefore!(2;3;0b)];
    .tst.testState.benchmarkProbe musteq 5;
    count[stats[`raw_ns]] musteq 2;

    measured:.tst.benchmark.measureOpts[
      2;
      {.tst.testState.benchmarkProbe+:1};
      (enlist `gc)!enlist 0b];
    .tst.testState.benchmarkProbe musteq 10;
    (-7h) musteq type measured[`space;`min];
  };
};

.tst.desc["benchmark histogram and statistics hardening"]{
  should["assign every boundary datum to exactly one histogram bin"]{
    hist:.tst.benchHistogram[0 1 2 3 4f;2];
    hist[`cnt] mustmatch 2 3;
    sum[hist[`cnt]] musteq 5;
    hist[`range_start] mustmatch 0 2f;
    hist[`range_end] mustmatch 2 4f;

    negative:.tst.benchHistogram[-1 -0.5 0 0.5 1f;4];
    negative[`cnt] mustmatch 1 1 1 2;
    sum[negative[`cnt]] musteq 5;
    first[negative[`range_start]] musteq -1f;
    last[negative[`range_end]] musteq 1f;

    extreme:.tst.benchHistogram[
      -9223372036854775806 9223372036854775806;
      2];
    sum[extreme[`cnt]] musteq 2;
    (9h) musteq type extreme[`range_start];
    must[
      all .tst.benchmark.isFiniteScalar each extreme[`range_end];
      "extreme finite integer ranges must not wrap"];
  };

  should["retain native timespan histogram range behavior"]{
    spans:0D00:00:00.000000000 0D00:00:00.000000002
      0D00:00:00.000000004;
    hist:.tst.benchHistogram[spans;2];
    (9h) musteq type hist[`range_start];
    (9h) musteq type hist[`range_end];
    hist[`cnt] mustmatch 1 2;
    sum[hist[`cnt]] musteq count spans;

    constant:.tst.benchHistogram[3#last spans;10];
    count[constant] musteq 1;
    (16h) musteq type constant[`range_start];
    first[constant[`range_start]] mustmatch last spans;
    first[constant[`range_end]] mustmatch last spans;
  };

  should["collapse constant maximum values into one exact bucket"]{
    maxima:(
      0xff;
      32766h;
      2147483646i;
      9223372036854775806;
      1.7976931348623157e308);
    {
      hist:.tst.benchHistogram[3#x;.tst.benchmark.MAX_BUCKETS];
      count[hist] musteq 1;
      first[hist[`range_start]] mustmatch x;
      first[hist[`range_end]] mustmatch x;
      first[hist[`cnt]] musteq 3;
      first[hist[`pct]] musteq 100f;
    } each maxima;
  };

  should["reject empty malformed and non-finite statistical data"]{
    mustthrow["*must not be empty*";(.tst.benchHistogram;();4)];
    mustthrow["*must not be empty*";(.tst.benchmark.stats;())];
    mustthrow[
      "*homogeneous numeric or timespan vector*";
      (.tst.benchHistogram;"not numeric";4)];
    mustthrow[
      "*finite values*";
      (.tst.benchHistogram;(0f;0n);4)];
    mustthrow[
      "*finite values*";
      (.tst.benchmark.stats;(0f;0w))];
    mustthrow[
      "*histogram range produced a non-finite value*";
      (.tst.benchHistogram;-1e308 1e308;4)];
  };

  should["validate bucket counts on both public histogram entry points"]{
    invalid:(0;-1;0N;0W;-0W;1b;1.5;0n;0w;"2");
    {
      mustthrow["*bucket count*";(.tst.benchHistogram;0 1f;x)];
      mustthrow["*bucket count*";(.tst.benchmark.hist;0 1f;x)];
    } each invalid;
  };

  should["clamp all singleton percentiles and keep statistics finite"]{
    stats:.tst.bench[
      {1+1};
      `iterations`warmup`gcBefore!(1;0;0b)];
    only:first stats[`raw_ns];
    stats[`p50_ns] mustmatch only;
    stats[`p90_ns] mustmatch only;
    stats[`p95_ns] mustmatch only;
    stats[`p99_ns] mustmatch only;
    stats[`std_ns] musteq 0f;
    must[
      all .tst.benchmark.isFiniteScalar each
        stats[`total_ns`min_ns`max_ns`avg_ns`std_ns];
      "singleton timing statistics must all be finite"];
  };

  should["validate histogram tables before printing and format fixed widths safely"]{
    .tst.benchmark.fixedWidth["abc";5] mustmatch "abc  ";
    .tst.benchmark.fixedWidth["abcdef";5] mustmatch "abcde";
    mustthrow[
      "*must be a table*";
      (.tst.benchPrintHistogram;42)];
    empty:([] bucket:`long$();
      range_start:`float$();
      range_end:`float$();
      cnt:`long$();
      pct:`float$());
    mustthrow[
      "*must not be empty*";
      (.tst.benchPrintHistogram;empty)];
    bad:update pct:0w from .tst.benchHistogram[0 1f;2];
    mustthrow[
      "*finite values*";
      (.tst.benchPrintHistogram;bad)];
    badBuckets:update bucket:"f"$bucket from
      .tst.benchHistogram[0 1f;2];
    mustthrow[
      "*buckets must be integer*";
      (.tst.benchPrintHistogram;badBuckets)];
  };
};

.tst.desc["benchmark failure and comparison stability"]{
  should["propagate contextual user errors and stop immediately"]{
    .tst.testState.benchmarkProbe:0;
    measureFailure:{
      .tst.testState.benchmarkProbe+:1;
      '"measure boom"
    };
    mustthrow[
      "*measurement warmup failed: measure boom*";
      (.tst.benchmark.measureOpts;
        5;
        measureFailure;
        (enlist `gc)!enlist 0b)];
    .tst.testState.benchmarkProbe musteq 1;

    .tst.testState.benchmarkProbe:0;
    benchFailure:{
      .tst.testState.benchmarkProbe+:1;
      '"bench boom"
    };
    mustthrow[
      "*benchmark iteration failed: bench boom*";
      (.tst.bench;
        benchFailure;
        `iterations`warmup`gcBefore!(5;0;0b))];
    .tst.testState.benchmarkProbe musteq 1;

    mustthrow[
      "*callable function*";
      (.tst.bench;+;`iterations`warmup`gcBefore!(1;0;0b))];
  };

  should["reject negative aggregate timing overflow"]{
    start:2000.01.01D00:00:00.000000000;
    finish:2150.01.01D00:00:00.000000000;
    .tst.mockSequence[
      `.tst.benchmark.now;
      (start;finish;start;finish)];
    mustthrow[
      "*benchmark statistics must be a finite non-negative*";
      (.tst.bench;
        {1+1};
        `iterations`warmup`gcBefore!(2;0;0b))];
  };

  should["handle zero averages deterministically without null or infinity"]{
    zero:(enlist `avg_us)!enlist 0f;
    one:(enlist `avg_us)!enlist 1f;
    huge:(enlist `avg_us)!enlist 1e308;
    tiny:(enlist `avg_us)!enlist 1e-308;
    .tst.mockSequence[
      `.tst.benchmark.runBench;
      (zero;zero;zero;one;one;zero;one;zero;
       huge;tiny;tiny;huge)];
    beforeSymbols:.Q.w[][`syms];
    beforeRoot:key `;
    suffix:string .z.i;
    leftName:"dynamic-left-",suffix;
    rightName:"dynamic-right-",suffix;
    noOp:{::};

    tied:.tst.benchCompare[leftName;noOp;rightName;noOp;()!()];
    tied[`ratio] musteq 1f;
    tied[`winner] mustmatch leftName;
    (10h) musteq type tied[`winner];

    leftZero:.tst.benchCompare[leftName;noOp;rightName;noOp;()!()];
    leftZero[`ratio] musteq 0f;
    leftZero[`winner] mustmatch leftName;

    rightZero:.tst.benchCompare[leftName;noOp;rightName;noOp;()!()];
    rightZero[`ratio] musteq .tst.benchmark.MAX_FINITE_RATIO;
    rightZero[`winner] mustmatch rightName;
    must[
      .tst.benchmark.isFiniteScalar rightZero[`ratio];
      "zero denominator ratio must use a finite saturation value"];

    symbolWinner:.tst.benchCompare[
      `leftBenchmark;noOp;`rightBenchmark;noOp;()!()];
    symbolWinner[`winner] mustmatch `rightBenchmark;
    (-11h) musteq type symbolWinner[`winner];

    saturated:.tst.benchCompare[leftName;noOp;rightName;noOp;()!()];
    saturated[`ratio] musteq .tst.benchmark.MAX_FINITE_RATIO;
    saturated[`winner] mustmatch rightName;

    underflow:.tst.benchCompare[leftName;noOp;rightName;noOp;()!()];
    underflow[`ratio] musteq 0f;
    underflow[`winner] mustmatch leftName;

    .Q.w[][`syms] musteq beforeSymbols;
    (key `) mustmatch beforeRoot;
  };
};
