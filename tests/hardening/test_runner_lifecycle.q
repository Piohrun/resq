/ Deterministic regression tests for spec/run finalization.
/ Direct overrides are saved under .tst.testState so nested finalizers cannot
/ erase the recovery state used by the outer test harness.

.tst.runnerLifecycle.namedValues:{[names] names!get each names};
.tst.runnerLifecycle.restoreNamed:{[saved]
  {[name;val] name set val}'[key saved;value saved];
 };
.tst.runnerLifecycle.openHandles:{[]
  .tst.openHandles[]
 };
.tst.runnerLifecycle.simpleExpec:{[result]
  expec:.tst.internals.testObj;
  expec[`result]:result;
  expec[`errorText]:"";
  expec[`desc]:"nested expectation";
  expec[`before]:{};
  expec[`after]:{};
  expec[`runtimeContext]:.tst.captureRuntimeContext[];
  expec[`failures]:();
  expec[`assertsRun]:0i;
  expec[`time]:0Nn;
  expec
 };
.tst.runnerLifecycle.testExpec:{[code]
  expec:.tst.internals.testObj;
  expec[`desc]:"nested expectation";
  expec[`code]:code;
  expec
 };
.tst.runnerLifecycle.spec:{[expectations;beforeHook;afterHook]
  `result`title`namespace`context`tstPath`expectations`beforeAll`afterAll!(
    `didNotRun;
    "nested lifecycle spec";
    system "d";
    system "d";
    `:runner_lifecycle;
    expectations;
    beforeHook;
    afterHook)
 };
.tst.runnerLifecycle.cleanupScratch:{[]
  state:@[get;`.tst.testState.runnerLifecycle;{()!()}];
  if[not 99h=type state; :()];
  if[`handle in key state; @[hclose;state[`handle];{}]];
  if[`path in key state;
    path:state[`path];
    @[hdel;hsym `$path;{}]];
 };
.tst.runnerLifecycle.runStateNames:
  (`.tst.halt`.tst.cleanupTasks`.tst.specCleanupTasks`.tst.context`.tst.tstPath),
  (`.tst.currentNs`.tst.currentContext`.tst.assertState`.tst.originalQ),
  (`.tst._runAllStep`.tst.callbacks.descLoaded`.resq.state.results),
  (`.tst.app.passed`.tst.app.exit`.tst.app.args`.tst.app.runCoverage),
  (`.tst.app.baseDir`.tst.app.runFailures`.tst.app.reportingFailed),
  (`.tst.app.coverageFailed`.tst.app.runRuntimeContext`.tst.app.runTimer),
  (`.tst.app.runHandles`.tst.app.runLifecycle`.tst.app.cleanupComplete),
  (`.tst.app.cleanupFailures`.tst.app.cleanupFailed`.tst.app.executionState),
  (`.tst.app.allSpecs`.tst.app.results`.tst.app.expectationsRan),
  (`.tst.app.expectationsPassed`.tst.app.expectationsFailed),
  (`.tst.app.expectationsErrored`.tst.app.discoveredFiles),
  (`.tst.app.loadedFiles`.tst.app.emptyFiles`.tst.app.loadErrors);
.tst.runnerLifecycle.captureRunState:{[]
  .tst.captureNamedLifecycle .tst.runnerLifecycle.runStateNames
 };

.tst.runnerLifecycle.coverageNames:
  (`.tst.runAllPhase.initRun`.tst.loadTests`.tst.runAllPhase.filterSpecs),
  (`.tst.runAllPhase.runDiscoveredSpecs`.tst.runAllPhase.injectLoadErrors),
  (`.tst.runAllPhase.applyStrictMode`.tst.runAllPhase.computePassed),
  (`.tst.runAllPhase.generateCoverage),
  (`.tst.finalCleanupHandles`.tst.printRunAudit`.resq.report),
  (`.tst.restoreCoverageInstrumentation),
  (`.tst.testState.runnerCoverageBusiness);

.tst.runnerLifecycle.setupCoverageTest:{[]
  .tst.testState.runnerCoverageHarness:
    `names`runState`fixtures!(
      .tst.captureNamedLifecycle .tst.runnerLifecycle.coverageNames;
      .tst.runnerLifecycle.captureRunState[];
      .tst.fixtures);
  .tst.runAllPhase.initRun:{[] .tst.app.exit:0b};
  .tst.runAllPhase.filterSpecs:{[]};
  .tst.runAllPhase.runDiscoveredSpecs:{[]};
  .tst.runAllPhase.injectLoadErrors:{[]};
  .tst.runAllPhase.applyStrictMode:{[]};
  .tst.runAllPhase.computePassed:{[] .tst.app.passed:1b};
  .tst.finalCleanupHandles:{[]
    .tst.testState.runnerCoverageEvents,:enlist `framework;
    if[.tst.testState.runnerCoverageAuthority~`valid;
      if[5<>(get `.tst.testState.runnerCoverageBusiness)4;
        '"business function remained instrumented"]]};
  .tst.printRunAudit:{[]};
  .tst.app.exit:0b;
  .tst.app.runCoverage:1b;
 };

.tst.runnerLifecycle.teardownCoverageTest:{[]
  @[.tst.runCleanupTasks;();{}];
  @[.tst.runSpecCleanupTasks;();{}];
  .tst.installQExports[];
  state:.tst.testState.runnerCoverageHarness;
  .tst.restoreNamedLifecycle state`names;
  .tst.restoreNamedLifecycle state`runState;
  .tst.fixtures:state`fixtures;
  ![`.tst.testState;();0b;
    `runnerCoverageHarness`runnerCoverageEvents`runnerCoverageOriginal,
    `runnerCoverageReplacement`runnerCoverageCoverageThrows,
    `runnerCoverageReportThrows`runnerCoverageRestoreThrows,
    `runnerCoverageAuthority];
 };

