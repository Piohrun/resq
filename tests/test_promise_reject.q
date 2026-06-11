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
