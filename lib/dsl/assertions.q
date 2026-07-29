/ assertions.q - core assertion DSL (musteq, mustthrow, snapshots, aliases)
\d .tst

/ Lowerable test seams; literal ceilings remain authoritative.
.tst.THROW_MAX_PATTERNS:32;
.tst.THROW_MAX_PATTERN_CHARS:256;
.tst.THROW_MAX_PATTERN_TOTAL:2048;
.tst.ORDER_ASSERT_MAX_ITEMS:10000;
.tst.ORDER_ASSERT_MAX_COLUMNS:256;
.tst.ORDER_ASSERT_MAX_CELLS:1048576;
.tst.INCLUDE_COLS_MAX_COLUMNS:1024;
.tst.INCLUDE_COLS_MAX_ROWS:100000;
.tst.INCLUDE_COLS_MAX_CELLS:1048576;
.tst.SPY_ASSERT_MAX_NAMES:10000;
.tst.SPY_ASSERT_MAX_CALLS:100000;
.tst.SPY_ASSERT_MAX_COMPARE_ITEMS:1048576;
.tst.ASSERT_FAILURE_MAX_COUNT:100;
.tst.ASSERT_FAILURE_MAX_CHARS:200000;
.tst.ASSERT_PREDICATE_MAX_ITEMS:1048576;
.tst.ASSERT_PREDICATE_MAX_DEPTH:4;
.tst.ASSERT_PREDICATE_MAX_NESTED_CHILDREN:4096;

.tst.assertMessageLimit:{[]
    .tst.safeDiagnosticBudget[
        `.tst.output.reportLimit;
        50000;
        50000]
 };

.tst.assertBudget:{[name;default;hardMax]
    .tst.safeDiagnosticBudget[name;default;hardMax]
 };

.tst.throwPatternCountLimit:{[]
    .tst.assertBudget[`.tst.THROW_MAX_PATTERNS;32;32]
 };

.tst.throwPatternCharLimit:{[]
    .tst.assertBudget[`.tst.THROW_MAX_PATTERN_CHARS;256;256]
 };

.tst.throwPatternTotalLimit:{[]
    .tst.assertBudget[`.tst.THROW_MAX_PATTERN_TOTAL;2048;2048]
 };

.tst.orderItemLimit:{[]
    .tst.assertBudget[`.tst.ORDER_ASSERT_MAX_ITEMS;10000;10000]
 };

.tst.orderColumnLimit:{[]
    .tst.assertBudget[`.tst.ORDER_ASSERT_MAX_COLUMNS;256;256]
 };

.tst.orderCellLimit:{[]
    .tst.assertBudget[
        `.tst.ORDER_ASSERT_MAX_CELLS;
        1048576;
        1048576]
 };

.tst.includeColumnLimit:{[]
    .tst.assertBudget[`.tst.INCLUDE_COLS_MAX_COLUMNS;1024;1024]
 };

.tst.includeRowLimit:{[]
    .tst.assertBudget[`.tst.INCLUDE_COLS_MAX_ROWS;100000;100000]
 };

.tst.includeCellLimit:{[]
    .tst.assertBudget[
        `.tst.INCLUDE_COLS_MAX_CELLS;
        1048576;
        1048576]
 };

.tst.spyNameLimit:{[]
    .tst.assertBudget[`.tst.SPY_ASSERT_MAX_NAMES;10000;10000]
 };

.tst.spyCallLimit:{[]
    .tst.assertBudget[`.tst.SPY_ASSERT_MAX_CALLS;100000;100000]
 };

.tst.spyCompareLimit:{[]
    .tst.assertBudget[
        `.tst.SPY_ASSERT_MAX_COMPARE_ITEMS;
        1048576;
        1048576]
 };

.tst.assertFailureCountLimit:{[]
    1 | .tst.assertBudget[
        `.tst.ASSERT_FAILURE_MAX_COUNT;
        100;
        100]
 };

.tst.assertFailureCharLimit:{[]
    64 | .tst.assertBudget[
        `.tst.ASSERT_FAILURE_MAX_CHARS;
        200000;
        200000]
 };

.tst.assertPredicateItemLimit:{[]
    1 | .tst.assertBudget[
        `.tst.ASSERT_PREDICATE_MAX_ITEMS;
        1048576;
        1048576]
 };

.tst.assertPredicateDepthLimit:{[]
    .tst.assertBudget[
        `.tst.ASSERT_PREDICATE_MAX_DEPTH;
        4;
        4]
 };

.tst.assertPredicateNestedChildLimit:{[]
    1 | .tst.assertBudget[
        `.tst.ASSERT_PREDICATE_MAX_NESTED_CHILDREN;
        4096;
        4096]
 };

