/ End-to-end guards for two ways a test declaration/run could disappear while
/ leaving a successful process status. These checks deliberately use bin/resq:
/ the launcher is the public process boundary responsible for supervising q.

\d .tst

.tst.procguard.canQ: 0 < count @[system; "command -v q 2>/dev/null"; {()}];
.tst.procguard.canTimeout: 0 < count @[system; "command -v timeout 2>/dev/null"; {()}];
.tst.procguard.base: .utl.tempRoot[], "/resq_process_guard_", string .z.i;
.tst.procguard.counter: 0;

.tst.procguard.workDir:{[]
    .tst.procguard.counter+: 1;
    .tst.procguard.base, "/run_", string .tst.procguard.counter
 };

.tst.procguard.cleanup:{[]
    expected: .utl.tempRoot[], "/resq_process_guard_", string .z.i;
    if[not .tst.procguard.base ~ expected; '"refusing unsafe process-guard cleanup path"];
    if[.utl.pathExists .tst.procguard.base;
        system "rm -rf -- ", .utl.shellQuote .tst.procguard.base];
 };

.tst.procguard.run:{[fixtureContent;extraFlags]
    wd: .tst.procguard.workDir[];
    .utl.ensureDir wd;
    fixPath: wd, "/test_fixture.q";
    outPath: wd, "/out.txt";
    (hsym `$fixPath) 0: fixtureContent;
    / Do not lead with cd: q handles a leading system "cd ..." internally.
    cmd: "mkdir -p ", .utl.shellQuote[wd], " && cd ", .utl.shellQuote[wd], " && ",
         .utl.shellQuote["timeout"], " -k 5 60 ",
         .utl.shellQuote[.resq.HOME, "/bin/resq"], " test ",
         .utl.shellQuote[fixPath], " ", extraFlags,
         " -quiet < /dev/null > ", .utl.shellQuote[outPath], " 2>&1; echo $?";
    statusLines: @[system; cmd; {[e] enlist "-1"}];
    code: "J"$last statusLines;
    out: @[read0; hsym `$outPath; {()}];
    `code`out!(code;out)
 };

.tst.procguard.anyLike:{[lines;pat] any lines like ("*",pat,"*")};

\d .

.tst.procguard.fxArity: (
    ".tst.desc[\"arity slip\"]{";
    "  should[\"real test\"]{ 1 musteq 1 };";
    "  holds[\"missing properties\"]{ 1 musteq 1 };";
    " };");

.tst.procguard.fxExitZero: (
    ".tst.desc[\"premature exit\"]{";
    "  should[\"must not fake green\"]{ exit 0 };";
    "  should[\"never reached\"]{ 1 musteq 1 };";
    " };");

.tst.procguard.fxPass: (
    ".tst.desc[\"ordinary pass\"]{";
    "  should[\"finishes\"]{ 1 musteq 1 };";
    " };");

.tst.desc["Process completion and DSL declaration guards #slow"]{
  after{.tst.procguard.cleanup[]};

  should["every source DSL constructor has an incomplete-declaration guard"]{
    oldDeclarations: .tst.dslDeclarations;
    oldActive: .tst.dslDeclarationAuditActive;
    .tst.dslDeclarations: .tst.emptyDslDeclarations[];
    .tst.dslDeclarationAuditActive: 1b;

    / Deliberately retain each returned projection without supplying its final
    / argument. This is the exact q behavior that used to delete a test.
    projections: (
      .tst.shouldEntry[1]["s"];
      .tst.itEntry[2]["i"];
      .tst.holdsEntry[3]["h";()!()];
      .tst.perfEntry[4]["p";()!()];
      .tst.skipEntry[5]["k"];
      .tst.pendingEntry[6];
      .tst.skipIfEntry[7][1b;"c"];
      .tst.retryEntry[8][2;"r"];
      .tst.testOnlyEntry[9]["o"]);
    declarations: .tst.dslDeclarations;

    .tst.dslDeclarations: oldDeclarations;
    .tst.dslDeclarationAuditActive: oldActive;

    musteq[count declarations; 9];
    must[not any declarations`completed; "no incomplete projection may be marked complete"];
    / q evaluates the list expression right-to-left; all names must still be
    / present exactly once.
    musteq[asc declarations`verb; asc `should`it`holds`perf`skip`pending`skipIf`retry`testOnly];
    musteq[count projections; 9];
  };

  should["the loader rewrites declarations through the arity entry point"]{
    rewritten: .tst.annotateExpectationLine[42; "  holds[\"property\";`runs!10]{ 1b }"];
    musteq[rewritten; "  .tst.holdsEntry[42][\"property\";`runs!10]{ 1b }"];
    qualified: .tst.annotateExpectationLine[43; "  .tst.retry[2;\"flaky\"]{ 1b }"];
    musteq[qualified; "  .tst.retryEntry[43][2;\"flaky\"]{ 1b }"];
  };

  should["line annotation can be disabled without disabling the DSL"]{
    previous: @[get;`.tst.app.expectationLineAnnotations;1b];
    .tst.app.expectationLineAnnotations: 0b;
    rewritten: first .tst.preprocessScript enlist
      "  should[\"plain\"]{ must[1b;\"ok\"] };";
    .tst.app.expectationLineAnnotations: previous;
    must[not .tst.literalIn["Entry[";rewritten];
         "the kill switch must bypass line-aware entry wrappers"];
    must[.tst.literalIn[".tst.dsl.should[";rewritten] and
         .tst.literalIn[".tst.dsl.must[";rewritten];
         "the ordinary DSL must remain bound when annotation is off"];
  };

  skipIf[(not .tst.procguard.canQ) or not .tst.procguard.canTimeout;
         "an incomplete DSL constructor is a load error"]{
    r: .tst.procguard.run[.tst.procguard.fxArity; "-strict"];
    musteq[r`code; 4];
    must[.tst.procguard.anyLike[r`out; "DSL arity error"]; "the load error must explain the incomplete declaration"];
    must[.tst.procguard.anyLike[r`out; "holds"]; "the load error must name the constructor"];
  };

  skipIf[(not .tst.procguard.canQ) or not .tst.procguard.canTimeout;
         "exit 0 before run completion cannot return success"]{
    r: .tst.procguard.run[.tst.procguard.fxExitZero; "-strict"];
    musteq[r`code; 1];
    must[.tst.procguard.anyLike[r`out; "before resQ completed"]; "the launcher must explain the forced failure"];
  };

  skipIf[(not .tst.procguard.canQ) or not .tst.procguard.canTimeout;
         "an ordinary completed run still exits zero"]{
    r: .tst.procguard.run[.tst.procguard.fxPass; "-strict"];
    musteq[r`code; 0];
  };
 };
