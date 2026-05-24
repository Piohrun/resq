/ lib/runner.q - Simplified
.tst.initReporting:{[]
    / Defensive: ensure state exists
    if[not `xmlOutput in key `.tst.app; .tst.app.xmlOutput: 0b];
    if[not `runCoverage in key `.tst.app; .tst.app.runCoverage: 0b];
    reportFmt: .tst.normalizeFmt .resq.config.fmt;

    / Respect config format even when explicit xml flag was not set.
    if[not .tst.app.xmlOutput;
        .tst.app.xmlOutput: reportFmt in `junit`xunit;
    ];

    / Define XML reporter function
    .resq.reportXml:{[results] 
      / JUnit/XUnit output expects spec objects, not the flat results table
      specs: $[`results in key `.tst.app; .tst.app.results; ()];
      specs: $[`sanitize in key `.tst; .tst.sanitize specs; specs];
      / Defensive serialization to avoid reporter crashes
      xmlReport: $[`top in key `.tst.output;
        @[.tst.output.top; specs; {[e]
            -1 "ERROR: XML reporter failed: ", .tst.toString e;
            "<testsuites><testsuite name=\"resq\" errors=\"1\" tests=\"1\"><testcase name=\"reporter\"/><error message=\"reporter_failed\"/></testsuite></testsuites>"
          }];
        "<testsuites><testsuite name=\"resq\" errors=\"1\" tests=\"1\"><testcase name=\"reporter\"/><error message=\"xml_generator_unavailable\"/></testsuite></testsuites>"
      ];
      outDirStr: .tst.toString .resq.config.outDir;
      if[0 = count outDirStr; outDirStr: "."];
      baseDirStr: .tst.toString .tst.app.baseDir;
      if[0 = count baseDirStr; baseDirStr: system "cd"];
      if[not outDirStr like "/*"; outDirStr: baseDirStr, "/", outDirStr];
      outDirStr: .utl.normalizePath outDirStr;
      outFile: outDirStr, "/test-results.xml";
      .utl.ensureDir outDirStr;
      hsym[`$outFile] 0: enlist xmlReport;
      -1 "XML Report written to ", outFile;
     };

    / Apply XML reporter if enabled
    if[.tst.app.xmlOutput;
      reportModule: $[reportFmt=`xunit; "xunit"; "junit"];
      if[.tst.loadOutputModule[reportModule];
          if[`top in key `.tst.output;
              .resq.report: .resq.reportXml;
          ];
     ];
    ];

    / Apply JSON reporter when explicitly requested (non-XML path)
    if[not .tst.app.xmlOutput;
        if[reportFmt ~ `json;
            if[.tst.loadOutputModule["json"];
                if[`reportJson in key `.resq; .resq.report: .resq.reportJson];
            ];
        ];
    ];
     

    if[.tst.app.runCoverage;
        if[not `coverageLoading in key `.tst; .tst.coverageLoading: 0b];
        .tst.coverageLoading: 1b;
        home: @[get; `.resq.HOME; {"."}];
        if[not `initCoverage in key `.tst;
            .utl.require home,"/lib/coverage.q";
        ];
        .tst.coverageLoading: 0b;

        / Fallback: attempt a direct load if the require path did not register coverage.
        if[not `initCoverage in key `.tst;
            @[system; "l ", home, "/lib/coverage.q"; {[e]
                -1 "Coverage module load failed: ", .tst.toString e;
                :()
            }];
        ];

        covInit: @[get; `.tst.initCoverage; {::}];
        .tst._covInitOk: 1b;
        @[covInit; (); {[e]
            .tst._covInitOk: 0b;
            -1 "Coverage init failed: ", .tst.toString e;
            :()
        }];
        if[1b ~ .tst._covInitOk; -1 "Coverage enabled."];
     ];
 };

/ Lifecycle of a single spec: snapshot pollution-guard state, switch into
/ the spec's context, run before/each/after hooks, then detect and clean up
/ any state the spec leaked (namespaces, mutated globals, open handles,
/ modified .z.ts). Returns the spec dict with results populated.
.tst.runSpec:{[spec]
    runCtx: .tst.captureRuntimeContext[];
    specTitle: $[`title in key spec; spec`title; `];
    pollutionGuard: $[`pollutionGuard in key `.tst.app; .tst.app.pollutionGuard; 1b];
    / Deep snapshot: all top-level namespaces and their keys AND values
    namespaces: $[pollutionGuard; key `; `symbol$()];
    / Skip system namespaces and .tst/.resq internals
    if[pollutionGuard; namespaces: namespaces except `q`Q`j`h`o`s`v`z`tst`resq`utl];

    fullSnapshot: $[pollutionGuard; namespaces!.tst.snapshotNamespaceValues each namespaces; ()!()];

    / Resource snapshot (cross-platform). Used to detect handles/timers a
    / spec leaks so the runner can warn and clean them up at spec end.
    origHandles: $[.utl.isLinux;
        (), "J"$ raze " " vs/: @[system; "ls /proc/self/fd"; {""}];
        key .z.W  / Fallback: IPC handles on macOS/Windows
    ];
    origTs: @[get; `.z.ts; {::}];

    / Switch to spec context if defined (default to root)
    ctx: $[`namespace in key spec; spec`namespace; `context in key spec; spec`context; `.`];
    if[ctx ~ `; ctx: `.`];
    .tst.context: ctx;
    system "d ", string ctx;
    if[`tstPath in key spec; .tst.tstPath: spec`tstPath];

    / Set current context for stack traces.
    .tst.currentContext[`file]: .tst.toString .tst.tstPath;
    .tst.currentContext[`suite]: .tst.toString specTitle;

    / If halting prior to running, skip hooks/expectations and leave context/path as-is
    if[.tst.halt; .tst.restoreRuntimeContext runCtx; :spec];

    / Run Before Hooks
    if[`before in key spec; .tst.runHook[spec`before]];

    / Run Expectations
    / UI tests store tests in `expectations`, simple tests in `code`
    exList: $[`expectations in key spec; spec`expectations; spec`code];

    / Clean up list (ensure it is a list of objects)
    t: type exList;
    if[98h = t;
        exList: $[0 = count exList; (); {[tbl; idx] tbl idx}[exList] each til count exList];
        t: type exList;
    ];
    if[not t in 0 98h; exList: enlist exList];
    / Remove null expectations
    exList: exList where not (::)~/: exList;

    res: {[s; ex] if[.tst.halt; :()]; .tst.runExpec[s; ex]}[spec] each exList;
    / Remove skipped expectations (halt)
    res: res where not (::)~/: res;

    / Run After Hooks (skip if halting)
    if[not .tst.halt;
        if[`after in key spec; .tst.runHook[spec`after]];
    ];

    / Set spec result
    specResult: $[count res; $[all res[;`result] = `pass; `pass; `fail]; `pass];
    spec[`expectations]: res;
    spec[`result]: specResult;

    if[.tst.halt; .tst.restoreRuntimeContext runCtx; :spec];

    .tst.restoreDir[];
    .tst.restoreRuntimeContext runCtx;

    / Check for Global/Deep Pollution
    currentNamespaces: $[pollutionGuard; key `; `symbol$()];
    if[pollutionGuard; currentNamespaces: currentNamespaces except `q`Q`j`h`o`s`v`z`tst`resq`utl];
    
    newNamespaces: currentNamespaces except namespaces;
    / Only warn if the new top-level name actually holds state. q does not
    / let you remove a top-level identifier once defined, so we clear its
    / value (set to ::) instead -- a name with :: is functionally empty and
    / not worth pestering the test author about every run.
    if[count newNamespaces;
        nonTrivial: newNamespaces where {[n] not (::) ~ @[get; n; ::]} each newNamespaces;
        if[count nonTrivial;
            -1 "WARNING: Test '", .tst.toString[specTitle], "' introduced top-level names: ", .tst.toString nonTrivial;
            { @[set; (x; ::); {}] } each nonTrivial;
            -1 "  -> Cleared values (q retains the bare names).";
        ];
    ];

    / Check existing namespaces for new keys AND modified values
    / Check existing namespaces for new keys AND modified values
    checkNs: namespaces inter currentNamespaces;
    
    if[count checkNs;
        { [title; ns; originalState]
            currentState: .tst.snapshotNamespaceValues ns;
            
            / 1. Detect New Keys (Pollution)
            newKeys: (key currentState) except (key originalState);
            if[count newKeys;
                -1 "WARNING: Test '", .tst.toString[title], "' leaked members in ", string[ns], ": ", .tst.toString newKeys;
                .tst.deleteVar each newKeys;
                 -1 "  -> Cleaned up leaked members in ", string[ns], ".";
            ];
            
            / 2. Detect Modified Values (Mutation)
            commonKeys: (key currentState) inter (key originalState);
            / Filter out views or functions that might be tricky? For now check all.
            modifiedKeys: commonKeys where not { x ~ y }'[originalState commonKeys; currentState commonKeys];
            
            if[count modifiedKeys;
                -1 "WARNING: Test '", .tst.toString[title], "' modified globals in ", string[ns], ": ", .tst.toString modifiedKeys;
                 / Restore values
                { [k; v] 
                    / Check if view by attempting to get definition
                    / Wrap result in (isView; result) to distinguish success/fail
                    r: @[{ (1b; view x) }; k; { (0b; x) }];
                    isView: r 0;
                    
                    if[not isView; k set v];
                }'[modifiedKeys; originalState modifiedKeys];
                -1 "  -> Restored modified globals in ", string[ns], ".";
            ];
            
        }[specTitle]'[checkNs; fullSnapshot checkNs];
    ];

    / Resource teardown: close handles the spec left open, restore .z.ts.
    currentHandles: $[.utl.isLinux;
        (), "J"$ raze " " vs/: @[system; "ls /proc/self/fd"; {""}];
        key .z.W  / Fallback: IPC handles on macOS/Windows
    ];
    leaked: currentHandles except origHandles;
    if[count leaked;
        -1 "WARNING: Test Suite '", .tst.toString[specTitle], "' leaked handles: ", .tst.toString leaked;
        { @[hclose; x; {}] } each leaked;
        -1 "  -> Closed leaked handles.";
    ];

    currentTs: @[get; `.z.ts; {::}];
    if[not currentTs ~ origTs;
        -1 "WARNING: Test Suite '", .tst.toString[specTitle], "' modified .z.ts. Restoring.";
        .z.ts: origTs;
    ];

    / Spec-scope cleanups fire now that handles are closed, so file
    / deletes registered alongside a leaked handle succeed cross-platform.
    @[.tst.runSpecCleanupTasks; (); {[e] -1 "WARNING: Spec cleanup failed: ", .tst.toString e}];

    spec
 };

/ Per-expectation callback. Records the result row in .resq.state.results
/ and bumps the per-status counters. Honours failFast (stop run) and
/ failHard (set .tst.halt so subsequent specs short-circuit too).
.tst.callbacks.expecRan:{[s;e]
    .[{[s;e]
        .tst.app.expectationsRan+: 1;
        r: e[`result];
        status: .tst.normalizeResultStatus r;
        if[status ~ `pass;  .tst.app.expectationsPassed+: 1];
        if[status ~ `fail;  .tst.app.expectationsFailed+: 1];
        if[status ~ `error; .tst.app.expectationsErrored+: 1];

        messageText: $[status ~ `pass; "";
                       status in `skip`pending; $[`skipReason in key e; .tst.toString e`skipReason; .tst.toString e`desc];
                       0 < count e[`failures]; e[`failures];
                       e[`errorText]];

        toSym: {`$ .tst.toString x};
        dur: `timespan$ first e[`time];
        toInsert: flip `suite`description`status`message`time`failures`assertsRun!(
            enlist toSym s[`title];
            enlist toSym e[`desc];
            enlist status;
            enlist messageText;
            enlist dur;
            enlist $[`failures in key e; e[`failures]; ()];
            enlist $[`assertsRun in key e; e[`assertsRun]; 0i]
        );
        / Defensive: re-initialise the results table if something clobbered it.
        if[not 98h = type .resq.state.results;
            .resq.state.results: flip `suite`description`status`message`time`failures`assertsRun!(`symbol$(); `symbol$(); `symbol$(); (); `timespan$(); (); `int$());
        ];
        .resq.state.results: .resq.state.results upsert toInsert;

        / failFast / failHard escapes.
        isFail: not r ~ `pass;
        shouldHalt: (1b ~ .tst.app.failFast) or (1b ~ .tst.app.failHard);
        if[shouldHalt and isFail;
            -1 "!!! HALTING FAILURE !!!";
            -1 "Suite: ", .tst.toString s[`title];
            -1 "Desc:  ", .tst.toString e[`desc];
            -1 "Error: ", .tst.toString messageText;
            if[1b ~ .tst.app.failHard; .tst.halt: 1b];
            if[(1b ~ .tst.app.exit) and not 1b ~ .tst.app.failHard; .tst.die 1];
        ];
    };
    (s;e);
    {[args; err]
        spec: first args;
        expec: last args;
        -1 "ERROR: expecRan failed for suite ", .tst.toString spec`title, " / desc ", .tst.toString expec`desc, ": ", .tst.toString err;
        :()
    }]
 };

/ ----------------------------------------------------------------------------
/ runAll phases. Each phase is independently testable and called in sequence
/ by .tst.runAll. They share state through .tst.app.* and .resq.state.* --
/ no phase returns into the next; ordering is the contract.
/ ----------------------------------------------------------------------------

/ Reset per-run mutable state. Sets defensive defaults for any .tst.app key
/ a downstream phase reads, then captures the base directory so output paths
/ survive a test that changes CWD mid-run.
.tst.runAllPhase.initRun:{[]
    if[not `failFast in key `.tst.app; .tst.app.failFast: 0b];
    if[not `failHard in key `.tst.app; .tst.app.failHard: 0b];
    if[not `exit in key `.tst.app; .tst.app.exit: 0b];
    if[not `describeOnly in key `.tst.app; .tst.app.describeOnly: 0b];
    if[not `pollutionGuard in key `.tst.app; .tst.app.pollutionGuard: 1b];

    .tst.app.allSpecs: ();
    .tst.app.expectationsRan: 0;
    .tst.app.expectationsPassed: 0;
    .tst.app.expectationsFailed: 0;
    .tst.app.expectationsErrored: 0;
    .tst.app.discoveredFiles: ();
    .tst.app.loadedFiles: ();
    .tst.app.emptyFiles: ();
    .tst.app.executionState: `notStarted;
    .tst.app.baseDir: system "cd";

    / On non-Linux, per-spec leak detection only sees IPC handles (.z.W),
    / not file descriptors. Warn once per session if we are using the fallback.
    if[(not .utl.isLinux) and (not .tst.app.quiet) and not `handleWarnPrinted in key `.tst.app;
        -1 "NOTE: file-handle leak detection requires Linux /proc; on this OS only IPC handles (.z.W) are tracked.";
        .tst.app.handleWarnPrinted: 1b;
    ];

    .resq.state.results: flip `suite`description`status`message`time`failures`assertsRun!(`symbol$(); `symbol$(); `symbol$(); (); `timespan$(); (); `int$());
    .tst.callbacks.descLoaded: {[specObj] .tst.app.allSpecs,: enlist specObj};
 };

