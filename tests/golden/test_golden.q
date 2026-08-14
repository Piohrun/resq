/ ============================================================================
/ Golden test harness for resQ.
/ .
/ Runs resQ ITSELF as a subprocess against tiny fixture suites (tests/golden/
/ fixtures/f_*.q) and asserts on exit codes, summary output, and report-file
/ content. This locks in end-to-end behavior - especially failure paths - that
/ unit tests miss.
/ .
/ Fixtures are named f_*.q on purpose: discovery patterns are test_*.q and
/ *_test.q, so f_*.q files are NEVER auto-discovered. The harness passes them as
/ explicit paths, which resQ honors regardless of pattern.
/ .
/ Subprocess pattern: q's `system "cmd"` THROWS 'os when the child exits
/ nonzero, so we never call the test command directly. We append `; echo $?`
/ (the shell then always exits 0) and read the real child exit code back off
/ the last stdout line. `timeout 60` guards against hangs when the `timeout`
/ binary is present; on systems without it (e.g. macOS) the prefix is dropped
/ and scenarios run unguarded rather than failing with exit 127. See
/ .tst.golden.canTimeout / .tst.golden.timeoutPrefix below.
/ .
/ NOTE: a column-1 lone "/" line opens a q block comment (terminated by a lone
/ "\"); this banner uses "/ ." separators on purpose so it stays a plain line-
/ comment block that real q `\l` and the resQ preprocessor BOTH load identically.
/ resQ loads each test file via `value "\n" sv content`, where `\d` namespace
/ directives are NOT honored. All helpers below are fully-qualified
/ (.tst.golden.*) with no \d blocks.
/ ============================================================================

/ --- harness helpers (self-contained; no new lib/ modules) -----------------

/ Absolute fixtures dir, derived from the install root so this works from any
/ checkout location / CWD.
.tst.golden.fixtures: .resq.HOME, "/tests/golden/fixtures/";

/ Unique work-dir prefix. .z.i (process id) is stable within this single
/ process; a per-call counter keeps each scenario's dir distinct.
.tst.golden.base: .utl.tempRoot[], "/resq_golden";
.tst.golden.counter: 0;

/ Remove the whole golden scratch tree. The base honours TMPDIR, so this can no
/ longer be the literal "/tmp/resq_golden" it once was -- with TMPDIR set, that
/ literal deleted a path that did not exist and the real run dirs accumulated
/ silently. The safety property the literal provided is kept as an explicit
/ shape check: refuse to recursively delete anything that is not an absolute
/ path ending in /resq_golden.
.tst.golden.cleanupBase:{[]
    d: .tst.golden.base;
    if[not ("/" = first d) and d like "*/resq_golden"; :()];
    if[not .utl.pathExists d; :()];
    @[system; "rm -rf -- ", .utl.shellQuote d; {[e] }];
 };
.tst.golden.workDir:{[]
    .tst.golden.counter+: 1;
    .tst.golden.base, "/run_", string[.z.i], "_", string .tst.golden.counter
 };

/ Run resQ in a fresh work dir. Returns `code`out`dir!(exitInt; outLines; wd).
/ args is the full argument string after `resq.q test ` (paths + flags).
.tst.golden.run:{[args]
    wd: .tst.golden.workDir[];
    cmd: "mkdir -p ", wd, " && cd ", wd,
         " && ", .tst.golden.timeoutPrefix, "q ", .resq.HOME, "/resq.q -q test ", args,
         " > run_out.txt 2>&1; echo $?";
    lines: @[system; cmd; {[e] enlist "-1"}];
    code: "J"$ last lines;
    out: @[read0; hsym `$wd, "/run_out.txt"; {()}];
    `code`out`dir!(code; out; wd)
 };

/ Run resQ in `cover` mode against a single test file. The LCOV/state files are
/ written into the run's own work dir (outDir == cwd default), so the caller can
/ read coverage.lcov back from r`dir. `testF` is an absolute test path.
.tst.golden.runCover:{[testF]
    wd: .tst.golden.workDir[];
    cmd: "mkdir -p ", wd, " && cd ", wd,
         " && ", .tst.golden.timeoutPrefix, "q ", .resq.HOME, "/resq.q -q cover ", testF, " -quiet",
         " > run_out.txt 2>&1; echo $?";
    lines: @[system; cmd; {[e] enlist "-1"}];
    code: "J"$ last lines;
    out: @[read0; hsym `$wd, "/run_out.txt"; {()}];
    `code`out`dir!(code; out; wd)
 };

/ Read a report file written into a work dir, as string lines.
.tst.golden.readFile:{[wd; name] @[read0; hsym `$wd, "/", name; {()}] };
/ Read raw bytes of a report file (for control-char scanning).
.tst.golden.readRaw:{[wd; name] @[read1; hsym `$wd, "/", name; {`byte$()}] };

/ "some line contains substring" idiom.
.tst.golden.anyLike:{[lines; pat] any lines like ("*", pat, "*") };
.tst.golden.frameworkChatter:{[lines]
    patterns:("Loading Test:";"RUN AUDIT";"SUMMARY";"All tests passed";
              "Tests FAILED";"Report written to";"FAILURE DIFF");
    any {[rows;pattern] any rows like ("*",pattern,"*")}[lines;] each patterns
 };

/ Probe q availability ONCE before the desc blocks; skipIf each scenario.
.tst.golden.canQ: 0 < count @[system; "which q 2>/dev/null"; {()}];

/ Graceful degradation: `timeout` guards against hung children but is not
/ present everywhere (e.g. stock macOS has no `timeout`). Probe ONCE and build
/ the command prefix conditionally - "timeout 60 " when available, "" otherwise -
/ so scenarios run normally on systems without it instead of failing exit 127.
.tst.golden.canTimeout: 0 < count @[system; "which timeout 2>/dev/null"; {()}];
.tst.golden.timeoutPrefix: $[.tst.golden.canTimeout; "timeout 60 "; ""];

/ #slow: this harness spawns ~12 subprocesses at ~0.5s each.
.tst.desc["Golden: exit codes and summaries #slow"]{
  / Each scenario has asserted before after{} fires, so per-test cleanup of the
  / literal prefix is safe and leaves nothing behind (rm -rf is idempotent).
  / Only ever rm -rf the exact literal prefix path - never a variable.
  after{ .tst.golden.cleanupBase[] };

  / f_pass: exit 0, 2 passed.
  skipIf[not .tst.golden.canQ; "f_pass: exit 0 and 2-passed summary"]{
    r: .tst.golden.run .tst.golden.fixtures, "f_pass.q -quiet";
    musteq[r`code; 0];
    must[.tst.golden.anyLike[r`out; "2 passed, 0 failed, 0 error, 0 skipped"];
         "summary should report 2 passed"];
  };

  / f_fail: exit 1, real diff message (NOT "Error: type"). Pins diff-crash fix.
  skipIf[not .tst.golden.canQ; "f_fail: exit 1, real failure message, no type error"]{
    r: .tst.golden.run .tst.golden.fixtures, "f_fail.q -quiet";
    musteq[r`code; 1];
    must[.tst.golden.anyLike[r`out; "1 passed, 1 failed"];
         "summary should report 1 passed, 1 failed"];
    must[.tst.golden.anyLike[r`out; "Got 1 — expected 2"];
         "real musteq diff message should appear"];
    must[not .tst.golden.anyLike[r`out; "Error: type"];
         "must NOT crash with Error: type"];
  };

  / Selecting a FILE reporter must not silence the console. This used to replace
  / the text reporter outright, so `resq test ... -junit -json` -- the invocation
  / docs/CI.md recommends -- printed only two "Report written to" lines: no
  / summary, no counts, no verdict, no failure list. A CI log showed nothing but
  / a non-zero exit code.
  skipIf[not .tst.golden.canQ; "file reporters compose with console text"]{
    r: .tst.golden.run .tst.golden.fixtures, "f_fail.q -junit -json -quiet";
    musteq[r`code; 1];
    must[.tst.golden.anyLike[r`out; "1 passed, 1 failed"];
         "the summary must survive selecting -junit/-json"];
    must[.tst.golden.anyLike[r`out; "Got 1 — expected 2"];
         "the failure detail must survive selecting -junit/-json"];
    must[.tst.golden.anyLike[r`out; "TOTAL FAILURES"];
         "the verdict line must survive selecting -junit/-json"];
    / ...and the artifacts must still be written and announced.
    must[.tst.golden.anyLike[r`out; "XML Report written to"];
         "the XML artifact must still be produced"];
    must[.tst.golden.anyLike[r`out; "JSON Report written to"];
         "the JSON artifact must still be produced"];
  };

  / The structural diff must reach the MACHINE reports, not just the terminal.
  / It used to exist only as a streamed console banner, so JSON/JUnit carried the
  / one-line "Got X — expected Y" and a CI consumer never saw which row, column
  / or index actually differed.
  skipIf[not .tst.golden.canQ; "the structural diff reaches JSON and JUnit"]{
    r: .tst.golden.run .tst.golden.fixtures, "f_fail.q -json -junit -quiet";
    musteq[r`code; 1];

    j: .j.k raze .tst.golden.readFile[r`dir; "test-results.json"];
    failing: j[`tests] where j[`tests;`status] ~\: "fail";
    musteq[count failing; 1];
    / `failures` is a JSON array per row, so this is a list OF lists: take the
    / row's list, then its first entry, to reach a plain char vector for `ss`.
    detail: first first failing`failures;
    must[0 < count ss[detail; "Got 1 — expected 2"];
         "the JSON failure must keep its one-line summary"];
    must[0 < count ss[detail; "--- diff ---"];
         "the JSON failure must carry the diff section"];
    must[0 < count ss[detail; "Value mismatch"];
         "the JSON failure must carry the rendered diff body"];

    / Same detail in the XML element body; the attribute stays one line, because
    / XML attribute-value normalization would flatten newlines into spaces.
    xml: "\n" sv .tst.golden.readFile[r`dir; "test-results.junit.xml"];
    must[0 < count ss[xml; "Value mismatch"];
         "the JUnit body must carry the rendered diff"];
    must[0 = count ss[xml; "message=\"Got 1 — expected 2\n"];
         "the JUnit message attribute must not contain a raw newline"];
  };

  / The console keeps the SUMMARY line only: the same diff already streamed live
  / under a "FAILURE DIFF [suite :: test]" banner, so repeating it in the
  / end-of-run listing would double every failure in the log.
  skipIf[not .tst.golden.canQ; "console listing shows the summary, not the diff again"]{
    r: .tst.golden.run .tst.golden.fixtures, "f_fail.q";
    musteq[r`code; 1];
    must[.tst.golden.anyLike[r`out; "FAILURE DIFF"];
         "the diff must still stream at failure time"];
    / "Value mismatch" belongs to the streamed banner; it must appear exactly
    / once, not a second time inside the per-suite failure listing.
    / `sum` over booleans yields an int; musteq is `~` and so type-strict.
    must[1 = sum {0 < count ss[x; "Value mismatch"]} each r`out;
         "the diff body must appear exactly once, in the streamed banner"];
  };

  / -pass suppresses resQ-owned chatter/artifacts while preserving the status.
  / Runtime and application output remain outside that contract.
  skipIf[not .tst.golden.canQ; "-pass suppresses framework chatter and file reporters"]{
    r: .tst.golden.run .tst.golden.fixtures, "f_fail.q -pass -junit";
    musteq[r`code; 1];
    .tst.golden.frameworkChatter[r`out] musteq 0b;
    must[not .utl.pathExists r[`dir],"/test-results.junit.xml";
         "-pass must suppress the selected file reporter"];
  };

  / f_error: exit 1, 1 error, signalled message surfaces.
  skipIf[not .tst.golden.canQ; "f_error: exit 1, 1 error, message surfaces"]{
    r: .tst.golden.run .tst.golden.fixtures, "f_error.q -quiet";
    musteq[r`code; 1];
    must[.tst.golden.anyLike[r`out; "1 error"]; "summary should report 1 error"];
    must[.tst.golden.anyLike[r`out; "deliberate error"];
         "signalled error message should surface"];
  };

  / f_skip_mix: exit 0 (skips/pending never fail a run). pending counts as
  / SKIPPED in the summary (calibrated), so 1 passed + 2 skipped.
  skipIf[not .tst.golden.canQ; "f_skip_mix: skips/pending do not fail the run"]{
    r: .tst.golden.run .tst.golden.fixtures, "f_skip_mix.q -quiet";
    musteq[r`code; 0];
    must[.tst.golden.anyLike[r`out; "1 passed, 0 failed, 0 error, 2 skipped"];
         "1 passed + 2 skipped (pending counts as skipped)"];
  };

  / f_dsl_mix: should + retry + testOnly + holds in one block, exit 0,
  / no load error, no column 'mismatch.
  skipIf[not .tst.golden.canQ; "f_dsl_mix: mixed DSL in one block, exit 0, no mismatch"]{
    r: .tst.golden.run .tst.golden.fixtures, "f_dsl_mix.q -quiet";
    musteq[r`code; 0];
    must[not .tst.golden.anyLike[r`out; "FILE_LOAD_ERROR"];
         "no load error"];
    must[not .tst.golden.anyLike[r`out; "mismatch"];
         "no 'mismatch from mixing expec column shapes"];
  };

  / f_loaderr: exit 4 (LOAD_ERROR); load-error banner present.
  skipIf[not .tst.golden.canQ; "f_loaderr: exit 4 and load-error banner"]{
    r: .tst.golden.run .tst.golden.fixtures, "f_loaderr.q -quiet";
    musteq[r`code; 4];
    must[.tst.golden.anyLike[r`out; "FILE_LOAD_ERROR"] or
         .tst.golden.anyLike[r`out; "CRITICAL LOAD ERROR"];
         "load-error banner should appear"];
  };

  / Empty directory: exit 3 (NO_TESTS). The dir is created at runtime.
  skipIf[not .tst.golden.canQ; "empty dir: exit 3 (NO_TESTS)"]{
    wd: .tst.golden.workDir[];
    emptyDir: wd, "/emptydir";
    system "mkdir -p ", emptyDir;
    r: .tst.golden.run emptyDir, " -quiet";
    musteq[r`code; 3];
  };

  / Explicit missing file: an explicitly-named path that does not exist is a
  / user error (typo, deleted file), NOT "no tests found". It must fail with
  / EXIT.LOAD_ERROR (4) and report the missing path, rather than being silently
  / dropped to a NO_TESTS (3) exit.
  skipIf[not .tst.golden.canQ; "missing file: exit 4 (LOAD_ERROR) and reported"]{
    r: .tst.golden.run .tst.golden.fixtures, "f_does_not_exist_xyz.q -quiet";
    musteq[r`code; 4];
    must[.tst.golden.anyLike[r`out; "ERROR"] and .tst.golden.anyLike[r`out; "not found"];
         "missing path should produce an ERROR ... not found line"];
  };

  / \l system-command support: a test file may load its code-under-test with a
  / column-1 `\l <abs path>`, exactly like real qspec-era suites. `value` cannot
  / run `\` commands, so the loader rewrites them to `system "..."`. The fixture
  / needs an ABSOLUTE path resolved at runtime, so we generate the helper, the
  / test file (with a `\d .goldns` block exercising namespace directives), and
  / run resQ on it.
  skipIf[not .tst.golden.canQ; "f_sysload: \\l + \\d in a test file, exit 0, 1 passed"]{
    wd: .tst.golden.workDir[];
    system "mkdir -p ", wd;
    helper: wd, "/helper_gen.q";
    testF:  wd, "/test_sysload_gen.q";
    / Helper defines a function in an explicit namespace.
    (hsym `$helper) 0: enlist ".goldhelp.add:{x+y};";
    / Test file: \l the helper by absolute path, use a \d block to define a
    / namespaced value, then assert both the loaded fn and the \d value worked.
    (hsym `$testF) 0: (
      "\\l ", helper;
      "\\d .goldns";
      "answer:42;";
      "\\d .";
      ".tst.desc[\"sysload\"]{ should[\"loaded helper plus namespaced value\"]{";
      "  musteq[7; .goldhelp.add[3;4]];";
      "  musteq[42; .goldns.answer];";
      "}; };");
    r: .tst.golden.run testF, " -quiet";
    musteq[r`code; 0];
    must[.tst.golden.anyLike[r`out; "1 passed"];
         "f_sysload should load via \\l and pass its single test"];
    must[not .tst.golden.anyLike[r`out; "nyi"]; "must NOT fail with 'nyi"];
  };

  / Coverage end-to-end: `resq cover` must instrument source a test loads with
  / `\l` and emit a real LCOV report. We generate a self-contained src file (a
  / \d-namespaced module with TWO functions) and a test that \l's it and calls
  / exactly ONE of them. The rewritten \l routes through .tst.sysl, which loads
  / then instruments the module, so the LCOV must carry FN: records for BOTH
  / functions, FNDA:>0 for the called one, and FNDA:0 for the uncalled one. This
  / is the feature's definition of done; before the coverage fixes it produced
  / an empty report (every FNDA:0, or no SF: record at all).
  skipIf[not .tst.golden.canQ; "f_cover: \\l'd src instrumented, LCOV has FNDA>0 for called fn"]{
    wd: .tst.golden.workDir[];
    system "mkdir -p ", wd;
    srcF:  wd, "/cov_src_gen.q";
    testF: wd, "/test_cover_gen.q";
    / Src: a \d-namespaced module with two functions. `called` is exercised by
    / the test; `uncalled` is not, so its hit count must stay 0.
    (hsym `$srcF) 0: (
      "\\d .covmod";
      "called:{[x;y] x+y};";
      "uncalled:{[z] z*2};";
      "\\d .");
    / Test: \l the src by absolute path (rewritten to .tst.sysl + instrument),
    / then call ONLY .covmod.called.
    (hsym `$testF) 0: (
      "\\l ", srcF;
      ".tst.desc[\"cover\"]{ should[\"call one of two\"]{";
      "  musteq[7; .covmod.called[3;4]];";
      "}; };");
    r: .tst.golden.runCover testF;
    musteq[r`code; 0];
    must[not .tst.golden.anyLike[r`out; "nyi"]; "cover run must NOT fail with 'nyi"];
    lcov: .tst.golden.readFile[r`dir; "coverage.lcov"];
    / NB: q's `like` signals 'nyi when a pattern has 3+ wildcards, so we match
    / LCOV lines with leading-anchored, single-`*` patterns rather than the
    / `*..*`-wrapping anyLike helper. Lines are exact, so anchoring is fine.
    / Both functions appear as FN: records (the src was statically analyzed).
    must[any lcov like "FN:*,.covmod.called"; "LCOV should list FN:...called"];
    must[any lcov like "FN:*,.covmod.uncalled"; "LCOV should list FN:...uncalled"];
    / The src file appears as an SF: record.
    must[any lcov like "SF:*cov_src_gen.q"; "LCOV should reference the \\l'd src as SF:"];
    / The called fn has a NON-ZERO hit count (proving instrumentation fired):
    / isolate its FNDA line, then assert the count field is not 0.
    calledFnda: lcov where lcov like "FNDA:*,.covmod.called";
    must[0 < count calledFnda; "an FNDA line for .covmod.called should exist"];
    must[not any calledFnda like "FNDA:0,*";
         "FNDA for .covmod.called should be > 0"];
    / The uncalled fn records exactly zero hits.
    must[any lcov like "FNDA:0,.covmod.uncalled";
         "FNDA for .covmod.uncalled should be 0"];
  };

  / Symlink loop survival: a directory tree that cycles back on itself via a
  / symlink must not crash discovery AND must not rediscover the same test under
  / the loop. Discovery does not follow symlinked dirs, so the cycle branch is
  / never entered and the one real test is found EXACTLY once.
  skipIf[not .tst.golden.canQ; "symlink loop: survived, test found exactly once, exit 0"]{
    wd: .tst.golden.workDir[];
    loopDir: wd, "/loop";
    system "mkdir -p ", loopDir, "/sub";
    / Cycle: loop/sub/back -> loop
    system "ln -sf ", loopDir, " ", loopDir, "/sub/back";
    (hsym `$loopDir, "/test_loop_gen.q") 0:
      enlist ".tst.desc[\"loop\"]{ should[\"survives the cycle\"]{ musteq[1;1]; }; };";
    r: .tst.golden.run loopDir, " -quiet";
    musteq[r`code; 0];
    / Symlinked dirs are not followed, so the test runs exactly once: 1 total.
    must[.tst.golden.anyLike[r`out; "1 total (1 passed, 0 failed, 0 error"];
         "the test inside the symlink-looped dir should run exactly once"];
    must[not .tst.golden.anyLike[r`out; "symbolic links"];
         "the symlink loop must be survived, not crash the run"];
  };

  / Snapshot first-run under -strict must NOT silently create-and-pass: a fresh
  / CI workspace (no stored .snap) has to fail loudly so green-washing can't
  / happen. The mustmatchs signal errors the expectation -> nonzero exit.
  skipIf[not .tst.golden.canQ; "snapshot -strict first run: fails loudly, no green-wash"]{
    wd: .tst.golden.workDir[];
    system "mkdir -p ", wd;
    testF: wd, "/test_snap_strict_gen.q";
    (hsym `$testF) 0: (
      ".tst.desc[\"snap strict\"]{ should[\"missing snapshot under strict\"]{";
      "  .tst.mustmatchs[`a`b!1 2; \"golden_strict_firstrun\"];";
      "}; };");
    r: .tst.golden.run testF, " -strict -quiet";
    / The mustmatchs signal errors the expectation -> exit 1 (FAIL).
    musteq[r`code; 1];
    must[.tst.golden.anyLike[r`out; "Snapshot missing under -strict"];
         "the strict-missing-snapshot message should surface"];
  };

  / Without -strict the same first run creates the snapshot and passes, but
  / prints a NOTE so the new file is never committed unreviewed by accident.
  skipIf[not .tst.golden.canQ; "snapshot first run (no -strict): creates + NOTE, exit 0"]{
    wd: .tst.golden.workDir[];
    system "mkdir -p ", wd;
    testF: wd, "/test_snap_create_gen.q";
    (hsym `$testF) 0: (
      ".tst.desc[\"snap create\"]{ should[\"creates snapshot on first run\"]{";
      "  .tst.mustmatchs[`a`b!1 2; \"golden_create_firstrun\"];";
      "}; };");
    r: .tst.golden.run testF, " -quiet";
    musteq[r`code; 0];
    must[.tst.golden.anyLike[r`out; "NOTE: snapshot created"];
         "first-run snapshot creation should print a review NOTE"];
    must[not .utl.pathExists .resq.HOME,"/lib/tests/snapshots/golden_create_firstrun.snap";
         "framework module loading must not redirect snapshots under lib/"];
  };

  / Banner-comment idiom: a file opening with `/ ...` line comments, then a lone
  / `/` (block-comment open), some non-q garbage, a lone `\` (block close), then
  / the real test. Real q `\l` loads this fine - the garbage is swallowed by the
  / block comment. resQ's preprocessor must match: load OK, 1 passed, exit 0.
  / (Regression: the old prevBlank gate refused to open the block after a `/`
  / comment line, so the garbage hit `value` and threw CRITICAL LOAD ERROR.)
  skipIf[not .tst.golden.canQ; "banner block comment: loads, 1 passed, exit 0"]{
    wd: .tst.golden.workDir[];
    system "mkdir -p ", wd;
    testF: wd, "/test_banner_gen.q";
    / NB: lone "/" and "\" are 1-char strings (char ATOMS); they must be enlisted
    / so `0:` sees a uniform list of char vectors (a bare atom -> 'type).
    (hsym `$testF) 0: (
      "/ This is a banner comment";
      "/ describing the file";
      enlist "/";
      "garbage line that is not valid q at all";
      enlist "\\";
      ".tst.desc[\"banner\"]{ should[\"loads past the banner block\"]{";
      "  musteq[1;1];";
      "}; };");
    r: .tst.golden.run testF, " -quiet";
    musteq[r`code; 0];
    must[.tst.golden.anyLike[r`out; "1 passed, 0 failed, 0 error"];
         "banner fixture should load and report 1 passed"];
    must[not .tst.golden.anyLike[r`out; "CRITICAL LOAD ERROR"];
         "banner fixture must NOT throw a load error"];
  };

  / Block comment in the MIDDLE of a file, after real code: a lone `/` opens a
  / block that contains a fake `\l /nonexistent` and garbage, closed by a lone
  / `\`; code before and after the block both run. The fake \l must NEVER be
  / executed (it lives inside the dropped block), so no load failure - 1 passed.
  skipIf[not .tst.golden.canQ; "mid-file block comment: fake \\l swallowed, 1 passed"]{
    wd: .tst.golden.workDir[];
    system "mkdir -p ", wd;
    testF: wd, "/test_midblock_gen.q";
    (hsym `$testF) 0: (
      ".tst.midblock.before: 1;";
      enlist "/";
      "\\l /nonexistent/should/never/load.q";
      "garbage that would not parse as q";
      enlist "\\";
      ".tst.desc[\"midblock\"]{ should[\"code around a mid-file block runs\"]{";
      "  musteq[1; .tst.midblock.before];";
      "}; };");
    r: .tst.golden.run testF, " -quiet";
    musteq[r`code; 0];
    must[.tst.golden.anyLike[r`out; "1 passed, 0 failed, 0 error"];
         "mid-file-block fixture should load and report 1 passed"];
    must[not .tst.golden.anyLike[r`out; "nonexistent"];
         "the fake \\l inside the block must never be executed"];
  };

  / Duplicate spelling: the SAME file passed under two spellings (./x.q and x.q)
  / must register and run its tests exactly ONCE. Relative spellings require the
  / subprocess CWD to be the fixture dir, which .tst.golden.run already cd's into,
  / so we generate the file there and pass the bare relative names.
  skipIf[not .tst.golden.canQ; "dup spelling ./x.q x.q: suite counted once"]{
    wd: .tst.golden.workDir[];
    system "mkdir -p ", wd;
    (hsym `$wd, "/dup_gen.q") 0:
      enlist ".tst.desc[\"dup\"]{ should[\"runs once\"]{ musteq[1;1]; }; };";
    / Relative spellings resolve against the subprocess CWD, so we cd INTO the
    / fixture dir and pass the bare relative names. (Built inline rather than via
    / .tst.golden.run, which cds into its own fresh work dir.) mkdir -p mirrors
    / the proven .tst.golden.run command shape and is idempotent.
    cmd: "mkdir -p ", wd, " && cd ", wd, " && ", .tst.golden.timeoutPrefix, "q ", .resq.HOME,
         "/resq.q test ./dup_gen.q dup_gen.q -quiet > run_out.txt 2>&1; echo $?";
    lines: @[system; cmd; {[e] enlist "-1"}];
    code: "J"$ last lines;
    out: @[read0; hsym `$wd, "/run_out.txt"; {()}];
    musteq[code; 0];
    must[.tst.golden.anyLike[out; "1 total (1 passed, 0 failed, 0 error"];
         "the same file under two spellings should run its test exactly once"];
  };
 };

.tst.desc["Golden: report files #slow"]{
  / Per-test cleanup; idempotent rm of the exact literal prefix only.
  after{ .tst.golden.cleanupBase[] };

  / f_fail with -junit: real testcases, a failure node, escaped message, and
  / no illegal control bytes in the XML.
  skipIf[not .tst.golden.canQ; "f_fail -junit: parseable XML with 2 testcases + failure"]{
    r: .tst.golden.run .tst.golden.fixtures, "f_fail.q -junit -quiet";
    musteq[r`code; 1];
    lines: .tst.golden.readFile[r`dir; "test-results.xml"];
    xml: "\n" sv lines;
    must[0 < count lines; "test-results.xml should be written"];
    must[.tst.golden.anyLike[lines; "<testcase"]; "XML should contain <testcase"];
    musteq[count xml ss "<testcase"; 2];          / exactly 2 testcases
    must[.tst.golden.anyLike[lines; "<failure"]; "XML should contain <failure"];
    must[.tst.golden.anyLike[lines; "Got 1 — expected 2"];
         "failure message should appear in XML"];
    must[0 < count ss[xml;"f_fail.q\" line=\"4\""];
         "JUnit testcase should carry the source file and declaration line"];
    must[0 < count ss[xml;"f_fail.q\" line=\"5\""];
         "each JUnit testcase should retain its own declaration line"];
    / Report-message rendering fix: the failure text must be the plain message,
    / NOT the q literal form of a 1-element list (which escapes to `,&quot;` in
    / XML once the leading `,"` is &quot;-escaped).
    must[not .tst.golden.anyLike[lines; ",&quot;"];
         "no q-literal `,\"` artifact (escaped as ,&quot;) in the XML message"];
    must[not .tst.golden.anyLike[lines; "Error: type"];
         "no type-error leakage into XML"];
    / No control bytes below 0x20 except tab/LF/CR.
    raw: .tst.golden.readRaw[r`dir; "test-results.xml"];
    ctrl: "x"$ 1 2 3 4 5 6 7 8 11 12 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31;
    musteq[count raw where raw in ctrl; 0];
  };

  / beforeAll-throwing fixture with -junit: the runner synthesizes a single
  / error row whose time is a NULL timespan (0Nn). toSeconds must coerce that to
  / 0f so the XML carries the fixed xsd:decimal spelling time="0.000000000",
  / never time="" (invalid).
  / Generated at runtime per this file's existing fixture-generation pattern.
  skipIf[not .tst.golden.canQ; "beforeAll-failure -junit: fixed zero time"]{
    wd: .tst.golden.workDir[];
    system "mkdir -p ", wd;
    testF: wd, "/test_beforeall_fail_gen.q";
    (hsym `$testF) 0: (
      ".tst.desc[\"beforeAll throws\"]{";
      "  beforeAll{ '\"deliberate beforeAll failure\" };";
      "  should[\"never runs\"]{ musteq[1;1]; };";
      "};");
    r: .tst.golden.run testF, " -junit -quiet";
    lines: .tst.golden.readFile[r`dir; "test-results.xml"];
    must[0 < count lines; "test-results.xml should be written"];
    must[.tst.golden.anyLike[lines; "time=\"0.000000000\""];
         "synthetic beforeAll-failure row should carry fixed decimal zero"];
    must[not .tst.golden.anyLike[lines; "time=\"\""];
         "no empty time=\"\" attribute (invalid xsd:decimal)"];
  };

  / f_nasty with -junit: XML specials in titles are escaped; the raw <&>
  / sequence must NOT survive unescaped.
  skipIf[not .tst.golden.canQ; "f_nasty -junit: XML specials escaped"]{
    r: .tst.golden.run .tst.golden.fixtures, "f_nasty.q -junit -quiet";
    lines: .tst.golden.readFile[r`dir; "test-results.xml"];
    xml: "\n" sv lines;
    must[0 < count lines; "test-results.xml should be written"];
    must[.tst.golden.anyLike[lines; "&amp;"]; "& should be escaped to &amp;"];
    must[.tst.golden.anyLike[lines; "&lt;"]; "< should be escaped to &lt;"];
    musteq[count xml ss "<&>"; 0];                 / unescaped <&> absent
  };

  / f_pass with -json: native .j.k parse; field names per lib/output/json.q.
  / Note: .j.k yields numeric counts as floats, so 2 = testCount (2f) holds.
  skipIf[not .tst.golden.canQ; "f_pass -json: parseable JSON with 2 passing tests"]{
    r: .tst.golden.run .tst.golden.fixtures, "f_pass.q -json -quiet";
    musteq[r`code; 0];
    lines: .tst.golden.readFile[r`dir; "test-results.json"];
    must[0 < count lines; "test-results.json should be written"];
    j: .j.k raze lines;
    must[2 = j`schemaVersion; "JSON schemaVersion should be 2"];
    must[2 = j[`summary;`testCount]; "testCount should be 2"];
    must[2 = j[`summary;`assertionCount]; "assertionCount should aggregate row assertions"];
    must[2 = j[`summary;`passCount]; "passCount should be 2"];
    must[0 = j[`summary;`failCount]; "failCount should be 0"];
    st: j[`tests]`status;
    musteq[count st; 2];
    must[all st ~\: "pass"; "both tests should have status pass"];
  };

  skipIf[not .tst.golden.canQ; "f_fail -json: stable message type and source metadata"]{
    r: .tst.golden.run .tst.golden.fixtures, "f_fail.q -json -quiet";
    musteq[r`code; 1];
    j: .j.k raze .tst.golden.readFile[r`dir; "test-results.json"];
    failedRows: j[`tests] where j[`tests;`status] ~\: "fail";
    musteq[count failedRows; 1];
    must[10h = type first failedRows`message; "failure message must be a JSON string"];
    must[0 < count first failedRows`failures; "failure details must remain an array"];
    must[0 < count first failedRows`file; "test source file must reach JSON"];
    must[0 = count first failedRows`namespace;
         "generated sandbox namespace must not become a dashboard dimension"];
  };
 };
