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
