\d .tst

/ Initialize deferred states dictionary and counter

deferredStates: ()!();

deferredCounter: 0;



/ Promise-like deferred object for managing async state

/ Uses global state dictionary for mutability

/ @return (symbol) Deferred ID

deferred:{[]

    if[@[get; `.utl.DEBUG; 0b]; -1 "DEBUG: deferred called"];

    / Generate unique ID from counter

    id: `$ "def_", string .tst.deferredCounter;

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

    if[not id in key .tst.deferredStates; :0b];

    not ((first .tst.deferredStates[id;`state]) ~ `pending)

 };



/ Get state of deferred

getState:{[id]

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
/ @param id (symbol) Deferred ID
/ @param timeoutMs (long) Timeout in milliseconds
/ @return (any) Resolved value or throws if rejected/timeout
await:{[id; timeoutMs]
    if[null timeoutMs; timeoutMs: 5000];
    
    / Poll until settled (build niladic function with bound id)
    checkFn: value raze ("{ .tst.isSettled[`"; string id; "] }");
    eventually[checkFn; timeoutMs; 10];
    
    / Get final state
    state: .tst.getState[id];
    
    / Return value or throw error
    $[state[`state] ~ `resolved;
        state[`val];
        state[`state] ~ `rejected;
        'string state[`err];
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
