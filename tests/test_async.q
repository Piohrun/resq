.tst.desc["Async and Promise Testing"]{
 should["create and resolve a deferred"]{
  id: .tst.deferred[];
  state: .tst.getState[id];
  state[`state] musteq `pending;
  .tst.resolve[id; 42];
  state: .tst.getState[id];
  state[`state] musteq `resolved;
  state[`val] musteq 42;
  };
 should["create and reject a deferred"]{
  id: .tst.deferred[];
  .tst.reject[id; "error message"];
  state: .tst.getState[id];
  state[`state] mustmatch `rejected;
  state[`err] mustmatch "error message";
  };
 should["await a resolved promise"]{
  id: .tst.deferred[];
  .tst.resolve[id; 123];
  result: .tst.await[id; 1000];
  result musteq 123;
  };
 should["timeout if promise never settles"]{
  code: { id: .tst.deferred[]; .tst.await[id; 100] };
  mustthrow["*timed out*"; code];
  };
 should["eventually succeed when condition becomes true"]{
  .tst.asyncCounter: 0;
  cond: { .tst.asyncCounter+::1; .tst.asyncCounter > 3 };
  .tst.eventually[cond; 2000; 50];
  .tst.asyncCounter mustgt 3;
  };
 should["eventually timeout if condition never succeeds"]{
  code: { .tst.eventually[{0b}; 200; 50] };
  mustthrow["*timed out*"; code];
  };
 should["track callback invocations"]{
  .tst.clearCallbackLogs[];
  cb: .tst.callbackSpy[`testCallback];
  cb[1 2 3];
  cb[4 5 6];
  calls: .tst.getCallbackCalls[`testCallback];
  count[calls] musteq 2;
  };
 };

::