/ Apply a function and wrap its return outside the user-controlled result. A
/ normal return may contain either tag but remains nested beneath `ok.
.tst.assertCapture:{[fn;args]
    .[
        {[callable;argv]
            answer:callable . argv;
            (`ok;enlist answer)
          };
        (fn;args);
        {[err] (`error;enlist err)}]
 };

.tst.assertErrorText:{[err]
    $[
        10h=type err;
        .tst.capString[err;512];
        .tst.renderValue[err;512]]
 };

.tst.assertMessageValue:{[message]
    limit:.tst.assertMessageLimit[];
    if[10h=type message; :.tst.capString[message;limit]];
    if[-10h=type message; :.tst.capString[enlist message;limit]];
    .tst.renderValue[message;limit]
 };

.tst.assertFailureMarker:
    "(additional assertion failures omitted by diagnostic budget)";
.tst.assertStateCorruptionMarker:
    "(assertion state corrupted; test treated as failed)";

.tst.assertRunMax:{[] 1000000};
.tst.assertCorruptionCount:{[] 1};

.tst.assertCounterValid:{[current]
    valid:(type current) in -5 -6 -7h;
    if[not valid; :0b];
    if[null current; :0b];
    if[current in (0Wh;-0Wh;0Wi;-0Wi;0W;-0W); :0b];
    0<=current
 };

.tst.assertInstallCorruptionState:{[]
    .tst.assertState:``failures`assertsRun!(
        ::;
        enlist .tst.assertStateCorruptionMarker;
        .tst.assertCorruptionCount[]);
    ::
 };

.tst.assertEnsureState:{[]
    state:@[get;`.tst.assertState;{[err] ()!()}];
    if[99h<>type state;
        .tst.assertInstallCorruptionState[];
        :0b
    ];
    stateKeys:@[key;state;{[err] ()}];
    if[
        (11h<>type stateKeys) or
        (16<count stateKeys);
        .tst.assertInstallCorruptionState[];
        :0b
    ];
    if[not all (`failures`assertsRun in stateKeys);
        .tst.assertInstallCorruptionState[];
        :0b
    ];
    failures:@[
        {[input] input`failures};
        state;
        {[err] ::}];
    counter:@[
        {[input] input`assertsRun};
        state;
        {[err] ::}];
    if[10h=type failures;
        failures:enlist failures;
        .tst.assertState.failures:failures];
    if[
        (0h<>type failures) or
        not .tst.assertCounterValid counter;
        .tst.assertInstallCorruptionState[];
        :0b
    ];
    counter:"j"$counter;
    .tst.assertState.assertsRun:
        counter & .tst.assertRunMax[];
    1b
 };

.tst.assertTerminalFailure:{[item]
    if[10h<>type item; :0b];
    (item~.tst.assertFailureMarker) or
        item~.tst.assertStateCorruptionMarker
 };

.tst.assertFailuresTerminal:{[failures]
    if[10h=type failures;
        :.tst.assertTerminalFailure failures];
    if[0h<>type failures; :0b];
    if[0=count failures; :0b];
    item:@[last;failures;{[err] ::}];
    .tst.assertTerminalFailure item
 };

.tst.assertFailuresCorrupted:{[failures]
    if[10h=type failures;
        :failures~.tst.assertStateCorruptionMarker];
    if[0h<>type failures; :1b];
    if[0=count failures; :0b];
    item:@[last;failures;{[err] ::}];
    (10h=type item) and
        item~.tst.assertStateCorruptionMarker
 };

/ Normalize at most the retained diagnostic budget. Existing malformed or
/ oversized state is not trusted and cannot make the cleanup pass unbounded.
.tst.assertNormalizeFailures:{[]
    countLimit:.tst.assertFailureCountLimit[];
    charLimit:.tst.assertFailureCharLimit[];
    detailLimit:0 | countLimit-1;
    marker:.tst.assertFailureMarker;
    reserve:count marker;
    raw:@[
        get;
        `.tst.assertState.failures;
        {[err] ()}];
    if[10h=type raw; raw:enlist raw];
    malformed:not 0h=type raw;
    if[malformed; raw:()];
    rawCount:count raw;
    takeN:rawCount & detailLimit;
    out:();
    used:0;
    omitted:malformed or rawCount>takeN;
    stop:malformed;
    i:0;
    while[(i<takeN) and not stop;
        item:raw i;
        if[.tst.assertTerminalFailure item;
            room:charLimit-used;
            if[0<room;
                capped:.tst.capString[item;room];
                if[0<count capped;
                    out,:enlist capped;
                    used+:count capped]];
            omitted:1b;
            stop:1b];
        if[not stop;
            textState:.tst.assertCapture[
                {[existing]
                    $[
                        10h=type existing;
                        existing;
                        .tst.renderValue[
                            existing;
                            .tst.assertMessageLimit[]]]
                  };
                enlist item];
            text:$[
                `ok~first textState;
                first last textState;
                "(existing assertion failure could not be rendered)"];
            room:(charLimit-used)-reserve;
            if[0>=room;
                omitted:1b;
                stop:1b];
            if[0<room;
                capped:.tst.capString[
                    text;
                    room & .tst.assertMessageLimit[]];
                if[0=count capped;
                    omitted:1b;
                    stop:1b];
                if[0<count capped;
                    out,:enlist capped;
                    used+:count capped]];
        ];
        i+:1;
    ];
    `failures`used`omitted!(out;used;omitted)
 };

.tst.assertAppendFailureMarker:{[failures;used]
    if[.tst.assertFailuresTerminal failures; :failures];
    charLimit:.tst.assertFailureCharLimit[];
    room:charLimit-used;
    if[0>=room; :failures];
    marker:.tst.capString[.tst.assertFailureMarker;room];
    if[0=count marker; :failures];
    failures,enlist marker
 };

.tst.assertRecordFailure:{[context;message]
    .tst.assertEnsureState[];
    raw:@[
        get;
        `.tst.assertState.failures;
        {[err] ()}];
    if[.tst.assertFailuresTerminal raw; :()];
    normalized:.tst.assertNormalizeFailures[];
    failures:normalized`failures;
    used:normalized`used;
    omitted:normalized`omitted;
    countLimit:.tst.assertFailureCountLimit[];
    charLimit:.tst.assertFailureCharLimit[];
    detailLimit:0 | countLimit-1;
    room:(charLimit-used)-count .tst.assertFailureMarker;
    if[
        omitted or
        (count[failures]>=detailLimit) or
        (0>=room);
        .tst.assertState.failures:
            .tst.assertAppendFailureMarker[failures;used];
        :()
    ];
    limit:.tst.assertMessageLimit[];
    renderedState:.tst.assertCapture[
        {[msg] .tst.assertMessageValue msg};
        enlist message];
    rendered:$[
        `ok~first renderedState;
        first last renderedState;
        context," failed (message rendering unavailable: ",
            .tst.assertErrorText[first last renderedState],")"];
    if[not 10h=type rendered;
        rendered:context," failed (message unavailable)"];
    capped:.tst.capString[rendered;room & limit];
    if[0=count capped;
        .tst.assertState.failures:
            .tst.assertAppendFailureMarker[failures;used];
        :()
    ];
    failures,:enlist capped;
    .tst.assertState.failures:failures;
    ::
 };

.tst.assertStateSnapshot:{[]
    .tst.assertEnsureState[];
    normalized:.tst.assertNormalizeFailures[];
    failures:normalized`failures;
    if[normalized`omitted;
        failures:.tst.assertAppendFailureMarker[
            failures;
            normalized`used]];
    .tst.assertState.failures:failures;
    `failures`assertsRun!(
        failures;
        .tst.assertState.assertsRun)
 };

.tst.assertBegin:{[]
    .tst.assertEnsureState[];
    current:.tst.assertState.assertsRun;
    maxCount:.tst.assertRunMax[];
    .tst.assertState.assertsRun:
        $[current<maxCount;current+1;maxCount];
    ::
 };

.tst.assertPredicateCostResult:{[safe;used]
    `safe`used!(safe;used)
 };

.tst.assertPredicateTableCost:{[table;remaining]
    flat:@[.tst.diffFlatTable;table;{[err] 0b}];
    if[not flat;
        :.tst.assertPredicateCostResult[0b;1]];
    columnNames:@[cols;table;{[err] ()}];
    rows:@[count;table;{[err] -1}];
    if[0>rows;
        :.tst.assertPredicateCostResult[0b;1]];
    ncols:count columnNames;
    cost:1+ncols+(ncols*rows);
    .tst.assertPredicateCostResult[cost<=remaining;cost]
 };

.tst.assertPredicateDictCost:{[dictionary;depth;remaining]
    flat:@[.tst.diffFlatDict;dictionary;{[err] 0b}];
    if[not flat;
        :.tst.assertPredicateCostResult[0b;1]];
    layout:@[
        {[input] (key input;value input)};
        dictionary;
        {[err] ()}];
    if[2<>count layout;
        :.tst.assertPredicateCostResult[0b;1]];
    if[98h=type layout 0;
        keyCost:.tst.assertPredicateTableCost[
            layout 0;
            remaining-1];
        if[not keyCost`safe;
            :.tst.assertPredicateCostResult[0b;1+keyCost`used]];
        valueCost:.tst.assertPredicateTableCost[
            layout 1;
            (remaining-1)-keyCost`used];
        total:1+keyCost`used+valueCost`used;
        :.tst.assertPredicateCostResult[valueCost`safe;total]
    ];
    n:count layout 0;
    cost:1+2*n;
    .tst.assertPredicateCostResult[cost<=remaining;cost]
 };

/ Prove that a predicate argument has only bounded, shallow payload before q
/ comparison verbs are allowed to traverse or allocate from it.
.tst.assertPredicateValueCost:{[input;depth;remaining]
    if[0>=remaining;
        :.tst.assertPredicateCostResult[0b;0]];
    t:type input;
    if[t within -19 -1h;
        :.tst.assertPredicateCostResult[1b;1]];
    if[101h=t;
        genericNull:@[
            {[box] (::)~first box};
            enlist input;
            {[err] 0b}];
        :.tst.assertPredicateCostResult[genericNull;1]
    ];
    if[t within 1 19h;
        n:@[count;input;{[err] -1}];
        if[0>n;
            :.tst.assertPredicateCostResult[0b;1]];
        cost:1+n;
        :.tst.assertPredicateCostResult[cost<=remaining;cost]
    ];
    if[98h=t;
        :.tst.assertPredicateTableCost[input;remaining]];
    if[99h=t;
        :.tst.assertPredicateDictCost[input;depth;remaining]];
    if[0h<>t;
        :.tst.assertPredicateCostResult[0b;1]];

    n:@[count;input;{[err] -1}];
    if[0>n;
        :.tst.assertPredicateCostResult[0b;1]];
    used:1+n;
    if[used>remaining;
        :.tst.assertPredicateCostResult[0b;used]];
    flat:@[
        {[pair] .tst.diffFlatSequence[pair 0;pair 1]};
        (input;n);
        {[err] 0b}];
    if[flat;
        :.tst.assertPredicateCostResult[1b;used]];
    if[
        (0>=depth) or
        n>.tst.assertPredicateNestedChildLimit[];
        :.tst.assertPredicateCostResult[0b;used]
    ];
    i:0;
    safe:1b;
    while[(i<n) and safe;
        child:.tst.assertPredicateValueCost[
            input i;
            depth-1;
            remaining-used];
        if[not child`safe; safe:0b];
        childUsed:child`used;
        if[0>=childUsed; childUsed:1];
        childUsed:(remaining-used) & childUsed;
        used+:childUsed;
        i+:1;
    ];
    .tst.assertPredicateCostResult[safe;used]
 };

.tst.assertPredicateArgsCost:{[args]
    n:@[count;args;{[err] -1}];
    if[(0>n) or n>8;
        :.tst.assertPredicateCostResult[0b;0]];
    remaining:.tst.assertPredicateItemLimit[];
    depth:.tst.assertPredicateDepthLimit[];
    used:0;
    safe:1b;
    i:0;
    while[(i<n) and safe;
        itemState:.[
            .tst.assertPredicateValueCost;
            (args i;depth;remaining);
            {[err] .tst.assertPredicateCostResult[0b;1]}];
        if[not itemState`safe; safe:0b];
        itemUsed:itemState`used;
        if[0>=itemUsed; itemUsed:1];
        itemUsed:remaining & itemUsed;
        used+:itemUsed;
        remaining-:itemUsed;
        i+:1;
    ];
    .tst.assertPredicateCostResult[safe;used]
 };

/ Central trapped predicate + lazy-message path. Returns 1b on pass and 0b when
/ it records one contextual failure; callers use the boolean only for safe diff
/ printing and do not increment again.
.tst.assertEvaluate:{[context;predicate;predicateArgs;messageFn;messageArgs]
    .tst.assertBegin[];
    safety:.tst.assertPredicateArgsCost predicateArgs;
    if[not safety`safe;
        .tst.assertRecordFailure[
            context;
            context,
                " predicate failed: input exceeds structural safety budget"];
        :0b
    ];
    predicateState:.tst.assertCapture[predicate;predicateArgs];
    if[`error~first predicateState;
        .tst.assertRecordFailure[
            context;
            context," predicate failed: ",
                .tst.assertErrorText[first last predicateState]];
        :0b
    ];
    predicateResult:first last predicateState;
    if[not -1h=type predicateResult;
        .tst.assertRecordFailure[
            context;
            context," predicate returned a non-boolean result: ",
                .tst.renderValue[predicateResult;512]];
        :0b
    ];
    if[predicateResult; :1b];
    messageState:.tst.assertCapture[messageFn;messageArgs];
    if[`error~first messageState;
        .tst.assertRecordFailure[
            context;
            context," failed (message builder error: ",
                .tst.assertErrorText[first last messageState],")"];
        :0b
    ];
    .tst.assertRecordFailure[context;first last messageState];
    0b
 };

/ Print expected-vs-actual diff; rendering problems must never mask the failure.
.tst.printDiffSafe:{[expected;actual]
    @[
        {[pair]
            -1 "";
            -1 "FAILURE DIFF ---------------------------------------------------";
            -1 .tst.diffKnownMismatch[pair 0;pair 1];
            -1 "----------------------------------------------------------------";
            ::
          };
        (expected;actual);
        {[err]
            -1 "  (diff rendering failed: ",
                .tst.capString[err;256],")";
            ::}]
 };

.tst.mustEqMessage:{[left;right]
    limit:.tst.assertMessageLimit[];
    half:limit div 2;
    message:"Got ",.tst.renderValue[left;half],
        " — expected ",.tst.renderValue[right;half];
    typeLeft:type left;
    typeRight:type right;
    if[typeLeft<>typeRight;
        message,: " (Type mismatch: ",string[typeLeft],
            " vs ",string[typeRight],")"];
    supplement:.tst.assertCapture[
        {[l;r;tl;tr]
            extra:"";
            if[(tl within -9 -6h) and tr within -9 -6h;
                extra,: " (diff: ",string[l-r],")"];
            if[(tl>=0h) and tr>=0h;
                if[count[l]<>count r;
                    extra,: " (length: ",string[count l],
                        " vs ",string[count r],")"]];
            extra
          };
        (left;right;typeLeft;typeRight)];
    if[`ok~first supplement; message,:first last supplement];
    .tst.capString[message;limit]
 };

.tst.binaryAssertionMessage:{[left;right;phrase]
    limit:.tst.assertMessageLimit[];
    half:limit div 2;
    .tst.capString[
        "Got ",.tst.renderValue[left;half]," — expected it ",
        phrase," ",.tst.renderValue[right;half];
        limit]
 };

.tst.ternaryAssertionMessage:{[tolerance;left;right]
    limit:.tst.assertMessageLimit[];
    part:limit div 3;
    .tst.capString[
        "Expected ",.tst.renderValue[left;part]," to be within +/-",
        .tst.renderValue[tolerance;part]," of ",
        .tst.renderValue[right;part];
        limit]
 };

asserts:()!();

asserts[`must]:{[val;message]
    .tst.assertEvaluate[
        "must";
        {[v] 1b~all v};
        enlist val;
        {[m] .tst.assertMessageValue m};
        enlist message];
    ::
 };

asserts[`musteq]:{[left;right]
    .tst.assertBegin[];
    compared:.tst.diffSafeMatchState[left;right];
    if[`equal~compared`state; :()];
    if[`unknown~compared`state;
        .tst.assertRecordFailure[
            "musteq";
            "musteq comparison budget exhausted before equality could be proven"];
        :()
    ];
    messageState:.tst.assertCapture[
        .tst.mustEqMessage;
        (left;right)];
    message:$[
        `ok~first messageState;
        first last messageState;
        "musteq failed (message builder error: ",
            .tst.assertErrorText[first last messageState],")"];
    .tst.assertRecordFailure["musteq";message];
    if[
        not 1b~@[get;`.tst.suppressAssertionDiff;{[err] 0b}];
        .tst.printDiffSafe[right;left]];
    ::
 };

/ mustmatch retains musteq's match semantics and rich diff path.
asserts[`mustmatch]:{[left;right]
    .tst.asserts[`musteq][left;right]
 };

/ Snapshot implementations historically signal on mismatch. Count before
/ delegating and preserve that public signaling behavior.
asserts[`mustmatchs]:{[left;right]
    .tst.assertBegin[];
    .tst.mustmatchSnap[left;right]
 };

asserts[`mustmatchst]:{[left;right]
    .tst.assertBegin[];
    .tst.mustmatchTxtSnap[left;right]
 };

asserts[`mustnmatch]:{[left;right]
    .tst.assertBegin[];
    compared:.tst.diffSafeMatchState[left;right];
    if[`different~compared`state; :()];
    if[`unknown~compared`state;
        .tst.assertRecordFailure[
            "mustnmatch";
            "mustnmatch comparison budget exhausted before inequality could be proven"];
        :()
    ];
    messageState:.tst.assertCapture[
        {[l;r] .tst.binaryAssertionMessage[l;r;"NOT to match"]};
        (left;right)];
    .tst.assertRecordFailure[
        "mustnmatch";
        $[
            `ok~first messageState;
            first last messageState;
            "mustnmatch message builder failed: ",
                .tst.assertErrorText[first last messageState]]];
    ::
 };

asserts[`mustne]:{[left;right]
    if[
        ((type left) in 98 99h) or
        (type right) in 98 99h;
        .tst.assertBegin[];
        compared:.tst.diffSafeMatchState[left;right];
        if[`different~compared`state; :()];
        if[`unknown~compared`state;
            .tst.assertRecordFailure[
                "mustne";
                "mustne comparison budget exhausted before inequality could be proven"];
            :()
        ];
        messageState:.tst.assertCapture[
            {[l;r] .tst.binaryAssertionMessage[
                l;
                r;
                "NOT to equal"]};
            (left;right)];
        .tst.assertRecordFailure[
            "mustne";
            $[
                `ok~first messageState;
                first last messageState;
                "mustne message builder failed: ",
                    .tst.assertErrorText[first last messageState]]];
        :()
    ];
    .tst.assertEvaluate[
        "mustne";
        {[l;r] 1b~all l<>r};
        (left;right);
        {[l;r] .tst.binaryAssertionMessage[l;r;"NOT to equal"]};
        (left;right)];
    ::
 };

