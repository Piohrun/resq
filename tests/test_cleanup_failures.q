/ Cleanup failures are framework errors, not warnings. This subprocess contract
/ covers every lifecycle scope without making the meta-test run itself red.

.tst.testState.cleanupchk.canRun:
    (0 < count @[system; "which q 2>/dev/null"; {()}]) and
    (0 < count @[system; "which timeout 2>/dev/null"; {()}]);

.tst.testState.cleanupchk.run:{[]
    wd: .utl.tempRoot[], "/resq_cleanup_", string[.z.i], "_", string `long$.z.p;
    fixturePath: wd, "/test_cleanup_fixture.q";
    .utl.ensureDir wd;
    (hsym `$fixturePath) 0: (
        ".tst.registerFixtureWithOpts[`badTest;1;`scope`teardown!(`test;{[v] '\"test fixture boom\"})];";
        ".tst.registerFixtureWithOpts[`badSession;2;`scope`teardown!(`session;{[v] '\"session fixture boom\"})];";
        ".tst.desc[\"cleanup failures\"]{";
        "  afterAll{ '\"afterAll boom\" };";
        "  should[\"body passes\"]{[badTest;badSession]";
        "    .tst.registerCleanup[{'\"cleanup task boom\"};()];";
        "    .tst.registerSpecCleanup[{'\"spec cleanup boom\"};()];";
        "    (badTest+badSession) musteq 3;";
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
    if[wd like "*/resq_cleanup_*"; system "rm -rf -- ", .utl.shellQuote wd];
    `code`payload!(exitCode;payload)
 };

.tst.desc["Cleanup failures fail the run #slow"]{
    skipIf[not .tst.testState.cleanupchk.canRun;
           "all cleanup scopes become reported errors while later cleanup continues"]{
        result: .tst.testState.cleanupchk.run[];
        result[`code] musteq 1;
        payload: result`payload;
        payload[`summary;`passCount] musteq 1f;
        payload[`summary;`errorCount] musteq 5f;
        cleanupRows: payload[`tests] where payload[`tests;`status] ~\: "error";
        count[cleanupRows] musteq 5;
        allMessages: "\n" sv cleanupRows`message;
        must[allMessages like "*test fixture boom*"; "test fixture teardown must be reported"];
        must[allMessages like "*cleanup task boom*"; "expectation cleanup must be reported"];
        must[allMessages like "*spec cleanup boom*"; "spec cleanup must be reported"];
        must[allMessages like "*afterAll boom*"; "afterAll must be reported"];
        must[allMessages like "*session fixture boom*"; "session fixture must be reported"];
    };
};

::
