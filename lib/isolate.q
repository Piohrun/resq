/ lib/isolate.q - Opt-in process isolation mode.
/ ============================================================================
/ Each discovered test FILE runs in its OWN q subprocess; the parent process
/ aggregates the per-file JSON reports back into .resq.state.results and drives
/ the normal reporting + exit pipeline.
/ .
/ Why: three failure modes silently corrupt a normal in-process run -
/   1. a test that calls `exit`        (kills the whole run; exit 0 fakes success)
/   2. an infinite loop                (hangs forever; maxTestTime only checks
/                                        AFTER a test returns)
/   3. a process-fatal error (wsfull / stack)
/ Isolation converts each into a per-FILE failure row instead of a run-killer.
/ .
/ Subprocess pattern (mirrors tests/golden/test_golden.q): q's `system "cmd"`
/ THROWS 'os on a nonzero child exit, and INTERCEPTS a leading "cd" / rejects a
/ leading "(". So every command LEADS with `mkdir -p`, appends `; echo $?` (the
/ shell then always exits 0 and the real child code is the last stdout line),
/ and feeds the nested q `< /dev/null` so it reaches EOF and exits.
/ ============================================================================

\d .tst

/ --- timeout probe (once) --------------------------------------------------
/ `timeout` guards against hung children but is not present everywhere (stock
/ macOS). Probe ONCE; without it there is no preemption (the hang scenario
/ cannot be killed) so we warn a single time when isolation actually runs.
.tst.isolate.canTimeout: 0 < count @[system; "which timeout 2>/dev/null"; {()}];
.tst.isolate.timeoutWarned: 0b;

/ Unique work-dir per file. .z.i (pid) is stable within this process; a
/ per-call counter keeps each file's dir distinct (no .z.p randomness needed).
.tst.isolate.base: "/tmp/resq_isolate";
.tst.isolate.counter: 0;
.tst.isolate.workDir:{[]
    .tst.isolate.counter+: 1;
    .tst.isolate.base, "/run_", string[.z.i], "_", string .tst.isolate.counter
 };

/ Normalize a JSON-decoded string-or-list-of-strings field into a list of
/ strings. .j.k collapses a single-element JSON array to a bare char vector
/ (type 10h) and leaves [] / multi-element arrays as a general list (0h).
.tst.isolate.toStrList:{[v]
    $[10h = type v; enlist v;
      0h = type v; v;
      (::) ~ v; ();
      enlist .tst.toString v]
 };

/ Build one .resq.state.results row (the flat 7-column schema) as a 1-row table
/ suitable for upsert.
.tst.isolate.row:{[suite; dsc; status; message; tm; failures; asserts]
    flip `suite`description`status`message`time`failures`assertsRun!(
        enlist suite;
        enlist dsc;
        enlist status;
        enlist message;
        enlist tm;
        enlist failures;
        enlist `int$asserts)
 };

/ Synthesize a single error row for a file (timeout / died / load-error).
.tst.isolate.errorRow:{[suiteSym; file; msg]
    .tst.isolate.row[suiteSym; `$file; `error; msg; 0Nn; enlist msg; 0i]
 };

