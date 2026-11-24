/ Suite-level hook wiring: beforeAll / afterAll.
/ State lives under .tst.testState.* because the pollution guard skips the
/ `tst` namespace (runner.q: `except `q`Q`j`h`o`s`v`z`tst`resq`utl`), so we can
/ carry counters across a suite's tests and across desc blocks without the
/ guard restoring/warning on them.

/ ---------------------------------------------------------------------------
/ (1) beforeAll runs exactly once for a multi-test suite.
/ The beforeAll increments a counter; both tests assert it is still 1,
/ proving beforeAll fired once before the expectations and not per-test.
.tst.desc["beforeAll runs once per suite"]{
  beforeAll{
    .tst.testState.hookcheck.beforeAllRuns: 1 + @[get; `.tst.testState.hookcheck.beforeAllRuns; 0];
  };

  should["have run beforeAll before the first test"]{
    .tst.testState.hookcheck.beforeAllRuns musteq 1;
  };

  should["not re-run beforeAll for the second test"]{
    .tst.testState.hookcheck.beforeAllRuns musteq 1;
  };
 };

/ ---------------------------------------------------------------------------
/ (2) afterAll runs once after all tests of its suite.
/ desc blocks run in definition order (runner.q runDiscoveredSpecs iterates
/ .tst.app.allSpecs, populated by descLoaded in definition order), so the
/ second suite can assert what the first suite's afterAll recorded.
.tst.testState.afterallonce.inOrder:{[name]
  wd: .utl.tempRoot[], "/resq_afterallonce_order_", string[.z.i], "_", string `long$.z.p;
  .utl.ensureDir wd;
  fixture: .resq.HOME, "/tests/fixtures/declaration_order/", name;
  cmd: "cd ", .utl.shellQuote[wd], " && timeout -k 2 60 ", .utl.shellQuote[.resq.HOME, "/bin/resq"],
      " test ", .utl.shellQuote[fixture], " -json -outDir out -state-file out/s.json",
      " -flake-history out/f.json -flake-proposal-file out/p.json < /dev/null > out.txt 2>&1; echo $?";
  code: "J"$last @[system; "sh -c ", .utl.shellQuote cmd; {[e] enlist "-1"}];
  raw: @[read0; hsym `$wd, "/out/test-results.json"; {()}];
  rows: $[count raw; (.j.k raze raw)`tests; ()];
  @[system; "rm -rf -- ", .utl.shellQuote wd; {}];
  `code`rows!(code; rows)
 };
.tst.testState.afterallonce.canQ: 0 < count @[system; "which q 2>/dev/null"; {()}];

.tst.desc["afterAll runs once, checked by the suite after it, in declaration order #slow"]{
  skipIf[not .tst.testState.afterallonce.canQ; "see afterAll run exactly once after its suite"]{
    r: .tst.testState.afterallonce.inOrder "afterall_once.q";
    r[`code] musteq 0;
    statuses: {x`status} each r`rows;
    (count statuses) musteq 4;
    (distinct statuses) musteq enlist "pass";
  };
 };

