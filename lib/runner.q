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

    / Shared XML writer. A single-format run retains test-results.xml; when
    / both XML schemas are requested, schema-specific names prevent overwrite.
    / Serialization failures still leave a small, parseable diagnostic artifact,
    / then signal so the enclosing multi-reporter dispatcher can fail the run.
    .resq.writeXmlReport:{[results;builder;fileName]
      / JUnit/XUnit output expects flat result rows (the results argument),
      / which .tst.resultRows (called inside the reporter) sanitizes itself.
      buildOutcome: $[type[builder] in 100 104h;
        @[
          {[pair]
            buildFn: pair 0;
            payload: pair 1;
            (0b; buildFn payload)
          };
          (builder;results);
          {[e] (1b;.tst.toString e)}];
        (1b;"xml_generator_unavailable")];
      xmlReport: $[first buildOutcome;
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?><testsuites tests=\"1\" failures=\"0\" errors=\"1\"><testsuite name=\"resq reporter\" tests=\"1\" failures=\"0\" errors=\"1\"><testcase name=\"report generation\"><error message=\"reporter_failed\">Reporter generation failed; see stderr.</error></testcase></testsuite></testsuites>";
        last buildOutcome];
      outDirStr: .tst.toString .resq.config.outDir;
      if[0 = count outDirStr; outDirStr: "."];
      baseDirStr: .tst.toString .tst.app.baseDir;
      if[0 = count baseDirStr; baseDirStr: system "cd"];
      if[not outDirStr like "/*"; outDirStr: baseDirStr, "/", outDirStr];
      outDirStr: .utl.normalizePath outDirStr;
      outFile: outDirStr, "/", fileName;
      .utl.ensureDir outDirStr;
      hsym[`$outFile] 0: enlist xmlReport;
      -1 "XML Report written to ", outFile;
      if[first buildOutcome;
        '"XML reporter failed: ", last buildOutcome];
     };

    .resq.reportXml:{[results]
        .resq.writeXmlReport[results;.tst.output.top;"test-results.xml"]
     };

    requested: @[get; `.tst.app.reportFormats; `symbol$()];
    formats: $[count requested; requested;
               .tst.app.xmlOutput and reportFmt ~ `text; enlist `junit;
               enlist reportFmt];
    formats: distinct {$[x~`console;`text;x~`xml;`junit;x]} each formats;
    / Console text is the HUMAN channel, not a format competing with the file
    / reporters. Selecting -junit/-json/-xunit used to REPLACE it, so the
    / recommended CI invocation (see docs/CI.md) printed no summary, no counts,
    / no verdict and no failure list -- an errored test produced nothing at all
    / on stdout, leaving a correct exit code as the only signal in the log.
    / Text now always leads, so the human-readable result comes first and the
    / "Report written to ..." lines follow it. Silence is still available and is
    / applied after this: -pass replaces .resq.report with a no-op, -quiet keeps
    / failures and the summary while dropping passing-suite chatter, and -desc
    / swaps the reporter wholesale in resq.q.
    formats: distinct `text, formats;
    reportAvailability: .tst.loadOutputModule each formats;
    .tst.app.activeReportFormats: formats where reportAvailability;

    / Invoke one reporter under a structural tag. This lets reportSelected try
    / every requested format even when an earlier serializer or file write fails.
    .resq.invokeReporter:{[results;multiple;available;format]
        if[not available;
            :(1b;"requested output module unavailable")];
        @[
          {[args]
            resultRows: args 0;
            isMultiple: args 1;
            reportFormat: args 2;
            $[reportFormat ~ `text;
                .resq.reportText resultRows;
              reportFormat ~ `json;
                .resq.reportJson resultRows;
              reportFormat ~ `junit;
                .resq.writeXmlReport[resultRows;.tst.output.junitTop;
                    $[isMultiple;"test-results.junit.xml";"test-results.xml"]];
              reportFormat ~ `xunit;
                .resq.writeXmlReport[resultRows;.tst.output.xunitTop;
                    $[isMultiple;"test-results.xunit.xml";"test-results.xml"]];
              ::];
            (0b;"")
          };
          (results;multiple;format);
          {[e] (1b;.tst.toString e)}]
     };

    .resq.reportSelected:{[selected;availability;results]
        / "Multiple" means multiple FILE reporters. Console text is always in the
        / selected list now, so counting it would make every -junit run look
        / multi-format and rename test-results.xml to test-results.junit.xml.
        multiple: 1 < count selected except `text;
        outcomes: {[resultRows;isMultiple;formats;available;i]
            .resq.invokeReporter[resultRows;isMultiple;available i;formats i]
        }[results;multiple;selected;availability;] each til count selected;
        failedAt: where first each outcomes;
        if[count failedAt;
            details: {[fmt;err] string[fmt], ": ", err}'[
                selected failedAt; last each outcomes failedAt];
            '"REPORTER_FAILURE: ", "; " sv details];
        ::
     };
    / Capture the selected list in a projection. A later initReporting call may
    / change activeReportFormats, but restoring a previously saved reporter must
    / restore its behavior too (important for embedded/repeated-process use).
    .resq.report: .resq.reportSelected[formats;reportAvailability;];
     

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

        / A q file that opens an unterminated block comment does not FAIL to
        / load -- it silently stops defining, so `system "l"` reports success and
        / half the module is missing. That produced a coverage run with
        / initCoverage present but generateLCOV absent, surfacing much later as a
        / vague "LCOV generator not available". Check the module's entry points
        / explicitly and say exactly what is missing.
        covExports: `initCoverage`instrumentFile`generateLCOV`generateHTML;
        covMissing: covExports where not covExports in key `.tst;
        if[count covMissing;
            -1 "Coverage module loaded INCOMPLETELY - missing: ",
               " " sv string covMissing;
            -1 "  (a truncated load usually means an unterminated block comment";
            -1 "   in lib/coverage.q: a line containing only \"/\" opens one.)";
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

    / qspec compatibility: -pass executes the suite and preserves its exit
    / status, but suppresses every result reporter (text, XML, JSON).
    if[1b ~ @[get; `.tst.app.passOnly; 0b];
        .resq.report: {[results] ()}];
 };

/ Run a suite-level hook (beforeAll/afterAll). Returns `ok or (`failed;errText).
/ Hooks are trapped: a throwing hook must never crash the runner.
.tst.runHook:{[h]
    if[not (type h) within 100 104h; :`ok];
    @[{x[]; `ok}; h; {[e] (`failed; e)}]
 };

/ testOnly focus filtering -- PER-SUITE, not global. If ANY expectation in this
/ spec is focused (`1b ~ x`only`), the non-focused expectations are converted to
/ SKIPPED results (result `skip + a skipReason) so they still appear in the
/ results table as skipped -- CI output then shows the suite is focused and the
/ -strict executed-count (which excludes skips) stays correct. Only suites that
/ contain a testOnly entry are affected; other suites run untouched. We mutate
/ existing dicts in place (set `result`skipReason, mirroring how ui.q skip[]
/ builds its dict) and never change a dict's key set -- the unified schema
/ invariant (every expectation already carries `only and `skipReason) makes this
/ safe, preserving the enlist-dict-becomes-table column uniformity.
.tst.applyTestOnlyFocus:{[specTitle; exList]
    if[0 = count exList; :exList];
    onlyFlags: {$[`only in key x; 1b ~ x`only; 0b]} each exList;
    if[not any onlyFlags; :exList];
    nKeep: sum onlyFlags;
    nTotal: count exList;
    -1 "NOTE: testOnly active in suite '", .tst.toString[specTitle], "': running ",
       string[nKeep], " of ", string[nTotal], " tests";
    skipReason: "skipped: testOnly active in this suite";
    {[focused; ex; reason]
        if[focused; :ex];
        ex[`result]: `skip;
        ex[`skipReason]: reason;
        ex
    }'[onlyFlags; exList; nTotal # enlist skipReason]
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

    / Run suite-level beforeAll hook (once per spec, before any expectation).
    beforeAllResult: $[`beforeAll in key spec; .tst.runHook spec`beforeAll; `ok];

    if[not beforeAllResult ~ `ok;
        / beforeAll threw: do NOT run expectations. Synthesize a single error
        / expectation (same shape as injectLoadErrors) and route it through the
        / normal expecRan callback so it lands in .resq.state.results and fails.
        errText: .tst.toString beforeAllResult 1;
        syntheticExpec: `desc`type`time`result`errorText`failures`code`before`after`assertsRun!(
            "beforeAll hook failed";
            `test;
            0Nn;
            `error;
            errText;
            enlist errText;
            {}; {}; {};
            0i
        );
        .tst.callbacks.expecRan[spec; syntheticExpec];
        spec[`expectations]: enlist syntheticExpec;
        spec[`result]: `fail;
        / Run afterAll for cleanup even though beforeAll failed (unless halting).
        if[not .tst.halt;
            if[`afterAll in key spec;
                afterAllResult: .tst.runHook spec`afterAll;
                if[not afterAllResult ~ `ok;
                    .tst.recordCleanupError[`afterAll;
                        "afterAll hook failed for suite '", .tst.toString[specTitle], "': ",
                        .tst.toString afterAllResult 1];
                ];
            ];
        ];
        .tst.restoreRuntimeContext runCtx;
        :spec;
    ];

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

    / Per-suite testOnly focus: if any expectation is focused, convert the rest
    / to skipped (they flow through runExpec's terminal skip path unchanged).
    exList: .tst.applyTestOnlyFocus[specTitle; exList];

    res: {[s; ex] if[.tst.halt; :()]; .tst.runExpec[s; ex]}[spec] each exList;
    / Remove skipped expectations (halt)
    res: res where not (::)~/: res;

    / Run suite-level afterAll hook (skip if halting). Cleanup failures are
    / recorded now and injected as error rows after all cleanup attempts finish.
    if[not .tst.halt;
        if[`afterAll in key spec;
            afterAllResult: .tst.runHook spec`afterAll;
            if[not afterAllResult ~ `ok;
                .tst.recordCleanupError[`afterAll;
                    "afterAll hook failed for suite '", .tst.toString[specTitle], "': ",
                    .tst.toString afterAllResult 1];
            ];
        ];
    ];

    / Set spec result
    specResult: $[count res; $[all (.tst.normalizeResultStatus each res[;`result]) in `pass`skip`pending; `pass; `fail]; `pass];
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
        r: e[`result];
        status: .tst.normalizeResultStatus r;
        / expectationsRan tracks expectations that actually EXECUTED. A skip or
        / pending expectation did not run, so it must NOT bump this counter --
        / otherwise an all-skip suite looks like it ran tests and green-washes
        / under -strict (see .tst.runAllPhase.applyStrictMode). The audit line
        / labels this value "Expectations executed", matching this semantics.
        if[status in `pass`fail`error; .tst.app.expectationsRan+: 1];
        if[status ~ `pass;  .tst.app.expectationsPassed+: 1];
        if[status ~ `fail;  .tst.app.expectationsFailed+: 1];
        if[status ~ `error; .tst.app.expectationsErrored+: 1];

        messageText: $[status ~ `pass; "";
                       status in `skip`pending; $[`skipReason in key e; .tst.toString e`skipReason; .tst.toString e`desc];
                       0 < count e[`failures]; e[`failures];
                       e[`errorText]];

        toSym: {`$ .tst.toString x};
        dur: `timespan$ first e[`time];
        fileText: $[`tstPath in key s; .utl.pathToString s`tstPath; ""];
        namespaceText: $[`namespace in key e; .tst.toString e`namespace;
                         `namespace in key s; .tst.toString s`namespace;
                         ""];
        specTags: $[`tags in key s; (),s`tags; ()];
        expecTags: $[`tags in key e; (),e`tags; ()];
        rowTags: distinct specTags, expecTags;
        sourceLine: $[`line in key e; "i"$e`line; 0Ni];
        toInsert: flip `suite`description`status`message`time`failures`assertsRun`file`line`namespace`tags`output!(
            enlist toSym s[`title];
            enlist toSym e[`desc];
            enlist status;
            enlist messageText;
            enlist dur;
            enlist $[`failures in key e; e[`failures]; ()];
            enlist $[`assertsRun in key e; e[`assertsRun]; 0i];
            enlist fileText;
            enlist sourceLine;
            enlist namespaceText;
            enlist rowTags;
            enlist ""
        );
        / Keep a perf block's measurement. runners[`perf] stores it on the
        / expectation as `perf (time/space stats from benchmark.measureOpts) but
        / nothing downstream read it, so a passing benchmark reported nothing at
        / all and only a breached budget ever surfaced a number.
        if[`perf in key e;
            pr: e`perf;
            if[99h = type pr;
                popts: $[`props in key e; $[99h = type e`props; e`props; ()!()]; ()!()];
                lim: {[d;k] $[k in key d; "f"$d k; 0nf]};
                .tst.app.perfResults: .tst.app.perfResults upsert
                    `suite`description`runs`avgTimeMs`minTimeMs`maxTimeMs`devTimeMs`avgSpaceBytes`maxSpaceBytes`timeLimitMs`spaceLimitBytes!(
                        toSym s[`title];
                        toSym e[`desc];
                        "j"$$[`runs in key popts; popts`runs; 100];
                        "f"$pr[`time;`avg];  "f"$pr[`time;`min];
                        "f"$pr[`time;`max];  "f"$pr[`time;`dev];
                        "f"$pr[`space;`avg]; "f"$pr[`space;`max];
                        lim[popts;`maxTime]; lim[popts;`maxSpace]);
            ];
        ];

        / Defensive: re-initialise the results table if something clobbered it.
        if[not 98h = type .resq.state.results;
            .resq.state.results: .resq.state.emptyResults[];
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
            if[(1b ~ @[get; `.tst.app.exitImmediately; 0b]) and not 1b ~ .tst.app.failHard; .tst.die 1];
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
    .tst.app.loadErrors: flip `file`error`type!(`symbol$(); (); `symbol$());
    .tst.app.cleanupErrors: ();
    .tst.app.perfResults: .tst.app.emptyPerfResults[];
    .tst.halt: 0b;
    .tst.assertState: .tst.defaultAssertState;
    .tst.pendingBacktrace: "";
    .tst.suppressAssertionDiff: 1b ~ @[get; `.tst.app.passOnly; 0b];
    if[`testDeps in key `.utl; .utl.testDeps: ()!()];
    if[`activateQNamespaceExports in key `.tst; .tst.activateQNamespaceExports[]];

    / On non-Linux, per-spec leak detection only sees IPC handles (.z.W),
    / not file descriptors. Warn once per session if we are using the fallback.
    if[(not .utl.isLinux) and (not .tst.app.quiet) and not `handleWarnPrinted in key `.tst.app;
        -1 "NOTE: file-handle leak detection requires Linux /proc; on this OS only IPC handles (.z.W) are tracked.";
        .tst.app.handleWarnPrinted: 1b;
    ];

    .resq.state.results: .resq.state.emptyResults[];
    .tst.callbacks.descLoaded: {[specObj] .tst.app.allSpecs,: enlist specObj};
 };

