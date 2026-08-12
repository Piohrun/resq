/ resq.q - Unified CLI Entry Point
\e 1

/ Resolve install root. Honor RESQ_HOME if set (bin/resq exports it), else
/ derive from .z.f (the path of this script). All framework module loads
/ use this absolute root so the user's CWD stays free for their own
/ test/discover paths.
.resq.envHome: getenv `RESQ_HOME;
.resq.HOME: $[count .resq.envHome;
              .resq.envHome;
              { p: string x; $[any p = "/"; (last where p = "/") # p; "."] } .z.f];
if[not "/" = first .resq.HOME; .resq.HOME: (system "cd"), "/", .resq.HOME];

/ Always load bootstrap (raw \l so we can pass an absolute path before
/ .utl.require exists).
system "l ", .resq.HOME, "/lib/bootstrap.q";
/ Canonicalize once bootstrap makes normalizePath available. This also removes
/ the trailing "/." produced by the documented `q resq.q ...` invocation.
.resq.HOME: .utl.normalizePath .resq.HOME;
.utl.resqHomeAtBoot: .resq.HOME;
.utl.PKGLOADING: .resq.HOME, "/lib";

/ A q `exit 0` cannot be cancelled or have its status changed from .z.exit.
/ The supported launchers therefore supervise test-mode completion through a
/ private directory. The callback adds an immediate diagnostic; the completion
/ marker makes the launcher fail closed even if application code replaces
/ .z.exit while tests are loading.
.resq.exitGuardDir: getenv `RESQ_RUN_GUARD_DIR;
.resq.exitGuardArmed: 0b;
.resq.exitGuardPrevious: @[get; `.z.exit; {::}];
.resq.exitGuardWrite:{[name;text]
    if[0 = count .resq.exitGuardDir; :0b];
    path: .resq.exitGuardDir, "/", name;
    @[
        {[pair]
            handle: hsym `$pair 0;
            handle 0: enlist pair 1;
            1b};
        (path;text);
        {[err]
            -2 "resQ ERROR: could not write process guard marker: ", err;
            0b}]
 };
.resq.armExitGuard:{[]
    .resq.exitGuardArmed: 1b;
    .resq.exitGuardWrite["armed";string .z.i];
    ::
 };
.resq.completeExitGuard:{[]
    if[.resq.exitGuardArmed;
        .resq.exitGuardWrite["complete";string .z.i]];
    .resq.exitGuardArmed: 0b;
    ::
 };
.resq.onProcessExit:{[code]
    if[.resq.exitGuardArmed;
        -2 "resQ ERROR: q exited before resQ completed the test run (requested exit ",
           string[code], ").";
        .resq.exitGuardWrite["premature";string code]];
    if[100h = type .resq.exitGuardPrevious;
        @[.resq.exitGuardPrevious;code;{[err]
            -2 "resQ WARNING: previous .z.exit handler failed: ", err}]];
    ::
 };
.z.exit:{[code] .resq.onProcessExit code};

/ Load Libraries
.utl.require .resq.HOME,"/lib/init.q"
.utl.require .resq.HOME,"/lib/config.q"

/ Load Features
.utl.require .resq.HOME,"/lib/parametrize.q"
.utl.require .resq.HOME,"/lib/async.q"
.utl.require .resq.HOME,"/lib/bench.q"

/ Load CLI/Runner
.utl.require .resq.HOME,"/lib/cli.q"
.utl.require .resq.HOME,"/lib/runner.q"

/ Configuration
config: .tst.loadConfig[::];
/ Validate config early; keep warnings non-fatal so execution can continue.
.resq.config.validationWarnings: .tst.validateConfig[config];
.tst.printConfigWarnings .resq.config.validationWarnings;
.tst.applyConfig[config];

/ Ensure text reporter is loaded before mode dispatch
textReporterLoaded: .tst.loadOutputModule "text";
if[not textReporterLoaded; -1 "WARNING: Falling back to built-in text reporter."];

