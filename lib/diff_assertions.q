\d .tst

musteqDiff:{[expected;actual]
    if[expected~actual; :1b];
    
    / Use diff
    d: .tst.diff[expected;actual];

    / Print diff to console for visibility (unless suppressed by fuzz/etc.)
    if[not .tst.suppressAssertionDiff;
        -1 "";
        -1 "FAILURE DIFF ---------------------------------------------------";
        -1 d;
        -1 "----------------------------------------------------------------";
    ];

    / Signal error like standard assertion
    'musteqFailed
 }

mustmatchDiff: .tst.musteqDiff

\d .
