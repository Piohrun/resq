/ resq.q - Unified CLI Entry Point
\e 1
/ Always load bootstrap
\l lib/bootstrap.q

/ Load Libraries
.utl.require "lib/init.q"
.utl.require "lib/config.q"
.utl.require "qutil/opts.q"

/ Load Features
.utl.require "lib/diff.q"
.utl.require "lib/snapshot.q"
.utl.require "lib/snapshot_txt.q"
.utl.require "lib/diff_assertions.q"
.utl.require "lib/mock.q"
.utl.require "lib/parallel_runner.q"
.utl.require "lib/watch.q"
.utl.require "lib/parametrize.q"
.utl.require "lib/async.q"
.utl.require "lib/bench.q"
.utl.require "lib/test_finder.q"

/ Load CLI/Runner
.utl.require "lib/cli.q"
.utl.require "lib/runner.q"

.tst.loadOutputModule["text"]

/ Initialize State (defaults set in lib/tests/internals.q)
/ Here we just reset for a fresh run
.tst.app.excludeSpecs: ();
.tst.app.runSpecs: ();
.tst.app.args: ();
.tst.app.allSpecs: ();
.tst.app.passed: 1b;
.tst.output.mode: `run;

/ Reset results table for fresh run
.resq.state.results: flip `suite`description`status`message`time`failures`assertsRun!(`symbol$(); `symbol$(); `symbol$(); (); `timespan$(); (); `int$());

/ Configuration
config: .tst.loadConfig[::];
.tst.applyConfig[config];

/ Initialize CLI
.tst.initCLI[];

/ Parse Args
.utl.parseArgs[];
if[not count .tst.app.args; .tst.app.args: .z.x where not .z.x like "-*"];

/ Handle Debug Flag
if[any .z.x like "-debug"; .utl.DEBUG: 1b];

/ Handle CLI Flags
if[any .z.x like "-strict"; .tst.app.strict: 1b];
if[count i: where .z.x like "-maxTestTime"; p: 1 + last i; if[p < count .z.x; .tst.app.maxTestTime: "I" $ .z.x p]];
if[count i: where .z.x like "-fuzzLimit"; p: 1 + last i; if[p < count .z.x; .tst.output.fuzzLimit: "I" $ .z.x p]];

/ Determine Mode
.resq.mode: `test;
args: .tst.app.args;

/ Safer Argument Parsing
if[0<count args; 
    cmd: first args; 
    if[cmd ~ "test"; .resq.mode: `test; .tst.app.args: 1 _ args]; 
    if[cmd ~ "cover"; .resq.mode: `cover; .tst.app.args: 1 _ args]; 
    if[cmd ~ "discover"; .resq.mode: `discover; .tst.app.args: 1 _ args]; 
    if[cmd ~ "watch"; .resq.mode: `watch; .tst.app.args: 1 _ args]
 ];

/ --- DISPATCH ---

/ MODE: COVER
if[.resq.mode ~ `cover; .tst.app.runCoverage: 1b; .resq.mode: `test];

/ MODE: TEST
if[.resq.mode ~ `test; 
    .tst.initReporting[]; 
    .tst.runAll[]; 
    if[not any .z.x like "-noquit"; 
        / Granular exit codes for CI/CD
        exitCode: $[0 < count .tst.app.loadErrors; .resq.EXIT.LOAD_ERROR;
                    not .tst.app.passed; .resq.EXIT.FAIL;
                    .resq.EXIT.PASS];
        exit exitCode
    ]
 ];

/ MODE: DISCOVER
if[.resq.mode ~ `discover;
    src: "examples/quickstart/src"; tst: "examples/quickstart/test";
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
    .tst.watch.runnerCmd: { 
        files: x;
        system "l lib/runner.q"; 
        .tst.app.exit: 0b;
        .tst.app.args: files;
        @[.tst.runAll; ::; {-1 "Error during test run: ", x}];
    };
    .tst.watch.init[dirs];
    .z.ts: { [x] changes: .tst.watch.check[]; if[0<count changes; .tst.watch.onChanges[changes]] };
    system "t 1000";
    -1 ">> Watch mode active. Press Ctrl+C to exit.";
 ];