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

    should["benchmark quantiles small samples"]{
        .tst.benchPercentile[(); .5] mustmatch 0n;
        .tst.benchPercentile[enlist 42; .99] musteq 42f;
        .tst.benchPercentile[0 10; .25] musteq 2.5;
        .tst.benchPercentile[til 10; .5] musteq 4.5;
        .tst.benchPercentile[til 10; .99] musteq 8.91;
        .tst.benchPercentile[2 2 2 2; .95] musteq 2f;
        .tst.benchPercentile[0 10 20 30; .9] musteq 27f;
        .tst.benchPercentile[10 20; -1] musteq 10f;
        .tst.benchPercentile[10 20; 2] musteq 20f;
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

    should["Mann-Whitney reference statistics cover order, ties, and unequal samples"]{
        / These goldens use SciPy's two-sided asymptotic method with average
        / ranks, tie correction and continuity correction. SciPy is an
        / authoring cross-check only; resQ has no runtime Python dependency.
        cases:((1 2 3 4 5f;1 2 3 4 5f;12.5f;0f;1f);
               (1 1 2 2 3f;1 1 2 2 3f;12.5f;0f;1f);
               (1 2 3 4 5f;6 7 8 9 10f;0f;2.5067182457620487f;0.0121857803553449f);
               (1 2 2 3f;2 3 3 4 5 5f;3f;1.863748291027437f;0.0623570603614063f);
               (1 3 5f;2 4 6 8f;3f;0.8838834764831843f;0.3767591178115821f));
        / Deliberately slow pairwise U oracle. It is structurally independent
        / of the production rank implementation and stays small enough to read.
        referenceU:{[left;right]
            wins:sum {[other;item]sum item>other}[right;] each left;
            ties:sum {[other;item]sum item=other}[right;] each left;
            firstU:wins+0.5f*ties;
            min firstU,((count left)*count right)-firstU
        };
        {[referenceU;row]
            result:.tst.benchmarkMannWhitney[row 0;row 1];
            swapped:.tst.benchmarkMannWhitney[row 1;row 0];
            (result`u) musteq referenceU[row 0;row 1];
            (abs[result[`u]-row 2]<0.0000000001) musteq 1b;
            (abs[result[`z]-row 3]<0.0000001) musteq 1b;
            (abs[result[`pValue]-row 4]<0.0000002) musteq 1b;
            (abs[result[`pValue]-swapped`pValue]<0.0000000001) musteq 1b;
            p:result`pValue;
            ((p>=0f) and (p<=1f)) musteq 1b;
        }[referenceU;] each cases;
    };

    should["classify only significant effects at the practical boundary"]{
        template:`comparable`pValue`alpha`relativeChangePercent`practicalEffectPercent`classification!(
          1b;0.01f;0.05f;4.999f;5f;`inconclusive);
        below:first .tst.classifyBenchmarkComparisons enlist template;
        boundary:template;boundary[`relativeChangePercent]:5f;
        above:first .tst.classifyBenchmarkComparisons enlist boundary;
        improvement:template;improvement[`relativeChangePercent]:-5f;
        better:first .tst.classifyBenchmarkComparisons enlist improvement;
        below[`classification] musteq `stable;
        above[`classification] musteq `regressed;
        better[`classification] musteq `improved;
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
    (r[`numericStatus;`avgTimeMs]) musteq "finite";
    (r[`numericStatus;`spaceLimitBytes]) musteq "notConfigured";
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

/ The documented command gives the baseline as a path relative to the project
/ (docs/CI.md, docs/PERFORMANCE.md). It used to stop the run before any test
/ loaded, because the path was resolved before the base directory was set.
.tst.testState.relBaseline.canRun:
    (0 < count @[system; "which q 2>/dev/null"; {()}]) and
    (0 < count @[system; "which timeout 2>/dev/null"; {()}]);

.tst.testState.relBaseline.run:{[]
    wd: .resq.util.tempRoot[], "/resq_relbaseline_", string[.z.i], "_", string `long$.z.p;
    .resq.util.ensureDir wd, "/tests";
    (hsym `$wd, "/tests/test_speed.q") 0: (
        ".tst.desc[\"speed\"]{";
        "  perf[\"sorts\"; `runs`gc!(5;0b)]{ asc 1000?100 };";
        " };");
    / "true &&" first: q itself takes a command that starts with "cd".
    cmd: "true && cd ", (.resq.util.shellQuote wd), " && timeout -k 2 60 q ",
         (.resq.util.shellQuote .resq.HOME, "/resq.q"),
         " test tests -perf -benchmark-baseline benchmarks/baseline.json -json -outDir out",
         " -state-file out/state.json -flake-history out/flake.json",
         " -quarantine-file out/quarantine.json -flake-proposal-file out/proposals.json",
         " > out.txt 2>&1; echo $?";
    exitLines: @[system; cmd; {[err] enlist "-1"}];
    output: "\n" sv @[read0; hsym `$wd, "/out.txt"; {()}];
    if[wd like "*/resq_relbaseline_*"; system "rm -rf -- ", .resq.util.shellQuote wd];
    `code`output!("J"$last exitLines; output)
 };

.tst.desc["A benchmark baseline given as a relative path #slow"]{
  should["be resolved against the project directory, and the tests run"]{
    if[not .tst.testState.relBaseline.canRun; :must[1b; "q or timeout unavailable"]];
    r: .tst.testState.relBaseline.run[];
    r[`code] musteq 0;
    (0 < count r[`output] ss "Framework phase") musteq 0b;
    (0 < count r[`output] ss "baseline: benchmarks/baseline.json") musteq 1b;
    (0 < count r[`output] ss "1 total (1 passed") musteq 1b;
  };
 };

/ Presentation of benchmark figures.
.tst.desc["benchmark figures on the console"]{
    should["print microseconds below 100 with decimals"]{
        / every figure was rounded to a whole microsecond: 0.4 read "0us"
        .tst.benchUs[0.42] musteq "0.42";
        .tst.benchUs[3.14159] musteq "3.14";
        .tst.benchUs[12.345] musteq "12.3";
        .tst.benchUs[100.4] musteq "100";
        .tst.benchUs[1234.5] musteq "1235";
        .tst.benchUs[0n] musteq "n/a";
        .tst.benchUs[7i] musteq "7.00";
    };

    should["decide on colour from NO_COLOR, TERM, the setting and the terminal"]{
        .tst.colorWanted[""; "xterm-256color"; 1b; 1b] musteq 1b;
        / a terminal that says it shows escape sequences as they are
        .tst.colorWanted[""; "dumb"; 1b; 1b] musteq 0b;
        .tst.colorWanted[enlist "1"; "xterm"; 1b; 1b] musteq 0b;
        .tst.colorWanted[""; "xterm"; 0b; 1b] musteq 0b;
        .tst.colorWanted[""; "xterm"; 1b; 0b] musteq 0b;
        .tst.colorWanted[""; ""; 1b; 1b] musteq 1b;
    };

    should["show the benchmark table on a run that failed, and say when -desc writes no report #slow"]{
        if[(0 = count @[system; "which q 2>/dev/null"; {()}]); :must[1b; "q unavailable"]];
        wd: .resq.util.tempRoot[], "/resq_perf_red_", string[.z.i], "_", string `long$.z.p;
        .resq.util.ensureDir wd;
        .tst.registerCleanup[{[d] @[system; "rm -rf -- ", .resq.util.shellQuote d; {}]}; enlist wd];
        (hsym `$wd, "/test_perf_red.q") 0: (
            ".tst.desc[\"with a benchmark\"]{";
            "  perf[\"sums a vector\"; `runs!5]{ sum til 1000 };";
            "  should[\"fails\"]{ 1 musteq 2; };";
            " };");
        run: {[wd;flags]
            cmd: "cd ", .resq.util.shellQuote[wd], " && ", (.resq.util.shellQuote .resq.HOME, "/bin/resq"),
                " test . ", flags, " -state-file out/s.json -flake-history out/f.json -flake-proposal-file out/p.json",
                " < /dev/null 2>&1; echo exit=$?";
            @[system; "sh -c ", .resq.util.shellQuote cmd; {[e] enlist "exit=-1"}]}[wd];
        out: run "-perf";
        (last out) musteq "exit=1";
        table: first where out like "PERFORMANCE (1 benchmark):";
        verdict: first where out like "TOTAL FAILURES: 1";
        must[table < count out; "the benchmark table is printed on a red run"];
        must[table < verdict; "before the verdict"];
        / -desc runs nothing, so it writes no report; asked for one, it says so
        out: run "-desc -json -outDir rep";
        (any out like "NOTE: -desc lists the tests without running them; no json report is written.") musteq 1b;
        (() ~ key hsym `$wd, "/rep/test-results.json") musteq 1b;
    };
};

