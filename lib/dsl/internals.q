\d .tst

/ ============================================================================
/ State Initialization - Safe Defaults
/ These ensure variables exist before any module tries to use them
/ Using direct assignment to create namespace structure (like init.q does)
/ ============================================================================

/ Ensure namespaces exist by touching variables
/ This is the safe pattern - setting a variable creates its parent namespaces
if[not `app in key `.tst; .tst.app.init_: 1b];
if[not `output in key `.tst; .tst.output.init_: 1b];

/ App configuration (with safe defaults) - only set if not already defined
if[not `excludeSpecs in key `.tst.app; .tst.app.excludeSpecs: ()];
if[not `runSpecs in key `.tst.app; .tst.app.runSpecs: ()];
if[not `args in key `.tst.app; .tst.app.args: ()];
if[not `describeOnly in key `.tst.app; .tst.app.describeOnly: 0b];
if[not `xmlOutput in key `.tst.app; .tst.app.xmlOutput: 0b];
if[not `runPerformance in key `.tst.app; .tst.app.runPerformance: 0b];
if[not `runCoverage in key `.tst.app; .tst.app.runCoverage: 0b];
if[not `exit in key `.tst.app; .tst.app.exit: 0b];
if[not `failFast in key `.tst.app; .tst.app.failFast: 0b];
if[not `failHard in key `.tst.app; .tst.app.failHard: 0b];
if[not `pollutionGuard in key `.tst.app; .tst.app.pollutionGuard: 1b];
if[not `maxTestTime in key `.tst.app; .tst.app.maxTestTime: 0];
if[not `passOnly in key `.tst.app; .tst.app.passOnly: 0b];
if[not `allSpecs in key `.tst.app; .tst.app.allSpecs: ()];
if[not `passed in key `.tst.app; .tst.app.passed: 1b];

/ Counters (reset on each run)
if[not `expectationsRan in key `.tst.app; .tst.app.expectationsRan: 0];
if[not `expectationsPassed in key `.tst.app; .tst.app.expectationsPassed: 0];
if[not `expectationsFailed in key `.tst.app; .tst.app.expectationsFailed: 0];
if[not `expectationsErrored in key `.tst.app; .tst.app.expectationsErrored: 0];

/ Output configuration
if[not `mode in key `.tst.output; .tst.output.mode: `run];
if[not `fuzzLimit in key `.tst.output; .tst.output.fuzzLimit: 10];
if[not `reportLimit in key `.tst.output; .tst.output.reportLimit: 50000];
if[not `reportListLimit in key `.tst.output; .tst.output.reportListLimit: 1000];

/ Truncation utility for safely outputting large values
/ Prevents memory exhaustion from very large test outputs
.tst.truncate:{[val;maxLen]
    s: -3!val;
    n: count s;
    if[n > maxLen;
        truncLen: maxLen - 30;
        origLen: n;
        s: truncLen # s;
        s,: "... [truncated ", string[origLen - truncLen], " chars]"
    ];
    s
 };

/ Initialize .resq namespace if not exists
if[not `resq in key `.; .resq.state.init_: 1b; .resq.config.init_: 1b];

/ Resq config defaults
if[not `fmt in key `.resq.config; .resq.config.fmt: `text];
if[not `outDir in key `.resq.config; .resq.config.outDir: "."];

/ Resq state - results table
if[not `results in key `.resq.state; .resq.state.results: flip `suite`description`status`message`time`failures`assertsRun!(`symbol$(); `symbol$(); `symbol$(); (); `timespan$(); (); `int$())];

/ Default reporter (can be overridden)
if[not `report in key `.resq; .resq.report: {[x]}];

/ ============================================================================

.tst.defaultAssertState:.tst.assertState:``failures`assertsRun!(::;();0);
.tst.tstPath: `;
/ When true, failing assertions skip the per-call FAILURE DIFF banner.
/ The fuzz runner flips this on inside its iteration + shrink loops so
/ a single fuzz spec does not flood stdout with one banner per attempt
/ (the runner reports a single shrunk repro at the end instead).
if[not `suppressAssertionDiff in key `.tst; .tst.suppressAssertionDiff: 0b];

