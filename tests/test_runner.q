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
        `.tst.app.executionState       mock `running;
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
};

/ ----------------------------------------------------------------------------

.tst.desc["runAll phase: injectLoadErrors"]{
    before{
        `.tst.app.loadErrors mock flip `file`error`type!(`symbol$(); (); `symbol$());
        `.tst.app.results    mock ();
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
        .resq.state.results: .resq.state.emptyResults[] upsert (`s;`x;`pass;"";0Nn;();0i);
        .tst.runAllPhase.computePassed[];
        .tst.app.passed musteq 1b;
    };

    should["report failed when any expectation failed"]{
        .tst.app.results: enlist mkFailedSpec[];
        .resq.state.results: .resq.state.emptyResults[] upsert (`s;`x;`fail;"";0Nn;();0i);
        .tst.runAllPhase.computePassed[];
        .tst.app.passed musteq 0b;
    };

    should["report failed when load errors exist"]{
        .tst.app.results: enlist mkPassedSpec[];
        .tst.app.loadErrors: flip `file`error`type!(enlist `bad.q; enlist "boom"; enlist `load);
        .resq.state.results: .resq.state.emptyResults[] upsert (`s;`x;`pass;"";0Nn;();0i);
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
        saved: .tst.app.executionState;
        .tst.app.executionState: `running;
        .tst.runAllPhase.finalCleanup[];
        .tst.app.executionState musteq `completed;
        .tst.app.executionState: saved;
    };

    should["survive when a sub-cleanup raises (each one is trapped)"]{
        / Same reason for manual save/restore: finalCleanup wipes mocks.
        savedState: .tst.app.executionState;
        savedHook:  @[get; `.tst.cleanupAllFixtures; {{}}];
        .tst.cleanupAllFixtures: {'cleanupExplosion};
        .tst.app.executionState: `running;
        @[.tst.runAllPhase.finalCleanup; (); {[e] -1 "unexpected: ", e}];
        .tst.app.executionState musteq `completed;
        .tst.cleanupAllFixtures: savedHook;
        .tst.app.executionState: savedState;
    };
};

/ ----------------------------------------------------------------------------

.tst.desc["runAll phase: run helper"]{
    before{
        `.tst._runAllStep mock `before;
        `captured mock `;
    };

    should["set _runAllStep to the symbol name before invoking the phase"]{
        .tst.runAllPhase.run[`myPhase; {`captured set .tst._runAllStep}];
        / The phase fn ran AFTER the marker was set, so it observed the new name.
        captured musteq `myPhase;
        .tst._runAllStep musteq `myPhase;
    };
};
