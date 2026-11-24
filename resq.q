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

/ q's loader splits a path containing spaces. Bootstrap from its directory so
/ a supported checkout path may contain whitespace, then restore the project
/ directory before any user/config path is resolved.
.resq.startCwd: system "cd";
system "cd ", .resq.HOME, "/lib";
system "l bootstrap.q";
system "cd ", .resq.startCwd;
/ Canonicalize once bootstrap makes normalizePath available. This also removes
/ the trailing "/." produced by the documented `q resq.q ...` invocation.
.resq.HOME: .resq.util.normalizePath .resq.HOME;
.resq.homeAtBoot: .resq.HOME;
.resq.PKGLOADING: .resq.HOME, "/lib";
if[not .resq.hasQutil; .resq.offerUtl[`PKGLOADING; .resq.PKGLOADING]];

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
/ The run's verdict, for the launcher. With -noquit or "exit": false this
/ script does not call exit, and under the launcher q then ends at the end of
/ its input with status 0, whatever the tests did. The launcher takes the
/ status from here instead.
.resq.recordVerdict:{[code]
    .resq.exitGuardWrite["verdict";string code];
    ::
 };
/ The launcher was told to stop, and the run ended early without writing a
/ report or state (.tst.noteInterrupted). Leave with the status the launcher
/ leaves with; this is not q exiting behind resQ's back.
.resq.endInterruptedRun:{[]
    if[not 1b ~ @[get; `.tst.app.interrupted; 0b]; :(::)];
    -2 "resQ: interrupted. The run stopped early; no report or state file was written.";
    .resq.exitGuardArmed: 0b;
    exit .resq.util.interruptExitCode[]
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
.resq.require .resq.HOME,"/lib/init.q"
.resq.require .resq.HOME,"/lib/config.q"

/ Load Features
.resq.require .resq.HOME,"/lib/parametrize.q"
.resq.require .resq.HOME,"/lib/async.q"
.resq.require .resq.HOME,"/lib/bench.q"

/ Load CLI/Runner
.resq.require .resq.HOME,"/lib/cli.q"
.resq.require .resq.HOME,"/lib/runner.q"
/ The adapter is inert unless its explicit external-provider environment is set.
.resq.require .resq.HOME,"/lib/self_coverage.q"

/ Configuration. Everything this script keeps goes under .resq: a plain
/ assignment here is a global in the root namespace of the process under
/ test, where an application that sets `config` or `args` only when they are
/ undefined would take resQ's values for its own.
/ A resq.json that cannot be applied as written stops here. It used to be a
/ warning: the bad key kept its default and the run went on, so one trailing
/ comma or one misspelled key silently removed `strict`, a coverage threshold
/ or a snapshot gate from a pipeline that then stayed green.
.resq.configFailure:{[problems]
    {-2 "CONFIG ERROR: ", x} each problems;
    -2 "resq.json was not applied, so none of its settings can be relied on. Fix the file or remove it.";
    exit .resq.EXIT.FAIL
 };
.resq.bootConfig: @[.tst.loadConfig; ::; {[e] .resq.configFailure enlist "resq.json could not be read: ", e}];
if[count .tst.configLoadProblems; .resq.configFailure .tst.configLoadProblems];
.resq.config.validationWarnings: @[.tst.validateConfig; .resq.bootConfig;
    {[e] .resq.configFailure enlist "resq.json could not be checked: ", e}];
if[count .resq.config.validationWarnings;
    .resq.configFailure .tst.toString each .resq.config.validationWarnings];
@[.tst.applyConfig; .resq.bootConfig; {[e] .resq.configFailure enlist "resq.json could not be applied: ", e}];
if[count @[get; `.tst.configIgnoredKeys; {`symbol$()}];
    .resq.configFailure enlist "invalid value for: ", ", " sv string .tst.configIgnoredKeys];
.resq.labelEnvironmentError:.tst.applyEnvironmentLabels[];
if[count .resq.labelEnvironmentError;
    -2 "LABEL ERROR: RESQ_LABELS_JSON: ",.resq.labelEnvironmentError;
    exit .resq.EXIT.FAIL];

