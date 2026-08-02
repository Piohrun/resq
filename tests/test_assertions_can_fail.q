/ ============================================================================
/ Every assertion must be CAPABLE of failing.
/ .
/ A verb that can never fail is a silent no-op wearing the costume of a check.
/ mustBeFasterThan was exactly that for as long as the benchmark never executed
/ its subject: it looked like a performance gate, ran green, and asserted
/ nothing. A timing or a green tick does not reveal that; only feeding each verb
/ a clearly-false case does.
/ ============================================================================
.tst.desc["every assertion can fail"]{
  should["register a failure for a clearly-false case"]{
    probe: {[lbl;f]
        old: .tst.assertState.failures;
        r: @[{[g] g[]; `ran}; f; {`$"THREW"}];
        n: (count .tst.assertState.failures) - count old;
        .tst.assertState.failures: old;
        must[n > 0;
             "assertion `", lbl, "` did not register a failure for a clearly-false case",
             $[r ~ `THREW; " (it threw instead)"; ""]];
        };
    probe["must";            {must[0b; "m"]}];
    probe["musteq";          {musteq[1; 2]}];
    probe["mustne";          {mustne[1; 1]}];
    probe["mustmatch";       {mustmatch[1; 2]}];
    probe["mustnmatch";      {mustnmatch[1; 1]}];
    probe["mustlt";          {mustlt[2; 1]}];
    probe["mustgt";          {mustgt[1; 2]}];
    probe["mustlike";        {mustlike["abc"; "z*"]}];
    probe["mustin";          {mustin[9; 1 2 3]}];
    probe["mustnin";         {mustnin[2; 1 2 3]}];
    probe["mustwithin";      {mustwithin[99; 1 2]}];
    probe["mustdelta";       {mustdelta[0.001; 5; 9]}];
    probe["mustthrow";       {mustthrow["*x*"; {1+1}]}];
    probe["mustnotthrow";    {mustnotthrow[(); {'"boom"}]}];
    probe["mustmatchignoringorder"; {mustmatchignoringorder[1 2 3; 4 5 6]}];
    probe["mustincludecols"; {mustincludecols[([]a:1 2); ([]zzz:1 2)]}];
    probe["mustBeFasterThan";{mustBeFasterThan[{asc 50000?1000}; 0.0000001]}];
    probe["mustAllocLessThan";{mustAllocLessThan[{til 500000}; 1]}];
    probe["mustHaveBeenCalledWith"; {
        .tst.testState.cf.f: {[a] a};
        .tst.spy[`.tst.testState.cf.f; (::)];
        .tst.testState.cf.f 1;
        mustHaveBeenCalledWith[`.tst.testState.cf.f; enlist 999]}];
  };
};
