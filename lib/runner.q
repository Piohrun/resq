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
    / JSON is the richest observability artifact. Run it after XML so it can
    / include typed diagnostics recorded by an earlier reporter failure.
    if[`json in formats;formats:(formats except `json),`json];
    reportAvailability: .tst.loadOutputModule each formats;
    .tst.app.activeReportFormats: formats where reportAvailability;

    / Invoke one reporter under a structural tag. This lets reportSelected try
    / every requested format even when an earlier serializer or file write fails.
    .resq.invokeReporter:{[results;multiple;available;format]
        if[not available;
            .tst.recordDiagnostic[`reporter;`error;`report;
                "Requested reporter is unavailable";
                enlist[`format]!enlist format];
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
          {[fmt;e]
            .tst.recordDiagnostic[`reporter;`error;`report;
                "Reporter failed: ",.tst.toString e;
                `format`error!(fmt;.tst.toString e)];
            (1b;.tst.toString e)}[format;]]
     };

    .resq.reportSelected:{[selected;availability;results]
        / "Multiple" means multiple FILE reporters. Console text is always in the
        / selected list now, so counting it would make every -junit run look
        / multi-format and rename test-results.xml to test-results.junit.xml.
        multiple: 1 < count selected except `text;
        / Rebuild immediately before each reporter. Reporter N may record a
        / typed failure diagnostic; reporter N+1 (JSON is ordered last by the
        / CLI) must see it rather than serializing the pre-dispatch snapshot.
        outcomes:();
        i:0;
        while[i<count selected;
            runModel:.tst.canonicalRunModel results;
            outcomes,:enlist .resq.invokeReporter[
                runModel;multiple;availability i;selected i];
            i+:1];
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
        covExports: `initCoverage`instrumentFile`generateLCOV`generateCoverageJSON`generateHTML;
        covMissing: covExports where not covExports in key `.tst;
        if[count covMissing;
            -1 "Coverage module loaded INCOMPLETELY - missing: ",
               " " sv string covMissing;
            -1 "  (a truncated load usually means an unterminated block comment";
            -1 "   in lib/coverage.q: a line containing only \"/\" opens one.)";
        ];

        covInit: @[get; `.tst.initCoverage; {::}];
        covSources: @[get; `.tst.app.coverageSources; {()}];
        .tst._covInitOk: 1b;
        @[{[initFn;sources]
            manifest: $[count sources; .tst.coverageManifest sources; ()];
            initFn manifest
          }[covInit]; covSources; {[e]
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

/ Restore application namespaces after a spec. Kept separate from resource and
/ runtime cleanup so each stage can be trapped independently by the finalizer.
.tst.finalizeSpecPollution:{[specTitle;pollutionGuard;namespaces;fullSnapshot]
    if[not pollutionGuard; :()];
    currentNamespaces: (key `) except `q`Q`j`h`o`s`v`z`tst`resq`utl;
    newNamespaces: currentNamespaces except namespaces;
    / q retains a top-level identifier after deletion, so clear non-trivial
    / values to :: and avoid warning forever about already-empty names.
    if[count newNamespaces;
        nonTrivial: newNamespaces where {[n] not (::) ~ @[get; n; ::]} each newNamespaces;
        if[count nonTrivial;
            .tst.recordDiagnostic[`pollution;`warning;`cleanup;
                "Suite introduced top-level names";
                `suite`names!(.tst.toString specTitle;nonTrivial)];
            -1 "WARNING: Test '", .tst.toString[specTitle], "' introduced top-level names: ", .tst.toString nonTrivial;
            { @[set; (x; ::); {}] } each nonTrivial;
            -1 "  -> Cleared values (q retains the bare names).";
        ];
    ];

    checkNs: namespaces inter currentNamespaces;
    if[count checkNs;
        { [title; ns; originalState]
            currentState: .tst.snapshotNamespaceValues ns;

            newKeys: (key currentState) except key originalState;
            if[count newKeys;
                .tst.recordDiagnostic[`pollution;`warning;`cleanup;
                    "Suite leaked namespace members";
                    `suite`namespace`members!(.tst.toString title;.tst.toString ns;newKeys)];
                -1 "WARNING: Test '", .tst.toString[title], "' leaked members in ", string[ns], ": ", .tst.toString newKeys;
                .tst.deleteVar each newKeys;
                -1 "  -> Cleaned up leaked members in ", string[ns], ".";
            ];

            commonKeys: (key currentState) inter key originalState;
            modifiedKeys: commonKeys where not {x ~ y}'[
                originalState commonKeys; currentState commonKeys];
            if[count modifiedKeys;
                .tst.recordDiagnostic[`pollution;`warning;`cleanup;
                    "Suite modified globals";
                    `suite`namespace`members!(.tst.toString title;.tst.toString ns;modifiedKeys)];
                -1 "WARNING: Test '", .tst.toString[title], "' modified globals in ", string[ns], ": ", .tst.toString modifiedKeys;
                { [k; v]
                    viewResult: @[{(1b; view x)}; k; {(0b; x)}];
                    if[not first viewResult; k set v];
                }'[modifiedKeys; originalState modifiedKeys];
                -1 "  -> Restored modified globals in ", string[ns], ".";
            ];
        }[specTitle]'[checkNs; fullSnapshot checkNs];
    ];
    ::
 };

