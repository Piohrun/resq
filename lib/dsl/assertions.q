/ assertions.q - core assertion DSL (musteq, mustthrow, snapshots, aliases)
\d .tst

/ Name the active expectation on streamed diffs. The summary may appear much
/ later, so an anonymous block is not actionable in a multi-failure CI log.
.tst.diffContextLabel:{[]
    ctx: @[get; `.tst.currentContext; {()!()}];
    if[not 99h = type ctx; :""];
    suiteName: $[`suite in key ctx; .tst.toString ctx`suite; ""];
    testName: $[`test in key ctx; .tst.toString ctx`test; ""];
    $[(count suiteName) and count testName; suiteName, " :: ", testName;
      count testName; testName;
      suiteName]
 };

/ Marker that separates an assertion's one-line summary from its structural diff
/ inside a single recorded failure string. The console listing cuts here (the
/ diff already streamed live, labelled with suite :: test); JSON, JUnit and xUnit
/ keep the whole thing, so a machine report is no longer strictly poorer than the
/ terminal a human happened to be watching.
diffDetailMarker: "\n--- diff ---\n";

/ Render the expected-vs-actual diff as ONE char vector. `.tst.diff` may return a
/ LIST of lines, which `-1` prints happily but which would turn the failure
/ message into a mixed list -- and then `ss` on it signals 'type. Returns "" when
/ it cannot be rendered: a diff problem must never mask the assertion failure.
renderDiffText:{[expected;actual]
    @[{ text: .tst.diff[x 0; x 1];
        $[10h = abs type text; text;
          0h = type text; "\n" sv {$[10h = abs type y; y; .tst.toString y]}[::;] each text;
          .tst.toString text] };
      (expected;actual);
      {[err] ""}]
 };

/ Print a already-rendered diff under a labelled banner.
printDiffText:{[text]
    if[0 = count text; :()];
    label: .tst.diffContextLabel[];
    -1 "";
    -1 "FAILURE DIFF", $[count label; " [", label, "] "; " "],
        "---------------------------------------------------";
    -1 text;
    -1 "----------------------------------------------------------------";
 };

/ Print expected-vs-actual diff; rendering problems must never mask the assertion failure itself.
printDiffSafe:{[expected;actual]
    .tst.printDiffText .tst.renderDiffText[expected;actual]
 };

/ Append "(assertion #N in this test)" to the SUMMARY line, not to the end of a
/ message that already carries a diff section -- the locator belongs beside the
/ claim it locates, and the diff must stay the last thing in the string so a
/ reader (and the console listing's cut) can rely on the marker.
withOrdinalSuffix:{[m]
    suffix: .tst.assertionOrdinalSuffix[];
    if[0 = count suffix; :m];
    at: ss[m; .tst.diffDetailMarker];
    / NOT named `cut`: that is a q keyword, and assigning to it fails the load.
    $[count at;
        [ splitAt: first at; (splitAt # m), suffix, splitAt _ m ];
        m, suffix]
 };

asserts:()!()

/ Assertion diagnostics are deferred so a successful comparison never renders
/ (or copies) its operands. This matters for the exact workloads resQ is meant
/ to test: million-element vectors and large tables should be cheap when green.
.tst.assertValueText:{[val]
  limit: $[`reportLimit in key `.tst.output; .tst.output.reportLimit; 50000];
  .tst.renderValueBounded[val;`long$limit % 2]
 };

.tst.deferAssertionMessage:{[fn;args]
  `resqDeferredMessage`resqDeferredArgs!(fn;args)
 };

.tst.renderAssertionMessage:{[message]
  if[99h = type message;
    if[`resqDeferredMessage in key message;
      fn: message`resqDeferredMessage;
      if[type[fn] in 100 104h;
        args: $[`resqDeferredArgs in key message; message`resqDeferredArgs; ()];
        outcome: @[{[pair] (0b;.[pair 0;pair 1])};(fn;args);{[err](1b;err)}];
        :$[first outcome;
            "Assertion failed; diagnostic rendering failed: ", .tst.toString last outcome;
            last outcome];
      ];
    ];
  ];
  message
 };