/ Apply runSpecs / excludeSpecs / tagFilter / excludeTagFilter to the
/ loaded spec list. failHard is also propagated into each spec dict here
/ so individual expecs can see it without re-reading .tst.app.
.tst.runAllPhase.filterSpecs:{[]
    if[0 = count .tst.app.allSpecs; :()];
    if[1b ~ .tst.app.failHard; .tst.app.allSpecs[; `failHard]: 1b];
    if[0 <> count .tst.app.excludeSpecs;
        .tst.app.allSpecs: .tst.app.allSpecs where not (or) over .tst.app.allSpecs[; `title] like/: .tst.app.excludeSpecs
    ];
    if[0 <> count .tst.app.runSpecs;
        .tst.app.allSpecs: .tst.app.allSpecs where (or) over .tst.app.allSpecs[; `title] like/: .tst.app.runSpecs
    ];
    if[`tagFilter in key .tst.app;
        if[0 < count .tst.app.tagFilter;
            .tst.app.allSpecs: .tst.app.allSpecs where
                {[spec;tags] any tags in $[`tags in key spec; spec`tags; ()]}[; .tst.app.tagFilter] each .tst.app.allSpecs
        ]
    ];
    if[`excludeTagFilter in key .tst.app;
        if[0 < count .tst.app.excludeTagFilter;
            .tst.app.allSpecs: .tst.app.allSpecs where
                {[spec;tags] not any tags in $[`tags in key spec; spec`tags; ()]}[; .tst.app.excludeTagFilter] each .tst.app.allSpecs
        ]
    ];
 };

/ Iterate the filtered spec list, running each via .tst.runSpec inside a
/ per-spec error trap so a crashing spec does not abort the rest of the run.
/ In describeOnly mode, leave specs untouched (no execution).
.tst.runAllPhase.runDiscoveredSpecs:{[]
    .tst.app.executionState: `running;
    specsList: $[98h = type .tst.app.allSpecs;
                 {[tbl; idx] tbl idx}[.tst.app.allSpecs] each til count .tst.app.allSpecs;
                 .tst.app.allSpecs];
    .tst.app.results: $[1b ~ .tst.app.describeOnly;
        specsList;
        {[spec]
            @[.tst.runSpec; spec; {[s; err]
                -1 "ERROR running spec: ", .tst.toString s[`title], ": ", .tst.toString err;
                s
            }[spec;]]
        } each specsList
    ];
 };

/ Synthesize FILE_LOAD_ERROR pseudo-specs for any test files that failed
/ to load. Surfaces load failures in both the text reporter and XML output.
.tst.runAllPhase.injectLoadErrors:{[]
    if[0 = count .tst.app.loadErrors; :()];
    {[err]
        toInsert: flip `suite`description`status`message`time`failures`assertsRun!(
            enlist `FILE_LOAD_ERROR;
            enlist err`file;
            enlist `error;
            enlist err`error;
            enlist 0Nn;
            enlist enlist err`error;
            enlist 0i
        );
        `.resq.state.results upsert toInsert;

        syntheticExpec: `desc`type`time`result`errorText`failures`code`before`after`assertsRun!(
            "File: ", string err`file;
            `test;
            0Nn;
            `fileLoadError;
            err`error;
            enlist err`error;
            {}; {}; {};
            0
        );
        syntheticSpec: `title`expectations!(`FILE_LOAD_ERROR; enlist syntheticExpec);
        .tst.app.results,: enlist syntheticSpec;
    } each .tst.app.loadErrors;
 };

/ Under -strict, a run that executed zero expectations becomes a failure.
/ Insert a synthetic row so the failure is visible in the results table
/ and propagates through computePassed.
.tst.runAllPhase.applyStrictMode:{[]
    if[not (.tst.app.strict and 0 = .tst.app.expectationsRan); :()];
    toInsert: flip `suite`description`status`message`time`failures`assertsRun!(
        enlist `STRICT_MODE_FAILURE;
        enlist `NO_TESTS_FOUND;
        enlist `error;
        enlist "Strict mode enabled but no tests were found/executed.";
        enlist 0Nn;
        enlist enlist "No tests executed.";
        enlist 0i
    );
    `.resq.state.results upsert toInsert;
 };

/ Aggregate per-spec results into the global pass/fail bit. Any load error
/ or empty-results state forces a failure.
.tst.runAllPhase.computePassed:{[]
    resList: $[98h = type .tst.app.results;
               {[tbl; idx] tbl idx}[.tst.app.results] each til count .tst.app.results;
               .tst.app.results];
    r: raze { [x] $[99h = type x; $[count x`expectations; x`expectations; ()]; ()] } each resList;
    allResPass:   $[count r; all r[; `result] ~\: `pass; 1b];
    allStatePass: $[count .resq.state.results; all .resq.state.results[`status] = `pass; 1b];

    .tst.app.passed: allResPass and (0 = count .tst.app.loadErrors) and allStatePass and (0 < count .resq.state.results);
    if[0 < count .tst.app.loadErrors; .tst.app.passed: 0b];
 };

/ Coverage report writers. Skipped entirely unless -cov / -coverage was
/ set. Both LCOV and HTML are individually trapped so a failure in one
/ does not block the other.
.tst.runAllPhase.generateCoverage:{[]
    if[not 1b ~ .tst.app.runCoverage; :()];

    outDirStr: .tst.toString .resq.config.outDir;
    if[0 = count outDirStr; outDirStr: "."; -1 "Coverage outDir was empty; defaulting to '.'"];
    baseDirStr: .tst.toString .tst.app.baseDir;
    if[0 = count baseDirStr; baseDirStr: system "cd"];
    if[not outDirStr like "/*"; outDirStr: baseDirStr, "/", outDirStr];
    outDirStr: .utl.normalizePath outDirStr;
    -1 "Coverage outDir: ", outDirStr;
    .utl.ensureDir outDirStr;

    covLCOV: @[get; `.tst.generateLCOV; {()}];
    if[0 = count covLCOV; -1 "Coverage LCOV generator not available."];
    if[0 < count covLCOV;
        @[covLCOV; outDirStr, "/coverage.lcov"; {[e] -1 "Coverage LCOV generation failed: ", .tst.toString e; :()}];
    ];

    covHTML: @[get; `.tst.generateHTML; {()}];
    if[0 = count covHTML; -1 "Coverage HTML generator not available."];
    if[0 < count covHTML;
        @[covHTML; outDirStr, "/coverage.html"; {[e] -1 "Coverage HTML generation failed: ", .tst.toString e; :()}];
    ];
 };

/ End-of-run cleanup. Every step is trapped so one bad cleanup does not
/ skip the rest. Sandbox namespaces are removed wholesale.
.tst.runAllPhase.finalCleanup:{[]
    .tst.app.executionState: `completed;
    @[.tst.cleanupAllFixtures; (); {[e] -1 "WARNING: Fixture cleanup failed: ", .tst.toString e}];
    @[.tst.restoreOriginalQ; (); {[e] -1 "WARNING: Original .q restore failed: ", .tst.toString e}];
    @[.tst.restore; (); {[e] -1 "WARNING: Mock restore failed: ", .tst.toString e}];

    rootKeys: key `.;
    sandboxKeys: rootKeys where (string rootKeys) like "sandbox_*";
    if[0 < count sandboxKeys; ![`.; (); 0b; sandboxKeys]];
 };

/ ----------------------------------------------------------------------------
/ runAll: the public entry point. Pure orchestration of the phases above.
/ ----------------------------------------------------------------------------
.tst.runAll:{[]
    .tst.runAllPhase.initRun[];

    .tst._runAllStep: "loadTests";       .tst.loadTests .tst.app.args;
    .tst._runAllStep: "filterSpecs";     .tst.runAllPhase.filterSpecs[];
    .tst._runAllStep: "runSpecs";        .tst.runAllPhase.runDiscoveredSpecs[];
    .tst._runAllStep: "loadErrors";      .tst.runAllPhase.injectLoadErrors[];
    .tst._runAllStep: "strictMode";      .tst.runAllPhase.applyStrictMode[];
    .tst._runAllStep: "resultsSummary";  .tst.runAllPhase.computePassed[];

    .tst._runAllStep: "report";
    .tst.printRunAudit[];
    .resq.report[.resq.state.results];

    .tst._runAllStep: "coverage";        .tst.runAllPhase.generateCoverage[];
    .tst._runAllStep: "cleanup";         .tst.runAllPhase.finalCleanup[];

    if[1b ~ .tst.app.exit; .tst.die `int$not .tst.app.passed];
 };
