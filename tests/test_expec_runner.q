.tst.desc["Running an Expectation"]{
 before{
  `.tst.contextHelper mock {[x;y] system "d ", string x} system "d"; / Need to change back to the proper execution context after every call that refers to a mocked variable in the current context
  `myRestore mock .tst.restore; / Mocking restore so the UI doesn't get clobbered
  `.tst.restore mock {};
  `.tst.expecList mock .tst.expecList;
  `.tst.currentBefore mock .tst.currentBefore;
  `.tst.currentAfter mock .tst.currentAfter;
  `.tst.callbacks.expecRan mock {[x;y]}; / Mock this out so expectations run TO test running expectations don't count towards test expectations ran
  `getExpec mock {last .tst.fillExpecBA .tst.expecList};
  };
 after{
  @[{[]
    names:`lifecycleFirst`lifecycleSecond`lifecycleThird`lifecycleThrowing`lifecycleAssertState`lifecycleSelfRemoving`lifecycleFailHard;
    ![`.tst.fixtures; (); 0b; names]
    }; (); {}];
  myRestore[];
  @[{[]
    names:`expecRan`expecBeforeRan`expecBodyRan`expecAfterRan`expecNoError,
      `expecContext`expecRestoreTarget`expecCallerMock`expecCleanupEvents,
      `expecCleanupAttempts`invalidRetryBodies`expecBeforeCounter,
      `expecRestoreCounter`fixtureEvents;
    present:names inter key `.tst.testState;
    if[count present;![`.tst.testState;();0b;present]]
    }; (); {}];
 };
 should["call the main expectation function"]{
  .tst.testState.expecRan:0b;
  should["run this"]{.tst.testState.expecRan:1b};
  e:getExpec[];
  .tst.runExpec[();e];
  .tst.contextHelper[];
  must[.tst.testState.expecRan;"Expected the expectation to have run."];
  };
 should["call the before function before calling the main expectation function"]{
  .tst.testState.expecBeforeRan:0b;
  .tst.testState.expecBodyRan:0b;
  should["run this"]{
    .tst.testState.expecBodyRan:.tst.testState.expecBeforeRan};
  before {.tst.testState.expecBeforeRan:1b};
  e:getExpec[];
  .tst.runExpec[();e];
  .tst.contextHelper[];
  must[.tst.testState.expecBeforeRan;
    "Expected the before expectation to run"];
  must[.tst.testState.expecBodyRan;
    "Expected the main expectation to run after the before function"];
  };
 should["call the after function after calling the main expectation function"]{
  .tst.testState.expecAfterRan:0b;
  .tst.testState.expecBodyRan:0b;
  should["run this"]{.tst.testState.expecBodyRan:1b};
  after {
    .tst.testState.expecAfterRan:.tst.testState.expecBodyRan};
  e:getExpec[];
  .tst.runExpec[();e];
  .tst.contextHelper[];
  must[.tst.testState.expecBodyRan;"Expected the main expectation to run"];
  must[.tst.testState.expecAfterRan;
    "Expected the after function to run after the main expectation"];
 };
 should["make assertions available to be used within the expectation"]{
  .tst.testState.expecNoError:0b;
  should["run this"]{
    .tst.testState.expecNoError:
      @[{must[1b;"silent pass"];1b};(::);0b]};
  e:getExpec[];
  .tst.runExpec[();e];
  .tst.contextHelper[];
  must[.tst.testState.expecNoError;
    "Expected the assertion method to not throw an error"];
  };
 should["execute the expectation in the correct context"]{
  .tst.testState.expecContext:`;
  should["change context"]{
    .tst.testState.expecContext:system "d"};
  e:getExpec[];
  `.tst.context mock `.foo;
  .tst.runExpec[();e];
  .tst.testState.expecContext mustmatch `.foo;
  };
 should["restore mocked values after all expectation functions have executed"]{
  .tst.testState.expecRestoreTarget:0;
  should["run this"]{
    `.tst.testState.expecRestoreTarget mock 1};
  e:getExpec[];
  .tst.runExpec[();e];
  .tst.contextHelper[];
 .tst.testState.expecRestoreTarget musteq 0;
  };
 should["preserve caller mocks when expectation setup fails"]{
  target:`.tst.testState.expecCallerMock;
  target set {[x]x};
  .tst.mock[target;{[x]x+10}];
  savedSetup:.tst.setupExpec;
  .tst.setupExpec:{[spec;expec]'"setup boom"};
  should["setup failure"]{};
  e:getExpec[];
  outcome:.[
    .tst.runExpec;
    (();e);
    {[err] (`escaped;err)}];
  .tst.setupExpec:savedSetup;
  .tst.asserts[`must][
    99h=type outcome;
    "setup failure escaped runExpec"];
  (.tst.normalizeResultStatus outcome`result) musteq `error;
  ((get target)5) musteq 15;
  target mustin .tst.mockRegistryNames[];
  };
 should["retain finalizer authority and fail after attempting throwing cleanups"]{
  .tst.testState.expecCleanupEvents:`symbol$();
  .tst.testState.expecCleanupAttempts:0;
  .tst.deleteVar `.tst.testState.expecCleanupLeak;
  should["mutate cleanup authority"]{
    .tst.registerCleanup[{[]
      .tst.testState.expecCleanupEvents,:enlist `throwing;
      .tst.testState.expecCleanupAttempts+:1;
      .tst.mock[`.tst.restoreRuntimeContext;{[ctx]'"late runtime replacement"}];
      if[1=.tst.testState.expecCleanupAttempts;'"cleanup boom"]
      };enlist(::)];
    .tst.registerCleanup[{[]
      .tst.testState.expecCleanupEvents,:enlist `afterThrow
      };enlist(::)];
    .tst.mock[`.tst.teardownExpec;{[s;e]e}];
    .tst.mock[`.tst.finalizeExpecWith;{[a;s;e]'"mocked finalizer"}];
    .tst.mock[`.tst.makeExpectationCleanup;{[]{[]::}}];
    .tst.mock[`.tst.runCleanupTasks;{[]::}];
    .tst.mock[`.tst.testState.expecCleanupLeak;42];
  };
  e:getExpec[];
  r:.tst.runExpec[();e];
  .tst.contextHelper[];
  .tst.testState.expecCleanupEvents musteq `throwing`afterThrow;
  (count .tst.cleanupTasks) musteq 1;
  (.tst.normalizeResultStatus r`result) musteq `error;
  mustthrow["*expecCleanupLeak*";{
    get `.tst.testState.expecCleanupLeak
  }];
  .tst.asserts[`must][
    not `.tst.finalizeExpecWith in .tst.mockRegistryNames[];
    "finalizer replacement survived"];
  .tst.asserts[`must][
    not `.tst.restoreRuntimeContext in .tst.mockRegistryNames[];
    "cleanup callback replacement survived"];
  .tst.runCleanupTasks[];
  .tst.testState.expecCleanupEvents musteq
    `throwing`afterThrow`throwing;
  (count .tst.cleanupTasks) musteq 0;
  ![`.tst.testState;();0b;
    `expecCleanupEvents`expecCleanupAttempts];
  };
 should["reject malformed retry counts before executing the body"]{
  .tst.testState.invalidRetryBodies:0;
  should["invalid retry body"]{.tst.testState.invalidRetryBodies+:1};
  e:getExpec[];
  invalid:("bad";0Nj;0Wj;1000000j;enlist 1;1f);
  results:{[template;bad]
    candidate:template;
    candidate[`retries]:bad;
    .tst.runExpec[();candidate]}[e;] each invalid;
  .tst.contextHelper[];
  .tst.testState.invalidRetryBodies musteq 0;
  (.tst.normalizeResultStatus each results[;`result]) musteq
    count[invalid]#`error;
  results[;`errorText] musteq
    count[invalid]#enlist
      "Invalid retries: expected an integer from 0 to 64";
  ![`.tst.testState;();0b;enlist `invalidRetryBodies];
  };
 should["prevent errors from escaping when running the expectation"]{
  should["run this"]{'foo};
  e:getExpec[];
  .tst.runExpec[();e];
  mustnotthrow[();{[x;y] .tst.runExpec[x]}[e]];
  };
 should["call the expecRan callback with the results of running the expectation and current specification"]{
  `.tst.callbackCalled mock 0b;                                / The context will be in .tst when the callback is executed
  `.tst.callbacks.expecRan mock {[x;y]`.tst.callbackCalled set 1b};
  should["run this"]{};
  e:getExpec[];
  .tst.runExpec[();e];
  .tst.contextHelper[];
   must[.tst.callbackCalled;"Expected the descLoaded callback to have been called"];
 };
 should["restage an expectation if the test run is to immediately halt"]{
  .tst.testState.expecBeforeCounter:0;
  .tst.testState.expecRestoreCounter:0;
  `.tst.restore mock {.tst.testState.expecRestoreCounter+:1};
  `.tst.halt mock 1b;
  before{.tst.testState.expecBeforeCounter+:1};
  should["restage"]{'"foo"};
  e:getExpec[];
  .tst.runExpec[();e];
  .tst.testState.expecBeforeCounter musteq 2;
  .tst.testState.expecRestoreCounter musteq 0;
  };
 should["unwind installed fixtures in reverse when a later setup throws"]{
  .tst.testState.fixtureEvents: `symbol$();
  fixtureNames:`lifecycleFirst`lifecycleSecond`lifecycleThird;
  .tst.registerFixtureWithOpts[`lifecycleFirst; 1;
    `scope`setup`teardown!(`test;
      {[x] .tst.testState.fixtureEvents,: enlist `setupFirst; x};
      {[x] .tst.testState.fixtureEvents,: enlist `teardownFirst})];
  .tst.registerFixtureWithOpts[`lifecycleSecond; 2;
    `scope`setup`teardown!(`test;
      {[x] .tst.testState.fixtureEvents,: enlist `setupSecond; x};
      {[x] .tst.testState.fixtureEvents,: enlist `teardownSecond})];
  .tst.registerFixtureWithOpts[`lifecycleThird; 3;
    `scope`setup`teardown!(`test;
      {[x] .tst.testState.fixtureEvents,: enlist `setupThird; '"fixture setup boom"};
      {[x] .tst.testState.fixtureEvents,: enlist `teardownThird})];
  should["partial fixture setup"]{[lifecycleFirst;lifecycleSecond;lifecycleThird] 1b};
  e:getExpec[];
  r:.tst.runExpec[();e];
  ![`.tst.fixtures; (); 0b; fixtureNames];
  .tst.contextHelper[];
  .tst.testState.fixtureEvents musteq `setupFirst`setupSecond`setupThird`teardownSecond`teardownFirst;
  (.tst.normalizeResultStatus r`result) musteq `error;
  ![`.tst.testState; (); 0b; enlist `fixtureEvents];
  };
 should["teardown a fixture exactly once when the test body throws"]{
  .tst.testState.fixtureEvents: `symbol$();
  .tst.registerFixtureWithOpts[`lifecycleThrowing; 1;
    `scope`setup`teardown!(`test;
      {[x] .tst.testState.fixtureEvents,: enlist `setup; x};
      {[x] .tst.testState.fixtureEvents,: enlist `teardown})];
  should["throw with fixture"]{[lifecycleThrowing]
    .tst.testState.fixtureEvents,: enlist `body;
    '"test body boom"
    };
  e:getExpec[];
  r:.tst.runExpec[();e];
  ![`.tst.fixtures; (); 0b; enlist `lifecycleThrowing];
  .tst.contextHelper[];
  .tst.testState.fixtureEvents musteq `setup`body`teardown;
  (.tst.normalizeResultStatus r`result) musteq `error;
  ![`.tst.testState; (); 0b; enlist `fixtureEvents];
  };
 should["teardown fixtures when assertion result extraction throws"]{
  .tst.testState.fixtureEvents: `symbol$();
  savedAssertState:.tst.assertState;
  .tst.registerFixtureWithOpts[`lifecycleAssertState; 1;
    `scope`setup`teardown!(`test;
      {[x] .tst.testState.fixtureEvents,: enlist `setup; x};
      {[x] .tst.testState.fixtureEvents,: enlist `teardown})];
  should["clobber assertion state"]{[lifecycleAssertState]
    .tst.testState.fixtureEvents,: enlist `body;
    .tst.assertState: `broken
    };
  e:getExpec[];
  r:.tst.runExpec[();e];
  .tst.assertState:savedAssertState;
  ![`.tst.fixtures; (); 0b; enlist `lifecycleAssertState];
  .tst.contextHelper[];
  .tst.testState.fixtureEvents musteq `setup`body`teardown;
  (.tst.normalizeResultStatus r`result) musteq `error;
  ![`.tst.testState; (); 0b; enlist `fixtureEvents];
  };
 should["use the captured fixture definition when setup removes its registry entry"]{
  .tst.testState.fixtureEvents: `symbol$();
  .tst.registerFixtureWithOpts[`lifecycleSelfRemoving; 1;
    `scope`setup`teardown!(`test;
      {[x]
        .tst.testState.fixtureEvents,: enlist `setup;
        ![`.tst.fixtures; (); 0b; enlist `lifecycleSelfRemoving];
        x
        };
      {[x] .tst.testState.fixtureEvents,: enlist `teardown})];
  should["throw after self-removing fixture setup"]{[lifecycleSelfRemoving]
    .tst.testState.fixtureEvents,: enlist `body;
    '"test body boom"
    };
  e:getExpec[];
  r:.tst.runExpec[();e];
  .tst.contextHelper[];
  .tst.testState.fixtureEvents musteq `setup`body`teardown;
  (.tst.normalizeResultStatus r`result) musteq `error;
  };
 should["teardown fixtures before a failing expectation halts the run"]{
  .tst.testState.fixtureEvents: `symbol$();
  `.tst.halt mock 0b;
  `.tst.app.failHard mock 1b;
  `.tst.callbacks.expecRan mock {[s;e] .tst.halt:1b};
  .tst.registerFixtureWithOpts[`lifecycleFailHard; 1;
    `scope`setup`teardown!(`test;
      {[x] .tst.testState.fixtureEvents,: enlist `setup; x};
      {[x] .tst.testState.fixtureEvents,: enlist `teardown})];
  should["fail hard with fixture"]{[lifecycleFailHard]
    .tst.testState.fixtureEvents,: enlist `body;
    '"fail hard boom"
    };
  e:getExpec[];
  r:.tst.runExpec[();e];
  ![`.tst.fixtures; (); 0b; enlist `lifecycleFailHard];
  .tst.contextHelper[];
  .tst.testState.fixtureEvents musteq `setup`body`teardown`setup`body`teardown;
  .tst.halt musteq 1b;
  (.tst.normalizeResultStatus r`result) musteq `error;
  ![`.tst.testState; (); 0b; enlist `fixtureEvents];
  };
 };
