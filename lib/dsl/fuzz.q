\d .tst

fuzzListMaxLength:100

/ Safety limits are intentionally private and may be lowered by focused tests.
if[not `fuzzRunHardLimit in key `.tst; fuzzRunHardLimit:1000000];
if[not `pickFuzzBulkRunLimit in key `.tst; pickFuzzBulkRunLimit:10000];
if[not `pickFuzzBulkNodeLimit in key `.tst; pickFuzzBulkNodeLimit:1000000];
if[not `fuzzListLengthHardLimit in key `.tst; fuzzListLengthHardLimit:10000];
if[not `fuzzGeneratorDepthLimit in key `.tst; fuzzGeneratorDepthLimit:16];
if[not `fuzzGeneratorNodeLimit in key `.tst; fuzzGeneratorNodeLimit:1024];
if[not `fuzzShrinkStepLimit in key `.tst; fuzzShrinkStepLimit:64];
if[not `fuzzShrinkTimeLimitMs in key `.tst; fuzzShrinkTimeLimitMs:1000];
if[not `fuzzRenderLimit in key `.tst; fuzzRenderLimit:2048];
if[not `fuzzDiagnosticHardLimit in key `.tst; fuzzDiagnosticHardLimit:1000];
if[not `fuzzFailureItemLimit in key `.tst; fuzzFailureItemLimit:16];
if[not `fuzzAssertionHardLimit in key `.tst; fuzzAssertionHardLimit:1000000];
if[not `boundedRenderItemLimit in key `.tst; boundedRenderItemLimit:16];
if[not `boundedRenderDepthLimit in key `.tst; boundedRenderDepthLimit:4];
if[not `fuzzGeneratedValueHardLimit in key `.tst;
    fuzzGeneratedValueHardLimit:10000];
if[not `fuzzGeneratedNodeHardLimit in key `.tst;
    fuzzGeneratedNodeHardLimit:10000];
if[not `fuzzGeneratedDepthHardLimit in key `.tst;
    fuzzGeneratedDepthHardLimit:16];
if[not `fuzzGeneratorChoiceHardLimit in key `.tst;
    fuzzGeneratorChoiceHardLimit:10000];
if[not `fuzzStateFailureHardLimit in key `.tst;
    fuzzStateFailureHardLimit:1000];

typeNames: `boolean`guid`byte`short`int`long`real`float`char`symbol`timestamp`month`date`datetime`timespan`minute`second`time
typeCodes: 1 2 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19h
typeDefaults:(0b;0Ng;0x00;0h;0;0j;0e;0f;" ";`symbol;0p;2000.01m;2000.01.01;2000.01.01T00:00:00.000;0D00:00:00.000000000;00:00;00:00:00;00:00:00.000)
typeFuzzN: typeNames!typeDefaults
typeFuzzC: typeCodes!typeDefaults

/ Return a safely introspected callable arity, or -1 when it cannot be proven.
/ Lambdas, unary/binary primitives and ordinary projections cover the public DSL.
safeCallableArityBody:{[f]
    t:type f;
    if[100h=t; :count (value f) 1];
    if[101h=t; :1];
    if[102h=t; :2];
    if[104h=t; :sum {(::)~x} each 1_value f];
    -1
 };

safeCallableArity:{[f]
    @[.tst.safeCallableArityBody;f;{[e] -1}]
 };

integerIsInfinite:{[x]
    t:type x;
    if[-5h=t; :(x=0Wh) or x=-0Wh];
    if[-6h=t; :(x=0Wi) or x=-0Wi];
    if[-7h=t; :(x=0W) or x=-0W];
    0b
 };

/ q's float comparisons are tolerant around zero. Serialized bytes are exact,
/ so compare a value with its magnitude to recover {-1,0,1} without tolerance.
exactFloatSign:{[x]
    magnitudeBytes:-8!abs x;
    if[magnitudeBytes~-8!0f; :0];
    $[(-8!x)~magnitudeBytes;1;-1]
 };

safePositiveLimit:{[name;fallback]
    n:@[get;name;fallback];
    if[not (type n) in -5 -6 -7h; :fallback];
    if[null n; :fallback];
    if[.tst.integerIsInfinite n; :fallback];
    if[1>n; :fallback];
    "j"$(fallback&n)
 };

fuzzRunLimit:{[] .tst.safePositiveLimit[`.tst.fuzzRunHardLimit;1000000] }
pickFuzzRunLimit:{[] .tst.safePositiveLimit[`.tst.pickFuzzBulkRunLimit;10000] }
pickFuzzNodeLimit:{[] .tst.safePositiveLimit[`.tst.pickFuzzBulkNodeLimit;1000000] }
fuzzListHardLimit:{[] .tst.safePositiveLimit[`.tst.fuzzListLengthHardLimit;10000] }
fuzzGeneratorDepth:{[] .tst.safePositiveLimit[`.tst.fuzzGeneratorDepthLimit;16] }
fuzzGeneratorNodes:{[] .tst.safePositiveLimit[`.tst.fuzzGeneratorNodeLimit;1024] }
fuzzShrinkSteps:{[] .tst.safePositiveLimit[`.tst.fuzzShrinkStepLimit;64] }
fuzzShrinkMillis:{[] .tst.safePositiveLimit[`.tst.fuzzShrinkTimeLimitMs;1000] }
fuzzReproLimit:{[] .tst.safePositiveLimit[`.tst.fuzzRenderLimit;2048] }
fuzzDiagnosticCap:{[] .tst.safePositiveLimit[`.tst.fuzzDiagnosticHardLimit;1000] }
fuzzFailureItems:{[] .tst.safePositiveLimit[`.tst.fuzzFailureItemLimit;16] }
fuzzAssertionLimit:{[] .tst.safePositiveLimit[`.tst.fuzzAssertionHardLimit;1000000] }
fuzzGeneratedValueLimit:{[]
    .tst.safePositiveLimit[`.tst.fuzzGeneratedValueHardLimit;10000]
 }
