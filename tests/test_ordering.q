/ End-to-end replay contract for deterministic execution ordering.

\d .tst

.tst.ordertest.base:.utl.tempRoot[],"/resq_order_test_",string .z.i;
.tst.ordertest.counter:0;

.tst.ordertest.run:{[seed;isolated]
  .tst.ordertest.counter+:1;
  wd:.tst.ordertest.base,"/run_",string .tst.ordertest.counter;
  .utl.ensureDir wd;
  report:wd,"/report";
  fixtureA:.resq.HOME,"/tests/fixtures/ordering/order_a.q";
  fixtureB:.resq.HOME,"/tests/fixtures/ordering/order_b.q";
  qexe:first @[system;"command -v q 2>/dev/null";{enlist (getenv[`QHOME]),"/l64/q"}];
  cmd:"cd ",.utl.shellQuote[.resq.HOME]," && timeout -k 5 30 ",
      .utl.shellQuote[qexe]," ",.utl.shellQuote[.resq.HOME,"/resq.q"],
      " test ",.utl.shellQuote[fixtureA]," ",.utl.shellQuote[fixtureB],
      " -random-order -seed ",string[seed],
      $[isolated;" -isolate";""],
      " -state-file ",.utl.shellQuote[wd,"/state.json"],
      " -flake-history ",.utl.shellQuote[wd,"/flake.json"],
      " -quarantine-file ",.utl.shellQuote[wd,"/quarantine.json"],
      " -flake-proposal-file ",.utl.shellQuote[wd,"/proposals.json"],
      " -json -quiet -outDir ",.utl.shellQuote[report],
      " < /dev/null > ",.utl.shellQuote[wd,"/out.txt"]," 2>&1; echo $?";
  statusLines:@[system;"sh -c ",.utl.shellQuote cmd;{[err] enlist "-1"}];
  code:"J"$last statusLines;
  raw:@[read0;hsym `$report,"/test-results.json";{()}];
  doc:$[count raw;.j.k "\n" sv raw;()!()];
  rows:$[(99h=type doc) and `tests in key doc;doc`tests;()];
  labels:{.tst.toString[x`suite],"/",.tst.toString x`description} each rows;
  ordering:$[(99h=type doc) and `run in key doc;doc[`run;`ordering];()!()];
  `code`labels`ordering`dir!(code;labels;ordering;wd)
 };

.tst.ordertest.cleanup:{[]
  expected:.utl.tempRoot[],"/resq_order_test_",string .z.i;
  if[not .tst.ordertest.base~expected;'"refusing unsafe ordering cleanup path"];
  if[.utl.pathExists .tst.ordertest.base;
    system "rm -rf -- ",.utl.shellQuote .tst.ordertest.base];
 };

\d .

.tst.desc["Replayable execution ordering #slow"]{
  after{.tst.ordertest.cleanup[]};

  skipIf[0=count @[system;"command -v timeout 2>/dev/null";{()}];
         "same seeds replay and isolation preserves the order"]{
    firstRun:.tst.ordertest.run[913;0b];
    replayRun:.tst.ordertest.run[913;0b];
    alternateRun:.tst.ordertest.run[914;0b];
    isolatedRun:.tst.ordertest.run[913;1b];
    firstRun[`code] musteq 0;
    replayRun[`code] musteq 0;
    alternateRun[`code] musteq 0;
    isolatedRun[`code] musteq 0;
    firstRun[`labels] musteq replayRun`labels;
    firstRun[`labels] mustne alternateRun`labels;
    firstRun[`labels] musteq isolatedRun`labels;
    firstRun[`ordering;`randomized] musteq 1b;
    decodedSeed:"j"$firstRun[`ordering;`seed];
    decodedSeed musteq 913j;
    firstRun[`ordering;`algorithm] musteq "md5-counter-v1";
  };
 };

::
