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
  diagnostics:$[(99h=type doc) and `diagnostics in key doc;doc`diagnostics;()];
  `code`labels`statuses`testIds`selection`stateFile`diagnostics!(
      code;labels;statuses;testIds;selection;stateFile;diagnostics)
 };

.tst.reruntest.corrupt:{[]
  path:.tst.reruntest.base,"/state/last-run.json";
  .utl.ensureDir .tst.reruntest.base,"/state";
  (hsym `$path) 0:enlist "{not-json";
 };

.tst.reruntest.legacy:{[]
  path:.tst.reruntest.base,"/state/last-run.json";
  .utl.ensureDir .tst.reruntest.base,"/state";
  doc:`schemaVersion`framework`failedTestIds!(1j;"resQ";enlist "test_legacy");
  (hsym `$path) 0:enlist .j.j doc;
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
    stateVersion musteq 2j;
    stateDoc[`identityAlgorithm] musteq .tst.IDENTITY_ALGORITHM;
    must[.tst.identityCodecMatches stateDoc`identityCodec;
         "persisted identity codec must match this runtime"];
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
         "a run with nothing to record leaves no state directory behind"]{
    / The rerun cache used to create .resq/ before deciding there was nothing
    / to save, so a run whose only file failed to load left an empty .resq/
    / in the caller's directory.
    wd:.tst.reruntest.base,"/load_failure";
    .utl.ensureDir wd;
    (hsym `$wd,"/test_broken.q") 0: enlist ".tst.desc[\"x\"]{ should[\"y\"]{ 1 musteq 1 };";
    qexe:first @[system;"command -v q 2>/dev/null";{enlist (getenv[`QHOME]),"/l64/q"}];
    cmd:"cd ",.utl.shellQuote[wd]," && timeout -k 5 30 ",.utl.shellQuote[qexe]," ",
        .utl.shellQuote[.resq.HOME,"/resq.q"]," test test_broken.q -quiet < /dev/null > out.txt 2>&1; echo $?";
    code:"J"$last @[system;"sh -c ",.utl.shellQuote cmd;{[err]enlist "-1"}];
    code musteq 4;
    (.utl.pathExists wd,"/.resq") musteq 0b;
  };

  skipIf[0=count @[system;"command -v timeout 2>/dev/null";{()}];
         "unwritable state is a warning, not a failed run"]{
    / Every state write is trapped, but the trap handlers took two arguments.
    / q passes a handler the error alone, so it returned a projection, `not`
    / on that signalled 'type, and a green suite in a read-only checkout (or a
    / .resq/ owned by another user) failed with "Framework phase 'rerunState'
    / failed: type". /dev/null/... is unwritable even for root.
    wd:.tst.reruntest.base,"/unwritable_state";
    .utl.ensureDir wd;
    (hsym `$wd,"/test_green.q") 0: enlist ".tst.desc[\"x\"]{ should[\"y\"]{ 1 musteq 1 }; };";
    qexe:first @[system;"command -v q 2>/dev/null";{enlist (getenv[`QHOME]),"/l64/q"}];
    cmd:"cd ",.utl.shellQuote[wd]," && timeout -k 5 30 ",.utl.shellQuote[qexe]," ",
        .utl.shellQuote[.resq.HOME,"/resq.q"]," test test_green.q",
        " -state-file /dev/null/resq/last-run.json",
        " -flake-history /dev/null/resq/flake-history.json",
        " -json -quiet -outDir report < /dev/null > out.txt 2>&1; echo $?";
    code:"J"$last @[system;"sh -c ",.utl.shellQuote cmd;{[err]enlist "-1"}];
    code musteq 0;
    doc:.j.k "\n" sv read0 hsym `$wd,"/report/test-results.json";
    statuses:{`$.tst.toString x`status} each doc`tests;
    statuses musteq enlist `pass;
    messages:{.tst.toString x`message} each doc`diagnostics;
    must[any messages like "Unable to write rerun state*";
         "the failed rerun-state write must surface as a diagnostic"];
    / An uncreatable lock is reported as such, not as a live writer after a
    / 5 s busy-wait.
    must[any messages like "Unable to create the flake history lock*";
         "an unwritable flake-history lock must be named as the cause"];
    must[not any messages like "*locked by another live writer*";
         "an unwritable lock must not be blamed on another writer"];
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

  skipIf[0=count @[system;"command -v timeout 2>/dev/null";{()}];
         "legacy identity state is archived before a clean rebuild"]{
    .tst.reruntest.legacy[];
    fallback:.tst.reruntest.run["-last-failed";1b;0b];
    fallback[`code] musteq 0;
    count[fallback`labels] musteq 3;
    fallback[`selection;`historyStatus] musteq "unsupported";
    fallback[`selection;`applied] musteq 0b;
    entries:string key hsym `$ .tst.reruntest.base,"/state";
    archives:entries where entries like "last-run.json.identity-mismatch.*.bak";
    count[archives] musteq 1;
    archived:.j.k raze read0 hsym `$ .tst.reruntest.base,"/state/",first archives;
    archivedVersion:"j"$archived`schemaVersion;
    archivedVersion musteq 1j;
    rebuilt:.j.k raze read0 hsym `$fallback`stateFile;
    rebuiltVersion:"j"$rebuilt`schemaVersion;
    rebuiltVersion musteq 2j;
    rebuiltAlgorithm:rebuilt`identityAlgorithm;
    rebuiltAlgorithm musteq .tst.IDENTITY_ALGORITHM;
    messages:{.tst.toString x`message} each fallback`diagnostics;
    must[any messages like "*archived at*";"the migration diagnostic must name the archive"];
  };
 };

::