/ Apply runSpecs / excludeSpecs / tagFilter / excludeTagFilter to the
/ loaded spec list. failHard is also propagated into each spec dict here
/ so individual expecs can see it without re-reading .tst.app.
.tst.runAllPhase.filterSpecs:{[]
    if[0 = count .tst.app.allSpecs; :()];
    if[1b ~ .tst.app.failHard; .tst.app.allSpecs[; `failHard]: 1b];
    / Match qspec: perf expectations are opt-in and disappear from the run
    / unless -perf/-performance (or runPerformance:true) was selected.
    specKeys: $[98h = type .tst.app.allSpecs;
                cols .tst.app.allSpecs;
                key first .tst.app.allSpecs];
    if[(not 1b ~ .tst.app.runPerformance) and `expectations in specKeys;
        .tst.app.allSpecs[; `expectations]: {
            expecs:x;
            if[98h = type expecs;
                :expecs where not expecs[`type] = `perf];
            expecs where not {`perf ~ x`type} each expecs
        } each .tst.app.allSpecs[; `expectations];
    ];
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
                / Record a result row, the same way the beforeAll failure path
                / does. Without one the spec contributes nothing: a throwing
                / before[]/after[] produced "0 total tests" and an EMPTY
                / <testsuites></testsuites>, so a pipeline reading the report saw
                / no tests and no failures. The exit code was the only signal.
                errText: .tst.toString err;
                syntheticExpec: `desc`type`time`result`errorText`failures`code`before`after`assertsRun!(
                    "spec failed to run";
                    `test;
                    0Nn;
                    `error;
                    errText;
                    enlist errText;
                    {}; {}; {};
                    0i
                );
                .tst.callbacks.expecRan[s; syntheticExpec];
                s[`expectations]: enlist syntheticExpec;
                s[`result]: `fail;
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
        toInsert: flip `suite`description`status`message`time`failures`assertsRun`file`line`namespace`tags`output!(
            enlist `FILE_LOAD_ERROR;
            enlist err`file;
            enlist `error;
            enlist err`error;
            enlist 0Nn;
            enlist enlist err`error;
            enlist 0i;
            enlist .utl.pathToString err`file;
            enlist 0Ni;
            enlist "";
            enlist `symbol$();
            enlist ""
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

/ Under -strict, a run where no expectation actually EXECUTED becomes a
/ failure. expectationsRan now counts only EXECUTED expectations (skips and
/ pendings no longer bump it -- see expecRan above), so an all-skip suite
/ correctly reports 0 here and fails loudly instead of green-washing. Insert
/ a synthetic row so the failure is visible in the results table and
/ propagates through computePassed.
/ Under -strict, a test that PASSED while running zero assertions is a failure.
/ A `should` block's return value is ignored, so a bare expression
/ (`0 < count warnings;`) is a value the block discards rather than a check, and
/ the test passes however broken the code beneath it is. -strict already means
/ "a run that verified nothing must not pass"; this applies the same rule per
/ test instead of only to the run as a whole. Without -strict these are reported
/ by the text reporter but do not fail the run.
.tst.runAllPhase.applyStrictAssertions:{[]
    if[not .tst.app.strict; :()];
    if[0 = count .resq.state.results; :()];
    r: .resq.state.results;
    silent: where (r[`status] = `pass) and 0 = r`assertsRun;
    if[0 = count silent; :()];
    msg: "Test passed without running any assertion (-strict). A bare expression is not a check: wrap it as must[cond; \"message\"].";
    / Rewrite the offending rows in place so each keeps its own suite and
    / description rather than collapsing into one synthetic failure. Columns are
    / rebuilt explicitly: a table amend over several row indices needs the
    / replacement to conform per row, so each value is repeated count[silent] times.
    n: count silent;
    st: r`status;   st[silent]: `fail;
    ms: r`message;  ms[silent]: n # enlist msg;
    fl: r`failures; fl[silent]: n # enlist enlist msg;
    r[`status]: st; r[`message]: ms; r[`failures]: fl;
    .resq.state.results: r;
 };

.tst.runAllPhase.applyStrictMode:{[]
    .tst.runAllPhase.applyStrictAssertions[];
    if[not (.tst.app.strict and 0 = .tst.app.expectationsRan); :()];
    toInsert: flip `suite`description`status`message`time`failures`assertsRun`file`line`namespace`tags`output!(
        enlist `STRICT_MODE_FAILURE;
        enlist `NO_TESTS_FOUND;
        enlist `error;
        enlist "Strict mode enabled but no tests were executed (skipped tests do not count under -strict).";
        enlist 0Nn;
        enlist enlist "No tests were executed (skipped tests do not count under -strict).";
        enlist 0i;
        enlist "";
        enlist 0Ni;
        enlist "";
        enlist `symbol$();
        enlist ""
    );
    `.resq.state.results upsert toInsert;
 };

/ Convert every recorded teardown/cleanup failure into an ordinary error row.
/ Called only after finalCleanup, so late session-fixture and restore errors are
/ included in both exit status and machine-readable reports.
.tst.runAllPhase.injectCleanupErrors:{[]
    records: @[get; `.tst.app.cleanupErrors; {()}];
    if[0 = count records; :()];
    {[rec]
        suiteText: $[`suite in key rec; .tst.toString rec`suite; ""];
        testText: $[`test in key rec; .tst.toString rec`test; ""];
        scopeText: $[`scope in key rec; .tst.toString rec`scope; "cleanup"];
        messageText: $[`message in key rec; .tst.toString rec`message; "Cleanup failed"];
        sourcePath: $[`file in key rec; .utl.pathToString rec`file; ""];
        suiteSym: `$ $[count suiteText; suiteText; "CLEANUP_ERROR"];
        descSym: `$ "cleanup [",scopeText,"]",$[count testText; " after ",testText; ""];
        toInsert: flip `suite`description`status`message`time`failures`assertsRun`file`line`namespace`tags`output!(
            enlist suiteSym;
            enlist descSym;
            enlist `error;
            enlist messageText;
            enlist 0Nn;
            enlist enlist messageText;
            enlist 0i;
            enlist sourcePath;
            enlist 0Ni;
            enlist "";
            enlist `symbol$();
            enlist "");
        `.resq.state.results upsert toInsert;
      } each records;
    / Injection is a drain operation. Clearing only after every row was added
    / keeps a mid-injection error diagnosable while preventing duplicate rows
    / if a caller invokes this phase again.
    .tst.app.cleanupErrors: ();
 };

/ Turn an unexpected framework-phase exception into the same canonical result
/ contract as a test error. The runner must never print an exception and then
/ leave machine reporters (or the process exit status) green.
.tst.runAllPhase.recordFrameworkError:{[phase;err]
    phaseText: .tst.toString phase;
    errText: .tst.toString err;
    messageText: "Framework phase '",phaseText,"' failed: ",errText;
    -1 "ERROR: ",messageText;
    toInsert: flip `suite`description`status`message`time`failures`assertsRun`file`line`namespace`tags`output!(
        enlist `RESQ_FRAMEWORK_ERROR;
        enlist `$phaseText;
        enlist `error;
        enlist messageText;
        enlist 0Nn;
        enlist enlist messageText;
        enlist 0i;
        enlist "";
        enlist 0Ni;
        enlist "";
        enlist `symbol$();
        enlist "");
    `.resq.state.results upsert toInsert;
    .tst.app.passed: 0b;
 };

/ Aggregate per-spec results into the global pass/fail bit. Any load error
/ or empty-results state forces a failure.
.tst.runAllPhase.computePassed:{[]
    rawResults: @[get; `.tst.app.results; ()];
    resList: $[98h = type rawResults;
               {[tbl; idx] tbl idx}[rawResults] each til count rawResults;
               rawResults];
    r: raze { [x] $[99h = type x; $[count x`expectations; x`expectations; ()]; ()] } each resList;
    allResPass:   $[count r; all (.tst.normalizeResultStatus each r[; `result]) in `pass`skip`pending; 1b];
    allStatePass: $[count .resq.state.results; all .resq.state.results[`status] in `pass`skip`pending; 1b];

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

    errors: ();
    covLCOV: @[get; `.tst.generateLCOV; {()}];
    if[0 = count covLCOV; errors,: enlist "Coverage LCOV generator not available."];
    if[0 < count covLCOV;
        lcovOutcome: @[
            {[pair] (pair 0) pair 1; (0b;"")};
            (covLCOV;outDirStr, "/coverage.lcov");
            {[e] (1b;e)}];
        if[first lcovOutcome;
            errors,: enlist "LCOV generation failed: ", .tst.toString last lcovOutcome];
    ];

    covHTML: @[get; `.tst.generateHTML; {()}];
    if[0 = count covHTML; errors,: enlist "Coverage HTML generator not available."];
    if[0 < count covHTML;
        htmlOutcome: @[
            {[pair] (pair 0) pair 1; (0b;"")};
            (covHTML;outDirStr, "/coverage.html");
            {[e] (1b;e)}];
        if[first htmlOutcome;
            errors,: enlist "HTML generation failed: ", .tst.toString last htmlOutcome];
    ];

    summary: @[get; `.tst.lastCoverageSummary; {()!()}];
    measurable: (99h = type summary) and
        (`linesFound in key summary) and (`functionsFound in key summary) and
        (0 < summary`linesFound) or 0 < summary`functionsFound;
    if[not measurable; errors,: enlist "Coverage measured no executable lines or functions."];
    if[measurable;
        primaryPercent: $[0 < summary`linesFound; summary`linePercent; summary`functionPercent];
        primaryHit: $[0 < summary`linesFound; summary`linesHit; summary`functionsHit];
        primaryFound: $[0 < summary`linesFound; summary`linesFound; summary`functionsFound];
        primaryKind: $[0 < summary`linesFound; "lines"; "functions"];
        .tst.app.coveragePercent: primaryPercent;
        / Only append the function figure when lines are the primary signal;
        / otherwise it repeats the headline verbatim ("100% functions; functions 100%").
        headline: "Coverage: ", string[primaryPercent], "% ", primaryKind,
            " (", string[primaryHit], "/", string[primaryFound], ")";
        if[not primaryKind ~ "functions";
            headline,: "; functions ", string[summary`functionPercent], "% (",
                string[summary`functionsHit], "/", string[summary`functionsFound], ")"];
        -1 headline;
        / Say plainly which signal the number -- and any -cov-min gate -- is built
        / on. Default mode wraps whole functions, so "100%" means every function
        / was entered, NOT that every branch inside them ran. Naming that here is
        / what stops a green gate from being read as a stronger claim than it is.
        if[0 = summary`linesFound;
            -1 "  (function-level: a function counts as covered once entered.",
               " Statement/branch execution is NOT measured -- add -cov-statements.)"];
        required: @[get; `.tst.app.coverageMin; 0];
        if[primaryPercent < required;
            errors,: enlist "Coverage ",string[primaryPercent],"% is below required minimum ",
                string[required],"% (",string[primaryHit],"/",string[primaryFound]," ",primaryKind,")."];
    ];
    if[count errors; '"Coverage failed: ","; " sv errors];
 };

/ End-of-run cleanup. Every step is trapped so one bad cleanup does not
/ skip the rest. Only namespaces THIS run created are removed.
.tst.runAllPhase.finalCleanup:{[]
    .tst.app.executionState: `completed;
    @[.tst.cleanupAllFixtures; (); {[e] .tst.recordCleanupError[`sessionFixture;e]}];
    @[.tst.restoreOriginalQ; (); {[e] .tst.recordCleanupError[`qNamespaceRestore;e]}];
    @[.tst.restore; (); {[e] .tst.recordCleanupError[`mockRestore;e]}];

    .tst.releaseSandboxes[];
 };

/ Release each sandbox this run created. Kept separate from finalCleanup so it
/ can be exercised without also restoring every mock and .q export, which
/ finalCleanup does and which is destructive in the middle of a run.
/ .
/ Two q facts shape this:
/ .
/   1. `key `.` lists only root VARIABLES, never child namespaces, so the old
/      `rootKeys where (string rootKeys) like "sandbox_*"` matched nothing --
/      it could neither free a sandbox nor, as feared, hit a user namespace
/      sharing the prefix. It was dead code.
/   2. q cannot remove a namespace. `![`.; (); 0b; enlist `sandbox_a]` returns
/      cleanly and changes nothing.
/ .
/ What IS reclaimable is the namespace's CONTENTS, which is where the memory
/ actually is: clearing one sandbox holding a 5M-element vector returned ~67MB.
/ So delete the members of exactly the registered sandboxes. The empty namespace
/ name persists, matching how top-level names behave elsewhere.
.tst.releaseSandboxes:{[]
    registered: distinct @[get; `.tst.app.sandboxNamespaces; {`symbol$()}];
    {[ns]
        full: `$".", string ns;
        @[{[n] members: key n; if[count members; ![n; (); 0b; members]]}; full; {[e] ::}];
    } each registered;
    .tst.app.sandboxNamespaces: `symbol$();
 };

/ Phase-runner helper. Records the current phase name as a symbol
/ (overwriting earlier string-literal style) and optionally emits a trace
/ line under .utl.DEBUG. Used as the single dispatch point in runAll so a
/ crash mid-run shows where via .tst._runAllStep.
.tst.runAllPhase.run:{[name; fn]
    .tst._runAllStep: name;
    if[.utl.DEBUG; -1 "[runAll] ", string name];
    fn[]
 };

/ Execute one orchestration phase under a structural outcome tag. The tag is
/ added outside user/framework code so an ordinary return value cannot imitate
/ an exception. Returns 1b on success and records a framework error on failure.
.tst.runAllPhase.runSafely:{[name;fn]
    outcome: @[
        {[pair] .tst.runAllPhase.run[pair 0;pair 1]; (0b;"")};
        (name;fn);
        {[err] (1b;err)}];
    if[first outcome; .tst.runAllPhase.recordFrameworkError[name;last outcome]];
    not first outcome
 };

/ ----------------------------------------------------------------------------
/ runAll: the public entry point. Every phase is trapped, and cleanup/reporting
/ still run after an unexpected framework error. A phase failure stops only the
/ remaining execution phases; the lifecycle tail is unconditional.
/ ----------------------------------------------------------------------------

/ Boundary between a child's TEST output and its own report.
/ .
/ Under -isolate the parent forwards a failing child's captured stdout so user
/ diagnostics (show, -1, library chatter) survive into the merged report. But the
/ child also runs a full reporter: its per-suite listing, SUMMARY box, verdict
/ line and "JSON Report written to <private scratch>" line. Forwarding those
/ duplicated the parent's own summary once per failing file and advertised a
/ scratch directory that is deleted moments later -- and, because the scratch
/ name comes from mktemp, it made two runs of the same failing suite differ,
/ breaking the byte-stable output docs/PARALLEL.md promises.
/ .
/ The child therefore marks where its report starts and the parent cuts there.
/ Emitted ONLY for isolation children (the parent passes -isolate-child), so an
/ ordinary run's stdout is unchanged. The text is human-readable on purpose: if
/ the cut is ever missed, the line explains itself rather than looking like junk.
/ .
/ Silent under -pass, whose contract is that a run prints nothing at all; there
/ is no report to trim in that mode anyway.
/ .
/ Keep the text free of "[", "]", "*" and "?": the parent locates it with `ss`,
/ where those are pattern syntax rather than literal characters.
.tst.isolatedReportSentinel: "--- resq: child report follows (trimmed by parent) ---";

.tst.markIsolatedReportBegin:{[]
    if[not 1b ~ @[get; `.tst.app.isolateChild; 0b]; :()];
    if[1b ~ @[get; `.tst.app.passOnly; 0b]; :()];
    -1 .tst.isolatedReportSentinel;
 };

.tst.runAll:{[]
    continue: .tst.runAllPhase.runSafely[`initRun; .tst.runAllPhase.initRun];
    if[continue; continue: .tst.runAllPhase.runSafely[`loadTests; {.tst.loadTests .tst.app.args}]];
    if[continue; continue: .tst.runAllPhase.runSafely[`filterSpecs; .tst.runAllPhase.filterSpecs]];
    if[continue; continue: .tst.runAllPhase.runSafely[`runSpecs; .tst.runAllPhase.runDiscoveredSpecs]];
    if[continue; continue: .tst.runAllPhase.runSafely[`loadErrors; .tst.runAllPhase.injectLoadErrors]];
    if[continue; continue: .tst.runAllPhase.runSafely[`strictMode; .tst.runAllPhase.applyStrictMode]];
    if[continue; continue: .tst.runAllPhase.runSafely[`coverage; .tst.runAllPhase.generateCoverage]];

    / These phases deliberately ignore `continue`: they are the finally path.
    .tst.runAllPhase.runSafely[`cleanup; .tst.runAllPhase.finalCleanup];
    .tst.runAllPhase.runSafely[`cleanupErrors; .tst.runAllPhase.injectCleanupErrors];
    .tst.runAllPhase.runSafely[`resultsSummary; .tst.runAllPhase.computePassed];
    .tst.runAllPhase.runSafely[`report; {.tst.markIsolatedReportBegin[]; .tst.printRunAudit[]; .resq.report .resq.state.results}];
    ::
 };
