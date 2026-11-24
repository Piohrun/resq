/ A run the launcher was told to stop (INT, TERM, HUP, QUIT). q does not stop
/ at a signal while it is busy: it went on to start the next batch of
/ isolated children, and to write a report and state files from a run that
/ had been cut short. The launcher now leaves a marker the run looks for.

.tst.testState.interrupt.canRun:
    (0 < count @[system; "which q 2>/dev/null"; {()}]) and
    (0 < count @[system; "which timeout 2>/dev/null"; {()}]);

.tst.testState.interrupt.workDir:{[]
    wd: .resq.util.tempRoot[], "/resq_interrupt_", string[.z.i], "_", string `long$.z.p;
    .resq.util.ensureDir wd;
    .tst.registerCleanup[{[d] @[system; "rm -rf -- ", .resq.util.shellQuote d; {}]}; enlist wd];
    wd
 };

/ Start a run in the background, signal the launcher after two seconds and
/ report its exit status and what it left behind.
.tst.testState.interrupt.signalled:{[wd;flags;sig]
    (hsym `$wd, "/test_wait.q") 0: enlist
        ".tst.desc[\"slow\"]{ should[\"waits\"]{ system \"sleep 30\"; 1 musteq 1; }; };";
    cmd: "cd ", .resq.util.shellQuote[wd], " && { ",
        .resq.util.shellQuote[.resq.HOME, "/bin/resq"], " test . ", flags,
        " -json -outDir out -state-file out/s.json -flake-history out/f.json",
        " -flake-proposal-file out/p.json > run.log 2>&1 & } ; pid=$!; sleep 2; kill -", sig,
        " \"$pid\"; wait \"$pid\"; echo exit=$?";
    out: @[system; "sh -c ", .resq.util.shellQuote cmd; {[e] enlist "exit=-1"}];
    `status`log`written!(last out;
        @[read0; hsym `$wd, "/run.log"; {[e] ()}];
        @[key; hsym `$wd, "/out"; {[e] ()}])
 };

.tst.desc["the interrupt marker"]{
  should["not be looked for when no launcher started the run"]{
    `.resq.interruptMarker mock `;
    .resq.util.runInterrupted[] musteq 0b;
  };
  should["mean interrupted once the launcher has left it, with the launcher's exit status"]{
    wd: .tst.testState.interrupt.workDir[];
    `.resq.interruptMarker mock hsym `$wd, "/interrupted";
    .resq.util.runInterrupted[] musteq 0b;
    (hsym `$wd, "/interrupted") 0: enlist "143";
    .resq.util.runInterrupted[] musteq 1b;
    .resq.util.interruptExitCode[] musteq 143;
    (hsym `$wd, "/interrupted") 0: enlist "not a number";
    .resq.util.interruptExitCode[] musteq 130;
    hdel hsym `$wd, "/interrupted";
  };
  should["stop a group of isolated children from being started"]{
    wd: .tst.testState.interrupt.workDir[];
    `.resq.interruptMarker mock hsym `$wd, "/interrupted";
    started: wd, "/started.txt";
    cmd: "touch ", .resq.util.shellQuote started;
    .tst.isolate.launchGroup[enlist 0; enlist cmd; enlist wd];
    (not () ~ key hsym `$started) musteq 1b;
    hdel hsym `$started;
    (hsym `$wd, "/interrupted") 0: enlist "130";
    .tst.isolate.launchGroup[enlist 0; enlist cmd; enlist wd];
    (() ~ key hsym `$started) musteq 1b;
    hdel hsym `$wd, "/interrupted";
  };
  should["mark the run as interrupted and not passed"]{
    wd: .tst.testState.interrupt.workDir[];
    `.resq.interruptMarker mock hsym `$wd, "/interrupted";
    `.tst.app.interrupted mock 0b;
    `.tst.app.passed mock 1b;
    .tst.noteInterrupted[] musteq 0b;
    .tst.app.interrupted musteq 0b;
    (hsym `$wd, "/interrupted") 0: enlist "143";
    .tst.noteInterrupted[] musteq 1b;
    .tst.app.interrupted musteq 1b;
    .tst.app.passed musteq 0b;
    hdel hsym `$wd, "/interrupted";
  };
 };

.tst.desc["a run that is told to stop #slow"]{
  should["write no report and no state, in process"]{
    if[not .tst.testState.interrupt.canRun; :must[1b; "q or timeout unavailable"]];
    r: .tst.testState.interrupt.signalled[.tst.testState.interrupt.workDir[]; ""; "TERM"];
    r[`status] musteq "exit=143";
    (count r`written) musteq 0;
    (any r[`log] like "resQ: interrupted.*") musteq 1b;
  };
  should["write no report and no state, and no made-up timeout, under -isolate"]{
    if[not .tst.testState.interrupt.canRun; :must[1b; "q or timeout unavailable"]];
    / TERM here too: a shell starts a background job with INT ignored.
    r: .tst.testState.interrupt.signalled[.tst.testState.interrupt.workDir[]; "-isolate"; "TERM"];
    r[`status] musteq "exit=143";
    (count r`written) musteq 0;
    (any r[`log] like "resQ: interrupted.*") musteq 1b;
    (any r[`log] like "*TIMEOUT*") musteq 0b;
  };
 };