fuzzGeneratedNodeLimit:{[]
    .tst.safePositiveLimit[`.tst.fuzzGeneratedNodeHardLimit;10000]
 }
fuzzGeneratedDepthLimit:{[]
    .tst.safePositiveLimit[`.tst.fuzzGeneratedDepthHardLimit;16]
 }
fuzzGeneratorChoiceLimit:{[]
    .tst.safePositiveLimit[`.tst.fuzzGeneratorChoiceHardLimit;10000]
 }
fuzzStateFailureLimit:{[]
    .tst.safePositiveLimit[`.tst.fuzzStateFailureHardLimit;1000]
 }

boundedRenderItems:{[] .tst.safePositiveLimit[`.tst.boundedRenderItemLimit;16] }
boundedRenderDepth:{[] .tst.safePositiveLimit[`.tst.boundedRenderDepthLimit;4] }

/ Render only bounded prefixes of containers. Unlike truncate[-3!x], this never
/ constructs a full textual representation of an attacker-sized value.
boundedSimpleText:{[x;limit]
    t:type x;
    if[11h=t;
        :.tst.capString[
            "<symbol list count=",string[count x],">";limit]];
    if[20h<=t;
        :.tst.capString[
            "<list type=",string[t]," count=",string[count x],">";limit]];
    n:.tst.boundedRenderItems[]&count x;
    prefix:n#x;
    text:-3!prefix;
    if[(count x)>n;
        text:text," ... [",string[(count x)-n]," more]"];
    .tst.capString[text;limit]
 };

boundedGeneralText:{[x;limit;depth]
    n:.tst.boundedRenderItems[]&count x;
    itemLimit:1|limit div 1|n;
    parts:();
    i:0;
    while[i<n;
        parts,:enlist .tst.boundedValueTextBody[x i;itemLimit;depth+1];
        i+:1;
    ];
    text:"[",("; " sv parts),"]";
    if[(count x)>n;
        text:text," ... [",string[(count x)-n]," more]"];
    .tst.capString[text;limit]
 };

boundedDictText:{[x;limit;depth]
    ks:key x;
    if[98h=type ks;
        :.tst.capString[
            "<keyed table rows=",string[count x],">";limit]];
    vals:value x;
    n:.tst.boundedRenderItems[]&count ks;
    itemLimit:1|limit div 1|n;
    parts:();
    i:0;
    while[i<n;
        kText:.tst.boundedValueTextBody[ks i;itemLimit div 2;depth+1];
        vText:.tst.boundedValueTextBody[vals i;itemLimit div 2;depth+1];
        parts,:enlist kText,":",vText;
        i+:1;
    ];
    text:"{",("; " sv parts),"}";
    if[(count ks)>n;
        text:text," ... [",string[(count ks)-n]," more]"];
    .tst.capString[text;limit]
 };

