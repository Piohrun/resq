\d .tst

if[not `parametrizeCaseHardLimit in key `.tst;
    parametrizeCaseHardLimit:1000000];
if[not `parametrizeRenderLimit in key `.tst;
    parametrizeRenderLimit:1024];
if[not `parametrizeFailureItemLimit in key `.tst;
    parametrizeFailureItemLimit:16];
if[not `parametrizeParamHardLimit in key `.tst;
    parametrizeParamHardLimit:8];
if[not `parametrizeNameLengthLimit in key `.tst;
    parametrizeNameLengthLimit:128];
if[not `parametrizeAssertionHardLimit in key `.tst;
    parametrizeAssertionHardLimit:1000000];
if[not `parametrizeRenderDepthLimit in key `.tst;
    parametrizeRenderDepthLimit:4];
if[not `parametrizeStateFailureHardLimit in key `.tst;
    parametrizeStateFailureHardLimit:1000];

paramIntegerIsInfinite:{[x]
    t:type x;
    if[-5h=t; :(x=0Wh) or x=-0Wh];
    if[-6h=t; :(x=0Wi) or x=-0Wi];
    if[-7h=t; :(x=0W) or x=-0W];
    0b
 };

paramCallableArityBody:{[f]
    t:type f;
    if[100h=t; :count (value f) 1];
    if[101h=t; :1];
    if[102h=t; :2];
    if[104h=t; :sum {(::)~x} each 1_value f];
    -1
 };

paramCallableArity:{[f]
    @[.tst.paramCallableArityBody;f;{[e] -1}]
 };

safeParamLimit:{[name;maximum]
    n:@[get;name;maximum];
    if[not (type n) in -5 -6 -7h; :maximum];
    if[null n; :maximum];
    if[.tst.paramIntegerIsInfinite n; :maximum];
    if[1>n; :maximum];
    "j"$(maximum&n)
 };

parametrizeCaseLimit:{[]
    .tst.safeParamLimit[`.tst.parametrizeCaseHardLimit;1000000]
 };

parametrizeTextLimit:{[]
    .tst.safeParamLimit[`.tst.parametrizeRenderLimit;1024]
 };

parametrizeFailureLimit:{[]
    .tst.safeParamLimit[`.tst.parametrizeFailureItemLimit;16]
 };

parametrizeAssertionLimit:{[]
    .tst.safeParamLimit[`.tst.parametrizeAssertionHardLimit;1000000]
 };

parametrizeParamLimit:{[]
    .tst.safeParamLimit[`.tst.parametrizeParamHardLimit;8]
 };

parametrizeNameLimit:{[]
    .tst.safeParamLimit[`.tst.parametrizeNameLengthLimit;128]
 };

parametrizeRenderDepth:{[]
    .tst.safeParamLimit[`.tst.parametrizeRenderDepthLimit;4]
 };

parametrizeStateFailureLimit:{[]
    .tst.safeParamLimit[`.tst.parametrizeStateFailureHardLimit;1000]
 };

