\d .tst

musteqDiff:{[expected;actual]
    if[expected~actual; :1b];
    
    / Use diff
    d: .tst.diff[expected;actual];
    
    / Print diff to console for visibility
    -1 "";
    -1 "FAILURE DIFF ---------------------------------------------------";
    -1 d;
    -1 "----------------------------------------------------------------";
    
    / Signal error like standard assertion
    'musteqFailed
 }

mustmatchDiff: .tst.musteqDiff

\d .