asserts[`mustlt]:{[left;right]
    .tst.assertEvaluate[
        "mustlt";
        {[l;r] 1b~all l<r};
        (left;right);
        {[l;r] .tst.binaryAssertionMessage[l;r;"to be less than"]};
        (left;right)];
    ::
 };

asserts[`mustgt]:{[left;right]
    .tst.assertEvaluate[
        "mustgt";
        {[l;r] 1b~all l>r};
        (left;right);
        {[l;r] .tst.binaryAssertionMessage[l;r;"to be greater than"]};
        (left;right)];
    ::
 };

asserts[`mustlike]:{[left;right]
    .tst.assertEvaluate[
        "mustlike";
        {[l;r] 1b~all l like r};
        (left;right);
        {[l;r]
            .tst.binaryAssertionMessage[l;r;"to be like"]};
        (left;right)];
    ::
 };

asserts[`mustin]:{[left;right]
    .tst.assertEvaluate[
        "mustin";
        {[l;r] 1b~all l in r};
        (left;right);
        {[l;r] .tst.binaryAssertionMessage[l;r;"to be in"]};
        (left;right)];
    ::
 };

asserts[`mustnin]:{[left;right]
    .tst.assertEvaluate[
        "mustnin";
        {[l;r] 1b~all not l in r};
        (left;right);
        {[l;r] .tst.binaryAssertionMessage[l;r;"not to be in"]};
        (left;right)];
    ::
 };

asserts[`mustwithin]:{[left;right]
    .tst.assertEvaluate[
        "mustwithin";
        {[l;r] 1b~all l within r};
        (left;right);
        {[l;r] .tst.binaryAssertionMessage[l;r;"to be within"]};
        (left;right)];
    ::
 };