validateParamNames:{[names;source]
    if[0=count names; 'source," requires at least one parameter"];
    if[not 11h=type names;
        'source," parameter names must be symbols"];
    paramLimit:.tst.parametrizeParamLimit[];
    if[(count names)>paramLimit;
        'source," parameter count exceeds safety limit ",string paramLimit];
    if[any null names; 'source," parameter names must not be null"];
    if[(count names)<>count distinct names;
        'source," parameter names must be unique"];
    nameLimit:.tst.parametrizeNameLimit[];
    i:0;
    while[i<count names;
        text:string names i;
        if[(count text)>nameLimit;
            'source," parameter name exceeds length limit ",string nameLimit];
        codes:"i"$text;
        if[any (codes<32) or codes=127;
            'source," parameter names must not contain control characters"];
        i+:1;
    ];
    names
 };

validateParamFunction:{[func;countNames;source]
    if[not (type func) within 100 112h;
        'source," expects a callable function"];
    arity:.tst.paramCallableArity func;
    if[0>arity;
        'source," cannot safely determine function arity"];
    if[arity<>countNames;
        'source," function arity ",string[arity],
            " does not match ",string[countNames]," parameter(s)"];
    1b
 };

normalizeParamSet:{[name;vals]
    t:type vals;
    if[99h=t;
        '"parametrize values for `",string[name],
            "` must be a list or scalar, not a dictionary"];
    normalized:$[(0>t) or 100<=t;enlist vals;vals];
    if[0=count normalized;
        '"parametrize values for `",string[name],"` must not be empty"];
    normalized
 };

normalizeParamInput:{[input]
    t:type input;
    pd:$[99h=t;input;
         98h=t;flip input;
         t in -20 20h;(enlist key input)!enlist value input;
         '"parametrize expects a dictionary or table as first argument"];
    names:key pd;
    vals:value pd;
    if[-11h=type names;
        names:enlist names;
        vals:enlist vals];
    names:.tst.validateParamNames[names;"parametrize"];
    if[(count names)<>count vals;
        '"parametrize parameter names and value sets have inconsistent lengths"];
    normalized:();
    i:0;
    while[i<count names;
        normalized,:enlist .tst.normalizeParamSet[names i;vals i];
        i+:1;
    ];
    `names`values!(names;normalized)
 };

/ Product cardinality is checked before multiplication, so neither long overflow
/ nor a cap breach can wrap into a small, falsely safe case count.
checkedParamProduct:{[counts;limit]
    if[not (type counts) in 5 6 7h;
        '"parameter cardinalities must be an integer list"];
    if[0=count counts; '"parameter cardinalities must not be empty"];
    if[any null counts; '"parameter cardinalities must be finite"];
    if[any .tst.paramIntegerIsInfinite each counts;
        '"parameter cardinalities must be finite"];
    if[any 1>counts; '"parameter value sets must not be empty"];
    if[not (type limit) in -5 -6 -7h;
        '"parameter case limit must be an integer scalar"];
    if[(null limit) or .tst.paramIntegerIsInfinite[limit] or 1>limit;
        '"parameter case limit must be finite and positive"];
    maxFinite:9223372036854775806;
    total:1j;
    i:0;
    while[i<count counts;
        n:"j"$counts i;
        if[total>maxFinite div n;
            '"parametrize Cartesian product cardinality overflows long"];
        if[total>limit div n;
            '"parametrize Cartesian product exceeds safety limit ",
                string limit];
        total*:n;
        i+:1;
    ];
    total
 };

validParamAssertState:{[state]
    if[not 99h=type state; :0b];
    if[not all `failures`assertsRun in key state; :0b];
    if[not 0h=type state`failures; :0b];
    if[(count state`failures)>.tst.parametrizeStateFailureLimit[]; :0b];
    if[not (type state`assertsRun) in -5 -6 -7h; :0b];
    if[null state`assertsRun; :0b];
    if[.tst.paramIntegerIsInfinite state`assertsRun; :0b];
    0<=state`assertsRun
 };

restoreParamFailureState:{[savedState;current]
    restored:savedState;
    if[.tst.validParamAssertState current;
        delta:current[`assertsRun]-savedState`assertsRun;
        limit:.tst.parametrizeAssertionLimit[];
        if[(0<=delta) and delta<=limit;
            restored[`assertsRun]:current`assertsRun]
    ];
    .tst.assertState:restored;
    restored
 };

paramSimpleText:{[val;limit]
    t:type val;
    if[11h=t;
        :.tst.capString[
            "<symbol list count=",string[count val],">";limit]];
    if[20h<=t;
        :.tst.capString[
            "<list type=",string[t]," count=",string[count val],">";limit]];
    n:.tst.parametrizeFailureLimit[]&count val;
    prefix:n#val;
    text:-3!prefix;
    if[(count val)>n;
        text:text," ... [",string[(count val)-n]," more]"];
    .tst.capString[text;limit]
 };

paramGeneralText:{[val;limit;depth]
    n:.tst.parametrizeFailureLimit[]&count val;
    itemLimit:1|limit div 1|n;
    parts:();
    i:0;
    while[i<n;
        parts,:enlist .tst.paramValueTextBody[val i;itemLimit;depth+1];
        i+:1;
    ];
    text:"[",("; " sv parts),"]";
    if[(count val)>n;
        text:text," ... [",string[(count val)-n]," more]"];
    .tst.capString[text;limit]
 };

paramDictText:{[val;limit;depth]
    ks:key val;
    if[98h=type ks;
        :.tst.capString[
            "<keyed table rows=",string[count val],">";limit]];
    vals:value val;
    n:.tst.parametrizeFailureLimit[]&count ks;
    itemLimit:1|limit div 1|n;
    parts:();
    i:0;
    while[i<n;
        kText:.tst.paramValueTextBody[ks i;itemLimit div 2;depth+1];
        vText:.tst.paramValueTextBody[vals i;itemLimit div 2;depth+1];
        parts,:enlist kText,":",vText;
        i+:1;
    ];
    text:"{",("; " sv parts),"}";
    if[(count ks)>n;
        text:text," ... [",string[(count ks)-n]," more]"];
    .tst.capString[text;limit]
 };

paramValueTextBody:{[val;limit;depth]
    if[1>limit; :""];
    t:type val;
    if[10h=t; :.tst.capString[val;limit]];
    if[-11h=t; :.tst.capString["<symbol>";limit]];
    if[t<0; :.tst.capString[string val;limit]];
    depthLimit:.tst.parametrizeRenderDepth[];
    if[depth>=depthLimit;
        :.tst.capString[
            "<",string[t]," value depth limit>";limit]];
    if[0h=t; :.tst.paramGeneralText[val;limit;depth]];
    if[98h=t;
        cs:cols val;
        cs:(.tst.parametrizeFailureLimit[]&count cs)#cs;
        colsText:.tst.paramSimpleText[cs;limit div 2];
        :.tst.capString[
            "<table rows=",string[count val]," cols=",
            .tst.capString[colsText;limit div 2],">";
            limit]
    ];
    if[99h=t; :.tst.paramDictText[val;limit;depth]];
    if[t within 1 97h; :.tst.paramSimpleText[val;limit]];
    .tst.capString["<function type ",string[t],">";limit]
 };

paramValueText:{[val]
    limit:.tst.parametrizeTextLimit[];
    text:.[.tst.paramValueTextBody;(val;limit;0);
      {[e] "<value could not be rendered>"}];
    .tst.capString[text;limit]
 };

paramPairText:{[name;val]
    string[name],"=",.tst.paramValueText val
 };

paramContext:{[names;args]
    pairs:.tst.paramPairText'[names;args];
    .tst.capString[", " sv pairs;.tst.parametrizeTextLimit[]]
 };

paramContextFallback:{[names]
    .tst.capString["names: "," " sv string names;.tst.parametrizeTextLimit[]]
 };

paramErrorText:{[prefix;err;context]
    limit:.tst.parametrizeTextLimit[];
    / Preserve the root error first. Parameter context and the generic wrapper
    / are useful, but neither may crowd the actual cause out of a tight cap.
    root:$[(count err)<=limit;err;limit#err];
    remaining:0|limit-count root;
    context:.tst.capString[context;remaining];
    suffix:.tst.capString[
        " (Params: ",context,")";remaining];
    remaining:0|remaining-count suffix;
    prefix:.tst.capString[prefix;remaining];
    prefix,root,suffix
 };

paramFailureText:{[failures]
    limit:.tst.parametrizeFailureLimit[];
    shown:(limit&count failures)#failures;
    rendered:{[v]
        .tst.paramValueText v
      } each shown;
    text:"; " sv rendered;
    if[(count failures)>count shown;
        text:text,"; ... [",string[(count failures)-count shown],
            " more failure(s)]"];
    .tst.capString[text;.tst.parametrizeTextLimit[]]
 };

invokeParamFunction:{[func;args]
    func . args;
    `ok
 };

/ Execute one case as a protected region. A throwing/corrupting case restores
/ the entire prior assertion state before its contextual error is signalled.
runParamCase:{[names;args;func]
    savedState:.tst.assertState;
    if[not .tst.validParamAssertState savedState;
        '"parametrized case started with invalid assertion state"];
    contextAttempt:.[{[n;a] (`ok;.tst.paramContext[n;a])};
        (names;args);{[e] (`error;e)}];
    if[`error~first contextAttempt;
        .tst.assertState:savedState;
        fallback:.tst.paramContextFallback names;
        msg:.tst.paramErrorText[
            "Parameter rendering failed: ";last contextAttempt;fallback];
        'msg
    ];
    context:last contextAttempt;
    outcome:.[.tst.invokeParamFunction;(func;args);{[e] (`error;e)}];
    if[`error~first outcome;
        current:@[get;`.tst.assertState;savedState];
        .tst.restoreParamFailureState[savedState;current];
        msg:.tst.paramErrorText["Parametrized case failed: ";last outcome;context];
        'msg
    ];
    current:.tst.assertState;
    if[not .tst.validParamAssertState current;
        .tst.assertState:savedState;
        msg:.tst.paramErrorText[
            "Parametrized case failed: ";"assertion state became invalid";context];
        'msg
    ];
    delta:current[`assertsRun]-savedState`assertsRun;
    if[delta>.tst.parametrizeAssertionLimit[];
        .tst.assertState:savedState;
        msg:.tst.paramErrorText[
            "Parametrized case failed: ";"assertion count exceeds safety limit";context];
        'msg
    ];
    oldFailures:savedState`failures;
    newFailures:current`failures;
    prefixOk:(count newFailures)>=count oldFailures;
    if[prefixOk; prefixOk:oldFailures~(count oldFailures)#newFailures];
    if[not prefixOk;
        .tst.assertState:savedState;
        msg:.tst.paramErrorText[
            "Parametrized case failed: ";"assertion failure state was replaced";context];
        'msg
    ];
    if[current[`assertsRun]<savedState`assertsRun;
        .tst.assertState:savedState;
        msg:.tst.paramErrorText[
            "Parametrized case failed: ";"assertion count moved backwards";context];
        'msg
    ];
    if[(count newFailures)>count oldFailures;
        failures:(count oldFailures)_newFailures;
        .tst.restoreParamFailureState[savedState;current];
        root:.tst.paramFailureText failures;
        msg:.tst.paramErrorText["Assertion failed: ";root;context];
        'msg
    ];
    1b
 };

/ Parametrized Test Runner
/ data is already materialized by its caller; rows are executed incrementally.
forall:{[data;func]
    if[not 98h=type data; '"forall expects a table as first argument"];
    names:.tst.validateParamNames[cols data;"forall"];
    if[0=count data; '"forall input table must contain at least one row"];
    if[(count data)>.tst.parametrizeCaseLimit[];
        '"forall row count exceeds safety limit ",
            string .tst.parametrizeCaseLimit[]];
    .tst.validateParamFunction[func;count names;"forall"];
    i:0;
    while[i<count data;
        row:data i;
        .tst.runParamCase[names;value row;func];
        i+:1;
    ];
    1b
 };

/ Read one combination from a reusable mixed-radix position vector.
paramArgsAt:{[values;positions]
    {[v;i] v i}'[values;positions]
 };

/ Advance with the final parameter fastest, matching q `cross order.
advanceParamPositions:{[positions;counts]
    i:count positions;
    carry:1b;
    while[carry and 0<i;
        i-:1;
        positions[i]+:1;
        if[positions[i]<counts i; carry:0b];
        if[carry; positions[i]:0];
    ];
    positions
 };

/ Parametrize: stream the Cartesian product without constructing a cases table.
parametrize:{[paramInput;func]
    normalized:.tst.normalizeParamInput paramInput;
    names:normalized`names;
    values:normalized`values;
    .tst.validateParamFunction[func;count names;"parametrize"];
    counts:count each values;
    total:.tst.checkedParamProduct[counts;.tst.parametrizeCaseLimit[]];
    if[@[get;`.utl.DEBUG;0b];
        -1 "DEBUG: parametrize data count ",string total];
    i:0;
    positions:(count counts)#0;
    while[i<total;
        args:.tst.paramArgsAt[values;positions];
        .tst.runParamCase[names;args;func];
        positions:.tst.advanceParamPositions[positions;counts];
        i+:1;
    ];
    1b
 };

\d .
