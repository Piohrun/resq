/ ============================================================================
/ Every runnable claim in docs/ASYNC.md, executed.
/ .
/ The async and promise helpers were shipped undocumented, and the docstrings in
/ lib/async.q were wrong about the most important detail: waitEx claimed to
/ return false on timeout when it always signals. Docs for this repo are only
/ trustworthy if they run, so the guide's examples live here as tests -- a
/ change to the behaviour breaks the test, not just the prose.
/ ============================================================================
.feed.buffer: 1 2 3;
.feed.start: {[] .feed.buffer: ()};
.db.trades: ();
.order.notifyUser: {[u] u};
.order.fill: {[i] .order.notifyUser i};

.tst.desc["ASYNC.md examples"]{
  should["deferred: settle once, then throw"]{
    d: .tst.deferred[];
    .tst.resolve[d; 42];
    mustthrow["*already settled*"; (.tst.resolve; d; 43)];
    mustthrow["*Unknown deferred*"; (.tst.getState; `nosuch)];
  };

  should["await returns the value, or throws the reason"]{
    d: .tst.deferred[];
    .tst.reject[d; "gateway unreachable"];
    mustthrow["*gateway unreachable*"; (.tst.await; d; 1000)];
    d2: .tst.deferred[];
    .tst.resolve[d2; 7];
    (.tst.await[d2; 0N]) musteq 7;          / 0N -> default 5000ms
  };

  should["isSettled never throws; getState does"]{
    d: .tst.deferred[];
    (.tst.isSettled d) musteq 0b;
    (.tst.isSettled `nosuch) musteq 0b;
    .tst.resolve[d; 7];
    s: .tst.getState d;
    (first s`state) musteq `resolved;
    (cols s) musteq `state`val`err;
  };

  should["until/wait poll, and throw on timeout"]{
    .feed.buffer: 1 2 3;
    .feed.start[];
    must[.tst.until {0 = count .feed.buffer}; "buffer should drain"];
    must[.tst.until {[] 1b}; "a niladic condition works too"];
    must[.tst.wait[{0 = count .feed.buffer}; 5000; 50]; "explicit timings work"];
    mustthrow["*wait timeout*"; (.tst.wait; {0b}; 60; 20)];
  };

  should["waitEx can fire the timer"]{
    must[.tst.waitEx[{1b}; 2000; 100; 1b]; "heartbeat form works"];
  };

  should["eventually treats a throwing condition as not-yet"]{
    .db.trades: enlist 1;
    must[.tst.eventually[{0 < count .db.trades}; 2000; 50]; "should converge"];
    / A condition that always throws polls to the timeout.
    mustthrow["*Eventually timed out*"; (.tst.eventually; {'"not ready"}; 60; 20)];
    must[.tst.eventually[{1b}; 0N; 0N]; "0N gives the defaults"];
  };

  should["callbackSpy records calls and passes args through"]{
    .tst.clearCallbackLogs[];
    `.order.notifyUser mock .tst.callbackSpy `notify;
    .order.fill 1;
    .order.fill 2;
    (count .tst.getCallbackCalls `notify) musteq 2;
    calls: .tst.getCallbackCalls `notify;
    (last first calls) musteq 1;
    (.tst.getCallbackCalls `never) musteq ();
  };

  should["sleep blocks for roughly the requested time"]{
    t0: .z.p;
    .tst.sleep 50;
    must[(.z.p - t0) >= 40000000; "sleep should block ~50ms"];
  };
};
