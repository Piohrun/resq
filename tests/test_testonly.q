/ ============================================================================
/ Tests for testOnly[desc; code] - the per-suite focus DSL - and the
/ beforeAll/afterAll-outside-a-describe-block warning.
/ .
/ testOnly focus is PER-SUITE: if any expectation in a suite is focused, the
/ non-focused tests in THAT suite become SKIPPED results (they still appear in
/ the results table, so CI shows the suite is focused); other suites run fully.
/ Skips do not count under -strict, so a focused-and-passing test still
/ satisfies -strict (executed count >= 1).
/ .
/ We can't assert a suite's skip/exit behavior from inside the same run, so the
/ checks spawn resQ as a child against a generated fixture and inspect the
/ child's exit code + stdout - the golden-harness idiom (mirrors test_retry.q).
/ Counters live under .tst.testState.* because the pollution guard skips the
/ `tst` namespace, so they survive across desc blocks unrestored.
/ ============================================================================

/ Run resQ in a fresh work dir against a fixture written to disk. Returns
/ `code`out!(exitInt; outLines). `; echo $?` makes the shell exit 0 so q's
/ `system` never throws 'os; we read the real child exit code off stdout.
/ Lead the command with `mkdir`, NOT `cd`/`(`: q intercepts a leading `cd` /
/ rejects a leading `(`, mangling the `&&`-chained command.
.tst.testState.tochk.run:{[extraArgs; fixtureContent]
  wd: "/tmp/resq_testonly_", string[.z.i], "_", string `long$.z.p;
  fix: wd, "/test_fixture.q";
  system "mkdir -p ", wd;
  (hsym `$fix) 0: fixtureContent;
  cmd: "mkdir -p ", wd, " && cd ", wd, " && timeout 60 q ", .resq.HOME, "/resq.q test ", fix,
       " ", extraArgs, " -quiet > out.txt 2>&1; echo $?";
  lines: @[system; cmd; {[e] enlist "-1"}];
  code: "J"$ last lines;
  out: @[read0; hsym `$wd, "/out.txt"; {()}];
  system "rm -rf ", wd;
  `code`out!(code; out)
 };

.tst.testState.tochk.anyLike:{[lines; pat] any lines like ("*", pat, "*") };

/ Probe q availability once; skipIf each subprocess scenario.
.tst.testState.tochk.canQ: 0 < count @[system; "which q 2>/dev/null"; {()}];

/ ---------------------------------------------------------------------------
/ (1) testOnly focuses its suite: only the focused test runs; the two normal
/ shoulds become skipped. The fixture's counters (under .tst.testState.*)
/ prove which bodies executed: focused body bumps `foc`, the normal bodies
/ would bump `norm` -- but they are skipped, so `norm` stays 0. The fixture
/ asserts that itself in a later suite. The PARENT then checks the NOTE line,
/ the "1 passed"/"2 skipped" summary, and exit 0.
/ ---------------------------------------------------------------------------
.tst.desc["testOnly: focuses its own suite, others appear as skipped #slow"]{
  skipIf[not .tst.testState.tochk.canQ;
         "focused test runs, normals skipped, NOTE printed, exit 0"]{
    fixSrc: (
      ".tst.testState.tofix.foc:  0;";
      ".tst.testState.tofix.norm: 0;";
      ".tst.desc[\"focused suite\"]{";
      "  testOnly[\"the focused one\"]{";
      "    .tst.testState.tofix.foc: 1 + .tst.testState.tofix.foc;";
      "    1 musteq 1;";
      "  };";
      "  should[\"normal one\"]{";
      "    .tst.testState.tofix.norm: 1 + .tst.testState.tofix.norm;";
      "    1 musteq 1;";
      "  };";
      "  should[\"normal two\"]{";
      "    .tst.testState.tofix.norm: 1 + .tst.testState.tofix.norm;";
      "    1 musteq 1;";
      "  };";
      " };";
      ".tst.desc[\"counter verification\"]{";
      "  should[\"focused body ran exactly once\"]{ .tst.testState.tofix.foc musteq 1 };";
      "  should[\"normal bodies never ran (skipped)\"]{ .tst.testState.tofix.norm musteq 0 };";
      " };");
    r: .tst.testState.tochk.run["";fixSrc];
    musteq[r`code; 0];
    must[.tst.testState.tochk.anyLike[r`out; "NOTE: testOnly active"];
         "a NOTE about the focused suite should be printed"];
    must[.tst.testState.tochk.anyLike[r`out; "running 1 of 3 tests"];
         "the NOTE should report 1 of 3 tests in the focused suite"];
    / 3 focused-suite tests (1 pass + 2 skip) + 2 verification passes = 5 total,
    / 3 passed, 2 skipped.
    must[.tst.testState.tochk.anyLike[r`out; "3 passed"];
         "focused + 2 verification tests pass"];
    must[.tst.testState.tochk.anyLike[r`out; "2 skipped"];
         "the two non-focused tests are reported as skipped"];
  };
 };