asserts[`mustdelta]:{[tolerance;left;right]
    .tst.assertEvaluate[
        "mustdelta";
        {[tol;l;r] 1b~all l within (r-abs tol;r+abs tol)};
        (tolerance;left;right);
        .tst.ternaryAssertionMessage;
        (tolerance;left;right)];
    ::
 };

.tst.execAssertionCode:{[code]
    t:type code;
    if[t in 100 104h; :code[]];
    if[0h=t;
        if[0=count code; :()];
        f:first code;
        args:1 _ code;
        fval:$[-11h=type f;value f;f];
        if[type[fval] in 100 104h; :fval . args];
        :value code
    ];
    value code
 };

.tst.invalidThrowPattern:{[label;detail]
    '"",label," ",detail
 };

.tst.convertSymbolThrowPatterns:{[pattern;label]
    countLimit:.tst.throwPatternCountLimit[];
    charLimit:.tst.throwPatternCharLimit[];
    totalLimit:.tst.throwPatternTotalLimit[];
    if[-11h=type pattern;
        text:string pattern;
        length:count text;
        if[length>charLimit;
            .tst.invalidThrowPattern[
                label;
                "pattern length exceeds safety limit"]];
        if[length>totalLimit;
            .tst.invalidThrowPattern[
                label;
                "total pattern text exceeds safety limit"]];
        :enlist text
    ];
    n:count pattern;
    if[n>countLimit;
        .tst.invalidThrowPattern[
            label;
            "pattern count exceeds safety limit"]];
    patterns:();
    total:0;
    i:0;
    while[i<n;
        text:string pattern i;
        length:count text;
        if[length>charLimit;
            .tst.invalidThrowPattern[
                label;
                "pattern length exceeds safety limit"]];
        if[length>totalLimit-total;
            .tst.invalidThrowPattern[
                label;
                "total pattern text exceeds safety limit"]];
        patterns,:enlist text;
        total+:length;
        i+:1;
    ];
    patterns
 };

/ Validate shape/count/bytes and compile every glob before user code executes.
.tst.normalizeThrowPatterns:{[pattern;label]
    t:type pattern;
    if[(0h=t) and 0=count pattern; :()];
    if[10h=t;
        if[0=count pattern; :()];
        patterns:enlist pattern];
    if[t in -11 11h;
        patterns:.tst.convertSymbolThrowPatterns[
            pattern;
            label]];
    if[0h=t;
        if[count[pattern]>.tst.throwPatternCountLimit[];
            .tst.invalidThrowPattern[
                label;
                "pattern count exceeds safety limit"]];
        if[not all 10h=type each pattern;
            .tst.invalidThrowPattern[
                label;
                "patterns must be strings"]];
        patterns:pattern];
    if[not t in 0 10 11 -11h;
        .tst.invalidThrowPattern[
            label;
            "pattern must be empty, a string, a symbol, a symbol vector, or a list of strings"]];
    if[count[patterns]>.tst.throwPatternCountLimit[];
        .tst.invalidThrowPattern[
            label;
            "pattern count exceeds safety limit"]];
    lengths:count each patterns;
    if[any lengths>.tst.throwPatternCharLimit[];
        .tst.invalidThrowPattern[
            label;
            "pattern length exceeds safety limit"]];
    if[sum[lengths]>.tst.throwPatternTotalLimit[];
        .tst.invalidThrowPattern[
            label;
            "total pattern text exceeds safety limit"]];
    {
        [assertionLabel;p]
        valid:@[{[candidate] "" like candidate;1b};p;{[err] 0b}];
        if[not valid;
            .tst.invalidThrowPattern[
                assertionLabel;
                "contains an invalid pattern"]]
      }[label;] each patterns;
    patterns
 };

.tst.captureAssertionCode:{[code]
    @[
        {[c]
            answer:.tst.execAssertionCode c;
            (`return;enlist answer)
          };
        code;
        {[err] (`throw;enlist err)}]
 };

.tst.matchThrowPatterns:{[errorText;patterns]
    .tst.assertCapture[
        {[err;pats] any err like/: pats};
        (errorText;patterns)]
 };

.tst.throwPatternDescription:{[patterns]
    if[0=count patterns; :"an error."];
    if[1=count patterns;
        :"the error '",first[patterns],"'."];
    "one of the errors ",
        "," sv {"'",x,"'"} each patterns,
        "."
 };

.tst.throwMessage:{[label;code;patterns;suffix]
    limit:.tst.assertMessageLimit[];
    .tst.capString[
        "Expected '",.tst.renderValue[code;1024],"' to ",
        label," ",.tst.throwPatternDescription[patterns],suffix;
        limit]
 };

asserts[`mustthrow]:{[pattern;code]
    .tst.assertBegin[];
    if[
        (type[pattern] in 100 104h) and
        not type[code] in 100 104h;
        '"mustthrow expects [pattern; code] — got code first; did you call it infix? Use mustthrow[pattern; {code}]"];
    patterns:.tst.normalizeThrowPatterns[pattern;"mustthrow"];
    capture:.tst.captureAssertionCode code;
    if[`return~first capture;
        .tst.assertRecordFailure[
            "mustthrow";
            .tst.throwMessage[
                "throw";
                code;
                patterns;
                " No error thrown"]];
        :()
    ];
    if[0=count patterns; :()];
    errorText:.tst.assertErrorText first last capture;
    matched:.tst.matchThrowPatterns[errorText;patterns];
    if[`error~first matched;
        .tst.assertRecordFailure[
            "mustthrow";
            "mustthrow pattern matching failed: ",
                .tst.assertErrorText[first last matched]];
        :()
    ];
    if[not first last matched;
        .tst.assertRecordFailure[
            "mustthrow";
            .tst.throwMessage[
                "throw";
                code;
                patterns;
                " Error thrown: '",errorText,"'"]]];
    ::
 };

asserts[`mustnotthrow]:{[pattern;code]
    .tst.assertBegin[];
    if[
        (type[pattern] in 100 104h) and
        not type[code] in 100 104h;
        '"mustnotthrow expects [pattern; code] — got code first; did you call it infix? Use mustnotthrow[pattern; {code}]"];
    patterns:.tst.normalizeThrowPatterns[pattern;"mustnotthrow"];
    capture:.tst.captureAssertionCode code;
    if[`return~first capture; :()];
    errorText:.tst.assertErrorText first last capture;
    if[0=count patterns;
        .tst.assertRecordFailure[
            "mustnotthrow";
            .tst.throwMessage[
                "not throw";
                code;
                patterns;
                " Error thrown: '",errorText,"'"]];
        :()
    ];
    matched:.tst.matchThrowPatterns[errorText;patterns];
    if[`error~first matched;
        .tst.assertRecordFailure[
            "mustnotthrow";
            "mustnotthrow pattern matching failed: ",
                .tst.assertErrorText[first last matched]];
        :()
    ];
    if[first last matched;
        .tst.assertRecordFailure[
            "mustnotthrow";
            .tst.throwMessage[
                "not throw";
                code;
                enlist errorText;
                ""]]];
    ::
 };

.tst.normalizeIgnoringOrder:{[input]
    if[98h=type input;
        table:0!input;
        :(cols table) xasc table];
    if[99h=type input;
        table:0!input;
        :(cols table) xasc table];
    if[type[input] within 0 19h; :asc input];
    input
 };

.tst.orderValuesSafe:{[left;right]
    limit:.tst.orderCellLimit[];
    depth:.tst.assertPredicateDepthLimit[];
    leftCost:.[
        .tst.assertPredicateValueCost;
        (left;depth;limit);
        {[err] .tst.assertPredicateCostResult[0b;1]}];
    if[not leftCost`safe; :0b];
    remaining:limit-leftCost`used;
    if[0>=remaining; :0b];
    rightCost:.[
        .tst.assertPredicateValueCost;
        (right;depth;remaining);
        {[err] .tst.assertPredicateCostResult[0b;1]}];
    rightCost`safe
 };

asserts[`mustmatchignoringorder]:{[left;right]
    .tst.assertBegin[];
    typeLeft:type left;
    typeRight:type right;
    if[typeLeft<>typeRight;
        .tst.assertRecordFailure[
            "mustmatchignoringorder";
            "Ignoring-order comparison requires matching types (",
                string[typeLeft]," vs ",string[typeRight],")"];
        :()
    ];
    supported:(98h=typeLeft) or
        (99h=typeLeft) or
        typeLeft within 0 19h;
    if[not supported;
        .tst.assertRecordFailure[
            "mustmatchignoringorder";
            "Ignoring-order comparison is unsupported for ",
                .tst.renderValue[left;512]];
        :()
    ];
    itemCounts:.[
        {[l;r] (count l;count r)};
        (left;right);
        {[err] -1 -1}];
    itemLimit:.tst.orderItemLimit[];
    if[(any (0>itemCounts)) or any (itemCounts>itemLimit);
        .tst.assertRecordFailure[
            "mustmatchignoringorder";
            "Ignoring-order comparison exceeded the ",
                string[itemLimit]," item safety limit"];
        :()
    ];
    if[typeLeft in 98 99h;
        columnCounts:.[
            {[l;r] (count cols l;count cols r)};
            (left;right);
            {[err] -1 -1}];
        columnLimit:.tst.orderColumnLimit[];
        if[
            (any (0>columnCounts)) or
            any (columnCounts>columnLimit);
            .tst.assertRecordFailure[
                "mustmatchignoringorder";
                "Ignoring-order comparison exceeded the ",
                    string[columnLimit],
                    " column safety limit"];
            :()
        ];
        cellLimit:.tst.orderCellLimit[];
        leftCellsTooLarge:
            (0<columnCounts 0) and
            (columnCounts 0)>cellLimit div (1 | itemCounts 0);
        rightCellsTooLarge:
            (0<columnCounts 1) and
            (columnCounts 1)>cellLimit div (1 | itemCounts 1);
        if[leftCellsTooLarge or rightCellsTooLarge;
            .tst.assertRecordFailure[
                "mustmatchignoringorder";
                "Ignoring-order comparison exceeded the ",
                    string[cellLimit],
                    " cell safety limit"];
            :()
        ]
    ];
    shapeState:.tst.assertCapture[
        .tst.orderValuesSafe;
        (left;right)];
    if[`error~first shapeState;
        .tst.assertRecordFailure[
            "mustmatchignoringorder";
            "Ignoring-order structural safety validation failed: ",
                .tst.assertErrorText[first last shapeState]];
        :()
    ];
    if[not first last shapeState;
        .tst.assertRecordFailure[
            "mustmatchignoringorder";
            "Ignoring-order comparison input exceeds its structural safety budget"];
        :()
    ];
    exact:.tst.diffMatchState[left;right];
    if[`error~first exact;
        .tst.assertRecordFailure[
            "mustmatchignoringorder";
            "Ignoring-order equality check failed: ",
                .tst.assertErrorText[first last exact]];
        :()
    ];
    if[1b~first last exact; :()];
    normalized:.tst.assertCapture[
        {[l;r]
            (.tst.normalizeIgnoringOrder l;
             .tst.normalizeIgnoringOrder r)
          };
        (left;right)];
    if[`error~first normalized;
        .tst.assertRecordFailure[
            "mustmatchignoringorder";
            "Ignoring-order normalization failed: ",
                .tst.assertErrorText[first last normalized]];
        :()
    ];
    pair:first last normalized;
    compared:.tst.diffMatchState[pair 0;pair 1];
    if[`error~first compared;
        .tst.assertRecordFailure[
            "mustmatchignoringorder";
            "Ignoring-order comparison failed: ",
                .tst.assertErrorText[first last compared]];
        :()
    ];
    if[not 1b~first last compared;
        if[not 1b~@[get;`.tst.suppressAssertionDiff;{[err] 0b}];
            -1 "FAILURE DIFF (Ignoring Order) ------------------------------------";
            .tst.printDiffSafe[pair 1;pair 0]];
        .tst.assertRecordFailure[
            "mustmatchignoringorder";
            "Expected value (ignoring order) match failed."]];
    ::
 };

