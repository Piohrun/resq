/ resQ must not reserve ordinary q local names through .q. Unqualified test DSL
/ remains source-compatible through stable loader-generated .tst.dsl bindings.

.tst.testState.adoption.canRun:
    (0 < count @[system; "which q 2>/dev/null"; {()}]) and
    (0 < count @[system; "which timeout 2>/dev/null"; {()}]);

.tst.testState.adoption.runResq:{[]
    wd: .utl.tempRoot[], "/resq_adoption_", string[.z.i], "_", string `long$.z.p;
    sourcePath: wd, "/application.q";
    fixturePath: wd, "/test_application.q";
    .utl.ensureDir wd;
    (hsym `$sourcePath) 0: enlist
        ".appx.delta:{[t] before:first t; after:last t; mock:after-before; it:mock+0; holds:it; perf:holds; must:perf};";
    (hsym `$fixturePath) 0: (
        "system \"l \", ", .Q.s1[sourcePath], ";";
        "describe[\"application adoption\"]{";
        "  should[\"loads ordinary DSL-shaped application locals\"]{";
        "  .appx.delta[10 15] musteq 5;";
        "  };";
        "};");
    cmd: "true && timeout -k 2 60 q ", (.utl.shellQuote .resq.HOME, "/resq.q"),
         " test ", (.utl.shellQuote fixturePath), " -json -outDir ",
         (.utl.shellQuote wd),
         " -state-file ",.utl.shellQuote[wd,"/state.json"],
         " -flake-history ",.utl.shellQuote[wd,"/flake.json"],
         " -quarantine-file ",.utl.shellQuote[wd,"/quarantine.json"],
         " -flake-proposal-file ",.utl.shellQuote[wd,"/proposals.json"],
         " -quiet > ", (.utl.shellQuote wd, "/out.txt"),
         " 2>&1; echo $?";
    exitLines: @[system; cmd; {[err] enlist "-1"}];
    exitCode: "J"$last exitLines;
    rawJson: @[read0; hsym `$wd, "/test-results.json"; {()}];
    payload: $[count rawJson; .j.k raze rawJson; ()!()];
    outputText: "\n" sv @[read0; hsym `$wd, "/out.txt"; {()}];
    if[wd like "*/resq_adoption_*"; system "rm -rf -- ", .utl.shellQuote wd];
    `code`payload`output!(exitCode;payload;outputText)
 };

.tst.testState.adoption.runCorpus:{[]
    wd: .utl.tempRoot[], "/resq_adoption_corpus_", string[.z.i], "_", string `long$.z.p;
    fixturePath: .resq.HOME, "/tests/compat/application/application_suite.q";
    .utl.ensureDir wd;
    cmd: "true && cd ", (.utl.shellQuote .resq.HOME), " && timeout -k 2 60 q ",
         (.utl.shellQuote .resq.HOME, "/resq.q"), " test ",
         (.utl.shellQuote fixturePath), " -json -strict -outDir ",
         (.utl.shellQuote wd),
         " -state-file ",.utl.shellQuote[wd,"/state.json"],
         " -flake-history ",.utl.shellQuote[wd,"/flake.json"],
         " -quarantine-file ",.utl.shellQuote[wd,"/quarantine.json"],
         " -flake-proposal-file ",.utl.shellQuote[wd,"/proposals.json"],
         " -quiet > ", (.utl.shellQuote wd, "/out.txt"),
         " 2>&1; echo $?";
    exitLines: @[system; cmd; {[err] enlist "-1"}];
    exitCode: "J"$last exitLines;
    rawJson: @[read0; hsym `$wd, "/test-results.json"; {()}];
    payload: $[count rawJson; .j.k raze rawJson; ()!()];
    outputText: "\n" sv @[read0; hsym `$wd, "/out.txt"; {()}];
    if[wd like "*/resq_adoption_corpus_*"; system "rm -rf -- ", .utl.shellQuote wd];
    `code`payload`output!(exitCode;payload;outputText)
 };

