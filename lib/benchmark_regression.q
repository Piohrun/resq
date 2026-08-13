/ benchmark_regression.q - reproducible benchmark identities, baselines and gates
\d .tst

.tst.BENCHMARK_BASELINE_VERSION:1j;
.tst.BENCHMARK_ANALYSIS_VERSION:1j;

.tst.benchmarkRows:{[items]
    if[0=count items;:()];
    if[98h=type items;:{[table;i]table i}[items] each til count items];
    if[99h=type items;:enlist items];
    if[0h=type items;:items where 99h=type each items];
    ()
 };

.tst.benchmarkAbsolutePath:{[path]
    p:.utl.normalizePath .tst.toString path;
    if[count p;
      if[not "/"=first p;
        p:.utl.normalizePath .tst.toString[.tst.app.baseDir],"/",p]];
    p
 };

.tst.benchmarkBaselinePath:{[]
    configured:.tst.toString @[get;`.tst.app.benchmarkBaseline;{""}];
    $[count configured;.tst.benchmarkAbsolutePath configured;""]
 };

/ The fingerprint intentionally excludes hostname and checkout path. Those are
/ useful run dimensions but would make a reviewed baseline non-portable between
/ otherwise equivalent CI workers. CPU model remains included because changing
/ it can dominate the signal being measured.
.tst.benchmarkEnvironment:{[]
    architecture:.tst.firstCommandLine "uname -m 2>/dev/null";
    cpuModel:.tst.firstCommandLine "sed -n 's/^model name[[:space:]]*:[[:space:]]*//p' /proc/cpuinfo 2>/dev/null | head -1";
    coresText:.tst.firstCommandLine "getconf _NPROCESSORS_ONLN 2>/dev/null";
    cores:@[{"J"$x};coresText;{0Nj}];
    values:`qVersion`qRelease`os`architecture`cpuModel`logicalCores!(
        string .z.K;string .z.k;string .z.o;architecture;cpuModel;cores);
    values[`fingerprint]:"environment_",.tst.stableHash "\n" sv .tst.toString each value values;
    values
 };

.tst.currentBenchmarkEnvironment:{[]
    environment:@[get;`.tst.app.benchmarkEnvironment;{()!()}];
    if[not 99h=type environment;
        environment:.tst.benchmarkEnvironment[];
        .tst.app.benchmarkEnvironment:environment;
        :environment];
    if[not `fingerprint in key environment;
        environment:.tst.benchmarkEnvironment[];
        .tst.app.benchmarkEnvironment:environment];
    environment
 };

.tst.emptyBenchmarkCounts:{[]
    `total`baselineFound`comparable`improved`stable`inconclusive`regressed`environmentMismatches!(
        0j;0j;0j;0j;0j;0j;0j;0j)
 };

.tst.emptyBenchmarkAnalysis:{[enabled]
    gateEnabled:1b~@[get;`.tst.app.benchmarkGate;0b];
    `schemaVersion`kind`enabled`baselinePath`baselineStatus`method`config`environment`counts`comparisons`gate!(
        .tst.BENCHMARK_ANALYSIS_VERSION;"resq-benchmark-analysis";enabled;
        .tst.repoRelativePath .tst.benchmarkBaselinePath[];
        $[enabled;`notLoaded;`disabled];
        `name`alternative`continuityCorrection`tieCorrection`multipleComparison!(
            "Mann-Whitney U";"two-sided";1b;1b;"Holm-Bonferroni");
        `alpha`practicalEffectPercent`minimumSamples`metric!(
            ("f"$@[get;`.tst.app.benchmarkAlphaPercent;5j])%100f;
            "f"$@[get;`.tst.app.benchmarkEffectMin;5j];
            "j"$@[get;`.tst.app.benchmarkMinSamples;5j];"timeNs");
        .tst.currentBenchmarkEnvironment[];.tst.emptyBenchmarkCounts[];();
        `enabled`deferred`passed`reasons!(gateEnabled;0b;1b;()))
 };

.tst.benchmarkRanks:{[data]
    sorted:asc data;
    unique:distinct sorted;
    rankValues:{[vals;v]avg 1f+where vals=v}[data;] each unique;
    rankValues[unique?data]
 };