/ Accepted conditions: a boolean, or a number (q's own truthiness, as `if` and
/ qspec both use -- `must[count x; "non-empty"]` is a legitimate idiom and stays
/ source-compatible with qspec). A NULL number is rejected: it is the result of
/ a computation that did not produce an answer, not a truth value. So is a
/ string, symbol or anything else, because `all` maps those to true and the
/ usual cause is a swapped `must["message"; cond]`.
/ A test library may report a false failure; it must never report a false pass.
/ An empty boolean vector still passes: "all of zero items hold" is the intended
/ reading where a test checks every element of a possibly-empty set.
.tst.mustConditionKind:{[val]
    t: abs type val;
    $[1h = t;                 `boolean;
      t in 4 5 6 7 8 9h;      $[any null val; `null; `numeric];
      `unusable]
 };

asserts[`must]:{[val;message];
  .tst.assertState.assertsRun+:1;
  kind: .tst.mustConditionKind val;
  $[kind = `unusable;
      [ lim: $[`reportLimit in key `.tst.output; .tst.output.reportLimit; 50000];
        .tst.assertState.failures,: enlist
          "must expects a boolean or numeric condition, got type ",
          (string type val), "h: ", .tst.truncate[val; `long$lim % 2] ];
    kind = `null;
      .tst.assertState.failures,: enlist
        "must condition is null, which is not a truth value: ", .tst.toString val;
    not all $[kind = `numeric; 0 <> val; val];
      [ renderedMessage: .tst.renderAssertionMessage message;
        m: $[10h = abs type renderedMessage; renderedMessage;.tst.renderValueFull renderedMessage];
        / Which assertion in this test failed. assertState resets per
        / expectation, so assertsRun is this assertion's ordinal. q gives no
        / file/line for a failing assertion (nothing throws, and definitions
        / evaluated via `value` carry no source position), so the ordinal is the
        / locator available: in a test with several assertions it says which one.
        .tst.assertState.failures,: enlist .tst.withOrdinalSuffix m ];
    (::)];
  }

/ Rendered only past the first assertion: "(assertion #1)" on a single-assertion
/ test is noise, and goldens pin those messages exactly.
.tst.assertionOrdinalSuffix:{[]
  n: .tst.assertState.assertsRun;
  $[n > 1; " (assertion #", string[n], " in this test)"; ""]
 };

/ True when qspec's `=` comparison would have accepted this pair but `~` did
/ not: a scalar broadcast across a vector (`1 1 1 musteq 1`) or a type-loose
/ numeric match (`1 musteq 1.0`). Trapped, because `=` signals on tables and on
/ length-mismatched operands, which are exactly the cases `~` handles better.
.tst.qspecEqWouldPass:{[l;r] 1b ~ @[{[a;b] all a = b}[l;]; r; {[e] 0b}] };

asserts[`musteq]:{[l;r];
    if[l ~ r; :.tst.assertState.assertsRun+:1];
    / qspec's musteq is `=`, resQ's is `~`. Under -qspec-compat accept anything
    / qspec would have, so an unported suite runs unchanged; otherwise fail as
    / usual but say so in the message, since this is the single most common
    / reason a working qspec suite goes red on resQ.
    qspecWouldPass: .tst.qspecEqWouldPass[l; r];
    if[qspecWouldPass;
        if[1b ~ @[get; `.tst.app.qspecCompat; 0b];
            :.tst.assertState.assertsRun+:1]];
    / Use truncation for large values to prevent memory issues
    limit: $[`reportLimit in key `.tst.output; .tst.output.reportLimit; 50000];
    lStr: .tst.truncate[l; `long$limit % 2];
    rStr: .tst.truncate[r; `long$limit % 2];
    m: "Got ", lStr, " — expected ", rStr;
    if[not (type l) = type r; m,: " (Type mismatch: ", string[type l], " vs ", string[type r], ")"];
    / Show numeric diff for numbers
    if[(type l) within (-9h;-6h); if[(type r) within (-9h;-6h);
        m,: " (diff: ", string[l - r], ")"
    ]];
    / Show length diff for lists
    if[(type l) >= 0h; if[(type r) >= 0h;
        if[not (count l) = count r;
            m,: " (length: ", string[count l], " vs ", string[count r], ")"
        ]
    ]];
   / Self-guiding migration hint: name the exact reason and the switch.
   if[qspecWouldPass;
       m,: " [qspec compatibility: qspec's musteq used `=`, which would have"
            , " accepted this (scalar broadcast or loose numeric type)."
            , " resQ uses `~`. Run with -qspec-compat, or compare like-for-like"
            , " -- see docs/MIGRATION.md]"];
   / Render the diff ONCE, then use it twice: streamed to the console at failure
   / time, and appended to the recorded failure so it survives into the machine
   / reports. Under -pass nothing is reported at all, so skip the work entirely.
   if[not .tst.suppressAssertionDiff;
       diffText: .tst.renderDiffText[r;l];
       .tst.printDiffText diffText;
       if[count diffText; m,: .tst.diffDetailMarker, diffText]];
   .tst.asserts[`must][0b; m];
  }
/ mustmatch shares musteq's ~-equality semantics; route it through the same body
/ so a mismatch renders the rich FAILURE DIFF instead of a bare -3! message.
asserts[`mustmatch]:{[l;r]; .tst.asserts[`musteq][l;r]}
asserts[`mustmatchs]:{[l;r]; .tst.mustmatchSnap[l;r]}
asserts[`mustmatchst]:{[l;r]; .tst.mustmatchTxtSnap[l;r]}
asserts[`mustnmatch]:{[l;r]; .tst.asserts[`must][not l~r;
  .tst.deferAssertionMessage[{[a;b] "Got ",.tst.assertValueText[a],
    " — expected it NOT to match ",.tst.assertValueText[b]};(l;r)]]}
/ mustne is the exact inverse of musteq, so it must use `~` (whole-value match),
/ not `<>` (elementwise). With `<>` any non-atom yielded a boolean VECTOR rather
/ than an atom: `must` then applied `all`, so mustne silently meant "every
/ element differs" — 1 2 3 vs 9 2 3 reported a failure despite differing — and
/ tables/ragged pairs crashed with 'type / 'length.
/ qspec's mustne is `<>` ("every element differs"); resQ's is the exact inverse
/ of musteq. -qspec-compat restores the original semantics for unported suites.
asserts[`mustne]:{[l;r];
  cond: $[1b ~ @[get; `.tst.app.qspecCompat; 0b]; l <> r; not l ~ r];
  .tst.asserts[`must][cond; .tst.deferAssertionMessage[{[a;b]
    "Got ",.tst.assertValueText[a]," — expected it NOT to equal ",.tst.assertValueText[b]};(l;r)]]}

/ Evaluate a comparison under a functional trap. Invalid assertion operands
/ remain test errors (never ordinary mismatches), but the signal names the user
/ verb and q operand types instead of leaking a bare primitive `type/`length.
.tst.assertTypedComparison:{[name;fn;args;message]
  outcome:@[{[pair](0b;.[pair 0;pair 1])};(fn;args);{[err](1b;err)}];
  if[first outcome;
    .tst.assertState.assertsRun+:1;
    typeText:("h and " sv string type each args),"h";
    '"Assertion ",name," cannot compare operand types ",typeText,
      " (",.tst.toString[last outcome],")"];
  .tst.asserts[`must][last outcome;message]
 };

asserts[`mustlt]:{[l;r]; .tst.assertTypedComparison["mustlt";{[a;b]a<b};(l;r);
  .tst.deferAssertionMessage[{[a;b]
    "Got ",.tst.assertValueText[a]," — expected it to be less than ",.tst.assertValueText[b]};(l;r)]]}
asserts[`mustgt]:{[l;r]; .tst.assertTypedComparison["mustgt";{[a;b]a>b};(l;r);
  .tst.deferAssertionMessage[{[a;b]
    "Got ",.tst.assertValueText[a]," — expected it to be greater than ",.tst.assertValueText[b]};(l;r)]]}
asserts[`mustlike]:{[l;r]; .tst.asserts[`must][l like r; .tst.deferAssertionMessage[{[a;b]
  "Expected ",.tst.assertValueText[a]," to be like ",.tst.assertValueText[b]};(l;r)]]}
