/ Direct tests for the runAll phase functions. Each phase mutates global
/ .tst.app.* and .resq.state.* state, so every suite mocks the keys it
/ touches in a before-hook -- mock records the originals and .tst.restore[]
/ (run automatically between expectations) puts them back, so phase calls
/ don't clobber the runner state of the live harness.

.tst.desc["runAll phase: initRun"]{
    before{
        `.tst.app.expectationsRan      mock 999;
        `.tst.app.expectationsPassed   mock 50;
        `.tst.app.expectationsFailed   mock 7;
        `.tst.app.expectationsErrored  mock 3;
        `.tst.app.allSpecs             mock enlist `dummy;
        `.tst.app.discoveredFiles      mock .tst.app.discoveredFiles;
        `.tst.app.allDiscoveredFiles   mock .tst.app.allDiscoveredFiles;
        `.tst.app.executionInventory   mock .tst.app.executionInventory;
        `.tst.app.selectedExecutionIds mock .tst.app.selectedExecutionIds;
        `.tst.app.selectedTestCount    mock .tst.app.selectedTestCount;
        `.tst.app.canonicalRunSnapshot mock .tst.app.canonicalRunSnapshot;
        `.tst.app.runStartedAt         mock .tst.app.runStartedAt;
        `.tst.app.runFinishedAt        mock .tst.app.runFinishedAt;
        `.tst.app.runMetadata          mock .tst.app.runMetadata;
        `.tst.app.diagnostics          mock .tst.app.diagnostics;
        `.tst.app.executionIncompleteReason mock .tst.app.executionIncompleteReason;
        `.tst.app.loadedFiles          mock .tst.app.loadedFiles;
        `.tst.app.emptyFiles           mock .tst.app.emptyFiles;
        `.tst.app.executionState       mock `running;
        `.tst.app.loadErrors           mock flip `file`error`type!(enlist `stale; enlist "old"; enlist `load);
        `.tst.app.perfResults          mock enlist[`suite]!enlist `stale;
        `.tst.app.passOnly             mock 0b;
        `.tst.halt                     mock 1b;
        `.tst.assertState              mock ``failures`assertsRun!(::;enlist "old";9);
        `.tst.pendingBacktrace         mock "stale trace";
        `.tst.suppressAssertionDiff    mock 1b;
        `.utl.testDeps                 mock (enlist `stale)!enlist enlist `dependency;
        `.resq.state.results           mock .resq.state.results;
    };

    should["reset per-run counters to zero"]{
        .tst.runAllPhase.initRun[];
        .tst.app.expectationsRan      musteq 0;
        .tst.app.expectationsPassed   musteq 0;
        .tst.app.expectationsFailed   musteq 0;
        .tst.app.expectationsErrored  musteq 0;
        (count .tst.app.allSpecs)     musteq 0;
    };

    should["mark executionState as notStarted"]{
        .tst.runAllPhase.initRun[];
        .tst.app.executionState musteq `notStarted;
    };

    should["reset the results table"]{
        / Populate via the callback path so the table is non-empty pre-initRun.
        .tst.callbacks.expecRan[`title`expectations!(`s; ()); `desc`result`time`failures`assertsRun!(`x; `pass; 0Nn; (); 0i)];
        must[0 < count .resq.state.results; "fixture should populate the table"];
        .tst.runAllPhase.initRun[];
        (count .resq.state.results) musteq 0;
    };

    should["reset transient errors, benchmarks, halt, assertion and dependency state"]{
        .tst.runAllPhase.initRun[];
        resetAssertState: .tst.assertState;
        (count .tst.app.loadErrors) musteq 0;
        (count .tst.app.perfResults) musteq 0;
        .tst.halt musteq 0b;
        .tst.pendingBacktrace musteq "";
        resetAssertState mustmatch .tst.defaultAssertState;
        .tst.suppressAssertionDiff musteq 0b;
        (count .utl.testDeps) musteq 0;
    };

    should["suppress assertion diffs for pass-only runs"]{
        .tst.app.passOnly: 1b;
        .tst.runAllPhase.initRun[];
        .tst.suppressAssertionDiff musteq 1b;
    };
};

/ ----------------------------------------------------------------------------

.tst.desc["runAll phase: filterSpecs"]{
    before{
        / Mock a spec-builder helper and the .tst.app.* keys this suite reads.
        `mkSpec mock {[title; tags] `title`tags!(title; tags)};
        `.tst.app.allSpecs         mock ();
        `.tst.app.runSpecs         mock ();
        `.tst.app.excludeSpecs     mock ();
        `.tst.app.tagFilter        mock ();
        `.tst.app.excludeTagFilter mock ();
        `.tst.app.failHard         mock 0b;
        `.tst.app.runPerformance   mock 0b;
    };

    should["narrow to runSpecs by title pattern"]{
        .tst.app.allSpecs: (mkSpec[`alpha; `unit]; mkSpec[`beta; `unit]; mkSpec[`gamma; `integration]);
        .tst.app.runSpecs: enlist "a*";
        .tst.runAllPhase.filterSpecs[];
        (count .tst.app.allSpecs) musteq 1;
        .tst.app.allSpecs[0; `title] musteq `alpha;
    };

    should["drop excludeSpecs matches"]{
        .tst.app.allSpecs: (mkSpec[`alpha; `unit]; mkSpec[`beta; `unit]; mkSpec[`gamma; `unit]);
        .tst.app.excludeSpecs: enlist "be*";
        .tst.runAllPhase.filterSpecs[];
        (count .tst.app.allSpecs) musteq 2;
        must[all .tst.app.allSpecs[; `title] in `alpha`gamma; "wrong survivors"];
    };

    should["keep only matching tagFilter entries"]{
        .tst.app.allSpecs: (mkSpec[`a; `fast]; mkSpec[`b; `slow]; mkSpec[`c; `fast`integration]);
        .tst.app.tagFilter: enlist `fast;
        .tst.runAllPhase.filterSpecs[];
        (count .tst.app.allSpecs) musteq 2;
        must[all .tst.app.allSpecs[; `title] in `a`c; "wrong tag survivors"];
    };

    should["drop matching excludeTagFilter entries"]{
        .tst.app.allSpecs: (mkSpec[`a; `slow]; mkSpec[`b; `fast]; mkSpec[`c; `slow]);
        .tst.app.excludeTagFilter: enlist `slow;
        .tst.runAllPhase.filterSpecs[];
        (count .tst.app.allSpecs) musteq 1;
        .tst.app.allSpecs[0; `title] musteq `b;
    };

    should["short-circuit on empty allSpecs"]{
        .tst.app.runSpecs: enlist "anything";
        .tst.runAllPhase.filterSpecs[];
        (count .tst.app.allSpecs) musteq 0;
    };

    should["filter perf expectations unless performance mode is enabled"]{
        expecs: enlist .tst.internals.testObj,(enlist `desc)!enlist "ordinary";
        expecs,: enlist .tst.internals.perfObj,(enlist `desc)!enlist "benchmark";
        spec: `title`tags`expectations!(`mixed; (); expecs);

        .tst.app.allSpecs: enlist spec;
        .tst.app.runPerformance: 0b;
        .tst.runAllPhase.filterSpecs[];
        (count .tst.app.allSpecs[0; `expectations]) musteq 1;
        .tst.app.allSpecs[0; `expectations; `type] mustmatch enlist `test;

        .tst.app.allSpecs: enlist spec;
        .tst.app.runPerformance: 1b;
        .tst.runAllPhase.filterSpecs[];
        (count .tst.app.allSpecs[0; `expectations]) musteq 2;
    };
};

/ ----------------------------------------------------------------------------

.tst.desc["runAll phase: injectLoadErrors"]{
    before{
        `.tst.app.loadErrors mock flip `file`error`type!(`symbol$(); (); `symbol$());
        `.tst.app.results    mock ();
        `.tst.app.diagnostics mock .tst.app.diagnostics;
        `.resq.state.results mock .resq.state.emptyResults[];
    };

    should["be a no-op when there are no load errors"]{
        .tst.runAllPhase.injectLoadErrors[];
        (count .resq.state.results) musteq 0;
        (count .tst.app.results) musteq 0;
    };

    should["synthesize FILE_LOAD_ERROR rows for each load error"]{
        .tst.app.loadErrors: flip `file`error`type!(`$("tests/test_a.q"; "tests/test_b.q"); ("syntax oops"; "missing module"); `load`load);
        .tst.runAllPhase.injectLoadErrors[];
        (count .resq.state.results) musteq 2;
        must[all .resq.state.results[`suite] = `FILE_LOAD_ERROR; "wrong suite tag"];
        must[all .resq.state.results[`status] = `error;        "wrong status"];
        (count .tst.app.results) musteq 2;
    };
};

/ ----------------------------------------------------------------------------

.tst.desc["runAll phase: applyStrictMode"]{
    before{
        `.tst.app.strict           mock 0b;
        `.tst.app.expectationsRan  mock 0;
        `.resq.state.results       mock .resq.state.emptyResults[];
    };

    should["insert STRICT_MODE_FAILURE when strict and no expectations ran"]{
        .tst.app.strict: 1b;
        .tst.runAllPhase.applyStrictMode[];
        (count .resq.state.results) musteq 1;
        .resq.state.results[0; `suite] musteq `STRICT_MODE_FAILURE;
    };

    should["be a no-op when expectations did run"]{
        .tst.app.strict: 1b;
        .tst.app.expectationsRan: 5;
        .tst.runAllPhase.applyStrictMode[];
        (count .resq.state.results) musteq 0;
    };

    should["be a no-op when strict is off"]{
        .tst.runAllPhase.applyStrictMode[];
        (count .resq.state.results) musteq 0;
    };
};

/ ----------------------------------------------------------------------------

.tst.desc["runAll phase: computePassed"]{
    before{
        `mkExpec       mock {[r] `desc`result`time`failures`assertsRun!(`x; r; 0Nn; (); 0i)};
        `mkPassedSpec  mock {[] `title`expectations!(`s; enlist mkExpec `pass)};
        `mkFailedSpec  mock {[] `title`expectations!(`s; enlist mkExpec `fail)};
        `.tst.app.results    mock ();
        `.tst.app.loadErrors mock flip `file`error`type!(`symbol$(); (); `symbol$());
        `.tst.app.passed     mock 0b;
        `.resq.state.results mock .resq.state.emptyResults[];
    };

    should["report passed when all specs and state-results pass"]{
        .tst.app.results: enlist mkPassedSpec[];
        .resq.state.results: .resq.state.emptyResults[] upsert .tst.oneResultTable `suite`description`status!(`s;`x;`pass);
        .tst.runAllPhase.computePassed[];
        .tst.app.passed musteq 1b;
    };

    should["report failed when any expectation failed"]{
        .tst.app.results: enlist mkFailedSpec[];
        .resq.state.results: .resq.state.emptyResults[] upsert .tst.oneResultTable `suite`description`status!(`s;`x;`fail);
        .tst.runAllPhase.computePassed[];
        .tst.app.passed musteq 0b;
    };

    should["report failed when load errors exist"]{
        .tst.app.results: enlist mkPassedSpec[];
        .tst.app.loadErrors: flip `file`error`type!(enlist `bad.q; enlist "boom"; enlist `load);
        .resq.state.results: .resq.state.emptyResults[] upsert .tst.oneResultTable `suite`description`status!(`s;`x;`pass);
        .tst.runAllPhase.computePassed[];
        .tst.app.passed musteq 0b;
    };

    should["report failed when results table is empty"]{
        .tst.runAllPhase.computePassed[];
        .tst.app.passed musteq 0b;
    };
};

/ ----------------------------------------------------------------------------

/ NOTE: finalCleanup calls .tst.restore[] mid-body, which undoes any mocks
/ set up in a before-hook. This suite therefore does its state save/restore
/ by hand around each expectation -- using mock here would be self-defeating.
.tst.desc["runAll phase: finalCleanup"]{

    should["transition executionState to completed"]{
        / finalCleanup now really does release the registered sandboxes (it used
        / to be a no-op, because it matched on `key `.` which never lists
        / namespaces). Calling it MID-RUN would therefore empty the sandbox of
        / every test file loaded so far, so blank the registry for this call.
        completed:.tst.withIsolatedRunState[{[]
            .tst.app.sandboxNamespaces:`symbol$();
            .tst.app.executionState:`running;
            .tst.runAllPhase.finalCleanup[];
            .tst.app.executionState};()];
        completed musteq `completed;
    };

    should["survive when a sub-cleanup raises (each one is trapped)"]{
        / Same reason for manual save/restore: finalCleanup wipes mocks.
        savedHook:  @[get; `.tst.cleanupAllFixtures; {{}}];
        / Blank the sandbox registry for the same reason as the test above:
        / finalCleanup releases registered sandboxes for real now, and calling it
        / mid-run would empty every already-loaded test file's namespace.
        result:.tst.withIsolatedRunState[{[]
            .tst.app.sandboxNamespaces:`symbol$();
            .tst.cleanupAllFixtures:{'cleanupExplosion};
            .tst.app.executionState:`running;
            @[.tst.runAllPhase.finalCleanup; (); {[e] -1 "unexpected: ", e}];
            (.tst.app.executionState;count .tst.app.cleanupErrors)};()];
        first[result] musteq `completed;
        last[result] musteq 1;
        .tst.cleanupAllFixtures: savedHook;
    };
};

/ ----------------------------------------------------------------------------

.tst.desc["runAll phase: run helper"]{
    before{
        `.tst._runAllStep mock `before;
        `captured mock `;
        `.tst.app.passed mock 1b;
        `.tst.app.executionIncompleteReason mock .tst.app.executionIncompleteReason;
        `.tst.app.diagnostics mock .tst.app.diagnostics;
        `.resq.state.results mock .resq.state.emptyResults[];
    };

    should["set _runAllStep to the symbol name before invoking the phase"]{
        .tst.runAllPhase.run[`myPhase; {`captured set .tst._runAllStep}];
        / The phase fn ran AFTER the marker was set, so it observed the new name.
        captured musteq `myPhase;
        .tst._runAllStep musteq `myPhase;
    };

    should["turn an unexpected phase exception into a canonical error row"]{
        result: .tst.runAllPhase.runSafely[`explodingPhase; {'"phase boom"}];
        result musteq 0b;
        .tst.app.passed musteq 0b;
        count[.resq.state.results] musteq 1;
        .resq.state.results[0;`suite] musteq `RESQ_FRAMEWORK_ERROR;
        .resq.state.results[0;`description] musteq `explodingPhase;
        .resq.state.results[0;`status] musteq `error;
        must[.resq.state.results[0;`message] like "*phase boom*";
             "the original phase exception must remain visible"];
    };
};

/ A real second run is the lifecycle contract used by watch and -noquit. Keep
/ this out-of-process so finalCleanup cannot disturb the live meta-test runner.
.tst.testState.repeatRun.canQ: 0 < count @[system; "command -v q 2>/dev/null"; {()}];

.tst.desc["runAll repeated-process lifecycle #slow"]{
    skipIf[not .tst.testState.repeatRun.canQ;
           "the same namespace-based qspec suite passes twice in one q process"]{
        wd: .utl.tempRoot[], "/resq_repeat_", string[.z.i], "_", string `long$.z.p;
        fix: wd, "/test_repeat.q";
        stdinPath: wd, "/input.q";
        outPath: wd, "/out.txt";
        .utl.ensureDir wd;
        (hsym `$fix) 0: ("\\d .repeat_probe";
            "describe[\"repeat suite\"]{ should[\"passes\"]{ 1 musteq 1 } };";
            "\\d .");
        summaryPath:wd,"/repeat-summary.json";
        statePath:wd,"/.resq/last-run.json";
        (hsym `$stdinPath) 0: (
            "firstIds:.resq.state.results`testId";
            "firstRunId:.tst.app.runMetadata`id";
            "firstCount:count .resq.state.results";
            "firstDiagnostics:count .tst.app.diagnostics";
            "firstShard:.tst.shardMetadata[]";
            ".tst.runAll[]";
            "secondIds:.resq.state.results`testId";
            "secondRunId:.tst.app.runMetadata`id";
            "doc:`firstIds`secondIds`firstRunId`secondRunId`firstCount`secondCount`firstDiagnostics`secondDiagnostics`allSpecs`sandboxes`firstShard`secondShard!(firstIds;secondIds;firstRunId;secondRunId;firstCount;count .resq.state.results;firstDiagnostics;count .tst.app.diagnostics;count .tst.app.allSpecs;count .tst.app.sandboxNamespaces;firstShard;.tst.shardMetadata[])";
            "(hsym `$\"",summaryPath,"\") 0:enlist .j.j doc";
            enlist "\\");
        cmd: "true && cd ", .utl.shellQuote[wd], " && timeout -k 5 30 q ",
             .utl.shellQuote[.resq.HOME, "/resq.q"], " test ",
             .utl.shellQuote[fix], " -quiet -noquit -state-file ",.utl.shellQuote[statePath]," < ", .utl.shellQuote[stdinPath],
             " > ", .utl.shellQuote[outPath], " 2>&1; echo $?";
        status: "J"$last @[system; cmd; {[e] enlist "-1"}];
        out: @[read0; hsym `$outPath; {()}];
        rawSummary:@[read0;hsym `$summaryPath;{()}];
        repeatSummary:$[count rawSummary;.j.k "\n" sv rawSummary;()!()];
        system "rm -rf -- ", .utl.shellQuote wd;
        status musteq 0;
        (sum out like "*1 total (1 passed*") musteq 2i;
        must[not any out like "*LOAD ERROR*"; "the second load must stay clean"];
        repeatSummary[`firstIds] musteq repeatSummary`secondIds;
        repeatSummary[`firstRunId] mustne repeatSummary`secondRunId;
        firstCountValue:"j"$repeatSummary`firstCount;
        secondCountValue:"j"$repeatSummary`secondCount;
        allSpecsValue:"j"$repeatSummary`allSpecs;
        sandboxCount:"j"$repeatSummary`sandboxes;
        firstDiagnosticCount:"j"$repeatSummary`firstDiagnostics;
        secondDiagnosticCount:"j"$repeatSummary`secondDiagnostics;
        firstCountValue musteq 1j;
        secondCountValue musteq 1j;
        allSpecsValue musteq 1j;
        sandboxCount musteq 0j;
        firstDiagnosticCount musteq 0j;
        secondDiagnosticCount musteq 0j;
        repeatSummary[`firstShard] musteq repeatSummary`secondShard;
    };
 };

/ ============================================================================
/ finalCleanup must release the sandboxes THIS run created -- and nothing else.
/ .
/ Two q facts make the obvious implementation a no-op, which is what the previous
/ one was: `key `.` lists only root VARIABLES (never child namespaces), and q
/ cannot delete a namespace at all -- `![`.; (); 0b; enlist `ns]` returns cleanly
/ and changes nothing. What can be reclaimed is a namespace's CONTENTS, which is
/ where the memory lives.
/ ============================================================================
/ Build `.<ns>.<member>` by string concatenation. NOT `` ` sv `.,ns,`member ``:
/ `sv` joins with ".", and `` `. `` is already ".", so that form yields
/ `..ns.member` and silently writes to the wrong place. Defined at FILE scope
/ because q lambdas do not close over locals of the enclosing desc block.
.tst.testState.sbxMember:{[ns; m] `$ ".", string[ns], ".", string m};

.tst.desc["runAll phase: releaseSandboxes"]{

  should["clear the members of a registered sandbox"]{
    / Save/restore by hand rather than `mock`: releaseSandboxes is called from
    / finalCleanup, which also runs .tst.restore, so a mock would be rolled back
    / before the clearing ran. Exercising releaseSandboxes directly also avoids
    / restoring every mock and .q export in the middle of this suite.
    saved: .tst.app.sandboxNamespaces;
    ns: `$"sandbox_S_resq_cleanup_probe";
    (.tst.testState.sbxMember[ns;`payload]) set til 100000;
    (.tst.testState.sbxMember[ns;`marker]) set `present;
    .tst.app.sandboxNamespaces: enlist ns;

    must[0 < count key `$".", string ns; "the probe sandbox must start populated"];
    .tst.releaseSandboxes[];
    musteq[0; count key `$".", string ns];
    / q keeps the (now empty) namespace name; only the contents are reclaimable.
    musteq[`GONE; @[get; .tst.testState.sbxMember[ns;`marker]; {`GONE}]];
    .tst.app.sandboxNamespaces: saved;
  };

  should["leave an unregistered same-prefix namespace untouched"]{
    / The naming convention alone must not authorize clearing: under -noquit,
    / watch mode or embedded use a user may own a namespace starting "sandbox_".
    / Save/restore by hand rather than `mock`: releaseSandboxes is called from
    / finalCleanup, which also runs .tst.restore, so a mock would be rolled back
    / before the clearing ran. Exercising releaseSandboxes directly also avoids
    / restoring every mock and .q export in the middle of this suite.
    saved: .tst.app.sandboxNamespaces;
    mine: `$"sandbox_S_resq_registered_probe";
    theirs: `$"sandbox_userdata_probe";
    (.tst.testState.sbxMember[mine;`payload]) set 1 2 3;
    (.tst.testState.sbxMember[theirs;`payload]) set `keepme;
    .tst.app.sandboxNamespaces: enlist mine;

    .tst.releaseSandboxes[];
    musteq[0; count key `$".", string mine];
    musteq[`keepme; @[get; .tst.testState.sbxMember[theirs;`payload]; {`GONE}]];
    .tst.app.sandboxNamespaces: saved;
  };

  should["drain the registry so a second run cannot re-clear stale names"]{
    / Save/restore by hand rather than `mock`: releaseSandboxes is called from
    / finalCleanup, which also runs .tst.restore, so a mock would be rolled back
    / before the clearing ran. Exercising releaseSandboxes directly also avoids
    / restoring every mock and .q export in the middle of this suite.
    saved: .tst.app.sandboxNamespaces;
    ns: `$"sandbox_S_resq_drain_probe";
    (.tst.testState.sbxMember[ns;`payload]) set 42;
    .tst.app.sandboxNamespaces: enlist ns;
    .tst.releaseSandboxes[];
    musteq[0; count .tst.app.sandboxNamespaces];
    .tst.app.sandboxNamespaces: saved;
  };

  should["survive a registered namespace that no longer exists"]{
    / Save/restore by hand rather than `mock`: releaseSandboxes is called from
    / finalCleanup, which also runs .tst.restore, so a mock would be rolled back
    / before the clearing ran. Exercising releaseSandboxes directly also avoids
    / restoring every mock and .q export in the middle of this suite.
    saved: .tst.app.sandboxNamespaces;
    .tst.app.sandboxNamespaces: enlist `$"sandbox_S_resq_never_created";
    mustnotthrow[(); {.tst.releaseSandboxes[]}];
    .tst.app.sandboxNamespaces: saved;
  };
 };
