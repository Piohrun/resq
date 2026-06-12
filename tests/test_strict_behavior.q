/ ============================================================================
/ Subprocess golden checks for -strict suite-execution gating (#slow).
/ .
/ Bug: .tst.runAllPhase.applyStrictMode gated on `0 = .tst.app.expectationsRan`,
/ but expectationsRan increments for SKIPPED tests too. A suite that is entirely
/ skip[] therefore exited 0 under -strict despite executing ZERO assertions.
/ Fix gates on the executed counters (passed+failed+errored), which a skip never
/ bumps. We cannot assert another run's exit code from inside this run, so spawn
/ resQ as a child against a generated fixture and inspect exit code + stdout.
/ ============================================================================

/ Run resQ in a fresh work dir against a fixture written to disk. `; echo $?`
/ makes the shell exit 0 so q's `system` never throws 'os; we read the real
/ child exit code off the last stdout line. (Idiom copied from test_retry.q.)
.tst.testState.strictchk.run:{[fixtureContent; extraFlags]
  wd: "/tmp/resq_strict_", string[.z.i], "_", string `long$.z.p;
  fix: wd, "/test_fixture.q";
  system "mkdir -p ", wd;
  (hsym `$fix) 0: fixtureContent;
  / Lead with mkdir, NOT cd: q intercepts `system "cd ..."` for its own dir,
  / which would mangle the &&-chained command.
  cmd: "mkdir -p ", wd, " && cd ", wd, " && timeout 60 q ", .resq.HOME, "/resq.q test ", fix,
       " ", extraFlags, " -quiet > out.txt 2>&1; echo $?";
  lines: @[system; cmd; {[e] enlist "-1"}];
  code: "J"$ last lines;
  out: @[read0; hsym `$wd, "/out.txt"; {()}];
  system "rm -rf ", wd;
  `code`out!(code; out)
 };

.tst.testState.strictchk.anyLike:{[lines; pat] any lines like ("*", pat, "*") };

/ Probe q availability once; skipIf each subprocess scenario.
.tst.testState.strictchk.canQ: 0 < count @[system; "which q 2>/dev/null"; {()}];

/ An all-skip suite: every expectation is skip[], so zero assertions execute.
.tst.testState.strictchk.allSkip: (
  ".tst.desc[\"all skipped\"]{";
  "  skip[\"not run a\"]{ must[0b; \"never evaluated\"] };";
  "  skip[\"not run b\"]{ must[0b; \"never evaluated\"] };";
  " };");

/ A normal passing suite.
.tst.testState.strictchk.passing: (
  ".tst.desc[\"passing\"]{";
  "  should[\"add\"]{ 2 musteq 1 + 1 };";
  " };");

.tst.desc["strict: all-skipped suite gating, subprocess checks #slow"]{

  skipIf[not .tst.testState.strictchk.canQ;
         "all-skip suite under -strict exits nonzero with the strict message"]{
    r: .tst.testState.strictchk.run[.tst.testState.strictchk.allSkip; "-strict"];
    must[0 <> r`code; "an all-skip suite must FAIL under -strict (exit nonzero)"];
    must[.tst.testState.strictchk.anyLike[r`out; "skipped tests do not count"];
         "the synthetic strict failure must explain skips do not count"];
  };

  skipIf[not .tst.testState.strictchk.canQ;
         "all-skip suite WITHOUT -strict exits 0"]{
    r: .tst.testState.strictchk.run[.tst.testState.strictchk.allSkip; ""];
    musteq[r`code; 0];
  };

  skipIf[not .tst.testState.strictchk.canQ;
         "normal passing suite under -strict exits 0"]{
    r: .tst.testState.strictchk.run[.tst.testState.strictchk.passing; "-strict"];
    musteq[r`code; 0];
  };
 };