asserts[`mustin]:{[l;r]; .tst.assertTypedComparison["mustin";{[a;b]a in b};(l;r);
  .tst.deferAssertionMessage[{[a;b]
  "Expected ",.tst.assertValueText[a]," to be in ",.tst.assertValueText[b]};(l;r)]]}
asserts[`mustnin]:{[l;r]; .tst.assertTypedComparison["mustnin";{[a;b]not a in b};(l;r);
  .tst.deferAssertionMessage[{[a;b]
  "Expected ",.tst.assertValueText[a]," to not be in ",.tst.assertValueText[b]};(l;r)]]}
asserts[`mustwithin]:{[l;r]; .tst.assertTypedComparison["mustwithin";{[a;b]a within b};(l;r);
  .tst.deferAssertionMessage[{[a;b]
  "Expected ",.tst.assertValueText[a]," to be within ",.tst.assertValueText[b]};(l;r)]]}
asserts[`mustdelta]:{[tol;l;r]; .tst.assertTypedComparison["mustdelta";
  {[t;a;b]a within (b - abs t;b + abs t)};(tol;l;r);
  .tst.deferAssertionMessage[{[t;a;b] "Expected ",.tst.assertValueText[a],
    " to be within +/-",.tst.assertValueText[t]," of ",.tst.assertValueText[b]};(tol;l;r)]]}

