.tst.desc["Async and Promise Testing"]{
 should["create and resolve a deferred"]{
  id: .tst.deferred[];
  state: .tst.getState[id];
  state[`state] musteq `pending;
  .tst.resolve[id; 42];
  state: .tst.getState[id];
  state[`state] musteq `resolved;
  state[`val] musteq 42;
  .tst._forgetDeferred id;
  };
 should["create and reject a deferred"]{
  id: .tst.deferred[];
  .tst.reject[id; "error message"];
  state: .tst.getState[id];
  state[`state] mustmatch `rejected;
  state[`err] mustmatch "error message";
  .tst._forgetDeferred id;
  };
 should["await a resolved promise and release its state"]{
  id: .tst.deferred[];
  .tst.resolve[id; 123];
  result: .tst.await[id; 1000];
  result musteq 123;
  must[not id in key .tst.deferredStates; "resolved deferred state must be released after await"];
  mustthrow["*Unknown deferred*"; (.tst.getState; id)];
  };
 should["preserve composite resolved values without retaining state"]{
  existingIds:key .tst.deferredStates;
  resolvedValues:(::; 1 2 3; `a`b!1 2; ([] x:1 2));
  actual:{
    id:.tst.deferred[];
    .tst.resolve[id;x];
    .tst.await[id;100]
    } each resolvedValues;
  actual mustmatch resolvedValues;
  key[.tst.deferredStates] mustmatch existingIds;
  };
 should["await a string-rejected promise raises the message and releases state"]{
  / Regression for promise.q:188 await string-reject bug.
  id: .tst.deferred[];
  .tst.reject[id; "connection refused"];
  mustthrow["*connection refused*"; (.tst.await; id; 1000)];
  must[not id in key .tst.deferredStates; "rejected deferred state must be released after await"];
  };
 should["await a symbol-rejected promise raises the message and releases state"]{
  id: .tst.deferred[];
  .tst.reject[id; `boom];
  mustthrow["*boom*"; (.tst.await; id; 1000)];
  must[not id in key .tst.deferredStates; "symbol-rejected deferred state must be released after await"];
  };
 should["timeout if promise never settles and release its state"]{
  id: .tst.deferred[];
  mustthrow["*timed out*"; (.tst.await; id; 100)];
  must[not id in key .tst.deferredStates; "timed-out deferred state must be released after await"];
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
 should["retry condition errors until eventually succeeds"]{
  .tst.asyncCounter: 0;
  cond:{
    .tst.asyncCounter+::1;
    if[.tst.asyncCounter < 3; '"not ready"];
    1b
    };
  .tst.eventually[cond; 500; 5] musteq 1b;
  .tst.asyncCounter musteq 3;
  };
 should["bound sleep to the remaining eventually deadline"]{
  start: .z.p;
  mustthrow["*timed out*"; (.tst.eventually; {0b}; 40; 1000)];
  elapsedNs: `long$.z.p - start;
  must[elapsedNs < 500000000; "eventually must not sleep past its remaining timeout budget"];
  };
 should["bound sleep to the remaining wait deadline"]{
  start: .z.p;
  mustthrow["*wait timeout*"; (.tst.wait; {0b}; 40; 1000)];
  elapsedNs: `long$.z.p - start;
  must[elapsedNs < 500000000; "wait must not sleep past its remaining timeout budget"];
  };
 should["yield safely when the polling interval is zero"]{
  start: .z.p;
  mustthrow["*timed out*"; (.tst.eventually; {0b}; 30; 0)];
  elapsedNs: `long$.z.p - start;
  must[elapsedNs >= 20000000; "zero-interval polling must still honor the timeout"];
  must[elapsedNs < 500000000; "zero-interval polling must not oversleep"];
  };
 should["return immediately when sleep is zero"]{
  start:.z.p;
  result:.tst.sleep 0;
  elapsedNs:`long$.z.p-start;
  result mustmatch (::);
  must[elapsedNs < 50000000; "zero sleep must return without spawning a sleeper"];
  };
 should["reject invalid wait and sleep durations immediately"]{
  invalid:(-1; 0N; 0W; 0n; 0w; "10"; enlist 10; `ten);
  {mustthrow["*finite non-negative numeric scalar*"; (.tst.sleep; x)]} each invalid;
  {mustthrow["*timeout must be a finite non-negative numeric scalar*"; (.tst.wait; {1b}; x; 1)]} each invalid;
  {mustthrow["*interval must be a finite non-negative numeric scalar*"; (.tst.wait; {1b}; 1; x)]} each invalid;
  {mustthrow["*timeout must be a finite non-negative numeric scalar*"; (.tst.eventually; {1b}; x; 1)]} each invalid;
  {mustthrow["*interval must be a finite non-negative numeric scalar*"; (.tst.eventually; {1b}; 1; x)]} each invalid;
  };
 should["reject sleep command injection as non-numeric data"]{
  sentinel:.tst.tempFile ".async_sleep_injection";
  payload:"1; touch ",sentinel;
  mustthrow["*finite non-negative numeric scalar*"; (.tst.sleep; payload)];
  must[not .utl.pathExists sentinel; "invalid sleep input must never reach the shell"];
  };
 should["reject invalid await timeouts and release valid deferred IDs"]{
  invalid:(-1; 0N; 0W; 0n; 0w; "10"; enlist 10; `ten);
  {
    id:.tst.deferred[];
    mustthrow["*timeout must be a finite non-negative numeric scalar*"; (.tst.await; id; x)];
    must[not id in key .tst.deferredStates; "failed await validation must release deferred state"];
    } each invalid;
  };
 should["treat hostile deferred IDs as inert data"]{
  counterBefore:.tst.deferredCounter;
  hostile:"missing]; .tst.deferredCounter::-999; 1b} /";
  hostileSymbol:`$hostile;
  mustthrow["*Unknown deferred*"; (.tst.await; hostile; 10)];
  mustthrow["*Unknown deferred*"; (.tst.await; hostileSymbol; 10)];
  mustthrow["*Unknown deferred*"; (.tst.resolve; hostile; 1)];
  mustthrow["*Unknown deferred*"; (.tst.reject; hostile; "error")];
  mustthrow["*Unknown deferred*"; (.tst.isSettled; hostile)];
  mustthrow["*Unknown deferred*"; (.tst.getState; hostile)];
  .tst.deferredCounter musteq counterBefore;
  .tst.deferredCounter:counterBefore;
  };
 skipIf[not (.utl.isLinux and .utl.isFile "/proc/self/schedstat");
   "sleep blocks without burning process CPU (Linux schedstat)"]{
  procCmd:"/bin/cat /proc/",string[.z.i],"/schedstat";
  cpuBefore:"J"$first " " vs first system procCmd;
  start:.z.p;
  .tst.sleep 200;
  elapsedNs:`long$.z.p - start;
  cpuAfter:"J"$first " " vs first system procCmd;
  must[elapsedNs >= 150000000; "sleep returned materially before its requested duration"];
  must[elapsedNs < 1000000000; "sleep overshot its requested duration by an unreasonable amount"];
  must[50000000 > cpuAfter - cpuBefore; "sleep consumed excessive process CPU"];
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
