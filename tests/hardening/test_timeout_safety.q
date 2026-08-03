/ End-to-end duration-budget regression. maxTestTime is a post-execution budget
/ in milliseconds; isolateTimeout is the separate process-kill mechanism.

.tst.testState.timeoutchk.canRun:
    (0 < count @[system; "which q 2>/dev/null"; {()}]) and
    (0 < count @[system; "which timeout 2>/dev/null"; {()}]) and
    not .utl.isWindows;

.tst.testState.timeoutchk.run:{[]
    wd: .utl.tempRoot[], "/resq_timeout_", string[.z.i], "_", string `long$.z.p;
    fixturePath: wd, "/test_timeout_fixture.q";
    system "mkdir -p ", .utl.shellQuote wd;
    (hsym `$fixturePath) 0: (
        ".tst.desc[\"duration budget\"]{";
        "  should[\"slow\"]{ system \"sleep 0.05\"; 1 musteq 1 };";
        "  should[\"survivor\"]{ 1 musteq 1 };";
        "};");
    cmd: "true && timeout -k 2 60 q ", (.utl.shellQuote .resq.HOME, "/resq.q"),
         " test ", (.utl.shellQuote fixturePath), " -maxTestTime 10 -json -outDir ",
         (.utl.shellQuote wd), " -quiet > ", (.utl.shellQuote wd, "/out.txt"),
         " 2>&1; echo $?";
    exitLines: @[system; cmd; {[err] enlist "-1"}];
    exitCode: "J"$last exitLines;
    rawJson: @[read0; hsym `$wd, "/test-results.json"; {()}];
    payload: $[count rawJson; .j.k raze rawJson; ()!()];
    if[wd like "*/resq_timeout_*"; system "rm -rf -- ", .utl.shellQuote wd];
    `code`payload!(exitCode;payload)
 };

.tst.desc["Timeout Safety #slow"]{
    skipIf[not .tst.testState.timeoutchk.canRun;
           "millisecond budget reports an error after return and the session survives"]{
        result: .tst.testState.timeoutchk.run[];
        result[`code] musteq 1;
        payload: result`payload;
        payload[`testCount] musteq 2f;
        payload[`passCount] musteq 1f;
        payload[`errorCount] musteq 1f;
        slowRows: payload[`tests] where payload[`tests;`description] ~\: "slow";
        count[slowRows] musteq 1;
        (first slowRows`status) musteq "error";
        must[(first slowRows`message) like "*duration budget of 10*";
             "duration message must state the millisecond budget"];
        must[(first slowRows`message) like "*post-execution*";
             "duration message must distinguish the check from preemption"];
    };
};

::
