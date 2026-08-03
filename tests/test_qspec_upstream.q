/ Execute qspec's pinned, unmodified public tests as a compatibility contract.
/ The copies deliberately do not match resQ's discovery glob; this harness owns
/ their invocation through bin/qspec, which turns compatibility mode on.

.tst.testState.qspecUpstream.files:(
  ("assertions"; "tests/upstream_qspec/qspec_test_assertions.q");
  ("UI"; "tests/upstream_qspec/qspec_test_ui.q");
  ("mocking"; "tests/upstream_qspec/qspec_test_mock.q");
  ("fuzzing"; "tests/upstream_qspec/qspec_test_fuzz.q");
  ("file fixtures"; "tests/fixture_tests/qspec_test_file_fixture.q");
  ("directory fixtures"; "tests/fixture_tests/qspec_test_directory_fixture.q");
  ("text fixtures"; "tests/fixture_tests/qspec_test_text_fixture.q")
 );
.tst.testState.qspecUpstream.canRun:
  (0 < count @[system; "command -v q 2>/dev/null"; {()}]) and
  0 < count @[system; "command -v timeout 2>/dev/null"; {()}];

.tst.testState.qspecUpstream.run:{[entry]
  label:first entry;
  source:last entry;
  wd:.utl.tempRoot[], "/resq_qspec_upstream_", string[.z.i], "_", ssr[label; " "; "_"];
  outFile:wd, "/out.txt";
  .utl.ensureDir wd;
  launcher:.resq.HOME, "/bin/qspec";
  sourcePath:.resq.HOME, "/", source;
  cmd:"timeout -k 5 120 ", (.utl.shellQuote launcher), " -pass ",
      (.utl.shellQuote sourcePath), " < /dev/null > ",
      (.utl.shellQuote outFile), " 2>&1; echo $?";
  statusLines:@[system; cmd; {[e] enlist "-1"}];
  code:"J"$last statusLines;
  output:@[read0; hsym `$outFile; {()}];
  expectedPrefix:.utl.tempRoot[], "/resq_qspec_upstream_";
  if[wd like expectedPrefix, "*"; system "rm -rf -- ", .utl.shellQuote wd];
  `label`code`output!(label;code;output)
 };

.tst.desc["Pinned upstream qspec public tests #slow"]{
  skipIf[not .tst.testState.qspecUpstream.canRun;
         "pass unchanged through the qspec compatibility launcher"]{
    { [entry]
      r:.tst.testState.qspecUpstream.run entry;
      detail:$[count r`output; " Output: ", "\n" sv r`output; ""];
      must[0 = r`code;
           "upstream ", (r`label), " suite exited ", string[r`code], detail];
    } each .tst.testState.qspecUpstream.files;
  };
 };