/ Type-safe string conversion
/ Handles: symbols, strings, atoms, lists, nulls
/ Use this instead of `string` when concatenating with strings
.tst.toString:{
    t: type x;
    $[10h = t; x;                           / Already a string - return as-is
      -11h = t; string x;                   / Symbol - convert normally
      11h = t; " " sv string x;             / Symbol list - join with spaces
      t within -19 -1h; string x;           / Negative atom types (atoms)
      t within 1 19h; -3!x;                 / Positive simple list types
      0h = t; -3!x;                         / General list - use -3!
      99h = t; -3!x;                        / Dictionary
      98h = t; -3!x;                        / Table
      null x; "";                           / Null - empty string
      -3!x]                                 / Fallback - use -3! (show)
 };

/ Normalize internal execution states to the public result contract.
/ returns: one of `pass`fail`error`skip`pending
.tst.normalizeResultStatus:{[status]
    if[not -11h = type status; :`error];
    $[status in `pass`skip`pending; status;
      status in `fail`testFail`fuzzFail; `fail;
      status ~ `error; `error;
      status like "*Error"; `error;
      `error]
 };

/ Capture mutable process-level state affected while loading and running tests.
/ returns: dictionary suitable for .tst.restoreRuntimeContext
.tst.captureRuntimeContext:{[]
    `namespace`context`tstPath`currentNs`fileLoadingSet`fileLoading`cwd!(
        system "d";
        @[get; `.tst.context; `.];
        @[get; `.tst.tstPath; `];
        @[get; `.tst.currentNs; `];
        `FILELOADING in key `.utl;
        @[get; `.utl.FILELOADING; {::}];
        system "cd")
 };

/ Restore state captured by .tst.captureRuntimeContext.
/ side effects: current namespace, current directory, loader bookkeeping, test context
.tst.restoreRuntimeContext:{[ctx]
    if[not 99h = type ctx; :()];

    if[`context in key ctx; .tst.context: ctx`context];
    if[`tstPath in key ctx; .tst.tstPath: ctx`tstPath];
    if[`currentNs in key ctx; .tst.currentNs: ctx`currentNs];

    if[`fileLoadingSet in key ctx;
        if[ctx`fileLoadingSet; .utl.FILELOADING: ctx`fileLoading];
        if[not ctx`fileLoadingSet; delete FILELOADING from `.utl];
    ];

    if[`cwd in key ctx;
        cwd: .tst.toString ctx`cwd;
        if[0 < count cwd; @[system; "cd ", cwd; {}]];
    ];

    if[`namespace in key ctx;
        ns: .tst.toString ctx`namespace;
        if[0 < count ns; @[system; "d ", ns; {}]];
    ];

    :: 
 };

.tst.printRunAudit:{[]
    discovered: $[`discoveredFiles in key `.tst.app; count .tst.app.discoveredFiles; 0];
    loaded: $[`loadedFiles in key `.tst.app; count .tst.app.loadedFiles; 0];
    empty: $[`emptyFiles in key `.tst.app; count .tst.app.emptyFiles; 0];
    specs: $[`allSpecs in key `.tst.app; count .tst.app.allSpecs; 0];
    executed: $[`expectationsRan in key `.tst.app; .tst.app.expectationsRan; 0];

    -1 "\nRUN AUDIT";
    -1 "---------";
    -1 "Files discovered:      ", string discovered;
    -1 "Files loaded:          ", string loaded;
    -1 "Files with no tests:   ", string empty;
    -1 "Specs registered:      ", string specs;
    -1 "Expectations executed: ", string executed;
 };

.tst.snapshotNamespaceValues:{[ns]
    rootNs: ` sv (`; ns);
    ks: @[key; rootNs; {`symbol$()}];
    if[-11h = type ks; ks: enlist ks];
    if[not 11h = type ks; :()!()];
    ks: ks where ks <> rootNs;
    if[0=count ks; :()!()];
    paths: .Q.dd[rootNs;] each ks;
    vals: { @[get; x; { (`GENERIC_ERROR; x) }] } each paths;
    paths!vals
 };

halt:0b
internals:()!()
internals[`]:()!()
internals[`specObj]:`result`title`failHard!(`didNotRun;"";0b)
internals[`defaultExpecObj]:`result`errorText!(`didNotRun;())
internals[`testObj]: internals[`defaultExpecObj], ((),`type)!(),`test
internals[`fuzzObj]: internals[`defaultExpecObj], `type`runs`vars`maxFailRate!(`fuzz;100;`int;0f)
internals[`perfObj]: internals[`defaultExpecObj], ((),`type)!(),`perf

/ Callbacks - must exist before any test loading
if[not `callbacks in key `.tst; .tst.callbacks.descLoaded: {[specObj]}; .tst.callbacks.expecRan: {[spec;expec]}];
