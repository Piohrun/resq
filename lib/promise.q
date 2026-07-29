\d .tst

/ Initialize deferred states dictionary and counter
deferredStates: ()!();
deferredCounter: 0;

/ Promise-like deferred object for managing async state
/ Uses global state dictionary for mutability
/ @return (symbol) Deferred ID
deferred:{[]
    if[.tst._debug[]; -1 "DEBUG: deferred called"];
    / Generate unique ID from counter
    id: `$ "def_", string .tst.deferredCounter;
    .tst.deferredCounter +: 1;
    if[.tst._debug[]; -1 "DEBUG: new id is ",string id];
    / Initialize state in global dict
    .tst.deferredStates[id]: ([] state: enlist `pending; val: enlist (::); err: enlist (::));
    if[.tst._debug[]; -1 "DEBUG: deferredStates updated"];
    id
 };

/ Return whether debug logging is enabled without assuming `.utl.DEBUG` exists.
.tst._debug:{[] 1b~@[get; `.utl.DEBUG; {[e] 0b}] };

/ Validate a deferred ID without coercing, evaluating, or interning it.
/ side effects: signals "Unknown deferred" for every invalid or absent ID
.tst._requireDeferred:{[id]
    if[not -11h=type id; '"Unknown deferred"];
    if[not id in key .tst.deferredStates; '"Unknown deferred"];
    id
 };

/ Remove an awaited deferred's state. Repeated calls are harmless.
.tst._forgetDeferred:{[id]
    if[-11h=type id; .tst.deferredStates::id _ .tst.deferredStates];
    (::)
 };

/ Resolve a deferred with a value
resolve:{[id;v]
    .tst._requireDeferred id;
    if[.tst._debug[]; -1 "DEBUG: resolve called for ",string id];
    state: .tst.deferredStates[id];
    if[not ((first state[`state]) ~ `pending);
        if[.tst._debug[]; -1 "DEBUG: Already settled"];
        '"Promise already settled"
    ];
    .tst.deferredStates[id;`state]: enlist `resolved;
    .tst.deferredStates[id;`val]: enlist v;
    if[.tst._debug[]; -1 "DEBUG: resolved ",string id];
 };

/ Reject a deferred with an error
reject:{[id;e]
    .tst._requireDeferred id;
    if[.tst._debug[]; -1 "DEBUG: reject called for ",string id];
    state: .tst.deferredStates[id];
    if[not ((first state[`state]) ~ `pending);
        if[.tst._debug[]; -1 "DEBUG: Already settled"];
        '"Promise already settled"
    ];
    .tst.deferredStates[id;`state]: enlist `rejected;
    .tst.deferredStates[id;`err]: enlist e;
    if[.tst._debug[]; -1 "DEBUG: rejected ",string id];
 };

/ Check if deferred is settled
isSettled:{[id]
    .tst._requireDeferred id;
    not ((first .tst.deferredStates[id;`state]) ~ `pending)
 };

/ Get state of deferred
getState:{[id]
    .tst._requireDeferred id;
    if[.tst._debug[]; -1 "DEBUG: getState called for ",string id];
    res: first .tst.deferredStates[id];
    if[.tst._debug[]; -1 "DEBUG: getState returning for ",string id];
    res
 };

/ Invoke a public niladic eventually condition as data.
.tst._callNiladic:{[cond] cond[] };

/ Poll a unary function applied to inert data until it returns boolean/long 1.
/ side effects: condition errors are treated as failed attempts and retried
.tst._eventuallyApply:{[cond;arg;timeout;interval]
    timeoutMs:.tst._validateMillis[timeout;"timeout"];
    intervalMs:.tst._validateMillis[interval;"interval"];
    start:.z.p;
    while[1b;
        result:@[cond;arg;{[e] 0b}];
        if[(result ~ 1b) or (result ~ `long$1); :1b];
        elapsed:0.000001*"f"$`long$.z.p-start;
        if[elapsed >= timeoutMs;
            '"Eventually timed out after ",string[timeoutMs],"ms"];
        .tst._sleepRemaining[intervalMs;timeoutMs-elapsed];
    ];
    1b
 };

/ Eventually: Poll a condition until it succeeds or times out
/ @param cond (lambda) Niladic condition to check (may throw while not ready)
/ @param timeoutMs (numeric) Finite non-negative timeout in milliseconds
/ @param intervalMs (numeric) Finite non-negative polling interval in milliseconds
/ @return (boolean) 1b if condition met, throws if timeout
eventually:{[cond;timeoutMs;intervalMs]
    .tst._eventuallyApply[.tst._callNiladic;cond;timeoutMs;intervalMs]
 };

/ Signal a rejection reason using the same public formatting as before.
.tst._raiseDeferredError:{[err]
    msg:$[-11h=type err; string err; 10h=type err; err; .tst.toString err];
    'msg
 };

/ Wait for and return one deferred result. The caller owns final cleanup.
.tst._awaitResult:{[id;timeoutMs]
    .tst._eventuallyApply[.tst.isSettled;id;timeoutMs;10];
    state:getState id;
    if[state[`state] ~ `resolved; :state[`val]];
    if[state[`state] ~ `rejected; .tst._raiseDeferredError state[`err]];
    '"Promise in unexpected state"
 };

.tst._captureAwait:{[id;timeoutMs]
    (1b;enlist .tst._awaitResult[id;timeoutMs])
 };

.tst._captureAwaitError:{[err]
    (0b;enlist err)
 };

/ Wait for a deferred to settle
/ @param id (symbol) Deferred ID
/ @param timeoutMs (numeric) Finite non-negative timeout in milliseconds
/ @return (any) Resolved value or throws if rejected/timeout
await:{[id;timeoutMs]
    .tst._requireDeferred id;
    outcome:.[.tst._captureAwait;(id;timeoutMs);.tst._captureAwaitError];
    .tst._forgetDeferred id;
    if[not first outcome;
        err:first last outcome;
        'err];
    first last outcome
 };

/ Callback test helper: Wraps a callback to track invocations
/ @param name (symbol) Name for the callback
/ @return (function) Wrapped callback that logs calls
callbackSpy:{[name]
    / Initialize call log if not exists
    if[not name in key .tst.callbackLogs; .tst.callbackLogs[name]: ()];
    
    / Return spy function
    {[name; args]
        .tst.callbackLogs[name],: enlist (.z.p; args);
        / Return args for passthrough
        args
    }[name;]
 };

/ Initialize callback logs
callbackLogs: ()!();

/ Get callback invocations
getCallbackCalls:{[name]
    $[name in key .tst.callbackLogs; .tst.callbackLogs[name]; ()]
 };

/ Clear callback logs
clearCallbackLogs:{[]
    .tst.callbackLogs:: ()!();
 };

\d .
::
