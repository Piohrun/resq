/ Direct tests for the runAll phase functions. Each phase mutates global
/ .tst.app.* and .resq.state.* state, so every suite snapshots and restores
/ that state in before/after hooks -- without it, the live test runner that
/ is executing these specs has its own counters and results table clobbered.

/ ----------------------------------------------------------------------------
/ Snapshot / restore helpers, scoped to this test file under .tst.runnerTest.
/ ----------------------------------------------------------------------------

.tst.runnerTest.appKeys: `failFast`failHard`exit`describeOnly`pollutionGuard`allSpecs`expectationsRan`expectationsPassed`expectationsFailed`expectationsErrored`discoveredFiles`loadedFiles`emptyFiles`executionState`baseDir`results`loadErrors`strict`excludeSpecs`runSpecs`tagFilter`excludeTagFilter;

.tst.runnerTest.snapshotState:{[]
    keep: .tst.runnerTest.appKeys inter key .tst.app;
    / Dict slice: keep#dict returns a sub-dict with just those keys.
    .tst.runnerTest.savedApp:: keep # .tst.app;
    .tst.runnerTest.savedResults:: .resq.state.results;
 };

.tst.runnerTest.restoreState:{[]
    if[`savedApp in key `.tst.runnerTest;
        {[k;v] @[`.tst.app; k; :; v]} ./: flip (key; value) @\: .tst.runnerTest.savedApp;
    ];
    if[`savedResults in key `.tst.runnerTest;
        .resq.state.results: .tst.runnerTest.savedResults;
    ];
 };

/ ----------------------------------------------------------------------------

.tst.desc["runAll phase: initRun"]{
    before{ .tst.runnerTest.snapshotState[] };
    after{  .tst.runnerTest.restoreState[] };

    should["reset per-run counters to zero"]{
        .tst.app.expectationsRan: 999;
        .tst.app.expectationsPassed: 50;
        .tst.app.expectationsFailed: 7;
        .tst.app.expectationsErrored: 3;
        .tst.app.allSpecs: enlist `dummy;
        .tst.runAllPhase.initRun[];
        .tst.app.expectationsRan musteq 0;
        .tst.app.expectationsPassed musteq 0;
        .tst.app.expectationsFailed musteq 0;
        .tst.app.expectationsErrored musteq 0;
        (count .tst.app.allSpecs) musteq 0;
    };

    should["mark executionState as notStarted"]{
        .tst.app.executionState: `running;
        .tst.runAllPhase.initRun[];
        .tst.app.executionState musteq `notStarted;
    };

    should["reset the results table"]{
        / Pre-populate via the callback path (avoids row-literal type fights).
        .tst.callbacks.expecRan[`title`expectations!(`s; ()); `desc`result`time`failures`assertsRun!(`x; `pass; 0Nn; (); 0i)];
        must[0 < count .resq.state.results; "fixture should populate the table"];
        .tst.runAllPhase.initRun[];
        (count .resq.state.results) musteq 0;
    };
};

/ ----------------------------------------------------------------------------

/ Helper: build a synthetic spec list. Defined at module scope so the
/ should-block lambdas can reach it (q does not capture lexical scope).
.tst.runnerTest.mkSpec:{[title; tags] `title`tags!(title; tags)};

/ Helper: remove a key from .tst.app if present (preserves prior absence).
.tst.runnerTest.dropAppKey:{[k] if[k in key .tst.app; .tst.app: (enlist k) _ .tst.app]};

/ Helpers for computePassed: synthesise spec dicts with one expectation
/ each. Bound at module scope because q does not lexically capture.
.tst.runnerTest.mkExpec:{[r] `desc`result`time`failures`assertsRun!(`x; r; 0Nn; (); 0i)};
.tst.runnerTest.mkPassedSpec:{[] `title`expectations!(`s; enlist .tst.runnerTest.mkExpec `pass)};
.tst.runnerTest.mkFailedSpec:{[] `title`expectations!(`s; enlist .tst.runnerTest.mkExpec `fail)};

.tst.desc["runAll phase: filterSpecs"]{
    before{ .tst.runnerTest.snapshotState[] };
    after{  .tst.runnerTest.restoreState[] };

    should["narrow to runSpecs by title pattern"]{
        mk: .tst.runnerTest.mkSpec;
        .tst.app.allSpecs: (mk[`alpha; `unit]; mk[`beta; `unit]; mk[`gamma; `integration]);
        .tst.app.excludeSpecs: ();
        .tst.app.runSpecs: enlist "a*";
        .tst.runnerTest.dropAppKey `tagFilter;
        .tst.runnerTest.dropAppKey `excludeTagFilter;
        .tst.runAllPhase.filterSpecs[];
        (count .tst.app.allSpecs) musteq 1;
        .tst.app.allSpecs[0; `title] musteq `alpha;
    };

    should["drop excludeSpecs matches"]{
        mk: .tst.runnerTest.mkSpec;
        .tst.app.allSpecs: (mk[`alpha; `unit]; mk[`beta; `unit]; mk[`gamma; `unit]);
        .tst.app.runSpecs: ();
        .tst.app.excludeSpecs: enlist "be*";
        .tst.runnerTest.dropAppKey `tagFilter;
        .tst.runnerTest.dropAppKey `excludeTagFilter;
        .tst.runAllPhase.filterSpecs[];
        (count .tst.app.allSpecs) musteq 2;
        must[all .tst.app.allSpecs[; `title] in `alpha`gamma; "wrong survivors"];
    };

    should["keep only matching tagFilter entries"]{
        mk: .tst.runnerTest.mkSpec;
        .tst.app.allSpecs: (mk[`a; `fast]; mk[`b; `slow]; mk[`c; `fast`integration]);
        .tst.app.runSpecs: ();
        .tst.app.excludeSpecs: ();
        .tst.app.tagFilter: enlist `fast;
        .tst.runnerTest.dropAppKey `excludeTagFilter;
        .tst.runAllPhase.filterSpecs[];
        (count .tst.app.allSpecs) musteq 2;
        must[all .tst.app.allSpecs[; `title] in `a`c; "wrong tag survivors"];
    };

    should["drop matching excludeTagFilter entries"]{
        mk: .tst.runnerTest.mkSpec;
        .tst.app.allSpecs: (mk[`a; `slow]; mk[`b; `fast]; mk[`c; `slow]);
        .tst.app.runSpecs: ();
        .tst.app.excludeSpecs: ();
        .tst.runnerTest.dropAppKey `tagFilter;
        .tst.app.excludeTagFilter: enlist `slow;
        .tst.runAllPhase.filterSpecs[];
        (count .tst.app.allSpecs) musteq 1;
        .tst.app.allSpecs[0; `title] musteq `b;
    };

    should["short-circuit on empty allSpecs"]{
        .tst.app.allSpecs: ();
        .tst.app.runSpecs: enlist "anything";
        .tst.runAllPhase.filterSpecs[];
        (count .tst.app.allSpecs) musteq 0;
    };
};

/ ----------------------------------------------------------------------------

.tst.desc["runAll phase: injectLoadErrors"]{
    before{ .tst.runnerTest.snapshotState[] };
    after{  .tst.runnerTest.restoreState[] };

    should["be a no-op when there are no load errors"]{
        .tst.app.loadErrors: flip `file`error`type!(`symbol$(); (); `symbol$());
        .tst.app.results: ();
        .resq.state.results: .resq.state.emptyResults[];
        .tst.runAllPhase.injectLoadErrors[];
        (count .resq.state.results) musteq 0;
        (count .tst.app.results) musteq 0;
    };

    should["synthesize FILE_LOAD_ERROR rows for each load error"]{
        .tst.app.loadErrors: flip `file`error`type!(`$("tests/test_a.q"; "tests/test_b.q"); ("syntax oops"; "missing module"); `load`load);
        .tst.app.results: ();
        .resq.state.results: .resq.state.emptyResults[];
        .tst.runAllPhase.injectLoadErrors[];
        (count .resq.state.results) musteq 2;
        must[all .resq.state.results[`suite] = `FILE_LOAD_ERROR; "wrong suite tag"];
        must[all .resq.state.results[`status] = `error;       "wrong status"];
        (count .tst.app.results) musteq 2;
    };
};

/ ----------------------------------------------------------------------------

.tst.desc["runAll phase: applyStrictMode"]{
    before{ .tst.runnerTest.snapshotState[] };
    after{  .tst.runnerTest.restoreState[] };

    should["insert STRICT_MODE_FAILURE when strict and no expectations ran"]{
        .tst.app.strict: 1b;
        .tst.app.expectationsRan: 0;
        .resq.state.results: .resq.state.emptyResults[];
        .tst.runAllPhase.applyStrictMode[];
        (count .resq.state.results) musteq 1;
        .resq.state.results[0; `suite] musteq `STRICT_MODE_FAILURE;
    };

    should["be a no-op when expectations did run"]{
        .tst.app.strict: 1b;
        .tst.app.expectationsRan: 5;
        .resq.state.results: .resq.state.emptyResults[];
        .tst.runAllPhase.applyStrictMode[];
        (count .resq.state.results) musteq 0;
    };

    should["be a no-op when strict is off"]{
        .tst.app.strict: 0b;
        .tst.app.expectationsRan: 0;
        .resq.state.results: .resq.state.emptyResults[];
        .tst.runAllPhase.applyStrictMode[];
        (count .resq.state.results) musteq 0;
    };
};

/ ----------------------------------------------------------------------------

.tst.desc["runAll phase: computePassed"]{
    before{ .tst.runnerTest.snapshotState[] };
    after{  .tst.runnerTest.restoreState[] };

    should["report passed when all specs and state-results pass"]{
        .tst.app.results: enlist .tst.runnerTest.mkPassedSpec[];
        .tst.app.loadErrors: flip `file`error`type!(`symbol$(); (); `symbol$());
        .resq.state.results: .resq.state.emptyResults[] upsert (`s;`x;`pass;"";0Nn;();0i);
        .tst.runAllPhase.computePassed[];
        .tst.app.passed musteq 1b;
    };

    should["report failed when any expectation failed"]{
        .tst.app.results: enlist .tst.runnerTest.mkFailedSpec[];
        .tst.app.loadErrors: flip `file`error`type!(`symbol$(); (); `symbol$());
        .resq.state.results: .resq.state.emptyResults[] upsert (`s;`x;`fail;"";0Nn;();0i);
        .tst.runAllPhase.computePassed[];
        .tst.app.passed musteq 0b;
    };

    should["report failed when load errors exist"]{
        .tst.app.results: enlist .tst.runnerTest.mkPassedSpec[];
        .tst.app.loadErrors: flip `file`error`type!(enlist `bad.q; enlist "boom"; enlist `load);
        .resq.state.results: .resq.state.emptyResults[] upsert (`s;`x;`pass;"";0Nn;();0i);
        .tst.runAllPhase.computePassed[];
        .tst.app.passed musteq 0b;
    };

    should["report failed when results table is empty"]{
        .tst.app.results: ();
        .tst.app.loadErrors: flip `file`error`type!(`symbol$(); (); `symbol$());
        .resq.state.results: .resq.state.emptyResults[];
        .tst.runAllPhase.computePassed[];
        .tst.app.passed musteq 0b;
    };
};

/ ----------------------------------------------------------------------------

.tst.desc["runAll phase: finalCleanup"]{
    before{ .tst.runnerTest.snapshotState[] };
    after{  .tst.runnerTest.restoreState[] };

    should["transition executionState to completed"]{
        .tst.app.executionState: `running;
        .tst.runAllPhase.finalCleanup[];
        .tst.app.executionState musteq `completed;
    };

    should["survive when sub-cleanups raise (each one is trapped)"]{
        / Temporarily replace one of the cleanup hooks with a thrower and
        / confirm finalCleanup still completes its other work.
        savedCleanup: @[get; `.tst.cleanupAllFixtures; {{}}];
        .tst.cleanupAllFixtures: {'cleanupExplosion};
        .tst.app.executionState: `running;
        @[.tst.runAllPhase.finalCleanup; (); {[e] -1 "unexpected: ", e}];
        .tst.cleanupAllFixtures: savedCleanup;
        .tst.app.executionState musteq `completed;
    };
};

/ ----------------------------------------------------------------------------

.tst.desc["runAll phase: run helper"]{
    before{ .tst.runnerTest.snapshotState[] };
    after{  .tst.runnerTest.restoreState[] };

    should["set _runAllStep to the symbol name before invoking the phase"]{
        .tst._runAllStep: `before;
        .tst.runnerTest.captured: `;
        .tst.runAllPhase.run[`myPhase; {.tst.runnerTest.captured: .tst._runAllStep}];
        / _runAllStep was overwritten before fn ran, and fn observed the new value.
        .tst.runnerTest.captured musteq `myPhase;
        .tst._runAllStep musteq `myPhase;
    };
};
