/ ============================================================================
/ Tests for `resq watch` - the smart watch mode (lib/watch.q + resq.q dispatch).
/ .
/ Watch mode is interactive, so it is exercised at two levels:
/   1. Unit: the path-classification helpers (.tst.watch.isTestFile / inTestDir)
/      that decide whether a changed file reruns just itself or triggers a
/      source->test mapping. These used to throw 'nyi because their `like`
/      patterns had two `*` wildcards (q's `like` allows at most one), so the
/      regression pins below feed the EXACT inputs that used to throw.
/   2. Subprocess (#slow): launch `resq watch` against a scratch dir with stdin
/      at EOF (`< /dev/null`), append to a test file, and assert the process
/      stayed alive (banner printed), detected the change, reran the test, and
/      never printed 'nyi. This pins both verified bugs end to end.
/ .
/ lib/init.q loads lib/watch.q for every run, so the helpers are in scope here
/ with no extra setup. Counters/state live under .tst.testState.* (the pollution
/ guard skips the `tst` namespace), matching tests/test_retry.q.
/ ============================================================================

/ ---------------------------------------------------------------------------
/ (1) isTestFile: a .q file whose BASENAME matches configured discovery rules.
.tst.desc["watch: isTestFile classifies test files by basename"]{
  should["accept tests/test_foo.q (basename test_foo.q)"]{
    must[.tst.watch.isTestFile "tests/test_foo.q"; "basename test_foo.q is a test file"];
  };
  should["accept a bare test_x.q with no directory"]{
    must[.tst.watch.isTestFile "test_x.q"; "test_x.q is a test file"];
  };
  should["accept the supported suffix convention foo_test.q"]{
    must[.tst.watch.isTestFile "tests/foo_test.q"; "foo_test.q is a test file"];
  };
  should["reject a plain source file src/foo.q"]{
    must[not .tst.watch.isTestFile "src/foo.q"; "src/foo.q is not a test file"];
  };
  should["reject proj/test/bar.q (test-DIR file, not test_*.q basename)"]{
    must[not .tst.watch.isTestFile "proj/test/bar.q"; "bar.q is not a test_*.q basename"];
  };
  should["reject test_foo.txt (wrong suffix, two-star trap)"]{
    must[not .tst.watch.isTestFile "test_foo.txt"; "non-.q must be rejected"];
  };
 };

.tst.desc["watch: deletion and source mapping follow discovery semantics"]{
  before{
    `.tst.watch.runnerCmd mock {.tst.testState.watchchk.ran: x};
    `.tst.watch.scanFiles mock {()!()};
    `.tst.watch.fileStates mock ()!();
    `.tst.watch.deletedFiles mock `symbol$();
    `.tst.testState.watchchk.ran mock `unset;
  };

  should["surface deleted paths and fall back to the full remaining suite"]{
    deleted: `$"/project/tests/test_deleted.q";
    .tst.watch.fileStates: (enlist deleted)!enlist (10; 20);
    changes: .tst.watch.check[];
    must[deleted in changes; "a deletion must be returned as a change"];
    must[deleted in .tst.watch.deletedFiles; "deletion identity must be retained"];
    .tst.watch.onChanges changes;
    .tst.testState.watchchk.ran mustmatch ();
  };

  should["map a source change to the suffix-style test file"]{
    source: `$"/project/src/foo.q";
    test: `$"/project/tests/foo_test.q";
    .tst.watch.fileStates: (source; test)!((10; 20); (30; 40));
    .tst.watch.onChanges enlist source;
    .tst.testState.watchchk.ran mustmatch enlist test;
  };
 };

/ ---------------------------------------------------------------------------
/ (2) inTestDir: a file living under a directory segment named exactly "test".
.tst.desc["watch: inTestDir classifies files under a test/ directory"]{
  should["accept proj/test/bar.q"]{
    must[.tst.watch.inTestDir "proj/test/bar.q"; "lives under test/"];
  };
  should["accept a/test/b.q at any depth"]{
    must[.tst.watch.inTestDir "a/test/b.q"; "lives under test/"];
  };
  should["reject src/foo.q (no test dir segment)"]{
    must[not .tst.watch.inTestDir "src/foo.q"; "no test/ segment"];
  };
  should["reject tests/test_foo.q (segment is 'tests', not 'test')"]{
    must[not .tst.watch.inTestDir "tests/test_foo.q"; "segment 'tests' is not exactly 'test'"];
  };
 };

/ ---------------------------------------------------------------------------
/ (3) CRITICAL regression pin: the EXACT inputs that used to throw 'nyi (two
/ `*` wildcards in one `like`). Both helpers must classify these without ANY
/ throw. We trap with a lambda so a regression surfaces as a clear failure
/ rather than aborting the whole spec.
.tst.testState.watchchk.noThrow:{[f; arg] 0b ~ @[{x y; 0b}[f]; arg; {1b}] };

.tst.desc["watch: classification never throws (regression pin for 'nyi)"]{
  should["isTestFile does not throw on foo/test_bar.q (the old 'nyi input)"]{
    must[.tst.testState.watchchk.noThrow[.tst.watch.isTestFile; "foo/test_bar.q"];
         "must not throw 'nyi"];
  };
  should["inTestDir does not throw on proj/test/bar.q (the old 'nyi input)"]{
    must[.tst.testState.watchchk.noThrow[.tst.watch.inTestDir; "proj/test/bar.q"];
         "must not throw 'nyi"];
  };
 };

/ ---------------------------------------------------------------------------
/ (4) Weird/degenerate inputs must not throw and must classify as non-test.
.tst.desc["watch: degenerate inputs are safe (empty, no slash, spaces)"]{
  should["empty string -> not a test file, no throw"]{
    must[.tst.testState.watchchk.noThrow[.tst.watch.isTestFile; ""]; "no throw on empty"];
    must[not .tst.watch.isTestFile ""; "empty is not a test file"];
  };
  should["empty string -> not in test dir, no throw"]{
    must[.tst.testState.watchchk.noThrow[.tst.watch.inTestDir; ""]; "no throw on empty"];
    must[not .tst.watch.inTestDir ""; "empty is not under test/"];
  };
  should["no-slash path is handled"]{
    must[.tst.testState.watchchk.noThrow[.tst.watch.isTestFile; "noslash"]; "no throw"];
    must[not .tst.watch.isTestFile "noslash"; "no .q suffix"];
    must[not .tst.watch.inTestDir "noslash"; "no directory component"];
  };
  should["paths with spaces are handled"]{
    must[.tst.testState.watchchk.noThrow[.tst.watch.isTestFile; "dir with space/test_a.q"]; "no throw"];
    must[.tst.watch.isTestFile "dir with space/test_a.q"; "basename test_a.q is a test file"];
    must[.tst.watch.inTestDir "a/test/b c.q"; "test/ segment present"];
  };
  should["accept symbol input too (check[] yields symbols)"]{
    must[.tst.watch.isTestFile `$"tests/test_foo.q"; "symbol path classifies as test"];
  };
 };

/ ---------------------------------------------------------------------------
/ (4b) Batched fingerprinting (bug 2/3): the per-tick stat is now ONE subprocess
/ for all paths, shell-quoted so SPACED paths work (the old per-file code split
/ on whitespace and returned mtime 0 for them). Pin: a fingerprint over a file
/ under a SPACED directory must (a) report a non-zero mtime, and (b) change when
/ the file is appended to (size and/or mtime move).
.tst.desc["watch: fingerprint handles spaced paths and detects edits"]{
  should["fingerprint a file under a spaced dir, detect an append"]{
    wd: .utl.tempRoot[], "/resq_watchfp_", string[.z.i], "_", string `long$.z.p;
    sub: wd, "/my dir";
    tf: sub, "/test_a.q";
    system "mkdir -p ", .utl.shellQuote sub;
    (hsym `$tf) 0: enlist "/ a";
    fp1: .tst.watch.fingerprint tf;
    / mtime is the second slot; spaced paths used to yield 0 here.
    must[0<count fp1 1; "mtime token must be nonempty for a spaced path"];
    / Sleep past 1s so the mtime second-granularity ticks even if size matched.
    system "sleep 1.1";
    (hsym `$tf) 0: ("/ a"; "/ bb");
    fp2: .tst.watch.fingerprint tf;
    must[not fp1 ~ fp2; "fingerprint must change after an append"];
    system "rm -rf ", .utl.shellQuote wd;
  };
  should["statAll absorbs a missing path without throwing"]{
    wd: .utl.tempRoot[], "/resq_watchfp_m_", string[.z.i], "_", string `long$.z.p;
    tf: wd, "/test_b.q";
    system "mkdir -p ", .utl.shellQuote wd;
    (hsym `$tf) 0: enlist "/ b";
    / One present, one deleted-mid-tick path: the batch must keep the present one.
    mm: .tst.watch.statAll (tf; wd, "/gone.q");
    must[tf in key mm; "present path must appear in the mtime map"];
    must[not (wd, "/gone.q") in key mm; "missing path must be absent (mtime 0)"];
    system "rm -rf ", .utl.shellQuote wd;
  };
  should["watch detects same-size same-second edit"]{
    wd:.utl.tempRoot[],"/resq_watchfp_same_",string[.z.i],"_",string `long$.z.p;
    tf:wd,"/test_same.q";
    system "mkdir -p ",.utl.shellQuote wd;
    (hsym `$tf) 0:enlist "AAAA";
    setMtime:{[path;nanos]
      code:"import os,sys; n=int(sys.argv[2]); os.utime(sys.argv[1], ns=(n,n))";
      system "python3 -c ",.utl.shellQuote[code]," ",.utl.shellQuote[path],
        " ",string nanos};
    setMtime[tf;1700000000100000000j];
    fp1:.tst.watch.fingerprint tf;
    (hsym `$tf) 0:enlist "BBBB";
    setMtime[tf;1700000000200000000j];
    fp2:.tst.watch.fingerprint tf;
    must[(first fp1)=first fp2;"the fixture must preserve file size"];
    seconds:{first ":" vs 2 _ x} each (fp1 1;fp2 1);
    seconds[0] musteq seconds 1;
    must[not fp1~fp2;"subsecond fingerprint must detect the rewrite"];
    system "rm -rf ",.utl.shellQuote wd;
  };
 };

/ ---------------------------------------------------------------------------
/ (5) Subprocess #slow: prove the two CRITICAL bugs are fixed end to end.
/   - Bug 2: with stdin at EOF the old .z.ts+`system "t"` exited in ~0.2s.
/     The foreground loop must keep the process alive for the full timeout,
/     so the banner is printed AND it is still running when we touch a file.
/   - Bug 1: touching a test file used to 'nyi in onChanges. Now it must
/     detect the change, rerun the (trivial, passing) test, and print no 'nyi.
/ The compound shell command absorbs all exit codes (`; true`) so q's `system`
/ never throws 'os. The inner rerun spawns ANOTHER q (runnerCmd reloads
/ runner.q and runs the file), so the scratch test is kept trivial and fast.

.tst.testState.watchchk.canQ: 0 < count @[system; "which q 2>/dev/null"; {()}];

.tst.testState.watchchk.anyLike:{[lines; pat] any lines like ("*", pat, "*") };

/ Launch `resq watch <wd>` in the background with stdin at EOF, append to a
/ trivial passing test after a short delay, then collect the captured output.
.tst.testState.watchchk.run:{[]
  wd: .utl.tempRoot[], "/resq_watch_", string[.z.i], "_", string `long$.z.p;
  out: wd, "/out.txt";
  tf: wd, "/test_w.q";
  system "mkdir -p ", wd;
  (hsym `$tf) 0: enlist ".tst.desc[\"watchsub\"]{ should[\"pass\"]{ 1 musteq 1 } };";
  / Whole compound command absorbs exit codes with `; true`. Run watch in the
  / BACKGROUND (`& echo started`), wait for it to settle, append to the test
  / file to trigger a change, then wait for the rerun to complete.
  / NOTE: q's system special-cases some leading tokens: "cd ..." is intercepted
  / (chdir, never reaches a shell) and "(" is rejected outright ('( invalid).
  / Lead with a real binary (mkdir, like the golden harness) so the compound
  / command reaches the shell. All paths are absolute.
  / timeout needs -k: q's watch loop survives plain SIGTERM (same lesson as
  / isolate.q), and an unkilled child holds this test's pipes open forever.
  reportDir:wd,"/report";
  stateDir:wd,"_state";
  system "mkdir -p ",stateDir;
  cmd: "mkdir -p ", wd, " && ( timeout -k 2 9 q ", .resq.HOME, "/resq.q watch ", wd,
       " -json -outDir ",reportDir,
       " -state-file ",stateDir,"/last-run.json",
       " -flake-history ",stateDir,"/flake.json",
       " -quarantine-file ",stateDir,"/quarantine.json",
       " -flake-proposal-file ",stateDir,"/proposals.json",
       " < /dev/null > ", out, " 2>&1 & echo $! > ", stateDir, "/watch.pid )",
       " && sleep 2 && echo '/ touched' >> ", tf,
       " && sleep 4 ; true";
  @[system; cmd; {[e] e}];
  o: @[read0; hsym `$out; {()}];
  reportExists:.utl.pathExists reportDir,"/test-results.json";
  rawReport:@[read0;hsym `$reportDir,"/test-results.json";{()}];
  schemaVersion:$[count rawReport;"j"$(.j.k "\n" sv rawReport)`schemaVersion;0j];
  / Stop the watcher before deleting its directory. It outlives the reads
  / above (timeout 9 s plus a 2 s kill grace), and a report it wrote after the
  / rm recreated wd/report, leaving one resq_watch_* directory per run.
  .tst.testState.watchchk.stop stateDir,"/watch.pid";
  system "rm -rf ",wd," ",stateDir;
  `out`reportExists`schemaVersion!(o;reportExists;schemaVersion)
 };

/ Kill the timeout wrapper's q child, then the wrapper, and wait (bounded)
/ until the wrapper has gone so nothing writes into the work directory again.
.tst.testState.watchchk.stop:{[pidFile]
  pid:first @[read0;hsym `$pidFile;{enlist ""}];
  if[not all pid in .Q.n;:()];
  if[0=count pid;:()];
  @[system;"p=",pid,"; pkill -KILL -P $p 2>/dev/null; kill -KILL $p 2>/dev/null;",
    " i=0; while kill -0 $p 2>/dev/null && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done; true";
    {[e] ()}];
 };

/ Exercise the real long-lived process boundary: three file changes, three
/ in-process runAll calls, and a fresh coverage init/stop session for each one.
.tst.testState.watchchk.runCoverageCycles:{[]
  wd:.utl.tempRoot[],"/resq_watch_cov_",string[.z.i],"_",string `long$.z.p;
  srcDir:wd,"/src";
  src:srcDir,"/app.q";
  tf:wd,"/test_w.q";
  out:wd,"/out.txt";
  reportDir:wd,"/report";
  stateDir:wd,"_state";
  system "mkdir -p ",.utl.shellQuote[srcDir]," ",.utl.shellQuote stateDir;
  (hsym `$src) 0:("\\d .watchcov";"add:{[x;y]x+y};";"\\d .");
  testSource:".tst.loadSource[\"",src,
    "\"]; .tst.desc[\"watch coverage\"]{ should[\"pass\"]{ .watchcov.add[1;2] musteq 3 } };";
  (hsym `$tf) 0:enlist testSource;
  command:"timeout -k 2 14 q ",.utl.shellQuote[.resq.HOME,"/resq.q"],
    " watch ",.utl.shellQuote[wd]," -coverage --source ",.utl.shellQuote[srcDir],
    " -json -outDir ",.utl.shellQuote[reportDir],
    " -state-file ",.utl.shellQuote[stateDir,"/last-run.json"],
    " -flake-history ",.utl.shellQuote[stateDir,"/flake.json"],
    " -quarantine-file ",.utl.shellQuote[stateDir,"/quarantine.json"],
    " -flake-proposal-file ",.utl.shellQuote[stateDir,"/proposals.json"],
    " < /dev/null > ",.utl.shellQuote[out]," 2>&1 & watcher=$!; ",
    "sleep 2; echo '/ cycle 1' >> ",.utl.shellQuote[tf],"; ",
    "sleep 3; echo '/ cycle 2' >> ",.utl.shellQuote[tf],"; ",
    "sleep 3; echo '/ cycle 3' >> ",.utl.shellQuote[tf],"; ",
    "wait $watcher; true";
  @[system;"sh -c ",.utl.shellQuote command;{[e]e}];
  output:@[read0;hsym `$out;{()}];
  reportExists:.utl.pathExists reportDir,"/test-results.json";
  system "rm -rf ",.utl.shellQuote[wd]," ",.utl.shellQuote stateDir;
  `out`reportExists!(output;reportExists)
 };