/ Abramowitz-Stegun 26.2.17. Maximum absolute error is below 7.5e-8, far
/ beneath the precision at which the documented 5% decision boundary is used.
.tst.benchmarkNormalCdf:{[x]
    z:abs "f"$x;
    t:1f%1f+0.2316419*z;
    polynomial:t*(0.319381530+t*(-0.356563782+t*(1.781477937+t*(-1.821255978+t*1.330274429))));
    density:exp[-0.5*z*z]%sqrt[2f*acos -1f];
    positive:1f-density*polynomial;
    $[x<0;1f-positive;positive]
 };

/ Two-sided asymptotic Mann-Whitney U with average ranks, tie-corrected
/ variance, and the conventional 0.5 continuity correction. Raw samples are
/ retained in the report/baseline so this decision can be independently replayed.
.tst.benchmarkMannWhitney:{[current;baseline]
    x:"f"$current;y:"f"$baseline;
    nx:"j"$count x;ny:"j"$count y;
    if[(0=nx) or 0=ny;
        :`valid`u`z`pValue!(0b;0nf;0nf;1f)];
    combined:x,y;
    ranks:.tst.benchmarkRanks combined;
    rankX:sum nx#ranks;
    u1:rankX-(nx*(nx+1))%2f;
    u2:nx*ny-u1;
    u:min u1,u2;
    total:nx+ny;
    ties:count each value group asc combined;
    tieTerm:sum ties*ties*ties-ties;
    variance:(nx*ny%12f)*((total+1f)-tieTerm%(total*(total-1f)));
    if[variance<=0f;
        :`valid`u`z`pValue!(0b;u;0nf;1f)];
    distance:0f|abs[u-(nx*ny%2f)]-0.5f;
    z:distance%sqrt variance;
    p:1f&2f*(1f-.tst.benchmarkNormalCdf z);
    `valid`u`z`pValue!(1b;"f"$u;"f"$z;"f"$p)
 };

.tst.benchmarkHolm:{[pValues]
    n:count pValues;
    if[0=n;:()];
    order:iasc pValues;
    scaled:(n-til n)*pValues order;
    adjustedSorted:1f&maxs scaled;
    adjusted:n#0f;
    adjusted[order]:adjustedSorted;
    adjusted
 };

