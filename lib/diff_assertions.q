\d .tst

musteqDiff:{[expected;actual]
    if[expected~actual; :1b];

    / Print diff to console for visibility (unless suppressed by fuzz/etc.).
    / Rendering problems must never mask the assertion failure itself.
    if[not .tst.suppressAssertionDiff; .tst.printDiffSafe[expected;actual]];

    / Signal error like standard assertion
    'musteqFailed
 }

mustmatchDiff: .tst.musteqDiff

\d .
