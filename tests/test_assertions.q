.tst.desc["Assertions"]{
 should["increment the assertions run counter by one"]{
  assertsRun: .tst.assertState.assertsRun;
  1 musteq 1;
  .tst.assertState.assertsRun musteq 1 + assertsRun;
  };
 should["attach failure messages to the failures lists"]{
  oldFailures: .tst.assertState.failures; 
  must[0b;"failure1"];
  must[0b;"faiure2"];
  must[1b;"notfailure"];
  testedFailures: .tst.assertState.failures;
  .tst.assertState.failures:oldFailures;
  count[testedFailures] musteq 2;
  };
 };
.tst.desc["Error Assertions"]{
 before{
  `oldFailures mock .tst.assertState.failures; 
  };
 should["catch errors"]{
  mustnotthrow[()]{
   mustthrow[();{'"foo"}];
   mustnotthrow[();{'"foo"}];
   .tst.assertState.failures:oldFailures;
   };
  };
 should["be capable of executing function objects"]{
  errFunc:{'"foo"};
  cleanFunc:{"foo"};
  mustthrow[();errFunc];
  mustnotthrow[();cleanFunc];
  .tst.assertState.failures:oldFailures;
  };
 should["be capable of executing lists"]{
  `errFunc mock {'x};
  `cleanFunc mock {x};
  mustthrow[();(errFunc;"foo")];
  mustnotthrow[();(cleanFunc;"foo")];
  mustthrow[();(`errFunc;"foo")];
  mustnotthrow[();(`cleanFunc;"foo")];
  .tst.assertState.failures:oldFailures;
  };
 should["report only thrown exceptions that were not supposed to have been thrown"]{
  mustnotthrow["foo";{'"foo"}];
  mustnotthrow["foo";{'"bar"}];
  mustnotthrow["*foo*";{'"farfigfoogen"}];
  testedFailures: .tst.assertState.failures;
  .tst.assertState.failures:oldFailures;
  count[testedFailures] musteq 2;
  (first testedFailures) mustlike "*to not throw the error 'foo'*";
  (last testedFailures) mustlike "*to not throw the error 'farfigfoogen'*";
  };
 should["report only unthrown exceptions that were supposed to have been thrown"]{
  mustthrow["foo";{'"bar"}];
  testedFailures: .tst.assertState.failures;
  .tst.assertState.failures:oldFailures;
  count[testedFailures] musteq 1;
  (first testedFailures) mustlike "*the error 'foo'. Error thrown: 'bar'*";
  };
 should["never confuse a normal err0x-shaped return with an exception"]{
  oldFailures: .tst.assertState.failures;
  mustthrow["*boom*"; {(`err0x;"boom")}];
  mustnotthrow["*boom*"; {(`err0x;"boom")}];
  testedFailures: (count oldFailures) _ .tst.assertState.failures;
  .tst.assertState.failures: oldFailures;
  count[testedFailures] musteq 1;
  (first testedFailures) mustlike "*No error thrown*";
  };
 };

.tst.desc["Assertion aliases"]{
 should["expose camelCase aliases that behave like their snake_case targets"]{
  / Passing forms must not register a failure.
  oldFailures: .tst.assertState.failures;
  mustEqual[1; 1];
  mustNotEqual[1; 2];
  mustLessThan[1; 2];
  mustGreaterThan[2; 1];
  testedFailures: .tst.assertState.failures;
  .tst.assertState.failures: oldFailures;
  count[testedFailures] musteq 0;
  };
 should["fail through camelCase aliases just like the targets"]{
  oldFailures: .tst.assertState.failures;
  mustEqual[1; 2];
  testedFailures: .tst.assertState.failures;
  .tst.assertState.failures: oldFailures;
  count[testedFailures] musteq 1;
  };
 };

.tst.desc["mustthrow arg-shape guard"]{
 should["signal a clear message when called with code first (infix misuse)"]{
  / mustthrow expects [pattern; code]; passing a function first must not crash
  / with 'type but produce the guidance message instead.
  / NB: `like` patterns avoid `[` (char-class) and keep to <=2 wildcards.
  mustthrow["*did you call it infix*"]{ mustthrow[{'"boom"}; `somePattern] };
  };
 should["signal the same for mustnotthrow"]{
  mustthrow["*did you call it infix*"]{ mustnotthrow[{"ok"}; `somePattern] };
  };
 should["keep all working pattern shapes working"]{
  oldFailures: .tst.assertState.failures;
  mustthrow[(); {'"boom"}];               / no pattern
  mustthrow["*boom*"; {'"boom"}];         / string pattern
  mustthrow[`$"boom"; {'"boom"}];         / symbol pattern
  mustthrow[("*boom*"; "*x*"); {'"boom"}];  / list of patterns (one must match)
  testedFailures: .tst.assertState.failures;
  .tst.assertState.failures: oldFailures;
  count[testedFailures] musteq 0;
  };
 };

.tst.desc["mustmatch rich diff"]{
 should["fail like musteq (same message), not a bare -3! render"]{
  oldFailures: .tst.assertState.failures;
  / mustmatch now routes through musteq, so a mismatch yields the musteq message.
  mustmatch[5; 7];
  testedFailures: .tst.assertState.failures;
  .tst.assertState.failures: oldFailures;
  count[testedFailures] musteq 1;
  / Single-wildcard pattern (q `like` rejects 3+ stars with 'nyi).
  (first testedFailures) mustlike "Got 5 *";
  must[(first testedFailures) like "*expected 7*"; "message should name the expected value"];
  };
};

.tst.desc["assertion full-value evidence budget"]{
 should["cap only after full rendering and include a stable digest"]{
  `.tst.output.reportLimit mock 50000;
  raw:(30000#"x"),"DISTINGUISHING_TAIL";
  full:.tst.renderValueFull raw;
  bounded:.tst.assertValueText raw;
  must[0<count ss[full;"DISTINGUISHING_TAIL"];
       "full evidence renderer must retain the tail"];
  (count bounded) musteq 25000;
  must[(0<count ss[bounded;"truncated"]) and 0<count ss[bounded;"md5="];
       "bounded assertion evidence must make truncation and identity visible"];
  };
};

.tst.desc["failure diff context"]{
 should["derive a suite and test label for streamed diff headers"]{
  label: .tst.diffContextLabel[];
  label mustlike "failure diff context :: derive a suite*";
  };
 };

/ Regression: mustne used `<>` (elementwise), so for any non-atom it handed
/ `must` a boolean VECTOR. `must` applies `all`, so it meant "every element
/ differs" instead of "the values are not identical" — and tables or
/ different-length operands crashed with 'type / 'length before asserting.
.tst.desc["mustne whole-value semantics"]{
 / These pin resQ's DEFAULT semantics, so they must not be perturbed by a run
 / invoked with -qspec-compat (which deliberately restores qspec's).
 before{ `.tst.app.qspecCompat mock 0b };

 should["register no failure for values that genuinely differ"]{
  / Failures a single assertion adds, with global assert state left untouched.
  probe: {[f] old: .tst.assertState.failures; f[];
              n: (count .tst.assertState.failures) - count old;
              .tst.assertState.failures: old; n};

  probe[{mustne[1; 2]}] musteq 0;
  probe[{mustne[`a; `b]}] musteq 0;
  probe[{mustne[1 2 3; 1 2 4]}] musteq 0;
  probe[{mustne[1 2 3; 9 2 3]}] musteq 0;              / only the first element differs
  probe[{mustne["abc"; "abd"]}] musteq 0;
  probe[{mustne[1 2 3; 1 2]}] musteq 0;                / operands of different length
  probe[{mustne[`a`b!1 2; `a`b!1 3]}] musteq 0;
  probe[{mustne[([]v:1 2 3); ([]v:1 2 4)]}] musteq 0;
  };

 should["register exactly one failure for values that are identical"]{
  probe: {[f] old: .tst.assertState.failures; f[];
              n: (count .tst.assertState.failures) - count old;
              .tst.assertState.failures: old; n};

  probe[{mustne[1; 1]}] musteq 1;
  probe[{mustne[1 2 3; 1 2 3]}] musteq 1;
  probe[{mustne["abc"; "abc"]}] musteq 1;
  probe[{mustne[`a`b!1 2; `a`b!1 2]}] musteq 1;
  probe[{mustne[([]v:1 2 3); ([]v:1 2 3)]}] musteq 1;
  };

 should["reject conditions that are not truth values, but keep q truthiness"]{
  probe: {[f] old: .tst.assertState.failures; f[];
              n: (count .tst.assertState.failures) - count old;
              .tst.assertState.failures: old; n};

  / Numbers are truthy exactly as q's `if` and qspec treat them, so the common
  / `must[count x; ...]` idiom keeps working and stays source-compatible.
  probe[{must[count 1 2 3; "a non-zero count is true"]}] musteq 0;
  probe[{must[1i; "non-zero int"]}] musteq 0;
  probe[{must[2.5; "non-zero float"]}] musteq 0;
  probe[{must[0; "zero is false"]}] musteq 1;
  probe[{must[1 0 1; "any zero is false"]}] musteq 1;

  / `all` maps each of these to 1b, so they used to pass silently. A null is not
  / a truth value, and a string/symbol is almost always a swapped argument.
  probe[{must[0N; "a null is not a condition"]}] musteq 1;
  probe[{must["some message"; "swapped arguments"]}] musteq 1;
  probe[{must[`sym; "a symbol is not a condition"]}] musteq 1;
  probe[{must[(); "an empty generic list is not a condition"]}] musteq 1;

  / Booleans still behave exactly as before.
  probe[{must[1b; "true passes"]}] musteq 0;
  probe[{must[0b; "false fails"]}] musteq 1;
  probe[{must[111b; "all-true vector passes"]}] musteq 0;
  probe[{must[101b; "any-false vector fails"]}] musteq 1;
  / "all of zero items hold" -- an assertion over an empty set still passes.
  probe[{must[`boolean$(); "empty boolean vector"]}] musteq 0;
  };

 should["name the offending type when the condition is not boolean"]{
  old: .tst.assertState.failures;
  must[0N; "ignored"];
  reported: last .tst.assertState.failures;
  .tst.assertState.failures: old;
  must[reported like "*not a truth value*";
       "a null condition should say so, got: ", reported];

  old2: .tst.assertState.failures;
  must[`sym; "ignored"];
  reported2: last .tst.assertState.failures;
  .tst.assertState.failures: old2;
  must[reported2 like "*must expects a boolean or numeric condition*";
       "message should state the contract, got: ", reported2];
  must[reported2 like "*-11h*"; "message should name the actual type, got: ", reported2];
  };

 should["stay the exact inverse of musteq, including type strictness"]{
  probe: {[f] old: .tst.assertState.failures; f[];
              n: (count .tst.assertState.failures) - count old;
              .tst.assertState.failures: old; n};

  / `~` distinguishes 1 from 1.0, so musteq fails where mustne passes. Under the
  / old `<>` both failed at once, which no pair of inverses should ever do.
  probe[{musteq[1; 1.0]}] musteq 1;
  probe[{mustne[1; 1.0]}] musteq 0;
 };
};

.tst.desc["successful assertions keep diagnostics lazy"]{
 before{
  `.tst.testState.lazyRenderCount mock 0;
  `.tst.assertValueText mock {[v] .tst.testState.lazyRenderCount+:1; "rendered"};
  };

 should["not stringify operands on any successful comparison"]{
  1 mustne 2;
  1 mustnmatch 2;
  1 mustlt 2;
  2 mustgt 1;
  "alpha" mustlike "a*";
  2 mustin 1 2 3;
  4 mustnin 1 2 3;
  2 mustwithin 1 3;
  mustdelta[0.1;1f;1f];
  .tst.testState.lazyRenderCount musteq 0;
  };
 };

.tst.desc["typed comparison diagnostics"]{
 should["turn invalid operands into concise assertion usage errors"]{
  cases:(
    ("mustlt";{mustlt[`abc;5]});
    ("mustgt";{mustgt[5;`abc]});
    ("mustin";{mustin[1;`abc]});
    ("mustnin";{mustnin[1;`abc]});
    ("mustwithin";{mustwithin[1;`abc]});
    ("mustdelta";{mustdelta[`bad;1;2]}));
  {[row]
    captured:.tst.captureAssertionCode row 1;
    must[first captured;"invalid ",row[0]," operands must signal"];
    message:.tst.toString last captured;
    must[message like "*",row[0],"*";"error must name the assertion: ",message];
    must[message like "*operand types*";"error must name operand types: ",message];
  } each cases;
 };
};

/ resQ is meant to be a drop-in replacement for qspec (nugend/qspec). The
/ assertion NAMES are already identical; three semantics differ, and
/ -qspec-compat / "qspecCompat": true restores qspec's for an unported suite.
/ Verified against qspec's real definitions:
/   musteq  qspec: all l = r   (broadcasts a scalar, type-loose)
/   mustne  qspec: all l <> r  ("every element differs")
/ q gives no file/line for a failing assertion: nothing throws, and definitions
/ evaluated via `value` carry no source position, so a backtrace shows the
/ expression but not where it lives. The assertion's ordinal within the test is
/ the locator that IS available.
.tst.desc["failure messages locate the assertion"]{
 should["name the ordinal past the first assertion"]{
  old: .tst.assertState.failures;
  1 musteq 1;
  2 musteq 2;
  3 musteq 99;
  reported: last .tst.assertState.failures;
  .tst.assertState.failures: old;
  / Two wildcards max: q's `like` signals 'nyi on three or more.
  must[reported like "*assertion #3*";
       "a later assertion should report its ordinal, got: ", reported];
  };

 should["stay quiet for the first assertion"]{
  / A single-assertion test needs no ordinal, and goldens pin these messages.
  probe: {[f] old: .tst.assertState.failures; f[];
              msg: last .tst.assertState.failures;
              .tst.assertState.failures: old; msg};
  msg: probe[{must[0b; "plain message"]}];
  must[not msg like "*assertion #*"; "the first assertion needs no ordinal, got: ", msg];
  };
 };

.tst.desc["qspec compatibility mode"]{
 after{ .tst.app.qspecCompat: 0b };

 should["fail qspec-style comparisons by default, with a migration hint"]{
  probe: {[f] old: .tst.assertState.failures; f[];
              n: (count .tst.assertState.failures) - count old;
              msg: $[n > 0; last .tst.assertState.failures; ""];
              .tst.assertState.failures: old; (n; msg)};
  .tst.app.qspecCompat: 0b;

  r: probe[{(0 0 0) musteq 0}];
  (first r) musteq 1;
  must[(last r) like "*qspec compatibility*";
       "a broadcast mismatch must name the qspec difference, got: ", last r];
  must[(last r) like "*-qspec-compat*"; "the hint must name the switch"];

  (first probe[{1 musteq 1.0}]) musteq 1;
  };

 should["accept qspec's musteq semantics under -qspec-compat"]{
  probe: {[f] old: .tst.assertState.failures; f[];
              n: (count .tst.assertState.failures) - count old;
              .tst.assertState.failures: old; n};
  .tst.app.qspecCompat: 1b;

  probe[{(0 0 0) musteq 0}]  musteq 0;   / scalar broadcast
  probe[{1 musteq 1.0}]      musteq 0;   / loose numeric type
  probe[{(1 2 3) musteq 1 2 3}] musteq 0; / exact match still fine
  / Better than qspec, which signals 'type here:
  probe[{([]v:1 2) musteq ([]v:1 2)}] musteq 0;
  / A genuine mismatch must still fail.
  probe[{(1 2 3) musteq 9 9 9}] musteq 1;
  };

 should["use qspec's elementwise mustne under -qspec-compat"]{
  probe: {[f] old: .tst.assertState.failures; f[];
              n: (count .tst.assertState.failures) - count old;
              .tst.assertState.failures: old; n};
  .tst.app.qspecCompat: 1b;
  probe[{mustne[1 2 3; 4 5 6]}] musteq 0;   / every element differs
  probe[{mustne[1 2 3; 1 2 4]}] musteq 1;   / qspec: not every element differs
  .tst.app.qspecCompat: 0b;
  probe[{mustne[1 2 3; 1 2 4]}] musteq 0;   / resQ: the values are not identical
  };
 };
