\d .tst

runners:()!()

/ Context tracking for better error diagnostics
.tst.currentContext: `file`suite`test!(""; ""; "");

/ Stack trace capture for debugging test failures
/ Returns execution context as a string for error diagnostics
.tst.stackTrace:{[]
    / Build context string from current test context
    ctx: "";
    fileCtx: .tst.toString .tst.currentContext`file;
    suiteCtx: .tst.toString .tst.currentContext`suite;
    testCtx: .tst.toString .tst.currentContext`test;
    if[0 < count fileCtx; ctx,: "File: ", fileCtx, "\n"];
    if[0 < count suiteCtx; ctx,: "Suite: ", suiteCtx, "\n"];
    if[0 < count testCtx; ctx,: "Test: ", testCtx, "\n"];
    
    / Keep this conservative: .Q.bt can itself fail in trapped execution paths.
    bt: "";
    if[(10h = type bt) and (0 < count bt); ctx,: "\nQ Backtrace:\n", bt];
    
    / Return empty if no context available
    $[0 < count ctx; "\n", ctx; ""]
 };

.tst.perfDefaults:`runs`gc!(100;1b);

.tst.performanceEnabled:{[]
  1b~@[get;`.tst.app.runPerformance;{[e] 0b}]
 };

.tst.skipPerformance:{[expec]
  expec[`result]:`skip;
  expec[`skipReason]:"Performance tests disabled; enable with -perf.";
  expec[`failures]:();
  expec[`assertsRun]:0i;
  expec
 };

.tst.performancePropertyError:{[name;contract]
  err:"Performance property '",string[name],"' must be ",contract;
  'err
 };

.tst.validPerformanceRuns:{[runs]
  if[not type[runs] in -5 -6 -7h; :0b];
  if[null runs; :0b];
  if[runs in (0Wh;-0Wh;0Wi;-0Wi;0W;-0W); :0b];
  0<runs
 };

.tst.validPerformanceLimit:{[limit]
  / maxTime is milliseconds and maxSpace is bytes. Both accept numeric scalar
  / types, but not booleans, temporal values, null/NaN, or infinities.
  if[not type[limit] in -4 -5 -6 -7 -8 -9h; :0b];
  if[null limit; :0b];
  if[limit in (0Wh;-0Wh;0Wi;-0Wi;0W;-0W;0We;-0We;0w;-0w); :0b];
  0<=limit
 };

.tst.validatedPerformanceOptions:{[expec]
  props:$[`props in key expec;expec`props;()!()];
  if[not 99h=type props;
    err:"Performance properties must be a dictionary";
    'err
  ];
  propKeys:key props;
  if[count propKeys;
    if[not 11h=type propKeys;
      err:"Performance properties must use symbol keys";
      'err
    ];
    if[count[propKeys]<>count distinct propKeys;
      err:"Performance properties must not contain duplicate keys";
      'err
    ];
    unknown:propKeys except `runs`gc`maxTime`maxSpace;
    if[count unknown;
      .tst.performancePropertyError[first unknown;
        "one of runs, gc, maxTime, or maxSpace"]
    ]
  ];
  opts:.tst.perfDefaults,props;
  if[not .tst.validPerformanceRuns opts`runs;
    .tst.performancePropertyError[`runs;"a positive finite integer scalar"]
  ];
  if[not -1h=type opts`gc;
    .tst.performancePropertyError[`gc;"a boolean scalar"]
  ];
  if[`maxTime in key opts;
    if[not .tst.validPerformanceLimit opts`maxTime;
      .tst.performancePropertyError[`maxTime;"a finite non-negative numeric scalar (milliseconds)"]
    ]
  ];
  if[`maxSpace in key opts;
    if[not .tst.validPerformanceLimit opts`maxSpace;
      .tst.performancePropertyError[`maxSpace;"a finite non-negative numeric scalar (bytes)"]
    ]
  ];
  opts
 };