/ Execute the code forms accepted by mustthrow/mustnotthrow. Kept outside the
/ assertions so both use exactly the same dispatch semantics.
.tst.executeAssertionCode:{[code]
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

/ Return (didThrow; payload). The success tag is added OUTSIDE the user result,
/ so no ordinary return value can collide with the error representation.
.tst.captureAssertionCode:{[code]
  @[{[c] (0b; .tst.executeAssertionCode c)}; code; {[err] (1b; err)}]
 };

asserts[`mustthrow]:{[e;c];
  / Arg-shape guard: convention is mustthrow[pattern; code]. If the FIRST arg is
  / a function and the SECOND is not, the caller swapped them (typically by
  / writing it infix). Signal a clear message instead of crashing with 'type.
  if[((type e) within 100 104h) and not (type c) within 100 104h;
    '"mustthrow expects [pattern; code] — got code first; did you call it infix? Use mustthrow[pattern; {code}]"];
  r:.tst.captureAssertionCode c;
  isErr: 1b ~ first r;
  errMsg: $[isErr; last r; ""];
  / Ensure errMsg is string for concatenation
  errStr: $[10h = type errMsg; errMsg;.tst.renderValueFull errMsg];
  p:1b;
  m:"Expected '",.tst.assertValueText[c], "' to throw ";

  / Normalize patterns to a list of STRING patterns. A pattern may be a string,
  / a SYMBOL (stringified so `like` works), a symbol vector, or a list of
  / strings. `like` cannot match a string against a symbol, so symbols must be
  / coerced here -- otherwise a symbol pattern crashes with 'type.
  pats: $[0=count (),e;     ();
          10h=type e;        enlist e;          / single string
          -11h=type e;       enlist string e;   / single symbol
          11h=type e;        string e;          / symbol vector
          (),e];                                / list of strings

  m,: $[0=count pats; "an error.";
        1=count pats; "the error '",(first pats),"'.";
        "one of the errors ", ("," sv { "'",x,"'" } each pats), "."];

  if[not isErr; m,:" No error thrown"; p:0b];
  if[isErr and (0 < count pats) and not any (), errStr like/: pats; m,: " Error thrown: '",errStr,"'";p:0b];
  .tst.asserts[`must][p;m]
  }

