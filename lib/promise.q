\d .tst

/ Initialize deferred states dictionary and counter

deferredStates: ()!();

deferredCounter: 0j;

/ Normalize the v2 opaque long handle. Legacy `def_N symbols remain accepted
/ at API boundaries, but new deferreds never intern a per-request symbol.
deferredKey:{[id]
    if[(type id) in -5 -6 -7h; :"j"$id];
    if[-11h=type id;
        text:string id;
        if[text like "def_*";
            parsed:@[{"J"$x};4_text;{0Nj}];
            if[not null parsed;:parsed];
        ];
    ];
    0Nj
 };

/ Explicit source-compatibility adapter for callers that must expose the old
/ printable spelling. This is opt-in because constructing it interns a symbol.
legacyDeferredHandle:{[id]
    keyValue:.tst.deferredKey id;
    if[null keyValue;'"Unknown deferred"];
    `$"def_",string keyValue
 };

dropDeferred:{[id]
    keyValue:.tst.deferredKey id;
    if[(not null keyValue) and keyValue in key .tst.deferredStates;
        .tst.deferredStates:: (enlist keyValue) _ .tst.deferredStates];
    ::
 };

clearDeferreds:{[]
    .tst.deferredStates:: ()!();
    ::
 };



/ Promise-like deferred object for managing async state

/ Uses global state dictionary for mutability

/ @return (long) Opaque deferred handle

deferred:{[]

    if[@[get; `.utl.DEBUG; 0b]; -1 "DEBUG: deferred called"];

    / Generate a unique numeric handle without growing q's interned symbol pool.
    id: .tst.deferredCounter;

    .tst.deferredCounter +: 1;

    if[@[get; `.utl.DEBUG; 0b]; -1 "DEBUG: new id is ",string id];

    

    / Initialize state in global dict
    if[@[get; `.utl.DEBUG; 0b];
        -1 "DEBUG: deferredStates type ", string type .tst.deferredStates;
        -1 "DEBUG: deferredStates value type ", string type value .tst.deferredStates
    ];
    .tst.deferredStates[id]: ([] state: enlist `pending; val: enlist (::); err: enlist (::));

    if[@[get; `.utl.DEBUG; 0b]; -1 "DEBUG: deferredStates updated"];

    

    / Return ID

    id

 };



/ Resolve a deferred with a value  

resolve:{[id;v]

    id: .tst.deferredKey id;

    if[@[get; `.utl.DEBUG; 0b]; -1 "DEBUG: resolve called for ",string id];

    if[not id in key .tst.deferredStates;
        if[@[get; `.utl.DEBUG; 0b]; -1 "DEBUG: Unknown deferred ",string id];
        '"Unknown deferred"
    ];

    state: .tst.deferredStates[id];
    if[not ((first state[`state]) ~ `pending);
        if[@[get; `.utl.DEBUG; 0b]; -1 "DEBUG: Already settled"];
        '"Promise already settled"
    ];

    .tst.deferredStates[id;`state]: enlist `resolved;
    .tst.deferredStates[id;`val]: enlist v;

    if[@[get; `.utl.DEBUG; 0b]; -1 "DEBUG: resolved ",string id];

 };



/ Reject a deferred with an error

reject:{[id;e]

    id: .tst.deferredKey id;

    if[@[get; `.utl.DEBUG; 0b]; -1 "DEBUG: reject called for ",string id];

    if[not id in key .tst.deferredStates;
        if[@[get; `.utl.DEBUG; 0b]; -1 "DEBUG: Unknown deferred ",string id];
        '"Unknown deferred"
    ];

    state: .tst.deferredStates[id];

    if[not ((first state[`state]) ~ `pending);
        if[@[get; `.utl.DEBUG; 0b]; -1 "DEBUG: Already settled"];
        '"Promise already settled"
    ];

    .tst.deferredStates[id;`state]: enlist `rejected;
    .tst.deferredStates[id;`err]: enlist e;

    if[@[get; `.utl.DEBUG; 0b]; -1 "DEBUG: rejected ",string id];

 };



/ Check if deferred is settled

isSettled:{[id]

    id: .tst.deferredKey id;

    if[null id; :0b];
    if[not id in key .tst.deferredStates; :0b];

    not ((first .tst.deferredStates[id;`state]) ~ `pending)

 };



/ Get state of deferred

getState:{[id]

    id: .tst.deferredKey id;

    if[@[get; `.utl.DEBUG; 0b]; -1 "DEBUG: getState called for ",string id];

    if[not id in key .tst.deferredStates;
        if[@[get; `.utl.DEBUG; 0b]; -1 "DEBUG: Unknown deferred ",string id];
        '"Unknown deferred"
    ];

    res: first .tst.deferredStates[id];

    if[@[get; `.utl.DEBUG; 0b]; -1 "DEBUG: getState returning for ",string id];

    res

 };



/ Eventually: Poll a condition until it succeeds or times out
/ @param cond (lambda) Condition to check (should return boolean or throw)
/ @param timeoutMs (long) Timeout in milliseconds (default: 5000)
/ @param intervalMs (long) Polling interval in milliseconds (default: 100)
/ @return (boolean) 1b if condition met, throws if timeout
eventually:{[cond; timeoutMs; intervalMs]
    / Set defaults
    if[null timeoutMs; timeoutMs: 5000];
    if[null intervalMs; intervalMs: 100];
    
    startTime: .z.p;
    timeout: startTime + `long$timeoutMs * 1000000; / Convert ms to ns as long
    intervalSec: intervalMs % 1000.0; / Convert to seconds for system sleep
    
    / Poll until condition succeeds or timeout
    while[1b;
        / Try the condition
        result: @[cond; ::; {`error}];
        
        / If succeeded, return true
        if[(result ~ 1b) or (result ~ `long$1); :1b];
        
        / Check timeout
        if[.z.p > timeout; 
            '"Eventually timed out after ", string[timeoutMs], "ms"
        ];
        
        / Sleep for interval
        .tst.sleep[intervalMs];
    ];
    
    1b
 };

/ Wait for a deferred to settle
/ @param id (long, or legacy def_N symbol) Deferred ID
/ @param timeoutMs (long) Timeout in milliseconds
/ @return (any) Resolved value or throws if rejected/timeout
await:{[id; timeoutMs]
    if[null timeoutMs; timeoutMs: 5000];
    id: .tst.deferredKey id;
    if[null id;'"Unknown deferred"];

    / Poll directly. Besides avoiding dynamic source evaluation, this works for
    / opaque numeric handles and legacy adapters alike.
    startTime: .z.p;
    timeout: startTime + "j"$timeoutMs * 1000000;
    while[not .tst.isSettled id;
        if[.z.p > timeout;'"Eventually timed out after ",string[timeoutMs],"ms"];
        .tst.sleep 10;
    ];
    
    / Get final state
    state: .tst.getState[id];
    / Await is consuming: once the result has been copied locally, delete its
    / registry row before returning or re-throwing the rejection.
    .tst.dropDeferred id;
    
    / Return value or throw error
    $[state[`state] ~ `resolved;
        state[`val];
        state[`state] ~ `rejected;
        [err: state[`err]; '$[-11h = type err; string err; 10h = type err; err; .tst.toString err]];
        '"Promise in unexpected state"
    ]
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
