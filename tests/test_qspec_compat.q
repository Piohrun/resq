/ ============================================================================
/ The qspec compatibility CONTRACT, checked end to end.
/ .
/ tests/compat/test_qspec_surface.q pins the surface that must work in every
/ mode. This file pins the switch itself: a suite using qspec's ORIGINAL
/ assertion semantics must pass under -qspec-compat and fail without it, and
/ the failure must tell the reader why.
/ .
/ Subprocess-based, because a run cannot assert another run's exit code.
/ (Idiom from test_retry.q.)
/ ============================================================================
.tst.testState.qcompat.run:{[fixtureContent; extraFlags]
  wd: .utl.tempRoot[], "/resq_qcompat_", string[.z.i], "_", string `long$.z.p;
  fix: wd, "/test_fixture.q";
  system "mkdir -p ", wd;
  (hsym `$fix) 0: fixtureContent;
  / Lead with mkdir, NOT cd: q intercepts a leading `system "cd ..."`.
  cmd: "mkdir -p ", wd, " && cd ", wd, " && timeout 60 q ", .resq.HOME, "/resq.q -q test ", fix,
       " ", extraFlags, " -quiet > out.txt 2>&1; echo $?";
  lines: @[system; cmd; {[e] enlist "-1"}];
  code: "J"$ last lines;
  out: @[read0; hsym `$wd, "/out.txt"; {()}];
  system "rm -rf -- ", .utl.shellQuote wd;
  `code`out!(code; out)
 };

.tst.testState.qcompat.runLauncher:{[fixtureContent; extraFlags]
  wd: .utl.tempRoot[], "/resq_qspec_launcher_", string[.z.i], "_", string `long$.z.p;
  fix: wd, "/test_fixture.q";
  system "mkdir -p ", wd;
  (hsym `$fix) 0: fixtureContent;
  launcher: .resq.HOME, "/bin/qspec";
  cmd: "timeout 60 ", (.utl.shellQuote launcher), " ", (.utl.shellQuote fix),
       " ", extraFlags, " > ", (.utl.shellQuote wd, "/out.txt"), " 2>&1; echo $?";
  lines: @[system; cmd; {[e] enlist "-1"}];
  code: "J"$ last lines;
  out: @[read0; hsym `$wd, "/out.txt"; {()}];
  system "rm -rf -- ", .utl.shellQuote wd;
 `code`out!(code; out)
 };

