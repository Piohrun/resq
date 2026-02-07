\d .tst

runners:()!()

/ Context tracking for better error diagnostics
.tst.currentContext: `file`suite`test!(""; ""; "");

/ Stack trace capture for debugging test failures
/ Returns execution context as a string for error diagnostics
.tst.stackTrace:{[]
    / Build context string from current test context
    ctx: "";
    if[0 < count .tst.currentContext`file; 
        ctx,: "File: ", .tst.currentContext`file, "\n"];
    if[0 < count .tst.currentContext`suite; 
        ctx,: "Suite: ", .tst.currentContext`suite, "\n"];
    if[0 < count .tst.currentContext`test; 
        ctx,: "Test: ", .tst.currentContext`test, "\n"];
    
    / Try to capture backtrace using .Q.bt if available 
    / .Q.bt returns a list of strings, not a single string
    bt: @[{raze .Q.bt[],\:"\n"}; (); {""}];
    if[(10h = type bt) and (0 < count bt); ctx,: "\nQ Backtrace:\n", bt];
    
    / Return empty if no context available
    $[0 < count ctx; "\n", ctx; ""]
 };

runners[`perf]:{[expec];
  opts: `runs`gc!10b;
  if[0<count expec`props; opts: opts, expec`props];
  runs: $[`runs in key opts; opts`runs; 100];
  res: .tst.benchmark.measure[runs; expec`code];
  expec[`perf]: res;
  expec[`result]: `pass;
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

runners[`test]:{[expec];
 args: ();
 if[100h = type func: expec`code;
    params: (), (value func) 1;
    isDefaultX: (params ~ enlist `x) and not `x in key .tst.fixtures;
    params: params where not (null params) or params ~\: (::);
    if[isDefaultX; params: `symbol$()];
    
    if[0<count params;
        missing: params where not params in key .tst.fixtures;
        if[0<count missing;
            availFix: ", " sv string key .tst.fixtures;
            err: "Fixture Injection Error:\n",
                 "  Test: ", .Q.s1[expec`desc], "\n",
                 "  Missing fixture(s): ", .Q.s1[missing], "\n",
                 "  Available fixtures: [", availFix, "]\n",
                 "  Hint: Register missing fixtures in a before{} block or .tst.registerFixture";
            'err;
        ];
        args: {[p; d] @[.tst.getFixture; p; {[p;d;e] '"Failed to inject fixture '", string[p], "' for test '", string[d], "': ", e }[p;d]] }[;expec`desc] each params;
    ];
 ];
 $[0<count args; func . args; func[]];
 if[0<count args;
   teardown: { [p;a] f: .tst.fixtures p; if[f[`scope]~`test; .tst.teardownFixture[p;a]]; };
   i:0; do[count params; teardown[params i; args i]; i+:1];
 ];
 expec[`failures]:.tst.assertState.failures;
 expec[`assertsRun]:.tst.assertState.assertsRun;
 expec[`result]: $[0<count expec`failures;`testFail;`pass];
 expec
 }

expecError:{[expec;errorType;errorText];
 expec[`result]: `$errorType,"Error";
 expec[`errorText]: (),errorText;
 expec[`failures]:.tst.assertState.failures;
 expec[`assertsRun]:.tst.assertState.assertsRun;
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
 / Set test context for stack traces (Phase 3 enhancement)
 .tst.currentContext[`test]: $[`desc in key expec; .tst.toString expec`desc; ""];
 expec:.tst.setupExpec[spec;expec];
 
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
 
 expec[`time]:.z.p - time;
 expec:.tst.teardownExpec[spec;expec];
 if[.tst.halt; .tst.stageBadExpec[spec;startExpec;beforeBad]];
 expec
 }

stageBadExpec:{[spec;expec;beforeBad]
 expec:.tst.setupExpec[spec;expec];
 if[beforeBad ~ `before;:(::)];
 if[`before in key expec; c: expec`before; if[type[c] within 100 104h; @[c; (); {}]]];
 if[beforeBad ~ `test;:(::)];
 @[.tst.callExpec;expec;{.tst.expecError[x;string x`type;y]}[expec]];
 }

setupExpec:{[spec;expec];
  expec[`result]:();
  ((` sv `.q,) each .tst.uiRuntimeNames) .tst.mock' .tst.uiRuntimeCode;
  
  / Safe context switch - if no context defined (e.g. unit tests), stay in current
  if[`context in key .tst; system "d ", string .tst.context];
  
  expec
 }

teardownExpec:{[spec;expec];
 system "d .tst";
  .tst.restore[];
  @[.tst.runCleanupTasks; (); {}];
  .tst.assertState:.tst.defaultAssertState;
 .tst.callbacks.expecRan[spec;expec];
 expec
 }
