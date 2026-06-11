/ ============================================================================
/ Tests for retry[n; desc; code] - the flaky-test retry DSL.
/ .
/ retry[n;...] gives an expectation up to n+1 total attempts. The first attempt
/ that passes wins; only the final attempt is recorded (one results row). The
/ full before+test+after cycle re-runs each attempt so flaky state is reset.
/ .
/ Counters live under .tst.testState.* because the pollution guard skips the
/ `tst` namespace (runner.q: `except `q`Q`j`h`o`s`v`z`tst`resq`utl`), so they
/ survive across attempts and across desc blocks without the guard restoring
/ them or warning.
/ ============================================================================

/ ---------------------------------------------------------------------------
/ (1) flaky-passes-eventually: the test body increments an attempt counter and
/ only passes once it has run at least twice. With retry[3;...] it must PASS,
/ and the counter proves at least 2 attempts ran (it failed the first time).
.tst.testState.retrychk.a: 0;
.tst.desc["retry: flaky test passes on a later attempt"]{
  retry[3; "increments a counter and passes once it has run twice"]{
    .tst.testState.retrychk.a: 1 + .tst.testState.retrychk.a;
    must[.tst.testState.retrychk.a >= 2; "needs >= 2 attempts"];
  };

  / Runs after the retry above (same suite, definition order). By now the flaky
  / test has passed, having run exactly 2 attempts (failed once, passed once).
  should["have run the flaky body exactly twice"]{
    .tst.testState.retrychk.a musteq 2;
  };
 };

/ ---------------------------------------------------------------------------
/ (2) retries=0 runs the body exactly once - zero behavior change. Every normal
/ test takes this path, so be paranoid: a plain should[] must NOT loop.
.tst.testState.retrychk.once: 0;
.tst.desc["retry: a normal (retries=0) test runs its body exactly once"]{
  should["increment a counter once"]{
    .tst.testState.retrychk.once: 1 + .tst.testState.retrychk.once;
    1 musteq 1;
  };

  should["see the counter at exactly 1"]{
    .tst.testState.retrychk.once musteq 1;
  };
 };

/ ---------------------------------------------------------------------------
/ (3) before/after hooks re-run per attempt. The flaky body passes on attempt 2,
/ so the before/after hooks each fire exactly twice for that one retry test.
/ The retry test lives in its OWN suite with no sibling expectations - suite
/ before/after fire once per test in the suite, so a sibling would inflate the
/ counts. A SEPARATE later suite then asserts the recorded counts (desc blocks
/ run in definition order, so by then the retry suite has finished).
.tst.testState.retrychk.b: 0;
.tst.testState.retrychk.c: 0;
.tst.testState.retrychk.body: 0;
.tst.desc["retry: before/after hooks re-run on every attempt"]{
  before{ .tst.testState.retrychk.b: 1 + .tst.testState.retrychk.b };
  after{  .tst.testState.retrychk.c: 1 + .tst.testState.retrychk.c };

  retry[3; "passes on the second attempt"]{
    .tst.testState.retrychk.body: 1 + .tst.testState.retrychk.body;
    must[.tst.testState.retrychk.body >= 2; "needs >= 2 attempts"];
  };
 };

.tst.desc["retry: hooks/body fired once per attempt (verification)"]{
  should["have run the retry body exactly twice (2 attempts)"]{
    .tst.testState.retrychk.body musteq 2;
  };
  should["have run before exactly twice (once per attempt)"]{
    .tst.testState.retrychk.b musteq 2;
  };
  should["have run after exactly twice (once per attempt)"]{
    .tst.testState.retrychk.c musteq 2;
  };
 };

/ ---------------------------------------------------------------------------
/ (4) Subprocess golden checks (#slow): an always-failing retry[2;...] suite
/ must exit 1, print "failed after 3 attempts", and record exactly ONE results
/ row (summary "1 total", never "3 total"). We can't assert a suite failure from
/ inside the same run, so spawn resQ as a child against a generated fixture and
/ inspect its exit code + stdout - the golden-harness idiom, inlined here.

/ Run resQ in a fresh work dir against a fixture written to disk.
/ Returns `code`out!(exitInt; outLines). `; echo $?` makes the shell exit 0 so
/ q's `system` never throws 'os; we read the real child exit code off stdout.
.tst.testState.retrychk.run:{[fixtureContent]
  wd: "/tmp/resq_retry_", string[.z.i], "_", string `long$.z.p;
  fix: wd, "/test_fixture.q";
  system "mkdir -p ", wd;
  (hsym `$fix) 0: fixtureContent;
  / Lead the shell command with `mkdir`, NOT `cd`: q intercepts a `system "cd ..."`
  / call to change its OWN working dir, which mangles the `&&`-chained command.
  cmd: "mkdir -p ", wd, " && cd ", wd, " && timeout 60 q ", .resq.HOME, "/resq.q test ", fix,
       " -quiet > out.txt 2>&1; echo $?";
  lines: @[system; cmd; {[e] enlist "-1"}];
  code: "J"$ last lines;
  out: @[read0; hsym `$wd, "/out.txt"; {()}];
  system "rm -rf ", wd;
  `code`out!(code; out)
 };

.tst.testState.retrychk.anyLike:{[lines; pat] any lines like ("*", pat, "*") };

/ Probe q availability once; skipIf each subprocess scenario.
.tst.testState.retrychk.canQ: 0 < count @[system; "which q 2>/dev/null"; {()}];

.tst.desc["retry: always-failing retry suite, subprocess checks #slow"]{

  skipIf[not .tst.testState.retrychk.canQ;
         "always-fail retry[2] exits 1, says 'failed after 3 attempts', 1 row"]{
    fixSrc: (
      ".tst.desc[\"alwaysfail\"]{";
      "  retry[2; \"never passes\"]{ must[0b; \"always fails\"] };";
      " };");
    r: .tst.testState.retrychk.run fixSrc;
    musteq[r`code; 1];
    must[.tst.testState.retrychk.anyLike[r`out; "failed after 3 attempts"];
         "failures should be annotated with the attempt count"];
    / Exactly one results row: summary says "1 total", never "3 total".
    must[.tst.testState.retrychk.anyLike[r`out; "1 total"];
         "exactly one result row should be recorded (1 total)"];
    must[not .tst.testState.retrychk.anyLike[r`out; "3 total"];
         "retries must not produce duplicate result rows (no 3 total)"];
  };

  skipIf[not .tst.testState.retrychk.canQ;
         "flaky retry that passes late exits 0 and prints a NOTE"]{
    fixSrc: (
      ".tst.testState.retryfix.n: 0;";
      ".tst.desc[\"flaky\"]{";
      "  retry[3; \"passes on attempt 2\"]{";
      "    .tst.testState.retryfix.n: 1 + .tst.testState.retryfix.n;";
      "    must[.tst.testState.retryfix.n >= 2; \"needs 2 attempts\"];";
      "  };";
      " };");
    r: .tst.testState.retrychk.run fixSrc;
    musteq[r`code; 0];
    must[.tst.testState.retrychk.anyLike[r`out; "1 total (1 passed"];
         "should summarize one passing test"];
    must[.tst.testState.retrychk.anyLike[r`out; "passed on attempt 2"];
         "a NOTE about the late pass should be printed"];
  };
 };