.tst.testState.qcompat.runLauncherDirectory:{[explicitPatterns]
  wd: .utl.tempRoot[], "/resq_qspec_discovery_", string[.z.i], "_", string `long$.z.p;
  suite:wd,"/suite";
  system "mkdir -p ", .utl.shellQuote suite;
  qspecFile:suite,"/qspec_test_assertions.q";
  customFile:suite,"/custom_contract.q";
  qspecBody:$[explicitPatterns;
    (".tst.desc[\"excluded qspec file\"]{";
     " should[\"must not run\"]{ 1 musteq 2 };";
     " };");
    (".tst.desc[\"qspec discovery\"]{";
     " should[\"runs\"]{ 1 musteq 1 };";
     " };")];
  (hsym `$qspecFile) 0:qspecBody;
  (hsym `$customFile) 0:(".tst.desc[\"custom discovery\"]{";
    " should[\"runs\"]{ 1 musteq 1 };";" };");
  if[explicitPatterns;
    (hsym `$wd,"/resq.json") 0:enlist "{\"testFilePatterns\":[\"custom_*.q\"]}"];
  launcher:.resq.HOME,"/bin/qspec";
  cmd:"cd ",.utl.shellQuote[wd]," && timeout 60 ",.utl.shellQuote[launcher]," ",
      .utl.shellQuote[suite]," -strict -pass > ",.utl.shellQuote[wd,"/out.txt"],
      " 2>&1; echo $?";
  lines:@[system;"sh -c ",.utl.shellQuote cmd;{[e]enlist "-1"}];
  code:"J"$last lines;
  out:@[read0;hsym `$wd,"/out.txt";{()}];
  system "rm -rf -- ",.utl.shellQuote wd;
  `code`out!(code;out)
 };

.tst.testState.qcompat.anyLike:{[lines; pat] any lines like ("*", pat, "*") };
.tst.testState.qcompat.frameworkChatter:{[lines]
  patterns:("Loading Test:";"RUN AUDIT";"SUMMARY";"All tests passed";
            "Tests FAILED";"Report written to";"FAILURE DIFF");
  any {[rows;pattern] any rows like ("*",pattern,"*")}[lines;] each patterns
 };
.tst.testState.qcompat.canQ: 0 < count @[system; "which q 2>/dev/null"; {()}];

/ A suite relying on qspec's musteq (`=`: scalar broadcast, type-loose) and
/ mustne (`<>`: every element differs). Valid qspec; not valid default resQ.
.tst.testState.qcompat.qspecStyle: (
  ".tst.desc[\"qspec semantics\"]{";
  "  should[\"broadcast a scalar\"]{ (0 0 0) musteq 0 };";
  "  should[\"loose numeric type\"]{ 1 musteq 1.0 };";
  "  should[\"elementwise mustne\"]{ mustne[1 2 3; 4 5 6] };";
  " };");

/ The first mismatch is intentionally discarded so the suite stays green; it
/ exists solely to prove -pass suppresses assertion diagnostics too.
.tst.testState.qcompat.silentProbe: (
  ".tst.desc[\"pass silence\"]{";
  "  should[\"hide internal mismatch\"]{";
  "    saved:.tst.assertState; musteq[1;2]; .tst.assertState:saved; 1 musteq 1;";
  "  };";
  " };");

.tst.desc["qspec compatibility contract #slow"]{

  skipIf[not .tst.testState.qcompat.canQ;
         "a qspec-semantics suite passes under -qspec-compat"]{
    r: .tst.testState.qcompat.run[.tst.testState.qcompat.qspecStyle; "-qspec-compat"];
    musteq[r`code; 0];
  };

  skipIf[not .tst.testState.qcompat.canQ;
         "the qspec launcher enables compatibility without source changes"]{
    r: .tst.testState.qcompat.runLauncher[.tst.testState.qcompat.qspecStyle;
                                                 "-pass -performance -fdl 12"];
    musteq[r`code; 0];
    .tst.testState.qcompat.frameworkChatter[r`out] musteq 0b;
  };

  skipIf[not .tst.testState.qcompat.canQ;
         "the qspec launcher discovers pinned qspec filenames in a directory"]{
    r:.tst.testState.qcompat.runLauncherDirectory 0b;
    r[`code] musteq 0;
  };

  skipIf[not .tst.testState.qcompat.canQ;
         "an explicit testFilePatterns override remains authoritative"]{
    r:.tst.testState.qcompat.runLauncherDirectory 1b;
    r[`code] musteq 0;
  };

  skipIf[not .tst.testState.qcompat.canQ;
         "-pass suppresses assertion diffs as well as the reporter"]{
    r: .tst.testState.qcompat.runLauncher[.tst.testState.qcompat.silentProbe; "-pass"];
    musteq[r`code; 0];
    .tst.testState.qcompat.frameworkChatter[r`out] musteq 0b;
  };

  skipIf[not .tst.testState.qcompat.canQ;
         "the same suite fails WITHOUT the flag, and says why"]{
    r: .tst.testState.qcompat.run[.tst.testState.qcompat.qspecStyle; ""];
    must[0 <> r`code; "qspec semantics must not silently pass by default"];
    must[.tst.testState.qcompat.anyLike[r`out; "qspec compatibility"];
         "the failure must name the qspec difference"];
    must[.tst.testState.qcompat.anyLike[r`out; "-qspec-compat"];
         "the failure must name the switch that fixes it"];
  };

  skipIf[not .tst.testState.qcompat.canQ;
         "the qspec surface suite passes in BOTH modes"]{
    surface: .resq.HOME, "/tests/compat";
    { [dir; flags]
       / Lead with `true`, NOT `cd`: q intercepts a leading `system "cd ..."`
       / to change its OWN working directory and mangles the &&-chained command.
       / Parenthesised: q is right-to-left, so an unparenthesised
       / `.utl.shellQuote .resq.HOME, "/resq.q test "` quotes the whole string
       / including " test " and passes it as a single argument.
       cmd: "true && timeout 120 q ", (.utl.shellQuote .resq.HOME, "/resq.q"),
            " test ", (.utl.shellQuote dir), " ", flags, " -quiet > /dev/null 2>&1; echo $?";
       code: "J"$ last @[system; cmd; {[e] enlist "-1"}];
       must[0 = code; "tests/compat must pass with flags '", flags, "', got exit ", string code];
     }[surface;] each ("" ; "-qspec-compat");
  };
 };