.tst.includeColumnsFlat:{[left;right;required]
    rowsLeft:count left;
    rowsRight:count right;
    i:0;
    flat:1b;
    while[(i<count required) and flat;
        pair:.[
            {[l;r;name] (l name;r name)};
            (left;right;required i);
            {[err] ()}];
        if[2<>count pair; flat:0b];
        if[
            flat and
            not .tst.diffFlatSequence[pair 0;rowsLeft];
            flat:0b];
        if[
            flat and
            not .tst.diffFlatSequence[pair 1;rowsRight];
            flat:0b];
        i+:1;
    ];
    flat
 };

asserts[`mustincludecols]:{[left;right]
    .tst.assertBegin[];
    if[98h<>type left;
        .tst.assertRecordFailure[
            "mustincludecols";
            "mustincludecols applies only to a table left argument"];
        :()
    ];
    if[98h<>type right;
        .tst.assertRecordFailure[
            "mustincludecols";
            "mustincludecols expects a table right argument"];
        :()
    ];
    colsLeft:cols left;
    colsRight:cols right;
    if[
        (count[colsLeft]>.tst.includeColumnLimit[]) or
        (count[colsRight]>.tst.includeColumnLimit[]);
        .tst.assertRecordFailure[
            "mustincludecols";
            "Column comparison exceeded the ",
                string[.tst.includeColumnLimit[]],
                " column safety limit"];
        :()
    ];
    rowCounts:(count left;count right);
    rowLimit:.tst.includeRowLimit[];
    if[any (rowCounts>rowLimit);
        .tst.assertRecordFailure[
            "mustincludecols";
            "Row comparison exceeded the ",
                string[rowLimit],
                " row safety limit"];
        :()
    ];
    requiredCount:count colsRight;
    cellLimit:.tst.includeCellLimit[];
    leftCellsTooLarge:
        (0<requiredCount) and
        requiredCount>cellLimit div (1 | rowCounts 0);
    rightCellsTooLarge:
        (0<requiredCount) and
        requiredCount>cellLimit div (1 | rowCounts 1);
    if[leftCellsTooLarge or rightCellsTooLarge;
        .tst.assertRecordFailure[
            "mustincludecols";
            "Included-column comparison exceeded the ",
                string[cellLimit],
                " cell safety limit"];
        :()
    ];
    membership:.tst.assertCapture[
        {[available;required] required in available};
        (colsLeft;colsRight)];
    if[`error~first membership;
        .tst.assertRecordFailure[
            "mustincludecols";
            "Column membership comparison failed: ",
                .tst.assertErrorText[first last membership]];
        :()
    ];
    missingPositions:where not first last membership;
    if[count missingPositions;
        .tst.assertRecordFailure[
            "mustincludecols";
            "Missing ",string[count missingPositions],
                " required columns at positions ",
                .tst.renderValue[missingPositions;512]];
        :()
    ];
    if[not .tst.includeColumnsFlat[left;right;colsRight];
        .tst.assertRecordFailure[
            "mustincludecols";
            "Included-column comparison contains nested composite values outside its structural safety budget"];
        :()
    ];
    subsetState:.tst.assertCapture[
        {[table;required] required#table};
        (left;colsRight)];
    if[`error~first subsetState;
        .tst.assertRecordFailure[
            "mustincludecols";
            "Included-column projection failed: ",
                .tst.assertErrorText[first last subsetState]];
        :()
    ];
    subset:first last subsetState;
    compared:.tst.diffSafeMatchState[subset;right];
    if[`unknown~compared`state;
        .tst.assertRecordFailure[
            "mustincludecols";
            "Included-column comparison exhausted its structural safety budget"];
        :()
    ];
    if[`different~compared`state;
        if[not 1b~@[get;`.tst.suppressAssertionDiff;{[err] 0b}];
            -1 "FAILURE DIFF (Included Columns) ------------------------------------";
            .tst.printDiffSafe[right;subset]];
        .tst.assertRecordFailure[
            "mustincludecols";
            "Columns match failed."]];
    ::
 };