runners[`perf]:{[expec]
  if[not .tst.performanceEnabled[]; :.tst.skipPerformance expec];
  opts:.tst.validatedPerformanceOptions expec;
  runs:opts`runs;
  / Pass the gc flag through so measure can skip per-iteration .Q.gc[] when off.
  / NOTE: timings are wall-clock ms (float); maxTime asserts in CI need generous
  / headroom - a loaded runner can be 10-100x slower than a quiet local machine.
  / measureOpts evaluates a q parse tree. Pair the lambda with generic null so
  / each warmup/measurement invokes it instead of merely inspecting its value.
  body:(expec`code;::);
  res: .tst.benchmark.measureOpts[runs; body; enlist[`gc]!enlist opts`gc];
  expec[`perf]: res;
  expec[`result]: `pass;
  expec[`failures]:();
  expec[`assertsRun]:0i;
  if[`maxTime in key opts;
      avgTime: res[`time;`avg];
      if[avgTime > opts`maxTime;
          expec[`result]: `testFail;
          expec[`failures],: enlist "Performance Failure: Avg Time ",string[avgTime],"ms > Limit ",string[opts`maxTime],"ms";
      ];
  ];
  if[`maxSpace in key opts;
      avgSpace: res[`space;`avg];
      if[avgSpace > opts`maxSpace;
          expec[`result]: `testFail;
          expec[`failures],: enlist "Performance Failure: Avg Space ",string[avgSpace]," bytes > Limit ",string[opts`maxSpace]," bytes";
      ];
  ];
  expec
 }

/ Return the explicit fixture parameters for a test lambda.
/ The implicit x on an argument-free lambda is not a fixture dependency.
testFixtureParams:{[func]
 params:`symbol$();
 if[not 100h=type func; :params];
 params:(),(value func) 1;
 isDefaultX:(params~enlist `x) and not `x in key .tst.fixtures;
 params:params where not (null params) or params~\:(::);
 $[isDefaultX; `symbol$(); params]
 }

/ Fail before setup when one or more requested fixtures are unregistered.
validateTestFixtures:{[params;description]
 if[0=count params; :()];
 missing:params where not params in key .tst.fixtures;
 if[0=count missing; :()];
 availFix:", " sv string key .tst.fixtures;
 err:"Fixture Injection Error:\n",
     "  Test: ",.Q.s1[description],"\n",
     "  Missing fixture(s): ",.Q.s1[missing],"\n",
     "  Available fixtures: [",availFix,"]\n",
     "  Hint: Register missing fixtures in a before{} block or .tst.registerFixture";
 'err
 }

/ Tear down one captured test-scoped fixture. Capturing the fixture definition
/ at setup time makes teardown resilient if the test mutates the registry.
teardownInstalledFixture:{[entry]
 fixtureDef:entry`fixture;
 if[not 99h=type fixtureDef; :()];
 if[not ((fixtureDef`scope)~`test); :()];
 teardown:fixtureDef`teardown;
 if[teardown~{}; :()];
 @[teardown; entry`value; {[name;e]
   -1 "ERROR cleaning fixture '",string[name],"': ",e;
   :()
  }[entry`name;]]
 }

/ Unwind successfully-installed fixtures exactly once, in LIFO order.
teardownInstalledFixtures:{[installed]
 if[0=count installed; :()];
 .tst.teardownInstalledFixture each reverse installed;
 }

