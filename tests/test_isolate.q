/ ============================================================================
/ tests/test_isolate.q - end-to-end tests for `resq test -isolate`.
/ .
/ Runs resQ ITSELF as a subprocess (mirroring tests/golden/test_golden.q) with
/ -isolate, against fixtures GENERATED AT RUNTIME under /tmp (never under
/ tests/, so discovery never picks them up). Each scenario asserts on summary
/ output lines AND the parent exit code.
/ .
/ Subprocess idiom: q's `system "cmd"` THROWS on a nonzero child exit and
/ INTERCEPTS a leading "cd"; so the command LEADS with `mkdir -p`, appends
/ `; echo $?` (shell exits 0; real code is the last stdout line) and feeds the
/ nested q `< /dev/null`. #slow: this harness spawns several q subprocesses.
/ .
/ Authoring note: long should-bodies can hit value's nested-block 'assign limit
/ and a local named `desc`/`fixture`/`prev` collides with a DSL global - so
/ bodies are kept compact and use short, distinct local names.
/ ============================================================================

\d .tst

/ Probe q + timeout ONCE (skipIf each scenario).
.tst.isotest.canQ: 0 < count @[system; "which q 2>/dev/null"; {()}];
.tst.isotest.canTimeout: 0 < count @[system; "which timeout 2>/dev/null"; {()}];

/ Unique work dir per call (pid + counter; no randomness needed).
.tst.isotest.base: "/tmp/resq_isolate_test";
.tst.isotest.counter: 0;
.tst.isotest.workDir:{[]
    .tst.isotest.counter+: 1;
    .tst.isotest.base, "/run_", string[.z.i], "_", string .tst.isotest.counter
 };

/ Write a fixture file (string lines) and return its absolute path.
.tst.isotest.writeFixture:{[wd; name; lines]
    @[system; "mkdir -p ", .utl.shellQuote wd; {}];
    p: wd, "/", name;
    (hsym `$p) 0: lines;
    p
 };

/ Run `resq.q test <args> -isolate ...` in a fresh work dir.
/ Returns `code`out!(exitInt; outLines). `args` is the full arg string after
/ `resq.q test `.
.tst.isotest.run:{[args]
    wd: .tst.isotest.workDir[];
    / Pre-quote each path into its OWN local first. q is right-to-left, so
    / `.utl.shellQuote wd, " && ..."` would quote the WHOLE concatenation as one
    / argument - quote in a separate step so the closing quote stays on the path.
    qWd:   .utl.shellQuote wd;
    qHome: .utl.shellQuote .resq.HOME, "/resq.q";
    qOut:  .utl.shellQuote wd, "/parent_out.txt";
    / -isolate is always added here so every scenario exercises isolation mode.
    cmd: "mkdir -p ", qWd,
         " && q ", qHome, " test ", args, " -isolate",
         " < /dev/null > ", qOut, " 2>&1; echo $?";
    lines: @[system; cmd; {[e] enlist "-1"}];
    code: "J"$ last lines;
    out: @[read0; hsym `$wd, "/parent_out.txt"; {()}];
    `code`out!(code; out)
 };

.tst.isotest.anyLike:{[lines; pat] any lines like ("*", pat, "*") };

\d .

/ Fixture bodies, kept compact (one desc + small shoulds per file).
.tst.isotest.fxPass1: enlist ".tst.desc[\"iso pass one\"]{ should[\"a\"]{ musteq[1+1; 2] }; should[\"b\"]{ must[1b; \"t\"] }; };";
.tst.isotest.fxPass2: enlist ".tst.desc[\"iso pass two\"]{ should[\"c\"]{ musteq[2*2; 4] }; };";
.tst.isotest.fxFail:  enlist ".tst.desc[\"iso fail\"]{ should[\"bad\"]{ musteq[1; 2] }; };";
.tst.isotest.fxExit:  enlist ".tst.desc[\"iso exiter\"]{ should[\"quits\"]{ exit 0 }; };";
.tst.isotest.fxHang:  enlist ".tst.desc[\"iso hang\"]{ should[\"loops\"]{ while[1b;()] }; };";
.tst.isotest.fxLoad:  ("undefinedTopLevelName[42];"; ".tst.desc[\"iso never\"]{ should[\"x\"]{ must[1b; \"t\"] }; };");

