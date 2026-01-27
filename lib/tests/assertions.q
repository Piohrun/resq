\d .tst

asserts:()!()
asserts[`must]:{[val;message];
  .tst.assertState.assertsRun+:1;
  if[not all val;
    m: $[10h = abs type message; message; .Q.s1 message];
    .tst.assertState.failures,: enlist m];
  }

asserts[`musteq]:{[l;r]; 
   if[l=r; :.tst.assertState.assertsRun+:1];
   m: "Expected ", (-3!l), " to match ", (-3!r);
   -1 "";
   -1 "FAILURE DIFF ---------------------------------------------------";
   -1 .tst.diff[r;l];
   -1 "----------------------------------------------------------------";
   .tst.asserts[`must][0b; m];
  }
asserts[`mustmatch]:{[l;r]; asserts.must[l~r;"Expected ", (-3!l), " to match ", (-3!r)]}
asserts[`mustmatchs]:{[l;r]; .tst.mustmatchSnap[l;r]}
asserts[`mustmatchst]:{[l;r]; .tst.mustmatchTxtSnap[l;r]}
asserts[`mustnmatch]:{[l;r]; .tst.asserts[`must][not l~r;"Expected ", (-3!l), " to not match ", (-3!r)]}
asserts[`mustne]:{[l;r]; .tst.asserts[`must][l<>r;"Expected ", (-3!l), " to not be equal to ", (-3!r)]}
asserts[`mustlt]:{[l;r]; .tst.asserts[`must][l<r;"Expected ", (-3!l), " to be less than ", (-3!r)]}
asserts[`mustgt]:{[l;r]; .tst.asserts[`must][l>r;"Expected ", (-3!l), " to be greater than ", (-3!r)]}
asserts[`mustlike]:{[l;r]; .tst.asserts[`must][l like r;"Expected ", (-3!l), " to be like ", (-3!r)]}
asserts[`mustin]:{[l;r]; .tst.asserts[`must][l in r;"Expected ", (-3!l), " to be in ", (-3!r)]}
asserts[`mustnin]:{[l;r]; .tst.asserts[`must][not l in r;"Expected ", (-3!l), " to not be in ", (-3!r)]}
asserts[`mustwithin]:{[l;r]; .tst.asserts[`must][l within r;"Expected ", (-3!l), " to be within ", (-3!r)]}
asserts[`mustdelta]:{[tol;l;r]; .tst.asserts[`must][l within (r - abs tol;r + abs tol);"Expected ", (-3!l), " to be within +/-", (-3!tol), " of ", (-3!r)]}

asserts[`mustthrow]:{[e;c];
  execCode:{[code]
    t:type code;
    if[t in 100 104h; :code[]];
    if[0h = t;
      if[0 = count code; :()];
      f:first code;
      args: 1 _ code;
      fval: $[-11h = type f; value f; f];
      if[(type fval) in 100 104h; :fval . args];
      :value code
    ];
    value code
  };
  / Use sentinel value to detect errors vs normal return
  r:@[execCode;c;{(`err0x;x)}];
  isErr: (2 = count r) and (first r) ~ `err0x;
  errMsg: $[isErr; last r; ""];
  / Ensure errMsg is string for concatenation
  errStr: $[10h = type errMsg; errMsg; -3!errMsg];
  p:1b;
  m:"Expected '", (-3!c), "' to throw ";

  / Normalize patterns to list of strings
  pats: $[0=count (),e; (); 10h=abs type e; enlist e; (),e];

  m,: $[0=count pats; "an error.";
        1=count pats; "the error '",(first pats),"'.";
        "one of the errors ", ("," sv { "'",x,"'" } each pats), "."];

  if[not isErr; m,:" No error thrown"; p:0b];
  if[isErr and (0 < count pats) and not any (), errStr like/: pats; m,: " Error thrown: '",errStr,"'";p:0b];
  .tst.asserts[`must][p;m]
  }

asserts[`mustnotthrow]:{[e;c];
  execCode:{[code]
    t:type code;
    if[t in 100 104h; :code[]];
    if[0h = t;
      if[0 = count code; :()];
      f:first code;
      args: 1 _ code;
      fval: $[-11h = type f; value f; f];
      if[(type fval) in 100 104h; :fval . args];
      :value code
    ];
    value code
  };
  / Use sentinel value to detect errors vs normal return
  r:@[execCode;c;{(`err0x;x)}];
  isErr: (2 = count r) and (first r) ~ `err0x;
  errMsg: $[isErr; last r; ""];
  / Ensure errMsg is string for concatenation
  errStr: $[10h = type errMsg; errMsg; -3!errMsg];
  m:"Expected '", (-3!c), "' to not throw ";

  / Normalize patterns to list of strings
  pats: $[0=count (),e; (); 10h=abs type e; enlist e; (),e];

  p:1b;
  if[isErr and not 0 < count pats; m,:"an error. Error thrown: '",errStr,"'";p:0b];
  if[isErr and (0 < count pats) and any (), errStr like/: pats; m,: "the error '",errStr,"'";p:0b];
  .tst.asserts[`must][p;m]
  }

