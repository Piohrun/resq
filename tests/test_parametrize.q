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
 should["annotate failures with param values"]{
  code: { .tst.parametrize[`x!(1 2 3 99); {[x] x mustlt 10}] };
  mustthrow["*Params:*"; code];
  };
 };

::
