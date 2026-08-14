/ Regression tests for verified bugs:
/   - Bug 2: await on string/symbol rejection reasons (lib/promise.q)
/   - Bug 3: unprotected `get` in partialMock / mockSequence (lib/mock.q)

.tst.desc["Promise rejection and mock target errors"]{
 should["await re-raises a string rejection reason verbatim"]{
  code: { id: .tst.deferred[]; .tst.reject[id; "disk full"]; .tst.await[id; 1000] };
  mustthrow["*disk full*"; code];
  };
 should["await re-raises a symbol rejection reason"]{
  code: { id: .tst.deferred[]; .tst.reject[id; `kaboom]; .tst.await[id; 1000] };
  mustthrow["*kaboom*"; code];
  };
 should["deferred handles remain bounded"]{
  .tst.clearDeferreds[];
  firstHandle: .tst.deferred[];
  (-7h) musteq type firstHandle;
  .tst.resolve[firstHandle; 42];
  (.tst.await[firstHandle; 1000]) musteq 42;
  (count .tst.deferredStates) musteq 0;

  / A watch-like soak consumes settled handles immediately, and abandoned
  / pending handles are bounded by the end-of-run cleanup hook.
  do[10000;
    handle: .tst.deferred[];
    .tst.resolve[handle; handle];
    .tst.await[handle; 1000]];
  (count .tst.deferredStates) musteq 0;
  pendingHandles: .tst.deferred each 1000#enlist ();
  (count .tst.deferredStates) musteq 1000;
  .tst.clearDeferreds[];
  (count .tst.deferredStates) musteq 0;

  legacy: .tst.legacyDeferredHandle .tst.deferred[];
  (-11h) musteq type legacy;
  .tst.reject[legacy; `legacyFailure];
  mustthrow["*legacyFailure*"; (.tst.await; legacy; 1000)];
  (count .tst.deferredStates) musteq 0;
  };
 should["partialMock gives a friendly error for an undefined target"]{
  code: { .tst.partialMock[`.tst.noSuchTargetXyz; `a`b!1 2] };
  mustthrow["*target not defined*"; code];
  };
 should["mockSequence gives a friendly error for an undefined target"]{
  code: { .tst.mockSequence[`.tst.noSuchTargetXyz; (1; 2; 3)] };
  mustthrow["*target not defined*"; code];
  };
 };

::
