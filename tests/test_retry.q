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

/ Probe q availability once; skipIf each subprocess scenario.
.tst.testState.retrychk.canQ: 0 < count @[system; "which q 2>/dev/null"; {()}];

/ ---------------------------------------------------------------------------
/ (1)-(3) A flaky body runs until it passes; a normal test runs once; hooks
/ run once per attempt. Each is checked by a later suite that reads counters
/ an earlier one left, which holds only in declaration order. Under
/ -random-order (files, suites and tests permuted) they failed, so they run
/ in a child resQ: tests/fixtures/declaration_order/retry_counts.q.
.tst.testState.retrychk.inOrder:{[name]
  wd: .utl.tempRoot[], "/resq_retry_order_", string[.z.i], "_", string `long$.z.p;
  .utl.ensureDir wd;
  fixture: .resq.HOME, "/tests/fixtures/declaration_order/", name;
  cmd: "cd ", .utl.shellQuote[wd], " && timeout -k 2 60 ", .utl.shellQuote[.resq.HOME, "/bin/resq"],
      " test ", .utl.shellQuote[fixture], " -json -outDir out -state-file out/s.json",
      " -flake-history out/f.json -flake-proposal-file out/p.json < /dev/null > out.txt 2>&1; echo $?";
  code: "J"$last @[system; "sh -c ", .utl.shellQuote cmd; {[e] enlist "-1"}];
  raw: @[read0; hsym `$wd, "/out/test-results.json"; {()}];
  rows: $[count raw; (.j.k raze raw)`tests; ()];
  @[system; "rm -rf -- ", .utl.shellQuote wd; {}];
  `code`rows!(code; rows)
 };

.tst.desc["retry: attempts and hooks, counted in declaration order #slow"]{
  skipIf[not .tst.testState.retrychk.canQ; "run each body and hook as often as the attempts say"]{
    r: .tst.testState.retrychk.inOrder "retry_counts.q";
    r[`code] musteq 0;
    statuses: {x`status} each r`rows;
    (count statuses) musteq 8;
    (distinct statuses) musteq enlist "pass";
    attempts: (`$({x`description} each r`rows))!{"j"$x`attempts} each r`rows;
    attempts[`$"increments a counter and passes once it has run twice"] musteq 2;
    attempts[`$"passes on the second attempt"] musteq 2;
    attempts[`$"increment a counter once"] musteq 1;
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
  wd: .utl.tempRoot[], "/resq_retry_", string[.z.i], "_", string `long$.z.p;
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
