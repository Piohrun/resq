.tst.desc["Benchmarking Features"]{
    should["run bench and return proper structure"]{
        stats: .tst.bench[{1+1}; `iterations!(10)];
        99h mustmatch type stats;
        `iterations`total_ns`min_ns`max_ns`avg_ns mustin key stats;
        `min_us`max_us`avg_us`std_us mustin key stats;
        `p50_ns`p90_ns`p95_ns`p99_ns mustin key stats;
        `histogram`raw_ns mustin key stats;
    };

    should["run correct number of iterations"]{
        stats: .tst.bench[{1+1}; `iterations`warmup!(50;5)];
        stats[`iterations] musteq 50;
        (count stats`raw_ns) musteq 50;
    };

    should["measure actual execution time"]{
        stats: .tst.bench[{do[1000; 1+1]}; `iterations`warmup!(20;5)];
        stats[`avg_ns] mustgt 0;
        stats[`min_ns] mustgt 0;
        stats[`max_ns] mustgt 0;
    };

    should["calculate percentiles correctly"]{
        stats: .tst.bench[{1+1}; `iterations`warmup!(100;10)];
        stats[`p50_ns] mustgt 0;
        stats[`p90_ns] mustgt 0;
        stats[`p95_ns] mustgt 0;
        stats[`p99_ns] mustgt 0;
        stats[`p50_ns] mustlt stats[`p99_ns] + 1;
    };

    should["generate histogram with correct structure"]{
        stats: .tst.bench[{1+1}; `iterations`warmup!(100;10)];
        hist: stats`histogram;
        98h musteq type hist;
        `bucket`range_start`range_end`cnt`pct mustmatch cols hist;
        10 musteq count hist;
        100 musteq sum hist`cnt;
    };

    should["pass mustbench when under threshold"]{
        stats: .tst.mustbench[{1+1}; 1000000; `iterations`warmup!(10;5)];
        99h mustmatch type stats;
    };

    should["fail mustbench when over threshold"]{
        slowFunc: {do[100000; 1+1]};
        mustthrow["*Benchmark failed*"; (.tst.mustbench; slowFunc; 0.001; `iterations`warmup!(10;2))];
    };

    should["compare two implementations with benchCompare"]{
        fast: {1+1};
        slow: {do[100; 1+1]};
        result: .tst.benchCompare["fast"; fast; "slow"; slow; `iterations`warmup!(20;5)];
        99h mustmatch type result;
        `stats1`stats2`ratio`winner mustmatch key result;
        result[`winner] mustin `fast`slow;
    };

    should["identify faster implementation correctly"]{
        fast: {1+1};
        slow: {do[1000; 1+1]};
        result: .tst.benchCompare["fast"; fast; "slow"; slow; `iterations`warmup!(20;5)];
        result[`winner] mustmatch `fast;
    };

    should["use default configuration when no opts provided"]{
        `.tst.benchDefaults mock `iterations`warmup`gcBefore!(10;2;0b);
        stats: .tst.bench[{1+1}; ()!()];
        stats[`iterations] musteq 10;
    };

    should["generate histogram even with uniform times"]{
        hist: .tst.benchHistogram[10#1000; 5];
        98h mustmatch type hist;
        5 musteq count hist;
    };
};

.tst.desc["benchmark.measure timing precision"]{
    should["report float-millisecond timings (not whole-ms floor)"]{
        res: .tst.benchmark.measure[20; {sum til 100}];
        / Timings must be FLOAT ms with ns precision, never `long$-floored.
        (-9h) musteq type res[`time;`avg];
    };

    should["measure sub-millisecond code as non-zero average"]{
        / A tiny op completes in microseconds. Before the float fix this floored
        / to 0ms; now it must register a positive average.
        res: .tst.benchmark.measure[50; {sum til 100}];
        res[`time;`avg] mustgt 0;
    };

    should["honour the gc option via measureOpts"]{
        / gc on (default) and gc off must both produce float, non-zero timings.
        rOn: .tst.benchmark.measureOpts[20; {sum til 100}; enlist[`gc]!enlist 1b];
        rOff: .tst.benchmark.measureOpts[20; {sum til 100}; enlist[`gc]!enlist 0b];
        rOn[`time;`avg] mustgt 0;
        rOff[`time;`avg] mustgt 0;
        (-9h) musteq type rOff[`time;`avg];
    };

    should["keep measure as a backward-compatible wrapper (gc defaults on)"]{
        / Bare measure must still return the time/space dict structure.
        res: .tst.benchmark.measure[10; {1+1}];
        / `heapGrowth` joined `time`space when the allocation metric was split
        / into retained vs transient; `mustin` keeps this pinning the CONTRACT
        / (both original keys present) without re-breaking on the next addition.
        `time`space mustin key res;
        `min`med`max`avg`dev mustin key res`time;
    };
};

.tst.desc["benchmark regression statistics"]{
    should["retain one raw sample per measured run"]{
        result:.tst.benchmark.measureOpts[7;{sum til 20};enlist[`gc]!enlist 0b];
        (count result[`samples;`timeNs]) musteq 7;
        (count result[`samples;`retainedBytes]) musteq 7;
        result[`workload;`runs] musteq 7;
        result[`workload;`gcEach] musteq 0b;
    };

    should["average tied ranks deterministically"]{
        .tst.benchmarkRanks[1 2 2 4f] musteq 1 2.5 2.5 4f;
    };

    should["match the reference Mann-Whitney asymptotic result"]{
        / scipy.stats.mannwhitneyu([1..5],[6..10], alternative="two-sided",
        / method="asymptotic", use_continuity=True) gives p=0.0121857804.
        result:.tst.benchmarkMannWhitney[1 2 3 4 5f;6 7 8 9 10f];
        (result`valid) musteq 1b;
        (result`u) musteq 0f;
        (abs[(result`pValue)-0.0121857804] < 0.0000001) musteq 1b;
    };

    should["apply Holm-Bonferroni without decreasing adjusted p-values"]{
        adjusted:.tst.benchmarkHolm 0.01 0.04 0.03 0.002f;
        adjusted musteq 0.03 0.06 0.06 0.008f;
        (all adjusted>=0.01 0.04 0.03 0.002f) musteq 1b;
    };

    should["fingerprint the measurement environment without host paths"]{
        environment:.tst.benchmarkEnvironment[];
        (environment`fingerprint) mustlike "environment_????????????????????????????????";
        `qVersion`qRelease`os`architecture`cpuModel`logicalCores mustin key environment;
    };

    should["ignore non-benchmark framework rows"]{
        table:.resq.state.emptyResults[];
        table:table upsert .tst.isolate.errorRow[
            `FILE_LOAD_ERROR;"missing.q";"missing source"];
        (count .tst.performanceRecords table) musteq 0;
    };
};

.tst.desc["perf DSL runner"]{
    should["default to ten measured runs with per-iteration GC enabled"]{
        `.tst.benchmark.measureOpts mock {[n; code; opts]
            .tst.testState.perfDefaults: `runs`gc!(n; opts`gc);
            stats: `min`med`max`avg`dev!(1f; 1f; 1f; 1f; 0f);
            `time`space!(stats; stats)
        };
        expec: .tst.internals.perfObj, (`desc`code!("defaults"; {1+1}));
        .tst.runners[`perf] expec;
        .tst.testState.perfDefaults[`runs] musteq 10;
        .tst.testState.perfDefaults[`gc] musteq 1b;
    };

    should["reject a non-positive run count clearly"]{
        mustthrow["*positive integer*";
            (.tst.benchmark.measureOpts; 0; {1+1}; enlist[`gc]!enlist 0b)];
    };

    should["pass a sub-ms perf expectation under a generous maxTime"]{
        / Drive runners[`perf] directly. maxTime in ms; 1000ms is generous
        / headroom so this never flakes in CI even on a loaded runner.
        expec: .tst.internals.perfObj, (`desc`code`props!(
            "sub-ms perf"; {sum til 100}; `runs`gc`maxTime!(20; 0b; 1000f)));
        res: .tst.runners[`perf] expec;
        res[`result] mustmatch `pass;
        / Timing recorded as a float, non-zero average.
        res[`perf;`time;`avg] mustgt 0;
    };

    should["fail a perf expectation that exceeds maxTime"]{
        expec: .tst.internals.perfObj, (`desc`code`props!(
            "too slow"; {do[200000; sum til 100]}; `runs`gc`maxTime!(5; 0b; 0.0001)));
        res: .tst.runners[`perf] expec;
        res[`result] mustmatch `testFail;
        (any res[`failures] like "*Performance Failure: Avg Time*") mustmatch 1b;
    };
};

/ A perf block used to compute its averages and throw them away unless a budget
/ was breached: a passing benchmark left no record anywhere, so performance could
/ be gated but never tracked. Measurements now reach .tst.app.perfResults, the
/ console PERFORMANCE section and the JSON report's `performance` array.
.tst.desc["perf measurements are recorded"]{
  should["capture a row per perf block, with stats and any budget"]{
    saved: .tst.app.perfResults;
    savedRes: .resq.state.results;          / expecRan also writes a result row
    .tst.app.perfResults: .tst.app.emptyPerfResults[];

    e: `desc`props`code`type!("recorded bench"; `runs`maxTime!(5; 5000); {til 10}; `perf);
    ran: .tst.runners[`perf] e;
    .tst.callbacks.expecRan[`title`expectations!(`PerfProbe; ()); ran];

    rows: .tst.app.perfResults;
    .tst.app.perfResults: saved;
    .resq.state.results: savedRes;

    must[0 < count rows; "a perf block must record a row"];
    r: first rows;
    (r`description) musteq `$"recorded bench";
    (r`runs) musteq 5;
    must[0 <= r`avgTimeMs;   "an average time must be recorded"];
    must[not null r`maxTimeMs; "a max time must be recorded"];
    / The declared budget travels with the measurement so the margin is visible.
    (r`timeLimitMs) musteq 5000f;
  };

  should["record nothing for a suite with no perf blocks"]{
    saved: .tst.app.perfResults;
    savedRes: .resq.state.results;
    .tst.app.perfResults: .tst.app.emptyPerfResults[];
    e: `desc`code`type`failures`assertsRun!("plain"; {1+1}; `test; (); 1i);
    .tst.callbacks.expecRan[`title`expectations!(`PlainProbe; ()); e];
    n: count .tst.app.perfResults;
    .tst.app.perfResults: saved;
    .resq.state.results: savedRes;
    n musteq 0;
  };
 };

/ ---------------------------------------------------------------------------
/ The measured subject must actually RUN. `value` applied to a lambda returns
/ its internals without executing it, so measureOpts timed q's introspection
/ instead of the user's code: a perf block executed zero times and reported
/ ~200ns whatever it contained, and mustBeFasterThan/mustAllocLessThan were
/ therefore always satisfied. Counting executions is the only assertion that
/ catches this -- a timing alone looks plausible.
/ ---------------------------------------------------------------------------
.tst.desc["benchmark actually executes the subject"]{
  should["run the code once per iteration, plus warmup"]{
    .tst.testState.benchexec.n: 0;
    .tst.benchmark.measureOpts[10; {.tst.testState.benchexec.n: 1 + .tst.testState.benchexec.n}; enlist[`gc]!enlist 0b];
    n: .tst.testState.benchexec.n;
    must[n >= 10; "expected at least 10 executions, got ", string n];
  };

  should["execute a niladic lambda too"]{
    .tst.testState.benchexec.n: 0;
    .tst.benchmark.measureOpts[5; {[] .tst.testState.benchexec.n: 1 + .tst.testState.benchexec.n}; enlist[`gc]!enlist 0b];
    must[.tst.testState.benchexec.n >= 5;
         "a niladic subject must run too, got ", string .tst.testState.benchexec.n];
  };

  should["still evaluate a q source string"]{
    .tst.testState.benchexec.n: 0;
    .tst.benchmark.measureOpts[5; ".tst.testState.benchexec.n: 1 + .tst.testState.benchexec.n"; enlist[`gc]!enlist 0b];
    must[.tst.testState.benchexec.n >= 5;
         "a string subject must still be evaluated, got ", string .tst.testState.benchexec.n];
  };

  should["distinguish slow work from trivial work"]{
    / If the subject were not executed both would measure the same overhead.
    slow: .tst.benchmark.measureOpts[20; {asc 20000?1000}; enlist[`gc]!enlist 0b];
    fast: .tst.benchmark.measureOpts[20; {til 10}; enlist[`gc]!enlist 0b];
    must[slow[`time;`avg] > fast[`time;`avg];
         "sorting 20k must measure slower than `til 10`"];
  };

  should["make mustBeFasterThan meaningful"]{
    probe: {[f] old: .tst.assertState.failures; f[];
                n: (count .tst.assertState.failures) - count old;
                .tst.assertState.failures: old; n};
    / A generous bound passes; an impossible one must now FAIL, which it could
    / not do while the subject was never run.
    probe[{mustBeFasterThan[{til 10}; 1000]}] musteq 0;
    probe[{mustBeFasterThan[{asc 50000?1000}; 0.0000001]}] musteq 1;
  };
 };
