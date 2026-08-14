/ ============================================================================
/ tests/test_isolate.q - End-to-end process-isolation contracts.
/ .
/ Every nested resQ process runs under an outer timeout with SIGKILL escalation,
/ uses a scenario-local TMPDIR, and writes only below this process's PID-scoped
/ harness root. Tests assert child semantics, parent aggregation, exit codes,
/ scratch cleanup, and fail-closed setup behavior.
/ ============================================================================

\d .tst

.tst.isotest.qExe: {$[
    count found: @[system; "command -v q 2>/dev/null"; {()}];
        first found;
    (getenv[`QHOME]), "/l64/q"
]};
.tst.isotest.timeoutExe: {$[
    count found: @[system; "command -v timeout 2>/dev/null"; {()}];
        first found;
    ""
]};
.tst.isotest.qBinary: (getenv `QHOME), "/l64/q";
.tst.isotest.canQ: 0 < count .tst.isotest.qExe[];
.tst.isotest.canTimeout: 0 < count .tst.isotest.timeoutExe[];
.tst.isotest.base: .utl.tempRoot[], "/resq_isolate_test_", string .z.i;
.tst.isotest.counter: 0;

.tst.isotest.workDir:{[]
    .tst.isotest.counter+: 1;
    .tst.isotest.base, "/run_", string .tst.isotest.counter
 };

.tst.isotest.cleanupBase:{[]
    expected: .utl.tempRoot[], "/resq_isolate_test_", string .z.i;
    if[not .tst.isotest.base ~ expected;
        '"refusing unsafe isolate test cleanup path"];
    if[.utl.pathExists .tst.isotest.base;
        system "rm -rf -- ", .utl.shellQuote .tst.isotest.base];
 };

.tst.isotest.writeFixture:{[wd; name; lines]
    .utl.ensureDir wd;
    p: wd, "/", name;
    (hsym `$p) 0: lines;
    p
 };

.tst.isotest.markerLine:{[path]
    "(hsym `$\"", path, "\") 0: enlist \"executed\";"
 };

.tst.isotest.pidLine:{[path]
    "(hsym `$\"", path, "\") 0: enlist string .z.i;"
 };

/ Run `resq test ... -isolate` in a fresh parent project CWD.
/ noTimeoutPath hides timeout from the nested parent while the harness's outer
/ absolute timeout remains active.
.tst.isotest.runEnv:{[args; noTimeoutPath]
    wd: .tst.isotest.workDir[];
    tmpDir: wd, "/tmp";
    .utl.ensureDir tmpDir;
    qWd: .utl.shellQuote wd;
    qTmp: .utl.shellQuote tmpDir;
    qOut: .utl.shellQuote wd, "/parent_out.txt";
    qHome: .utl.shellQuote .resq.HOME, "/resq.q";
    nestedQ: $[
        noTimeoutPath and .utl.isFile .tst.isotest.qBinary;
            .tst.isotest.qBinary;
        .tst.isotest.qExe[]];
    qExe: .utl.shellQuote nestedQ;
    outerTimeout: .utl.shellQuote .tst.isotest.timeoutExe[];
    / This harness starts q directly, not through bin/resq. Never let a nested
    / probe arm or mark the outer launcher's completion guard.
    envPrefix: "RESQ_RUN_GUARD_DIR='' RESQ_ISOLATE_ROOT='' TMPDIR=", qTmp, " ";
    if[noTimeoutPath; envPrefix: "PATH='/nonexistent' ", envPrefix];
    cmd: "mkdir -p ", qWd, " && cd ", qWd,
         " && ", envPrefix, outerTimeout, " -k 5 45 ", qExe, " ", qHome,
         " -q test ", args, " -isolate < /dev/null > ", qOut, " 2>&1; echo $?";
    / A license-daemon-backed q installation can reject a burst of nested
    / process starts even though the same command succeeds one second later.
    / Retry ONLY that explicit startup diagnostic; all framework/test failures
    / remain single-attempt observations.
    code: -1;
    out: ();
    retryLicense: 1b;
    attempt: 0;
    while[retryLicense and attempt < 3;
        attempt+: 1;
        statusLines: @[system; cmd; {[e] enlist "-1"}];
        code: "J"$last statusLines;
        out: @[read0; hsym `$wd, "/parent_out.txt"; {()}];
        retryLicense: any {0 < count ss[x;"couldn't connect to license daemon"]} each out;
        if[retryLicense and attempt < 3; system "sleep 1"];
    ];
    tmpEntries: @[key; hsym `$tmpDir; {`symbol$()}];
    scratchCount: sum (string tmpEntries) like "resq_isolate.*";
    `code`out`dir`tmpDir`scratchCount!(code; out; wd; tmpDir; scratchCount)
 };

.tst.isotest.run:{[args] .tst.isotest.runEnv[args; 0b]};
.tst.isotest.anyLike:{[lines; pat] any lines like ("*", pat, "*")};
.tst.isotest.frameworkChatter:{[lines]
    patterns:("Loading Test:";"RUN AUDIT";"SUMMARY";"All tests passed";
              "Tests FAILED";"Report written to";"FAILURE DIFF");
    any {[rows;pattern] any rows like ("*",pattern,"*")}[lines;] each patterns
 };
.tst.isotest.fileExists:{[path] .utl.pathExists path};
.tst.isotest.childAlive:{[pidText]
    if[0 = count pidText; :0b];
    out: @[system; "kill -0 ", pidText, " 2>/dev/null; echo $?"; {[e] enlist "1"}];
    0 = "J"$last out
 };

\d .

.tst.isotest.fxPass1: enlist ".tst.desc[\"iso pass one\"]{ should[\"a\"]{ musteq[1+1; 2] }; should[\"b\"]{ must[1b; \"t\"] }; };";
.tst.isotest.fxPass2: enlist ".tst.desc[\"iso pass two\"]{ should[\"c\"]{ musteq[2*2; 4] }; };";
.tst.isotest.fxFail: enlist ".tst.desc[\"iso fail\"]{ should[\"bad\"]{ musteq[1; 2] }; };";
.tst.isotest.fxDiagnostic: enlist ".tst.desc[\"iso diagnostics\"]{ should[\"noisy mismatch\"]{ -1 \"RESQ_CHILD_DIAGNOSTIC\"; (`a`b!1 2) musteq (`a`b!1 3) }; };";
.tst.isotest.fxExit: enlist ".tst.desc[\"iso exiter\"]{ should[\"quits\"]{ exit 0 }; };";
.tst.isotest.fxReportThenExit: (".resq.childReport:.resq.report;";
    ".resq.report:{[results] .resq.childReport results; exit 9};";
    ".tst.desc[\"iso contradictory exit\"]{ should[\"passes before process exit\"]{ must[1b; \"yes\"] }; };");
.tst.isotest.fxLoad: ("undefinedTopLevelName[42];"; ".tst.desc[\"iso never\"]{ should[\"x\"]{ must[1b; \"t\"] }; };");
.tst.isotest.fxSkip: (".tst.desc[\"iso skipped\"]{"; " skip[\"not run\"]{ must[0b; \"never\"] };"; "};");

.tst.desc["Isolate: child argv uses effective parent options"]{
  before{
    `.tst.app.runSpecs        mock ("configured*"; "other*");
    `.tst.app.excludeSpecs    mock enlist "excluded*";
    `.tst.app.tagFilter       mock (`fast; `$"#fast");
    `.tst.app.excludeTagFilter mock (`slow; `$"#slow");
    `.tst.app.failFast        mock 1b;
    `.tst.app.qspecCompat     mock 1b;
    `.tst.app.expectationLineAnnotations mock 0b;
  };

  should["serialize config-derived filters and compatibility flags"]{
    argv: .tst.isolate.childArgv["test_a.q"; "/tmp/isolate"];
    must[(argv 1) like "*/resq.q"; "the child script must be q's first positional argument"];
    musteq[argv 2;"-q"];
    (argv 1 + argv ? "-only") musteq "configured*,other*";
    (argv 1 + argv ? "-exclude") musteq "excluded*";
    (argv 1 + argv ? "-tag") musteq "fast,#fast";
    (argv 1 + argv ? "-exclude-tag") musteq "slow,#slow";
    must["-fail-fast" in argv; "failFast must reach the child"];
    must["-qspec-compat" in argv; "qspec compatibility must reach the child"];
    must["-no-line-annotations" in argv; "the annotation kill switch must reach the child"];
    (argv 1 + argv ? "-flake-history") musteq "/tmp/isolate/flake-history.json";
    (argv 1 + argv ? "-flake-proposal-file") musteq "/tmp/isolate/quarantine-proposals.json";
    (argv 1 + argv ? "-state-file") musteq "/tmp/isolate/last-run.json";
    must[not (.tst.rerunStatePath[])~(argv 1+argv?"-state-file");
         "isolation children use private state"];
    must["-quarantine-file" in argv; "the reviewed quarantine manifest must reach the child"];
    (argv 1 + argv ? "-report-profile") musteq "full";
  };

  should["copy immutable parent selection into private child state"]{
    wd:.utl.tempRoot[],"/resq_isolate_state_",string[.z.i],"_",string `long$.z.p;
    .utl.ensureDir wd;
    `.tst.app.rerunState mock `status`failedTestIds`runId`updatedAt!(
        `ok;("test_a";"test_b");"run_parent";"2026-08-14T00:00:00Z");
    must[.tst.isolate.preparePrivateRerunState wd;"private state must be writable"];
    doc:.j.k "\n" sv read0 hsym `$.tst.isolate.privateRerunPath wd;
    doc[`failedTestIds] musteq ("test_a";"test_b");
    doc[`runId] musteq "run_parent";
    system "rm -rf -- ",.utl.shellQuote wd;
  };
 };

.tst.desc["Isolate: schema-v2 child telemetry"]{
  should["survive child JSON decoding into the parent result table"]{
    history:enlist `attempt`status`duration`durationSeconds`message`failures`assertsRun!(
      1j;"pass";"0D00:00:00.001";0.001;"";();1j);
    core:`suite`description`status`message`time`failures`assertsRun`file`line`namespace`tags`output!(
      "suite";"test";"pass";"";"0D00:00:00.001";();1j;"tests/test_x.q";7j;".sandbox";enlist "fast";"");
    telemetry:`testId`caseId`kind`attempts`retried`flaky`attemptHistory`parameterCases`property`diagnostics`snapshots`benchmark!(
      "test_fixed";"";"test";1j;0b;0b;history;();()!();();();()!());
    child:core,telemetry;
    rows:.tst.isolate.rowsFromJson enlist child;
    first[rows`testId] musteq "test_fixed";
    first[rows`attempts] musteq 1i;
    count[first rows`attemptHistory] musteq 1;
    first[rows`kind] musteq `test;
  };
 };

.tst.desc["Isolate: dead-child diagnostics"]{
  after{.tst.isotest.cleanupBase[]};

  should["bounds captured output while retaining its head and tail"]{
    wd: .tst.isotest.workDir[];
    .tst.isotest.writeFixture[wd; "out.txt";
        enlist "HEAD-",(500 # "x"),"-TAIL"];
    `.tst.output.reportLimit mock 120;
    captured: .tst.isolate.readCaptured wd;
    must[(count captured) <= 120; "captured output must obey reportLimit"];
    must[0 < count ss[captured;"HEAD-"]; "the diagnostic head must survive"];
    must[0 < count ss[captured;"-TAIL"]; "the diagnostic tail must survive"];
    must[0 < count ss[captured;"captured child output truncated"];
         "truncation must be explicit"];
  };

  should["identifies a captured wsfull instead of guessing exit"]{
    msg: .tst.isolate.noReportMessage[1;"'wsfull\n  [0]  huge allocation"];
    must[0 < count ss[msg;"q runtime/startup failure (wsfull)"];
         "captured fatal evidence must classify the dead child"];
    must[0 = count ss[msg;"did a test call exit?"];
         "a known fatal error must not be mislabeled as exit"];
    must[0 < count ss[msg;"huge allocation"];
         "the captured tail must remain attached"];
  };

  should["keeps the exit hint when the captured tail has no fatal evidence"]{
    msg: .tst.isolate.noReportMessage[7;"last user log line"];
    must[0 < count ss[msg;"process exited (code 7)"];
         "the actual exit code must be retained"];
    must[0 < count ss[msg;"did a test call exit?"];
         "unknown dead children should retain the actionable exit hint"];
  };

  should["names a license-daemon startup rejection explicitly"]{
    msg: .tst.isolate.noReportMessage[1;
        "'2026.08.03T10:17:33 couldn't connect to license daemon -- exiting"];
    must[0 < count ss[msg;"licence allocation was unavailable"];
         "runtime startup failures must name the exhausted allocation"];
    must[0 < count ss[msg;"reduce -isolateWorkers"];
         "the diagnostic must identify the operator-controlled remedy"];
    must[0 < count ss[msg;"couldn't connect to license daemon"];
         "the actionable license diagnostic must survive"];
  };

  should["retries only the explicit license startup failure"]{
    licenseRow: enlist .tst.isolate.errorRow[`ISOLATED_FILE_DIED;"test_a.q";
        "couldn't connect to license daemon -- exiting"];
    ordinaryRow: enlist .tst.isolate.errorRow[`ISOLATED_FILE_DIED;"test_b.q";
        "process exited without producing results"];
    .tst.isolate.retryableStartupFailure[licenseRow] musteq 1b;
    .tst.isolate.retryableStartupFailure[ordinaryRow] musteq 0b;
  };

  should["classifies license startup separately from a malformed child report"]{
    wd:.tst.isotest.workDir[];
    .tst.isotest.writeFixture[wd;"out.txt";
        enlist "couldn't connect to license daemon -- exiting"];
    rows:.tst.isolate.interpretFile[wd;"test_a.q";30;1;1;1];
    musteq[first {first x`suite} each rows;`ISOLATED_Q_STARTUP_ERROR];
    must[0 < count ss[first {first x`message} each rows;"reduce -isolateWorkers"];
         "classified startup failures must retain the capacity remedy"];
  };
 };

.tst.desc["Isolate: core process safety #slow"]{
  after{.tst.isotest.cleanupBase[]};

  skipIf[(not .tst.isotest.canQ) or not .tst.isotest.canTimeout; "two passing files aggregate"]{
    wd: .tst.isotest.workDir[];
    fa: .tst.isotest.writeFixture[wd; "test_a.q"; .tst.isotest.fxPass1];
    fb: .tst.isotest.writeFixture[wd; "test_b.q"; .tst.isotest.fxPass2];
    r: .tst.isotest.run[.utl.shellQuote[fa], " ", .utl.shellQuote[fb], " -quiet"];
    musteq[r`code; 0];
    must[.tst.isotest.anyLike[r`out; "3 total (3 passed"]; "must aggregate all passing tests"];
    must[0 = r`scratchCount; "private scratch must be removed"];
  };

  skipIf[(not .tst.isotest.canQ) or not .tst.isotest.canTimeout; "passing and failing files aggregate"]{
    wd: .tst.isotest.workDir[];
    fa: .tst.isotest.writeFixture[wd; "test_a.q"; .tst.isotest.fxPass1];
    ff: .tst.isotest.writeFixture[wd; "test_f.q"; .tst.isotest.fxFail];
    r: .tst.isotest.run[.utl.shellQuote[fa], " ", .utl.shellQuote[ff], " -quiet"];
    musteq[r`code; 1];
    must[.tst.isotest.anyLike[r`out; "Got 1 — expected 2"]; "failure must surface"];
    must[not .tst.isotest.anyLike[r`out; "ISOLATED_PROCESS_EXIT"]; "normal failure exit must preserve reported failure rows"];
    must[0 = r`scratchCount; "private scratch must be removed"];
  };

  skipIf[(not .tst.isotest.canQ) or not .tst.isotest.canTimeout;
         "failing child output and the full diff reach every parent reporter"]{
    wd: .tst.isotest.workDir[];
    ff: .tst.isotest.writeFixture[wd; "test_diagnostic.q"; .tst.isotest.fxDiagnostic];
    reportDir: wd, "/reports";
    r: .tst.isotest.run[.utl.shellQuote[ff], " -junit -json -outDir ",
        .utl.shellQuote[reportDir], " -quiet"];
    rawJson: @[read0; hsym `$reportDir, "/test-results.json"; {()}];
    report: $[count rawJson; .j.k raze rawJson; ()!()];
    xml: "\n" sv @[read0; hsym `$reportDir, "/test-results.junit.xml"; {()}];

    musteq[1; r`code];
    must[.tst.isotest.anyLike[r`out; "RESQ_CHILD_DIAGNOSTIC"];
         "the parent console must retain child stderr"];
    must[.tst.isotest.anyLike[r`out; "FAILURE DIFF"] and
         .tst.isotest.anyLike[r`out; "b: Value mismatch"];
         "the parent console must retain the child's full structural diff"];
    must[0 < count report; "the parent JSON report must exist"];
    captured: .tst.toString first report[`tests]`output;
    must[0 < count ss[captured;"RESQ_CHILD_DIAGNOSTIC"];
         "JSON output must retain child stderr"];
    must[(0 < count ss[captured;"FAILURE DIFF"]) and
         0 < count ss[captured;"b: Value mismatch"];
         "JSON output must retain the full diff"];
    must[0 < count ss[xml;"<system-out>"];
         "JUnit must publish captured child output as system-out"];
    must[0 < count ss[xml;"RESQ_CHILD_DIAGNOSTIC"];
         "JUnit system-out must contain child stderr"];
    / ... and NOTHING of the child's own report. Forwarding the whole transcript
    / repeated a SUMMARY box per failing file and advertised the child's private
    / mktemp scratch, which also made two runs of the same suite differ.
    must[not .tst.isotest.anyLike[r`out; "resq_isolate."];
         "the child's private scratch path must not reach the parent console"];
    must[1 = sum r[`out] like "SUMMARY";
         "exactly one SUMMARY block (the parent's) must be printed"];
    must[0 = count ss[captured;"JSON Report written to"];
         "captured output must not carry the child's reporter lines"];
    must[0 = count ss[captured;"resq_isolate."];
         "captured output must not carry the child's scratch path"];
    must[0 = count ss[captured;.tst.isolatedReportSentinel];
         "the report sentinel itself must be cut, not forwarded"];
    must[0 = r`scratchCount; "private scratch must be removed"];
  };

  skipIf[(not .tst.isotest.canQ) or not .tst.isotest.canTimeout;
         "a failing isolated suite produces byte-identical output across runs"]{
    wd: .tst.isotest.workDir[];
    ff: .tst.isotest.writeFixture[wd; "test_diagnostic.q"; .tst.isotest.fxDiagnostic];
    args: .utl.shellQuote[ff], " -quiet";
    first_: .tst.isotest.run[args];
    second: .tst.isotest.run[args];
    musteq[first_`code; second`code];
    / Durations are absent from -quiet failure output, so the transcripts must
    / match exactly. They did not while the child's mktemp scratch name leaked.
    musteq[first_`out; second`out];
  };

  skipIf[(not .tst.isotest.canQ) or not .tst.isotest.canTimeout; "exit-zero child cannot fake green"]{
    wd: .tst.isotest.workDir[];
    fe: .tst.isotest.writeFixture[wd; "test_e.q"; .tst.isotest.fxExit];
    fb: .tst.isotest.writeFixture[wd; "test_b.q"; .tst.isotest.fxPass2];
    r: .tst.isotest.run[.utl.shellQuote[fe], " ", .utl.shellQuote[fb], " -quiet"];
    musteq[r`code; 1];
    must[.tst.isotest.anyLike[r`out; "without producing results"]; "exit-zero must be a failure"];
    must[.tst.isotest.anyLike[r`out; "[2/2]"]; "later file must still execute"];
    must[0 = r`scratchCount; "private scratch must be removed"];
  };

  skipIf[(not .tst.isotest.canQ) or not .tst.isotest.canTimeout; "passing report plus nonzero process exit cannot fake green"]{
    wd: .tst.isotest.workDir[];
    f: .tst.isotest.writeFixture[wd; "test_report_exit.q"; .tst.isotest.fxReportThenExit];
    r: .tst.isotest.run[.utl.shellQuote[f], " -quiet"];
    musteq[r`code; 1];
    must[.tst.isotest.anyLike[r`out; "ISOLATED_PROCESS_EXIT"]; "process/report inconsistency must be reported"];
    must[.tst.isotest.anyLike[r`out; "unexpected code 9"]; "unexpected child exit must be explicit"];
    must[0 = r`scratchCount; "private scratch must be removed"];
  };

  skipIf[(not .tst.isotest.canQ) or not .tst.isotest.canTimeout; "hung child is reaped and scratch removed"]{
    wd: .tst.isotest.workDir[];
    pidFile: wd, "/child.pid";
    hangLines: (.tst.isotest.pidLine[pidFile]; ".tst.desc[\"iso hang\"]{ should[\"loops\"]{ while[1b;()] }; };");
    fh: .tst.isotest.writeFixture[wd; "test_h.q"; hangLines];
    fb: .tst.isotest.writeFixture[wd; "test_b.q"; .tst.isotest.fxPass2];
    r: .tst.isotest.run[.utl.shellQuote[fh], " ", .utl.shellQuote[fb], " -isolateTimeout 2 -quiet"];
    pidLines: @[read0; hsym `$pidFile; {()}];
    musteq[r`code; 1];
    must[.tst.isotest.anyLike[r`out; "TIMEOUT"]; "timeout must be reported"];
    must[not .tst.isotest.childAlive $[count pidLines; first pidLines; ""]; "timed-out q child must be gone"];
    must[0 = r`scratchCount; "private scratch must be removed"];
  };

  skipIf[(not .tst.isotest.canQ) or not .tst.isotest.canTimeout; "child load error keeps exit 4"]{
    wd: .tst.isotest.workDir[];
    fp: .tst.isotest.writeFixture[wd; "test_p.q"; .tst.isotest.fxPass1];
    fl: .tst.isotest.writeFixture[wd; "test_l.q"; .tst.isotest.fxLoad];
    r: .tst.isotest.run[.utl.shellQuote[fp], " ", .utl.shellQuote[fl], " -quiet"];
    musteq[r`code; 4];
    must[.tst.isotest.anyLike[r`out; "FILE_LOAD_ERROR"]; "load error row must be reported"];
    must[0 = r`scratchCount; "private scratch must be removed"];
  };
 };

.tst.desc["Isolate: child option propagation #slow"]{
  after{.tst.isotest.cleanupBase[]};

  skipIf[(not .tst.isotest.canQ) or not .tst.isotest.canTimeout; "-only may filter an entire child file"]{
    wd: .tst.isotest.workDir[];
    fd: .tst.isotest.writeFixture[wd; "test_drop.q"; enlist ".tst.desc[\"drop suite\"]{ should[\"drop\"]{ must[1b; \"yes\"] }; };"];
    fk: .tst.isotest.writeFixture[wd; "test_keep.q"; enlist ".tst.desc[\"keep suite\"]{ should[\"keep\"]{ must[1b; \"yes\"] }; };"];
    r: .tst.isotest.run[.utl.shellQuote[fd], " ", .utl.shellQuote[fk], " -only 'keep*' -quiet"];
    musteq[r`code; 0];
    must[.tst.isotest.anyLike[r`out; "1 total (1 passed"]; "the selected file must determine the global verdict"];
    must[not .tst.isotest.anyLike[r`out; "ISOLATED_PROCESS_EXIT"]; "a filtered-empty child is not a process failure"];
    must[0 = r`scratchCount; "private scratch must be removed"];
  };

  skipIf[(not .tst.isotest.canQ) or not .tst.isotest.canTimeout; "-only reaches child"]{
    wd: .tst.isotest.workDir[];
    marker: wd, "/excluded.marker";
    lines: (".tst.desc[\"selected suite\"]{ should[\"runs\"]{ must[1b; \"yes\"] }; };";
            ".tst.desc[\"excluded suite\"]{ should[\"no\"]{ ",.tst.isotest.markerLine[marker]," must[1b; \"yes\"] }; };");
    f: .tst.isotest.writeFixture[wd; "test_filter.q"; lines];
    r: .tst.isotest.run[.utl.shellQuote[f], " -only 'selected*' -quiet"];
    musteq[r`code; 0];
    must[.tst.isotest.anyLike[r`out; "1 total"]; "only one selected expectation must run"];
    must[not .tst.isotest.fileExists marker; "excluded expectation must not execute"];
  };

  skipIf[(not .tst.isotest.canQ) or not .tst.isotest.canTimeout; "-tag reaches child"]{
    wd: .tst.isotest.workDir[];
    marker: wd, "/slow.marker";
    lines: (".tst.desc[\"fast suite #fast\"]{ should[\"runs\"]{ must[1b; \"yes\"] }; };";
            ".tst.desc[\"slow suite #slow\"]{ should[\"no\"]{ ",.tst.isotest.markerLine[marker]," must[1b; \"yes\"] }; };");
    f: .tst.isotest.writeFixture[wd; "test_tag.q"; lines];
    r: .tst.isotest.run[.utl.shellQuote[f], " -tag fast -quiet"];
    musteq[r`code; 0];
    must[.tst.isotest.anyLike[r`out; "1 total"]; "tag filter must select one expectation"];
    must[not .tst.isotest.fileExists marker; "excluded tag must not execute"];
  };

  skipIf[(not .tst.isotest.canQ) or not .tst.isotest.canTimeout; "maxTestTime and fuzzLimit reach child"]{
    wd: .tst.isotest.workDir[];
    lines: enlist ".tst.desc[\"child settings\"]{ should[\"forwarded\"]{ .tst.app.maxTestTime musteq 7; .tst.output.fuzzLimit musteq 3; }; };";
    f: .tst.isotest.writeFixture[wd; "test_settings.q"; lines];
    r: .tst.isotest.run[.utl.shellQuote[f], " -maxTestTime 7 -fuzzLimit 3 -quiet"];
    musteq[r`code; 0];
    must[.tst.isotest.anyLike[r`out; "1 total (1 passed"]; "child must observe both numeric overrides"];
  };

  skipIf[(not .tst.isotest.canQ) or not .tst.isotest.canTimeout; "qspec compatibility reaches child"]{
    wd: .tst.isotest.workDir[];
    lines: enlist ".tst.desc[\"qspec child\"]{ should[\"broadcast\"]{ (0 0 0) musteq 0 }; };";
    f: .tst.isotest.writeFixture[wd; "test_qspec.q"; lines];
    r: .tst.isotest.run[.utl.shellQuote[f], " -qspec-compat -quiet"];
    musteq[r`code; 0];
    must[.tst.isotest.anyLike[r`out; "1 total (1 passed"]; "child must use qspec equality semantics"];
  };
 };

.tst.desc["Isolate: global strict semantics #slow"]{
  after{.tst.isotest.cleanupBase[]};

  skipIf[(not .tst.isotest.canQ) or not .tst.isotest.canTimeout; "filtered-empty file plus executed file passes strict"]{
    wd: .tst.isotest.workDir[];
    fd: .tst.isotest.writeFixture[wd; "test_drop.q"; enlist ".tst.desc[\"drop suite\"]{ should[\"drop\"]{ must[1b; \"yes\"] }; };"];
    fk: .tst.isotest.writeFixture[wd; "test_keep.q"; enlist ".tst.desc[\"keep suite\"]{ should[\"keep\"]{ must[1b; \"yes\"] }; };"];
    r: .tst.isotest.run[.utl.shellQuote[fd], " ", .utl.shellQuote[fk], " -only 'keep*' -strict -quiet"];
    musteq[r`code; 0];
    must[.tst.isotest.anyLike[r`out; "1 total (1 passed"]; "one global execution must satisfy strict"];
    must[not .tst.isotest.anyLike[r`out; "STRICT_MODE_FAILURE"]; "child strict rows must be discarded"];
  };

  skipIf[(not .tst.isotest.canQ) or not .tst.isotest.canTimeout; "all skipped fails strict exactly once"]{
    wd: .tst.isotest.workDir[];
    fs: .tst.isotest.writeFixture[wd; "test_skip.q"; .tst.isotest.fxSkip];
    r: .tst.isotest.run[.utl.shellQuote[fs], " -strict -quiet"];
    musteq[r`code; 1];
    musteq[sum (r`out) like "*STRICT_MODE_FAILURE*"; 1i];
  };

  skipIf[(not .tst.isotest.canQ) or not .tst.isotest.canTimeout; "missing snapshot still fails strict"]{
    wd: .tst.isotest.workDir[];
    snapName: "iso_missing_", string .z.i;
    line: ".tst.desc[\"strict snapshot\"]{ should[\"missing\"]{ .tst.mustmatchs[`a`b!1 2; \"",snapName,"\"]; }; };";
    fs: .tst.isotest.writeFixture[wd; "test_snapshot.q"; enlist line];
    r: .tst.isotest.run[.utl.shellQuote[fs], " -strict -quiet"];
    musteq[r`code; 1];
    must[.tst.isotest.anyLike[r`out; "Snapshot missing under -strict"]; "strict must reach snapshot backend"];
  };
 };

.tst.desc["Isolate: parent discovery and empty reports #slow"]{
  after{.tst.isotest.cleanupBase[]};

  skipIf[(not .tst.isotest.canQ) or not .tst.isotest.canTimeout; "explicit missing path exits 4"]{
    wd: .tst.isotest.workDir[];
    missing: wd, "/does_not_exist.q";
    r: .tst.isotest.run[.utl.shellQuote missing, " -quiet"];
    musteq[r`code; 4];
    must[.tst.isotest.anyLike[r`out; "FILE_LOAD_ERROR"]; "parent missing path must become a load row"];
  };

  skipIf[(not .tst.isotest.canQ) or not .tst.isotest.canTimeout; "mixed valid and missing paths exits 4"]{
    wd: .tst.isotest.workDir[];
    fp: .tst.isotest.writeFixture[wd; "test_pass.q"; .tst.isotest.fxPass2];
    missing: wd, "/missing.q";
    r: .tst.isotest.run[.utl.shellQuote[fp], " ", .utl.shellQuote[missing], " -quiet"];
    musteq[r`code; 4];
    must[.tst.isotest.anyLike[r`out; "FILE_LOAD_ERROR"]; "mixed discovery must preserve missing path"];
    must[.tst.isotest.anyLike[r`out; "[1/1]"]; "valid discovered file must still run"];
  };

  skipIf[(not .tst.isotest.canQ) or not .tst.isotest.canTimeout; "valid zero-test JSON is not a dead child"]{
    wd: .tst.isotest.workDir[];
    f: .tst.isotest.writeFixture[wd; "test_empty_filter.q"; enlist ".tst.desc[\"nothing selected\"]{ should[\"x\"]{ must[1b; \"yes\"] }; };"];
    r: .tst.isotest.run[.utl.shellQuote[f], " -only 'no-match*' -quiet"];
    musteq[r`code; 1];
    must[not .tst.isotest.anyLike[r`out; "DIED"]; "valid empty JSON must not be called dead"];
  };

  skipIf[(not .tst.isotest.canQ) or not .tst.isotest.canTimeout; "empty discovery keeps no-tests precedence"]{
    wd: .tst.isotest.workDir[];
    emptyDir: wd, "/empty";
    .utl.ensureDir emptyDir;
    r: .tst.isotest.runEnv[.utl.shellQuote[emptyDir], " -quiet"; 1b];
    musteq[r`code; 3];
    must[not .tst.isotest.anyLike[r`out; "ISOLATION_UNAVAILABLE"]; "no child helper is needed when no files were found"];
  };
 };

.tst.desc["Isolate: unsupported and unavailable modes #slow"]{
  after{.tst.isotest.cleanupBase[]};

  skipIf[(not .tst.isotest.canQ) or not .tst.isotest.canTimeout; "coverage plus isolate fails before tests"]{
    wd: .tst.isotest.workDir[];
    marker: wd, "/coverage.marker";
    f: .tst.isotest.writeFixture[wd; "test_marker.q"; (.tst.isotest.markerLine[marker]; ".tst.desc[\"never\"]{ should[\"x\"]{ must[1b; \"yes\"] }; };")];
    reportDir: wd, "/reports";
    r: .tst.isotest.run[.utl.shellQuote[f], " -cov -junit -outDir ", .utl.shellQuote[reportDir], " -quiet"];
    musteq[r`code; 1];
    must[.tst.isotest.anyLike[r`out; "CLI ERROR"]; "unsupported combination must be explicit"];
    must[not .tst.isotest.fileExists marker; "test file must not load"];
    must[not .tst.isotest.fileExists reportDir, "/test-results.xml"; "parent report must not be created"];
  };

  skipIf[(not .tst.isotest.canQ) or not .tst.isotest.canTimeout; "describe plus isolate fails before tests"]{
    wd: .tst.isotest.workDir[];
    marker: wd, "/describe.marker";
    f: .tst.isotest.writeFixture[wd; "test_marker.q"; (.tst.isotest.markerLine[marker]; ".tst.desc[\"never\"]{ should[\"x\"]{ must[1b; \"yes\"] }; };")];
    reportDir: wd, "/reports";
    r: .tst.isotest.run[.utl.shellQuote[f], " -desc -junit -outDir ", .utl.shellQuote[reportDir], " -quiet"];
    musteq[r`code; 1];
    must[.tst.isotest.anyLike[r`out; "CLI ERROR"]; "unsupported combination must be explicit"];
    must[not .tst.isotest.fileExists marker; "test file must not load"];
    must[not .tst.isotest.fileExists reportDir, "/test-results.xml"; "parent report must not be created"];
  };

  skipIf[(not .tst.isotest.canQ) or not .tst.isotest.canTimeout; "missing timeout fails closed before child launch"]{
    wd: .tst.isotest.workDir[];
    marker: wd, "/timeout.marker";
    f: .tst.isotest.writeFixture[wd; "test_marker.q"; (.tst.isotest.markerLine[marker]; ".tst.desc[\"never\"]{ should[\"x\"]{ must[1b; \"yes\"] }; };")];
    r: .tst.isotest.runEnv[.utl.shellQuote[f], " -quiet"; 1b];
    musteq[r`code; 1];
    must[.tst.isotest.anyLike[r`out; "requires a working timeout"]; "must fail closed clearly"];
    must[not .tst.isotest.fileExists marker; "child must never launch"];
  };
 };

.tst.desc["Isolate: parent reporter #slow"]{
  after{.tst.isotest.cleanupBase[]};

  skipIf[(not .tst.isotest.canQ) or not .tst.isotest.canTimeout; "parent junit merges all cases"]{
    wd: .tst.isotest.workDir[];
    fa: .tst.isotest.writeFixture[wd; "test_a.q"; .tst.isotest.fxPass1];
    fb: .tst.isotest.writeFixture[wd; "test_b.q"; .tst.isotest.fxPass2];
    xmlDir: wd, "/xml";
    r: .tst.isotest.run[.utl.shellQuote[fa], " ", .utl.shellQuote[fb], " -junit -outDir ", .utl.shellQuote[xmlDir], " -quiet"];
    xml: @[read0; hsym `$xmlDir, "/test-results.xml"; {()}];
    musteq[r`code; 0];
    must[0 < count xml; "parent XML must exist"];
    musteq[sum sum each xml like "*<testcase*"; 3i];
  };

  skipIf[(not .tst.isotest.canQ) or not .tst.isotest.canTimeout; "pass-only is silent in isolation mode"]{
    wd: .tst.isotest.workDir[];
    f: .tst.isotest.writeFixture[wd; "test_pass.q"; .tst.isotest.fxPass2];
    r: .tst.isotest.run[.utl.shellQuote[f], " -pass"];
    musteq[r`code; 0];
    .tst.isotest.frameworkChatter[r`out] musteq 0b;
  };
 };

/ ============================================================================
/ -isolateWorkers: running N files at once must not change ANY verdict.
/ .
/ Isolation is the feature people trust when a suite contains something that can
/ kill the run, so parallelism earns its place only if it is observably identical
/ to the sequential path. These tests compare the two directly rather than
/ asserting parallel output in isolation.
/ ============================================================================
.tst.desc["Isolate: parallel workers #slow"]{

  skipIf[(not .tst.isotest.canQ) or not .tst.isotest.canTimeout;
         "parallel run reaches the same verdicts as the sequential run"]{
    / Compare the JSON REPORTS rather than console text: the reports are the
    / contract CI consumes, and they carry the per-test verdicts that must not
    / shift. (Console text also differs legitimately in the banner, which names
    / the worker count.)
    wd: .tst.isotest.workDir[];
    fa: .tst.isotest.writeFixture[wd; "test_a.q"; .tst.isotest.fxPass1];
    fb: .tst.isotest.writeFixture[wd; "test_b.q"; .tst.isotest.fxPass2];
    ff: .tst.isotest.writeFixture[wd; "test_f.q"; .tst.isotest.fxFail];
    files: .utl.shellQuote[fa], " ", .utl.shellQuote[fb], " ", .utl.shellQuote[ff];

    serialDir:   wd, "/rep_serial";
    parallelDir: wd, "/rep_parallel";
    serial: .tst.isotest.run[files, " -json -outDir ",
        .utl.shellQuote[serialDir], " -quiet"];
    parallel: .tst.isotest.run[files, " -json -outDir ",
        .utl.shellQuote[parallelDir], " -isolateWorkers 3 -quiet"];

    musteq[parallel`code; serial`code];

    / NOT named `load`: that is a q keyword and assigning to it fails with 'assign.
    readReport: {[dir]
        raw: @[read0; hsym `$dir, "/test-results.json"; {()}];
        $[count raw; .j.k raze raw; ()!()]};
    sJson: readReport serialDir;
    pJson: readReport parallelDir;
    must[0 < count sJson; "the sequential run must write a JSON report"];

    / Counts must agree exactly...
    musteq[pJson[`summary;`testCount];  sJson[`summary;`testCount]];
    musteq[pJson[`summary;`passCount];  sJson[`summary;`passCount]];
    musteq[pJson[`summary;`failCount];  sJson[`summary;`failCount]];
    musteq[pJson[`summary;`errorCount]; sJson[`summary;`errorCount]];

    / ...and so must each individual verdict, in the same order. Ordering is
    / part of the contract: children start together but are interpreted in file
    / order, so a parallel report is not merely equivalent but identical here.
    key3: {[j] (j[`tests]`suite; j[`tests]`description; j[`tests]`status)};
    musteq[key3 pJson; key3 sJson];
  };

  skipIf[(not .tst.isotest.canQ) or not .tst.isotest.canTimeout;
         "a worker count above the file count is clamped, not an error"]{
    wd: .tst.isotest.workDir[];
    fa: .tst.isotest.writeFixture[wd; "test_a.q"; .tst.isotest.fxPass1];
    r: .tst.isotest.run[.utl.shellQuote[fa], " -isolateWorkers 64 -quiet"];
    musteq[r`code; 0];
  };

  skipIf[(not .tst.isotest.canQ) or not .tst.isotest.canTimeout;
         "each concurrent child still gets its own private scratch"]{
    / Two files that both record their pid. Distinct pids prove the children were
    / genuinely separate processes, and a clean run proves neither clobbered the
    / other's report -- the failure mode a shared scratch would produce.
    wd: .tst.isotest.workDir[];
    pidA: wd, "/pid_a.txt";
    pidB: wd, "/pid_b.txt";
    fa: .tst.isotest.writeFixture[wd; "test_a.q";
        (.tst.isotest.pidLine pidA;
         ".tst.desc[\"pa\"]{ should[\"a\"]{ must[1b; \"t\"] }; };")];
    fb: .tst.isotest.writeFixture[wd; "test_b.q";
        (.tst.isotest.pidLine pidB;
         ".tst.desc[\"pb\"]{ should[\"b\"]{ must[1b; \"t\"] }; };")];
    r: .tst.isotest.run[.utl.shellQuote[fa], " ", .utl.shellQuote[fb],
                        " -isolateWorkers 2 -quiet"];
    musteq[r`code; 0];
    a: @[read0; hsym `$pidA; {()}];
    b: @[read0; hsym `$pidB; {()}];
    must[(0 < count a) and 0 < count b; "both children must have run"];
    must[not (first a) ~ first b; "children must be distinct processes"];
  };

  skipIf[(not .tst.isotest.canQ) or not .tst.isotest.canTimeout;
         "no isolation scratch survives a parallel run"]{
    wd: .tst.isotest.workDir[];
    fa: .tst.isotest.writeFixture[wd; "test_a.q"; .tst.isotest.fxPass1];
    fb: .tst.isotest.writeFixture[wd; "test_b.q"; .tst.isotest.fxPass2];
    r: .tst.isotest.run[.utl.shellQuote[fa], " ", .utl.shellQuote[fb],
                        " -isolateWorkers 2 -quiet"];
    musteq[r`code; 0];
    / runEnv gives the nested parent its own TMPDIR, so any leaked scratch would
    / still be sitting under this scenario's tmp directory.
    leftovers: @[{[p] key hsym `$p}; wd, "/tmp"; {`symbol$()}];
    musteq[0; count leftovers where (string leftovers) like "resq_isolate.*"];
  };
 };
