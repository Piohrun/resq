/ An assertion counts wherever it runs. One that fails in `after` fails its
/ test; one that fails in `afterAll` or `beforeAll` fails the suite's hook;
/ one that fails outside any test, while the file loads, fails the file.
/ None of them may be blamed on the next test to run. Run in a child process
/ so the deliberately red fixture does not turn this suite red.

.tst.testState.hookAsserts.canRun:
    (0 < count @[system; "which q 2>/dev/null"; {()}]) and
    (0 < count @[system; "which timeout 2>/dev/null"; {()}]);

.tst.testState.hookAsserts.run:{[]
    wd: .utl.tempRoot[], "/resq_hookassert_", string[.z.i], "_", string `long$.z.p;
    .utl.ensureDir wd;
    (hsym `$wd, "/test_a_hooks.q") 0: (
        ".tst.desc[\"after hook\"]{";
        "  after{ 1 musteq 2; };";
        "  should[\"body passes\"]{ 1 musteq 1; };";
        " };";
        ".tst.desc[\"afterAll hook\"]{";
        "  afterAll{ 3 musteq 4; };";
        "  should[\"body passes too\"]{ 1 musteq 1; };";
        " };";
        ".tst.desc[\"beforeAll hook\"]{";
        "  beforeAll{ 5 musteq 6; };";
        "  should[\"never runs\"]{ 1 musteq 1; };";
        " };";
        ".tst.desc[\"the suite after them\"]{";
        "  should[\"is not blamed\"]{ 1 musteq 1; };";
        " };");
    (hsym `$wd, "/test_b_load.q") 0: (
        "7 musteq 8;";
        ".tst.desc[\"file with a failing assertion outside any test\"]{";
        "  should[\"still runs\"]{ 1 musteq 1; };";
        " };");
    cmd: "true && timeout -k 2 60 q ", (.utl.shellQuote .resq.HOME, "/resq.q"),
         " test ", (.utl.shellQuote wd), " -json -outDir ", (.utl.shellQuote wd),
         " -state-file ", .utl.shellQuote[wd, "/state.json"],
         " -flake-history ", .utl.shellQuote[wd, "/flake.json"],
         " -quarantine-file ", .utl.shellQuote[wd, "/quarantine.json"],
         " -flake-proposal-file ", .utl.shellQuote[wd, "/proposals.json"],
         " -quiet > ", (.utl.shellQuote wd, "/out.txt"), " 2>&1; echo $?";
    exitLines: @[system; cmd; {[err] enlist "-1"}];
    rawJson: @[read0; hsym `$wd, "/test-results.json"; {()}];
    payload: $[count rawJson; .j.k raze rawJson; ()!()];
    if[wd like "*/resq_hookassert_*"; system "rm -rf -- ", .utl.shellQuote wd];
    rows: $[`tests in key payload; payload`tests; ()];
    `code`rows!("J"$last exitLines; rows)
 };

/ status and message of the row whose description or suite matches a pattern
.tst.testState.hookAsserts.row:{[rows;pattern]
    hits: rows where {[pattern;r] (r[`description] like pattern) or r[`suite] like pattern}[pattern] each rows;
    $[count hits; first hits; `description`suite`status`message!("";"";"missing";"")]
 };

/ 1b when every part occurs in the text (`like` cannot take several wildcards)
.tst.testState.hookAsserts.has:{[text;parts] all {[text;part] 0 < count text ss part}[text] each parts};

.tst.desc["Assertions in hooks and at file load count #slow"]{
  before{
    if[not `result in key `.tst.testState.hookAsserts;
        .tst.testState.hookAsserts.result: $[.tst.testState.hookAsserts.canRun;
            .tst.testState.hookAsserts.run[]; ()!()]];
  };
  should["fail the test whose after hook asserted"]{
    if[not .tst.testState.hookAsserts.canRun; :must[1b; "q or timeout unavailable"]];
    r: .tst.testState.hookAsserts.row[.tst.testState.hookAsserts.result`rows; "body passes"];
    r[`status] musteq "fail";
    .tst.testState.hookAsserts.has[r`message; ("In after: Got 1"; "expected 2")] musteq 1b;
  };
  should["report a failed assertion in afterAll and in beforeAll as the hook's failure"]{
    if[not .tst.testState.hookAsserts.canRun; :must[1b; "q or timeout unavailable"]];
    rows: .tst.testState.hookAsserts.result`rows;
    messages: "\n" sv {x`message} each rows;
    has: .tst.testState.hookAsserts.has[messages];
    has[("afterAll hook failed"; "assertion failed: Got 3")] musteq 1b;
    hook: .tst.testState.hookAsserts.row[rows; "beforeAll hook failed"];
    hook[`status] musteq "error";
    .tst.testState.hookAsserts.has[hook`message; enlist "assertion failed: Got 5"] musteq 1b;
  };
  should["not blame the next test"]{
    if[not .tst.testState.hookAsserts.canRun; :must[1b; "q or timeout unavailable"]];
    rows: .tst.testState.hookAsserts.result`rows;
    .tst.testState.hookAsserts.row[rows; "is not blamed"][`status] musteq "pass";
    .tst.testState.hookAsserts.row[rows; "body passes too"][`status] musteq "pass";
    .tst.testState.hookAsserts.row[rows; "still runs"][`status] musteq "pass";
  };
  should["fail a file whose assertion outside any test failed, with the load-error exit code"]{
    if[not .tst.testState.hookAsserts.canRun; :must[1b; "q or timeout unavailable"]];
    rows: .tst.testState.hookAsserts.result`rows;
    messages: "\n" sv {x`message} each rows;
    .tst.testState.hookAsserts.has[messages; enlist "an assertion outside any test failed while the file was loading: Got 7"] musteq 1b;
    .tst.testState.hookAsserts.result[`code] musteq 4;
  };
 };
