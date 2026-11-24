/ Suites that check what an earlier suite in this file did. resQ runs
/ files, suites and the tests in them in any order under -random-order, so
/ tests/test_suite_hooks.q runs this file in a child resQ of its own, where declaration
/ order holds.

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