/ ---------------------------------------------------------------------------
/ (N) A throwing before[]/after[] must still produce a RESULT ROW.
/ Regression: the per-spec error trap in runner.q printed "ERROR running spec"
/ and returned the spec untouched, so it contributed no expectation. The run
/ summarised as "0 total tests" and the JUnit document came out as an empty
/ <testsuites></testsuites> — a pipeline reading the report saw no tests and no
/ failures, with the exit code as the only signal. beforeAll already synthesised
/ an error row; before/after now do the same.
/ We cannot inspect another run's report from inside this one, so spawn resQ
/ against a generated fixture (the golden-harness idiom from test_retry.q).
/ ---------------------------------------------------------------------------
.tst.testState.hookerr.run:{[fixtureContent]
  wd: .utl.tempRoot[], "/resq_hookerr_", string[.z.i], "_", string `long$.z.p;
  fix: wd, "/test_fixture.q";
  system "mkdir -p ", wd;
  (hsym `$fix) 0: fixtureContent;
  / Lead with mkdir, NOT cd: q intercepts a leading `system "cd ..."` for its
  / own working directory, which would mangle the &&-chained command.
  cmd: "mkdir -p ", wd, " && cd ", wd, " && timeout 60 q ", .resq.HOME, "/resq.q test ", fix,
       " -junit -quiet > out.txt 2>&1; echo $?";
  lines: @[system; cmd; {[e] enlist "-1"}];
  code: "J"$ last lines;
  xml: @[read0; hsym `$wd, "/test-results.xml"; {()}];
  system "rm -rf ", wd;
  `code`xml!(code; "" sv xml)
 };

.tst.testState.hookerr.canQ: 0 < count @[system; "which q 2>/dev/null"; {()}];

.tst.desc["a throwing before/after still reaches the report #slow"]{

  skipIf[not .tst.testState.hookerr.canQ;
         "a throwing before[] produces an error testcase, not an empty document"]{
    r: .tst.testState.hookerr.run (
      ".tst.desc[\"broken before\"]{";
      "  before { '\"before exploded\" };";
      "  should[\"never runs\"]{ 1 musteq 1 };";
      " };");
    must[0 <> r`code; "a throwing before[] must fail the run"];
    must[not (r`xml) like "*<testsuites></testsuites>*";
         "the report must not be an empty document"];
    must[(r`xml) like "*errors=\"1\"*"; "the suite must report one error"];
    must[(r`xml) like "*before exploded*";
         "the error text must reach the report, got: ", r`xml];
  };

  skipIf[not .tst.testState.hookerr.canQ;
         "a throwing after[] produces an error testcase too"]{
    r: .tst.testState.hookerr.run (
      ".tst.desc[\"broken after\"]{";
      "  after { '\"after exploded\" };";
      "  should[\"body passes\"]{ 1 musteq 1 };";
      " };");
    must[0 <> r`code; "a throwing after[] must fail the run"];
    must[(r`xml) like "*after exploded*";
         "the after[] error text must reach the report, got: ", r`xml];
  };

  skipIf[not .tst.testState.hookerr.canQ;
         "healthy suites still report their results alongside a broken one"]{
    r: .tst.testState.hookerr.run (
      ".tst.desc[\"healthy\"]{";
      "  should[\"pass one\"]{ 1 musteq 1 };";
      "  should[\"pass two\"]{ 2 musteq 2 };";
      " };";
      ".tst.desc[\"broken before\"]{";
      "  before { '\"before exploded\" };";
      "  should[\"never runs\"]{ 1 musteq 1 };";
      " };");
    must[0 <> r`code; "the run must still fail overall"];
    must[(r`xml) like "*name=\"pass one\"*"; "a healthy test must survive in the report"];
    must[(r`xml) like "*name=\"pass two\"*"; "both healthy tests must survive"];
    must[(r`xml) like "*before exploded*";   "the broken suite must also be reported"];
  };
 };

/ A mock installed in beforeAll is the suite's. Every mock used to be undone
/ after each test, so the suite's was gone from the second test on and the
/ real dependency ran.
.tst.testState.suiteMock.query: {[q] `real};
.tst.testState.suiteMock.count: 0;

.tst.desc["a mock installed in beforeAll"]{
  beforeAll{ `.tst.testState.suiteMock.query mock {[q] `mocked}; };
  should["is seen by one test"]{ .tst.testState.suiteMock.query[`x] musteq `mocked; };
  should["is seen by another, which may mock the name again for itself"]{
    .tst.testState.suiteMock.query[`x] musteq `mocked;
    `.tst.testState.suiteMock.query mock {[q] `inner};
    .tst.testState.suiteMock.query[`x] musteq `inner;
  };
  should["is the suite's version again in a third"]{ .tst.testState.suiteMock.query[`x] musteq `mocked; };
  should["leaves a test's own mock of something else undone afterwards"]{
    .tst.testState.suiteMock.count musteq 0;
    `.tst.testState.suiteMock.count mock 5;
    .tst.testState.suiteMock.count musteq 5;
  };
  should["and that other mock really is undone"]{ .tst.testState.suiteMock.count musteq 0; };
  afterAll{ `.tst.testState.suiteMock.seenInAfterAll set .tst.testState.suiteMock.query `x; };
 };

.tst.desc["the suite after one that mocked in beforeAll"]{
  should["sees the real function"]{ .tst.testState.suiteMock.query[`x] musteq `real; };
 };