boundedValueTextBody:{[x;limit;depth]
    if[1>limit; :""];
    t:type x;
    if[10h=t; :.tst.capString[x;limit]];
    if[-11h=t; :.tst.capString["<symbol>";limit]];
    if[t<0; :.tst.capString[string x;limit]];
    if[depth>=.tst.boundedRenderDepth[];
        :.tst.capString[
            "<",string[t]," value depth limit>";limit]];
    if[0h=t; :.tst.boundedGeneralText[x;limit;depth]];
    if[98h=t;
        cs:cols x;
        cs:(.tst.boundedRenderItems[]&count cs)#cs;
        colsText:.tst.boundedSimpleText[cs;limit div 2];
        :.tst.capString[
            "<table rows=",string[count x]," cols=",
            .tst.capString[colsText;limit div 2],">";
            limit]
    ];
    if[99h=t; :.tst.boundedDictText[x;limit;depth]];
    if[t within 1 97h; :.tst.boundedSimpleText[x;limit]];
    .tst.capString["<function type ",string[t],">";limit]
 };

boundedValueText:{[x;limit]
    cap:.tst.capLimit limit;
    if[1>cap; :""];
    text:.[.tst.boundedValueTextBody;(x;cap;0);
      {[e] "<value could not be rendered>"}];
    .tst.capString[text;cap]
 };