.tst.validAssertionLimit:{[limit]
    if[not type[limit] in -4 -5 -6 -7 -8 -9h; :0b];
    finite:@[
        .tst.benchmark.isFiniteScalar;
        limit;
        {[err] 0b}];
    finite and 0<=limit
 };

.tst.runBenchmarkAssertion:{[context;code;limit;metric;unit]
    .tst.assertBegin[];
    if[not type[code] in 100 104h;
        .tst.assertRecordFailure[
            context;
            context," expects a callable function"];
        :()
    ];
    if[not .tst.validAssertionLimit limit;
        .tst.assertRecordFailure[
            context;
            context," limit must be a finite non-negative numeric scalar"];
        :()
    ];
    measured:.tst.assertCapture[
        {[callable] .tst.benchmark.measure[20;callable]};
        enlist code];
    if[`error~first measured;
        .tst.assertRecordFailure[
            context;
            context," benchmark failed: ",
                .tst.assertErrorText[first last measured]];
        :()
    ];
    stats:first last measured;
    extracted:.tst.assertCapture[
        {[data;field] data[field;`avg]};
        (stats;metric)];
    if[`error~first extracted;
        .tst.assertRecordFailure[
            context;
            context," benchmark result was malformed: ",
                .tst.assertErrorText[first last extracted]];
        :()
    ];
    actual:first last extracted;
    compared:.tst.assertCapture[
        {[value;threshold] 1b~value<=threshold};
        (actual;limit)];
    if[(`error~first compared) or not -1h=type first last compared;
        detail:$[
            `error~first compared;
            .tst.assertErrorText[first last compared];
            "non-boolean comparison result"];
        .tst.assertRecordFailure[
            context;
            context," comparison failed: ",detail];
        :()
    ];
    if[not first last compared;
        .tst.assertRecordFailure[
            context;
            $[
                `time~metric;
                "Execution time ";
                "Allocation "],
            .tst.renderValue[actual;256]," ",unit," > Limit ",
            .tst.renderValue[limit;256],unit]];
    ::
 };