.tst.desc["Isolate: per-file subprocess isolation #slow"]{
  / Each scenario asserts before after fires; rm -rf the exact literal prefix.
  after{ system "rm -rf /tmp/resq_isolate_test" };

  / 1. Two passing files -> exit 0, summary counts both files' tests (3 total).
  skipIf[not .tst.isotest.canQ; "two passing files: exit 0, both counted"]{
    wd: .tst.isotest.workDir[];
    fa: .tst.isotest.writeFixture[wd; "test_a.q"; .tst.isotest.fxPass1];
    fb: .tst.isotest.writeFixture[wd; "test_b.q"; .tst.isotest.fxPass2];
    r: .tst.isotest.run[.utl.shellQuote[fa], " ", .utl.shellQuote[fb], " -quiet"];
    musteq[r`code; 0];
    must[.tst.isotest.anyLike[r`out; "3 total (3 passed"]; "should report 3 passing tests across both files"];
  };

  / 2. Passing + failing -> exit 1, failing test's message visible.
  skipIf[not .tst.isotest.canQ; "passing + failing file: exit 1, message visible"]{
    wd: .tst.isotest.workDir[];
    fa: .tst.isotest.writeFixture[wd; "test_a.q"; .tst.isotest.fxPass1];
    fb: .tst.isotest.writeFixture[wd; "test_f.q"; .tst.isotest.fxFail];
    r: .tst.isotest.run[.utl.shellQuote[fa], " ", .utl.shellQuote[fb], " -quiet"];
    musteq[r`code; 1];
    must[.tst.isotest.anyLike[r`out; "Got 1 — expected 2"]; "failing assertion message should surface in parent summary"];
  };

  / 3. A file whose test calls `exit 0` -> exit 1, "without producing results".
  skipIf[not .tst.isotest.canQ; "exit-0 file: caught as failure, not green-washed"]{
    wd: .tst.isotest.workDir[];
    fe: .tst.isotest.writeFixture[wd; "test_e.q"; .tst.isotest.fxExit];
    fb: .tst.isotest.writeFixture[wd; "test_b.q"; .tst.isotest.fxPass2];
    r: .tst.isotest.run[.utl.shellQuote[fe], " ", .utl.shellQuote[fb], " -quiet"];
    musteq[r`code; 1];
    must[.tst.isotest.anyLike[r`out; "without producing results"]; "exit-0 file should be flagged, not faked as success"];
    / The per-file progress line is printed even under -quiet, so it proves the
    / second file still ran (its passing suite is hidden from the quiet summary).
    must[.tst.isotest.anyLike[r`out; "[2/2]"] and .tst.isotest.anyLike[r`out; "ok (1 tests)"]; "subsequent passing file should still have run"];
  };

  / 4. Infinite loop (hang file FIRST) + -isolateTimeout 3 -> exit 1 in
  / reasonable wall time, TIMEOUT reported, subsequent passing file still ran.
  / Requires `timeout` for preemption (q ignores SIGTERM in a tight loop, so
  / the harness uses `timeout -k`); skip when absent.
  skipIf[(not .tst.isotest.canQ) or not .tst.isotest.canTimeout; "hanging file killed by isolateTimeout, run continues"]{
    wd: .tst.isotest.workDir[];
    fh: .tst.isotest.writeFixture[wd; "test_h.q"; .tst.isotest.fxHang];
    fb: .tst.isotest.writeFixture[wd; "test_b.q"; .tst.isotest.fxPass2];
    t0: .z.p;
    r: .tst.isotest.run[.utl.shellQuote[fh], " ", .utl.shellQuote[fb], " -isolateTimeout 3 -quiet"];
    elapsed: `long$(.z.p - t0) % 1000000000;
    musteq[r`code; 1];
    must[elapsed < 30; "should finish well within wall-clock budget (timeout preempts the hang)"];
    must[.tst.isotest.anyLike[r`out; "TIMEOUT"] or .tst.isotest.anyLike[r`out; "exceeded isolateTimeout"]; "hang should be reported as a timeout"];
    / Progress line proves the post-hang file ran (passing suite hidden by -quiet).
    must[.tst.isotest.anyLike[r`out; "[2/2]"] and .tst.isotest.anyLike[r`out; "ok (1 tests)"]; "the passing file after the hang should still run"];
  };

  / 5. A load-error file -> exit 4.
  skipIf[not .tst.isotest.canQ; "load-error file: exit 4"]{
    wd: .tst.isotest.workDir[];
    fa: .tst.isotest.writeFixture[wd; "test_a.q"; .tst.isotest.fxPass1];
    fl: .tst.isotest.writeFixture[wd; "test_l.q"; .tst.isotest.fxLoad];
    r: .tst.isotest.run[.utl.shellQuote[fa], " ", .utl.shellQuote[fl], " -quiet"];
    musteq[r`code; 4];
  };

  / 6. Parent -junit: merged XML parses, testcases counted across both files.
  skipIf[not .tst.isotest.canQ; "parent -junit: merged XML has testcases from both files"]{
    wd: .tst.isotest.workDir[];
    fa: .tst.isotest.writeFixture[wd; "test_a.q"; .tst.isotest.fxPass1];
    fb: .tst.isotest.writeFixture[wd; "test_b.q"; .tst.isotest.fxPass2];
    xmlDir: wd, "/xml";
    r: .tst.isotest.run[.utl.shellQuote[fa], " ", .utl.shellQuote[fb], " -junit -outDir ", .utl.shellQuote[xmlDir], " -quiet"];
    xml: @[read0; hsym `$xmlDir, "/test-results.xml"; {()}];
    must[0 < count xml; "junit XML report should be written from the parent merge"];
    nCases: sum sum each xml like "*<testcase*";
    musteq[nCases; 3i];
  };
 };
