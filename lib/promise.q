\d .tst

/ Deferred handles combine a per-process GUID epoch with a monotonic 64-bit
/ generation. Active state remains bounded, handles never enter the symbol
/ table, and a released handle cannot be reused before counter exhaustion.
MAX_ACTIVE_DEFERREDS:1024;
MAX_REJECTION_CHARS:1024;
MAX_REJECTION_ITEMS:128;
MAX_REJECTION_NODES:1024;

/ Callback-spy retention limits are lowerable test seams. Their accessors below
/ enforce smaller embedded ceilings before names, calls, or arguments are kept.
MAX_CALLBACK_NAMES:64;
MAX_CALLBACK_CALLS:256;
MAX_CALLBACK_VALUE_ITEMS:64;
MAX_CALLBACK_TEXT_CHARS:512;

.tst._promiseCapture:{[path]
    (1b;enlist get path)
 };

.tst._promiseCaptureError:{[err]
    (0b;enlist err)
 };

.tst._promiseFail:{[message]
    if[not 10h=type message; '"Promise state is invalid"];
    '(4096&count message)#message
 };

.tst._promiseLimit:{[path;label;minimum;literalCeiling]
    outcome:@[
        .tst._promiseCapture;
        path;
        .tst._promiseCaptureError];
    if[not first outcome;
        .tst._promiseFail[label," safety limit is unavailable"]];
    limitValue:first last outcome;
    if[not type[limitValue] in -4 -5 -6 -7h;
        .tst._promiseFail[
            label," safety limit must be a finite integer scalar"]];
    if[null limitValue;
        .tst._promiseFail[
            label," safety limit must be a finite integer scalar"]];
    if[limitValue in (0Wh;-0Wh;0Wi;-0Wi;0W;-0W);
        .tst._promiseFail[label," safety limit must be finite"]];
    if[limitValue<minimum;
        .tst._promiseFail[label," safety limit is below its supported minimum"]];
    if[limitValue>literalCeiling;
        .tst._promiseFail[label," safety limit exceeds its literal ceiling"]];
    "j"$limitValue
 };

.tst._activeDeferredLimit:{[]
    .tst._promiseLimit[
        `.tst.MAX_ACTIVE_DEFERREDS;
        "active deferred";
        1;
        1024]
 };

.tst._rejectionTextLimit:{[]
    .tst._promiseLimit[
        `.tst.MAX_REJECTION_CHARS;
        "rejection diagnostic";
        16;
        4096]
 };

.tst._rejectionItemLimit:{[]
    .tst._promiseLimit[
        `.tst.MAX_REJECTION_ITEMS;
        "rejection item count";
        1;
        128]
 };

.tst._rejectionNodeLimit:{[]
    .tst._promiseLimit[
        `.tst.MAX_REJECTION_NODES;
        "rejection node count";
        1;
        1024]
 };

.tst._callbackNameLimit:{[]
    .tst._promiseLimit[
        `.tst.MAX_CALLBACK_NAMES;
        "callback name count";
        1;
        64]
 };

.tst._callbackCallLimit:{[]
    .tst._promiseLimit[
        `.tst.MAX_CALLBACK_CALLS;
        "callback call count";
        1;
        256]
 };

.tst._callbackItemLimit:{[]
    .tst._promiseLimit[
        `.tst.MAX_CALLBACK_VALUE_ITEMS;
        "callback value item count";
        1;
        64]
 };

.tst._callbackTextLimit:{[]
    .tst._promiseLimit[
        `.tst.MAX_CALLBACK_TEXT_CHARS;
        "callback text length";
        16;
        512]
 };

/ Return whether debug logging is enabled without assuming `.utl.DEBUG` exists.
.tst._debug:{[]
    1b~@[get;`.utl.DEBUG;{[err] 0b}]
 };

.tst._validatedDeferredEpoch:{[]
    outcome:@[
        .tst._promiseCapture;
        `.tst.deferredEpoch;
        .tst._promiseCaptureError];
    if[not first outcome;
        .tst._promiseFail["Deferred GUID epoch is unavailable"]];
    epoch:first last outcome;
    if[not -2h=type epoch;
        .tst._promiseFail["Deferred GUID epoch is corrupt"]];
    if[null epoch;
        .tst._promiseFail["Deferred GUID epoch is corrupt"]];
    epoch
 };

.tst._deferredEpochPrefix:{[]
    19#string .tst._validatedDeferredEpoch[]
 };

.tst._deferredIdHasEpoch:{[prefix;id]
    if[not -2h=type id; :0b];
    prefix~19#string id
 };

.tst._validDeferredRejection:{[rejectionValue]
    textLimit:.tst._rejectionTextLimit[];
    if[-11h=type rejectionValue; :1b];
    if[10h=type rejectionValue;
        :count[rejectionValue]<=textLimit];
    .tst._retainableRejection[
        rejectionValue;
        .tst._rejectionItemLimit[];
        .tst._rejectionNodeLimit[]]
 };

.tst._validDeferredState:{[stateTable]
    if[not 98h=type stateTable; :0b];
    if[not 1=count stateTable; :0b];
    if[not `state`val`err~cols stateTable; :0b];
    row:first stateTable;
    status:row`state;
    if[not -11h=type status; :0b];
    if[not status in `pending`resolved`rejected; :0b];
    if[`pending=status;
        :((::)~row`val) and ((::)~row`err)];
    if[`resolved=status; :((::)~row`err)];
    ((::)~row`val) and
        (.tst._validDeferredRejection row`err)
 };

.tst._validatedDeferredStore:{[]
    activeLimit:.tst._activeDeferredLimit[];
    prefix:.tst._deferredEpochPrefix[];
    outcome:@[
        .tst._promiseCapture;
        `.tst.deferredStates;
        .tst._promiseCaptureError];
    if[not first outcome;
        .tst._promiseFail["Deferred state registry is unavailable"]];
    store:first last outcome;
    if[not 99h=type store;
        .tst._promiseFail["Deferred state registry is corrupt"]];
    ids:key store;
    if[not type[ids] in 0 2h;
        .tst._promiseFail["Deferred state registry keys are corrupt"]];
    if[count[ids]>1024;
        .tst._promiseFail["Deferred state registry exceeds its literal ceiling"]];
    if[count[ids]>activeLimit;
        .tst._promiseFail["Deferred state registry exceeds its safety limit"]];
    if[count[ids]<>count distinct ids;
        .tst._promiseFail["Deferred state registry contains duplicate IDs"]];
    if[count ids;
        if[any null ids;
            .tst._promiseFail["Deferred state registry contains a null ID"]];
        if[not all .tst._deferredIdHasEpoch[prefix;] each ids;
            .tst._promiseFail[
                "Deferred state registry contains an invalid GUID epoch"]];
        if[not all .tst._validDeferredState each value store;
            .tst._promiseFail["Deferred state registry contains invalid state"]]];
    store
 };

.tst._validatedDeferredCounter:{[]
    outcome:@[
        .tst._promiseCapture;
        `.tst.deferredCounter;
        .tst._promiseCaptureError];
    if[not first outcome;
        .tst._promiseFail["Deferred counter is unavailable"]];
    counter:first last outcome;
    if[not type[counter] in -4 -5 -6 -7h;
        .tst._promiseFail["Deferred counter is corrupt"]];
    if[null counter;
        .tst._promiseFail["Deferred counter is corrupt"]];
    if[counter in (0Wh;-0Wh;0Wi;-0Wi;0W;-0W);
        .tst._promiseFail["Deferred counter is corrupt"]];
    if[(counter<1) or (counter>9223372036854775805);
        .tst._promiseFail[
            "Deferred counter is outside its non-wrapping generation range"]];
    "j"$counter
 };

.tst._deferredCounterHex:{[counter]
    if[not -7h=type counter;
        .tst._promiseFail["Deferred counter encoding requires a long scalar"]];
    if[null counter;
        .tst._promiseFail["Deferred counter encoding requires a finite value"]];
    if[counter in (0W;-0W);
        .tst._promiseFail["Deferred counter encoding requires a finite value"]];
    if[(counter<1) or (counter>9223372036854775805);
        .tst._promiseFail[
            "Deferred counter encoding is outside its generation range"]];
    bytes:0x0 vs counter;
    if[not ((4h=type bytes) and (8=count bytes));
        .tst._promiseFail["Deferred counter encoding failed"]];
    alphabet:"0123456789abcdef";
    encoded:raze flip
        (alphabet bytes div 16;alphabet bytes mod 16);
    if[not 16=count encoded;
        .tst._promiseFail["Deferred counter encoding failed"]];
    encoded
 };

.tst._deferredGuid:{[epoch;counter]
    if[not -2h=type epoch;
        .tst._promiseFail["Deferred GUID epoch is corrupt"]];
    if[null epoch;
        .tst._promiseFail["Deferred GUID epoch is corrupt"]];
    counterHex:.tst._deferredCounterHex counter;
    guidText:
        (19#string epoch),
        (4#counterHex),
        "-",
        4_counterHex;
    id:@[
        {"G"$x};
        guidText;
        {[err] .tst._promiseFail["Deferred GUID generation failed"]}];
    if[not -2h=type id;
        .tst._promiseFail["Deferred GUID generation failed"]];
    if[null id;
        .tst._promiseFail["Deferred GUID generation failed"]];
    id
 };

/ Allocate from a non-wrapping generation. Advance the counter before publishing
/ state so even a later registry-assignment failure cannot reuse the handle.
deferred:{[]
    activeLimit:.tst._activeDeferredLimit[];
    store:.tst._validatedDeferredStore[];
    counter:.tst._validatedDeferredCounter[];
    epoch:.tst._validatedDeferredEpoch[];
    if[count[store]>=activeLimit;
        .tst._promiseFail["Deferred capacity exhausted"]];
    id:.tst._deferredGuid[epoch;counter];
    if[id in key store;
        .tst._promiseFail[
            "Deferred generation would reuse an active handle"]];
    nextCounter:counter+1;
    nextStore:store;
    nextStore[id]:([] state:enlist `pending;
        val:enlist (::);
        err:enlist (::));
    .tst.deferredCounter::nextCounter;
    .tst.deferredStates::nextStore;
    if[.tst._debug[]; -1 "DEBUG: created deferred ",string id];
    id
 };

/ Validate an ID and its state without coercing, evaluating, or interning it.
.tst._requireDeferred:{[id]
    if[not -2h=type id; '"Unknown deferred"];
    store:.tst._validatedDeferredStore[];
    if[not id in key store; '"Unknown deferred"];
    if[not .tst._validDeferredState store[id];
        .tst._promiseFail["Deferred state is corrupt"]];
    id
 };

/ Best-effort cleanup is intentionally independent of configurable limits so a
/ lowered or poisoned seam cannot retain an otherwise identifiable entry.
.tst._forgetDeferred:{[id]
    if[not -2h=type id; :1b];
    outcome:@[
        .tst._promiseCapture;
        `.tst.deferredStates;
        .tst._promiseCaptureError];
    if[not first outcome; :0b];
    store:first last outcome;
    if[not 99h=type store; :0b];
    ids:key store;
    if[not type[ids] in 0 2h; :0b];
    if[count[ids]>1024; :0b];
    if[id in ids;
        remaining:id _ store;
        if[not count remaining; remaining:()!()];
        .tst.deferredStates::remaining];
    1b
 };

.tst._deferredTable:{[id]
    .tst._requireDeferred id;
    .tst.deferredStates[id]
 };

/ Settlement is single-shot and updates the validated registry transactionally.
resolve:{[id;resolvedValue]
    stateTable:.tst._deferredTable id;
    if[not `pending~first stateTable`state;
        '"Promise already settled"];
    nextState:stateTable;
    nextState[`state]:enlist `resolved;
    nextState[`val]:enlist resolvedValue;
    nextStore:.tst.deferredStates;
    nextStore[id]:nextState;
    .tst.deferredStates::nextStore;
    if[.tst._debug[]; -1 "DEBUG: resolved ",string id];
    (::)
 };

.tst._rejectionDescriptor:{[rejectionValue]
    "rejected value type ",
        string[type rejectionValue],
        " count ",
        string count rejectionValue
 };

.tst._promiseText:{[text;limit]
    (limit&count text)#text
 };

.tst._rejectionLeafSize:{[rejectionValue;itemLimit]
    valueType:type rejectionValue;
    if[valueType<0; :1];
    if[0h=valueType;
        if[count[rejectionValue]>itemLimit; :0N];
        if[all (0>type each rejectionValue); :1+count rejectionValue];
        :0N];
    if[not valueType in
        1 2 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19h;
        :0N];
    if[count[rejectionValue]>itemLimit; :0N];
    1+count rejectionValue
 };

/ Preserve small, shallow values exposed by getState while refusing recursive
/ or attacker-sized structures. Dicts are retained only when both vectors are
/ bounded homogeneous leaves.
.tst._retainableRejection:{[
        rejectionValue;
        itemLimit;
        nodeLimit]
    valueType:type rejectionValue;
    if[valueType<0; :1b];
    if[valueType in
        1 2 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19h;
        :count[rejectionValue]<=itemLimit];
    if[0h=valueType;
        if[count[rejectionValue]>itemLimit; :0b];
        sizes:.tst._rejectionLeafSize[;itemLimit] each rejectionValue;
        if[any null sizes; :0b];
        :sum[sizes]<=nodeLimit];
    if[99h=valueType;
        if[count[rejectionValue]>itemLimit; :0b];
        keySize:.tst._rejectionLeafSize[key rejectionValue;itemLimit];
        valueSize:.tst._rejectionLeafSize[value rejectionValue;itemLimit];
        if[(null keySize) or (null valueSize); :0b];
        :(keySize+valueSize)<=nodeLimit];
    0b
 };

/ Retain exact ordinary strings/symbols and bounded shallow values. Oversized or
/ recursive composites become a fixed shallow descriptor.
.tst._boundedRejection:{[rejectionValue]
    limit:.tst._rejectionTextLimit[];
    itemLimit:.tst._rejectionItemLimit[];
    nodeLimit:.tst._rejectionNodeLimit[];
    valueType:type rejectionValue;
    if[-11h=valueType; :rejectionValue];
    if[10h=valueType; :.tst._promiseText[rejectionValue;limit]];
    if[.tst._retainableRejection[
            rejectionValue;
            itemLimit;
            nodeLimit];
        :rejectionValue];
    .tst._promiseText[
        .tst._rejectionDescriptor rejectionValue;
        limit]
 };

reject:{[id;rejectionValue]
    stateTable:.tst._deferredTable id;
    if[not `pending~first stateTable`state;
        '"Promise already settled"];
    retained:.tst._boundedRejection rejectionValue;
    nextState:stateTable;
    nextState[`state]:enlist `rejected;
    nextState[`err]:enlist retained;
    nextStore:.tst.deferredStates;
    nextStore[id]:nextState;
    .tst.deferredStates::nextStore;
    if[.tst._debug[]; -1 "DEBUG: rejected ",string id];
    (::)
 };

isSettled:{[id]
    stateTable:.tst._deferredTable id;
    not `pending~first stateTable`state
 };

getState:{[id]
    stateTable:.tst._deferredTable id;
    first stateTable
 };

/ Invoke a public niladic eventually condition as inert data.
.tst._callNiladic:{[condition]
    condition[]
 };

.tst._pollOutcome:{[condition;argument]
    (1b;enlist condition argument)
 };

.tst._pollError:{[err]
    (0b;enlist err)
 };

/ Poll one unary callable within both wall-clock and fixed attempt budgets.
/ `retryErrors` preserves eventually's historical retry-on-condition-error rule.
.tst._eventuallyPoll:{[
        condition;
        argument;
        timeout;
        interval;
        retryErrors;
        label]
    timeoutMs:.tst._validateMillis[timeout;"timeout"];
    intervalMs:.tst._validateMillis[interval;"interval"];
    condition:.tst._validateAsyncCallableArity[condition;label;1];
    if[not -1h=type retryErrors;
        .tst._promiseFail["retryErrors must be a boolean scalar"]];
    attemptLimit:.tst._asyncAttemptLimit[];
    errorLimit:.tst._asyncErrorLimit[];
    start:.z.p;
    attempts:0;
    while[1b;
        outcome:.[
            .tst._pollOutcome;
            (condition;argument);
            .tst._pollError];
        attempts+:1;
        if[first outcome;
            if[.tst._conditionResult[first last outcome;label]; :1b]];
        if[(not first outcome) and (not retryErrors);
            'label," failed: ",
                .tst._asyncErrorText[first last outcome;errorLimit]];
        elapsed:0.000001*"f"$`long$.z.p-start;
        if[elapsed>=timeoutMs;
            '"Eventually timed out after ",string[timeoutMs],"ms"];
        if[attempts>=attemptLimit;
            '"Eventually exceeded async attempt safety limit"];
        .tst._sleepRemaining[intervalMs;timeoutMs-elapsed];
    ];
    1b
 };

.tst._eventuallyApply:{[condition;argument;timeout;interval]
    .tst._eventuallyPoll[
        condition;
        argument;
        timeout;
        interval;
        1b;
        "eventually condition"]
 };

eventually:{[condition;timeoutMs;intervalMs]
    .tst._validateMillis[timeoutMs;"timeout"];
    .tst._validateMillis[intervalMs;"interval"];
    condition:.tst._validateAsyncCallable[
        condition;
        "eventually condition"];
    .tst._eventuallyApply[
        .tst._callNiladic;
        condition;
        timeoutMs;
        intervalMs]
 };

.tst._rejectionMessage:{[rejectionValue]
    limit:.tst._rejectionTextLimit[];
    valueType:type rejectionValue;
    if[-11h=valueType;
        :"rejected symbol value"];
    if[10h=valueType;
        :.tst._promiseText[rejectionValue;limit]];
    if[(valueType<0) and (valueType>=-19);
        :.tst._promiseText[string rejectionValue;limit]];
    .tst._promiseText[
        .tst._rejectionDescriptor rejectionValue;
        limit]
 };

.tst._raiseDeferredError:{[rejectionValue]
    '.tst._rejectionMessage rejectionValue
 };

.tst._awaitResult:{[id;timeoutMs]
    .tst._requireDeferred id;
    .tst._eventuallyPoll[
        .tst.isSettled;
        id;
        timeoutMs;
        10;
        0b;
        "deferred state"];
    state:.tst.getState id;
    if[state[`state]~`resolved; :state`val];
    if[state[`state]~`rejected;
        .tst._raiseDeferredError state`err];
    .tst._promiseFail["Deferred settled in an unexpected state"]
 };

.tst._captureAwait:{[id;timeoutMs]
    (1b;enlist .tst._awaitResult[id;timeoutMs])
 };

.tst._captureAwaitError:{[err]
    (0b;enlist err)
 };

.tst._captureForget:{[id]
    (1b;enlist .tst._forgetDeferred id)
 };

/ Await always attempts cleanup. A cleanup problem is reported only when there
/ is no primary rejection/timeout/validation error to preserve.
await:{[id;timeoutMs]
    outcome:.[
        .tst._captureAwait;
        (id;timeoutMs);
        .tst._captureAwaitError];
    cleanup:@[
        .tst._captureForget;
        id;
        .tst._captureAwaitError];
    cleanupOk:(first cleanup) and (1b~first last cleanup);
    if[not first outcome; 'first last outcome];
    if[not cleanupOk;
        .tst._promiseFail["Deferred cleanup failed"]];
    first last outcome
 };

.tst._validateCallbackName:{[name]
    if[not -11h=type name;
        .tst._promiseFail["Callback name must be a symbol scalar"]];
    if[null name;
        .tst._promiseFail["Callback name must not be empty"]];
    name
 };

.tst._callbackSentinel:{[]
    (enlist `callbackLogSaturated)!enlist 1b
 };

.tst._isCallbackSentinelValue:{[retainedValue]
    if[not 99h=type retainedValue; :0b];
    if[not 1=count retainedValue; :0b];
    sentinelKeys:key retainedValue;
    if[not 11h=type sentinelKeys; :0b];
    if[not 1=count sentinelKeys; :0b];
    if[not `callbackLogSaturated~first sentinelKeys; :0b];
    sentinelValues:value retainedValue;
    if[not 1h=type sentinelValues; :0b];
    if[not 1=count sentinelValues; :0b];
    1b~first sentinelValues
 };

.tst._validRetainedCallbackValue:{[retainedValue;itemLimit;textLimit]
    valueType:type retainedValue;
    if[valueType<0; :1b];
    if[10h=valueType; :count[retainedValue]<=textLimit];
    if[valueType in
        1 2 4 5 6 7 8 9 11 12 13 14 15 16 17 18 19h;
        :count[retainedValue]<=itemLimit];
    if[99h=valueType; :.tst._isCallbackSentinelValue retainedValue];
    0b
 };

.tst._validCallbackRecord:{[record;itemLimit;textLimit]
    if[not ((0h=type record) and (2=count record)); :0b];
    if[not -12h=type first record; :0b];
    .tst._validRetainedCallbackValue[
        record 1;
        itemLimit;
        textLimit]
 };

.tst._validCallbackCallList:{[
        calls;
        callLimit;
        itemLimit;
        textLimit]
    if[not 0h=type calls; :0b];
    if[count[calls]>callLimit; :0b];
    if[not count calls; :1b];
    all .tst._validCallbackRecord[;itemLimit;textLimit] each calls
 };

.tst._validatedCallbackLogs:{[]
    nameLimit:.tst._callbackNameLimit[];
    callLimit:.tst._callbackCallLimit[];
    itemLimit:.tst._callbackItemLimit[];
    textLimit:.tst._callbackTextLimit[];
    outcome:@[
        .tst._promiseCapture;
        `.tst.callbackLogs;
        .tst._promiseCaptureError];
    if[not first outcome;
        .tst._promiseFail["Callback log registry is unavailable"]];
    logs:first last outcome;
    if[not 99h=type logs;
        .tst._promiseFail["Callback log registry is corrupt"]];
    names:key logs;
    if[not type[names] in 0 11h;
        .tst._promiseFail["Callback log names are corrupt"]];
    if[count[names]>nameLimit;
        .tst._promiseFail["Callback log registry exceeds its safety limit"]];
    if[count[names]<>count distinct names;
        .tst._promiseFail["Callback log registry contains duplicate names"]];
    if[count names;
        if[any null names;
            .tst._promiseFail[
                "Callback log registry contains an empty name"]];
        callLists:value logs;
        if[not all .tst._validCallbackCallList[
                ;callLimit;itemLimit;textLimit] each callLists;
            .tst._promiseFail["Callback call log is corrupt"]]];
    logs
 };

/ q's negative GUID deal is the production form: it derives entropy from
/ process properties and current time instead of consuming the deterministic
/ main-thread RNG stream used by roll (`?`). A fresh epoch is generated only
/ when all correlated deferred globals are absent.
.tst._newDeferredEpoch:{[]
    epoch:@[
        {[ignored] first -1?0Ng};
        ::;
        {[err]
            .tst._promiseFail[
                "Deferred GUID epoch generation failed"]}];
    if[not -2h=type epoch;
        .tst._promiseFail["Deferred GUID epoch generation failed"]];
    if[null epoch;
        .tst._promiseFail["Deferred GUID epoch generation failed"]];
    epoch
 };

/ Module loading is idempotent. Validate every existing component before
/ writing anything; partial or corrupt state is left untouched as evidence and
/ the reload fails closed. Only a wholly absent deferred triple or callback
/ registry is initialized.
.tst._initializePromiseRuntime:{[]
    deferredPaths:
        `.tst.deferredEpoch,
        `.tst.deferredStates,
        `.tst.deferredCounter;
    deferredOutcomes:{
        @[.tst._promiseCapture;x;.tst._promiseCaptureError]
    } each deferredPaths;
    deferredPresent:first each deferredOutcomes;
    if[(any deferredPresent) and (not all deferredPresent);
        .tst._promiseFail[
            "Deferred runtime initialization is incomplete"]];
    hasDeferred:all deferredPresent;

    callbackOutcome:@[
        .tst._promiseCapture;
        `.tst.callbackLogs;
        .tst._promiseCaptureError];
    hasCallback:first callbackOutcome;

    / These validators are read-only and run before either missing component is
    / created, so a corrupt existing registry cannot be silently overwritten.
    if[hasDeferred;
        .tst._validatedDeferredEpoch[];
        .tst._validatedDeferredCounter[];
        .tst._validatedDeferredStore[]];
    if[hasCallback;
        .tst._validatedCallbackLogs[]];

    newEpoch:(::);
    if[not hasDeferred;
        newEpoch:.tst._newDeferredEpoch[]];
    if[not hasDeferred;
        .tst.deferredEpoch::newEpoch;
        .tst.deferredStates::()!();
        .tst.deferredCounter::1];
    if[not hasCallback;
        .tst.callbackLogs::()!()];
    (::)
 };

.tst._callbackValueDescriptor:{[callbackValue]
    "callback value type ",
        string[type callbackValue],
        " count ",
        string count callbackValue
 };

/ Preserve ordinary scalars and small homogeneous vectors. Complex or oversized
/ values are retained only as a shallow descriptor.
.tst._boundedCallbackValue:{[callbackValue]
    itemLimit:.tst._callbackItemLimit[];
    textLimit:.tst._callbackTextLimit[];
    valueType:type callbackValue;
    if[valueType<0; :callbackValue];
    if[10h=valueType;
        if[count[callbackValue]<=textLimit; :callbackValue];
        :.tst._promiseText[
            .tst._callbackValueDescriptor callbackValue;
            textLimit]];
    if[valueType in
        1 2 4 5 6 7 8 9 11 12 13 14 15 16 17 18 19h;
        if[count[callbackValue]<=itemLimit; :callbackValue]];
    .tst._promiseText[
        .tst._callbackValueDescriptor callbackValue;
        textLimit]
 };

.tst._isCallbackSentinelRecord:{[record]
    if[not ((0h=type record) and (2=count record)); :0b];
    .tst._isCallbackSentinelValue record 1
 };

.tst._recordCallback:{[name;callbackValue]
    name:.tst._validateCallbackName name;
    logs:.tst._validatedCallbackLogs[];
    nameLimit:.tst._callbackNameLimit[];
    callLimit:.tst._callbackCallLimit[];
    if[not name in key logs;
        if[count[logs]>=nameLimit;
            .tst._promiseFail["Callback log name capacity exhausted"]];
        logs[name]:()];
    calls:logs[name];
    saturated:$[
        count calls;
        .tst._isCallbackSentinelRecord last calls;
        0b];
    if[saturated; :callbackValue];
    if[count[calls]<callLimit;
        retained:.tst._boundedCallbackValue callbackValue;
        logs[name],:enlist (.z.p;retained);
        .tst.callbackLogs::logs;
        :callbackValue];
    sentinel:(.z.p;.tst._callbackSentinel[]);
    logs[name]:$[
        1=callLimit;
        enlist sentinel;
        ((callLimit-1)#calls),enlist sentinel];
    .tst.callbackLogs::logs;
    callbackValue
 };

/ Wrap a unary callback and retain bounded invocation diagnostics.
callbackSpy:{[name]
    name:.tst._validateCallbackName name;
    logs:.tst._validatedCallbackLogs[];
    if[not name in key logs;
        nameLimit:.tst._callbackNameLimit[];
        if[count[logs]>=nameLimit;
            .tst._promiseFail["Callback log name capacity exhausted"]];
        logs[name]:();
        .tst.callbackLogs::logs];
    {[callbackName;callbackValue]
        .tst._recordCallback[callbackName;callbackValue]
    }[name;]
 };

getCallbackCalls:{[name]
    name:.tst._validateCallbackName name;
    logs:.tst._validatedCallbackLogs[];
    $[name in key logs;logs[name];()]
 };

/ Clearing is recovery-safe even when the prior registry or a seam is corrupt.
clearCallbackLogs:{[]
    .tst.callbackLogs::()!();
    (::)
 };

\d .
.tst._initializePromiseRuntime[];
::