.tst.finalizeSpecResources:{[specTitle;origHandles;origTs]
    currentHandles: $[.utl.isLinux;
        (), "J"$ raze " " vs/: @[system; "ls /proc/self/fd"; {""}];
        key .z.W];
    leakedHandles: currentHandles except origHandles;
    if[count leakedHandles;
        .tst.recordDiagnostic[`resource;`warning;`cleanup;
            "Suite leaked handles";
            `suite`handles!(.tst.toString specTitle;leakedHandles)];
        -1 "WARNING: Test Suite '", .tst.toString[specTitle], "' leaked handles: ", .tst.toString leakedHandles;
        { @[hclose; x; {}] } each leakedHandles;
        -1 "  -> Closed leaked handles.";
    ];

    currentTs: @[get; `.z.ts; {::}];
    if[not currentTs ~ origTs;
        .tst.recordDiagnostic[`resource;`warning;`cleanup;
            "Suite modified .z.ts";
            enlist[`suite]!enlist .tst.toString specTitle];
        -1 "WARNING: Test Suite '", .tst.toString[specTitle], "' modified .z.ts. Restoring.";
        .z.ts: origTs;
    ];
    ::
 };

.tst.finalizeSpecAfterAll:{[spec]
    if[not `afterAll in key spec; :()];
    specTitle: $[`title in key spec; spec`title; `];
    afterAllResult: .tst.runHook spec`afterAll;
    if[not afterAllResult ~ `ok;
        .tst.recordCleanupError[`afterAll;
            "afterAll hook failed for suite '", .tst.toString[specTitle], "': ",
            .tst.toString afterAllResult 1];
    ];
    ::
 };

/ One finally tail for every recoverable runSpec outcome. Each stage is trapped
/ independently so a broken directory fixture cannot suppress pollution,
/ resource, or registered-cleanup restoration.
.tst.finalizeSpec:{[runCtx;specTitle;pollutionGuard;namespaces;fullSnapshot;origHandles;origTs]
    @[.tst.restoreDir; (); {[e]
        .tst.recordCleanupError[`specFinalizer; "restoreDir failed: ", .tst.toString e]}];
    @[.tst.restoreRuntimeContext; runCtx; {[e]
        .tst.recordCleanupError[`specFinalizer; "runtime context restore failed: ", .tst.toString e]}];
    .[.tst.finalizeSpecPollution; (specTitle;pollutionGuard;namespaces;fullSnapshot); {[e]
        .tst.recordCleanupError[`specFinalizer; "pollution restore failed: ", .tst.toString e]}];
    .[.tst.finalizeSpecResources; (specTitle;origHandles;origTs); {[e]
        .tst.recordCleanupError[`specFinalizer; "resource restore failed: ", .tst.toString e]}];
    / Spec-scope cleanups run after handles and global state are restored, so a
    / registered probe/file delete observes the clean post-suite environment.
    @[.tst.runSpecCleanupTasks; (); {[e]
        .tst.recordCleanupError[`specFinalizer; "spec cleanup dispatch failed: ", .tst.toString e]}];
    ::
 };

