\d .tst

.tst.context:`.
runSpec:{
 oldContext: .tst.context;
 .tst.context: $[`context in key x; x[`context]; `.];
 .tst.tstPath: x[`tstPath];
 e: x[`expectations];
 if[not type[e] in (0h;98h); e:enlist e];
 e: e where not (::)~/:e;
 x[`expectations]: e;
 x:@[x;`expectations;{[s;e]if[.tst.halt;:()];runExpec[s;e]}[x] each];
 if[.tst.halt;:()];
 .tst.restoreDir[];
 .tst.context: oldContext;
 .tst.tstPath: `;
 x[`result]:$[all `pass = x[`expectations;;`result];`pass;`fail];
 x
 }
