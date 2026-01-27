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
