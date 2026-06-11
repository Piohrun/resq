\d .tst

/ Initialize the active test execution context. The real .tst.runSpec lives in
/ lib/runner.q (loaded after this file via resq.q) - a duplicate runSpec used to
/ live here but was dead (immediately overwritten at load), so it was removed.
/ This file remains solely to seed .tst.context, which fixture/mock/internals/
/ expec all read before any spec runs.
.tst.context:`.