/ Execute the user-visible part of a spec. Cleanup belongs exclusively to the
/ wrapper below; early returns here are therefore safe.
.tst.runSpecBody:{[spec]
    specTitle: $[`title in key spec; spec`title; `];

    / Switch to spec context if defined (default to root)
    ctx: $[`namespace in key spec; spec`namespace; `context in key spec; spec`context; `.`];
    if[ctx ~ `; ctx: `.`];
    .tst.context: ctx;
    system "d ", string ctx;
    if[`tstPath in key spec; .tst.tstPath: spec`tstPath];

    / Set current context for stack traces.
    .tst.currentContext[`file]: .tst.toString .tst.tstPath;
    .tst.currentContext[`suite]: .tst.toString specTitle;

    / If halting prior to running, skip hooks/expectations. The wrapper still
    / executes the same finalizer as every other path.
    if[.tst.halt; :spec];

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

    / Set spec result
    specResult: $[count res; $[all (.tst.normalizeResultStatus each res[;`result]) in `pass`skip`pending; `pass; `fail]; `pass];
    spec[`expectations]: res;
    spec[`result]: specResult;

    if[.tst.halt; :spec];

    spec
 };

/ Lifecycle wrapper: snapshot once, execute under a structural outcome tag,
/ always finalize, then preserve the original result or re-signal the original
/ exception for runDiscoveredSpecs to turn into a canonical error row.
.tst.runSpec:{[spec]
    runCtx: .tst.captureRuntimeContext[];
    specTitle: $[`title in key spec; spec`title; `];
    pollutionGuard: $[`pollutionGuard in key `.tst.app; .tst.app.pollutionGuard; 1b];
    namespaces: $[pollutionGuard; key `; `symbol$()];
    if[pollutionGuard;
        namespaces: namespaces except `q`Q`j`h`o`s`v`z`tst`resq`utl];
    fullSnapshot: $[pollutionGuard;
        namespaces!.tst.snapshotNamespaceValues each namespaces;
        ()!()];
    origHandles: $[.utl.isLinux;
        (), "J"$ raze " " vs/: @[system; "ls /proc/self/fd"; {""}];
        key .z.W];
    origTs: @[get; `.z.ts; {::}];
    runAfterAll: not .tst.halt;

    runOutcome: @[{[s] (0b; .tst.runSpecBody s)}; spec; {[err] (1b; err)}];
    if[runAfterAll;
        @[.tst.finalizeSpecAfterAll; spec; {[err]
            .tst.recordCleanupError[`specFinalizer;
                "afterAll dispatch failed: ", .tst.toString err]}]];
    .tst.finalizeSpec[
        runCtx;specTitle;pollutionGuard;namespaces;fullSnapshot;origHandles;origTs];
    if[first runOutcome; 'last runOutcome];
    last runOutcome
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
        fileText: .tst.repoRelativePath $[`tstPath in key s; .utl.pathToString s`tstPath; ""];
        namespaceText: $[`namespace in key e; .tst.toString e`namespace;
                         `namespace in key s; .tst.toString s`namespace;
                         ""];
        if[namespaceText like ".sandbox_*";namespaceText:""];
        specTags: $[`tags in key s; (),s`tags; ()];
        expecTags: $[`tags in key e; (),e`tags; ()];
        rowTags: distinct specTags, expecTags;
        sourceLine: $[`line in key e; "i"$e`line; 0Ni];
        baseRow:`suite`description`status`message`time`failures`assertsRun`file`line`namespace`tags`output!(
            toSym s[`title];toSym e[`desc];status;messageText;dur;
            $[`failures in key e;e`failures;()];
            $[`assertsRun in key e;e`assertsRun;0i];
            fileText;sourceLine;namespaceText;rowTags;"");
        telemetry:.tst.expectationTelemetry[s;e;fileText];
        toInsert:.tst.oneResultTable baseRow,telemetry;
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
    .tst.beginRunMetadata[];
    configWarnings:@[get;`.resq.config.validationWarnings;{()}];
    if[count configWarnings;
        {.tst.recordDiagnostic[`configuration;`warning;`configuration;x;()!()]} each configWarnings];
    .tst.app.loadErrors: flip `file`error`type!(`symbol$(); (); `symbol$());
    .tst.app.cleanupErrors: ();
    .tst.app.perfResults: .tst.app.emptyPerfResults[];
    .tst.halt: 0b;
    .tst.assertState: .tst.defaultAssertState;
    .tst.pendingBacktrace: "";
    .tst.suppressAssertionDiff: 1b ~ @[get; `.tst.app.passOnly; 0b];
    if[`testDeps in key `.utl; .utl.testDeps: ()!()];

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
        .tst.recordDiagnostic[`loading;`error;`loading;err`error;
            `file`errorType!(.tst.repoRelativePath err`file;err`type)];
        baseRow:`suite`description`status`message`time`failures`assertsRun`file`line`namespace`tags`output`kind!(
            `FILE_LOAD_ERROR;err`file;`error;err`error;0Nn;enlist err`error;0i;
            .utl.pathToString err`file;0Ni;"";`symbol$();"";`load);
        toInsert:.tst.oneResultTable baseRow;
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
    baseRow:`suite`description`status`message`time`failures`assertsRun`kind!(
        `STRICT_MODE_FAILURE;`NO_TESTS_FOUND;`error;
        "Strict mode enabled but no tests were executed (skipped tests do not count under -strict).";
        0Nn;enlist "No tests were executed (skipped tests do not count under -strict).";0i;`framework);
    toInsert:.tst.oneResultTable baseRow;
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
        .tst.recordDiagnostic[`cleanup;`error;`cleanup;messageText;rec];
        suiteSym: `$ $[count suiteText; suiteText; "CLEANUP_ERROR"];
        descSym: `$ "cleanup [",scopeText,"]",$[count testText; " after ",testText; ""];
        baseRow:`suite`description`status`message`time`failures`assertsRun`file`kind`diagnostics!(
            suiteSym;descSym;`error;messageText;0Nn;enlist messageText;0i;sourcePath;
            `cleanup;enlist `type`severity`phase`message`data!(
                `cleanup;`error;`cleanup;messageText;rec));
        toInsert:.tst.oneResultTable baseRow;
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
    .tst.recordDiagnostic[`framework;`error;phase;messageText;
        enlist[`error]!enlist errText];
    baseRow:`suite`description`status`message`time`failures`assertsRun`kind`diagnostics!(
        `RESQ_FRAMEWORK_ERROR;`$phaseText;`error;messageText;0Nn;enlist messageText;
        0i;`framework;enlist `type`severity`phase`message`data!(
            `framework;`error;phase;messageText;enlist[`error]!enlist errText));
    toInsert:.tst.oneResultTable baseRow;
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
.tst.coverageGateDecision:{[summary;minimum]
    emptyDecision: `measurable`basis`percent`hit`found`minimum`passed!(
        0b; "functions"; 0f; 0j; 0j; minimum; 0b);
    if[not 99h = type summary; :emptyDecision];
    requiredKeys: `functionsFound`functionsHit`functionPercent;
    if[not all requiredKeys in key summary; :emptyDecision];

    foundCount: `long$summary`functionsFound;
    if[0 >= foundCount; :emptyDecision];
    hitCount: `long$summary`functionsHit;
    percentValue: `float$summary`functionPercent;
    `measurable`basis`percent`hit`found`minimum`passed!(
        1b;
        "functions";
        percentValue;
        hitCount;
        foundCount;
        minimum;
        percentValue >= minimum)
 };

.tst.coverageMetricDecision:{[summary;basis;foundKey;hitKey;percentKey;minimum]
    emptyDecision:`measurable`basis`percent`hit`found`minimum`passed!(
        0b;basis;0f;0j;0j;minimum;0b);
    if[not 99h=type summary;:emptyDecision];
    if[not all (foundKey;hitKey;percentKey) in key summary;:emptyDecision];
    foundCount:`long$summary foundKey;
    if[foundCount<=0;:emptyDecision];
    hitCount:`long$summary hitKey;
    percentValue:`float$summary percentKey;
    `measurable`basis`percent`hit`found`minimum`passed!(
        1b;basis;percentValue;hitCount;foundCount;minimum;percentValue>=minimum)
 };

/ Evaluate the three independent coverage dimensions. A line threshold over a
/ partial statement denominator is rejected unless the user explicitly accepts
/ that weaker contract with -cov-allow-partial.
.tst.coverageGateEvaluation:{[summary]
    legacyMin:@[get;`.tst.app.coverageMin;0];
    functionMin:max legacyMin,@[get;`.tst.app.coverageFunctionMin;0];
    lineMin:@[get;`.tst.app.coverageLineMin;0];
    completeMin:@[get;`.tst.app.coverageCompletenessMin;0];
    allowPartial:1b~@[get;`.tst.app.allowPartialLineCoverage;0b];
    functionGate:.tst.coverageGateDecision[summary;functionMin];
    lineGate:.tst.coverageMetricDecision[
        summary;"measured_lines";`linesFound;`linesHit;`linePercent;lineMin];
    completeGate:.tst.coverageMetricDecision[
        summary;"statement_instrumentation";`statementFunctionsEligible;
        `statementFunctionsInstrumented;`statementInstrumentationPercent;completeMin];
    stmtMode:1b~$[`statementMode in key summary;summary`statementMode;0b];
    if[not stmtMode;completeGate[`measurable]:0b;completeGate[`passed]:0b];
    partial:stmtMode and (not 1b~$[`statementInstrumentationComplete in key summary;
        summary`statementInstrumentationComplete;0b]);
    errors:();
    if[not functionGate`measurable;
        errors,:enlist "Coverage measured no executable functions."];
    if[(functionGate`measurable) and not functionGate`passed;
        errors,:enlist "Function coverage ",string[functionGate`percent],
            "% is below required minimum ",string[functionMin],"% (",
            string[functionGate`hit],"/",string[functionGate`found]," functions)."];
    if[lineMin>0;
        $[partial and (not allowPartial);
            errors,:enlist "Line coverage gate refused partial statement instrumentation (",
                string[completeGate`hit],"/",string[completeGate`found],
                " functions instrumented). Use -cov-completeness-min, fix fallbacks,",
                " or explicitly pass -cov-allow-partial.";
          not lineGate`measurable;
            errors,:enlist "Line coverage gate requested but no statements were measured.";
          not lineGate`passed;
            errors,:enlist "Measured line coverage ",string[lineGate`percent],
                "% is below required minimum ",string[lineMin],"% (",
                string[lineGate`hit],"/",string[lineGate`found]," statements).";
          ::]
    ];
    if[completeMin>0;
        $[not completeGate`measurable;
            errors,:enlist "Statement instrumentation completeness gate requested but statement mode is unavailable.";
          not completeGate`passed;
            errors,:enlist "Statement instrumentation completeness ",
                string[completeGate`percent],"% is below required minimum ",
                string[completeMin],"% (",string[completeGate`hit],"/",
                string[completeGate`found]," functions).";
          ::]
    ];
    gates:`functions`lines`completeness!(functionGate;lineGate;completeGate);
    `gates`errors`allowPartialLines`partialLines`effectiveFunctionMinimum!(
        gates;errors;allowPartial;partial;functionMin)
 };

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

    covJSON:@[get;`.tst.generateCoverageJSON;{()}];
    if[0=count covJSON;errors,:enlist "Coverage JSON generator not available."];
    if[0<count covJSON;
        jsonOutcome:@[
            {[pair] (pair 0) pair 1;(0b;"")};
            (covJSON;outDirStr,"/coverage.json");
            {[e] (1b;e)}];
        if[first jsonOutcome;
            errors,:enlist "Coverage JSON generation failed: ",
                .tst.toString last jsonOutcome];
    ];

    summary: @[get; `.tst.lastCoverageSummary; {()!()}];
    evaluation:.tst.coverageGateEvaluation summary;
    gateDecision:evaluation[`gates;`functions];
    .tst.lastCoverageSummary:summary,
        `gates`allowPartialLines`partialLines!(evaluation`gates;
            evaluation`allowPartialLines;evaluation`partialLines);
    errors,:evaluation`errors;
    if[evaluation`partialLines;
        .tst.recordDiagnostic[`coverage;`warning;`coverage;
            "Statement instrumentation is partial.";
            `instrumented`eligible`allowPartial!(
                summary`statementFunctionsInstrumented;
                summary`statementFunctionsEligible;
                evaluation`allowPartialLines)]];
    if[count errors;
        {[coverageSummary;msg]
            .tst.recordDiagnostic[`coverage;`error;`coverage;msg;coverageSummary]
        }[summary;] each errors];
    .tst.app.coveragePercent:gateDecision`percent;
    .tst.app.coverageBasis:gateDecision`basis;
    .tst.app.coverageEffectiveMinimum:evaluation`effectiveFunctionMinimum;
    .tst.app.coveragePassed:(gateDecision`measurable) and 0=count evaluation`errors;
    if[gateDecision`measurable;
        headline: "Coverage: ", string[gateDecision`percent], "% functions (",
            string[gateDecision`hit], "/", string[gateDecision`found], ")";
        if[(99h = type summary) and (`linesFound in key summary) and 0 < summary`linesFound;
            headline,: "; measured lines ", string[summary`linePercent], "% (",
                string[summary`linesHit], "/", string[summary`linesFound], ")"];
        -1 headline;
        if[1b~$[`statementMode in key summary;summary`statementMode;0b];
            -1 "  Statement instrumentation completeness: ",
                string[summary`statementInstrumentationPercent],"% (",
                string[summary`statementFunctionsInstrumented],"/",
                string[summary`statementFunctionsEligible]," functions)."];
        if[(not `linesFound in key summary) or 0 = summary`linesFound;
            -1 "  (function-level: a function counts as covered once entered.",
               " Statement/branch execution is NOT measured -- add -cov-statements.)"];
        if[(0 < summary`linesFound) and
           (0 < evaluation`effectiveFunctionMinimum);
            -1 "  (-cov-min gates on complete function coverage; measured lines are diagnostic.)"];
    ];
    if[count errors; '"Coverage failed: ","; " sv errors];
 };

/ End-of-run cleanup. Every step is trapped so one bad cleanup does not
/ skip the rest. Only namespaces THIS run created are removed.
.tst.runAllPhase.finalCleanup:{[]
    .tst.app.executionState: `completed;
    @[.tst.cleanupAllFixtures; (); {[e] .tst.recordCleanupError[`sessionFixture;e]}];
    @[.tst.restore; (); {[e] .tst.recordCleanupError[`mockRestore;e]}];

    .tst.releaseSandboxes[];
    .tst.finishRunMetadata[];
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
