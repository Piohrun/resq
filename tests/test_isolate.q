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
.tst.isotest.base: "/tmp/resq_isolate_test_", string .z.i;
.tst.isotest.counter: 0;

.tst.isotest.workDir:{[]
    .tst.isotest.counter+: 1;
    .tst.isotest.base, "/run_", string .tst.isotest.counter
 };

.tst.isotest.cleanupBase:{[]
    expected: "/tmp/resq_isolate_test_", string .z.i;
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
    envPrefix: "TMPDIR=", qTmp, " ";
    if[noTimeoutPath; envPrefix: "PATH='/nonexistent' ", envPrefix];
    cmd: "mkdir -p ", qWd, " && cd ", qWd,
         " && ", envPrefix, outerTimeout, " -k 5 45 ", qExe, " ", qHome,
         " test ", args, " -isolate < /dev/null > ", qOut, " 2>&1; echo $?";
    statusLines: @[system; cmd; {[e] enlist "-1"}];
    code: "J"$last statusLines;
    out: @[read0; hsym `$wd, "/parent_out.txt"; {()}];
    tmpEntries: @[key; hsym `$tmpDir; {`symbol$()}];
    scratchCount: sum (string tmpEntries) like "resq_isolate.*";
    `code`out`dir`tmpDir`scratchCount!(code; out; wd; tmpDir; scratchCount)
 };

.tst.isotest.run:{[args] .tst.isotest.runEnv[args; 0b]};
.tst.isotest.anyLike:{[lines; pat] any lines like ("*", pat, "*")};
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
.tst.isotest.fxExit: enlist ".tst.desc[\"iso exiter\"]{ should[\"quits\"]{ exit 0 }; };";
.tst.isotest.fxReportThenExit: (".resq.childReport:.resq.report;";
    ".resq.report:{[results] .resq.childReport results; exit 9};";
    ".tst.desc[\"iso contradictory exit\"]{ should[\"passes before process exit\"]{ must[1b; \"yes\"] }; };");
.tst.isotest.fxLoad: ("undefinedTopLevelName[42];"; ".tst.desc[\"iso never\"]{ should[\"x\"]{ must[1b; \"t\"] }; };");
.tst.isotest.fxSkip: (".tst.desc[\"iso skipped\"]{"; " skip[\"not run\"]{ must[0b; \"never\"] };"; "};");

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
 };
