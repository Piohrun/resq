\d .tst

/ Async Utilities

/ More efficient sleep that doesn't fork a process
/ @param ms (int) millseconds
sleep:{[ms]
    start: .z.p;
    limit: start + `long$ms * 1000000;
    while[.z.p < limit; ];
 }

/ Wait for condition to be true
/ @param cond (function) Returns boolean
/ @param timeout (int) Max wait in milliseconds
/ @param interval (int) Check interval in milliseconds
/ @param heartbeat (bool) If true, calls .z.ts[] during wait to allow timer-based logic
/ @return (boolean) true if condition met, false (or signal) if timeout
waitEx:{[cond;timeout;interval;heartbeat]
    start: .z.p;
    limit: start + `long$timeout * 1000000;
    
    res: 0b;
    while[not res: cond[];
        if[.z.p > limit; 
            '"wait timeout: condition not met in ",string[timeout],"ms"];
        
        / Heartbeat: allow timers to run
        if[heartbeat;
            @[value; ".z.ts[]"; { [e] -1 "ERROR in heartbeat (.z.ts): ", e }];
        ];
        
        sleep[interval];
    ];
    res
 }

/ Standard wait (backwards compatible)
wait:{[cond;timeout;interval]
    waitEx[cond; timeout; interval; 0b]
 }

/ Simplified wait (default 1s timeout, 100ms interval)
until:{[cond]
    wait[cond; 1000; 100]
 }

\d .