/ ---------------------------------------------------------------------------
/ (2) A second suite in the same fixture WITHOUT testOnly runs fully. Proven by
/ a counter the unfocused suite bumps twice; a later verification suite asserts
/ it reached 2 (would be 0/skipped if focus leaked across suites).
/ ---------------------------------------------------------------------------
.tst.desc["testOnly: a sibling suite without testOnly runs fully #slow"]{
  skipIf[not .tst.testState.tochk.canQ;
         "unfocused sibling suite executes all its tests, exit 0"]{
    fixSrc: (
      ".tst.testState.tofix2.unfoc: 0;";
      ".tst.desc[\"focused suite\"]{";
      "  testOnly[\"focus here\"]{ 1 musteq 1 };";
      "  should[\"skipped in this suite\"]{ 1 musteq 1 };";
      " };";
      ".tst.desc[\"unfocused sibling\"]{";
      "  should[\"runs a\"]{ .tst.testState.tofix2.unfoc: 1 + .tst.testState.tofix2.unfoc; 1 musteq 1 };";
      "  should[\"runs b\"]{ .tst.testState.tofix2.unfoc: 1 + .tst.testState.tofix2.unfoc; 1 musteq 1 };";
      " };";
      ".tst.desc[\"verify sibling ran fully\"]{";
      "  should[\"both unfocused bodies executed\"]{ .tst.testState.tofix2.unfoc musteq 2 };";
      " };");
    r: .tst.testState.tochk.run["";fixSrc];
    musteq[r`code; 0];
    must[.tst.testState.tochk.anyLike[r`out; "running 1 of 2 tests"];
         "only the focused suite reports a focus NOTE (1 of 2)"];
    must[not .tst.testState.tochk.anyLike[r`out; "unfocused sibling'"];
         "the unfocused sibling suite must NOT emit a focus NOTE"];
    must[.tst.testState.tochk.anyLike[r`out; "All tests passed"];
         "the whole run passes"];
  };
 };

/ ---------------------------------------------------------------------------
/ (3) testOnly + -strict: a focused test that passes satisfies -strict because
/ at least one expectation EXECUTED (skips do not count, but the focused test
/ does). Exit 0.
/ ---------------------------------------------------------------------------
.tst.desc["testOnly: focused passing test satisfies -strict #slow"]{
  skipIf[not .tst.testState.tochk.canQ;
         "testOnly + -strict exits 0 (executed count >= 1)"]{
    fixSrc: (
      ".tst.desc[\"focused under strict\"]{";
      "  testOnly[\"this one runs\"]{ 1 musteq 1 };";
      "  should[\"this one is skipped\"]{ 1 musteq 1 };";
      " };");
    r: .tst.testState.tochk.run["-strict"; fixSrc];
    musteq[r`code; 0];
    must[.tst.testState.tochk.anyLike[r`out; "NOTE: testOnly active"];
         "focus NOTE still printed under -strict"];
    must[not .tst.testState.tochk.anyLike[r`out; "STRICT_MODE_FAILURE"];
         "strict mode must NOT fail: the focused test executed"];
    must[.tst.testState.tochk.anyLike[r`out; "All tests passed"];
         "the run passes under -strict"];
  };
 };

/ ---------------------------------------------------------------------------
/ (4) beforeAll defined OUTSIDE a describe block prints a WARNING and the suite
/ still passes (the stray hook is simply ignored, not fatal). Same for afterAll.
/ ---------------------------------------------------------------------------
.tst.desc["beforeAll/afterAll outside a describe block warns, suite still passes #slow"]{
  skipIf[not .tst.testState.tochk.canQ;
         "stray beforeAll/afterAll -> WARNING printed, exit 0"]{
    fixSrc: (
      "beforeAll{ 1+1 };";
      "afterAll{ 1+1 };";
      ".tst.desc[\"a normal suite\"]{";
      "  should[\"passes fine\"]{ 1 musteq 1 };";
      " };");
    r: .tst.testState.tochk.run["";fixSrc];
    musteq[r`code; 0];
    must[.tst.testState.tochk.anyLike[r`out; "WARNING: beforeAll defined outside a describe block is ignored"];
         "a stray beforeAll should warn"];
    must[.tst.testState.tochk.anyLike[r`out; "WARNING: afterAll defined outside a describe block is ignored"];
         "a stray afterAll should warn"];
    must[.tst.testState.tochk.anyLike[r`out; "All tests passed"];
         "the suite still passes despite the ignored hooks"];
  };
 };
