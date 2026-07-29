\d .tst

/ Async Utilities

.tst.ASYNC_MAX_MILLIS:3600000;
.tst.ASYNC_MAX_ATTEMPTS:10000;
.tst.ASYNC_MAX_ERROR_CHARS:1024;

.tst._captureSafetyValue:{[path]
    (1b;enlist get path)
 };

.tst._captureSafetyError:{[err]
    (0b;enlist err)
 };

/ Read a lowerable integer safety seam without allowing it to exceed its
/ embedded ceiling. Missing or corrupt seams fail before async work begins.
.tst._asyncLimit:{[path;label;minimum;literalCeiling]
    outcome:@[
        .tst._captureSafetyValue;
        path;
        .tst._captureSafetyError];
    if[not first outcome; 'label," safety limit is unavailable"];
    limitValue:first last outcome;
    if[not type[limitValue] in -4 -5 -6 -7h;
        'label," safety limit must be a finite integer scalar"];
    if[null limitValue;
        'label," safety limit must be a finite integer scalar"];
    if[limitValue in (0Wh;-0Wh;0Wi;-0Wi;0W;-0W);
        'label," safety limit must be finite"];
    if[limitValue<minimum;
        'label," safety limit is below its supported minimum"];
    if[limitValue>literalCeiling;
        'label," safety limit exceeds its literal ceiling"];
    "j"$limitValue
 };

.tst._asyncMillisLimit:{[]
    .tst._asyncLimit[
        `.tst.ASYNC_MAX_MILLIS;
        "async duration";
        0;
        3600000]
 };

.tst._asyncAttemptLimit:{[]
    .tst._asyncLimit[
        `.tst.ASYNC_MAX_ATTEMPTS;
        "async attempt";
        1;
        10000]
 };

.tst._asyncErrorLimit:{[]
    .tst._asyncLimit[
        `.tst.ASYNC_MAX_ERROR_CHARS;
        "async diagnostic";
        16;
        4096]
 };

.tst._asyncErrorText:{[err;limit]
    if[not 10h=type err; :"async operation failed"];
    (limit&count err)#err
 };

.tst._asyncCallableArityBody:{[fn]
    callableType:type fn;
    if[100h=callableType; :count (value fn)1];
    if[101h=callableType; :1];
    if[102h=callableType; :2];
    if[104h=callableType; :sum {(::)~x} each 1_value fn];
    -1
 };

.tst._asyncCallableArity:{[fn]
    @[.tst._asyncCallableArityBody;fn;{[err] -1}]
 };

.tst._validateAsyncCallableArity:{[fn;label;expectedArity]
    if[not type[fn] within 100 112h;
        'label," must be a callable function"];
    arity:.tst._asyncCallableArity fn;
    if[0>arity;
        'label," arity cannot be determined safely"];
    compatible:$[
        0=expectedArity;
        (0=arity) or ((100h=type fn) and 1=arity);
        arity=expectedArity];
    if[not compatible;
        'label," must accept ",string[expectedArity]," argument(s)"];
    fn
 };

.tst._validateAsyncCallable:{[fn;label]
    .tst._validateAsyncCallableArity[fn;label;0]
 };

.tst._validateHeartbeat:{[heartbeat]
    if[not -1h=type heartbeat;
        '"heartbeat must be a boolean scalar"];
    heartbeat
 };

/ Async conditions deliberately accept only boolean or integer 0/1 results.
.tst._conditionResult:{[result;label]
    if[(result~0b) or (result~0); :0b];
    if[(result~1b) or (result~1); :1b];
    if[type[result] in -4 -5 -6 -7h;
        if[result=0; :0b];
        if[result=1; :1b]];
    'label," must return boolean or integer 0/1"
 };

.tst._heartbeat:{[]
    .z.ts[]
 };

.tst._windowsSleepFail:{[detail]
    if[not 10h=type detail; detail:"trusted PowerShell is unavailable"];
    '"Windows sleep unavailable: ",detail
 };

/ Use one immutable, absolute OS location. This deliberately fails closed on
/ Windows installations whose trusted executable is elsewhere: environment
/ variables cannot safely attest an alternative system root.
.tst._windowsPowerShellPath:{[]
    executable:
        "C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe";
    if[not 57=count executable;
        .tst._windowsSleepFail[
            "trusted PowerShell path failed its literal integrity check"]];
    exists:@[
        {[path] 1b~.utl.isFile path};
        executable;
        {[err] 0b}];
    if[not exists;
        .tst._windowsSleepFail[
            "trusted PowerShell executable was not found as a regular file"]];
    executable
 };

.tst._windowsSleepCommand:{[executable;wholeMs]
    if[not 10h=type executable;
        .tst._windowsSleepFail["trusted PowerShell path must be a string"]];
    trusted:
        "C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe";
    if[not executable~trusted;
        .tst._windowsSleepFail["trusted PowerShell path is invalid"]];
    if[not -7h=type wholeMs;
        .tst._windowsSleepFail[
            "sleep duration must be a finite integer millisecond scalar"]];
    if[(null wholeMs) or
       (wholeMs in (0W;-0W)) or
       (wholeMs<0) or
       (wholeMs>3600000);
        .tst._windowsSleepFail[
            "sleep duration is outside its literal millisecond ceiling"]];
    "\"",executable,
        "\" -NoLogo -NoProfile -NonInteractive -Command ",
        "\"[System.Threading.Thread]::Sleep(",
        string[wholeMs],
        ")\""
 };

/ Validate a duration expressed in milliseconds.
/ params:  ms — numeric scalar; label — field name used in errors
/ returns: duration as a float, preserving fractional milliseconds
/ side effects: signals for invalid input or a poisoned duration safety seam
.tst._durationError:{[label]
    msg:label," must be a finite non-negative numeric scalar";
    'msg
 }

.tst._validateMillis:{[ms;label]
    maximum:.tst._asyncMillisLimit[];
    numericTypes:neg 4 5 6 7 8 9h;
    infinities:(0Wh;-0Wh;0Wi;-0Wi;0W;-0W;0we;-0we;0w;-0w);
    if[not (type ms) in numericTypes; .tst._durationError label];
    if[null ms; .tst._durationError label];
    if[ms in infinities; .tst._durationError label];
    if[0 > ms; .tst._durationError label];
    if[ms>maximum;
        'label," exceeds async duration safety limit"];
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
        executable:.tst._windowsPowerShellPath[];
        system .tst._windowsSleepCommand[executable;wholeMs];
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
    cond:.tst._validateAsyncCallable[cond;"wait condition"];
    heartbeat:.tst._validateHeartbeat heartbeat;
    attemptLimit:.tst._asyncAttemptLimit[];
    errorLimit:.tst._asyncErrorLimit[];
    start:.z.p;
    attempts:0;
    while[1b;
        outcome:@[
            {[fn] (1b;enlist fn[])};
            cond;
            {[e] (0b;enlist e)}];
        attempts+:1;
        if[not first outcome;
            '"wait condition failed: ",
                .tst._asyncErrorText[first last outcome;errorLimit]];
        if[.tst._conditionResult[first last outcome;"wait condition"]; :1b];
        elapsed:0.000001*"f"$`long$.z.p-start;
        if[elapsed >= timeoutMs;
            '"wait timeout: condition not met in ",string[timeout],"ms"];
        if[attempts>=attemptLimit;
            '"wait exceeded async attempt safety limit"];
        / Heartbeat: allow timers to run
        if[heartbeat;
            heartbeatOutcome:@[
                {[ignored] (1b;enlist .tst._heartbeat[])};
                ::;
                {[e] (0b;enlist e)}];
            if[not first heartbeatOutcome;
                '"heartbeat failed: ",
                    .tst._asyncErrorText[
                        first last heartbeatOutcome;
                        errorLimit]];
        ];
        .tst._sleepRemaining[intervalMs;timeoutMs-elapsed];
    ];
    1b
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
