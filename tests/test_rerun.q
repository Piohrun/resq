/ End-to-end stable-ID rerun cache and selection contract.

\d .tst

.tst.reruntest.base:.utl.tempRoot[],"/resq_rerun_test_",string .z.i;
.tst.reruntest.counter:0;

.tst.reruntest.run:{[mode;markerPresent;isolated]
  .tst.reruntest.counter+:1;
  wd:.tst.reruntest.base,"/run_",string .tst.reruntest.counter;
  .utl.ensureDir wd;
  report:wd,"/report";
  stateFile:.tst.reruntest.base,"/state/last-run.json";
  marker:.tst.reruntest.base,"/pass.marker";
  if[markerPresent;(hsym `$marker) 0:enlist "pass"];
  if[not markerPresent;@[hdel;hsym `$marker;{}]];
  fixture:.resq.HOME,"/tests/fixtures/rerun/rerun_suite.q";
  qexe:first @[system;"command -v q 2>/dev/null";{enlist (getenv[`QHOME]),"/l64/q"}];
  cmd:"cd ",.utl.shellQuote[.resq.HOME]," && RESQ_RERUN_MARKER=",
      .utl.shellQuote[marker]," timeout -k 5 30 ",.utl.shellQuote[qexe]," ",
      .utl.shellQuote[.resq.HOME,"/resq.q"]," test ",.utl.shellQuote[fixture],
      $[count mode;" ",mode;""],$[isolated;" -isolate";""],
      " -state-file ",.utl.shellQuote[stateFile],
      " -flake-history ",.utl.shellQuote[wd,"/flake.json"],
      " -quarantine-file ",.utl.shellQuote[wd,"/quarantine.json"],
      " -flake-proposal-file ",.utl.shellQuote[wd,"/proposals.json"],
      " -json -quiet -outDir ",.utl.shellQuote[report],
      " < /dev/null > ",.utl.shellQuote[wd,"/out.txt"]," 2>&1; echo $?";
  statusLines:@[system;"sh -c ",.utl.shellQuote cmd;{[err]enlist "-1"}];
  code:"J"$last statusLines;
  raw:@[read0;hsym `$report,"/test-results.json";{()}];
  doc:$[count raw;.j.k "\n" sv raw;()!()];
  rows:$[(99h=type doc) and `tests in key doc;doc`tests;()];
  labels:{.tst.toString x`description} each rows;
  statuses:{`$.tst.toString x`status} each rows;
  testIds:{.tst.toString x`testId} each rows;
  selection:$[(99h=type doc) and `run in key doc;doc[`run;`selection];()!()];
  `code`labels`statuses`testIds`selection`stateFile!(
      code;labels;statuses;testIds;selection;stateFile)
 };

.tst.reruntest.corrupt:{[]
  path:.tst.reruntest.base,"/state/last-run.json";
  .utl.ensureDir .tst.reruntest.base,"/state";
  (hsym `$path) 0:enlist "{not-json";
 };

.tst.reruntest.cleanup:{[]
  expected:.utl.tempRoot[],"/resq_rerun_test_",string .z.i;
  if[not .tst.reruntest.base~expected;'"refusing unsafe rerun cleanup path"];
  if[.utl.pathExists .tst.reruntest.base;
    system "rm -rf -- ",.utl.shellQuote .tst.reruntest.base];
 };

\d .

.tst.desc["Stable-ID rerun workflow #slow"]{
  after{
    .tst.reruntest.cleanup[];
    if[.utl.pathExists .tst.reruntest.base;'"rerun test state cleanup failed"];
  };

  skipIf[0=count @[system;"command -v timeout 2>/dev/null";{()}];
         "persist, prioritize, select and isolate previous failures"]{
    initial:.tst.reruntest.run["";0b;0b];
    initial[`code] musteq 1;
    initial[`statuses] musteq `pass`fail`pass;
    must[.utl.pathExists initial`stateFile;"the first run must atomically publish state"];
    stateEntries:string key hsym `$ .tst.reruntest.base,"/state";
    must[not any stateEntries like "*.tmp.*";"atomic publish must leave no temp file"];
    stateLines:read0 hsym `$initial`stateFile;
    stateDoc:.j.k "\n" sv stateLines;
    stateVersion:"j"$stateDoc`schemaVersion;
    stateVersion musteq 1j;
    failedIds:initial[`testIds] where initial[`statuses]=`fail;
    stateDoc[`failedTestIds] musteq failedIds;

    prioritized:.tst.reruntest.run["-failed-first";1b;0b];
    prioritized[`code] musteq 0;
    prioritized[`labels] musteq ("previously failing";"first passes";"third passes");
    prioritized[`selection;`mode] musteq "failedFirst";
    priorCount:"j"$prioritized[`selection;`priorFailedCount];
    priorCount musteq 1j;

    primed:.tst.reruntest.run["";0b;0b];
    primed[`code] musteq 1;
    selected:.tst.reruntest.run["-last-failed";1b;0b];
    selected[`code] musteq 0;
    selected[`labels] musteq enlist "previously failing";
    selected[`selection;`applied] musteq 1b;

    primedAgain:.tst.reruntest.run["";0b;0b];
    primedAgain[`code] musteq 1;
    isolated:.tst.reruntest.run["-last-failed";1b;1b];
    isolated[`code] musteq 0;
    isolated[`labels] musteq enlist "previously failing";
    isolated[`selection;`applied] musteq 1b;
  };

  skipIf[0=count @[system;"command -v timeout 2>/dev/null";{()}];
         "corrupt state falls back to the complete suite"]{
    .tst.reruntest.corrupt[];
    fallback:.tst.reruntest.run["-last-failed";1b;0b];
    fallback[`code] musteq 0;
    count[fallback`labels] musteq 3;
    fallback[`selection;`historyStatus] musteq "invalid";
    fallback[`selection;`applied] musteq 0b;
  };
 };

::
