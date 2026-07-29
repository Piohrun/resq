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
      / JUnit/XUnit output expects flat result rows (the results argument),
      / which .tst.resultRows (called inside the reporter) sanitizes itself.
      / Defensive serialization to avoid reporter crashes
      xmlReport: $[`top in key `.tst.output;
        @[.tst.output.top; results; {[e]
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
      (hsym `$outFile) 0: enlist xmlReport;
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

/ Snapshot process state before entering a specification. Reading the proc
/ directory temporarily consumes the lowest free descriptor in q itself.
/ Immediately opening /dev/null after the directory read returns that same
/ descriptor, allowing us to remove the observer from its own observation.
.tst.linuxOpenHandles:{[]
    fdDirectory:hsym `$":/proc/",string[.z.i],"/fd";
    listed:"J"$string key fdDirectory;
    probe:hopen `:/dev/null;
    @[hclose;probe;{}];
    listed except enlist probe
 };

.tst.openHandles:{[]
    $[.utl.isLinux;
      @[.tst.linuxOpenHandles;();{[e] key .z.W}];
      key .z.W]
 };

.tst.specPollutionNamespaces:{[enabled]
    if[not enabled; :0#`];
    (key `) except `q`Q`j`h`o`s`v`z`tst`resq`utl
 };

.tst.lifecycleValue:{[name]
    path:$[(string name) like ".*";name;.Q.dd[`.;name]];
    get path
 };

.tst.captureNamedLifecycle:{[names]
    names:distinct (),names;
    captured:{[name]
      result:@[{(1b;.tst.lifecycleValue x)};name;{(0b;::)}];
      (first result;last result)
    } each names;
    `names`exists`values!(
      names;
      $[count captured;first each captured;`boolean$()];
      $[count captured;last each captured;()])
 };

.tst.restoreNamedLifecycle:{[state]
    if[not 99h=type state; :()];
    names:$[`names in key state;state[`names];`symbol$()];
    exists:$[`exists in key state;state[`exists];count[names]#0b];
    values:$[`values in key state;state[`values];count[names]#enlist(::)];
    if[count names;
      {[name;didExist;original]
        $[didExist;
          .tst.setMockLifecycleValue[name;original];
          .tst.deleteVar name]
      }'[names;exists;values]];
 };

.tst.captureMockLifecycle:{[]
    store:.tst.mockState.store;
    removeList:.tst.mockState.removeList;
    tracked:(key[store] where not null key store) union removeList;
    `store`removeList`trackedState`spyCalls`spyImpls`seqs!(
      store;
      removeList;
      .tst.captureNamedLifecycle tracked;
      .tst.spyLog.calls;
      .tst.spyLog.impls;
      .tst.seqs)
 };

.tst.setMockLifecycleValue:{[name;mockValue]
    $[not (string name) like ".*";
      @[`.;name;:;mockValue];
      name set mockValue]
 };

.tst.restoreMockLifecycle:{[state]
    .tst.restore[];
    .tst.restoreNamedLifecycle state[`trackedState];
    .tst.mockState.store:state[`store];
    .tst.mockState.removeList:state[`removeList];
    .tst.spyLog.calls:state[`spyCalls];
    .tst.spyLog.impls:state[`spyImpls];
    .tst.seqs:state[`seqs];
 };

.tst.specLifecycleTitle:{[spec]
    @[{$[(99h=type x) and `title in key x;x[`title];`SPEC_LIFECYCLE]};
      spec;
      {`SPEC_LIFECYCLE}]
 };

.tst.emptySpecLifecycle:{[spec]
    fieldNames:`title`acquired`bodyEntered`runContextSet`runContext`diagnosticContextSet`diagnosticContext`assertStateSet`assertState`mockLifecycleSet`mockLifecycle`pollutionSet`pollutionGuard`namespaces`pollutionSnapshot`handlesSet`handles`timerSet`timer`errorPhase`error;
    values:(
        .tst.specLifecycleTitle spec;
        0b;
        0b;
        0b;
        ()!();
        0b;
        ()!();
        0b;
        ();
        0b;
        ()!();
        0b;
        0b;
        `symbol$();
        ()!();
        0b;
        `long$();
        0b;
        ::;
        `;
        ::);
    fieldNames!values
 };

.tst.captureLifecycleValue:{[fn]
    @[{[f] (`ok;f[])};fn;{[err] (`error;err)}]
 };

.tst.captureLifecycleSteps:{[state;phases;valueKeys;flagKeys;functions]
    idx:0;
    while[idx<count phases;
      outcome:.tst.captureLifecycleValue functions idx;
      if[`error~first outcome;
        state[`errorPhase]:phases idx;
        state[`error]:last outcome;
        :state];
      state[valueKeys idx]:last outcome;
      state[flagKeys idx]:1b;
      idx+:1];
    state[`acquired]:1b;
    state
 };

.tst.captureSpecPollution:{[]
    guard:$[`pollutionGuard in key `.tst.app;.tst.app.pollutionGuard;1b];
    namespaces:.tst.specPollutionNamespaces guard;
    snapshot:$[guard;namespaces!.tst.snapshotNamespaceValues each namespaces;()!()];
    `guard`namespaces`snapshot!(guard;namespaces;snapshot)
 };

.tst.captureSpecLifecycle:{[spec]
    state:.tst.emptySpecLifecycle spec;
    phases:`runtime`diagnostics`assertState`timer`handles`mocks`pollution;
    valueKeys:`runContext`diagnosticContext`assertState`timer`handles,
      `mockLifecycle`pollutionSnapshot;
    flagKeys:`runContextSet`diagnosticContextSet`assertStateSet`timerSet,
      `handlesSet`mockLifecycleSet`pollutionSet;
    functions:(
      .tst.captureRuntimeContext;
      {[] .tst.currentContext};
      {[] .tst.assertState};
      {[] @[get;`.z.ts;{::}]};
      .tst.openHandles;
      .tst.captureMockLifecycle;
      .tst.captureSpecPollution);
    state:.tst.captureLifecycleSteps[state;phases;valueKeys;flagKeys;functions];
    if[state[`pollutionSet];
      pollution:state[`pollutionSnapshot];
      state[`pollutionGuard]:pollution[`guard];
      state[`namespaces]:pollution[`namespaces];
      state[`pollutionSnapshot]:pollution[`snapshot]];
    state
 };

.tst.enterSpec:{[payload]
    spec:payload[`spec];
    lifecycle:payload[`lifecycle];
    ctx:$[`namespace in key spec;spec[`namespace];`context in key spec;spec[`context];`.];
    if[ctx~`;ctx:`.];
    .tst.context:ctx;
    system "d ",string ctx;
    if[`tstPath in key spec;.tst.tstPath:spec[`tstPath]];
    .tst.currentContext[`file]:.tst.toString .tst.tstPath;
    .tst.currentContext[`suite]:.tst.toString lifecycle[`title];
 };

/ Normalize either a table or scalar expectation into a general list.
.tst.specExpectationList:{[spec]
    exList:$[`expectations in key spec;spec[`expectations];`code in key spec;spec[`code];()];
    exType:type exList;
    if[98h=exType;
      exList:$[0=count exList;();{[table;idx] table idx}[exList] each til count exList];
      exType:type exList];
    if[not exType in 0 98h;exList:enlist exList];
    exList where not (::)~/:exList
 };

.tst.lifecycleErrorExpec:{[phase;err]
    errorText:.tst.toString err;
    description:.tst.toString[phase]," lifecycle failed";
    expec:.tst.internals.testObj;
    expec[`result]:`error;
    expec[`errorText]:errorText;
    expec[`desc]:description;
    expec[`before]:{};
    expec[`after]:{};
    expec[`runtimeContext]:@[.tst.captureRuntimeContext;();{()!()}];
    expec[`failures]:();
    expec[`assertsRun]:0i;
    expec[`time]:0Nn;
    expec
 };

.tst.appendLifecycleResult:{[spec;expec]
    if[not 98h=type .resq.state.results;
      .resq.state.results:.resq.state.emptyResults[]];
    suite:`$.tst.toString .tst.specLifecycleTitle spec;
    description:`$.tst.toString expec[`desc];
    message:.tst.toString expec[`errorText];
    row:flip `suite`description`status`message`time`failures`assertsRun!(
      enlist suite;
      enlist description;
      enlist `error;
      enlist message;
      enlist 0Nn;
      enlist enlist message;
      enlist 0i);
    .resq.state.results:.resq.state.results upsert row;
 };

.tst.hasLifecycleResult:{[spec;expec]
    if[not 98h=type .resq.state.results; :0b];
    if[0=count .resq.state.results; :0b];
    suite:`$ .tst.toString .tst.specLifecycleTitle spec;
    description:`$ .tst.toString expec[`desc];
    message:.tst.toString expec[`errorText];
    messageMatches:{[expected;actual] expected~actual}[message;] each
      .resq.state.results[`message];
    any (.resq.state.results[`suite]=suite) and
      (.resq.state.results[`description]=description) and
      (.resq.state.results[`status]=`error) and
      messageMatches
 };

/ Callback failures are contained so cleanup hooks still get their turn. A
/ callback is an extension point, not the storage authority: if it throws or
/ does nothing, append the canonical lifecycle row directly.
.tst.notifyLifecycleExpec:{[spec;expec]
    .[.tst.callbacks.expecRan;(spec;expec);{[args;err]
      -1 "ERROR recording lifecycle failure: ",.tst.toString err;
      :()}];
    if[not .tst.hasLifecycleResult[spec;expec];
      .tst.appendLifecycleResult[spec;expec]];
 };

.tst.appendSpecError:{[spec;phase;err]
    expec:.tst.lifecycleErrorExpec[phase;err];
    exList:.tst.specExpectationList spec;
    spec[`expectations]:exList,enlist expec;
    spec[`result]:`fail;
    .tst.notifyLifecycleExpec[spec;expec];
    spec
 };

/ Convert an unexpected expectation-runner error into an ordinary error result.
.tst.runSpecExpec:{[spec;expec]
    if[.tst.halt; :()];
    .[.tst.runExpec;(spec;expec);{[s;e;err]
      failed:.tst.lifecycleErrorExpec[`runExpec;err];
      .tst.notifyLifecycleExpec[s;failed];
      failed
    }[spec;expec;]]
 };

.tst.runSpecAfterAll:{[spec]
    if[not `afterAll in key spec; :spec];
    result:.tst.runHook spec[`afterAll];
    if[result~`ok; :spec];
    .tst.appendSpecError[spec;`afterAll;result 1]
 };

.tst.runSpecBody:{[payload]
    spec:payload[`spec];
    .tst.enterSpec payload;
    if[.tst.halt; :spec];
    beforeResult:$[`beforeAll in key spec;.tst.runHook spec[`beforeAll];`ok];
    if[not beforeResult~`ok;
      spec[`expectations]:();
      spec:.tst.appendSpecError[spec;`beforeAll;beforeResult 1];
      :.tst.runSpecAfterAll spec];
    exList:.tst.specExpectationList spec;
    exList:.tst.applyTestOnlyFocus[spec[`title];exList];
    results:.tst.runSpecExpec[spec;] each exList;
    results:results where not (::)~/:results;
    passed:$[count results;
      all (.tst.normalizeResultStatus each results[;`result]) in `pass`skip`pending;
      1b];
    spec[`expectations]:results;
    spec[`result]:$[passed;`pass;`fail];
    .tst.runSpecAfterAll spec
 };

/ Pollution restoration is one finalizer step; any error is returned to the
/ finalizer while later resource steps continue.
.tst.clearNewSpecNamespaces:{[lifecycle;current]
    newNamespaces:current except lifecycle[`namespaces];
    nonTrivial:newNamespaces where {[name] not (::)~@[get;name;::]} each newNamespaces;
    if[0=count nonTrivial; :()];
    -1 "WARNING: Test '",.tst.toString[lifecycle[`title]],
      "' introduced top-level names: ",.tst.toString nonTrivial;
    {@[set;(x;::);{}]} each nonTrivial;
    -1 "  -> Cleared values (q retains the bare names).";
 };

.tst.restoreSpecNamespace:{[title;namespace;original]
    current:.tst.snapshotNamespaceValues namespace;
    newKeys:(key current) except key original;
    if[count newKeys;
      -1 "WARNING: Test '",.tst.toString[title],"' leaked members in ",
        string[namespace],": ",.tst.toString newKeys;
      .tst.deleteVar each newKeys;
      -1 "  -> Cleaned up leaked members in ",string[namespace],"."];
    common:(key current) inter key original;
    modified:common where not {x~y}'[original common;current common];
    if[0=count modified; :()];
    -1 "WARNING: Test '",.tst.toString[title],"' modified globals in ",
      string[namespace],": ",.tst.toString modified;
    {[name;value]
      viewResult:@[{(1b;view x)};name;{(0b;x)}];
      if[not first viewResult;name set value]
    }'[modified;original modified];
    -1 "  -> Restored modified globals in ",string[namespace],".";
 };

.tst.cleanupSpecPollution:{[lifecycle]
    if[not lifecycle[`pollutionGuard]; :()];
    current:.tst.specPollutionNamespaces 1b;
    .tst.clearNewSpecNamespaces[lifecycle;current];
    check:(lifecycle[`namespaces]) inter current;
    if[0=count check; :()];
    originals:(lifecycle[`pollutionSnapshot]) check;
    {[title;names;values;idx]
      .tst.restoreSpecNamespace[title;names idx;values idx]
    }[lifecycle[`title];check;originals] each til count check;
 };

.tst.finalizeSpecDir:{[lifecycle]
    if[lifecycle[`acquired];.tst.restoreDir[]]
 };
.tst.finalizeSpecRuntime:{[lifecycle]
    if[lifecycle[`runContextSet];.tst.restoreRuntimeContext lifecycle[`runContext]]
 };
.tst.finalizeSpecMocks:{[lifecycle]
    if[lifecycle[`mockLifecycleSet];.tst.restoreMockLifecycle lifecycle[`mockLifecycle]]
 };
.tst.finalizeSpecExpecCleanup:{[lifecycle]
    if[lifecycle[`acquired];.tst.runCleanupTasks[]]
 };
.tst.finalizeSpecAssertState:{[lifecycle]
    if[lifecycle[`assertStateSet];.tst.assertState:lifecycle[`assertState]]
 };
.tst.finalizeSpecPollution:{[lifecycle]
    if[lifecycle[`pollutionSet];.tst.cleanupSpecPollution lifecycle]
 };
.tst.finalizeSpecHandles:{[lifecycle]
    if[not lifecycle[`handlesSet]; :()];
    leaked:(.tst.openHandles[]) except lifecycle[`handles];
    if[0=count leaked; :()];
    -1 "WARNING: Test Suite '",.tst.toString[lifecycle[`title]],
      "' leaked handles: ",.tst.toString leaked;
    {@[hclose;x;{}]} each leaked;
    -1 "  -> Closed leaked handles.";
 };
.tst.finalizeSpecTimer:{[lifecycle]
    if[not lifecycle[`timerSet]; :()];
    current:@[get;`.z.ts;{::}];
    if[current~lifecycle[`timer]; :()];
    -1 "WARNING: Test Suite '",.tst.toString[lifecycle[`title]],
      "' modified .z.ts. Restoring.";
    .z.ts:lifecycle[`timer];
 };
.tst.finalizeSpecCleanupQueue:{[lifecycle]
    if[lifecycle[`acquired];.tst.runSpecCleanupTasks[]]
 };
.tst.finalizeSpecDiagnostics:{[lifecycle]
    if[lifecycle[`diagnosticContextSet];
      .tst.currentContext:lifecycle[`diagnosticContext]];
    if[lifecycle[`runContextSet];
      .tst.restoreRuntimeContext lifecycle[`runContext]];
 };

.tst.runSpecFinalizeStep:{[phase;fn;lifecycle]
    .[{[f;state] f state;()};(fn;lifecycle);{[p;err]
      -1 "WARNING: Spec ",string[p]," cleanup failed: ",.tst.toString err;
      enlist string[p],": ",.tst.toString err
    }[phase;]]
 };

/ Single idempotent spec finalizer. Queue drains clear before execution, handle
/ closure is diff-based, and state restoration is safe to repeat.
.tst.finalizeSpec:{[lifecycle]
    phases:(`mocks`directory`runtime`expectationCleanup`assertState`pollution),
      `handles`timer`specCleanup`diagnostics;
    functions:(.tst.finalizeSpecMocks;.tst.finalizeSpecDir;
      .tst.finalizeSpecRuntime;.tst.finalizeSpecExpecCleanup;.tst.finalizeSpecAssertState;
      .tst.finalizeSpecPollution;.tst.finalizeSpecHandles;.tst.finalizeSpecTimer;
      .tst.finalizeSpecCleanupQueue;.tst.finalizeSpecDiagnostics);
    raze {[state;ps;fs;idx]
      .tst.runSpecFinalizeStep[ps idx;fs idx;state]
    }[lifecycle;phases;functions] each til count phases
 };

/ Public spec runner: one protected body followed by exactly one finalizer call.
.tst.failedSpecFromOutcome:{[spec;phase;err]
    spec[`expectations]:();
    .tst.appendSpecError[spec;phase;err]
 };

.tst.runSpec:{[spec]
    empty:.tst.emptySpecLifecycle spec;
    captured:@[{[s] (`ok;.tst.captureSpecLifecycle s)};spec;{[err] (`error;err)}];
    lifecycle:$[`ok~first captured;
      last captured;
      empty[`errorPhase`error]:(`capture;last captured)];
    if[not null lifecycle[`errorPhase];
      acquisitionError:string[lifecycle[`errorPhase]],
        " acquisition failed: ",.tst.toString lifecycle[`error];
      result:.tst.failedSpecFromOutcome[spec;`acquisition;acquisitionError];
      cleanupErrors:.tst.finalizeSpec lifecycle;
      if[count cleanupErrors;
        result:.tst.appendSpecError[result;`cleanup;"; " sv cleanupErrors]];
      :result];
    if[.tst.halt;
      if[not `result in key spec;spec[`result]:`didNotRun];
      cleanupErrors:.tst.finalizeSpec lifecycle;
      if[count cleanupErrors;
        spec:.tst.appendSpecError[spec;`cleanup;"; " sv cleanupErrors]];
      :spec];
    lifecycle[`bodyEntered]:1b;
    payload:`spec`lifecycle!(spec;lifecycle);
    outcome:@[{[p] (`ok;.tst.runSpecBody p)};payload;{[err] (`error;err)}];
    result:$[`ok~first outcome;
      last outcome;
      .tst.failedSpecFromOutcome[spec;`spec;last outcome]];
    cleanupErrors:.tst.finalizeSpec lifecycle;
    if[count cleanupErrors;
      result:.tst.appendSpecError[result;`cleanup;"; " sv cleanupErrors]];
    result
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

.tst.captureRunSandboxes:{[]
    rootNames:key `.;
    sandboxNames:rootNames where (string rootNames) like "sandbox_*";
    .tst.captureNamedLifecycle sandboxNames
 };

.tst.captureRunQExports:{[]
    exports:@[get;`.tst.qExports;{()!()}];
    if[not 99h=type exports; '"qExports state is invalid"];
    qNames:(` sv `.q,) each key exports;
    .tst.captureNamedLifecycle qNames
 };

.tst.emptyRunLifecycle:{[]
    fieldNames:`acquired`initStarted`runtimeSet`runtime`timerSet`timer,
      `handlesSet`handles`mockLifecycleSet`mockLifecycle`sandboxesSet`sandboxes,
      `qOriginalSet`qOriginal`qExportsSet`qExports,
      `diagnosticContextSet`diagnosticContext`assertStateSet`assertState,
      `haltSet`halt`callbacksSet`callbacks`errorPhase`error;
    fieldNames!(
      0b;       / acquired
      0b;       / initStarted
      0b;       / runtimeSet
      ()!();    / runtime
      0b;       / timerSet
      ::;       / timer
      0b;       / handlesSet
      `long$(); / handles
      0b;       / mockLifecycleSet
      ()!();    / mockLifecycle
      0b;       / sandboxesSet
      ()!();    / sandboxes
      0b;       / qOriginalSet
      ()!();    / qOriginal
      0b;       / qExportsSet
      ()!();    / qExports
      0b;       / diagnosticContextSet
      ()!();    / diagnosticContext
      0b;       / assertStateSet
      ();       / assertState
      0b;       / haltSet
      0b;       / halt
      0b;       / callbacksSet
      ()!();    / callbacks
      `;        / errorPhase
      ::)       / error
 };

.tst.captureRunLifecycle:{[]
    state:.tst.emptyRunLifecycle[];
    phases:`runtime`timer`qOriginal`qExports`diagnostics`assertState`halt,
      `callbacks`handles`mocks`sandboxes;
    valueKeys:`runtime`timer`qOriginal`qExports`diagnosticContext`assertState,
      `halt`callbacks`handles`mockLifecycle`sandboxes;
    flagKeys:`runtimeSet`timerSet`qOriginalSet`qExportsSet,
      `diagnosticContextSet`assertStateSet`haltSet`callbacksSet,
      `handlesSet`mockLifecycleSet`sandboxesSet;
    functions:(
      .tst.captureRuntimeContext;
      {[] @[get;`.z.ts;{::}]};
      {[] .tst.captureNamedLifecycle enlist `.tst.originalQ};
      .tst.captureRunQExports;
      {[] .tst.currentContext};
      {[] .tst.assertState};
      {[] .tst.halt};
      {[] .tst.captureNamedLifecycle enlist `.tst.callbacks.descLoaded};
      .tst.openHandles;
      .tst.captureMockLifecycle;
      .tst.captureRunSandboxes);
    .tst.captureLifecycleSteps[state;phases;valueKeys;flagKeys;functions]
 };

.tst.installQExports:{[]
    if[not 1b~@[get;`.tst.qNamespaceExports;0b]; :()];
    exports:@[get;`.tst.qExports;{()!()}];
    if[not 99h=type exports; :()];
    if[count exports;
      {(` sv `.q,x) set y}'[key exports;value exports]];
 };

.tst.prepareRunBookkeeping:{[]
    .resq.state.results:.resq.state.emptyResults[];
    .tst.app.passed:0b;
    .tst.app.runFailures:();
    .tst.app.cleanupFailures:();
    .tst.app.cleanupFailed:0b;
    .tst.app.cleanupComplete:0b;
    .tst.app.reportingFailed:0b;
    .tst.app.coverageFailed:0b;
 };

/ Reset per-run mutable state. Sets defensive defaults for any .tst.app key
/ a downstream phase reads, then captures the base directory so output paths
/ survive a test that changes CWD mid-run.
.tst.runAllPhase.initRun:{[]
    .tst.installQExports[];
    if[not `failFast in key `.tst.app; .tst.app.failFast: 0b];
    if[not `failHard in key `.tst.app; .tst.app.failHard: 0b];
    if[not `exit in key `.tst.app; .tst.app.exit: 0b];
    if[not `describeOnly in key `.tst.app; .tst.app.describeOnly: 0b];
    if[not `pollutionGuard in key `.tst.app; .tst.app.pollutionGuard: 1b];

    / Drain stale queues before resetting them. This makes an in-process rerun
    / safe without silently discarding cleanup work left by an interrupted run.
    @[.tst.runCleanupTasks;();{[e] -1 "WARNING: stale expectation cleanup failed: ",.tst.toString e}];
    @[.tst.runSpecCleanupTasks;();{[e] -1 "WARNING: stale spec cleanup failed: ",.tst.toString e}];
    .tst.cleanupTasks:();
    .tst.specCleanupTasks:();

    .tst.halt:0b;
    .tst.app.allSpecs: ();
    .tst.app.results: ();
    .tst.app.expectationsRan: 0;
    .tst.app.expectationsPassed: 0;
    .tst.app.expectationsFailed: 0;
    .tst.app.expectationsErrored: 0;
    .tst.app.discoveredFiles: ();
    .tst.app.loadedFiles: ();
    .tst.app.emptyFiles: ();
    .tst.app.executionState: `notStarted;
    .tst.app.baseDir: system "cd";
    .tst.app.passed:0b;
    .tst.app.runFailures:();
    .tst.app.cleanupFailures:();
    .tst.app.cleanupFailed:0b;
    .tst.app.cleanupComplete:0b;
    .tst.app.reportingFailed:0b;
    .tst.app.coverageFailed:0b;
    .tst.app.loadErrors:flip `file`error`type!(`symbol$();();`symbol$());

    .tst.context:`$".";
    .tst.tstPath:`;
    .tst.currentNs:`$".";
    .tst.currentContext:`file`suite`test!("";"";"");
    .tst.assertState:.tst.defaultAssertState;

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

/ Under -strict, a run where no expectation actually EXECUTED becomes a
/ failure. expectationsRan now counts only EXECUTED expectations (skips and
/ pendings no longer bump it -- see expecRan above), so an all-skip suite
/ correctly reports 0 here and fails loudly instead of green-washing. Insert
/ a synthetic row so the failure is visible in the results table and
/ propagates through computePassed.
.tst.runAllPhase.applyStrictMode:{[]
    if[not (.tst.app.strict and 0 = .tst.app.expectationsRan); :()];
    toInsert: flip `suite`description`status`message`time`failures`assertsRun!(
        enlist `STRICT_MODE_FAILURE;
        enlist `NO_TESTS_FOUND;
        enlist `error;
        enlist "Strict mode enabled but no tests were executed (skipped tests do not count under -strict).";
        enlist 0Nn;
        enlist enlist "No tests were executed (skipped tests do not count under -strict).";
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
    allResPass:   $[count r; all (.tst.normalizeResultStatus each r[; `result]) in `pass`skip`pending; 1b];
    allStatePass: $[count .resq.state.results; all .resq.state.results[`status] in `pass`skip`pending; 1b];

    .tst.app.passed: allResPass and (0 = count .tst.app.loadErrors) and allStatePass and (0 < count .resq.state.results);
    if[0 < count .tst.app.loadErrors; .tst.app.passed: 0b];
 };

/ Attempt one requested coverage artifact and return "" or an error string.
.tst.runAllPhase.coverageArtifact:{[name;generator;path]
    if[not (type generator) within 100 104h;
      :string[name]," generator not available"];
    .[{[fn;target] fn target;""};(generator;path);{[artifact;err]
      string[artifact]," generation failed: ",.tst.toString err
    }[name;]]
 };

/ Coverage report writers. Both artifacts are attempted; any requested
/ artifact failure is re-signalled after both attempts so runAll fails.
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

    covLCOV:@[get;`.tst.generateLCOV;{::}];
    covHTML:@[get;`.tst.generateHTML;{::}];
    lcovError:.tst.runAllPhase.coverageArtifact[`LCOV;covLCOV;outDirStr,"/coverage.lcov"];
    htmlError:.tst.runAllPhase.coverageArtifact[`HTML;covHTML;outDirStr,"/coverage.html"];
    errors:(lcovError;htmlError);
    errors:errors where 0<count each errors;
    if[count errors;
      .tst.app.coverageFailed:1b;
      '"; " sv errors];
 };

/ Record a primary run failure without throwing away earlier failures.
.tst.appendRunFailureResult:{[phase;err]
    if[not 98h=type .resq.state.results;
      .resq.state.results:.resq.state.emptyResults[]];
    message:string[phase]," phase failed: ",.tst.toString err;
    row:flip `suite`description`status`message`time`failures`assertsRun!(
      enlist `RUN_LIFECYCLE_ERROR;
      enlist phase;
      enlist `error;
      enlist message;
      enlist 0Nn;
      enlist enlist message;
      enlist 0i);
    .resq.state.results:.resq.state.results upsert row;
 };

.tst.recordRunFailure:{[phase;err]
    if[not `runFailures in key `.tst.app;.tst.app.runFailures:()];
    failure:`phase`error!(phase;.tst.toString err);
    .tst.app.runFailures,:enlist failure;
    .tst.appendRunFailureResult[phase;err];
    .tst.app.passed:0b;
    if[phase~`report;.tst.app.reportingFailed:1b];
    if[phase~`coverage;.tst.app.coverageFailed:1b];
    -1 "ERROR: run phase ",string[phase]," failed: ",.tst.toString err;
 };

.tst.currentRunLifecycle:{[]
    lifecycle:@[get;`.tst.app.runLifecycle;{()!()}];
    $[99h=type lifecycle;lifecycle;()!()]
 };

.tst.runLifecycleInitialized:{[]
    lifecycle:.tst.currentRunLifecycle[];
    $[0=count lifecycle;1b;1b~lifecycle[`initStarted]]
 };

.tst.finalCleanupFixtures:{[]
    if[.tst.runLifecycleInitialized[];.tst.cleanupAllFixtures[]]
 };
.tst.finalCleanupMocks:{[]
    lifecycle:.tst.currentRunLifecycle[];
    $[(count lifecycle) and lifecycle[`mockLifecycleSet];
      .tst.restoreMockLifecycle lifecycle[`mockLifecycle];
      if[0=count lifecycle;.tst.restore[]]]
 };
.tst.finalCleanupExpecQueue:{[]
    if[.tst.runLifecycleInitialized[];.tst.runCleanupTasks[]]
 };
.tst.finalCleanupHandles:{[]
    lifecycle:.tst.currentRunLifecycle[];
    if[(count lifecycle) and not lifecycle[`handlesSet]; :()];
    original:$[count lifecycle;
      lifecycle[`handles];
      @[get;`.tst.app.runHandles;{.tst.openHandles[]}]];
    leaked:(.tst.openHandles[]) except original;
    {@[hclose;x;{}]} each leaked;
 };
.tst.finalCleanupSpecQueue:{[]
    if[.tst.runLifecycleInitialized[];.tst.runSpecCleanupTasks[]]
 };
.tst.finalCleanupDirectory:{[]
    if[.tst.runLifecycleInitialized[];.tst.restoreDir[]]
 };
.tst.finalCleanupTimer:{[]
    lifecycle:.tst.currentRunLifecycle[];
    if[(count lifecycle) and not lifecycle[`timerSet]; :()];
    original:$[count lifecycle;
      lifecycle[`timer];
      @[get;`.tst.app.runTimer;{@[get;`.z.ts;{::}]}]];
    .z.ts:original;
 };
.tst.finalCleanupRuntime:{[]
    lifecycle:.tst.currentRunLifecycle[];
    if[(count lifecycle) and not lifecycle[`runtimeSet]; :()];
    runtime:$[count lifecycle;
      lifecycle[`runtime];
      @[get;`.tst.app.runRuntimeContext;{()!()}]];
    if[99h=type runtime;.tst.restoreRuntimeContext runtime];
 };
.tst.finalCleanupCallerState:{[]
    lifecycle:.tst.currentRunLifecycle[];
    if[(count lifecycle) and lifecycle[`diagnosticContextSet];
      .tst.currentContext:lifecycle[`diagnosticContext]];
    if[(count lifecycle) and lifecycle[`assertStateSet];
      .tst.assertState:lifecycle[`assertState]];
    if[(count lifecycle) and lifecycle[`haltSet];
      .tst.halt:lifecycle[`halt]];
    if[(count lifecycle) and lifecycle[`callbacksSet];
      .tst.restoreNamedLifecycle lifecycle[`callbacks]];
    if[0=count lifecycle;
      .tst.currentContext:`file`suite`test!("";"";"");
      .tst.assertState:.tst.defaultAssertState];
 };
.tst.finalCleanupQExports:{[]
    lifecycle:.tst.currentRunLifecycle[];
    if[0=count lifecycle;
      .tst.restoreOriginalQ[];
      :()];
    if[lifecycle[`qExportsSet];
      .tst.restoreOriginalQ[];
      .tst.restoreNamedLifecycle lifecycle[`qExports]];
    if[lifecycle[`qOriginalSet];
      .tst.restoreNamedLifecycle lifecycle[`qOriginal]];
 };
.tst.finalCleanupSandboxes:{[]
    rootKeys:key `.;
    sandboxKeys:rootKeys where (string rootKeys) like "sandbox_*";
    lifecycle:.tst.currentRunLifecycle[];
    if[count lifecycle;
      if[not lifecycle[`sandboxesSet]; :()];
      baseline:lifecycle[`sandboxes];
      created:sandboxKeys except baseline[`names];
      if[count created;.tst.deleteVar each created];
      .tst.restoreNamedLifecycle baseline;
      :()];
    if[count sandboxKeys;.tst.deleteVar each sandboxKeys];
 };

.tst.runFinalCleanupStep:{[phase;fn]
    .[{[cleanup] cleanup[];()};enlist fn;{[p;err]
      -1 "WARNING: ",string[p]," cleanup failed: ",.tst.toString err;
      enlist string[p],": ",.tst.toString err
    }[phase;]]
 };

/ Idempotent end-of-run cleanup. The completion guard is set before the first
/ step, making recursive or repeated calls no-ops while preserving failures.
.tst.runAllPhase.finalCleanup:{[]
    if[1b~@[get;`.tst.app.cleanupComplete;0b];
      .tst.app.executionState:`completed;
      :@[get;`.tst.app.cleanupFailures;()]];
    .tst.app.cleanupComplete:1b;
    .tst.app.executionState:`completed;
    phases:(`fixtures`mocks`expectationCleanup`handles`specCleanup`directory),
      `timer`runtime`callerState`qExports`sandboxes;
    functions:(.tst.finalCleanupFixtures;.tst.finalCleanupMocks;
      .tst.finalCleanupExpecQueue;.tst.finalCleanupHandles;
      .tst.finalCleanupSpecQueue;.tst.finalCleanupDirectory;
      .tst.finalCleanupTimer;.tst.finalCleanupRuntime;
      .tst.finalCleanupCallerState;.tst.finalCleanupQExports;
      .tst.finalCleanupSandboxes);
    failures:raze {[ps;fs;idx]
      .tst.runFinalCleanupStep[ps idx;fs idx]
    }[phases;functions] each til count phases;
    .tst.app.cleanupFailures:failures;
    .tst.app.cleanupFailed:0<count failures;
    if[.tst.app.cleanupFailed;.tst.app.passed:0b];
    failures
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

/ Execute all non-cleanup phases. The public wrapper supplies the finally path.
.tst.runAllPhase.execute:{[]
    .tst.runAllPhase.run[`loadTests;       {.tst.loadTests .tst.app.args}];
    .tst.runAllPhase.run[`filterSpecs;     .tst.runAllPhase.filterSpecs];
    .tst.runAllPhase.run[`runSpecs;        .tst.runAllPhase.runDiscoveredSpecs];
    .tst.runAllPhase.run[`loadErrors;      .tst.runAllPhase.injectLoadErrors];
    .tst.runAllPhase.run[`strictMode;      .tst.runAllPhase.applyStrictMode];
    .tst.runAllPhase.run[`resultsSummary;  .tst.runAllPhase.computePassed];
    .tst.runAllPhase.run[`coverage;        .tst.runAllPhase.generateCoverage];
 };

/ ----------------------------------------------------------------------------
/ runAll: protected acquisition and execution, unconditional cleanup, then one
/ final report over the complete result set.
/ ----------------------------------------------------------------------------
.tst.runAll:{[]
    empty:.tst.emptyRunLifecycle[];
    captured:@[{[] (`ok;.tst.captureRunLifecycle[])};();{[err] (`error;err)}];
    lifecycle:$[`ok~first captured;
      last captured;
      empty[`errorPhase`error]:(`capture;last captured)];
    .tst.app.runLifecycle:lifecycle;
    if[lifecycle[`runtimeSet];.tst.app.runRuntimeContext:lifecycle[`runtime]];
    if[lifecycle[`timerSet];.tst.app.runTimer:lifecycle[`timer]];
    if[lifecycle[`handlesSet];.tst.app.runHandles:lifecycle[`handles]];
    .tst.prepareRunBookkeeping[];
    if[lifecycle[`acquired];
      lifecycle[`initStarted]:1b;
      .tst.app.runLifecycle:lifecycle;
      outcome:@[{[]
        .tst._runAllStep:`init;
        .tst.runAllPhase.initRun[];
        .tst.runAllPhase.execute[];
        `ok};();{[err] (`failed;err)}];
      if[not outcome~`ok;
        phase:@[get;`.tst._runAllStep;{`init}];
        .tst.recordRunFailure[phase;outcome 1]]];
    if[not lifecycle[`acquired];
      acquisitionError:string[lifecycle[`errorPhase]],
        " acquisition failed: ",.tst.toString lifecycle[`error];
      .tst.recordRunFailure[`acquisition;acquisitionError]];
    .tst._runAllStep:`cleanup;
    cleanupOutcome:@[{[] .tst.runAllPhase.finalCleanup[];`ok};();{[err] (`failed;err)}];
    if[cleanupOutcome~`ok;
      {.tst.recordRunFailure[`cleanup;x]} each
        @[get;`.tst.app.cleanupFailures;{()}]];
    if[not cleanupOutcome~`ok;
      .tst.recordRunFailure[`cleanup;last cleanupOutcome]];
    .tst._runAllStep:`audit;
    auditOutcome:@[{[] .tst.printRunAudit[];`ok};();{[err] (`failed;err)}];
    if[not auditOutcome~`ok;
      .tst.recordRunFailure[`audit;last auditOutcome]];
    .tst._runAllStep:`report;
    reportOutcome:@[{[] .resq.report .resq.state.results;`ok};
      ();
      {[err] (`failed;err)}];
    if[not reportOutcome~`ok;
      .tst.recordRunFailure[`report;last reportOutcome]];
    if[count @[get;`.tst.app.runFailures;{()}];.tst.app.passed:0b];
    if[1b ~ .tst.app.exit; .tst.die `int$not .tst.app.passed];
 };