/ Ensure text reporter is loaded before mode dispatch
.resq.textReporterLoaded: .tst.loadOutputModule "text";
if[not .resq.textReporterLoaded; -1 "WARNING: Falling back to built-in text reporter."];

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
/ qspec's app/spec.q loads qutil's option parser before any test file, so
/ qspec-era code can call .utl.addOpt without requiring it. bin/qspec keeps
/ that when qutil is installed.
if[.resq.hasQutil and 1b~@[get;`.tst.app.qspecDiscovery;0b];
    @[.resq.qutilRequire; "qutil/opts.q";
      {[e] -2 "resQ WARNING: could not preload qutil/opts.q as qspec does: ",.tst.toString e}]];
/ A plugin that is not there, or does not load, is a mistake on the command
/ line or in resq.json: one line, not a q trace.
@[.resq.loadPluginFiles; ::; {[e]
    -2 "CLI ERROR: ", e;
    exit .resq.EXIT.FAIL}];
.resq.mode: .resq.cli`mode;
.tst.app.args: .resq.cli`args;
/ A resq.json further up is not read; see .tst.unreadConfigAbove.
.resq.configAbove: @[.tst.unreadConfigAbove; system "cd"; {[e] ""}];
if[(count .resq.configAbove) and (.resq.mode in `test`cover`mutate`watch`discover) and
   not 1b ~ @[get; `.tst.app.passOnly; 0b];
    -2 "resQ: note: ", .resq.configAbove, " is not read. resq.json is read from the directory resQ is started in;",
       " its settings (strict, thresholds, paths) do not apply to this run."];
/ An empty path, as from an unset shell variable (resq test "$DIR"), was
/ dropped without a word, and the run tested the default directory instead.
if[any 0 = count each .resq.util.pathToString each .tst.app.args;
    -2 "CLI ERROR: an empty path was given. Leave the path out to use tests/, or name a file or directory.";
    exit .resq.EXIT.FAIL];
/ Options that only say how -isolate runs change nothing without it.
if[(.resq.mode in `test`cover) and not 1b ~ @[get; `.tst.app.isolate; 0b];
    .resq.unusedIsolate: (),{[name] $[0 < count (.resq.cli`options) name; enlist "-", string name; ()]} each `isolateTimeout`isolateWorkers;
    if[count raze .resq.unusedIsolate;
        -2 "CLI WARNING: ", (" and " sv raze .resq.unusedIsolate), " ",
            $[1 < count raze .resq.unusedIsolate; "have"; "has"],
            " no effect without -isolate; the run is in one process."]];

/ --- DISPATCH ---

/ MODE: COVER
if[.resq.mode ~ `cover; .tst.app.runCoverage: 1b; .resq.mode: `test];

/ MODE: TEST
if[.resq.mode ~ `test;
    / Convention: if no path is given and a local tests/ directory exists,
    / use it. Keeps `resq test` useful without making the path mandatory.
    if[(0 = count .tst.app.args) and .resq.util.isDir "tests";
        .tst.app.args: enlist "tests";
        -1 "No path specified; defaulting to tests/";
    ];
    / Isolation cannot compose truthfully with coverage instrumentation or
    / describe-only discovery. Reject both before reporter initialization or
    / test loading so no report/coverage artifact can be created.
    if[(1b ~ @[get; `.tst.app.isolate; 0b]) and
       (1b ~ @[get; `.tst.app.runCoverage; 0b]);
        -2 "CLI ERROR: process isolation cannot be combined with coverage; use paired isolated-correctness and non-isolated-coverage lanes";
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
        .resq.endInterruptedRun[];
        .resq.recordVerdict .resq.isolateExitCode;
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
        .resq.runAllWithOptionalSelfCoverage[];
        .resq.endInterruptedRun[];
        / -desc exits cleanly (0) when files loaded without error; a load error
        / still surfaces as LOAD_ERROR so a broken file is never silently listed.
        / Otherwise granular exit codes for CI/CD.
        .resq.noTestsFound: (not 1b~@[get;`.tst.app.emptyShard;0b]) and
            (0 = count .tst.app.discoveredFiles) and (0 = count .resq.state.results);
        .resq.exitCode: $[1b ~ @[get; `.tst.app.describeOnly; 0b];
                $[0 < count .tst.app.loadErrors; .resq.EXIT.LOAD_ERROR; .resq.EXIT.PASS];
            0 < count .tst.app.loadErrors; .resq.EXIT.LOAD_ERROR;
            .resq.noTestsFound; .resq.EXIT.NO_TESTS;
            not .tst.app.passed; .resq.EXIT.FAIL;
            .resq.EXIT.PASS];
        .resq.recordVerdict .resq.exitCode;
        .resq.completeExitGuard[];
        if[1b ~ .tst.app.exit; exit .resq.exitCode];
    ];
 ];

/ MODE: DISCOVER
if[.resq.mode ~ `discover;
    / Defaults point at the bundled quickstart inside the install root,
    / since "examples/quickstart" is only meaningful relative to resq itself.
    / Both paths are required. With none, discover used to analyse the example
    / project bundled with resQ and write its report into the caller's
    / directory, which answers a question nobody asked.
    if[(2 > count .tst.app.args) and not .resq.cli[`options; `interactive];
        -2 "CLI ERROR: discover needs a source path and a test path: resq discover src tests";
        exit .resq.EXIT.FAIL];
    .resq.discoverSrc: $[0<count .tst.app.args; .tst.app.args 0; "src"];
    .resq.discoverTst: $[1<count .tst.app.args; .tst.app.args 1; "tests"];
    if[.resq.cli[`options; `interactive]; .tst.start[]; exit 0];
    .tst.main[.resq.discoverSrc; .resq.discoverTst];
    exit 0;
 ];

/ MODE: MUTATE
/ Mutation testing runs each mutant in a child `resq test` process and prints
/ its own report, so no reporter is initialised here. See lib/mutate.q.
if[.resq.mode ~ `mutate;
    exit .tst.mutate.main .tst.app.args];

/ MODE: WATCH
if[.resq.mode ~ `watch;
    / One path, "." (a list holding the string): `enlist "."` is that
    / string itself, and `resq watch` with no path died with 'type.
    .resq.watchDirs: enlist enlist ".";
    if[0<count .tst.app.args; .resq.watchDirs: .resq.util.pathToString each .tst.app.args];
    / A path that is not there was watched for ever, with nothing in it.
    .resq.watchMissing: .resq.watchDirs where not .resq.util.pathExists each .resq.watchDirs;
    if[count .resq.watchMissing;
        -2 "CLI ERROR: watch path not found: ", ", " sv .resq.watchMissing;
        exit .resq.EXIT.FAIL];
    / Watch owns repeated full runAll invocations in this process. runnerCmd
    / composes reporters and starts coverage immediately before each rerun, so
    / the idle watcher never holds live instrumentation wrappers.
    / lib/watch.q's default runnerCmd already anchors at .resq.HOME, so
    / there is no need to override it here.
    .tst.watch.init[.resq.watchDirs];
    -1 ">> Watch mode active. Press Ctrl+C to exit.";
    / Explicit foreground loop instead of .z.ts + `system "t": the timer
    / approach lets q reach EOF on stdin (CI, pipes, `< /dev/null`) and exit
    / before any tick fires. A blocking loop keeps the process alive without a
    / TTY. `system "sleep"` is portable; Ctrl+C still interrupts the loop.
    while[1b;
        / Told to stop (Ctrl+C, TERM): leave quietly. q does not stop at the
        / signal while this loop runs, and every command it then started
        / failed, which printed an error trace on the way out.
        .resq.watchSlept: @[{system x; 1b}; "sleep ", string .tst.watch.interval; {[e] 0b}];
        if[.resq.util.runInterrupted[]; exit .resq.util.interruptExitCode[]];
        if[not .resq.watchSlept; '"watch: the sleep command failed"];
        .resq.watchChanges: .tst.watch.check[];
        if[.resq.util.runInterrupted[]; exit .resq.util.interruptExitCode[]];
        if[0 < count .resq.watchChanges; .tst.watch.onChanges[.resq.watchChanges]];
    ];
 ];
