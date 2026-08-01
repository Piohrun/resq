/ lib/isolate.q - Fail-safe process-per-file execution.
/ ============================================================================
/ The parent discovers files once, launches each in a preemptively bounded q
/ child, consumes a private JSON report, merges rows, reports once, and returns
/ the normal granular exit code. The caller owns process exit policy.
/ ============================================================================

\d .tst

.tst.isolate.commandPath:{[name]
    found: @[system; "command -v ", name, " 2>/dev/null"; {()}];
    $[count found; first found; ""]
 };

.tst.isolate.timeoutExe: .tst.isolate.commandPath "timeout";
.tst.isolate.qExe: .tst.isolate.commandPath "q";
.tst.isolate.mktempExe: .tst.isolate.commandPath "mktemp";
.tst.isolate.chmodExe: .tst.isolate.commandPath "chmod";
.tst.isolate.rmExe: .tst.isolate.commandPath "rm";
.tst.isolate.shExe: .tst.isolate.commandPath "sh";

/ Require timeout's kill-after form and prove it can preempt a busy process.
.tst.isolate.probeTimeout:{[exe]
    if[(0 = count exe) or 0 = count .tst.isolate.shExe; :0b];
    busy: .utl.shellQuote "while :; do :; done";
    cmd: .utl.shellQuote[exe], " -k 1 0.05 ",
         .utl.shellQuote[.tst.isolate.shExe], " -c ", busy, "; echo $?";
    out: @[system; cmd; {[e] enlist "-1"}];
    if[0 = count out; :0b];
    code: "J"$last out;
    code in 124 137
 };

/ Scratch directories are tracked as strings; only paths returned by mktemp and
/ present in this allocation list may be recursively removed.
.tst.isolate.allocated: ();

