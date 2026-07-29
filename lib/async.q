\d .tst

/ Async Utilities

/ Validate a duration expressed in milliseconds.
/ params:  ms — numeric scalar; label — field name used in errors
/ returns: duration as a float, preserving fractional milliseconds
/ side effects: signals for non-numeric, null, infinite, or negative input
.tst._durationError:{[label]
    msg:label," must be a finite non-negative numeric scalar";
    'msg
 }

.tst._validateMillis:{[ms;label]
    numericTypes:neg 1 4 5 6 7 8 9h;
    infinities:(0Wh;-0Wh;0Wi;-0Wi;0W;-0W;0we;-0we;0w;-0w);
    if[not (type ms) in numericTypes; .tst._durationError label];
    if[null ms; .tst._durationError label];
    if[ms in infinities; .tst._durationError label];
    if[0 > ms; .tst._durationError label];
    "f"$ms
 }

/ Pause without consuming a CPU core.
/ params:  ms — finite, non-negative numeric scalar in milliseconds
/ returns: generic null
/ side effects: invokes only a fixed OS sleep command plus validated numeric data
sleep:{[ms]
    duration:.tst._validateMillis[ms;"sleep milliseconds"];
    if[0f=duration; :(::)];
    if[.utl.isWindows;
        wholeMs:"j"$ceiling duration;
        system "powershell.exe -NoLogo -NoProfile -NonInteractive -Command \"[System.Threading.Thread]::Sleep(",string[wholeMs],")\"";
        :(::)];
    system "/bin/sleep ",string 0.001*duration;
    (::)
 }

/ Sleep for at most the polling interval or remaining deadline.
/ side effects: yields for at least 1ms when interval is zero
.tst._sleepRemaining:{[interval;remaining]
    effective:$[0f=interval;1f;interval];
    delay:effective & remaining;
    if[0f < delay; sleep delay];
    (::)
 }

/ Wait for condition to be true
/ @param cond (function) Returns boolean
/ @param timeout (numeric) Max wait in milliseconds
/ @param interval (numeric) Check interval in milliseconds
/ @param heartbeat (bool) If true, calls .z.ts[] during wait to allow timer-based logic
/ @return (boolean) true if condition met, false (or signal) if timeout
waitEx:{[cond;timeout;interval;heartbeat]
    timeoutMs:.tst._validateMillis[timeout;"timeout"];
    intervalMs:.tst._validateMillis[interval;"interval"];
    start:.z.p;
    res:cond[];
    while[not res;
        elapsed:0.000001*"f"$`long$.z.p-start;
        if[elapsed >= timeoutMs;
            '"wait timeout: condition not met in ",string[timeout],"ms"];
        / Heartbeat: allow timers to run
        if[heartbeat;
            @[.z.ts; ::; {[e] -1 "ERROR in heartbeat (.z.ts): ",e }];
        ];
        .tst._sleepRemaining[intervalMs;timeoutMs-elapsed];
        res:cond[];
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
