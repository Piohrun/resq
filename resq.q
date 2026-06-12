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
.resq.state.results: .resq.state.emptyResults[];

/ Initialize CLI
.tst.initCLI[];

/ Parse Args: collect positional args (everything not prefixed with -).
/ A value-taking flag (-only "pat", -tag x, ...) has its VALUE as the next
/ token; that value is NOT a flag (no leading "-") so the naive filter would
/ also treat it as a positional test path. Exclude the token immediately
/ FOLLOWING each value-flag occurrence. Boolean flags (-strict, -quiet, -junit,
/ ...) are NOT listed here, so they never swallow their successor. The list
/ mirrors cli.q's getArg call sites (both -x and --x spellings).
.resq.valueFlagWords: `maxTestTime`fuzzLimit, (`$"cov-include"), (`$"cov-exclude"),
  `outDir`exclude`only`tag, (`$"exclude-tag");
.resq.valueFlagTokens: raze {("-",x;"--",x)} each string .resq.valueFlagWords;
/ Index of every value-flag occurrence; its successor (if present and itself a
/ non-flag token) is the consumed value.
.resq.valueFlagIdx: where .z.x in .resq.valueFlagTokens;
.resq.consumedValueIdx: 1 + .resq.valueFlagIdx;
.resq.consumedValueIdx: .resq.consumedValueIdx where .resq.consumedValueIdx < count .z.x;
.resq.consumedValueIdx: .resq.consumedValueIdx where not (.z.x .resq.consumedValueIdx) like "-*";
/ Positionals are every index that is neither a "-"-flag nor a consumed value.
/ Indexing by position (not `except` on values) keeps a path that legitimately
/ equals a flag value, e.g. `resq test -only foo.q foo.q`.
.resq.allIdx: til count .z.x;
.resq.positionalIdx: .resq.allIdx where (not .z.x like "-*") and not .resq.allIdx in .resq.consumedValueIdx;
.tst.app.args: .z.x .resq.positionalIdx;

/ Loud warning for "-"-prefixed tokens that are NOT recognized flags. Full flag
/ parsing lives in cli.q (getFlag/getArg); here we only need the recognized flag
/ NAMES (both -x and --x spellings, plus the value-arg names whose own token is a
/ leading-"-" word). A path that legitimately starts with "-" gets silently
/ dropped by the filter above, so surface it and tell the user how to keep it.
.resq.knownFlagWords: `perf`junit`xml`xunit`json`noquit`exit`cov`coverage`debug,
  `interactive`strict`quiet`v`version`desc`describe`ff`fh`e,
  (`$"fail-fast"), (`$"fail-hard"), `maxTestTime`fuzzLimit,
  (`$"cov-include"), (`$"cov-exclude"), `outDir`exclude`only`tag, (`$"exclude-tag");
.resq.knownFlagTokens: raze {("-",x;"--",x)} each string .resq.knownFlagWords;
.resq.droppedFlags: .z.x where (.z.x like "-*") and not .z.x in .resq.knownFlagTokens;
if[0 < count .resq.droppedFlags;
    -1 "WARNING: ignoring unrecognized flag(s): ", ", " sv .resq.droppedFlags;
    if[any {(x like "*/*") or x like "*.q"} each .resq.droppedFlags;
        -1 "  (if you meant a path, prefix it with ./)"];
 ];

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
    / -desc/-describe: specs are discovered but NOT executed, so the normal text
    / reporter would consume the empty results table and print a malformed
    / "( passed, failed, ...)" summary. Override the .resq.report hook with the
    / describe-listing reporter AFTER initReporting (the last thing to touch
    / .resq.report), so runAll's `.resq.report` call lands on our listing.
    if[1b ~ @[get; `.tst.app.describeOnly; 0b];
        .resq.report: .tst.describeReport;
    ];
    .tst.runAll[];
    if[not any .z.x like "-noquit";
        / -desc exits cleanly (0) when files loaded without error; a load error
        / still surfaces as LOAD_ERROR so a broken file is never silently listed.
        if[1b ~ @[get; `.tst.app.describeOnly; 0b];
            exit $[0 < count .tst.app.loadErrors; .resq.EXIT.LOAD_ERROR; .resq.EXIT.PASS];
        ];
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