.tst.benchmarkWorkload:{[benchmark]
    workload:$[`workload in key benchmark;benchmark`workload;()!()];
    `runs`warmup`gcBefore`gcEach`space!(
        "j"$$[`runs in key workload;workload`runs;
              `runs in key benchmark;benchmark`runs;0j];
        "j"$$[`warmup in key workload;workload`warmup;3j];
        1b~$[`gcBefore in key workload;workload`gcBefore;1b];
        1b~$[`gcEach in key workload;workload`gcEach;1b];
        1b~$[`space in key workload;workload`space;1b])
 };

.tst.benchmarkSamples:{[benchmark]
    samples:$[`samples in key benchmark;benchmark`samples;()!()];
    `timeNs`retainedBytes`heapGrowthBytes!(
        "j"$$[`timeNs in key samples;samples`timeNs;`long$()];
        "j"$$[`retainedBytes in key samples;samples`retainedBytes;`long$()];
        "j"$$[`heapGrowthBytes in key samples;samples`heapGrowthBytes;`long$()])
 };

.tst.performanceRecord:{[row]
    benchmark:row`benchmark;
    measurement:$[`measurement in key benchmark;benchmark`measurement;()!()];
    timeStats:$[(99h=type measurement) and `time in key measurement;measurement`time;()!()];
    spaceStats:$[(99h=type measurement) and `space in key measurement;measurement`space;()!()];
    limits:$[`limits in key benchmark;benchmark`limits;()!()];
    valueOr:{[dict;name;fallback]
        $[(99h=type dict) and name in key dict;dict name;fallback]};
    fields:`benchmarkId`testId`file`suite`description`metric`unit`runs,
      `avgTimeMs`minTimeMs`medTimeMs`maxTimeMs`devTimeMs,
      `avgSpaceBytes`maxSpaceBytes`timeLimitMs`spaceLimitBytes,
      `workload`samples`measurement`environment`comparison;
    values:(
        .tst.toString benchmark`benchmarkId;.tst.toString row`testId;
        .tst.toString row`file;`$.tst.toString row`suite;`$.tst.toString row`description;
        `time;"nanoseconds";"j"$benchmark`runs;
        "f"$valueOr[timeStats;`avg;0nf];"f"$valueOr[timeStats;`min;0nf];
        "f"$valueOr[timeStats;`med;0nf];"f"$valueOr[timeStats;`max;0nf];
        "f"$valueOr[timeStats;`dev;0nf];
        "f"$valueOr[spaceStats;`avg;0nf];"f"$valueOr[spaceStats;`max;0nf];
        "f"$valueOr[limits;`maxTimeMs;0nf];"f"$valueOr[limits;`maxSpaceBytes;0nf];
        .tst.benchmarkWorkload benchmark;.tst.benchmarkSamples benchmark;
        measurement;.tst.currentBenchmarkEnvironment[];
        $[`comparison in key benchmark;benchmark`comparison;()!()]);
    fields!values
 };

.tst.performanceRecords:{[results]
    rows:.tst.resultRows results;
    perfRows:rows where {[row]
        benchmark:row`benchmark;
        if[not 99h=type benchmark;:0b];
        `benchmarkId in key benchmark
      } each rows;
    .tst.performanceRecord each perfRows
 };

.tst.rebuildPerfResults:{[]
    records:.tst.performanceRecords .resq.state.results;
    table:.tst.app.emptyPerfResults[];
    i:0;
    while[i<count records;table:table upsert records i;i+:1];
    .tst.app.perfResults:table;
    records
 };

.tst.benchmarkWholeNumber:{[v;minimum]
    if[not ((type v) in "h"$-4 -5 -6 -7 -8 -9);:0b];
    (not null v) and (v>=minimum) and v=floor v
 };

.tst.benchmarkSampleVectorValid:{[values;minimumCount]
    sampleType:type values;
    if[(sampleType<4h) or sampleType>9h;:0b];
    if[count[values]<minimumCount;:0b];
    if[any null values;:0b];
    all (0<=values) and values=floor values
 };

.tst.validBenchmarkEnvironment:{[environment]
    if[not 99h=type environment;:0b];
    required:`qVersion`qRelease`os`architecture`cpuModel`logicalCores`fingerprint;
    if[not all required in key environment;:0b];
    fingerprint:.tst.toString environment`fingerprint;
    (44=count fingerprint) and "environment_"~12#fingerprint
 };

.tst.validBenchmarkBaselineEntryImpl:{[entry]
    if[not 99h=type entry;:0b];
    required:`benchmarkId`testId`file`suite`description`metric`unit`workload`samples`summary`environment;
    if[not all required in key entry;:0b];
    benchmarkId:.tst.toString entry`benchmarkId;
    testId:.tst.toString entry`testId;
    if[(42<>count benchmarkId) or not "benchmark_"~10#benchmarkId;:0b];
    if[(37<>count testId) or not "test_"~5#testId;:0b];
    if[not "timeNs"~.tst.toString entry`metric;:0b];
    if[not "nanoseconds"~.tst.toString entry`unit;:0b];
    workload:entry`workload;
    if[not 99h=type workload;:0b];
    if[not all `runs`warmup`gcBefore`gcEach`space in key workload;:0b];
    if[not .tst.benchmarkWholeNumber[workload`runs;1];:0b];
    if[not .tst.benchmarkWholeNumber[workload`warmup;0];:0b];
    if[not all -1h=type each workload `gcBefore`gcEach`space;:0b];
    samples:entry`samples;
    if[not 99h=type samples;:0b];
    if[not all `timeNs`retainedBytes`heapGrowthBytes in key samples;:0b];
    sampleRows:samples `timeNs`retainedBytes`heapGrowthBytes;
    if[not all {.tst.benchmarkSampleVectorValid[x;2]} each sampleRows;:0b];
    if[not all (count first sampleRows)=count each sampleRows;:0b];
    if[not workload[`runs]=count first sampleRows;:0b];
    .tst.validBenchmarkEnvironment entry`environment
 };

.tst.validBenchmarkBaselineEntry:{[entry]
    @[{[v]1b~.tst.validBenchmarkBaselineEntryImpl v};entry;{[error]0b}]
 };

.tst.loadBenchmarkBaseline:{[path]
    if[0=count path;:`status`entries`document!(`missing;();()!())];
    raw:.tst.readVersionedJson[path;.tst.BENCHMARK_BASELINE_VERSION;
        `schemaVersion`kind`updatedAt`frameworkVersion`source`environment`benchmarks];
    if[not `ok~raw`status;:`status`entries`document!(raw`status;();raw`document)];
    document:raw`document;
    entries:.tst.benchmarkRows document`benchmarks;
    if[not "resq-benchmark-baseline"~.tst.toString document`kind;
        :`status`entries`document!(`invalid;();document)];
    if[not .tst.validBenchmarkEnvironment document`environment;
        :`status`entries`document!(`invalid;();document)];
    if[not all .tst.validBenchmarkBaselineEntry each entries;
        :`status`entries`document!(`invalid;();document)];
    fingerprint:.tst.toString document[`environment;`fingerprint];
    if[not all {[expected;entry]
            expected~.tst.toString entry[`environment;`fingerprint]
          }[fingerprint;] each entries;
        :`status`entries`document!(`invalid;();document)];
    ids:.tst.toString each {x`benchmarkId} each entries;
    if[count[ids]<>count distinct ids;
        :`status`entries`document!(`invalid;();document)];
    `status`entries`document!(`ok;entries;document)
 };