/ Initialize State (defaults set in lib/dsl/internals.q)
/ Here we just reset for a fresh run
.tst.app.args: ();
.tst.app.allSpecs: ();
.tst.app.passed: 1b;
.tst.output.mode: `run;

/ Reset results table for fresh run
.resq.state.results: .resq.state.emptyResults[];

/ Parse exactly once. Invalid input exits before mode dispatch, test loading, or
/ reporter initialization, so malformed CLI input cannot run tests or create
/ output artifacts.
.resq.cli: .tst.parseCLI .z.x;
if[not .resq.cli`ok;
    -2 "CLI ERROR: ", .resq.cli`error;
    exit .resq.EXIT.FAIL];

.tst.initCLI .resq.cli;
.resq.mode: .resq.cli`mode;
.tst.app.args: .resq.cli`args;
args: .tst.app.args;

/ --- DISPATCH ---

/ MODE: COVER
if[.resq.mode ~ `cover; .tst.app.runCoverage: 1b; .resq.mode: `test];

/ MODE: TEST
if[.resq.mode ~ `test;
    / Convention: if no path is given and a local tests/ directory exists,
    / use it. Keeps `resq test` useful without making the path mandatory.
    if[(0 = count .tst.app.args) and .utl.isDir "tests";
        .tst.app.args: enlist "tests";
        -1 "No path specified; defaulting to tests/";
    ];
    / Isolation cannot compose truthfully with coverage instrumentation or
    / describe-only discovery. Reject both before reporter initialization or
    / test loading so no report/coverage artifact can be created.
    if[(1b ~ @[get; `.tst.app.isolate; 0b]) and
       (1b ~ @[get; `.tst.app.runCoverage; 0b]);
        -2 "CLI ERROR: process isolation cannot be combined with coverage";
        exit .resq.EXIT.FAIL];
    if[(1b ~ @[get; `.tst.app.isolate; 0b]) and
       (1b ~ @[get; `.tst.app.describeOnly; 0b]);
        -2 "CLI ERROR: process isolation cannot be combined with describe mode";
        exit .resq.EXIT.FAIL];

    .resq.armExitGuard[];
    .tst.initReporting[];
    / Process-isolation mode (-isolate): each discovered FILE runs in its own q
    / subprocess and the parent aggregates. runAll reports once and returns the
    / granular status; this entry point alone owns process exit policy.
    if[1b ~ @[get; `.tst.app.isolate; 0b];
        .resq.isolateExitCode: .tst.isolate.runAll .tst.app.args;
        .resq.completeExitGuard[];
        if[1b ~ .tst.app.exit;
            exit .resq.isolateExitCode];
    ];
    if[not 1b ~ @[get; `.tst.app.isolate; 0b];
        / -desc/-describe: specs are discovered but NOT executed, so the normal text
        / reporter would consume the empty results table and print a malformed
        / "( passed, failed, ...)" summary. Override the .resq.report hook with the
        / describe-listing reporter AFTER initReporting (the last thing to touch
        / .resq.report), so runAll's `.resq.report` call lands on our listing.
        if[1b ~ @[get; `.tst.app.describeOnly; 0b];
            .resq.report: .tst.describeReport;
        ];
        .tst.runAll[];
        .resq.completeExitGuard[];
        if[1b ~ .tst.app.exit;
            / -desc exits cleanly (0) when files loaded without error; a load error
            / still surfaces as LOAD_ERROR so a broken file is never silently listed.
            if[1b ~ @[get; `.tst.app.describeOnly; 0b];
                exit $[0 < count .tst.app.loadErrors; .resq.EXIT.LOAD_ERROR; .resq.EXIT.PASS];
            ];
            / Granular exit codes for CI/CD
            noTestsFound: (not 1b~@[get;`.tst.app.emptyShard;0b]) and
                (0 = count .tst.app.discoveredFiles) and (0 = count .resq.state.results);
            exitCode: $[0 < count .tst.app.loadErrors; .resq.EXIT.LOAD_ERROR;
                        noTestsFound; .resq.EXIT.NO_TESTS;
                        not .tst.app.passed; .resq.EXIT.FAIL;
                        .resq.EXIT.PASS];
            exit exitCode
        ];
    ];
 ];

/ MODE: DISCOVER
if[.resq.mode ~ `discover;
    / Defaults point at the bundled quickstart inside the install root,
    / since "examples/quickstart" is only meaningful relative to resq itself.
    src: .resq.HOME, "/examples/quickstart/src"; tst: .resq.HOME, "/examples/quickstart/test";
    if[0<count .tst.app.args; src: .tst.app.args 0];
    if[1 < count .tst.app.args; tst: .tst.app.args 1];
    if[.resq.cli[`options; `interactive]; .tst.start[]; exit 0];
    .tst.main[src; tst];
    exit 0;
 ];

/ MODE: WATCH
if[.resq.mode ~ `watch;
    dirs: enlist ".";
    if[0<count .tst.app.args; dirs: .tst.app.args];
    / lib/watch.q's default runnerCmd already anchors at .resq.HOME, so
    / there is no need to override it here.
    .tst.watch.init[dirs];
    -1 ">> Watch mode active. Press Ctrl+C to exit.";
    / Explicit foreground loop instead of .z.ts + `system "t": the timer
    / approach lets q reach EOF on stdin (CI, pipes, `< /dev/null`) and exit
    / before any tick fires. A blocking loop keeps the process alive without a
    / TTY. `system "sleep"` is portable; Ctrl+C still interrupts the loop.
    while[1b;
        system "sleep ", string .tst.watch.interval;
        changes: .tst.watch.check[];
        if[0 < count changes; .tst.watch.onChanges[changes]];
    ];
 ];