/ Shares .utl.tempRoot (which honours TMPDIR) and then enforces the stricter
/ requirements isolation has: the root must exist and be a real directory,
/ because child processes are about to write scratch into it.
.tst.isolate.tempRoot:{[]
    root: .utl.tempRoot[];
    if[(0 = count root) or not "/" = first root;
        '"TMPDIR must be an absolute directory: ", root];
    if[not .utl.isDir root;
        '"TMPDIR does not exist or is not a directory: ", root];
    root
 };

.tst.isolate.scratchPrefix:{[root]
    root, $["/" = last root; ""; "/"], "resq_isolate."
 };

.tst.isolate.validScratch:{[wd]
    root: .tst.isolate.tempRoot[];
    prefix: .tst.isolate.scratchPrefix root;
    suffix: (count prefix) _ wd;
    (wd like prefix, "*") and
        (0 < count suffix) and
        (not any "/" = suffix) and
        any wd ~/: .tst.isolate.allocated
 };

.tst.isolate.createScratch:{[]
    if[0 = count .tst.isolate.mktempExe; '"mktemp executable is required for isolation"];
    if[0 = count .tst.isolate.chmodExe; '"chmod executable is required for isolation"];
    root: .tst.isolate.tempRoot[];
    template: (.tst.isolate.scratchPrefix root), "XXXXXXXX";
    cmd: .utl.shellQuote[.tst.isolate.mktempExe], " -d ", .utl.shellQuote template;
    made: @[system; cmd; {[e] '"mktemp failed: ", e}];
    if[0 = count made; '"mktemp returned no scratch directory"];
    wd: first made;
    prefix: .tst.isolate.scratchPrefix root;
    suffix: (count prefix) _ wd;
    if[(not wd like prefix, "*") or (0 = count suffix) or any "/" = suffix;
        '"mktemp returned an unsafe scratch path: ", wd];
    if[not .utl.isDir wd; '"mktemp scratch directory does not exist: ", wd];
    .tst.isolate.allocated,: enlist wd;
    secured: @[
        {system x; 1b};
        .utl.shellQuote[.tst.isolate.chmodExe], " 700 -- ", .utl.shellQuote wd;
        {[e] 0b}];
    if[not secured;
        .tst.isolate.cleanupScratch wd;
        '"failed to restrict isolation scratch permissions: ", wd;
    ];
    wd
 };

.tst.isolate.cleanupScratch:{[wd]
    if[not .tst.isolate.validScratch wd;
        -1 "ERROR: refusing unsafe isolation scratch cleanup: ", wd;
        :0b];
    if[0 = count .tst.isolate.rmExe;
        -1 "ERROR: rm executable unavailable; cannot clean isolation scratch: ", wd;
        :0b];
    cmd: .utl.shellQuote[.tst.isolate.rmExe], " -rf -- ", .utl.shellQuote wd;
    ok: @[{system x; 1b}; cmd; {[e] 0b}];
    inspected: @[
        {[path] `ok`exists!(1b; .utl.pathExists path)};
        wd;
        {[e] `ok`exists!(0b; 1b)}];
    if[not inspected`ok;
        -1 "ERROR: unable to inspect isolation scratch after cleanup: ", wd;
        :0b];
    if[inspected`exists; ok: 0b];
    if[ok;
        .tst.isolate.allocated:
            .tst.isolate.allocated where not wd ~/: .tst.isolate.allocated];
    ok
 };

.tst.isolate.toStrList:{[v]
    $[10h = type v; enlist v;
      0h = type v; v;
      (::) ~ v; ();
      enlist .tst.toString v]
 };

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

.tst.isolate.errorRow:{[suiteSym; file; msg]
    .tst.isolate.row[suiteSym; `$file; `error; msg; 0Nn; enlist msg; 0i]
 };

.tst.isolate.processExitRow:{[file; code; unexpected]
    msg: $[unexpected;
        "child produced a valid report but exited with unexpected code ",
            string[code], "; process status and report disagree";
        "child produced a valid report with no failing rows but exited with code ",
            string[code], "; refusing inconsistent success"];
    .tst.isolate.errorRow[`ISOLATED_PROCESS_EXIT; file; msg]
 };

.tst.isolate.tail:{[wd; n]
    lines: @[read0; hsym `$wd, "/out.txt"; {()}];
    lines: (neg n) sublist lines;
    $[count lines; "\n" sv lines; ""]
 };

.tst.isolate.rowsFromJson:{[tests]
    tests: $[98h = type tests; {[t;i] t i}[tests] each til count tests;
             99h = type tests; enlist tests;
             0h = type tests; tests;
             enlist tests];
    {[t]
        suite: `$ .tst.toString t`suite;
        dsc: `$ .tst.toString t`description;
        status: `$ .tst.toString t`status;
        msg: $[`message in key t; t`message; ""];
        msg: $[0h = type msg; .tst.isolate.toStrList msg; msg];
        tmText: $[`time in key t; .tst.toString t`time; ""];
        tm: $[count tmText; @["N"$; tmText; 0Nn]; 0Nn];
        fails: .tst.isolate.toStrList $[`failures in key t; t`failures; ()];
        asserts: $[`assertsRun in key t; t`assertsRun; 0];
        .tst.isolate.row[suite; dsc; status; msg; tm; fails; asserts]
    } each tests
 };

.tst.isolate.decodeReport:{[raw]
    if[0 = count raw; :`valid`report`error!(0b; ()!(); "report missing")];
    attempt: @[
        {[text] `ok`value!(1b; .j.k text)};
        "\n" sv raw;
        {[e] `ok`value!(0b; ()!())}];
    report: attempt`value;
    valid: (1b ~ attempt`ok) and (99h = type report) and `tests in key report;
    error: $[valid; ""; $[1b ~ attempt`ok; "JSON report missing tests"; "malformed JSON report"]];
    `valid`report`error!(valid; report; error)
 };

.tst.isolate.appendValue:{[argv; flag; val]
    $[0 < count val; argv, (flag; .tst.toString val); argv]
 };

.tst.isolate.appendFlag:{[argv; flag; enabled]
    $[1b ~ enabled; argv, enlist flag; argv]
 };

/ Child argv derives from normalized CLI values plus effective parent settings.
/ Parent reporter/lifecycle/isolation options are deliberately absent.
.tst.isolate.childArgv:{[file; wd]
    options: .resq.cli`options;
    argv: (.tst.isolate.qExe; .resq.HOME, "/resq.q"; "test"; file);
    argv: .tst.isolate.appendValue[argv; "-only"; options`only];
    argv: .tst.isolate.appendValue[argv; "-exclude"; options`exclude];
    argv: .tst.isolate.appendValue[argv; "-tag"; options`tag];
    argv: .tst.isolate.appendValue[argv; "-exclude-tag"; options`excludeTag];
    argv: .tst.isolate.appendFlag[argv; "-strict"; @[get; `.tst.app.strict; 0b]];
    argv: .tst.isolate.appendFlag[argv; "-perf"; @[get; `.tst.app.runPerformance; 0b]];
    argv: .tst.isolate.appendFlag[argv; "-fail-hard"; @[get; `.tst.app.failHard; 0b]];
    argv: .tst.isolate.appendValue[argv; "-maxTestTime"; @[get; `.tst.app.maxTestTime; 0]];
    argv: .tst.isolate.appendValue[argv; "-fuzzLimit"; @[get; `.tst.output.fuzzLimit; 0]];
    argv: .tst.isolate.appendFlag[argv; "-quiet"; @[get; `.tst.app.quiet; 0b]];
    argv, ("-json"; "-outDir"; wd)
 };

.tst.isolate.shellCommand:{[argv]
    " " sv .utl.shellQuote each argv
 };

.tst.isolate.runFileBody:{[wd; file; timeoutSecs; k; n]
    childArgv: .tst.isolate.childArgv[file; wd];
    timedArgv: (.tst.isolate.timeoutExe; "-k"; .tst.toString 5; string timeoutSecs), childArgv;
    outPath: wd, "/out.txt";
    cmd: .tst.isolate.shellCommand[timedArgv],
         " < /dev/null > ", .utl.shellQuote[outPath], " 2>&1; echo $?";
    statusLines: @[system; cmd; {[e] enlist "-1"}];
    code: "J"$last statusLines;
    raw: @[read0; hsym `$wd, "/test-results.json"; {()}];
    decoded: .tst.isolate.decodeReport raw;
    valid: decoded`valid;
    report: decoded`report;
    tests: $[valid; report`tests; ()];
    rows: $[valid; .tst.isolate.rowsFromJson tests; ()];
    rowStatus: $[count rows;
        .tst.normalizeResultStatus each {first x`status} each rows;
        `symbol$()];
    hasFailingRows: any rowStatus in `fail`error;
    progress: "[", string[k], "/", string[n], "] ", file, " ... ";

    if[code in 124 137;
        msg: "file exceeded isolateTimeout (", string[timeoutSecs], "s); killed",
             $[count detail: .tst.isolate.tail[wd; 20]; "\n", detail; ""];
        -1 progress, "TIMEOUT";
        :enlist .tst.isolate.errorRow[`ISOLATED_FILE_TIMEOUT; file; msg]];

    if[code = .resq.EXIT.LOAD_ERROR;
        hasLoadRow: $[count rows;
            any ({first x`suite} each rows) = `FILE_LOAD_ERROR;
            0b];
        if[hasLoadRow;
            -1 progress, "LOAD ERROR (", string[count rows], " rows)";
            :rows];
        msg: "file failed to load (exit 4)",
             $[count detail: .tst.isolate.tail[wd; 20]; "\n", detail; ""];
        -1 progress, "LOAD ERROR";
        :rows, enlist .tst.isolate.errorRow[`FILE_LOAD_ERROR; file; msg]];

    if[valid;
        if[code = .resq.EXIT.PASS;
            -1 progress, "ok (", string[count rows], " tests)";
            :rows];
        if[(code = .resq.EXIT.FAIL) and hasFailingRows;
            -1 progress, "FAILED (", string[count rows], " tests)";
            :rows];
        expectedCodes: (.resq.EXIT.PASS; .resq.EXIT.FAIL; .resq.EXIT.LOAD_ERROR);
        unexpected: not code in expectedCodes;
        processRow: .tst.isolate.processExitRow[file; code; unexpected];
        -1 progress, "PROCESS ERROR (exit ", string[code], ")";
        :rows, enlist processRow];

    detail: .tst.isolate.tail[wd; 20];
    if[0 = count raw;
        msg: "process exited (code ", string[code],
             ") without producing results - did a test call exit?",
             $[count detail; "\n", detail; ""];
        -1 progress, "DIED (exit ", string[code], ", no results)";
        :enlist .tst.isolate.errorRow[`ISOLATED_FILE_DIED; file; msg]];

    msg: decoded`error, " (exit ", string[code], ")",
         $[count detail; "\n", detail; ""];
    -1 progress, "INVALID REPORT";
    enlist .tst.isolate.errorRow[`ISOLATED_REPORT_ERROR; file; msg]
 };

.tst.isolate.runFile:{[file; timeoutSecs; k; n]
    scratchAttempt: @[
        {[ignored] `ok`wd!(1b; .tst.isolate.createScratch[])};
        ();
        {[e] `ok`wd!(0b; e)}];
    if[not scratchAttempt`ok;
        msg: "unable to create private isolation scratch: ", .tst.toString scratchAttempt`wd;
        :enlist .tst.isolate.errorRow[`ISOLATED_SETUP_ERROR; file; msg]];

    wd: scratchAttempt`wd;
    result: .[
        .tst.isolate.runFileBody;
        (wd; file; timeoutSecs; k; n);
        {[file; e]
            msg: "isolation helper failed: ", e;
            enlist .tst.isolate.errorRow[`ISOLATED_HELPER_ERROR; file; msg]
        }[file;]];
    cleaned: @[
        .tst.isolate.cleanupScratch;
        wd;
        {[file; e]
            -1 "ERROR: isolation scratch cleanup failed for ", file, ": ", e;
            0b
        }[file;]];
    if[not cleaned;
        result,: enlist .tst.isolate.errorRow[
            `ISOLATED_CLEANUP_ERROR; file; "failed to remove private isolation scratch"]];
    result
 };

.tst.isolate.parentLoadRows:{[]
    errors: $[`loadErrors in key `.tst.app;
        .tst.app.loadErrors;
        flip `file`error`type!(`symbol$(); (); `symbol$())];
    if[0 = count errors; :()];
    records: {[table; i] table i}[errors] each til count errors;
    {[record]
        file: .tst.toString record`file;
        msg: "Explicit test path failed discovery: ", file, " (", .tst.toString[record`error], ")";
        .tst.isolate.errorRow[`FILE_LOAD_ERROR; file; msg]
    } each records
 };

.tst.isolate.upsertRows:{[rows]
    if[0 = count rows; :()];
    {[row] .resq.state.results: .resq.state.results upsert row} each rows;
 };

.tst.isolate.dropChildStrict:{[]
    if[0 = count .resq.state.results; :()];
    .resq.state.results:
        select from .resq.state.results where suite <> `STRICT_MODE_FAILURE;
 };

.tst.isolate.executedCount:{[]
    if[0 = count .resq.state.results; :0];
    status: .tst.normalizeResultStatus each .resq.state.results`status;
    synthetic:`STRICT_MODE_FAILURE`FILE_LOAD_ERROR`ISOLATED_FILE_TIMEOUT`ISOLATED_FILE_DIED`ISOLATED_REPORT_ERROR`ISOLATED_PROCESS_EXIT`ISOLATED_SETUP_ERROR`ISOLATED_HELPER_ERROR`ISOLATED_CLEANUP_ERROR`ISOLATION_UNAVAILABLE;
    executed: status in `pass`fail`error;
    generated: (.resq.state.results`suite) in synthetic;
    sum executed where not generated
 };

.tst.isolate.addGlobalStrict:{[]
    if[not 1b ~ @[get; `.tst.app.strict; 0b]; :()];
    if[0 < .tst.app.expectationsRan; :()];
    .tst.isolate.upsertRows enlist .tst.isolate.errorRow[
        `STRICT_MODE_FAILURE;
        "NO_TESTS_FOUND";
        "Strict mode enabled but no tests were executed (skipped tests do not count under -strict)."]
 };

/ Discover, execute, merge, report, and return one granular exit code.
.tst.isolate.runAll:{[paths]
    timeoutSecs: @[get; `.tst.app.isolateTimeout; 300];
    .resq.state.results: .resq.state.emptyResults[];
    .tst.app.baseDir: system "cd";
    .tst.app.loadErrors: flip `file`error`type!(`symbol$(); (); `symbol$());

    files: .tst.findTests paths;
    n: count files;
    .tst.app.discoveredFiles: files;
    .tst.isolate.upsertRows .tst.isolate.parentLoadRows[];

    unavailable: 0b;
    if[0 < n;
        unavailable: (not .tst.isolate.probeTimeout .tst.isolate.timeoutExe) or
            (0 = count .tst.isolate.qExe) or
            (0 = count .tst.isolate.mktempExe) or
            (0 = count .tst.isolate.chmodExe) or
            (0 = count .tst.isolate.rmExe) or
            (0 = count .tst.isolate.shExe);
    ];
    if[unavailable;
        msg: "Process isolation requires a working timeout with -k support and q/mktemp/chmod/rm/sh executables.";
        -1 "ERROR: ", msg;
        .tst.isolate.upsertRows enlist .tst.isolate.errorRow[
            `ISOLATION_UNAVAILABLE; "isolation"; msg];
    ];

    if[(not unavailable) and 0 < n;
        -1 "Running ", string[n], " test file(s) in isolated subprocesses (timeout ",
            string[timeoutSecs], "s each)";
        {[files; timeoutSecs; n; i]
            .tst.isolate.upsertRows
                .tst.isolate.runFile[files i; timeoutSecs; i + 1; n]
        }[files; timeoutSecs; n] each til n;
    ];

    .tst.isolate.dropChildStrict[];
    .tst.app.expectationsRan: .tst.isolate.executedCount[];
    .tst.isolate.addGlobalStrict[];

    .resq.report .resq.state.results;

    status: .tst.normalizeResultStatus each .resq.state.results`status;
    hasLoadError: any (.resq.state.results`suite) in `FILE_LOAD_ERROR;
    anyFailure: any status in `fail`error;
    noResults: 0 = count .resq.state.results;
    exitCode: $[hasLoadError; .resq.EXIT.LOAD_ERROR;
                0 = n; .resq.EXIT.NO_TESTS;
                unavailable; .resq.EXIT.FAIL;
                noResults; .resq.EXIT.FAIL;
                anyFailure; .resq.EXIT.FAIL;
                .resq.EXIT.PASS];
    .tst.app.passed: exitCode = .resq.EXIT.PASS;
    exitCode
 };

\d .
