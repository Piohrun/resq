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
        `time`space mustmatch key res;
        `min`med`max`avg`dev mustin key res`time;
    };
};

/ Run a tiny perf-DSL fixture through the real CLI with and without -perf.
.tst.testState.perfchk.canQ:0<count @[system;"command -v q 2>/dev/null";{()}];
.tst.testState.perfchk.canTimeout:0<count @[system;"command -v timeout 2>/dev/null";{()}];
.tst.testState.perfchk.anyLike:{[lines;pattern] any lines like ("*",pattern,"*")};
.tst.testState.perfchk.fixture:{[]
    lb:enlist "c"$123;
    rb:enlist "c"$125;
    (
        ".tst.desc[\"perf cli fixture\"]",lb;
        "  perf[\"selected threshold failure\"; `runs`gc`maxTime!(1;0b;0f)]",lb;
        "    -1 \"PERF_BODY_EXECUTED\";";
        "  ",rb,";";
        "  perf[\"invalid options are trapped\"; (enlist `runs)!enlist 0]",lb;
        "    -1 \"INVALID_PERF_BODY_EXECUTED\";";
        "  ",rb,";";
        " ",rb,";")
 };
.tst.testState.perfchk.run:{[flags]
    wd:"/tmp/resq_perf_",string[.z.i],"_",string `long$.z.p;
    system "mkdir -p ",.utl.shellQuote wd;
    (hsym `$wd,"/test_perf_fixture.q") 0:.tst.testState.perfchk.fixture[];
    if["config"~flags;
        (hsym `$wd,"/resq.json") 0:enlist "{\"runPerformance\":true}";
        flags:""
    ];
    cmd:"mkdir -p ",.utl.shellQuote[wd]," && cd ",.utl.shellQuote[wd],
        " && timeout -k 2s 30s q ",.utl.shellQuote[.resq.HOME,"/resq.q"],
        " test ",.utl.shellQuote[wd,"/test_perf_fixture.q"]," ",flags,
        " > out.txt 2>&1; echo $?";
    lines:@[system;cmd;{[e] enlist "-1"}];
    result:`code`out!("J"$last lines;@[read0;hsym `$wd,"/out.txt";{()}]);
    system "rm -rf -- ",.utl.shellQuote wd;
    result
 };