asserts[`mustBeFasterThan]:{[code;limitMs]
    .tst.runBenchmarkAssertion[
        "mustBeFasterThan";
        code;
        limitMs;
        `time;
        "ms"]
 };

asserts[`mustAllocLessThan]:{[code;limitBytes]
    .tst.runBenchmarkAssertion[
        "mustAllocLessThan";
        code;
        limitBytes;
        `space;
        " bytes"]
 };

.tst.spyFindCall:{[wanted;calls]
    n:count calls;
    stop:n & .tst.spyCallLimit[];
    found:0b;
    comparisonExhausted:0b;
    remaining:.tst.spyCompareLimit[];
    pos:0;
    while[
        ((pos<stop) and not found) and
        not comparisonExhausted;
        if[0>=remaining;
            comparisonExhausted:1b;
            pos+:1];
        if[not comparisonExhausted;
            probe:.tst.diffProbe[
                wanted;
                calls pos;
                .tst.diffDepthLimit[];
                remaining];
            used:probe`used;
            if[0>=used; used:1];
            used:remaining & used;
            remaining-:used;
            if[`equal~probe`state; found:1b];
            if[`unknown~probe`state;
                comparisonExhausted:1b];
            pos+:1];
    ];
    `found`comparisonExhausted`scanExhausted`scanned!(
        found;
        comparisonExhausted;
        (not found) and
            ((stop<n) or comparisonExhausted);
        pos)
 };

asserts[`mustHaveBeenCalledWith]:{[name;args]
    .tst.assertBegin[];
    logState:.tst.assertCapture[
        {[ignored] .tst.spyLog.calls};
        enlist 0];
    if[`error~first logState;
        .tst.assertRecordFailure[
            "mustHaveBeenCalledWith";
            "Spy call log is unavailable: ",
                .tst.assertErrorText[first last logState]];
        :()
    ];
    callsByName:first last logState;
    if[99h<>type callsByName;
        .tst.assertRecordFailure[
            "mustHaveBeenCalledWith";
            "Spy call log is malformed"];
        :()
    ];
    nameCount:count callsByName;
    nameLimit:.tst.spyNameLimit[];
    if[nameCount>nameLimit;
        .tst.assertRecordFailure[
            "mustHaveBeenCalledWith";
            "Spy name lookup exceeded the ",
                string[nameLimit],
                " name safety limit"];
        :()
    ];
    layoutState:.tst.assertCapture[
        {[callsDict] (key callsDict;value callsDict)};
        enlist callsByName];
    if[`error~first layoutState;
        .tst.assertRecordFailure[
            "mustHaveBeenCalledWith";
            "Spy call log layout is unreadable: ",
                .tst.assertErrorText[first last layoutState]];
        :()
    ];
    layout:first last layoutState;
    names:layout 0;
    callLists:layout 1;
    namesValid:(0=nameCount) or 11h=type names;
    logsValid:(0=nameCount) or 0h=type callLists;
    if[not (namesValid and logsValid);
        .tst.assertRecordFailure[
            "mustHaveBeenCalledWith";
            "Spy call log names or call lists are malformed"];
        :()
    ];
    shapeState:.tst.assertCapture[
        {[logs;callLimit]
            listTypes:type each logs;
            callCounts:count each logs;
            (
                all (listTypes=0h);
                all (callCounts<=callLimit))
          };
        (callLists;.tst.spyCallLimit[])];
    if[`error~first shapeState;
        .tst.assertRecordFailure[
            "mustHaveBeenCalledWith";
            "Spy call-list validation failed: ",
                .tst.assertErrorText[first last shapeState]];
        :()
    ];
    shape:first last shapeState;
    if[not shape 0;
        .tst.assertRecordFailure[
            "mustHaveBeenCalledWith";
            "Spy call log contains a malformed call list"];
        :()
    ];
    if[not shape 1;
        .tst.assertRecordFailure[
            "mustHaveBeenCalledWith";
            "Spy call log contains a call list exceeding the ",
                string[.tst.spyCallLimit[]],
                " call safety limit"];
        :()
    ];
    present:.tst.assertCapture[
        {[candidate;names] candidate in names};
        (name;names)];
    if[
        (`error~first present) or
        not -1h=type first last present;
        detail:$[
            `error~first present;
            .tst.assertErrorText[first last present];
            "non-boolean membership result"];
        .tst.assertRecordFailure[
            "mustHaveBeenCalledWith";
            "Spy name lookup failed: ",detail];
        :()
    ];
    if[not first last present;
        .tst.assertRecordFailure[
            "mustHaveBeenCalledWith";
            "Function ",.tst.renderValue[name;256],
                " is not spied on."];
        :()
    ];
    callsState:.tst.assertCapture[
        {[callsDict;candidate] callsDict candidate};
        (callsByName;name)];
    if[`error~first callsState;
        .tst.assertRecordFailure[
            "mustHaveBeenCalledWith";
            "Spy calls could not be read: ",
                .tst.assertErrorText[first last callsState]];
        :()
    ];
    calls:first last callsState;
    scanned:.tst.assertCapture[
        .tst.spyFindCall;
        (args;calls)];
    if[`error~first scanned;
        .tst.assertRecordFailure[
            "mustHaveBeenCalledWith";
            "Spy call comparison failed: ",
                .tst.assertErrorText[first last scanned]];
        :()
    ];
    search:first last scanned;
    if[search`comparisonExhausted;
        .tst.assertRecordFailure[
            "mustHaveBeenCalledWith";
            "Spy call comparison exhausted its structural safety budget"];
        :()
    ];
    if[search`found; :()];
    if[search`scanExhausted;
        .tst.assertRecordFailure[
            "mustHaveBeenCalledWith";
            "Spy call scan exhausted its ",
                string[.tst.spyCallLimit[]],
                " call safety budget without a match"];
        :()
    ];
    .tst.assertRecordFailure[
        "mustHaveBeenCalledWith";
        "Expected ",.tst.renderValue[name;256],
            " to have been called with ",.tst.renderValue[args;1024],
            ". Actual calls: ",
            $[
                0=count calls;
                "(none)";
                .tst.renderValue[calls;2048]]];
    ::
 };

/ Additive camelCase aliases (compat surface).
asserts[`mustEqual]:asserts[`musteq];
asserts[`mustNotEqual]:asserts[`mustne];
asserts[`mustLessThan]:asserts[`mustlt];
asserts[`mustGreaterThan]:asserts[`mustgt];
asserts[`mustMatchSnapshot]:asserts[`mustmatchs];
asserts[`mustMatchTextSnapshot]:asserts[`mustmatchst];
asserts[`mustMatchIgnoringOrder]:asserts[`mustmatchignoringorder];

\d .
must:.tst.asserts[`must];
musteq:.tst.asserts[`musteq];
mustmatch:.tst.asserts[`mustmatch];
mustmatchs:.tst.asserts[`mustmatchs];
mustmatchst:.tst.asserts[`mustmatchst];
mustnmatch:.tst.asserts[`mustnmatch];
mustne:.tst.asserts[`mustne];
mustlt:.tst.asserts[`mustlt];
mustgt:.tst.asserts[`mustgt];
mustlike:.tst.asserts[`mustlike];
mustin:.tst.asserts[`mustin];
mustnin:.tst.asserts[`mustnin];
mustwithin:.tst.asserts[`mustwithin];
mustdelta:.tst.asserts[`mustdelta];
mustthrow:.tst.asserts[`mustthrow];
mustnotthrow:.tst.asserts[`mustnotthrow];
mustmatchignoringorder:.tst.asserts[`mustmatchignoringorder];
mustincludecols:.tst.asserts[`mustincludecols];
mustBeFasterThan:.tst.asserts[`mustBeFasterThan];
mustAllocLessThan:.tst.asserts[`mustAllocLessThan];
mustHaveBeenCalledWith:.tst.asserts[`mustHaveBeenCalledWith];

.tst.mustmatchs:.tst.asserts[`mustmatchs];
.tst.mustmatchst:.tst.asserts[`mustmatchst];

/ Additive camelCase root aliases (compat).
mustEqual:.tst.asserts[`mustEqual];
mustNotEqual:.tst.asserts[`mustNotEqual];
mustLessThan:.tst.asserts[`mustLessThan];
mustGreaterThan:.tst.asserts[`mustGreaterThan];
mustMatchSnapshot:.tst.asserts[`mustMatchSnapshot];
mustMatchTextSnapshot:.tst.asserts[`mustMatchTextSnapshot];
mustMatchIgnoringOrder:.tst.asserts[`mustMatchIgnoringOrder];
