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
.resq.state.results: flip `suite`description`status`message`time`failures`assertsRun!(`symbol$(); `symbol$(); `symbol$(); (); `timespan$(); (); `int$());

/ Initialize CLI
.tst.initCLI[];

/ Parse Args: collect positional args (everything not prefixed with -).
.tst.app.args: .z.x where not .z.x like "-*";

/ Handle Debug Flag
if[any .z.x like "-debug"; .utl.DEBUG: 1b];

/ Determine mode and leave only mode-specific positional args.
parsedMode: .tst.parseModeArgs .tst.app.args;
.resq.mode: parsedMode`mode;
.tst.app.args: parsedMode`args;
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
    .tst.initReporting[];
    .tst.runAll[];
    if[not any .z.x like "-noquit";
        / Granular exit codes for CI/CD
        noTestsFound: (0 = count .tst.app.discoveredFiles) and (0 = count .resq.state.results);
        exitCode: $[0 < count .tst.app.loadErrors; .resq.EXIT.LOAD_ERROR;
                    noTestsFound; .resq.EXIT.NO_TESTS;
                    not .tst.app.passed; .resq.EXIT.FAIL;
                    .resq.EXIT.PASS];
        exit exitCode
    ]
 ];

/ MODE: DISCOVER
if[.resq.mode ~ `discover;
    / Defaults point at the bundled quickstart inside the install root,
    / since "examples/quickstart" is only meaningful relative to resq itself.
    src: .resq.HOME, "/examples/quickstart/src"; tst: .resq.HOME, "/examples/quickstart/test";
    if[0<count .tst.app.args; src: .tst.app.args 0];
    if[1 < count .tst.app.args; tst: .tst.app.args 1];
    if[any .z.x like "-interactive"; .tst.start[]; exit 0];
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
    .z.ts: { [x] changes: .tst.watch.check[]; if[0<count changes; .tst.watch.onChanges[changes]] };
    system "t 1000";
    -1 ">> Watch mode active. Press Ctrl+C to exit.";
 ];