.tst.findBenchmarkBaseline:{[entries;benchmarkId]
    if[0=count entries;:()!()];
    ids:.tst.toString each {x`benchmarkId} each entries;
    positions:where ids~\:.tst.toString benchmarkId;
    $[count positions;entries first positions;()!()]
 };

.tst.benchmarkEnvironmentMatches:{[left;right]
    if[(not 99h=type left) or not 99h=type right;:0b];
    if[not `fingerprint in key left;:0b];
    if[not `fingerprint in key right;:0b];
    .tst.toString[left`fingerprint]~.tst.toString right`fingerprint
 };

.tst.benchmarkRawComparison:{[current;baseline;environment;config;acceptEnvironment]
    benchmarkId:.tst.toString current`benchmarkId;
    baselineFound:(99h=type baseline) and 0<count baseline;
    currentSamples:current[`samples;`timeNs];
    baselineSamples:$[baselineFound;"j"$baseline[`samples;`timeNs];`long$()];
    environmentMatch:baselineFound and .tst.benchmarkEnvironmentMatches[environment;baseline`environment];
    workloadMatch:baselineFound and .tst.benchmarkWorkload[current]~.tst.benchmarkWorkload baseline;
    enough:(count currentSamples)>=config`minimumSamples;
    enough:enough and (count baselineSamples)>=config`minimumSamples;
    comparable:baselineFound and workloadMatch and enough and (environmentMatch or acceptEnvironment);
    reason:$[not baselineFound;"baseline-missing";
        not workloadMatch;"workload-mismatch";
        not enough;"insufficient-samples";
        (not environmentMatch) and (not acceptEnvironment);"environment-mismatch";
        not environmentMatch;"environment-mismatch-accepted";""];
    test:$[comparable;.tst.benchmarkMannWhitney[currentSamples;baselineSamples];
        `valid`u`z`pValue!(0b;0nf;0nf;1f)];
    currentMedian:$[count currentSamples;"f"$med currentSamples;0nf];
    baselineMedian:$[count baselineSamples;"f"$med baselineSamples;0nf];
    effect:$[(not null baselineMedian) and baselineMedian<>0f;
        100f*(currentMedian-baselineMedian)%baselineMedian;0nf];
    fields:`benchmarkId`testId`file`suite`description`classification`reason,
      `baselineFound`comparable`environmentMatch`workloadMatch`environmentAccepted,
      `metric`unit`baselineMedian`currentMedian`relativeChangePercent,
      `u`z`pValue`adjustedPValue`alpha`practicalEffectPercent`baselineRuns`currentRuns;
    values:(
        benchmarkId;.tst.toString current`testId;.tst.toString current`file;
        .tst.toString current`suite;.tst.toString current`description;
        `inconclusive;reason;baselineFound;comparable;environmentMatch;workloadMatch;
        (not environmentMatch) and acceptEnvironment;
        "timeNs";"nanoseconds";baselineMedian;currentMedian;effect;
        test`u;test`z;test`pValue;test`pValue;config`alpha;
        config`practicalEffectPercent;"j"$count baselineSamples;"j"$count currentSamples);
    fields!values
 };