.tst.runnerLifecycle.coverageRun:{[replacement;coverageThrows;reportThrows;restoreThrows;authority]
  .tst.cleanupTasks:();
  .tst.specCleanupTasks:();
  .tst.testState.runnerCoverageEvents:`symbol$();
  .tst.testState.runnerCoverageOriginal:{[x]x+1};
  .tst.testState.runnerCoverageReplacement:replacement;
  .tst.testState.runnerCoverageCoverageThrows:coverageThrows;
  .tst.testState.runnerCoverageReportThrows:reportThrows;
  .tst.testState.runnerCoverageRestoreThrows:restoreThrows;
  .tst.testState.runnerCoverageAuthority:authority;
  `.tst.testState.runnerCoverageBusiness set {[x]
    .tst.testState.runnerCoverageEvents,:enlist `wrapped;
    x+100};
  fixtureName:`runnerCoverageFixture;
  ![`.tst.fixtures;();0b;enlist fixtureName];
  .tst.registerFixtureWithOpts[
    fixtureName;
    1;
    `scope`teardown!(`session;{[fixtureValue]
      .tst.testState.runnerCoverageEvents,:enlist `fixture
    })];
  .tst.fixtures[fixtureName;`instance]:1;
  if[authority~`valid;
    `.tst.restoreCoverageInstrumentation set {[]
      .tst.testState.runnerCoverageEvents,:enlist `restore;
      `.tst.testState.runnerCoverageBusiness set
        .tst.testState.runnerCoverageOriginal;
      if[.tst.testState.runnerCoverageRestoreThrows;'"restore boom"];
      1b}];
  if[authority~`missing;
    .tst.deleteVar `.tst.restoreCoverageInstrumentation];
  if[authority~`malformed;
    `.tst.restoreCoverageInstrumentation set 42];
  if[authority~`wrongRank;
    `.tst.restoreCoverageInstrumentation set {[x]x}];
  .tst.loadTests:{[args]
    .tst.testState.runnerCoverageEvents,:enlist `body;
    (get `.tst.testState.runnerCoverageBusiness)4;
    replacement:.tst.testState.runnerCoverageReplacement;
    if[replacement~`noop;
      `.tst.restoreCoverageInstrumentation set {[]1b}];
    if[replacement~`throw;
      `.tst.restoreCoverageInstrumentation set {[]'"replacement boom"}];
    if[replacement~`mock;
      .tst.mock[`.tst.restoreCoverageInstrumentation;
        {[]'"mocked replacement boom"}]];
    .tst.registerCleanup[{[]
      .tst.testState.runnerCoverageEvents,:enlist `expectation};
      enlist(::)];
    .tst.registerSpecCleanup[{[]
      .tst.testState.runnerCoverageEvents,:enlist `spec};
      enlist(::)]};
  .tst.runAllPhase.generateCoverage:{[]
    .tst.testState.runnerCoverageEvents,:enlist `coverage;
    if[104<>(get `.tst.testState.runnerCoverageBusiness)4;
      '"coverage lost instrumented function"];
    if[.tst.testState.runnerCoverageCoverageThrows;'"coverage boom"]};
  .resq.report:{[rows]
    .tst.testState.runnerCoverageEvents,:enlist `report;
    if[.tst.testState.runnerCoverageReportThrows;'"report boom"]};
  outcome:@[{[] .tst.runAll[];`ok};();{[err](`escaped;err)}];
  escaped:not outcome~`ok;
  events:.tst.testState.runnerCoverageEvents;
  businessValue:(get `.tst.testState.runnerCoverageBusiness)4;
  `events`escaped`passed`cleanupFailures`businessValue!(
    events;
    escaped;
    .tst.app.passed;
    .tst.app.cleanupFailures;
    businessValue)
 };

.tst.runnerLifecycle.setupSpecTest:{[]
    names:(`.tst.runExpec`.tst.callbacks.expecRan`.tst.snapshotNamespaceValues),
      `.tst.captureMockLifecycle;
    .tst.testState.runnerLifecycle:
      `savedNamed`savedRuntime`savedTimer`savedHalt`savedGuard`savedFailHard`savedFailFast`savedExit`savedResults`savedCounters`savedCleanup`savedSpecCleanup`events!(
        .tst.runnerLifecycle.namedValues names;
        .tst.captureRuntimeContext[];
        @[get;`.z.ts;{::}];
        .tst.halt;
        .tst.app.pollutionGuard;
        .tst.app.failHard;
        .tst.app.failFast;
        .tst.app.exit;
        .resq.state.results;
        (.tst.app.expectationsRan;.tst.app.expectationsPassed;.tst.app.expectationsFailed;.tst.app.expectationsErrored);
        .tst.cleanupTasks;
        .tst.specCleanupTasks;
        `symbol$());
    .tst.cleanupTasks:();
    .tst.specCleanupTasks:();
    .tst.halt:0b;
    .tst.app.pollutionGuard:0b;
    .tst.app.failHard:0b;
    .tst.app.failFast:0b;
    .tst.app.exit:0b;
    .tst.callbacks.expecRan:{[s;e]};
 };
.tst.runnerLifecycle.teardownSpecTest:{[]
    .tst.runnerLifecycle.cleanupScratch[];
    @[.tst.runCleanupTasks;();{}];
    @[.tst.runSpecCleanupTasks;();{}];
    state:.tst.testState.runnerLifecycle;
    .tst.runnerLifecycle.restoreNamed state[`savedNamed];
    .tst.restoreRuntimeContext state[`savedRuntime];
    .z.ts:state[`savedTimer];
    .tst.halt:state[`savedHalt];
    .tst.app.pollutionGuard:state[`savedGuard];
    .tst.app.failHard:state[`savedFailHard];
    .tst.app.failFast:state[`savedFailFast];
    .tst.app.exit:state[`savedExit];
    .resq.state.results:state[`savedResults];
    .tst.app.expectationsRan:(state[`savedCounters]) 0;
    .tst.app.expectationsPassed:(state[`savedCounters]) 1;
    .tst.app.expectationsFailed:(state[`savedCounters]) 2;
    .tst.app.expectationsErrored:(state[`savedCounters]) 3;
    .tst.cleanupTasks:state[`savedCleanup];
    .tst.specCleanupTasks:state[`savedSpecCleanup];
    ![`.tst.testState;();0b;enlist `runnerLifecycle];
 };

.tst.desc["runSpec finalization: early paths"]{
  before{.tst.runnerLifecycle.setupSpecTest[]};
  after{.tst.runnerLifecycle.teardownSpecTest[]};
  should["drain spec cleanup exactly once when already halted"]{
    .tst.halt:1b;
    .tst.registerSpecCleanup[{[]
      .tst.testState.runnerLifecycle.events,:enlist `cleanup
      };enlist(::)];
    spec:.tst.runnerLifecycle.spec[();{};{}];
    .tst.runSpec spec;
    .tst.runSpec spec;
    .tst.testState.runnerLifecycle.events musteq enlist `cleanup;
    (count .tst.specCleanupTasks) musteq 0;
  };

  should["finalize resources and still attempt afterAll after beforeAll throws"]{
    path:(system "cd"),"/runner_lifecycle_beforeall_",(string .z.i),".tmp";
    .tst.testState.runnerLifecycle[`path]:path;
    (hsym `$path) 0:enlist "lifecycle";
    beforeHook:{[]
      path:.tst.testState.runnerLifecycle[`path];
      .tst.testState.runnerLifecycle[`handle]:
        hopen hsym `$path;
      .z.ts:{42};
      .tst.registerSpecCleanup[{[]
        handles:.tst.runnerLifecycle.openHandles[];
        event:$[.tst.testState.runnerLifecycle[`handle] in handles;
          `cleanupBeforeClose;
          `cleanupAfterClose];
        .tst.testState.runnerLifecycle.events,:enlist event
        };enlist(::)];
      '"beforeAll boom"
    };
    afterHook:{[]
      .tst.testState.runnerLifecycle.events,:enlist `afterAll
    };
    result:.tst.runSpec .tst.runnerLifecycle.spec[();beforeHook;afterHook];
    handles:.tst.runnerLifecycle.openHandles[];
    result[`result] musteq `fail;
    .tst.testState.runnerLifecycle.events musteq `afterAll`cleanupAfterClose;
    .tst.asserts[`must][not .tst.testState.runnerLifecycle[`handle] in handles;"handle remained open"];
    .tst.asserts[`must][.tst.testState.runnerLifecycle[`savedTimer]~@[get;`.z.ts;{::}];"timer was not restored"];
  };
};

.tst.desc["runSpec finalization: execution errors"]{
  before{.tst.runnerLifecycle.setupSpecTest[]};
  after{.tst.runnerLifecycle.teardownSpecTest[]};
  should["convert an unexpected runExpec throw and still attempt afterAll"]{
    .tst.runExpec:{[s;e] '"runExpec boom"};
    .tst.registerSpecCleanup[{[]
      .tst.testState.runnerLifecycle.events,:enlist `cleanup
      };enlist(::)];
    afterHook:{[]
      .tst.testState.runnerLifecycle.events,:enlist `afterAll
    };
    outcome:@[.tst.runSpec;
      .tst.runnerLifecycle.spec[enlist .tst.runnerLifecycle.simpleExpec `pass;{};afterHook];
      {[e] (`escaped;e)}];
    .tst.asserts[`must][99h=type outcome;"runSpec error escaped"];
    outcome[`result] musteq `fail;
    .tst.testState.runnerLifecycle.events musteq `afterAll`cleanup;
  };

  should["contain a throwing result callback and still attempt afterAll"]{
    .tst.runExpec:(.tst.testState.runnerLifecycle[`savedNamed])[`.tst.runExpec];
    .tst.callbacks.expecRan:{[s;e] '"callback boom"};
    afterHook:{[]
      .tst.testState.runnerLifecycle.events,:enlist `afterAll
    };
    expec:.tst.runnerLifecycle.testExpec {1b};
    outcome:@[.tst.runSpec;
      .tst.runnerLifecycle.spec[enlist expec;{};afterHook];
      {[e] (`escaped;e)}];
    .tst.asserts[`must][99h=type outcome;"callback error escaped runSpec"];
    outcome[`result] musteq `fail;
    .tst.testState.runnerLifecycle.events musteq enlist `afterAll;
  };

  should["make afterAll failure visible without replacing the passing result"]{
    .tst.runExpec:{[s;e] e};
    afterHook:{[] '"afterAll boom"};
    result:.tst.runSpec .tst.runnerLifecycle.spec[
      enlist .tst.runnerLifecycle.simpleExpec `pass;
      {};
      afterHook];
    result[`result] musteq `fail;
    (count result[`expectations]) musteq 2;
    (.tst.normalizeResultStatus (last result[`expectations])[`result]) musteq `error;
  };

  should["retain spec finalizer authority across helper and cleanup mutations"]{
    .tst.deleteVar `.tst.testState.runnerLifecycleSpecLeak;
    afterHook:{[]
      .tst.mock[`.tst.finalizeSpec;{[state]()}];
      .tst.mock[`.tst.finalizeSpecWith;{[authority;state]
        '"mocked spec finalizer"}];
      .tst.mock[`.tst.restoreMockLifecycle;{[state]::}];
      .tst.mock[`.tst.runFinalizationPipeline;{[plan;state]
        '"mocked spec cleanup pipeline"}];
      .tst.mock[`.tst.makeExpectationCleanup;{[]{[]::}}];
      .tst.mock[`.tst.makeSpecCleanup;{[]{[]::}}];
      .tst.mock[`.tst.testState.runnerLifecycleSpecLeak;42];
      .tst.registerSpecCleanup[{[]
        .tst.testState.runnerLifecycle.events,:enlist `cleanupThrow;
        .tst.mock[`.tst.restoreRuntimeContext;{[ctx]::}];
        '"spec cleanup boom"
        };enlist(::)];
      .tst.registerSpecCleanup[{[]
        .tst.testState.runnerLifecycle.events,:enlist `cleanupAfterThrow
        };enlist(::)]
    };
    outcome:@[
      .tst.runSpec;
      .tst.runnerLifecycle.spec[();{};afterHook];
      {[err] (`escaped;err)}];
    .tst.asserts[`must][99h=type outcome;"spec finalizer error escaped"];
    outcome[`result] musteq `fail;
    .tst.testState.runnerLifecycle.events musteq
      `cleanupThrow`cleanupAfterThrow;
    (count .tst.specCleanupTasks) musteq 1;
    mustthrow["*runnerLifecycleSpecLeak*";{
      get `.tst.testState.runnerLifecycleSpecLeak
    }];
    .tst.asserts[`must][
      not `.tst.finalizeSpecWith in .tst.mockRegistryNames[];
      "spec finalizer replacement survived"];
    .tst.asserts[`must][
      not `.tst.restoreRuntimeContext in .tst.mockRegistryNames[];
      "spec cleanup callback replacement survived"];
    .tst.asserts[`must][
      not any `.tst.makeExpectationCleanup`.tst.makeSpecCleanup in
        .tst.mockRegistryNames[];
      "spec cleanup capsule builder replacement survived"];
  };
};

.tst.desc["runSpec finalization: acquisition"]{
  before{.tst.runnerLifecycle.setupSpecTest[]};
  after{.tst.runnerLifecycle.teardownSpecTest[]};

  should["preserve caller mock ownership when an earlier spec acquisition fails"]{
    target:`.tst.testState.runnerLifecycleSpecCallerMock;
    target set {[x]x};
    .tst.mock[target;{[x]x+10}];
    expected:.tst.captureMockLifecycle[];
    savedCapture:.tst.captureRuntimeContext;
    .tst.captureRuntimeContext:{[]'"early spec capture boom"};
    outcome:@[
      .tst.runSpec;
      .tst.runnerLifecycle.spec[();{};{}];
      {[err] (`escaped;err)}];
    .tst.captureRuntimeContext:savedCapture;
    afterCapture:.tst.captureMockLifecycle[];
    .tst.asserts[`must][
      99h=type outcome;
      "early spec acquisition failure escaped"];
    comparable:
      `store`removeList`trackedState`spyCalls`spyImpls`seqs;
    (comparable#afterCapture) mustmatch comparable#expected;
    ((get target)5) musteq 15;
  };

  should["fail closed when lifecycle capture and callback both throw"]{
    baselineRuntime:.tst.captureRuntimeContext[];
    baselineTimer:@[get;`.z.ts;{::}];
    baselineHandles:.tst.runnerLifecycle.openHandles[];
    path:(system "cd"),"/runner_lifecycle_acquisition_",
      (string .z.i),".tmp";
    .tst.testState.runnerLifecycle[`path]:path;
    (hsym `$path) 0:enlist "lifecycle";
    .resq.state.results:.resq.state.emptyResults[];
    .tst.captureMockLifecycle:{[]
      path:.tst.testState.runnerLifecycle[`path];
      .tst.testState.runnerLifecycle[`handle]:hopen hsym `$path;
      .z.ts:{46};
      '"capture mock boom"};
    .tst.callbacks.expecRan:{[s;e] '"callback boom"};
    beforeHook:{[]
      .tst.testState.runnerLifecycle.events,:enlist `body
    };
    outcome:@[.tst.runSpec;
      .tst.runnerLifecycle.spec[();beforeHook;{}];
      {[e] (`escaped;e)}];
    afterRuntime:.tst.captureRuntimeContext[];
    afterTimer:@[get;`.z.ts;{::}];
    afterHandles:.tst.runnerLifecycle.openHandles[];
    .tst.asserts[`must][99h=type outcome;"capture error escaped runSpec"];
    outcome[`result] musteq `fail;
    .tst.testState.runnerLifecycle.events musteq `symbol$();
    (count .resq.state.results) musteq 1;
    .resq.state.results[0;`status] musteq `error;
    .tst.asserts[`must][
      .resq.state.results[0;`message] like "*acquisition*";
      "capture failure row was not visible"];
    afterRuntime mustmatch baselineRuntime;
    afterTimer mustmatch baselineTimer;
    afterHandles mustmatch baselineHandles;
  };

  should["capture a deleted removeList target without throwing"]{
    savedStore:.tst.mockState.store;
    savedRemoveList:.tst.mockState.removeList;
    missing:`.tst.testState.runnerLifecycleMissingMock;
    .tst.deleteVar missing;
    .tst.mockState.removeList:enlist missing;
    outcome:@[.tst.captureMockLifecycle;();{[e] (`escaped;e)}];
    .tst.mockState.store:savedStore;
    .tst.mockState.removeList:savedRemoveList;
    .tst.asserts[`must][99h=type outcome;"corrupt removeList escaped capture"];
    missingIndex:first where outcome[`trackedState;`names]=missing;
    outcome[`trackedState;`exists;missingIndex] musteq 0b;
  };

  should["append the canonical row when the callback is a no-op"]{
    .resq.state.results:.resq.state.emptyResults[];
    .tst.captureMockLifecycle:{[] '"capture mock noop callback"};
    .tst.callbacks.expecRan:{[s;e]};
    result:.tst.runSpec .tst.runnerLifecycle.spec[();{};{}];
    result[`result] musteq `fail;
    (count .resq.state.results) musteq 1;
    .resq.state.results[0;`status] musteq `error;
    .tst.asserts[`must][
      .resq.state.results[0;`message] like "*acquisition*";
      "no-op callback left no canonical failure row"];
  };

  should["append the error when a noisy callback adds only a pass row"]{
    .resq.state.results:.resq.state.emptyResults[];
    .tst.captureMockLifecycle:{[] '"capture mock noisy callback"};
    .tst.callbacks.expecRan:{[s;e]
      noise:flip `suite`description`status`message`time`failures`assertsRun!(
        enlist `CALLBACK_NOISE;
        enlist `not_the_lifecycle_error;
        enlist `pass;
        enlist "";
        enlist 0Nn;
        enlist ();
        enlist 0i);
      .resq.state.results:.resq.state.results upsert noise};
    result:.tst.runSpec .tst.runnerLifecycle.spec[();{};{}];
    result[`result] musteq `fail;
    (count .resq.state.results) musteq 2;
    (sum .resq.state.results[`status]=`error) musteq 1i;
    errorRow:first .resq.state.results where
      .resq.state.results[`status]=`error;
    .tst.asserts[`must][
      errorRow[`message] like "*capture mock noisy callback*";
      "noisy callback suppressed the canonical lifecycle error"];
  };
};

.tst.desc["runSpec finalization: halt and pollution"]{
  before{.tst.runnerLifecycle.setupSpecTest[]};
  after{.tst.runnerLifecycle.teardownSpecTest[]};
  should["run current afterAll once, then skip later halted suites"]{
    .tst.runExpec:(.tst.testState.runnerLifecycle[`savedNamed])[`.tst.runExpec];
    .tst.callbacks.expecRan:(.tst.testState.runnerLifecycle[`savedNamed])[`.tst.callbacks.expecRan];
    .tst.app.failHard:1b;
    .tst.registerSpecCleanup[{[]
      .tst.testState.runnerLifecycle.events,:enlist `cleanup
      };enlist(::)];
    afterHook:{[]
      .tst.testState.runnerLifecycle.events,:enlist `afterAll
    };
    expec:.tst.runnerLifecycle.testExpec {'"fail hard boom"};
    result:.tst.runSpec .tst.runnerLifecycle.spec[enlist expec;{};afterHook];
    laterBefore:{[]
      .tst.testState.runnerLifecycle.events,:enlist `laterBefore
    };
    laterAfter:{[]
      .tst.testState.runnerLifecycle.events,:enlist `laterAfter
    };
    later:.tst.runSpec .tst.runnerLifecycle.spec[
      enlist .tst.runnerLifecycle.simpleExpec `pass;
      laterBefore;
      laterAfter];
    .tst.halt musteq 1b;
    result[`result] musteq `fail;
    later[`result] musteq `didNotRun;
    .tst.testState.runnerLifecycle.events musteq `afterAll`cleanup;
  };

  should["continue resource cleanup when pollution restoration throws"]{
    .tst.app.pollutionGuard:1b;
    .tst.testState.runnerLifecycle[`throwPollution]:0b;
    .tst.snapshotNamespaceValues:{[ns]
      if[1b~.tst.testState.runnerLifecycle[`throwPollution]; '"pollution cleanup boom"];
      ((.tst.testState.runnerLifecycle[`savedNamed])[`.tst.snapshotNamespaceValues]) ns
    };
    path:(system "cd"),"/runner_lifecycle_pollution_",(string .z.i),".tmp";
    .tst.testState.runnerLifecycle[`path]:path;
    (hsym `$path) 0:enlist "lifecycle";
    .tst.runExpec:{[s;e]
      path:.tst.testState.runnerLifecycle[`path];
      .tst.testState.runnerLifecycle[`handle]:
        hopen hsym `$path;
      .z.ts:{43};
      .tst.registerSpecCleanup[{[]
        handles:.tst.runnerLifecycle.openHandles[];
        event:$[.tst.testState.runnerLifecycle[`handle] in handles;
          `cleanupBeforeClose;
          `cleanupAfterClose];
        .tst.testState.runnerLifecycle.events,:enlist event
        };enlist(::)];
      .tst.testState.runnerLifecycle[`throwPollution]:1b;
      e
    };
    outcome:@[.tst.runSpec;
      .tst.runnerLifecycle.spec[enlist .tst.runnerLifecycle.simpleExpec `pass;{};{}];
      {[e] (`escaped;e)}];
    handles:.tst.runnerLifecycle.openHandles[];
    .tst.asserts[`must][99h=type outcome;"pollution cleanup error escaped"];
    outcome[`result] musteq `fail;
    .tst.testState.runnerLifecycle.events musteq enlist `cleanupAfterClose;
    .tst.asserts[`must][not .tst.testState.runnerLifecycle[`handle] in handles;"handle remained open"];
    .tst.asserts[`must][.tst.testState.runnerLifecycle[`savedTimer]~@[get;`.z.ts;{::}];"timer was not restored"];
  };
};

.tst.desc["run lifecycle reset"]{
  should["reset mutable rerun state without erasing args"]{
    saved:`halt`loadErrors`results`allSpecs`appResults`cleanup`specCleanup`context`tstPath`currentContext`assertState`args!(
        .tst.halt;
        .tst.app.loadErrors;
        .resq.state.results;
        .tst.app.allSpecs;
        @[get;`.tst.app.results;()];
        .tst.cleanupTasks;
        .tst.specCleanupTasks;
        .tst.context;
        .tst.tstPath;
        .tst.currentContext;
        .tst.assertState;
        .tst.app.args);
    .tst.testState.runnerLifecycleEvents:`symbol$();
    .tst.cleanupTasks:(),enlist (`func`args!({[]
      .tst.testState.runnerLifecycleEvents,:enlist `cleanup};enlist(::)));
    .tst.specCleanupTasks:(),enlist (`func`args!({[]
      .tst.testState.runnerLifecycleEvents,:enlist `specCleanup};enlist(::)));
    .tst.halt:1b;
    .tst.app.loadErrors:flip `file`error`type!(enlist `bad;enlist "bad";enlist `load);
    .tst.app.allSpecs:enlist `poison;
    .tst.app.results:enlist `poison;
    .tst.context:`.poison;
    .tst.tstPath:`:poison;
    .tst.currentContext:`file`suite`test!("poison";"poison";"poison");
    .tst.assertState:`poison;
    .tst.app.args:("keep";"these");
    .tst.runAllPhase.initRun[];
    resetHalt:.tst.halt;
    resetLoadErrors:.tst.app.loadErrors;
    resetAllSpecs:.tst.app.allSpecs;
    resetAppResults:.tst.app.results;
    resetCleanup:.tst.cleanupTasks;
    resetSpecCleanup:.tst.specCleanupTasks;
    resetContext:.tst.context;
    resetPath:.tst.tstPath;
    resetCurrent:.tst.currentContext;
    resetAssert:.tst.assertState;
    keptArgs:.tst.app.args;
    drained:.tst.testState.runnerLifecycleEvents;
    .tst.halt:saved[`halt];
    .tst.app.loadErrors:saved[`loadErrors];
    .resq.state.results:saved[`results];
    .tst.app.allSpecs:saved[`allSpecs];
    .tst.app.results:saved[`appResults];
    .tst.cleanupTasks:saved[`cleanup];
    .tst.specCleanupTasks:saved[`specCleanup];
    .tst.context:saved[`context];
    .tst.tstPath:saved[`tstPath];
    .tst.currentContext:saved[`currentContext];
    .tst.assertState:saved[`assertState];
    .tst.app.args:saved[`args];
    ![`.tst.testState;();0b;enlist `runnerLifecycleEvents];
    resetHalt musteq 0b;
    (count resetLoadErrors) musteq 0;
    (count resetAllSpecs) musteq 0;
    (count resetAppResults) musteq 0;
    (count resetCleanup) musteq 0;
    (count resetSpecCleanup) musteq 0;
    resetContext musteq `.;
    resetPath musteq `;
    resetCurrent musteq `file`suite`test!("";"";"");
    resetAssert mustmatch .tst.defaultAssertState;
    keptArgs musteq ("keep";"these");
    drained musteq `cleanup`specCleanup;
  };
};

.tst.desc["run lifecycle reporter failure"]{
  should["fail and finalize exactly once when the reporter throws"]{
    names:(`.tst.runAllPhase.initRun`.tst.loadTests`.tst.runAllPhase.filterSpecs),
      (`.tst.runAllPhase.runDiscoveredSpecs`.tst.runAllPhase.injectLoadErrors),
      (`.tst.runAllPhase.applyStrictMode`.tst.runAllPhase.computePassed),
      (`.tst.runAllPhase.generateCoverage),
      `.tst.printRunAudit`.resq.report;
    savedNamed:.tst.runnerLifecycle.namedValues names;
    savedRunState:.tst.captureNamedLifecycle
      (`.tst.app.passed`.tst.app.exit`.tst.app.args`.tst.app.runFailures),
      (`.tst.app.reportingFailed`.tst.app.coverageFailed),
      (`.tst.app.runRuntimeContext`.tst.app.runTimer`.tst.app.runHandles),
      (`.tst.app.runLifecycle`.tst.app.cleanupComplete`.tst.app.cleanupFailures),
      (`.tst.app.cleanupFailed`.tst.app.executionState);
    savedResults:.resq.state.results;
    savedStep:.tst._runAllStep;
    .tst.testState.runnerLifecycleEvents:`symbol$();
    .tst.runAllPhase.initRun:{[] .tst.app.passed:1b;.tst.app.exit:0b};
    .tst.loadTests:{[x]};
    .tst.runAllPhase.filterSpecs:{[]};
    .tst.runAllPhase.runDiscoveredSpecs:{[]};
    .tst.runAllPhase.injectLoadErrors:{[]};
    .tst.runAllPhase.applyStrictMode:{[]};
    .tst.runAllPhase.computePassed:{[] .tst.app.passed:1b};
    .tst.runAllPhase.generateCoverage:{[]};
    .tst.registerCleanup[{[]
      .tst.testState.runnerLifecycleEvents,:enlist `cleanup};
      enlist(::)];
    .tst.printRunAudit:{[]};
    .resq.report:{[x]
      .tst.testState.runnerLifecycleEvents,:enlist `report;
      '"reporter boom"};
    .tst.testState.runnerLifecycleEscaped:0b;
    @[.tst.runAll;();{[e]
      .tst.testState.runnerLifecycleEscaped:1b;
      :()}];
    failed:not .tst.app.passed;
    events:.tst.testState.runnerLifecycleEvents;
    escaped:.tst.testState.runnerLifecycleEscaped;
    .tst.installQExports[];
    .tst.runnerLifecycle.restoreNamed savedNamed;
    .tst.restoreNamedLifecycle savedRunState;
    .resq.state.results:savedResults;
    .tst._runAllStep:savedStep;
    ![`.tst.testState;();0b;`runnerLifecycleEvents`runnerLifecycleEscaped];
    .tst.asserts[`must][not escaped;"reporter error escaped runAll"];
    .tst.asserts[`must][failed;"reporter failure left run green"];
    events musteq `cleanup`report;
  };
};

.tst.desc["run lifecycle coverage failure"]{
  should["fail, attempt both artifacts, and finalize on coverage errors"]{
    names:(`.tst.runAllPhase.initRun`.tst.loadTests`.tst.runAllPhase.filterSpecs),
      (`.tst.runAllPhase.runDiscoveredSpecs`.tst.runAllPhase.injectLoadErrors),
      (`.tst.runAllPhase.applyStrictMode`.tst.runAllPhase.computePassed),
      `.tst.printRunAudit`.resq.report;
    savedNamed:.tst.runnerLifecycle.namedValues names;
    oldLCOV:@[get;`.tst.generateLCOV;{`missing}];
    oldHTML:@[get;`.tst.generateHTML;{`missing}];
    savedRunState:.tst.captureNamedLifecycle
      (`.tst.app.passed`.tst.app.exit`.tst.app.args`.tst.app.runCoverage),
      (`.tst.app.baseDir`.tst.app.runFailures`.tst.app.reportingFailed),
      (`.tst.app.coverageFailed`.tst.app.runRuntimeContext`.tst.app.runTimer),
      (`.tst.app.runHandles`.tst.app.runLifecycle`.tst.app.cleanupComplete),
      (`.tst.app.cleanupFailures`.tst.app.cleanupFailed`.tst.app.executionState);
    savedResults:.resq.state.results;
    savedStep:.tst._runAllStep;
    savedOutDir:.resq.config.outDir;
    .tst.testState.runnerLifecycleEvents:`symbol$();
    .tst.runAllPhase.initRun:{[] .tst.app.passed:1b;.tst.app.exit:0b};
    .tst.loadTests:{[x]};
    .tst.runAllPhase.filterSpecs:{[]};
    .tst.runAllPhase.runDiscoveredSpecs:{[]};
    .tst.runAllPhase.injectLoadErrors:{[]};
    .tst.runAllPhase.applyStrictMode:{[]};
    .tst.runAllPhase.computePassed:{[] .tst.app.passed:1b};
    .tst.registerCleanup[{[]
      .tst.testState.runnerLifecycleEvents,:enlist `cleanup};
      enlist(::)];
    .tst.printRunAudit:{[]};
    .resq.report:{[x]
      .tst.testState.runnerLifecycleEvents,:enlist `report;
      .tst.testState.runnerLifecycleReported:x};
    .tst.generateLCOV:{[path]
      .tst.testState.runnerLifecycleEvents,:enlist `lcov;
      '"lcov boom"};
    .tst.generateHTML:{[path]
      .tst.testState.runnerLifecycleEvents,:enlist `html;
      '"html boom"};
    .tst.app.runCoverage:1b;
    .tst.app.baseDir:system "cd";
    .resq.config.outDir:".";
    .tst.testState.runnerLifecycleEscaped:0b;
    @[.tst.runAll;();{[e]
      .tst.testState.runnerLifecycleEscaped:1b;
      :()}];
    failed:not .tst.app.passed;
    events:.tst.testState.runnerLifecycleEvents;
    escaped:.tst.testState.runnerLifecycleEscaped;
    reported:.tst.testState.runnerLifecycleReported;
    .tst.installQExports[];
    .tst.runnerLifecycle.restoreNamed savedNamed;
    $[oldLCOV~`missing;.tst.deleteVar `.tst.generateLCOV;`.tst.generateLCOV set oldLCOV];
    $[oldHTML~`missing;.tst.deleteVar `.tst.generateHTML;`.tst.generateHTML set oldHTML];
    .tst.restoreNamedLifecycle savedRunState;
    .resq.state.results:savedResults;
    .tst._runAllStep:savedStep;
    .resq.config.outDir:savedOutDir;
    ![`.tst.testState;();0b;
      `runnerLifecycleEvents`runnerLifecycleEscaped`runnerLifecycleReported];
    .tst.asserts[`must][not escaped;"coverage error escaped runAll"];
    .tst.asserts[`must][failed;"coverage failure left run green"];
    events musteq `lcov`html`cleanup`report;
    .tst.asserts[`must][
      any reported[`status]=`error;
      "reporter did not receive the coverage failure row"];
    .tst.asserts[`must][
      any reported[`message] like "*LCOV generation failed*";
      "coverage failure detail missing from reported rows"];
  };
};

.tst.desc["run lifecycle coverage restoration"]{
  before{.tst.runnerLifecycle.setupCoverageTest[]};
  after{.tst.runnerLifecycle.teardownCoverageTest[]};

  should["capture one restorer across repeated noquit runs and hostile replacements"]{
    expected:
      `body`wrapped`coverage`wrapped`fixture`expectation`spec,
      `restore`framework`report;
    plain:.tst.runnerLifecycle.coverageRun[`none;0b;0b;0b;`valid];
    noop:.tst.runnerLifecycle.coverageRun[`noop;0b;0b;0b;`valid];
    throwing:.tst.runnerLifecycle.coverageRun[`throw;0b;0b;0b;`valid];
    mocked:.tst.runnerLifecycle.coverageRun[`mock;0b;0b;0b;`valid];
    plain[`events] musteq expected;
    noop[`events] musteq expected;
    throwing[`events] musteq expected;
    mocked[`events] musteq expected;
    .tst.asserts[`must][
      all not (plain;noop;throwing;mocked)[;`escaped];
      "a noquit run escaped"];
    .tst.asserts[`must][
      all (plain;noop;throwing;mocked)[;`passed];
      "a successful coverage restoration left the run failed"];
    (plain;noop;throwing;mocked)[;`businessValue] musteq 4#5;
    (count each (plain;noop;throwing;mocked)[;`cleanupFailures]) musteq 4#0;
  };

  should["invoke a present restorer but tolerate an absent one on noncoverage reruns"]{
    .tst.app.runCoverage:0b;
    stale:.tst.runnerLifecycle.coverageRun[`none;0b;0b;0b;`valid];
    absent:.tst.runnerLifecycle.coverageRun[`none;0b;0b;0b;`missing];
    malformed:.tst.runnerLifecycle.coverageRun[`none;0b;0b;0b;`malformed];
    wrongRank:.tst.runnerLifecycle.coverageRun[`none;0b;0b;0b;`wrongRank];
    stale[`businessValue] musteq 5;
    (sum stale[`events]=`restore) musteq 1i;
    absent[`businessValue] musteq 104;
    (sum absent[`events]=`restore) musteq 0i;
    (malformed;wrongRank)[;`businessValue] musteq 2#104;
    (sum each (malformed;wrongRank)[;`events]=`restore) musteq 2#0i;
    .tst.asserts[`must][all (stale;absent;malformed;wrongRank)[;`passed];
      "a noncoverage rerun failed solely because of restorer availability"];
    (count each (stale;absent;malformed;wrongRank)[;`cleanupFailures]) musteq
      4#0;
  };

  should["restore after coverage data on artifact and report failures"]{
    expected:
      `body`wrapped`coverage`wrapped`fixture`expectation`spec,
      `restore`framework`report;
    artifact:.tst.runnerLifecycle.coverageRun[`none;1b;0b;0b;`valid];
    report:.tst.runnerLifecycle.coverageRun[`none;0b;1b;0b;`valid];
    artifact[`events] musteq expected;
    report[`events] musteq expected;
    .tst.asserts[`must][not any artifact[`escaped],report[`escaped];
      "run failure escaped"];
    .tst.asserts[`must][not any artifact[`passed],report[`passed];
      "artifact or report failure left a run green"];
    artifact[`businessValue] musteq 5;
    report[`businessValue] musteq 5;
    (sum artifact[`events]=`restore) musteq 1i;
    (sum report[`events]=`restore) musteq 1i;
  };

  should["retain restore failure and continue every later finalizer"]{
    result:.tst.runnerLifecycle.coverageRun[`none;0b;0b;1b;`valid];
    result[`events] musteq
      `body`wrapped`coverage`wrapped`fixture`expectation`spec,
      `restore`framework`report;
    .tst.asserts[`must][not result[`escaped];"restore failure escaped"];
    .tst.asserts[`must][not result[`passed];"restore failure left run green"];
    result[`businessValue] musteq 5;
    (sum result[`events]=`restore) musteq 1i;
    (count result[`cleanupFailures]) musteq 1;
    failure:first result[`cleanupFailures];
    failure musteq "coverageInstrumentation: restore boom";
  };

  should["fail closed on a missing or malformed restorer only under coverage"]{
    expected:
      `body`wrapped`coverage`wrapped`fixture`expectation`spec`framework`report;
    missing:.tst.runnerLifecycle.coverageRun[`none;0b;0b;0b;`missing];
    malformed:.tst.runnerLifecycle.coverageRun[`none;0b;0b;0b;`malformed];
    wrongRank:.tst.runnerLifecycle.coverageRun[`none;0b;0b;0b;`wrongRank];
    missing[`events] musteq expected;
    malformed[`events] musteq expected;
    wrongRank[`events] musteq expected;
    .tst.asserts[`must][not any (missing;malformed;wrongRank)[;`passed];
      "invalid coverage restorer left a run green"];
    (count each (missing;malformed;wrongRank)[;`cleanupFailures]) musteq 3#1;
    failures:first each (missing;malformed;wrongRank)[;`cleanupFailures];
    .tst.asserts[`must][
      all {x like "*coverage instrumentation restore is missing or malformed*"}
        each failures;
      "invalid restorer failure was not retained"];
  };
};

.tst.desc["run lifecycle cleanup idempotence"]{
  should["make finalCleanup idempotent and retain cleanup failure state"]{
    savedFixtures:.tst.fixtures;
    savedState:`passed`executionState`cleanupComplete`cleanupFailures`cleanupFailed`runRuntimeContext`runTimer`runHandles!(
      .tst.app.passed;
      .tst.app.executionState;
      @[get;`.tst.app.cleanupComplete;0b];
      @[get;`.tst.app.cleanupFailures;()];
      @[get;`.tst.app.cleanupFailed;0b];
      .tst.app.runRuntimeContext;
      .tst.app.runTimer;
      .tst.app.runHandles);
    savedTimer:@[get;`.z.ts;{::}];
    savedCleanupTasks:.tst.cleanupTasks;
    savedSpecCleanupTasks:.tst.specCleanupTasks;
    .tst.testState.runnerLifecycleEvents:`symbol$();
    fixtureName:`runnerLifecycleIdempotenceFixture;
    ![`.tst.fixtures;();0b;enlist fixtureName];
    .tst.registerFixtureWithOpts[
      fixtureName;
      1;
      `scope`teardown!(`session;{[fixtureValue]
        .tst.testState.runnerLifecycleEvents,:enlist `fixtureAttempt;
        '"fixture cleanup boom"
      })];
    .tst.fixtures[fixtureName;`instance]:1;
    .tst.cleanupTasks:(),enlist (`func`args!({[]
      .tst.testState.runnerLifecycleEvents,:enlist `cleanup};enlist(::)));
    .tst.specCleanupTasks:(),enlist (`func`args!({[]
      .tst.testState.runnerLifecycleEvents,:enlist `specCleanup};enlist(::)));
    .tst.app.cleanupComplete:0b;
    .tst.app.cleanupFailures:();
    .tst.app.cleanupFailed:0b;
    .tst.app.passed:1b;
    .tst.app.runRuntimeContext:.tst.captureRuntimeContext[];
    .tst.app.runTimer:savedTimer;
    .tst.app.runHandles:.tst.runnerLifecycle.openHandles[];
    .z.ts:{44};
    .tst.runAllPhase.finalCleanup[];
    .tst.runAllPhase.finalCleanup[];
    .tst.installQExports[];
    events:.tst.testState.runnerLifecycleEvents;
    failed:.tst.app.cleanupFailed and not .tst.app.passed;
    restoredTimer:savedTimer~@[get;`.z.ts;{::}];
    .tst.fixtures:savedFixtures;
    .tst.cleanupTasks:savedCleanupTasks;
    .tst.specCleanupTasks:savedSpecCleanupTasks;
    .tst.app.passed:savedState[`passed];
    .tst.app.executionState:savedState[`executionState];
    .tst.app.cleanupComplete:savedState[`cleanupComplete];
    .tst.app.cleanupFailures:savedState[`cleanupFailures];
    .tst.app.cleanupFailed:savedState[`cleanupFailed];
    .tst.app.runRuntimeContext:savedState[`runRuntimeContext];
    .tst.app.runTimer:savedState[`runTimer];
    .tst.app.runHandles:savedState[`runHandles];
    .z.ts:savedTimer;
    ![`.tst.testState;();0b;enlist `runnerLifecycleEvents];
    events musteq `fixtureAttempt`cleanup`specCleanup;
    .tst.asserts[`must][failed;"cleanup failure was not retained"];
    .tst.asserts[`must][restoredTimer;"run timer was not restored"];
  };
};

.tst.desc["run lifecycle acquisition"]{
  should["fail closed, skip execution, restore partial state, and report once"]{
    functionNames:(`.tst.openHandles`.tst.runAllPhase.initRun),
      (`.tst.printRunAudit`.resq.report);
    savedFunctions:.tst.runnerLifecycle.namedValues functionNames;
    savedRunState:.tst.runnerLifecycle.captureRunState[];
    baselineRuntime:.tst.captureRuntimeContext[];
    baselineTimer:@[get;`.z.ts;{::}];
    .tst.testState.runnerLifecycleEvents:`symbol$();
    .tst.openHandles:{[]
      .z.ts:{45};
      system "d .tst";
      '"run handles capture boom"};
    .tst.runAllPhase.initRun:{[]
      .tst.testState.runnerLifecycleEvents,:enlist `init};
    .tst.printRunAudit:{[]};
    .resq.report:{[rows]
      .tst.testState.runnerLifecycleEvents,:enlist `report;
      .tst.testState.runnerLifecycleReported:rows};
    .tst.app.exit:0b;
    .tst.testState.runnerLifecycleEscaped:0b;
    @[.tst.runAll;();{[err]
      .tst.testState.runnerLifecycleEscaped:1b;
      :()}];
    .tst.installQExports[];
    escaped:.tst.testState.runnerLifecycleEscaped;
    failed:not .tst.app.passed;
    cleanupComplete:.tst.app.cleanupComplete;
    events:.tst.testState.runnerLifecycleEvents;
    reported:.tst.testState.runnerLifecycleReported;
    .tst.runnerLifecycle.restoreNamed savedFunctions;
    restoredRuntime:.tst.captureRuntimeContext[];
    restoredTimer:@[get;`.z.ts;{::}];
    .tst.restoreNamedLifecycle savedRunState;
    ![`.tst.testState;();0b;
      `runnerLifecycleEvents`runnerLifecycleReported`runnerLifecycleEscaped];
    .tst.asserts[`must][not escaped;"run acquisition error escaped"];
    .tst.asserts[`must][failed;"run acquisition failure left run green"];
    .tst.asserts[`must][cleanupComplete;"cleanup was not attempted"];
    events musteq enlist `report;
    restoredRuntime mustmatch baselineRuntime;
    restoredTimer mustmatch baselineTimer;
    (count reported) musteq 1;
    reported[0;`suite] musteq `RUN_LIFECYCLE_ERROR;
    reported[0;`description] musteq `acquisition;
    .tst.asserts[`must][
      reported[0;`message] like "*handles acquisition failed*";
      "acquisition detail missing from final rows"];
  };

  should["contain bookkeeping failure, finalize, and report once"]{
    functionNames:
      `.tst.prepareRunBookkeeping`.tst.runAllPhase.initRun,
      `.tst.printRunAudit`.resq.report;
    savedFunctions:.tst.runnerLifecycle.namedValues functionNames;
    savedRunState:.tst.runnerLifecycle.captureRunState[];
    .tst.testState.runnerLifecycleEvents:`symbol$();
    .tst.prepareRunBookkeeping:{[]'"bookkeeping boom"};
    .tst.runAllPhase.initRun:{[]
      .tst.testState.runnerLifecycleEvents,:enlist `init};
    .tst.printRunAudit:{[]};
    .resq.report:{[rows]
      .tst.testState.runnerLifecycleEvents,:enlist `report;
      .tst.testState.runnerLifecycleReported:rows};
    .tst.app.exit:0b;
    outcome:@[{[].tst.runAll[];`ok};();{[err](`escaped;err)}];
    escaped:not outcome~`ok;
    failed:not .tst.app.passed;
    cleanupComplete:.tst.app.cleanupComplete;
    events:.tst.testState.runnerLifecycleEvents;
    reported:.tst.testState.runnerLifecycleReported;
    bookkeepingIndices:where
      (reported[`suite]=`RUN_LIFECYCLE_ERROR) and
      reported[`description]=`bookkeeping;
    .tst.installQExports[];
    .tst.runnerLifecycle.restoreNamed savedFunctions;
    .tst.restoreNamedLifecycle savedRunState;
    ![`.tst.testState;();0b;
      `runnerLifecycleEvents`runnerLifecycleReported];
    .tst.asserts[`must][not escaped;"bookkeeping failure escaped runAll"];
    .tst.asserts[`must][failed;"bookkeeping failure left run green"];
    .tst.asserts[`must][cleanupComplete;"bookkeeping failure skipped cleanup"];
    events musteq enlist `report;
    (count bookkeepingIndices) musteq 1;
    .tst.asserts[`must][
      reported[first bookkeepingIndices;`message] like "*bookkeeping boom*";
      "bookkeeping detail missing from final rows"];
  };
};

.tst.desc["run lifecycle cleanup reporting"]{
  should["materialize cleanup failures before the single report"]{
    functionNames:(`.tst.runAllPhase.initRun`.tst.loadTests),
      (`.tst.runAllPhase.filterSpecs`.tst.runAllPhase.runDiscoveredSpecs),
      (`.tst.runAllPhase.injectLoadErrors`.tst.runAllPhase.applyStrictMode),
      (`.tst.runAllPhase.computePassed`.tst.runAllPhase.generateCoverage),
      (`.tst.finalCleanupDirectory`.tst.printRunAudit`.resq.report);
    savedFunctions:.tst.runnerLifecycle.namedValues functionNames;
    savedRunState:.tst.runnerLifecycle.captureRunState[];
    .tst.testState.runnerLifecycleEvents:`symbol$();
    .tst.runAllPhase.initRun:{[] .tst.app.exit:0b};
    .tst.loadTests:{[args]};
    .tst.runAllPhase.filterSpecs:{[]};
    .tst.runAllPhase.runDiscoveredSpecs:{[]};
    .tst.runAllPhase.injectLoadErrors:{[]};
    .tst.runAllPhase.applyStrictMode:{[]};
    .tst.runAllPhase.computePassed:{[] .tst.app.passed:1b};
    .tst.runAllPhase.generateCoverage:{[]};
    .tst.finalCleanupDirectory:{[]
      .tst.testState.runnerLifecycleEvents,:enlist `cleanup;
      '"forced cleanup boom"};
    .tst.printRunAudit:{[] '"audit boom"};
    .resq.report:{[rows]
      .tst.testState.runnerLifecycleEvents,:enlist `report;
      .tst.testState.runnerLifecycleReported:rows};
    .tst.testState.runnerLifecycleEscaped:0b;
    @[.tst.runAll;();{[err]
      .tst.testState.runnerLifecycleEscaped:1b;
      :()}];
    escaped:.tst.testState.runnerLifecycleEscaped;
    failed:not .tst.app.passed;
    events:.tst.testState.runnerLifecycleEvents;
    reported:.tst.testState.runnerLifecycleReported;
    .tst.runnerLifecycle.restoreNamed savedFunctions;
    .tst.restoreNamedLifecycle savedRunState;
    ![`.tst.testState;();0b;
      `runnerLifecycleEvents`runnerLifecycleReported`runnerLifecycleEscaped];
    .tst.asserts[`must][not escaped;"cleanup failure escaped runAll"];
    .tst.asserts[`must][failed;"cleanup failure left run green"];
    events musteq `cleanup`report;
    (count reported) musteq 2;
    reported[`description] musteq `cleanup`audit;
    .tst.asserts[`must][
      reported[0;`message] like "*forced cleanup boom*";
      "cleanup failure missing from reported rows"];
    .tst.asserts[`must][
      reported[1;`message] like "*audit boom*";
      "audit failure missing from reported rows"];
  };
};

.tst.desc["run lifecycle immutable finalizer"]{
  should["restore mocked cleanup authority and attempt every user cleanup"]{
    phaseNames:(`.tst.loadTests`.tst.runAllPhase.filterSpecs),
      (`.tst.runAllPhase.runDiscoveredSpecs`.tst.runAllPhase.injectLoadErrors),
      (`.tst.runAllPhase.applyStrictMode`.tst.runAllPhase.computePassed),
      (`.tst.runAllPhase.generateCoverage`.tst.printRunAudit`.resq.report);
    savedPhases:.tst.runnerLifecycle.namedValues phaseNames;
    savedRunState:.tst.runnerLifecycle.captureRunState[];
    fixtureName:`runnerLifecycleAuthorityFixture;
    ![`.tst.fixtures;();0b;enlist fixtureName];
    .tst.testState.runnerLifecycleAuthorityEvents:`symbol$();
    .tst.testState.runnerLifecycleAuthorityFixtureRan:0b;
    .tst.registerFixtureWithOpts[
      fixtureName;
      7;
      `scope`teardown!(`session;{[fixtureValue]
        .tst.testState.runnerLifecycleAuthorityFixtureRan:1b
      })];
    .tst.fixtures[fixtureName;`instance]:7;
    .tst.loadTests:{[args]
      .tst.testState.runnerLifecycleAuthorityEvents,:enlist `body;
      .tst.mock[`.tst.runAllPhase.finalCleanup;{[]()}];
      .tst.mock[`.tst.runFinalCleanupWith;{[authority;state;guard]
        '"mocked run finalizer"}];
      .tst.mock[`.tst.cleanupAllFixtures;{[]::}];
      .tst.mock[`.tst.makeFixtureCleanup;{[]{[]::}}];
      .tst.mock[`.tst.makeExpectationCleanup;{[]{[]::}}];
      .tst.mock[`.tst.makeSpecCleanup;{[]{[]::}}];
      .tst.mock[`.tst.teardownFixture;{[name;fixtureValue]
        '"mocked nested fixture cleanup"}];
      .tst.mock[`.tst.runFinalizationPipeline;
        {[plan;state]()}];
      .tst.registerCleanup[{[]
        .tst.testState.runnerLifecycleAuthorityEvents,:enlist `expecThrow;
        .tst.mock[`.tst.restoreDir;{[]'"late directory replacement"}];
        '"run cleanup boom"
        };enlist(::)];
      .tst.registerCleanup[{[]
        .tst.testState.runnerLifecycleAuthorityEvents,:enlist `expecAfter
        };enlist(::)];
      .tst.registerSpecCleanup[{[]
        .tst.testState.runnerLifecycleAuthorityEvents,:enlist `specCleanup;
        .tst.mock[`.tst.restoreRuntimeContext;{[ctx]::}]
        };enlist(::)]
    };
    .tst.runAllPhase.filterSpecs:{[]};
    .tst.runAllPhase.runDiscoveredSpecs:{[]};
    .tst.runAllPhase.injectLoadErrors:{[]};
    .tst.runAllPhase.applyStrictMode:{[]};
    .tst.runAllPhase.computePassed:{[] .tst.app.passed:1b};
    .tst.runAllPhase.generateCoverage:{[]};
    .tst.printRunAudit:{[]};
    .resq.report:{[rows]};
    .tst.app.exit:0b;
    .tst.testState.runnerLifecycleAuthorityEscaped:0b;
    @[.tst.runAll;();{[err]
      .tst.testState.runnerLifecycleAuthorityEscaped:1b;
      :()}];
    escaped:.tst.testState.runnerLifecycleAuthorityEscaped;
    failed:not .tst.app.passed;
    cleanupComplete:.tst.app.cleanupComplete;
    fixtureReleased:(::)~.tst.fixtures[fixtureName;`instance];
    fixtureRan:.tst.testState.runnerLifecycleAuthorityFixtureRan;
    events:.tst.testState.runnerLifecycleAuthorityEvents;
    retainedCleanup:count .tst.cleanupTasks;
    tracked:.tst.mockRegistryNames[];
    .tst.installQExports[];
    .tst.runnerLifecycle.restoreNamed savedPhases;
    .tst.restoreNamedLifecycle savedRunState;
    ![`.tst.fixtures;();0b;enlist fixtureName];
    ![`.tst.testState;();0b;
      `runnerLifecycleAuthorityEvents`runnerLifecycleAuthorityFixtureRan,
      `runnerLifecycleAuthorityEscaped];
    .tst.asserts[`must][not escaped;"immutable run finalizer escaped"];
    .tst.asserts[`must][failed;"throwing cleanup left run green"];
    .tst.asserts[`must][cleanupComplete;"run cleanup was not completed"];
    .tst.asserts[`must][fixtureRan;"captured fixture cleanup did not run"];
    .tst.asserts[`must][fixtureReleased;"session fixture was not released"];
    retainedCleanup musteq 1;
    events musteq `body`expecThrow`expecAfter`specCleanup;
    .tst.asserts[`must][
      not `.tst.runAllPhase.finalCleanup in tracked;
      "top-level run finalizer replacement survived"];
    .tst.asserts[`must][
      not `.tst.teardownFixture in tracked;
      "nested fixture helper replacement survived"];
    .tst.asserts[`must][
      not any
        `.tst.makeFixtureCleanup`.tst.makeExpectationCleanup`.tst.makeSpecCleanup
          in tracked;
      "cleanup capsule builder replacement survived"];
    .tst.asserts[`must][
      not `.tst.restoreRuntimeContext in tracked;
      "cleanup callback helper replacement survived"];
  };
};

.tst.desc["run lifecycle caller isolation"]{
  should["preserve an active caller mock when pre-mock run acquisition fails"]{
    phaseNames:
      `.tst.captureRunQExports`.tst.printRunAudit`.resq.report;
    savedPhases:.tst.runnerLifecycle.namedValues phaseNames;
    savedRunState:.tst.runnerLifecycle.captureRunState[];
    target:`.tst.testState.runnerLifecycleAcquisitionCallerMock;
    target set {[x]x};
    .tst.mock[target;{[x]x+10}];
    expected:.tst.captureMockLifecycle[];
    .tst.captureRunQExports:{[]'"run q export capture boom"};
    .tst.printRunAudit:{[]};
    .resq.report:{[rows]};
    .tst.app.exit:0b;
    outcome:@[{[] .tst.runAll[];`ok};();{[err](`escaped;err)}];
    afterCapture:.tst.captureMockLifecycle[];
    targetValue:(get target)5;
    comparable:
      `store`removeList`trackedState`spyCalls`spyImpls`seqs;
    .tst.runnerLifecycle.restoreNamed savedPhases;
    .tst.restoreNamedLifecycle savedRunState;
    .tst.asserts[`must][
      `ok~outcome;
      "run acquisition failure escaped"];
    (comparable#afterCapture) mustmatch comparable#expected;
    targetValue musteq 15;
  };

  should["restore caller mocks, spies, sequences, and pre-existing sandboxes"]{
    phaseNames:(`.tst.loadTests`.tst.runAllPhase.filterSpecs),
      (`.tst.runAllPhase.runDiscoveredSpecs`.tst.runAllPhase.injectLoadErrors),
      (`.tst.runAllPhase.applyStrictMode`.tst.runAllPhase.computePassed),
      (`.tst.runAllPhase.generateCoverage`.tst.printRunAudit`.resq.report);
    scratchNames:(`.tst.testState.runnerLifecycleCallerMock),
      (`.tst.testState.runnerLifecycleCallerSpy),
      (`.tst.testState.runnerLifecycleCallerSeq),
      (`.tst.testState.runnerLifecycleRunOwned),
      (`.tst.testState.runnerLifecycleCallerShould),
      (`.tst.testState.runnerLifecycleCallerCallback),
      `sandbox_runnerLifecycleExisting`sandbox_runnerLifecycleCreated;
    savedPhases:.tst.runnerLifecycle.namedValues phaseNames;
    savedScratch:.tst.captureNamedLifecycle scratchNames;
    savedLiveShould:.tst.captureNamedLifecycle enlist `.q.should;
    savedRunState:.tst.runnerLifecycle.captureRunState[];
    .tst.testState.runnerLifecycleCallerShould:
      {[title;definition] `callerShould};
    `.q.should set .tst.testState.runnerLifecycleCallerShould;
    .tst.callbacks.descLoaded:{[spec]
      .tst.testState.runnerLifecycleCallerCallback:spec};
    .tst.setMockLifecycleValue[
      `.tst.testState.runnerLifecycleCallerMock;
      {[x] x+1}];
    .tst.setMockLifecycleValue[
      `.tst.testState.runnerLifecycleCallerSpy;
      {[x] x*2}];
    .tst.setMockLifecycleValue[
      `.tst.testState.runnerLifecycleCallerSeq;
      {[x] x}];
    .tst.setMockLifecycleValue[
      `.tst.testState.runnerLifecycleRunOwned;
      {[x] x-1}];
    .tst.setMockLifecycleValue[
      `sandbox_runnerLifecycleExisting;
      `stable`nested!(42;`a`b)];
    .tst.deleteVar `sandbox_runnerLifecycleCreated;
    .tst.mock[
      `.tst.testState.runnerLifecycleCallerMock;
      {[x] x+10}];
    .tst.spy[`.tst.testState.runnerLifecycleCallerSpy;::];
    .tst.mockSequence[
      `.tst.testState.runnerLifecycleCallerSeq;
      10 20 30];
    (get `.tst.testState.runnerLifecycleCallerSpy) 3;
    expectedMocks:.tst.captureMockLifecycle[];
    expectedSandbox:.tst.lifecycleValue `sandbox_runnerLifecycleExisting;
    .tst.loadTests:{[args]
      .tst.setMockLifecycleValue[
        `sandbox_runnerLifecycleExisting;
        `changed];
      .tst.setMockLifecycleValue[
        `sandbox_runnerLifecycleCreated;
        `created];
      .tst.mock[
        `.tst.testState.runnerLifecycleRunOwned;
        {[x] x+100}];
      (get `.tst.testState.runnerLifecycleCallerSpy) 4;
      (get `.tst.testState.runnerLifecycleCallerSeq) 0;
      :()};
    .tst.runAllPhase.filterSpecs:{[]};
    .tst.runAllPhase.runDiscoveredSpecs:{[]};
    .tst.runAllPhase.injectLoadErrors:{[]};
    .tst.runAllPhase.applyStrictMode:{[]};
    .tst.runAllPhase.computePassed:{[] .tst.app.passed:1b};
    .tst.runAllPhase.generateCoverage:{[]};
    .tst.printRunAudit:{[]};
    .resq.report:{[rows]};
    .tst.app.exit:0b;
    .tst.testState.runnerLifecycleEscaped:0b;
    @[.tst.runAll;();{[err]
      .tst.testState.runnerLifecycleEscaped:1b;
      :()}];
    escaped:.tst.testState.runnerLifecycleEscaped;
    afterMocks:.tst.captureMockLifecycle[];
    afterSandbox:@[.tst.lifecycleValue;
      `sandbox_runnerLifecycleExisting;
      {`missing}];
    createdExists:not `missing~
      @[.tst.lifecycleValue;`sandbox_runnerLifecycleCreated;{`missing}];
    callerMockValue:(get `.tst.testState.runnerLifecycleCallerMock) 5;
    runOwnedValue:(get `.tst.testState.runnerLifecycleRunOwned) 5;
    callerShouldValue:(get `.q.should)[`ignored;{}];
    .tst.callbacks.descLoaded `callbackRestored;
    callbackValue:.tst.testState.runnerLifecycleCallerCallback;
    .tst.runnerLifecycle.restoreNamed savedPhases;
    .tst.restoreNamedLifecycle savedScratch;
    .tst.restoreNamedLifecycle savedLiveShould;
    .tst.restoreNamedLifecycle savedRunState;
    ![`.tst.testState;();0b;enlist `runnerLifecycleEscaped];
    .tst.asserts[`must][not escaped;"caller-isolation run escaped"];
    comparableMockFields:
      `store`removeList`trackedState`spyCalls`spyImpls`seqs;
    (comparableMockFields#afterMocks) mustmatch
      comparableMockFields#expectedMocks;
    afterSandbox mustmatch expectedSandbox;
    .tst.asserts[`must][not createdExists;"run-owned sandbox survived cleanup"];
    callerMockValue musteq 15;
    runOwnedValue musteq 4;
    callerShouldValue musteq `callerShould;
    callbackValue musteq `callbackRestored;
  };
};

.tst.desc["run lifecycle q exports"]{
  should["reinstall authoritative exports across two in-process cycles"]{
    savedRunState:.tst.runnerLifecycle.captureRunState[];
    baselineOriginal:@[get;`.tst.originalQ;{`missing}];
    savedLiveMust:.tst.captureNamedLifecycle enlist `.q.must;
    savedCallerMust:.tst.captureNamedLifecycle
      enlist `.tst.testState.runnerLifecycleCallerMust;
    savedRuntime:.tst.captureRuntimeContext[];
    .tst.cleanupTasks:();
    .tst.specCleanupTasks:();
    cycleResults:`boolean$();
    do[2;
      .tst.testState.runnerLifecycleCallerMust:{[condition;message]
        `callerMust};
      `.q.must set .tst.testState.runnerLifecycleCallerMust;
      lifecycle:.tst.captureRunLifecycle[];
      lifecycle[`initStarted]:1b;
      .tst.app.runLifecycle:lifecycle;
      .tst.finalCleanupQExports[];
      callerRestored:
        `callerMust~(get `.q.must)[0b;"ignored"];
      .tst.runAllPhase.initRun[];
      system "d .runnerLifecycleQProbe";
      probe:@[{[] (value "{[] must[1b;\"q export unavailable\"];1b}")[]};
        ();
        {[err] 0b}];
      .tst.restoreRuntimeContext savedRuntime;
      installed:@[get;`.q.must;{::}]~.tst.qExports[`must];
      cycleResults,:callerRestored and installed and probe];
    afterOriginal:@[get;`.tst.originalQ;{`missing}];
    .tst.restoreNamedLifecycle savedRunState;
    .tst.restoreNamedLifecycle savedLiveMust;
    .tst.restoreNamedLifecycle savedCallerMust;
    .tst.restoreRuntimeContext savedRuntime;
    cycleResults musteq 11b;
    afterOriginal mustmatch baselineOriginal;
  };
};
