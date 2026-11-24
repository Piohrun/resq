/ Suites that check what an earlier suite in this file did: retry's attempt
/ and hook counts. resQ runs suites, and the tests in them, in any order
/ under -random-order, so tests/test_retry.q runs this file in a child resQ
/ of its own, where declaration order holds.

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