/ Install fixtures from left to right. A later setup failure first unwinds the
/ successfully-installed prefix, then re-signals with fixture/test context.
installTestFixtures:{[params;description]
 installed:();
 i:0;
 while[i<count params;
   name:params i;
   fixtureDef:.tst.fixtures name;
   got:@[{[n] (`ok;.tst.getFixture n)}; name; {[n;d;e]
     (`error;"Failed to inject fixture '",string[n],"' for test '",string[d],"': ",e)
    }[name;description;]];
   if[`error~first got;
     .tst.teardownInstalledFixtures installed;
     'last got
    ];
   installed,:enlist `name`value`fixture!(name;last got;fixtureDef);
   i+:1;
  ];
 installed
 }

/ Execute the body and extract assertion results as one protected region.
/ The caller owns fixture teardown whether any statement here throws.
finishFixtureTest:{[state]
 args:{x`value} each state`installed;
 func:state`func;
 $[count args; func . args; func[]];
 expec:state`expec;
 expec[`failures]:.tst.assertState.failures;
 expec[`assertsRun]:.tst.assertState.assertsRun;
 expec[`result]:$[count expec`failures;`testFail;`pass];
 (`ok;expec)
 }

runners[`test]:{[expec]
 func:expec`code;
 params:.tst.testFixtureParams func;
 .tst.validateTestFixtures[params;expec`desc];
 installed:.tst.installTestFixtures[params;expec`desc];
 state:`func`expec`installed!(func;expec;installed);
 outcome:@[.tst.finishFixtureTest; state; {[e] (`error;e)}];
 .tst.teardownInstalledFixtures installed;
 if[`error~first outcome; 'last outcome];
 last outcome
 }

expecError:{[expec;errorType;errorText];
 assertState:@[get; `.tst.assertState; .tst.defaultAssertState];
 if[not 99h=type assertState; assertState:.tst.defaultAssertState];
 assertState:.tst.defaultAssertState,assertState;
 expec[`result]: `$errorType,"Error";
 expec[`errorText]: (),errorText;
 expec[`failures]:assertState`failures;
 expec[`assertsRun]:assertState`assertsRun;
 expec
 }

callExpec:{[expec];
 $[expec[`type] in  key .tst.runners;
 .tst.runners[expec`type] expec;
 '`badExpecType]
 }

runExpec:{[spec;expec];
 time:.z.p;
 startExpec:expec;
 / Record the current test name for stack-trace context.
 .tst.currentContext[`test]: $[`desc in key expec; .tst.toString expec`desc; ""];
 expec:.tst.setupExpec[spec;expec];

 / Performance expectations are opt-in. Select the skip state before entering
 / runExpecAttempt so neither hooks nor the benchmark body can execute.
 if[`type in key expec;
   if[`perf~expec`type;
     if[not .tst.performanceEnabled[]; expec:.tst.skipPerformance expec]
   ]
 ];

 / Skip and pending expectations are terminal states. Do not run hooks or code.
 exStatus: .tst.normalizeResultStatus expec`result;
 if[exStatus in `skip`pending;
    expec[`result]: exStatus;
    expec[`failures]: ();
    expec[`assertsRun]: 0i;
    expec[`time]: .z.p - time;
    expec:.tst.teardownExpec[spec;expec];
    :expec
 ];
 
 / Retry support: an expectation with `retries:n` (n>0) gets up to n+1 total
 / attempts. Each attempt re-runs the full before+test+after cycle (so flaky
 / state is reset). The FIRST attempt whose result normalizes to `pass wins.
 / Only the FINAL attempt is recorded (teardownExpec fires exactly once, below).
 / retries=0 (every normal test) collapses to a single pass through the loop.
 maxAttempts: 1 + $[`retries in key expec; 0 | `long$expec`retries; 0];
 / Pristine snapshot of the post-setup expec. q dicts are values, so this copies
 / semantically; restoring `expec:pristine` between attempts also resets the
 / accumulated result/failures/errorText/assertsRun and leaves before/after/code
 / keys untouched.
 pristine: expec;
 attempt: 0;
 / `do`-style loop via while; `attempt`-guarded break on pass or halt.
 done: 0b;
 while[(attempt < maxAttempts) and not done;
   attempt+: 1;
   res: .tst.runExpecAttempt[spec; expec];
   expec: res`expec;
   beforeBad: res`beforeBad;
   passed: `pass ~ .tst.normalizeResultStatus expec`result;
   / Stop if passed, if halt fired, or if no attempts remain.
   done: passed or .tst.halt or (attempt >= maxAttempts);
   / Between attempts: replicate teardownExpec's per-attempt cleanup, then
   / restore the pristine post-setup expec so the flaky test starts clean.
   if[not done;
      .tst.restore[];
      @[.tst.runCleanupTasks; (); {}];
      .tst.assertState: .tst.defaultAssertState;
      expec: pristine;
   ];
 ];

 / Annotate retry outcomes so flake debt is visible, not hidden.
 if[maxAttempts > 1;
    descStr: .tst.toString expec`desc;
    $[`pass ~ .tst.normalizeResultStatus expec`result;
      if[attempt > 1;
         note: "passed on attempt ", string[attempt], " of ", string maxAttempts;
         expec[`retryNote]: note;
         -1 "NOTE: '", descStr, "' ", note, ".";
      ];
      / Failed every attempt: surface the attempt count on the failures list.
      expec[`failures]: (enlist "failed after ", string[maxAttempts], " attempts"), (),expec`failures
    ];
 ];

 expec[`time]:.z.p - time;
 expec:.tst.teardownExpec[spec;expec];
 if[.tst.halt; .tst.stageBadExpec[spec;startExpec;beforeBad]];
 expec
 }

/ One retry attempt: the full before-block + main-test + after-block cycle.
/ Returns `expec`beforeBad!(attemptedExpec; lastStageSym). Does NOT teardown or
/ record - the caller (runExpec) owns the single teardownExpec / expecRan call.
runExpecAttempt:{[spec;expec];
 / Before Block
 beforeBad:`before;
 if[`before in key expec;
    c: expec`before;
    if[type[c] within 100 104h;
        expec: @[{[e;c] e[`before]:c; c[]; e}[expec;c]; (); {[e;err]
            st: .tst.stackTrace[];
            .tst.expecError[e;"before"; err, st]
        }[expec]];
    ];
 ];

  / Main Test
  beforeBad:`test;
  if[not count expec[`result];
     timeout: first .tst.app.maxTestTime;
     testStart: .z.p;
     / Execute test with error trapping (no session-killing \T command)
     res: @[.tst.callExpec; expec; {[e;err]
         st: .tst.stackTrace[];
         .tst.expecError[e; string e`type; err, st]
     }[expec]];
     / Post-execution timeout check (safe - doesn't kill session)
     if[timeout > 0;
         elapsedSec: `long$(.z.p - testStart) % 1000000000;
         if[elapsedSec > timeout;
             / Mark as timeout failure but continue running
             res: .tst.expecError[expec; "timeout";
                 "Test exceeded timeout of ", string[timeout], "s (took ", string[elapsedSec], "s)"];
         ];
     ];
     $[99h=type res; expec:res; @[{[e;r] e[`result]:`error; e[`errorText]:r; e}; expec; res]];
  ];

 / After Block
 beforeBad:`after;
 if[`after in key expec;
    c: expec`after;
    if[type[c] within 100 104h;
        expec: @[{[e;c] e[`after]:c; c[]; e}[expec;c]; (); {[e;err]
            st: .tst.stackTrace[];
            .tst.expecError[e;"after"; err, st]
        }[expec]];
    ];
 ];

 `expec`beforeBad!(expec; beforeBad)
 }

stageBadExpec:{[spec;expec;beforeBad]
 expec:.tst.setupExpec[spec;expec];
 if[beforeBad ~ `before;:(::)];
 if[`before in key expec; c: expec`before; if[type[c] within 100 104h; @[c; (); {}]]];
 if[beforeBad ~ `test;:(::)];
 @[.tst.callExpec;expec;{.tst.expecError[x;string x`type;y]}[expec]];
 }

setupExpec:{[spec;expec];
  if[not `result in key expec; expec[`result]:()];
  if[expec[`result] ~ `didNotRun; expec[`result]:()];
  if[not `runtimeContext in key expec; expec[`runtimeContext]: .tst.captureRuntimeContext[]];
  / Mirror fixture/fixtureAs/mock into .q so unqualified names resolve via the
  / .q fallback inside sandbox namespaces. Gated by qNamespaceExports (default
  / on); when off, tests must use the fully-qualified .tst.mock etc.
  if[1b ~ @[get; `.tst.qNamespaceExports; 1b];
    ((` sv `.q,) each .tst.uiRuntimeNames) .tst.mock' .tst.uiRuntimeCode];
  
  / Safe context switch - if no context defined (e.g. unit tests), stay in current
  if[`context in key .tst; system "d ", string .tst.context];
  
  expec
 }

teardownExpec:{[spec;expec];
 ctx: $[`runtimeContext in key expec; expec`runtimeContext; ()!()];
 system "d .tst";
  .tst.restore[];
  @[.tst.runCleanupTasks; (); {}];
  .tst.assertState:.tst.defaultAssertState;
 .tst.callbacks.expecRan[spec;expec];
 if[99h = type ctx; .tst.restoreRuntimeContext ctx];
 expec
 }