.tst.testState.adoption.runInitProbeAt:{[home]
    wd: .utl.tempRoot[], "/resq_q_probe_", string[.z.i], "_", string `long$.z.p;
    scriptPath: wd, "/probe.q";
    outPath: wd, "/out.txt";
    .utl.ensureDir wd;
    (hsym `$scriptPath) 0: (
        / .Q.s1 is a console renderer and truncates long strings to the active
        / console width. JSON string encoding is also valid q source for a char
        / vector, and preserves every byte of a long checkout path.
        ".resq.HOME:", .j.j[.tst.toString home], ";";
        ".q.resqProbeSentinel:42;";
        "qKeysBefore:key `.q;";
        "qValuesBefore:{get .Q.dd[`.q;x]} each qKeysBefore;";
        "system \"l \",.resq.HOME,\"/lib/bootstrap.q\";";
        ".utl.resqHomeAtBoot:.resq.HOME;";
        ".utl.PKGLOADING:.resq.HOME,\"/lib\";";
        "system \"l \",.resq.HOME,\"/lib/init.q\";";
        "qKeysAfter:key `.q;";
        "qValuesAfter:{get .Q.dd[`.q;x]} each qKeysAfter;";
        "-1 \"Q_UNCHANGED=\",string (qKeysBefore~qKeysAfter) and qValuesBefore~qValuesAfter;";
        "exit 0;");
    cmd: "timeout -k 2 60 q ", (.utl.shellQuote scriptPath), " < /dev/null > ",
         (.utl.shellQuote outPath), " 2>&1; echo $?";
    exitLines: @[system; cmd; {[err] enlist "-1"}];
    exitCode: "J"$last exitLines;
    outputText: "\n" sv @[read0; hsym `$outPath; {()}];
    if[wd like "*/resq_q_probe_*"; system "rm -rf -- ", .utl.shellQuote wd];
    `code`output!(exitCode;outputText)
 };

.tst.testState.adoption.runInitProbe:{[]
    .tst.testState.adoption.runInitProbeAt .resq.HOME
 };

.tst.desc["reserved namespace adoption contract #slow"]{
    skipIf[not .tst.testState.adoption.canRun;
           "leave .q byte-for-byte equivalent while loading the framework"]{
        result: .tst.testState.adoption.runInitProbe[];
        result[`code] musteq 0;
        must[result[`output] like "*Q_UNCHANGED=1*";
             "framework initialization must not add or replace .q members: ",
             result`output];
    };

    skipIf[not .tst.testState.adoption.canRun;
           "load framework initialization from a checkout path longer than the console width"]{
        root: .utl.tempRoot[], "/resq_q_long_home_", string[.z.i], "_", string `long$.z.p;
        longHome: root, "/", 96#"r";
        .utl.ensureDir root;
        linkLines: @[system;
            "ln -s -- ", (.utl.shellQuote .resq.HOME), " ", (.utl.shellQuote longHome),
            " 2>&1; echo $?";
            {[err] enlist "-1"}];
        linkCode: "J"$last linkLines;
        result: $[0=linkCode;
            .tst.testState.adoption.runInitProbeAt longHome;
            `code`output!(-1j;"could not create long-path checkout symlink")];
        if[root like "*/resq_q_long_home_*"; system "rm -rf -- ", .utl.shellQuote root];
        result[`code] musteq 0;
        must[result[`output] like "*Q_UNCHANGED=1*";
             "long checkout path must survive child-script serialization: ",
             result`output];
    };

    skipIf[not .tst.testState.adoption.canRun;
           "load application functions using DSL-shaped locals while test DSL stays unqualified"]{
        result: .tst.testState.adoption.runResq[];
        must[result[`code] = 0;
             "valid application source must load under resQ: ", result`output];
        result[`payload;`summary;`passCount] musteq 1f;
        result[`payload;`summary;`errorCount] musteq 0f;
    };

    skipIf[not .tst.testState.adoption.canRun;
           "pass the checked-in production application compatibility corpus"]{
        result: .tst.testState.adoption.runCorpus[];
        must[result[`code] = 0;
             "production compatibility corpus must pass unchanged: ", result`output];
        result[`payload;`summary;`testCount] musteq 3f;
        result[`payload;`summary;`passCount] musteq 3f;
        result[`payload;`summary;`errorCount] musteq 0f;
    };

    should["let test locals shadow DSL-shaped names without confusing annotation"]{
        it : 1 2 3;
        it[1] musteq 2;
    };

    it["keep an alias constructor outside a nested local of the same name"]{
        1 musteq 1;
    };

    should["let a test local use the constructor name should"]{
        should: 10 20 30;
        should[1] musteq 20;
    };

    should["scope a same-line should local to its test"]{should:10 20;should[1] musteq 20;};

    should["explain unresolved ambiguous DSL shadows"]{
        source:enlist ".tst.desc[\"x\"]{should:42;should[\"y\"]{1 musteq 1};};";
        hint:.tst.dslLoadErrorHint["should";source];
        hint mustlike "*local 'should' shadows a resQ DSL name*";
        hint mustlike "*.tst.should*";
    };

    should["preserve q right-to-left binding while rewriting infix assertions"]{
        x: 41;
        / q binds musteq to the immediate left noun, so this asserts 1~1 and
        / then evaluates x + the assertion result. Rewriting x+1 as the whole
        / left operand would introduce a false failure.
        x + 1 musteq 1;
    };
};

::