.tst.classifyBenchmarkComparisons:{[comparisons]
    comparable:where {1b~x`comparable} each comparisons;
    if[count comparable;
        adjusted:.tst.benchmarkHolm {"f"$x`pValue} each comparisons comparable;
        i:0;
        while[i<count comparable;
            at:comparable i;
            comparison:comparisons at;
            comparison[`adjustedPValue]:adjusted i;
            significant:(adjusted i)<=comparison`alpha;
            practical:(not null comparison`relativeChangePercent) and
                abs[comparison`relativeChangePercent]>=comparison`practicalEffectPercent;
            comparison[`classification]:$[significant and practical;
                $[(comparison`relativeChangePercent)>0f;`regressed;`improved];`stable];
            comparisons[at]:comparison;
            i+:1]];
    comparisons
 };

.tst.benchmarkCounts:{[comparisons]
    classifications:{x`classification} each comparisons;
    `total`baselineFound`comparable`improved`stable`inconclusive`regressed`environmentMismatches!(
        "j"$count comparisons;
        "j"$sum {1b~x`baselineFound} each comparisons;
        "j"$sum {1b~x`comparable} each comparisons;
        "j"$sum classifications=`improved;
        "j"$sum classifications=`stable;
        "j"$sum classifications=`inconclusive;
        "j"$sum classifications=`regressed;
        "j"$sum {(1b~x`baselineFound) and not 1b~x`environmentMatch} each comparisons)
 };

.tst.attachBenchmarkComparisons:{[comparisons]
    if[0=count comparisons;:()];
    ids:.tst.toString each {x`benchmarkId} each comparisons;
    benches:.resq.state.results`benchmark;
    i:0;
    while[i<count benches;
        benchmark:benches i;
        if[(99h=type benchmark) and `benchmarkId in key benchmark;
            positions:where ids~\:.tst.toString benchmark`benchmarkId;
            if[count positions;
                benchmark[`comparison]:comparisons first positions;
                benches[i]:benchmark]];
        i+:1];
    .resq.state.results[`benchmark]:benches;
    ::
 };

.tst.applyBenchmarkRegression:{[]
    records:.tst.performanceRecords .resq.state.results;
    baselinePath:.tst.benchmarkBaselinePath[];
    gateEnabled:1b~@[get;`.tst.app.benchmarkGate;0b];
    enabled:(0<count baselinePath) or gateEnabled;
    analysis:.tst.emptyBenchmarkAnalysis enabled;
    if[not enabled;
        counts:.tst.emptyBenchmarkCounts[];
        counts[`total]:"j"$count records;
        analysis[`counts]:counts;
        .tst.app.benchmarkAnalysis:analysis;
        .tst.rebuildPerfResults[];
        :analysis];
    loaded:.tst.loadBenchmarkBaseline baselinePath;
    analysis[`baselineStatus]:loaded`status;
    config:analysis`config;
    environment:analysis`environment;
    acceptEnvironment:1b~@[get;`.tst.app.benchmarkAcceptEnvironment;0b];
    comparisons:{[entries;environment;config;accept;current]
        baseline:.tst.findBenchmarkBaseline[entries;current`benchmarkId];
        .tst.benchmarkRawComparison[current;baseline;environment;config;accept]
      }[loaded`entries;environment;config;acceptEnvironment;] each records;
    comparisons:.tst.classifyBenchmarkComparisons comparisons;
    analysis[`comparisons]:comparisons;
    analysis[`counts]:.tst.benchmarkCounts comparisons;
    gateReasons:();
    if[gateEnabled and not `ok~loaded`status;
        gateReasons,:enlist "baseline-",.tst.toString loaded`status];
    if[gateEnabled and (0=count records) and 1="j"$@[get;`.tst.app.shardCount;1j];
        gateReasons,:enlist "no-benchmarks-executed"];
    if[gateEnabled and any {not 1b~x`baselineFound} each comparisons;
        gateReasons,:enlist "benchmark-missing-from-baseline"];
    if[gateEnabled and any {`regressed~x`classification} each comparisons;
        gateReasons,:enlist "statistically-significant-practical-regression"];
    deferred:gateEnabled and (1<"j"$@[get;`.tst.app.shardCount;1j]);
    analysis[`gate]:`enabled`deferred`passed`reasons!(
        gateEnabled;deferred;deferred or 0=count gateReasons;
        $[deferred;();distinct gateReasons]);
    .tst.attachBenchmarkComparisons comparisons;
    .tst.app.benchmarkAnalysis:analysis;
    .tst.rebuildPerfResults[];
    if[(gateEnabled and not deferred) and 0<count gateReasons;.tst.app.passed:0b];
    analysis
 };

\d .
