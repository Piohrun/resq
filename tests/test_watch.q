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
/ (1) isTestFile: a .q file whose BASENAME matches test_*.q.
.tst.desc["watch: isTestFile classifies test files by basename"]{
  should["accept tests/test_foo.q (basename test_foo.q)"]{
    must[.tst.watch.isTestFile "tests/test_foo.q"; "basename test_foo.q is a test file"];
  };
  should["accept a bare test_x.q with no directory"]{
    must[.tst.watch.isTestFile "test_x.q"; "test_x.q is a test file"];
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
  wd: "/tmp/resq_watch_", string[.z.i], "_", string `long$.z.p;
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
  cmd: "mkdir -p ", wd, " && ( timeout 9 q ", .resq.HOME, "/resq.q watch ", wd,
       " < /dev/null > ", out, " 2>&1 & echo started )",
       " && sleep 2 && echo '/ touched' >> ", tf,
       " && sleep 4 ; true";
  @[system; cmd; {[e] e}];
  o: @[read0; hsym `$out; {()}];
  system "rm -rf ", wd;
  o
 };

.tst.desc["watch: subprocess stays alive + detects change (#slow, regression)"]{

  skipIf[not .tst.testState.watchchk.canQ;
         "non-TTY watch keeps running, detects a change, reruns, no 'nyi"]{
    o: .tst.testState.watchchk.run[];
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
  };
 };
