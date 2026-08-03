.tst.desc["Parametrize Combinatorial Tests"]{
 should["generate Cartesian product for 2 params"]{
  .tst.paramResults: ();
  .tst.parametrize[`a`b!(1 2; 10 20); {[a;b] .tst.paramResults,: enlist (a;b)}];
  count[.tst.paramResults] musteq 4;
  .tst.paramResults mustmatchignoringorder (1 10; 1 20; 2 10; 2 20);
  };
 should["work with single parameter"]{
  .tst.paramResults: ();
  .tst.parametrize[enlist[`x]!enlist 1 2 3; {[x] .tst.paramResults,: x}];
  count[.tst.paramResults] musteq 3;
  .tst.paramResults mustmatch 1 2 3;
  };
 should["work with 3 parameters"]{
  .tst.paramResults: ();
  .tst.parametrize[`x`y`z!(1 2; 10 20; 100 200); {[x;y;z] .tst.paramResults,: enlist (x;y;z)}];
  count[.tst.paramResults] musteq 8;
  (1;10;100) mustin .tst.paramResults;
  (2;20;200) mustin .tst.paramResults;
  };
 should["pass params correctly to test function"]{
  code: {[a;b] result: a + b; result mustgt 0; result mustlt 20};
  .tst.parametrize[`a`b!(5 10; 2 3); code];
  };
 should["run every row and preserve assertion failures with param values"]{
  oldFailures: .tst.assertState.failures;
  oldAsserts: .tst.assertState.assertsRun;
  .tst.parametrize[`x!(99 1 100 2); {[x] x mustlt 10}];
  caseAssertions: .tst.assertState.assertsRun - oldAsserts;
  testedFailures: (count oldFailures) _ .tst.assertState.failures;
  .tst.assertState.failures: oldFailures;

  / Rows after the first failure must still execute, and both failures retain
  / the ordinary assertion diagnostic instead of becoming a generic error.
  caseAssertions musteq 4;
  count[testedFailures] musteq 2;
  (first testedFailures) mustlike "*less than 10*";
  (first testedFailures) mustlike "*Params: x=99*";
  (last testedFailures) mustlike "*Params: x=100*";
  };
 should["not signal a stale pre-existing failure on first forall row"]{
  / Regression for forall precedence bug (parametrize.q:21).
  / Seed a pre-existing failure entry, then run forall over all-passing
  / rows. The buggy `count a > count b` parse would count a boolean
  / vector and spuriously throw naming the STALE failure on row 1.
  saved: .tst.assertState.failures;
  .tst.assertState.failures,: enlist "stale";
  res: @[{.tst.forall[([] x: 1 2 3); {[x] :1b}]}; (::); {("THREW: "),x}];
  / Restore state BEFORE asserting so this test's own pass/fail is clean.
  .tst.assertState.failures: saved;
  threw: $[10h = type res; res like "THREW: *"; 0b];
  threw musteq 0b;
  };
 };

::