asserts[`mustnotthrow]:{[e;c];
  / Arg-shape guard: convention is mustnotthrow[pattern; code]. See mustthrow.
  if[((type e) within 100 104h) and not (type c) within 100 104h;
    '"mustnotthrow expects [pattern; code] — got code first; did you call it infix? Use mustnotthrow[pattern; {code}]"];
  r:.tst.captureAssertionCode c;
  isErr: 1b ~ first r;
  errMsg: $[isErr; last r; ""];
  / Ensure errMsg is string for concatenation
  errStr: $[10h = type errMsg; errMsg;.tst.renderValueFull errMsg];
  m:"Expected '",.tst.assertValueText[c], "' to not throw ";

  / Normalize patterns to a list of STRING patterns (see mustthrow: symbols are
  / stringified so `like` matches against the string error message).
  pats: $[0=count (),e;     ();
          10h=type e;        enlist e;          / single string
          -11h=type e;       enlist string e;   / single symbol
          11h=type e;        string e;          / symbol vector
          (),e];

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
    if[(not .tst.suppressAssertionDiff) and all 2 = count each distinct type each (l1;r1);
      -1 "FAILURE DIFF (Ignoring Order) ------------------------------------";
      $[100h < type .tst.diff; @[{ -1 .tst.diff[x 0; x 1] }; (r1;l1); {[err] -1 "  (diff rendering failed: ", err, ")" }]; -1 "Diff not available"];
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
  if[(not lSub~r) and not .tst.suppressAssertionDiff;
    -1 "FAILURE DIFF (Included Columns) ------------------------------------";
    $[100h < type .tst.diff; @[{ -1 .tst.diff[x 0; x 1] }; (r;lSub); {[err] -1 "  (diff rendering failed: ", err, ")" }]; -1 "Diff not available"];
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
  msg: "Expected ", (.tst.toString name), " to have been called with ",.tst.assertValueText args;
  if[not found; msg,: ". Actual calls: ", $[0 = count calls; "(none)";.tst.assertValueText calls]];
  .tst.asserts[`must][found; msg];
 };

/ Additive camelCase aliases (compat surface). Assigned AFTER their targets
/ exist so they capture live function values. Added to .tst.asserts so init.q's
/ canonical test-source export table includes them too.
asserts[`mustEqual]:                asserts[`musteq];
asserts[`mustNotEqual]:             asserts[`mustne];
asserts[`mustLessThan]:             asserts[`mustlt];
asserts[`mustGreaterThan]:          asserts[`mustgt];
asserts[`mustMatchSnapshot]:        asserts[`mustmatchs];
asserts[`mustMatchTextSnapshot]:    asserts[`mustmatchst];
asserts[`mustMatchIgnoringOrder]:   asserts[`mustmatchignoringorder];

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

/ Additive camelCase root aliases (compat). Assigned after targets exist.
mustEqual: .tst.asserts[`mustEqual];
mustNotEqual: .tst.asserts[`mustNotEqual];
mustLessThan: .tst.asserts[`mustLessThan];
mustGreaterThan: .tst.asserts[`mustGreaterThan];
mustMatchSnapshot: .tst.asserts[`mustMatchSnapshot];
mustMatchTextSnapshot: .tst.asserts[`mustMatchTextSnapshot];
mustMatchIgnoringOrder: .tst.asserts[`mustMatchIgnoringOrder];