.tst.desc["watch: subprocess stays alive + detects change (#slow, regression)"]{

  skipIf[not .tst.testState.watchchk.canQ;
         "non-TTY watch keeps running, detects a change, reruns, no 'nyi"]{
    watchResult: .tst.testState.watchchk.run[];
    o:watchResult`out;
    / Banner proves the process did NOT instant-exit before the loop started.
    must[.tst.testState.watchchk.anyLike[o; "Watch mode active"];
         "watch banner should be printed"];
    / Change detection proves the foreground loop actually ticked AND the
    / 'nyi-throwing classification is fixed.
    must[.tst.testState.watchchk.anyLike[o; "Changes detected in"];
         "the appended change should be detected"];
    must[.tst.testState.watchchk.anyLike[o; "Running tests internally"];
         "a rerun should be triggered for the changed test"];
    / The inner rerun must actually run the trivial passing test.
    must[.tst.testState.watchchk.anyLike[o; "1 total (1 passed"];
         "the changed test should rerun and pass"];
    / Hard regression pins: neither bug's failure signature may appear.
    must[not .tst.testState.watchchk.anyLike[o; "nyi"];
         "onChanges must not throw 'nyi (two-star like bug)"];
    must[not .tst.testState.watchchk.anyLike[o; "Error during test run"];
         "the internal rerun must not error"];
    must[watchResult`reportExists;"watch must honor the selected JSON reporter"];
    watchResult[`schemaVersion] musteq 2j;
  };
 };

.tst.desc["watch + coverage repeated lifecycle (#slow)"]{
  skipIf[(not .tst.testState.watchchk.canQ) or
         0=count @[system;"which timeout 2>/dev/null";{()}];
         "three watch reruns restore coverage wrappers between cycles"]{
    result:.tst.testState.watchchk.runCoverageCycles[];
    output:result`out;
    passLines:sum {0<count ss[x;"Tests:      1 total"]} each output;
    initLines:sum {0<count ss[x;"Coverage tracking initialized."]} each output;
    must[passLines>=3;
         "all three changed-file cycles must execute and pass: ","\n" sv output];
    must[initLines>=3;
         "each cycle must start a fresh coverage session: ","\n" sv output];
    must[not any {0<count ss[x;"Error during test run"]} each output;
         "watch reruns must not report an internal error"];
    must[not any {0<count ss[x;"Coverage init failed"]} each output;
         "coverage re-init must not fail"];
    must[not any {0<count ss[x;"Coverage restoration failed"]} each output;
         "coverage teardown must restore every owned wrapper"];
    must[result`reportExists;"the final cycle must publish its JSON report"];
  };
 };

/ ---------------------------------------------------------------------------
/ (6) Choosing what to rerun from the load graph (lib/load_graph.q).
/ Watch used to map src/foo.q to test_foo.q by NAME only, so a second test
/ that loaded foo.q was silently skipped. These write a real project to a
/ scratch directory, track it, and assert on .tst.watch.plan - the decision
/ onChanges acts on - with the runner mocked out.

/ Write `files` (relative path -> source lines) under a fresh scratch root and
/ make them the watcher's tracked files.
.tst.testState.watchsel.setup:{[files]
  root: .utl.tempRoot[], "/resq_watchsel_", string[.z.i], "_", string `long$.z.p;
  full: (root, "/") ,/: key files;
  system "mkdir -p ", " " sv .utl.shellQuote each distinct .tst.static.getDir each full;
  {[path;lines] (hsym `$path) 0: lines}'[full; value files];
  .tst.testState.watchsel.root: root;
  tracked: .tst.static.findSources root;
  .tst.watch.fileStates: tracked!(count tracked)#enlist (1; "t"; "");
  root
 };

.tst.testState.watchsel.sym:{[rel] `$.tst.testState.watchsel.root, "/", rel};
.tst.testState.watchsel.syms:{[rels] asc .tst.testState.watchsel.sym each rels};
.tst.testState.watchsel.plain: enlist "x: 1";

.tst.desc["watch: a source change reruns every test that loads it"]{
  before{
    `.tst.watch.runnerCmd mock {.tst.testState.watchsel.ran: x};
    `.tst.watch.fileStates mock ()!();
    `.tst.watch.deletedFiles mock `symbol$();
    `.tst.watch.loaders mock ();
    `.tst.watch.graph mock ();
    `.tst.testState.watchsel.ran mock `unset;
    `.tst.testState.watchsel.root mock "";
  };
  after{
    if[count .tst.testState.watchsel.root;
      system "rm -rf ", .utl.shellQuote .tst.testState.watchsel.root];
  };

  should["rerun the test that loads a source file under another name"]{
    .tst.testState.watchsel.setup ("src/foo.q"; "tests/test_foo.q"; "tests/test_bar.q"; "tests/test_other.q")!(
      .tst.testState.watchsel.plain;
      .tst.testState.watchsel.plain;
      enlist "\\l src/foo.q";
      .tst.testState.watchsel.plain);
    plan: .tst.watch.plan enlist .tst.testState.watchsel.sym "src/foo.q";
    must[not plan`all; "a known loader narrows the run"];
    / test_bar by its load; test_foo by its name, as before; test_other not at all.
    (asc plan`tests) mustmatch .tst.testState.watchsel.syms ("tests/test_bar.q"; "tests/test_foo.q");
  };

  should["hand the chosen tests to the runner"]{
    .tst.testState.watchsel.setup ("src/foo.q"; "tests/test_bar.q"; "tests/test_other.q")!(
      .tst.testState.watchsel.plain;
      enlist "\\l src/foo.q";
      .tst.testState.watchsel.plain);
    .tst.watch.onChanges enlist .tst.testState.watchsel.sym "src/foo.q";
    .tst.testState.watchsel.ran mustmatch enlist .tst.testState.watchsel.sym "tests/test_bar.q";
  };

  should["follow a change through the files in between"]{
    .tst.testState.watchsel.setup ("src/a.q"; "src/b.q"; "tests/test_a.q"; "tests/test_c.q")!(
      enlist "\\l src/b.q";
      .tst.testState.watchsel.plain;
      enlist "\\l src/a.q";
      .tst.testState.watchsel.plain);
    plan: .tst.watch.plan enlist .tst.testState.watchsel.sym "src/b.q";
    must[not plan`all; "the chain is known"];
    plan[`tests] mustmatch enlist .tst.testState.watchsel.sym "tests/test_a.q";
  };

  should["run the full suite when nothing is known to load the file"]{
    .tst.testState.watchsel.setup ("src/lonely.q"; "tests/test_a.q")!(
      .tst.testState.watchsel.plain; .tst.testState.watchsel.plain);
    plan: .tst.watch.plan enlist .tst.testState.watchsel.sym "src/lonely.q";
    must[plan`all; "an unexplained file cannot be narrowed"];
    must[any plan[`notes] like "*lonely.q*"; "the fallback names the file: ", .Q.s1 plan`notes];
  };

  should["rerun the tests that load a changed helper"]{
    .tst.testState.watchsel.setup ("tests/helpers.q"; "tests/test_a.q"; "tests/test_b.q")!(
      .tst.testState.watchsel.plain;
      enlist "\\l tests/helpers.q";
      .tst.testState.watchsel.plain);
    plan: .tst.watch.plan enlist .tst.testState.watchsel.sym "tests/helpers.q";
    must[not plan`all; "the helper's users are known"];
    plan[`tests] mustmatch enlist .tst.testState.watchsel.sym "tests/test_a.q";
  };

  should["rerun a changed file under test/ together with the tests that load it"]{
    .tst.testState.watchsel.setup ("test/helpers.q"; "test/test_a.q"; "test/test_b.q")!(
      .tst.testState.watchsel.plain;
      enlist "\\l test/helpers.q";
      .tst.testState.watchsel.plain);
    plan: .tst.watch.plan enlist .tst.testState.watchsel.sym "test/helpers.q";
    (asc plan`tests) mustmatch .tst.testState.watchsel.syms ("test/helpers.q"; "test/test_a.q");
  };
 };

.tst.desc["watch: a test whose loads cannot be read is rerun, not skipped"]{
  before{
    `.tst.watch.runnerCmd mock {.tst.testState.watchsel.ran: x};
    `.tst.watch.fileStates mock ()!();
    `.tst.watch.deletedFiles mock `symbol$();
    `.tst.watch.loaders mock ();
    `.tst.watch.graph mock ();
    `.tst.testState.watchsel.root mock "";
  };
  after{
    if[count .tst.testState.watchsel.root;
      system "rm -rf ", .utl.shellQuote .tst.testState.watchsel.root];
  };

  should["include it on a source change and leave it out when only a test changed"]{
    .tst.testState.watchsel.setup ("src/a.q"; "tests/test_a.q"; "tests/test_dyn.q"; "tests/test_plain.q")!(
      .tst.testState.watchsel.plain;
      enlist "\\l src/a.q";
      ("path: getenv `WATCHSEL_SOURCE;"; "system \"l \", path;");
      .tst.testState.watchsel.plain);
    onSource: .tst.watch.plan enlist .tst.testState.watchsel.sym "src/a.q";
    (asc onSource`tests) mustmatch .tst.testState.watchsel.syms ("tests/test_a.q"; "tests/test_dyn.q");
    must[any onSource[`notes] like "*no fixed target*"; "the extra tests are explained: ", .Q.s1 onSource`notes];
    onTest: .tst.watch.plan enlist .tst.testState.watchsel.sym "tests/test_a.q";
    onTest[`tests] mustmatch enlist .tst.testState.watchsel.sym "tests/test_a.q";
  };

  should["treat a named external loader's module names as unreadable"]{
    files: ("src/a.q"; "tests/test_a.q"; "tests/test_m.q")!(
      .tst.testState.watchsel.plain;
      enlist "\\l src/a.q";
      enlist ".ext.load \"pricing\";");
    .tst.testState.watchsel.setup files;
    unnamed: .tst.watch.plan enlist .tst.testState.watchsel.sym "src/a.q";
    unnamed[`tests] mustmatch enlist .tst.testState.watchsel.sym "tests/test_a.q";
    .tst.watch.loaders: enlist ".ext.load";
    named: .tst.watch.plan enlist .tst.testState.watchsel.sym "src/a.q";
    (asc named`tests) mustmatch .tst.testState.watchsel.syms ("tests/test_a.q"; "tests/test_m.q");
  };

  should["read loader names from both the variable and resq.json"]{
    `.resq.config.watchLoaders mock enlist ".cfg.load";
    .tst.watch.loaders: `.var.load;
    (asc .tst.watch.loaderNames[]) mustmatch asc (".cfg.load"; ".var.load");
  };

  should["run the full suite on a source change when the graph cannot be built"]{
    .tst.testState.watchsel.setup ("src/foo.q"; "tests/test_foo.q")!(
      .tst.testState.watchsel.plain; .tst.testState.watchsel.plain);
    `.tst.loadGraph.build mock {[tracked;fingerprints;loaders] '"simulated graph failure"};
    onSource: .tst.watch.plan enlist .tst.testState.watchsel.sym "src/foo.q";
    must[onSource`all; "without a graph a source change cannot be narrowed"];
    onTest: .tst.watch.plan enlist .tst.testState.watchsel.sym "tests/test_foo.q";
    must[not onTest`all; "a changed test still reruns alone"];
    onTest[`tests] mustmatch enlist .tst.testState.watchsel.sym "tests/test_foo.q";
  };
 };

/ ---------------------------------------------------------------------------
/ (7) The full-suite fallback must run the suite. The default runner used to
/ pass its empty file list straight to the test loader, which then discovered
/ nothing: "Running ALL tests" ran no tests. The loader, reporter setup and
/ runAll are mocked so only the argument hand-off is exercised.
.tst.desc["watch: the full-suite fallback runs the watched directories"]{
  should["hand the runner the watched directories when given no files"]{
    `.resq.util.loadQFile mock {[p] ::};
    `.tst.initReporting mock {[] ::};
    `.tst.runAll mock {[x] .tst.testState.watchsel.args: .tst.app.args};
    `.tst.app.exit mock .tst.app.exit;
    `.tst.app.args mock .tst.app.args;
    `.tst.watch.watchDirs mock ("srcdir"; "testdir");
    `.tst.testState.watchsel.args mock `unset;
    .tst.watch.runnerCmd[()];
    .tst.testState.watchsel.args mustmatch ("srcdir"; "testdir");
    .tst.watch.runnerCmd enlist `$"t/test_a.q";
    .tst.testState.watchsel.args mustmatch enlist "t/test_a.q";
  };
 };

/ ---------------------------------------------------------------------------
/ (7b) resQ's require loads a file once per process, and watch reruns in one
/ process. Without forgetting watched files, an edit to a source file loaded
/ through .utl.require was never read again: the test reran and stayed green
/ on the old definitions.
.tst.desc["watch: a rerun reloads watched files that require has cached"]{
  should["forget tracked files, keep resQ's own modules and unrelated paths"]{
    own: .resq.PKGLOADING, "/mock.q";
    `.tst.watch.fileStates mock (`$"/proj/src/a.q"; `$own)!((1; "t"; ""); (1; "t"; ""));
    `.resq.loaded mock (""; "/proj/src/a.q"; ":/proj/src/a.q"; "/elsewhere/b.q"; own);
    .tst.watch.forgetLoaded[];
    .resq.loaded mustmatch (""; "/elsewhere/b.q"; own);
  };

  should["recognise a tracked file however it was spelled when required"]{
    here: system "cd";
    `.tst.watch.fileStates mock (enlist `$"src/rel.q")!enlist (1; "t"; "");
    `.resq.loaded mock (""; here, "/src/rel.q"; "./src/rel.q"; "src/x/../rel.q"; "src/other.q");
    .tst.watch.forgetLoaded[];
    .resq.loaded mustmatch (""; "src/other.q");
  };

  should["leave the list alone when nothing is tracked"]{
    `.tst.watch.fileStates mock ()!();
    `.resq.loaded mock (""; "/proj/src/a.q");
    .tst.watch.forgetLoaded[];
    .resq.loaded mustmatch (""; "/proj/src/a.q");
  };
 };

/ ---------------------------------------------------------------------------
/ (8) Subprocess #slow: the same decisions through the real watch loop. One
/ test loads src/app.q through .utl.require; src/other.q is loaded by nothing.
/ Editing app.q must rerun just that test; editing other.q must fall back to
/ the full suite AND the full suite must actually run the test; and breaking
/ app.q afterwards must turn the test red, which proves the rerun read the
/ edited file rather than the copy require had already loaded.
.tst.testState.watchchk.runSelection:{[]
  wd: .utl.tempRoot[], "/resq_watch_sel_", string[.z.i], "_", string `long$.z.p;
  srcDir: wd, "/src";
  app: srcDir, "/app.q";
  other: srcDir, "/other.q";
  tf: wd, "/test_w.q";
  out: wd, "/out.txt";
  stateDir: wd, "_state";
  system "mkdir -p ", .utl.shellQuote[srcDir], " ", .utl.shellQuote stateDir;
  (hsym `$app) 0: enlist ".watchsel.add:{[x;y] x+y};";
  (hsym `$other) 0: enlist ".watchsel.unused:{[x] x};";
  (hsym `$tf) 0: (".utl.require \"", app, "\";"; ".tst.desc[\"watch selection\"]{ should[\"pass\"]{ .watchsel.add[1;2] musteq 3 } };");
  command: "timeout -k 2 15 q ", .utl.shellQuote[.resq.HOME, "/resq.q"],
    " watch ", .utl.shellQuote[wd],
    " -state-file ", .utl.shellQuote[stateDir, "/last-run.json"],
    " -flake-history ", .utl.shellQuote[stateDir, "/flake.json"],
    " -quarantine-file ", .utl.shellQuote[stateDir, "/quarantine.json"],
    " -flake-proposal-file ", .utl.shellQuote[stateDir, "/proposals.json"],
    " < /dev/null > ", .utl.shellQuote[out], " 2>&1 & watcher=$!; ",
    "sleep 2; echo '/ edit' >> ", .utl.shellQuote[app], "; ",
    "sleep 3; echo '/ edit' >> ", .utl.shellQuote[other], "; ",
    "sleep 3; echo '.watchsel.add:{[x;y] x-y};' > ", .utl.shellQuote[app], "; ",
    / Children first: once timeout itself is killed its q child is reparented,
    / pkill -P no longer finds it, and the watcher would run for ever.
    "sleep 3; pkill -KILL -P $watcher 2>/dev/null; kill -KILL $watcher 2>/dev/null; wait $watcher 2>/dev/null; true";
  @[system; "sh -c ", .utl.shellQuote command; {[e] e}];
  output: @[read0; hsym `$out; {()}];
  system "rm -rf ", .utl.shellQuote[wd], " ", .utl.shellQuote stateDir;
  output
 };

.tst.desc["watch: selection through the real loop (#slow)"]{
  skipIf[(not .tst.testState.watchchk.canQ) or
         0=count @[system;"which timeout 2>/dev/null";{()}];
         "a loaded source reruns its test, an unloaded one the whole suite, and edits are reloaded"]{
    o: .tst.testState.watchchk.runSelection[];
    shown: "\n" sv o;
    must[.tst.testState.watchchk.anyLike[o; "Load graph: 1 load"]; "the graph sees the test's load: ", shown];
    targeted: o where o like "*Running target tests:*";
    must[2 = count targeted; "both edits to app.q are targeted runs: ", shown];
    must[all targeted like "*test_w.q"; "the targeted runs are the test that loads app.q: ", shown];
    must[.tst.testState.watchchk.anyLike[o; "No test file is known to load"]; "the unloaded file is called out: ", shown];
    must[.tst.testState.watchchk.anyLike[o; "Running ALL tests"]; "and falls back to the full suite: ", shown];
    passes: sum o like "*1 total (1 passed*";
    must[passes = 2; "the first targeted run and the full suite ran the test green: ", shown];
    must[1 = sum o like "*1 total (0 passed, 1 failed*";
         "the broken edit was reloaded and turned the test red: ", shown];
    must[not .tst.testState.watchchk.anyLike[o; "No test files found"]; "the full suite must find the tests: ", shown];
    must[not .tst.testState.watchchk.anyLike[o; "Error during test run"]; "no rerun may error: ", shown];
  };
 };

/ Where stat gives whole seconds only, or is not there, a file's content
/ decides whether it changed. That path signalled 'type: md5 was given the
/ bytes read1 returns, and the empty stat map was asked a question it
/ answers with a list.
.tst.desc["watch: a change is seen without help from stat"]{
  should["digest a file's content, the same for the same bytes"]{
    dir: .resq.util.tempRoot[], "/resq_watch_digest_", string[.z.i], "_", string `long$.z.p;
    .resq.util.ensureDir dir;
    .tst.registerCleanup[{[d] @[system; "rm -rf -- ", .resq.util.shellQuote d; {}]}; enlist dir];
    (hsym `$dir, "/a.q") 0: enlist "x: 1";
    (hsym `$dir, "/b.q") 0: enlist "x: 2";
    (hsym `$dir, "/c.q") 0: enlist "x: 1";
    digest: {[d;name] .tst.watch.contentDigest hsym `$d, "/", name}[dir];
    (count digest "a.q") musteq 32;
    (digest "a.q") musteq digest "c.q";
    ((digest "a.q") ~ digest "b.q") musteq 0b;
    / a file that cannot be read has no digest
    (digest "missing.q") musteq "";
  };
  should["fingerprint a file when the stat map is empty"]{
    dir: .resq.util.tempRoot[], "/resq_watch_nostat_", string[.z.i], "_", string `long$.z.p;
    .resq.util.ensureDir dir;
    .tst.registerCleanup[{[d] @[system; "rm -rf -- ", .resq.util.shellQuote d; {}]}; enlist dir];
    f: dir, "/a.q";
    (hsym `$f) 0: enlist "x: 1";
    before1: .tst.watch.fingerprintWith[()!(); f];
    (before1 1) musteq "s:0";
    (count before1 2) musteq 32;
    / the same size, other content: the fingerprint changes
    (hsym `$f) 0: enlist "x: 2";
    after1: .tst.watch.fingerprintWith[()!(); f];
    (before1 0) musteq after1 0;
    (before1 ~ after1) musteq 0b;
  };
 };

.tst.desc["watch: the paths it is given #slow"]{
  should["refuse a path that is not there instead of watching nothing for ever"]{
    if[not .tst.testState.watchchk.canQ; :must[1b; "q unavailable"]];
    cmd: (.resq.util.shellQuote .resq.HOME, "/bin/resq"), " watch no-such-directory-here < /dev/null 2>&1; echo exit=$?";
    out: @[system; "sh -c ", .resq.util.shellQuote cmd; {[e] enlist "exit=-1"}];
    (last out) musteq "exit=1";
    (any out like "CLI ERROR: watch path not found: no-such-directory-here") musteq 1b;
  };
  should["watch the current directory when it is given no path"]{
    if[not .tst.testState.watchchk.canQ; :must[1b; "q unavailable"]];
    if[0 = count @[system; "which timeout 2>/dev/null"; {()}]; :must[1b; "timeout unavailable"]];
    dir: .resq.util.tempRoot[], "/resq_watch_nopath_", string[.z.i], "_", string `long$.z.p;
    .resq.util.ensureDir dir;
    .tst.registerCleanup[{[d] @[system; "rm -rf -- ", .resq.util.shellQuote d; {}]}; enlist dir];
    cmd: "cd ", .resq.util.shellQuote[dir], " && timeout 3 ", (.resq.util.shellQuote .resq.HOME, "/bin/resq"),
        " watch < /dev/null 2>&1; echo exit=$?";
    out: @[system; "sh -c ", .resq.util.shellQuote cmd; {[e] enlist "exit=-1"}];
    / still watching when the time was up, and no q error on the way
    (last out) musteq "exit=124";
    (any out like ">> Directories: .") musteq 1b;
    (any out like ">> Load graph: 0 load(s)*") musteq 1b;
    (any out like "'*") musteq 0b;
  };
 };

