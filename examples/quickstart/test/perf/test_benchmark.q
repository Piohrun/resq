/ Test: Performance Benchmarking Showcase";
/ Demonstrates .tst.bench capabilities

.tst.desc["Performance Benchmarking"; {

  / Basic benchmark with statistics
  should["collect timing statistics over 1000 iterations"; {[]
    stats: .tst.bench[{sum 100?1.0}; `iterations`warmup!(1000; 100)];
    
    / Verify iterations count
    stats[`iterations] mustmatch 1000;
  }];

  / Percentile analysis
  should["calculate accurate percentiles"; {[]
    stats: .tst.bench[{10?1.0}; `iterations`warmup!(500; 50)];
    
    / p50 should be less than or equal to p90
    (stats[`p50_ns] <= stats[`p90_ns]) mustmatch 1b;
    
    / p95 should be less than or equal to p99
    (stats[`p95_ns] <= stats[`p99_ns]) mustmatch 1b;
  }];

  / Histogram distribution
  should["generate histogram with 10 bins"; {[]
    stats: .tst.bench[{100?1.0}; `iterations`warmup!(200; 20)];
    hist: stats`histogram;
    
    / Should have 10 bins
    (count hist) mustmatch 10;
    
    / All counts should sum to iterations
    (sum hist`cnt) mustmatch 200;
  }];

  / Threshold assertion
  should["enforce performance thresholds"; {[]
    / This operation should be fast
    stats: .tst.mustbench[{1+1}; 100.0; `iterations`warmup!(100; 10)];
    
    / If we got here, the threshold passed
    (stats[`avg_us] < 100) mustmatch 1b;
  }];

  / Comparison mode
  should["compare two implementations"; {[]
    result: .tst.benchCompare[
      "each"; {(+) each 1000 2#1};
      "vector"; {sum 1000 2#1};
      `iterations`warmup!(200; 20)
    ];
    
    / Result should have expected structure
    (count key result) mustmatch 4;
  }];

  / High iteration count
  should["support 10k+ iterations for precise measurement"; {[]
    stats: .tst.bench[{1.0}; `iterations`warmup!(10000; 1000)];
    
    / Min should be <= avg <= max
    (stats[`min_ns] <= stats[`avg_ns]) mustmatch 1b;
    (stats[`avg_ns] <= stats[`max_ns]) mustmatch 1b;
  }];

}];
