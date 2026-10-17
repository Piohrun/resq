/ ============================================================================
/ Working-directory contract: every test starts where the previous one was
/ started (a test that cds is undone), a beforeAll cd applies to its suite's
/ tests, and nothing leaks into the next suite. resQ remembers the directory
/ it restored to instead of re-reading it per test (`system "cd"` costs about
/ a millisecond); these scenarios pin the behaviour that cache must keep.
/ Run in a child process so the fixture can change directory freely.
/ ============================================================================
.tst.testState.wdir.canQ: 0 < count @[system; "which q 2>/dev/null"; {()}];

.tst.testState.wdir.fixture: (
  ".tst.testState.wlogAdd:{[tag] .tst.testState.wlog,: enlist tag,\":\",last \"/\" vs system \"cd\"};";
  ".tst.testState.wlog:();";
  ".tst.desc[\"plain\"]{";
  "  should[\"a1\"]{ .tst.testState.wlogAdd \"a1\"; system \"cd sub\"; 1 musteq 1 };";
  "  should[\"a2\"]{ .tst.testState.wlogAdd \"a2\"; 1 musteq 1 };";
  " };";
  ".tst.desc[\"beforeAll cd\"]{";
  "  beforeAll{ system \"cd other\" };";
  "  should[\"b1\"]{ .tst.testState.wlogAdd \"b1\"; system \"cd ../sub/deeper\"; 1 musteq 1 };";
  "  should[\"b2\"]{ .tst.testState.wlogAdd \"b2\"; 1 musteq 1 };";
  "  afterAll{ system \"cd sub\" };";
  " };";
  ".tst.desc[\"next suite\"]{";
  "  should[\"c1\"]{ .tst.testState.wlogAdd \"c1\"; 1 musteq 1 };";
  " };";
  ".tst.desc[\"nested expectation\"]{";
  "  should[\"d1\"]{";
  "    system \"cd sub\";";
  "    e: first ((.tst.desc[\"inner\"]{ should[\"n\"]{ 1 musteq 1 } })`expectations);";
  "    .tst.runExpec[();e];";
  "    .tst.testState.wlogAdd \"d1\";";
  "    1 musteq 1 };";
  "  should[\"d2\"]{ .tst.testState.wlogAdd \"d2\"; -1 \"WLOG \",\" \" sv .tst.testState.wlog; 1 musteq 1 };";
  " };");

.tst.desc["working directory between tests #slow"]{
  skipIf[not .tst.testState.wdir.canQ; "tests and suites start in the directory they were given"]{
    wd: .utl.tempRoot[], "/resq_wdir_", string[.z.i], "_", string `long$.z.p;
    .utl.ensureDir each wd,/:("/sub/deeper";"/other");
    (hsym `$wd,"/test_wdir_fixture.q") 0: .tst.testState.wdir.fixture;
    cmd: "cd ", .utl.shellQuote[wd], " && timeout 60 q ", .utl.shellQuote[.resq.HOME,"/resq.q"],
      " test test_wdir_fixture.q -quiet < /dev/null > out.txt 2>&1; echo $?";
    code: "J"$ last @[system; "sh -c ", .utl.shellQuote cmd; {[e] enlist "-1"}];
    out: @[read0; hsym `$wd, "/out.txt"; {()}];
    system "rm -rf -- ", .utl.shellQuote wd;
    code musteq 0;
    root: last "/" vs wd;
    expected: "WLOG a1:",root," a2:",root," b1:other b2:other c1:",root," d1:sub d2:",root;
    must[any out ~\: expected; "directory sequence differs; got: ", "\n" sv out];
  };
 };