/ Tail of the captured child stdout (last N lines), joined for a message.
.tst.isolate.tail:{[wd; n]
    lines: @[read0; hsym `$wd, "/out.txt"; {()}];
    lines: (neg n) sublist lines;
    $[count lines; "\n" sv lines; ""]
 };

/ Convert the `tests` array of a parsed JSON report into flat result rows and
/ return them as a list of 1-row tables. Each JSON row carries the sanitized
/ superset schema (suite/description/status/message/time/failures/assertsRun +
/ file/namespace/tags); we keep the 7 columns of .resq.state.results. Times come
/ back as STRINGS ("0D00:00:00.00...") - parse with "N"$ or store 0Nn.
.tst.isolate.rowsFromJson:{[tests]
    / .j.k returns a TABLE (98h) when every JSON object shares the same keys, a
    / single DICT (99h) for a 1-element array that decoded to a lone object, or a
    / general list (0h) for ragged arrays. Normalize all three to a list of row
    / dicts so `each` below sees one expectation per iteration.
    tests: $[98h = type tests; {[t;i] t i}[tests] each til count tests;
             99h = type tests; enlist tests;
             0h  = type tests; tests;
             enlist tests];
    {[t]
        / NB: a local named `desc` collides with the DSL `desc` global (an
        / 'assign error at parse time), so use `dsc`. Same hazard as fixture/prev.
        suite:  `$ .tst.toString t`suite;
        dsc:    `$ .tst.toString t`description;
        status: `$ .tst.toString t`status;
        msg:    $[`message in key t; t`message; ""];
        / message may be a single string (10h) or a list of strings (0h).
        msg:    $[0h = type msg; .tst.isolate.toStrList msg; msg];
        tmStr:  $[`time in key t; .tst.toString t`time; ""];
        tm:     $[count tmStr; @["N"$; tmStr; 0Nn]; 0Nn];
        fails:  .tst.isolate.toStrList $[`failures in key t; t`failures; ()];
        asserts: $[`assertsRun in key t; t`assertsRun; 0];
        .tst.isolate.row[suite; dsc; status; msg; tm; fails; asserts]
    } each tests
 };

/ Run one file in its own subprocess and return the rows it produced (or a
/ synthesized error row). `k`/`n` drive the [k/N] progress line.
.tst.isolate.runFile:{[file; timeoutSecs; k; n]
    wd: .tst.isolate.workDir[];
    qFile: .utl.shellQuote file;
    qHome: .utl.shellQuote .resq.HOME, "/resq.q";
    qWd:   .utl.shellQuote wd;
    qOut:  .utl.shellQuote wd, "/out.txt";
    / timeout only when the binary is present; otherwise run unguarded.
    / `-k 5` (kill-after) escalates to SIGKILL 5s after the initial SIGTERM:
    / a q child in a tight `while[1b;()]` loop never polls signals, so a plain
    / `timeout N` SIGTERM is ignored and the child hangs forever. The KILL is
    / unconditional, so an infinite-loop file is reliably reaped. timeout exits
    / 124 on the SIGTERM path and 137 (128+SIGKILL) when it had to escalate.
    timeoutPrefix: $[.tst.isolate.canTimeout; "timeout -k 5 ", string[timeoutSecs], " "; ""];
    / CRITICAL: lead with mkdir (q's system rejects a leading cd / "("); nested
    / q needs < /dev/null; `; echo $?` absorbs the child exit code onto stdout.
    cmd: "mkdir -p ", qWd,
         " && ", timeoutPrefix, "q ", qHome, " test ", qFile,
         " -json -outDir ", qWd, " -quiet < /dev/null > ", qOut, " 2>&1; echo $?";
    lines: @[system; cmd; {[e] enlist "-1"}];
    code: "J"$ last lines;

    jsonFile: hsym `$wd, "/test-results.json";
    rawJson: @[read0; jsonFile; {()}];
    report: $[count rawJson; @[.j.k; "\n" sv rawJson; {()!()}]; ()!()];
    tests: $[`tests in key report; report`tests; ()];
    hasTests: 0 < count tests;

    progress: "[", string[k], "/", string[n], "] ", file, " ... ";

    result: $[
        / timeout kill: 124 (timeout) or 137 (SIGKILL after KILL-after).
        code in 124 137;
            [ msg: "file exceeded isolateTimeout (", string[timeoutSecs], "s); killed",
                   $[count tl: .tst.isolate.tail[wd; 20]; "\n", tl; ""];
              -1 progress, "TIMEOUT";
              enlist .tst.isolate.errorRow[`ISOLATED_FILE_TIMEOUT; file; msg] ];
        / load error: exit 4. JSON may carry FILE_LOAD_ERROR rows - use it if
        / present, else synthesize a load-error row.
        code = .resq.EXIT.LOAD_ERROR;
            $[hasTests;
                [ -1 progress, "LOAD ERROR (", string[count tests], " rows)";
                  .tst.isolate.rowsFromJson tests ];
                [ msg: "file failed to load (exit 4)",
                       $[count tl: .tst.isolate.tail[wd; 20]; "\n", tl; ""];
                  -1 progress, "LOAD ERROR";
                  enlist .tst.isolate.errorRow[`FILE_LOAD_ERROR; file; msg] ] ];
        / normal path: JSON present with tests -> round-trip the rows.
        hasTests;
            [ -1 progress, $[code = 0; "ok"; "FAILED"], " (", string[count tests], " tests)";
              .tst.isolate.rowsFromJson tests ];
        / exit 0 (or anything) but NO results: the exit-0-catching contract.
        / A test that called `exit` lands here.
            [ msg: "process exited (code ", string[code],
                   ") without producing results - did a test call exit?",
                   $[count tl: .tst.isolate.tail[wd; 20]; "\n", tl; ""];
              -1 progress, "DIED (exit ", string[code], ", no results)";
              enlist .tst.isolate.errorRow[`ISOLATED_FILE_DIED; file; msg] ]
    ];
    result
 };

/ ----------------------------------------------------------------------------
/ Public entry point: discover files, run each in its own subprocess, merge,
/ report, and exit with the normal granular codes.
/ ----------------------------------------------------------------------------
.tst.isolate.runAll:{[paths]
    timeoutSecs: $[`isolateTimeout in key `.tst.app; .tst.app.isolateTimeout; 300];

    files: .tst.findTests paths;
    n: count files;

    if[(not .tst.isolate.canTimeout) and not .tst.isolate.timeoutWarned;
        -1 "WARNING: `timeout` binary not found; isolated files run WITHOUT preemption (a hanging test will hang the run).";
        .tst.isolate.timeoutWarned: 1b;
    ];

    -1 "Running ", string[n], " test file(s) in isolated subprocesses (timeout ", string[timeoutSecs], "s each)";

    / Fresh results table.
    .resq.state.results: .resq.state.emptyResults[];
    .tst.app.baseDir: system "cd";

    / Sequential spawns only (no parallelism) - merge each file's rows as we go.
    if[0 < n;
        {[files; timeoutSecs; n; i]
            rows: .tst.isolate.runFile[files i; timeoutSecs; i + 1; n];
            {[r] .resq.state.results: .resq.state.results upsert r} each rows;
        }[files; timeoutSecs; n] each til n;
    ];

    / Strict semantics: no executed tests -> a strict failure row. Mirrors
    / runner.q applyStrictMode (which keys off .tst.app.expectationsRan); here
    / the equivalent signal is an empty merged results table.
    if[(1b ~ @[get; `.tst.app.strict; 0b]) and 0 = count .resq.state.results;
        `.resq.state.results upsert .tst.isolate.errorRow[`STRICT_MODE_FAILURE; "NO_TESTS_FOUND";
            "Strict mode enabled but no tests were executed."];
    ];

    / Drive the EXISTING reporting pipeline. .resq.report is whatever
    / initReporting installed (text / junit / xunit / json) and consumes the
    / flat results table directly.
    .resq.report .resq.state.results;

    / --- exit dispatch (reuse the normal constants / precedence) -------------
    statusNorm: .tst.normalizeResultStatus each .resq.state.results`status;
    hasLoadErr: any .resq.state.results[`suite] in `FILE_LOAD_ERROR;
    anyFail: any statusNorm in `fail`error;

    exitCode: $[hasLoadErr;          .resq.EXIT.LOAD_ERROR;
                0 = n;               .resq.EXIT.NO_TESTS;
                anyFail;             .resq.EXIT.FAIL;
                .resq.EXIT.PASS];

    .tst.app.passed: not anyFail;

    if[not any .z.x like "-noquit"; exit exitCode];
    exitCode
 };

\d .
