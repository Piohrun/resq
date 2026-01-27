system "l examples/quickstart/src/analytics/moving_avg.q";
/ Test: Moving Average Analytics

.tst.desc["Moving Average Analytics"]{
  should["trying to fix it"]{
  / Parametrized test showcasing .tst.forall
  cases: ([] 
    window: 2 3; 
    input: (1 2 3 4 5f; 1 2 3 4 5f); 
    expected_sma: (1 1.5 2.5 3.5 4.5; 1 1 2 3 4f)
  );

  .tst.forall[cases; {[row]
    res: .analytics.sma[row`window; row`input];
    mustmatch[row`expected_sma;res]
  }];

  };

  should["return correct moving average for window 2"]{
    res: .analytics.sma[2; 1 2 3 4 5f];
    res mustmatch 1 1.5 2.5 3.5 4.5;
  };

  / Performance test using benchmarking library
  should["handle large datasets efficiently"]{
    .tst.benchData: 10000?100.0;
    
    / Run 100 iterations with 10 warmup runs
    stats: .tst.bench[{.analytics.sma[100; .tst.benchData]}; `iterations`warmup!(100; 10)];
    
    / Print benchmark results
    .tst.benchPrint[stats];
    
    / Assert average time is under 500 microseconds
    (stats[`avg_us] < 500f) mustmatch 1b;
  };

  / Benchmark comparison example
  should["compare SMA window sizes"]{
    .tst.cmpData: 10000?100.0;
    
    cmp: .tst.benchCompare[
      "SMA window=10"; {.analytics.sma[10; .tst.cmpData]};
      "SMA window=100"; {.analytics.sma[100; .tst.cmpData]};
      `iterations`warmup!(50; 5)
    ];
    
    / Just verify comparison ran
    (count key cmp) mustmatch 4;
  };

}
