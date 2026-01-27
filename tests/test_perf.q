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
