/ Nightly compiler-boundary contract. This deliberately asks q to parse a desc
/ body beyond its per-lambda capacity and can take roughly one minute. The pure
/ diagnostic mapping is tested cheaply in tests/test_load_error.q; this file
/ proves the real runtime still reaches that mapping.
.tst.testState.limitchk.canQ: 0 < count @[system; "which q 2>/dev/null"; {()}];

.tst.desc["nightly oversized desc compiler boundary"]{
  skipIf[not .tst.testState.limitchk.canQ;
         "a desc block past q's lambda capacity explains itself"]{
    wd:.utl.tempRoot[], "/resq_limit_", string[.z.i], "_", string `long$.z.p;
    fix:wd, "/test_big.q";
    .utl.ensureDir wd;
    body:enlist ".tst.desc[\"too big\"]{";
    body,:{[i] "  should[\"t",string[i],"\"]{ 1 musteq 1 };"} each til 150;
    body,:enlist " };";
    (hsym `$fix) 0:body;

    cmd:"true && timeout 60 q ",(.utl.shellQuote .resq.HOME,"/resq.q"),
        " test ",(.utl.shellQuote fix)," -quiet > ",
        (.utl.shellQuote wd,"/out.txt")," 2>&1; echo $?";
    code:"J"$last @[system;cmd;{[e]enlist "-1"}];
    out:@[read0;hsym `$wd,"/out.txt";{()}];
    system "rm -rf -- ",.utl.shellQuote wd;

    must[0<>code;"an unloadable file must fail the run"];
    must[any out like "*desc block is a single q lambda*";
         "the error must name the real cause"];
    must[any out like "*Split it into several desc blocks*";
         "the error must state the fix"];
  };
 };