/ A q that ends in the middle of a run (out of memory under -w, a crash, an
/ exit in a test) writes no report. It named no test either.
.tst.desc["a run that dies in the middle of a test says which #slow"]{
  should["name the test, and the file, that was running"]{
    if[not .tst.testState.interrupt.canRun; :must[1b; "q or timeout unavailable"]];
    wd: .tst.testState.interrupt.workDir[];
    (hsym `$wd, "/test_exit.q") 0: (
        ".tst.desc[\"ends early\"]{";
        "  should[\"is fine\"]{ 1 musteq 1; };";
        "  should[\"quits\"]{ exit 0; };";
        "  should[\"never runs\"]{ 1 musteq 1; };";
        " };");
    cmd: "cd ", .resq.util.shellQuote[wd], " && ", .resq.util.shellQuote[.resq.HOME, "/bin/resq"],
        " test . -state-file out/s.json -flake-history out/f.json -flake-proposal-file out/p.json",
        " < /dev/null > run.log 2>&1; echo exit=$?";
    out: @[system; "sh -c ", .resq.util.shellQuote cmd; {[e] enlist "exit=-1"}];
    (last out) musteq "exit=1";
    shown: read0 hsym `$wd, "/run.log";
    said: first shown where shown like "resQ: the run ended while running*";
    (0 < count ss[said; "'ends early :: quits'"]) musteq 1b;
    (0 < count ss[said; "in test_exit.q"]) musteq 1b;
  };
  should["say nothing of the kind after a run that finished"]{
    if[not .tst.testState.interrupt.canRun; :must[1b; "q or timeout unavailable"]];
    wd: .tst.testState.interrupt.workDir[];
    (hsym `$wd, "/test_ok.q") 0: enlist ".tst.desc[\"fine\"]{ should[\"passes\"]{ 1 musteq 1; }; };";
    cmd: "cd ", .resq.util.shellQuote[wd], " && ", .resq.util.shellQuote[.resq.HOME, "/bin/resq"],
        " test . -state-file out/s.json -flake-history out/f.json -flake-proposal-file out/p.json",
        " < /dev/null > run.log 2>&1; echo exit=$?";
    out: @[system; "sh -c ", .resq.util.shellQuote cmd; {[e] enlist "exit=-1"}];
    (last out) musteq "exit=0";
    shown: read0 hsym `$wd, "/run.log";
    (any shown like "resQ: the run ended*") musteq 0b;
  };
 };

/ The launcher's guard directory is handed on in the environment. A test
/ that starts `q resq.q ...` itself gave it to that second run, which wrote
/ its own markers there: its "complete" stood for the first run.
.tst.desc["a run started inside a test leaves the outer run's guard alone #slow"]{
  should["write none of its markers into it"]{
    if[not .tst.testState.interrupt.canRun; :must[1b; "q or timeout unavailable"]];
    wd: .tst.testState.interrupt.workDir[];
    .resq.util.ensureDir wd, "/inner";
    (hsym `$wd, "/inner/test_inner.q") 0: enlist ".tst.desc[\"inner\"]{ should[\"a\"]{ 1 musteq 1; }; };";
    (hsym `$wd, "/test_outer.q") 0: (
        ".tst.desc[\"outer\"]{";
        "  should[\"runs a resQ of its own\"]{";
        "    guard: getenv `RESQ_RUN_GUARD_DIR;";
        "    had: key hsym `$guard;";
        "    system \"sh -c 'q \", (getenv `RESQ_HOME), \"/resq.q test inner -state-file out/i.json -flake-history out/if.json > inner.log 2>&1; true'\";";
        "    (hsym `$\"guard-after.txt\") 0: string (key hsym `$guard) except had;";
        "    (hsym `$\"guard-owner.txt\") 0: (first read0 hsym `$guard, \"/armed\"; string .z.i);";
        "    1 musteq 1;";
        "  };";
        " };");
    cmd: "cd ", .resq.util.shellQuote[wd], " && ", .resq.util.shellQuote[.resq.HOME, "/bin/resq"],
        " test test_outer.q -state-file out/s.json -flake-history out/f.json -flake-proposal-file out/p.json",
        " < /dev/null > run.log 2>&1; echo exit=$?";
    out: @[system; "sh -c ", .resq.util.shellQuote cmd; {[e] enlist "exit=-1"}];
    (last out) musteq "exit=0";
    / the inner run did run, and passed
    inner: read0 hsym `$wd, "/inner.log";
    (any {[line] 0 < count ss[line; "1 total (1 passed"]} each inner) musteq 1b;
    / and added nothing to the outer run's guard directory
    (count read0 hsym `$wd, "/guard-after.txt") musteq 0;
    owner: read0 hsym `$wd, "/guard-owner.txt";
    (owner 0) musteq owner 1;
  };
 };

