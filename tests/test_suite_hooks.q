/ Suite-level hook wiring: beforeAll / afterAll.
/ State lives under .tst.testState.* because the pollution guard skips the
/ `tst` namespace (runner.q: `except `q`Q`j`h`o`s`v`z`tst`resq`utl`), so we can
/ carry counters across a suite's tests and across desc blocks without the
/ guard restoring/warning on them.

/ ---------------------------------------------------------------------------
/ (1) beforeAll runs exactly once for a multi-test suite.
/ The beforeAll increments a counter; both tests assert it is still 1,
/ proving beforeAll fired once before the expectations and not per-test.
.tst.desc["beforeAll runs once per suite"]{
  beforeAll{
    .tst.testState.hookcheck.beforeAllRuns: 1 + @[get; `.tst.testState.hookcheck.beforeAllRuns; 0];
  };

  should["have run beforeAll before the first test"]{
    .tst.testState.hookcheck.beforeAllRuns musteq 1;
  };

  should["not re-run beforeAll for the second test"]{
    .tst.testState.hookcheck.beforeAllRuns musteq 1;
  };
 };

/ ---------------------------------------------------------------------------
/ (2) afterAll runs once after all tests of its suite.
/ desc blocks run in definition order (runner.q runDiscoveredSpecs iterates
/ .tst.app.allSpecs, populated by descLoaded in definition order), so the
/ second suite can assert what the first suite's afterAll recorded.
.tst.desc["afterAll records completion"]{
  afterAll{
    .tst.testState.hookcheck.afterAllRuns: 1 + @[get; `.tst.testState.hookcheck.afterAllRuns; 0];
  };

  should["pass a trivial assertion"]{ 1 musteq 1 };
  should["pass another trivial assertion"]{ 2 musteq 2 };
 };

.tst.desc["afterAll from the previous suite ran exactly once"]{
  should["see afterAllRuns == 1 from the prior suite"]{
    (@[get; `.tst.testState.hookcheck.afterAllRuns; 0]) musteq 1;
  };

  should["clean up the hookcheck state"]{
    / Remove our scratch state so it does not leak between runs.
    @[{![`.tst.testState; (); 0b; enlist `hookcheck]}; (); {}];
    1 musteq 1;
  };
 };