asserts[`mustmatchignoringorder]:{[l;r];
  norm:{[x]
    if[98h=type x; t:0!x; :(cols t) xasc t];
    if[99h=type x; t:0!x; :(cols t) xasc t];
    if[(t:type x) within 0 19h; :asc x];
    x
  };
  l1: norm l;
  r1: norm r;
  m: "Expected value (ignoring order) match failed.";
  if[not l1~r1;
    if[all 2 = count each distinct type each (l1;r1);
      -1 "FAILURE DIFF (Ignoring Order) ------------------------------------";
      $[100h < type .tst.diff; -1 .tst.diff[r1;l1]; -1 "Diff not available"];
      -1 "----------------------------------------------------------------";
    ];
  ];
  .tst.asserts[`must][l1~r1; m]
 }

asserts[`mustincludecols]:{[l;r];
  if[not 98h=type l; '`mustIncludeColsApplicableOnlyToTables];
  if[not 98h=type r; '`mustIncludeColsExpectsTableAsRightArg];
  cl: cols l; cr: cols r;
  missing: cr except cl;
  if[0<count missing;
    .tst.asserts[`must][0b; "Missing columns in target: ", ", " sv string missing];
    :();
  ];
  lSub: cr # l;
  m: "Columns match failed.";
  if[not lSub~r;
    -1 "FAILURE DIFF (Included Columns) ------------------------------------";
    $[100h < type .tst.diff; -1 .tst.diff[r;lSub]; -1 "Diff not available"];
    -1 "----------------------------------------------------------------";
  ];
  .tst.asserts[`must][lSub~r; m]
 }

asserts[`mustBeFasterThan]:{[code;limitMs]
  if[not type[code] in 100 104h; '`type];
  res: .tst.benchmark.measure[20; code];
  avgTime: res[`time;`avg];
  .tst.asserts[`must][avgTime <= limitMs; "Execution time ",string[avgTime],"ms > Limit ",string[limitMs],"ms"];
 };

asserts[`mustAllocLessThan]:{[code;limitBytes]
  if[not type[code] in 100 104h; '`type];
  res: .tst.benchmark.measure[20; code];
  avgSpace: res[`space;`avg];
  .tst.asserts[`must][avgSpace <= limitBytes; "Allocation ",string[avgSpace]," bytes > Limit ",string[limitBytes]," bytes"];
 };

asserts[`mustHaveBeenCalledWith]:{[name;args]
  if[not name in key .tst.spyLog.calls;
    .tst.asserts[`must][0b; "Function ", (.tst.toString name), " is not spied on."];
    :();
  ];
  calls: .tst.spyLog.calls[name];
  / Use ~ match for complex args comparison
  found: any { x ~ y }[args] each calls;
  msg: "Expected ", (.tst.toString name), " to have been called with ", (-3!args);
  if[not found; msg,: ". Actual calls: ", $[0 = count calls; "(none)"; -3!calls]];
  .tst.asserts[`must][found; msg];
 };

\d .
must: .tst.asserts[`must];
musteq: .tst.asserts[`musteq];
mustmatch: .tst.asserts[`mustmatch];
mustmatchs: .tst.asserts[`mustmatchs];
mustmatchst: .tst.asserts[`mustmatchst];
mustnmatch: .tst.asserts[`mustnmatch];
mustne: .tst.asserts[`mustne];
mustlt: .tst.asserts[`mustlt];
mustgt: .tst.asserts[`mustgt];
mustlike: .tst.asserts[`mustlike];
mustin: .tst.asserts[`mustin];
mustnin: .tst.asserts[`mustnin];
mustwithin: .tst.asserts[`mustwithin];
mustdelta: .tst.asserts[`mustdelta];
mustthrow: .tst.asserts[`mustthrow];
mustnotthrow: .tst.asserts[`mustnotthrow];
mustmatchignoringorder: .tst.asserts[`mustmatchignoringorder];
mustincludecols: .tst.asserts[`mustincludecols];
mustBeFasterThan: .tst.asserts[`mustBeFasterThan];
mustAllocLessThan: .tst.asserts[`mustAllocLessThan];
mustHaveBeenCalledWith: .tst.asserts[`mustHaveBeenCalledWith];

.tst.mustmatchs: .tst.asserts[`mustmatchs];
.tst.mustmatchst: .tst.asserts[`mustmatchst];
