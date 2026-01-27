\d .tst

runners:()!()

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
 expec:.tst.setupExpec[spec;expec];
 
 / Before Block
 beforeBad:`before;
 if[`before in key expec;
    c: expec`before;
    if[type[c] within 100 104h;
        expec: @[{[e;c] e[`before]:c; c[]; e}[expec;c]; (); {[e;err] .tst.expecError[e;"before";err]}[expec]];
    ];
 ];
 
 / Main Test
 beforeBad:`test;
 if[not count expec[`result];
    res: @[.tst.callExpec; expec; {[e;err] .tst.expecError[e;string e`type;err]}[expec]];
    $[99h=type res; expec:res; @[{[e;r] e[`result]:`error; e[`errorText]:r; e}; expec; res]];
 ];
 
 / After Block
 beforeBad:`after;
 if[`after in key expec;
    c: expec`after;
    if[type[c] within 100 104h;
        expec: @[{[e;c] e[`after]:c; c[]; e}[expec;c]; (); {[e;err] .tst.expecError[e;"after";err]}[expec]];
    ];
 ];
 
 expec:.tst.teardownExpec[spec;expec];
 if[.tst.halt; .tst.stageBadExpec[spec;startExpec;beforeBad]];
 expec[`time]:.z.p - time;
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
 system "d ", string .tst.context;
 expec
 }

teardownExpec:{[spec;expec];
 system "d .tst";
 .tst.restore[];
 .tst.assertState:.tst.defaultAssertState;
 .tst.callbacks.expecRan[spec;expec];
 expec
 }