validateFuzzRuns:{[runs]
    if[not (type runs) in -5 -6 -7h;
        '"fuzz option `runs` must be an integer scalar"];
    if[null runs; '"fuzz option `runs` must be finite"];
    if[.tst.integerIsInfinite runs; '"fuzz option `runs` must be finite"];
    if[1>runs; '"fuzz option `runs` must be positive"];
    limit:.tst.fuzzRunLimit[];
    if[runs>limit;
        '"fuzz option `runs` exceeds safety limit ",string limit];
    "j"$runs
 };

fuzzListLengthLimit:{[]
    configured:@[get;`.tst.fuzzListMaxLength;100];
    if[not (type configured) in -5 -6 -7h; :100];
    if[null configured; :100];
    if[.tst.integerIsInfinite configured; :100];
    if[1>configured; :100];
    "j"$(configured&.tst.fuzzListHardLimit[])
 };

validateBulkFuzz:{[x;runs]
    runs:.tst.validateFuzzRuns runs;
    runLimit:.tst.pickFuzzRunLimit[];
    if[runs>runLimit;
        '"pickFuzz run count exceeds bulk safety limit ",string runLimit];
    nodes:.tst.validateFuzzVarsBudget[x;"generator";0;0];
    weight:nodes*.tst.fuzzListLengthLimit[];
    budget:.tst.pickFuzzNodeLimit[];
    if[weight>budget; '"fuzz generator shape exceeds bulk output budget"];
    if[runs>budget div weight;
        '"pickFuzz estimated output exceeds bulk safety budget ",
            string budget];
    runs
 };

validateMaxFailRate:{[rate]
    if[not (type rate) in -4 -5 -6 -7 -8 -9h;
        '"fuzz option `maxFailRate` must be a numeric scalar"];
    r:"f"$rate;
    if[null r; '"fuzz option `maxFailRate` must be finite"];
    if[(r=0w) or r=-0w; '"fuzz option `maxFailRate` must be finite"];
    if[-1=.tst.exactFloatSign r;
        '"fuzz option `maxFailRate` must be between 0 and 1"];
    if[1=.tst.exactFloatSign[r-1f];
        '"fuzz option `maxFailRate` must be between 0 and 1"];
    r
 };

validateFuzzDictBudget:{[x;path;depth;nodes]
    names:key x;
    if[0=count names; '"fuzz ",path," dictionary must not be empty"];
    if[not 11h=type names;
        '"fuzz ",path," dictionary keys must be symbols"];
    if[(count names)>.tst.fuzzGeneratorNodes[];
        '"fuzz ",path," dictionary exceeds generator node limit"];
    if[any null names; '"fuzz ",path," dictionary keys must not be null"];
    if[(count names)<>count distinct names;
        '"fuzz ",path," dictionary keys must be unique"];
    vals:value x;
    i:0;
    while[i<count names;
        nodes:.tst.validateFuzzVarsBudget[
            vals i;path,"[",string[i],"]";depth+1;nodes];
        i+:1;
    ];
    nodes
 };

validateFuzzVarsBudget:{[x;path;depth;nodes]
    if[depth>.tst.fuzzGeneratorDepth[];
        '"fuzz ",path," exceeds generator depth limit"];
    nodes+:1;
    if[nodes>.tst.fuzzGeneratorNodes[];
        '"fuzz generator specification exceeds node limit"];
    t:type x;
    if[-11h=t; :nodes];                       / known type name or literal symbol
    if[11h=t;
        if[0=count x; '"fuzz ",path," symbol choices must not be empty"];
        if[(count x)>.tst.fuzzGeneratorChoiceLimit[];
            '"fuzz ",path," symbol choices exceed choice safety limit ",
                string .tst.fuzzGeneratorChoiceLimit[]];
        :nodes
    ];
    if[t within 100 104h;
        arity:.tst.safeCallableArity x;
        / q reports an implicit-argument lambda with one `x even when its body
        / uses no arguments; such lambdas are the established generator form.
        if[not arity in 0 1;
            '"fuzz ",path," generator must be callable without arguments"];
        :nodes
    ];
    if[99h=t; :.tst.validateFuzzDictBudget[x;path;depth;nodes]];
    if[98h=t; '"fuzz ",path," does not accept a table generator"];
    if[0h=t;
        if[0=count x;
            '"fuzz ",path," general-list choices must not be empty"];
        if[(count x)>.tst.fuzzGeneratorChoiceLimit[];
            '"fuzz ",path," general-list choices exceed choice safety limit ",
                string .tst.fuzzGeneratorChoiceLimit[]];
        :nodes
    ];
    if[0<t;
        if[not t in key .tst.typeFuzzC;
            '"fuzz ",path," has unsupported list type ",string t];
        if[(count x)>.tst.fuzzGeneratorChoiceLimit[];
            '"fuzz ",path," typed choices exceed choice safety limit ",
                string .tst.fuzzGeneratorChoiceLimit[]];
        :nodes
    ];
    nodes
 };

validateFuzzVars:{[x;path]
    .tst.validateFuzzVarsBudget[x;path;0;0];
    1b
 };

/ Add to a generated-value budget without allowing long overflow to wrap.
addGeneratedFuzzWeight:{[state;amount;limit;path]
    if[amount>limit-state`weight;
        '"fuzz generated ",path," exceeds total value safety limit ",
            string limit];
    state[`weight]+:amount;
    state
 };

addGeneratedFuzzNodes:{[state;amount;path]
    limit:.tst.fuzzGeneratedNodeLimit[];
    if[amount>limit-state`nodes;
        '"fuzz generated ",path," exceeds structural node safety limit ",
            string limit];
    state[`nodes]+:amount;
    state
 };

generatedFuzzTableCells:{[rows;width;limit;path]
    if[rows>limit;
        '"fuzz generated ",path," row count exceeds value safety limit ",
            string limit];
    if[width>limit;
        '"fuzz generated ",path," column count exceeds value safety limit ",
            string limit];
    if[(0<rows) and width>limit div rows;
        '"fuzz generated ",path," table cell count exceeds value safety limit ",
            string limit];
    rows*width
 };

/ Typed vectors and the row-by-column table footprint are counted in O(1).
/ Only general/dictionary nesting is traversed, under independent depth/node
/ limits. Exhaustion always rejects before the value reaches user property code.
validateGeneratedFuzzBudget:{[x;path;depth;state;limit]
    if[depth>.tst.fuzzGeneratedDepthLimit[];
        '"fuzz generated ",path," exceeds value depth safety limit"];
    state:.tst.addGeneratedFuzzNodes[state;1;path];
    t:type x;

    if[(t<0) or 100<=t;
        :.tst.addGeneratedFuzzWeight[state;1;limit;path]];

    if[0h=t;
        n:count x;
        if[n>limit;
            '"fuzz generated ",path," container exceeds value safety limit ",
                string limit];
        state:.tst.addGeneratedFuzzWeight[state;n;limit;path];
        nodeLimit:.tst.fuzzGeneratedNodeLimit[];
        if[n>nodeLimit-state`nodes;
            '"fuzz generated ",path,
                " exceeds structural node safety limit ",string nodeLimit];
        i:0;
        while[i<n;
            state:.tst.validateGeneratedFuzzBudget[
                x i;path,"[",string[i],"]";depth+1;state;limit];
            i+:1;
        ];
        :state
    ];

    if[98h=t;
        rows:count x;
        width:count cols x;
        cells:.tst.generatedFuzzTableCells[rows;width;limit;path];
        state:.tst.addGeneratedFuzzWeight[state;cells;limit;path];
        nodeLimit:.tst.fuzzGeneratedNodeLimit[];
        if[width>nodeLimit-state`nodes;
            '"fuzz generated ",path,
                " exceeds structural node safety limit ",string nodeLimit];
        columns:value flip x;
        i:0;
        while[i<width;
            column:columns i;
            columnPath:path,".column[",string[i],"]";
            if[0h=type column;
                state:.tst.validateGeneratedFuzzBudget[
                    column;columnPath;depth+1;state;limit]
            ];
            if[not 0h=type column;
                state:.tst.addGeneratedFuzzNodes[state;1;columnPath]
            ];
            i+:1;
        ];
        :state
    ];

    if[99h=t;
        n:count x;
        if[n>limit div 2;
            '"fuzz generated ",path,
                " dictionary exceeds value safety limit ",string limit];
        state:.tst.addGeneratedFuzzWeight[state;2*n;limit;path];
        ks:key x;
        vals:value x;
        if[(type ks) in 0 98 99h;
            state:.tst.validateGeneratedFuzzBudget[
                ks;path,".keys";depth+1;state;limit]];
        if[(type vals) in 0 98 99h;
            state:.tst.validateGeneratedFuzzBudget[
                vals;path,".values";depth+1;state;limit]];
        :state
    ];

    / All remaining positive types are simple vectors/enumerations.
    n:count x;
    if[n>limit;
        '"fuzz generated ",path," container exceeds value safety limit ",
            string limit];
    .tst.addGeneratedFuzzWeight[state;n;limit;path]
 };

validateGeneratedFuzzValue:{[x;requestedLimit]
    limit:requestedLimit;
    if[not (type limit) in -5 -6 -7h; limit:.tst.fuzzGeneratedValueLimit[]];
    if[(null limit) or .tst.integerIsInfinite[limit] or 1>limit;
        limit:.tst.fuzzGeneratedValueLimit[]];
    limit:"j"$(1000000&limit);
    state:`weight`nodes!0 0;
    .tst.validateGeneratedFuzzBudget[x;"value";0;state;limit];
    1b
 };

validateFuzzExpec:{[expec]
    if[not 99h=type expec; '"fuzz runner expects an expectation dictionary"];
    required:`code`runs`vars`maxFailRate;
    if[not all required in key expec;
        missing:required except key expec;
        '"fuzz expectation missing field(s): "," " sv string missing];
    if[`props in key expec;
        props:expec`props;
        if[not ((99h=type props) or (type props) in -20 20h);
            '"fuzz expectation `props` must be a dictionary"]
    ];
    if[not (type expec`code) within 100 112h;
        '"fuzz expectation `code` must be a function"];
    arity:.tst.safeCallableArity expec`code;
    if[1<>arity; '"fuzz expectation `code` must accept exactly one argument"];
    expec[`runs]:.tst.validateFuzzRuns expec`runs;
    expec[`maxFailRate]:.tst.validateMaxFailRate expec`maxFailRate;
    .tst.validateFuzzVars[expec`vars;"`vars`"];
    expec
 };

callFuzzGenerator:{[f]
    generatedValue:f[];
    .tst.validateGeneratedFuzzValue[
        generatedValue;.tst.fuzzGeneratedValueLimit[]];
    generatedValue
 };

pickFuzzRaw:{[x;runs]
    t:type x;

    / Symbol form - lookup type name, retaining unknown symbols as literals.
    if[-11h=t;
        if[x in key .tst.typeFuzzN;
            :.tst.genFuzzValues[.tst.typeFuzzN[x];runs]
        ];
        :runs#x
    ];

    if[11h=t; :runs?x];
    if[t within 100 104h;
        :{[f;i] .tst.callFuzzGenerator f}[x] each til runs];
    if[99h=t; :flip .tst.pickFuzzRaw[;runs] each x];
    if[0<=t; :.tst.pickListFuzzRaw[x;runs]];
    runs#x
 };

pickFuzz:{[x;runs]
    runs:.tst.validateBulkFuzz[x;runs];
    values:.tst.pickFuzzRaw[x;runs];
    .tst.validateGeneratedFuzzValue[values;.tst.pickFuzzNodeLimit[]];
    values
 };

/ Generate exactly one value without allocating a run-sized input collection.
pickFuzzOneRaw:{[x]
    t:type x;
    if[-11h=t;
        if[x in key .tst.typeFuzzN;
            :first .tst.genFuzzValues[.tst.typeFuzzN[x];1]];
        :x
    ];
    if[11h=t; :first 1?x];
    if[t within 100 104h; :.tst.callFuzzGenerator x];
    if[99h=t; :(key x)!.tst.pickFuzzOneRaw each value x];
    if[0<=t; :first .tst.pickListFuzzRaw[x;1]];
    x
 };

/ Helper: generate fuzz values of a specific type.
.tst.genFuzzValues:{[default;runs]
    runs:.tst.validateFuzzRuns runs;
    if[runs>.tst.pickFuzzRunLimit[];
        '"fuzz generation run count exceeds bulk safety limit"];
    t:type default;
    $[t=-1h; runs?01b;
      t=-2h; runs?0Ng;
      t=-4h; runs?0x0+til 256;
      t=-5h; runs?32767h;
      t=-6h; runs?2000000000i;
      t=-7h; runs?9000000000000j;
      t=-8h; runs?1e10;
      t=-9h; runs?1e15;
      t=-10h; runs?.Q.a;
      t=-11h; runs?`a`b`c`d`e`f`g;
      runs#default]
 };

pickListFuzzRaw:{[x;runs]
    tc:abs type x;
    if[0=count x;
        if[not tc in key .tst.typeFuzzC;
            '"empty fuzz list has unsupported type ",string tc];
        :{[tc;len] len?.tst.typeFuzzC[tc]}[tc] each
            runs?.tst.fuzzListLengthLimit[]
    ];
    if[0h=type x; :runs?x];
    if[(1=count distinct x) and null first x;
        :{[tc;len] len?.tst.typeFuzzC[tc]}[tc] each runs?count x
    ];
    if[1=count distinct x;
        :{[x;len] len?x}[first x] each runs?count x
    ];
    runs?x
 };

pickListFuzz:{[x;runs]
    runs:.tst.validateBulkFuzz[x;runs];
    values:.tst.pickListFuzzRaw[x;runs];
    .tst.validateGeneratedFuzzValue[values;.tst.pickFuzzNodeLimit[]];
    values
 };

fuzzErrorText:{[prefix;err]
    limit:.tst.fuzzReproLimit[];
    root:$[(count err)<=limit;err;limit#err];
    remaining:0|limit-count root;
    prefix:.tst.capString[prefix;remaining];
    prefix,root
 };

appendBoundedFuzzFailure:{[failures;message]
    limit:.tst.fuzzStateFailureLimit[];
    keep:(0|limit-1)&count failures;
    (keep#failures),enlist message
 };

fuzzCollectedState:{[fuzz;errText]
    st:@[get;`.tst.assertState;.tst.defaultAssertState];
    valid:99h=type st;
    if[valid; valid:all `failures`assertsRun in key st];
    forceFailure:0b;
    primaryError:"";
    if[not valid;
        primaryError:"Error during fuzz run: assertion state became invalid";
        failures:enlist primaryError;
        forceFailure:1b;
        asserts:0
    ];
    if[valid;
        failures:st`failures;
        asserts:st`assertsRun;
        if[not 0h=type failures;
            primaryError:"Error during fuzz run: assertion failures became invalid";
            failures:enlist primaryError;
            forceFailure:1b];
        if[0h=type failures;
            if[(count failures)>.tst.fuzzStateFailureLimit[];
                primaryError:
                    "Error during fuzz run: assertion failure state exceeded safety limit";
                failures:.tst.appendBoundedFuzzFailure[
                    failures;primaryError];
                forceFailure:1b]
        ];
        if[not (type asserts) in -5 -6 -7h;
            primaryError:"Error during fuzz run: assertion count became invalid";
            failures:.tst.appendBoundedFuzzFailure[
                failures;primaryError];
            forceFailure:1b;
            asserts:0];
        if[(type asserts) in -5 -6 -7h;
            if[(null asserts) or .tst.integerIsInfinite[asserts] or
               (0>asserts) or asserts>.tst.fuzzAssertionLimit[];
                primaryError:"Error during fuzz run: assertion count exceeded safety contract";
                failures:.tst.appendBoundedFuzzFailure[
                    failures;primaryError];
                forceFailure:1b;
                asserts:0]
        ];
    ];
    if[count errText;
        failures:.tst.appendBoundedFuzzFailure[failures;errText];
        if[not forceFailure;
            forceFailure:1b;
            primaryError:errText]];
    `failedFuzz`fuzzFailures`assertsRun`forceFailure`primaryError!(
        fuzz;failures;"j"$asserts;forceFailure;primaryError)
 };

executeFuzzCode:{[code;fuzz]
    code fuzz;
    .tst.fuzzCollectedState[fuzz;""]
 };

fuzzRunCollector:{[code;fuzz]
    origState:.tst.assertState;
    origSuppress:.tst.suppressAssertionDiff;
    .tst.assertState:.tst.defaultAssertState;
    .tst.suppressAssertionDiff:1b;
    outcome:.[.tst.executeFuzzCode;(code;fuzz);
        {[v;e] .tst.fuzzCollectedState[v;.tst.fuzzErrorText["Error during fuzz run: ";e]]}[fuzz;]];
    .tst.assertState:origState;
    .tst.suppressAssertionDiff:origSuppress;
    outcome
 };

fuzzGeneratorFailure:{[err]
    msg:.tst.fuzzErrorText["Error during fuzz generation: ";err];
    `failedFuzz`fuzzFailures`assertsRun`forceFailure`primaryError!(
        (::);enlist msg;0;1b;msg)
 };

/ Generator code is not a test body: it may return a value or throw, but it may
/ not leak assertions or corrupt the runner's assertion/suppression state.
generateFuzzOne:{[vars]
    .tst.assertState:.tst.defaultAssertState;
    .tst.suppressAssertionDiff:1b;
    generated:@[{[v]
        generatedValue:.tst.pickFuzzOneRaw v;
        .tst.validateGeneratedFuzzValue[
            generatedValue;.tst.fuzzGeneratedValueLimit[]];
        (`ok;generatedValue)
      };vars;
        {[e] (`error;e)}];
    generatedState:@[get;`.tst.assertState;`invalid];
    generatedSuppress:@[get;`.tst.suppressAssertionDiff;0b];
    .tst.assertState:.tst.defaultAssertState;
    .tst.suppressAssertionDiff:1b;
    if[`error~first generated; :generated];
    if[not generatedState~.tst.defaultAssertState;
        :(`error;"assertion state modified during fuzz generation")];
    if[not 1b~generatedSuppress;
        :(`error;"assertion suppression state modified during fuzz generation")];
    generated
 };

fuzzFailureText:{[failure]
    limit:.tst.fuzzReproLimit[];
    .tst.boundedValueText[failure;limit]
 };

capFuzzFailures:{[failures]
    n:.tst.fuzzFailureItems[]&count failures;
    shown:n#failures;
    rendered:.tst.fuzzFailureText each shown;
    if[(count failures)>n;
        rendered,:enlist "... [",string[(count failures)-n],
            " more failure(s)]"];
    rendered
 };

fuzzDiagnosticLimit:{[runs]
    n:@[get;`.tst.output.fuzzLimit;0];
    if[not (type n) in -5 -6 -7h; :0];
    if[null n; :0];
    if[.tst.integerIsInfinite n; :0];
    if[0>n; :0];
    "j"$(n&runs&.tst.fuzzDiagnosticCap[])
 };

emptyFuzzState:{[]
    `failCount`assertsRun`failedFuzz`failureMessages`hasFirst`firstFailure`canShrink`shrunkFailure`forceError!(
        0;0;();();0b;(::);0b;(::);"")
 };

recordFuzzOutcome:{[state;outcome;retain;canShrink]
    state[`assertsRun]+:outcome`assertsRun;
    if[0=count outcome`fuzzFailures; :state];
    state[`failCount]+:1;
    if[outcome`forceFailure;
        if[0=count state`forceError;
            state[`forceError]:outcome`primaryError]];
    if[not state`hasFirst;
        state[`hasFirst]:1b;
        state[`firstFailure]:outcome`failedFuzz;
        state[`canShrink]:canShrink;
    ];
    if[(count state`failedFuzz)<retain;
        state[`failedFuzz]:state[`failedFuzz],enlist outcome`failedFuzz;
        state[`failureMessages]:state[`failureMessages],
            enlist .tst.capFuzzFailures outcome`fuzzFailures;
    ];
    state
 };

shrinkWithinBudget:{[started;steps]
    if[steps>=.tst.fuzzShrinkSteps[]; :0b];
    elapsed:"j"$.z.p-started;
    elapsed<1000000*.tst.fuzzShrinkMillis[]
 };

fuzzCandidateFails:{[code;candidate]
    result:.tst.fuzzRunCollector[code;candidate];
    if[result`forceFailure; 'result`primaryError];
    0<count result`fuzzFailures
 };

/ Iteratively bisect list-like failures. Both candidate order and limits are fixed.
shrink:{[code;typeCode;val]
    if[not (type val) within 0 19h; :val];
    current:val;
    steps:0;
    started:.z.p;
    done:0b;
    while[(not done) and .tst.shrinkWithinBudget[started;steps];
        if[1>=count current; done:1b];
        if[not done;
            half:floor (count current)%2;
            left:half#current;
            right:half _ current;
            moved:0b;
            if[.tst.shrinkWithinBudget[started;steps];
                steps+:1;
                if[.tst.fuzzCandidateFails[code;left];
                    current:left;
                    moved:1b]
            ];
            if[(not moved) and .tst.shrinkWithinBudget[started;steps];
                steps+:1;
                if[.tst.fuzzCandidateFails[code;right];
                    current:right;
                    moved:1b]
            ];
            if[not moved; done:1b];
        ];
    ];
    current
 };

applyFuzzShrink:{[expec;state]
    if[not state`hasFirst; :state];
    if[not state`canShrink; :state];
    if[not @[get;`.tst.app.quiet;0b];
        -1 "  Fuzz failure detected. Attempting to shrink..."];
    attempt:.[{[e;v] (`ok;.tst.shrink[e`code;abs type v;v])};
        (expec;state`firstFailure);{[e] (`error;e)}];
    if[`error~first attempt;
        state[`shrunkFailure]:state`firstFailure;
        shrinkError:.tst.fuzzErrorText["Error during fuzz shrink: ";last attempt];
        if[0=count state`forceError; state[`forceError]:shrinkError];
        if[count state`failureMessages;
            msgs:state`failureMessages;
            msgs[0]:(msgs 0),enlist shrinkError;
            state[`failureMessages]:msgs;
        ];
        :state
    ];
    state[`shrunkFailure]:last attempt;
    if[not @[get;`.tst.app.quiet;0b];
        -1 "  Minimal Reproducible Case: ",
            .tst.fuzzFailureText state`shrunkFailure];
    state
 };

completeFuzzResult:{[expec;state]
    expec[`failedFuzz]:state`failedFuzz;
    expec[`fuzzFailureMessages]:state`failureMessages;
    expec[`fuzzFailureCount]:state`failCount;
    expec[`shrunkFailure]:state`shrunkFailure;
    expec[`failRate]:(state`failCount)%expec`runs;
    expec[`assertsRun]:state`assertsRun;
    exceeded:1=.tst.exactFloatSign[
        expec[`failRate]-expec`maxFailRate];
    forced:0<count state`forceError;
    if[exceeded or forced;
        msg:$[forced;state`forceError;
            .tst.capString[
                "Over max failure rate. Shrunk: ",
                    .tst.fuzzFailureText[state`shrunkFailure],
                    " (",string[state`failCount]," of ",string[expec`runs],
                    " runs failed)";
                .tst.fuzzReproLimit[]]];
        expec[`failures]:enlist msg;
        expec[`result]:`fuzzFail;
        :expec
    ];
    expec[`failures]:();
    expec[`result]:`pass;
    expec
 };

runFuzzBody:{[expec]
    retain:.tst.fuzzDiagnosticLimit expec`runs;
    state:.tst.emptyFuzzState[];
    i:0;
    while[i<expec`runs;
        .tst.assertState:.tst.defaultAssertState;
        .tst.suppressAssertionDiff:1b;
        generated:.tst.generateFuzzOne expec`vars;
        if[`error~first generated;
            outcome:.tst.fuzzGeneratorFailure last generated;
            state:.tst.recordFuzzOutcome[state;outcome;retain;0b]
        ];
        if[`ok~first generated;
            outcome:.tst.fuzzRunCollector[expec`code;last generated];
            state:.tst.recordFuzzOutcome[state;outcome;retain;1b]
        ];
        i+:1;
    ];
    state:.tst.applyFuzzShrink[expec;state];
    .tst.completeFuzzResult[expec;state]
 };

fatalFuzzResult:{[expec;err]
    msg:.tst.fuzzErrorText["Error during fuzz execution: ";err];
    retain:.tst.fuzzDiagnosticLimit expec`runs;
    expec[`failedFuzz]:$[0<retain;enlist (::);()];
    expec[`fuzzFailureMessages]:$[0<retain;enlist enlist msg;()];
    expec[`fuzzFailureCount]:expec`runs;
    expec[`shrunkFailure]:(::);
    expec[`failRate]:1f;
    expec[`assertsRun]:0;
    expec[`failures]:enlist msg;
    expec[`result]:`fuzzFail;
    expec
 };

runners[`fuzz]:{[expec]
    expec:.tst.validateFuzzExpec expec;
    origState:.tst.assertState;
    origSuppress:.tst.suppressAssertionDiff;
    .tst.suppressAssertionDiff:1b;
    outcome:@[{[e] (`ok;.tst.runFuzzBody e)};expec;{[e] (`error;e)}];
    .tst.assertState:origState;
    .tst.suppressAssertionDiff:origSuppress;
    if[`error~first outcome; :.tst.fatalFuzzResult[expec;last outcome]];
    last outcome
 };

\d .