.tst.desc["perf DSL runner"]{
    should["skip perf expectations by default without calling code"]{
        previousRun:.tst.app.runPerformance;
        .tst.app.runPerformance:0b;
        .tst.testState.perfProbe:0;
        expec:.tst.internals.perfObj,(`desc`code!(
            "disabled perf";{.tst.testState.perfProbe+:1}));
        res:.tst.runners[`perf] expec;
        observed:.tst.testState.perfProbe;
        .tst.app.runPerformance:previousRun;
        ![`.tst.testState;();0b;enlist `perfProbe];

        res[`result] musteq `skip;
        res[`skipReason] mustlike "*enable with -perf*";
        res[`assertsRun] musteq 0i;
        count[res`failures] musteq 0;
        observed musteq 0;
    };

    should["use typed 100-run and gc-enabled perf defaults when opted in"]{
        previousRun:.tst.app.runPerformance;
        .tst.app.runPerformance:1b;
        .tst.testState.perfProbe:0;
        expec:.tst.internals.perfObj,(`desc`code!(
            "default perf";{.tst.testState.perfProbe+:1}));
        res:.tst.runners[`perf] expec;
        observed:.tst.testState.perfProbe;
        defaults:@[get;`.tst.perfDefaults;{()!()}];
        defaultRuns:$[`runs in key defaults;defaults`runs;0N];
        defaultGc:$[`gc in key defaults;defaults`gc;0N];
        .tst.app.runPerformance:previousRun;
        ![`.tst.testState;();0b;enlist `perfProbe];

        res[`result] musteq `pass;
        defaultRuns musteq 100;
        defaultGc musteq 1b;
        / measureOpts performs 3 warmups plus the configured 100 measurements.
        observed musteq 103;
    };

    should["pass a sub-ms perf expectation under a generous maxTime"]{
        / Drive runners[`perf] directly. maxTime in ms; 1000ms is generous
        / headroom so this never flakes in CI even on a loaded runner.
        previousRun:.tst.app.runPerformance;
        .tst.app.runPerformance:1b;
        expec: .tst.internals.perfObj, (`desc`code`props!(
            "sub-ms perf"; {sum til 100}; `runs`gc`maxTime!(20; 0b; 1000f)));
        res: .tst.runners[`perf] expec;
        .tst.app.runPerformance:previousRun;
        res[`result] mustmatch `pass;
        / Timing recorded as a float, non-zero average.
        res[`perf;`time;`avg] mustgt 0;
    };

    should["fail a perf expectation that exceeds maxTime"]{
        previousRun:.tst.app.runPerformance;
        .tst.app.runPerformance:1b;
        expec: .tst.internals.perfObj, (`desc`code`props!(
            "too slow"; {do[200000; sum til 100]}; `runs`gc`maxTime!(5; 0b; 0.0001)));
        res: .tst.runners[`perf] expec;
        .tst.app.runPerformance:previousRun;
        res[`result] mustmatch `testFail;
        (any res[`failures] like "*Performance Failure: Avg Time*") mustmatch 1b;
    };

    should["reject malformed perf properties before calling code"]{
        previousRun:.tst.app.runPerformance;
        .tst.app.runPerformance:1b;
        .tst.testState.perfProbe:0;
        badProps:(
            (enlist `runs)!enlist 0;
            (enlist `runs)!enlist -1;
            (enlist `runs)!enlist 0N;
            (enlist `runs)!enlist 0W;
            (enlist `runs)!enlist 1b;
            (enlist `runs)!enlist 1.5;
            (enlist `gc)!enlist 1;
            (enlist `gc)!enlist enlist 1b;
            (enlist `maxTime)!enlist -1;
            (enlist `maxTime)!enlist 1b;
            (enlist `maxTime)!enlist 0n;
            (enlist `maxTime)!enlist 0Ne;
            (enlist `maxTime)!enlist 0w;
            (enlist `maxTime)!enlist 0We;
            (enlist `maxSpace)!enlist "100";
            (enlist `maxSpace)!enlist 1b;
            (enlist `maxSpace)!enlist 0N;
            (enlist `maxSpace)!enlist 0n;
            (enlist `maxSpace)!enlist 0w);
        {[props]
            expec:.tst.internals.perfObj,(`desc`code`props!(
                "bad perf";{.tst.testState.perfProbe+:1};props));
            mustthrow["*Performance property*";(.tst.runners[`perf];expec)];
        } each badProps;
        observed:.tst.testState.perfProbe;
        .tst.app.runPerformance:previousRun;
        ![`.tst.testState;();0b;enlist `perfProbe];
        observed musteq 0;
    };

    should["reject unknown and malformed perf property keys before calling code"]{
        previousRun:.tst.app.runPerformance;
        .tst.app.runPerformance:1b;
        .tst.testState.perfProbe:0;

        unknown:(enlist `maxTim)!enlist 1f;
        expec:.tst.internals.perfObj,(`desc`code`props!(
            "unknown perf key";{.tst.testState.perfProbe+:1};unknown));
        mustthrow["*Performance property 'maxTim'*";(.tst.runners[`perf];expec)];

        malformed:(
            (enlist enlist "runs")!enlist 1;
            `runs`runs!(1;2));
        {[props]
            expec:.tst.internals.perfObj,(`desc`code`props!(
                "malformed perf keys";{.tst.testState.perfProbe+:1};props));
            mustthrow["*Performance properties must*";(.tst.runners[`perf];expec)];
        } each malformed;

        observed:.tst.testState.perfProbe;
        .tst.app.runPerformance:previousRun;
        ![`.tst.testState;();0b;enlist `perfProbe];
        observed musteq 0;
    };

    skipIf[not (.tst.testState.perfchk.canQ and .tst.testState.perfchk.canTimeout);
       "real CLI skips perf by default and executes/traps it when opted in"]{
        defaultRun:.tst.testState.perfchk.run "";
        perfRun:.tst.testState.perfchk.run "-perf";
        configRun:.tst.testState.perfchk.run "config";

        defaultRun[`code] musteq 0;
        must[not .tst.testState.perfchk.anyLike[defaultRun`out;"PERF_BODY_EXECUTED"];
             "default CLI run must not call perf code"];
        must[.tst.testState.perfchk.anyLike[defaultRun`out;"2 skipped"];
             "default CLI run must report both perf expectations as skipped"];

        perfRun[`code] musteq 1;
        must[.tst.testState.perfchk.anyLike[perfRun`out;"PERF_BODY_EXECUTED"];
             "-perf must execute the selected perf body"];
        must[not .tst.testState.perfchk.anyLike[perfRun`out;"INVALID_PERF_BODY_EXECUTED"];
             "invalid perf properties must be rejected before code execution"];
        must[.tst.testState.perfchk.anyLike[perfRun`out;"Performance property"];
             "invalid perf properties must be reported as a trapped test error"];

        configRun[`code] musteq 1;
        must[.tst.testState.perfchk.anyLike[configRun`out;"PERF_BODY_EXECUTED"];
             "runPerformance config must execute the selected perf body"];
        must[not .tst.testState.perfchk.anyLike[configRun`out;"INVALID_PERF_BODY_EXECUTED"];
             "config opt-in must still validate options before body execution"];
    };
};
