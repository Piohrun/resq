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
  @[{[] if[`fixtureEvents in key `.tst.testState;
    ![`.tst.testState; (); 0b; enlist `fixtureEvents]]}; (); {}];
  myRestore[];
  };
 should["call the main expectation function"]{
  `ran mock 0b;
  should["run this"]{`ran mock 1b};
  e:getExpec[];
  .tst.runExpec[();e];
  .tst.contextHelper[];
  must[ran;"Expected the expectation to have run."];
  };
 should["call the before function before calling the main expectation function"]{
  `beforeRan`ran mock' 0b;
  should["run this"]{`ran mock 1b and beforeRan};
  before {`beforeRan mock 1b};
  e:getExpec[];
  .tst.runExpec[();e];
  .tst.contextHelper[];
  must[beforeRan;"Expected the before expectation to run"];
  must[ran;"Expected the main expectation to run after the before function"];
  };
 should["call the after function after calling the main expectation function"]{
  `afterRan`ran mock' 0b;
  should["run this"]{`ran mock 1b};
  after {`afterRan mock 1b and ran};
  e:getExpec[];
  .tst.runExpec[();e];
  .tst.contextHelper[];
  must[ran;"Expected the main expectation to run"];
  must[afterRan;"Expected the after function to run after the main expectation"];
  };
 should["make assertions available to be used within the expectation"]{
  `.q.must mock {[x;y];'"fail"};
  should["run this"]{`noError mock @[{must[1b;"silent pass"];1b};(::);0b]};
  e:getExpec[];
  .tst.runExpec[();e];
  .tst.contextHelper[];
  must[noError;"Expected the assertion method to not throw an error"];
  };
 should["execute the expectation in the correct context"]{
  should["change context"]{`..context mock system "d";};
  e:getExpec[];
  `.tst.context mock `.foo;
  .tst.runExpec[();e];
  `.[`context] mustmatch `.foo;
  };
 should["restore mocked values after all expectation functions have executed"]{
  `ran mock 0b;
  `.tst.restore mock {`ran mock 1b};
  should["run this"]{};
  e:getExpec[];
  .tst.runExpec[();e];
  .tst.contextHelper[];
  must[ran;"Expected the mocking restore function to have been called"];
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
  `beforeCounter mock 0;;
  `restoreCounter mock 0;
  `.tst.restore mock {restoreCounter+:1};
  `.tst.halt mock 1b;
  before{beforeCounter+:1};
  should["restage"]{'"foo"};
  e:getExpec[];
  .tst.runExpec[();e];
  beforeCounter musteq 2;
  restoreCounter musteq 1;
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
