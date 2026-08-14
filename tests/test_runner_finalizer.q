/ A spec's pollution/resource cleanup is a finally contract: beforeAll failure,
/ fail-hard halting, and an unexpected runSpec exception must all execute it.

.tst.testState.finalizer.canRun:
    (0 < count @[system; "which q 2>/dev/null"; {()}]) and
    (0 < count @[system; "which timeout 2>/dev/null"; {()}]);

.tst.testState.finalizer.run:{[fixtureBuilder;extraFlags]
    wd: .utl.tempRoot[], "/resq_finalizer_", string[.z.i], "_", string `long$.z.p;
    fixturePath: wd, "/test_finalizer_fixture.q";
    probePath: wd, "/finalizer_probe.txt";
    .utl.ensureDir wd;
    (hsym `$fixturePath) 0: fixtureBuilder probePath;
    cmd: "true && timeout -k 2 60 q ", (.utl.shellQuote .resq.HOME, "/resq.q"),
         " test ", (.utl.shellQuote fixturePath), " ", extraFlags,
         " -json -outDir ", (.utl.shellQuote wd),
         " -state-file ",.utl.shellQuote[wd,"/state.json"],
         " -flake-history ",.utl.shellQuote[wd,"/flake.json"],
         " -quarantine-file ",.utl.shellQuote[wd,"/quarantine.json"],
         " -flake-proposal-file ",.utl.shellQuote[wd,"/proposals.json"],
         " -quiet > ",
         (.utl.shellQuote wd, "/out.txt"), " 2>&1; echo $?";
    exitLines: @[system; cmd; {[err] enlist "-1"}];
    exitCode: "J"$last exitLines;
    rawJson: @[read0; hsym `$wd, "/test-results.json"; {()}];
    payload: $[count rawJson; .j.k raze rawJson; ()!()];
    outputText: "\n" sv @[read0; hsym `$wd, "/out.txt"; {()}];
    probeText: raze @[read0; hsym `$probePath; {()}];
    if[wd like "*/resq_finalizer_*"; system "rm -rf -- ", .utl.shellQuote wd];
    `code`payload`output`probe!(exitCode;payload;outputText;probeText)
 };

.tst.testState.finalizer.probeCleanup:{[probePath]
    ".tst.registerSpecCleanup[{[p] (hsym `$p) 0: enlist string .appx.marker};enlist ",
        .Q.s1[probePath], "];"
 };

.tst.desc["runSpec always-finalize contract #slow"]{
    skipIf[not .tst.testState.finalizer.canRun;
           "restore pollution after beforeAll throws, before the next suite"]{
        result: .tst.testState.finalizer.run[
            {[probePath]
                (".appx.marker:`clean;";
                 ".tst.desc[\"polluting setup\"]{";
                 "  beforeAll{ .appx.marker:`polluted; '\"beforeAll boom\" };";
                 "  should[\"never runs\"]{ 1 musteq 1 };";
                 "};";
                 ".tst.desc[\"following suite\"]{";
                 "  should[\"sees clean state\"]{ .appx.marker musteq `clean };";
                 "};")};
            ""];
        result[`code] musteq 1;
        rows: result[`payload;`tests];
        following: rows where rows[`description] ~\: "sees clean state";
        first[following`status] musteq "pass";
        must[result[`output] like "*modified globals in appx*";
             "the pollution must be visible in the log before restoration"];
    };

    skipIf[not .tst.testState.finalizer.canRun;
           "run pollution restoration and spec cleanup after fail-hard halts"]{
        result: .tst.testState.finalizer.run[
            {[probePath]
                (".appx.marker:`clean;";
                 ".tst.failHardAfterAllRan:0b;";
                 ".tst.desc[\"fail-hard pollution\"]{";
                 "  afterAll{ .tst.failHardAfterAllRan:1b };";
                 "  should[\"fails after registering cleanup\"]{";
                 "    .appx.marker:`polluted;";
                 "    .tst.registerSpecCleanup[{[p] (hsym `$p) 0: enlist string[.appx.marker],\"|\",string .tst.failHardAfterAllRan};enlist ", .Q.s1[probePath], "];";
                 "    1 musteq 2;";
                 "  };";
                 "};")};
            "-fail-hard"];
        result[`code] musteq 1;
        result[`probe] musteq "clean|1";
        must[result[`output] like "*modified globals in appx*";
             "fail-hard must not bypass pollution detection"];
    };

    skipIf[not .tst.testState.finalizer.canRun;
           "finalize before re-signalling an unexpected runSpec exception"]{
        result: .tst.testState.finalizer.run[
            {[probePath]
                (".appx.marker:`clean;";
                 ".tst.applyTestOnlyFocus:{[suiteName;items] '\"raw runSpec boom\"};";
                 ".tst.desc[\"raw exception pollution\"]{";
                 "  beforeAll{";
                 "    .appx.marker:`polluted;";
                 "    ", .tst.testState.finalizer.probeCleanup[probePath];
                 "  };";
                 "  should[\"never reaches body\"]{ 1 musteq 1 };";
                 "};")};
            ""];
        result[`code] musteq 1;
        result[`probe] musteq "clean";
        must[result[`output] like "*raw runSpec boom*";
             "the original runSpec exception must still be reported"];
        must[result[`output] like "*modified globals in appx*";
             "unexpected exceptions must not bypass pollution detection"];
    };
};

::
