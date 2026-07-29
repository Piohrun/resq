/ Focused helpers always restore global state before propagating a body error.
.tst.assertHardening.capture:{[body]
    @[
        {[fn] (`ok;enlist fn[])};
        body;
        {[err] (`error;enlist err)}]
 };

.tst.assertHardening.withGlobals:{[names;replacements;body]
    originals:get each names;
    i:0;
    while[i<count names;
        (names i) set (replacements i);
        i+:1];
    outcome:.tst.assertHardening.capture body;
    i:0;
    while[i<count names;
        (names i) set (originals i);
        i+:1];
    if[`error~first outcome; 'first last outcome];
    first last outcome
 };

.tst.assertHardening.captureAssertion:{[body]
    originalState:.tst.assertState;
    originalSuppress:.tst.suppressAssertionDiff;
    .tst.assertState:``failures`assertsRun!(::;();0);
    .tst.suppressAssertionDiff:1b;
    outcome:.tst.assertHardening.capture body;
    observed:.tst.assertState;
    .tst.assertState:originalState;
    .tst.suppressAssertionDiff:originalSuppress;
    `outcome`state!(outcome;observed)
 };

.tst.assertHardening.withColorState:{[body]
    originalUse:.tst.useColor;
    originalDiff:.tst.diffColors;
    originalLinux:.utl.isLinux;
    originalNoColor:getenv `NO_COLOR;
    outcome:.tst.assertHardening.capture body;
    .tst.useColor:originalUse;
    .tst.diffColors:originalDiff;
    .utl.isLinux:originalLinux;
    setenv[`NO_COLOR;originalNoColor];
    if[`error~first outcome; 'first last outcome];
    first last outcome
 };

.tst.assertHardening.probe:0;
.tst.assertHardening.renderProbe:0;
.tst.assertHardening.throwRestoreProbe:{[] '"restore helper probe"};
.tst.assertHardening.renderProbeFn:{[message]
    .tst.assertHardening.renderProbe+:1;
    "rendered"
 };
.tst.assertHardening.cyclicCallable:{
    [] .tst.assertHardening.cyclicCallable[]
 };
.tst.assertHardening.corruptFinalExtraction:{[]
    expec:`failures`assertsRun`result!(
        ();
        0;
        `pending);
    runnerState:`func`expec`installed!(
        {
            must[0b;"failure before final extraction"];
            .tst.assertState:42;
            ::
        };
        expec;
        ());
    .tst.finishFixtureTest runnerState
 };
.tst.assertHardening.predicateCases:(
    {must[4#1b;"bounded must"]};
    {mustne[til 4;10+til 4]};
    {mustlt[til 4;10+til 4]};
    {mustgt[10+til 4;til 4]};
    {mustlike[4#"a";"a*"]};
    {mustin[0;til 4]};
    {mustnin[-1;til 4]};
    {mustwithin[til 4;0 4]};
    {mustdelta[0;til 4;til 4]});

.tst.desc["assertion hardening: bounded rendering"]{
    should["render huge values from bounded prefixes"]{
        hugeString:200000#"x";
        hugeVector:til 200000;
        hugeTable:([] a:til 100000;b:100000#hugeString 0);
        hugeDict:(til 100000)!til 100000;

        stringText:.tst.renderValue[hugeString;512];
        vectorText:.tst.renderValue[hugeVector;512];
        tableText:.tst.renderValue[hugeTable;512];
        dictText:.tst.renderValue[hugeDict;512];

        must[count[stringText]<=512;"huge string render must be capped"];
        must[count[vectorText]<=512;"huge vector render must be capped"];
        must[count[tableText]<=512;"huge table render must be capped"];
        must[count[dictText]<=512;"huge dictionary render must be capped"];
        must[0<count stringText ss "truncated";
            "huge string render must disclose truncation"];
        must[0<count vectorText ss "truncated";
            "huge vector render must disclose truncation"];
    };

    should["render callables projections and deep values without inspection"]{
        lambdaText:.tst.renderValue[{x+1};256];
        projectionText:.tst.renderValue[+[1;];256];
        cyclicText:.tst.renderValue[
            .tst.assertHardening.cyclicCallable;
            256];
        deepText:.tst.renderValue[20 enlist/0;256];
        lambdaText mustlike "*callable*";
        projectionText mustlike "*callable*";
        cyclicText mustlike "*callable*";
        must[count[deepText]<=256;"deep render must remain bounded"];
        must[
            (0<count deepText ss "limit") or
            0<count deepText ss "omitted";
            "deep render must disclose its structural budget"];
    };

    should["treat mutable renderer budgets only as lowerable seams"]{
        names:(
            `.tst.DIAGNOSTIC_MAX_CHARS;
            `.tst.VALUE_RENDER_MAX_DEPTH;
            `.tst.VALUE_RENDER_MAX_NODES;
            `.tst.VALUE_RENDER_MAX_CHILDREN);
        hostile:(0W;"bad";{x};0N);
        body:{
            text:.tst.renderValue[
                (100000#"x";til 100000;10 enlist/0);
                1000000000];
            must[count[text]<=50000;
                "corrupt or raised renderer seams must not raise hard caps"];
        };
        .tst.assertHardening.withGlobals[names;hostile;body];
    };

    should["clamp direct caps and account tiny dictionary node budgets"]{
        .tst.capLimit[1000000000] musteq 50000;
        capped:.tst.capString[100000#"x";1000000000];
        must[count[capped]<=50000;
            "direct capString calls must obey the literal ceiling"];

        body:{
            ordinary:.tst.renderValue[
                `a`b!(enlist 1;enlist 2);
                512];
            keyed:.tst.renderValue[
                `id xkey ([] id:1 2;v:10 20);
                512];
            ordinary mustlike "*node limit*";
            keyed mustlike "*node limit*";
        };
        .tst.assertHardening.withGlobals[
            enlist `.tst.VALUE_RENDER_MAX_NODES;
            enlist 2;
            body];
    };

    should["distinguish generic null from type-101 unary primitives"]{
        .tst.renderValue[::;64] mustmatch "::";
        primitiveText:.tst.renderValue[neg;128];
        primitiveText mustlike "*callable/opaque type=101*";
        keyedText:.tst.renderValue[
            `id xkey ([] id:1 2;v:10 20);
            512];
        keyedText mustlike "keyed(*";
    };

    should["fall back safely when diagnostic cap globals are missing"]{
        originalChars:.tst.DIAGNOSTIC_MAX_CHARS;
        delete DIAGNOSTIC_MAX_CHARS from `.tst;
        rendered:.tst.assertHardening.capture[
            {.tst.renderValue[100000#"x";1000000000]}];
        .tst.DIAGNOSTIC_MAX_CHARS:originalChars;
        if[`error~first rendered; 'first last rendered];
        text:first last rendered;
        must[count[text]<=50000;
            "missing renderer cap must use the literal default"];

        originalProbe:.tst.DIFF_PROBE_ITEMS;
        delete DIFF_PROBE_ITEMS from `.tst;
        limited:.tst.assertHardening.capture[
            {.tst.diffProbeLimit[]}];
        .tst.DIFF_PROBE_ITEMS:originalProbe;
        if[`error~first limited; 'first last limited];
        first[last limited] musteq 4096;
    };

    should["restore mutated cap globals when the protected body throws"]{
        original:.tst.VALUE_RENDER_MAX_CHILDREN;
        mustthrow[
            "*restore helper probe*";
            {
                .tst.assertHardening.withGlobals[
                    enlist `.tst.VALUE_RENDER_MAX_CHILDREN;
                    enlist 1;
                    .tst.assertHardening.throwRestoreProbe]
            }];
        .tst.VALUE_RENDER_MAX_CHILDREN mustmatch original;
    };

};

.tst.desc["assertion hardening: deterministic diff"]{
    should["find late list string table and dictionary mismatches"]{
        n:100000;
        leftVector:til n;
        rightVector:leftVector;
        rightVector[n-1]:-1;
        vectorDiff:.tst.diff[leftVector;rightVector];
        must[
            any {x like "*99999*"} each vectorDiff;
            "late vector mismatch index must be found deterministically"];

        leftString:n#"a";
        rightString:leftString;
        rightString[n-1]:"b";
        stringDiff:.tst.diff[leftString;rightString];
        must[
            any {x like "*99999*"} each stringDiff;
            "late string mismatch index must be found deterministically"];

        leftTable:([] a:til n;b:til n);
        rightTable:leftTable;
        rightTable[n-1;`b]:-1;
        tableDiff:.tst.diff[leftTable;rightTable];
        must[
            any {x like "*99999*"} each tableDiff;
            "late table mismatch row must be found deterministically"];

        leftDict:(til n)!til n;
        rightDict:leftDict;
        rightDict[n-1]:-1;
        dictDiff:.tst.diff[leftDict;rightDict];
        must[
            any {x like "*99999*"} each dictDiff;
            "late dictionary value mismatch must be found deterministically"];
    };

    should["report exhausted scans instead of returning an empty diff"]{
        body:{
            n:100000;
            left:(til n)!til n;
            right:left;
            right[n-1]:-1;
            result:.tst.diff[left;right];
            must[0<count result;"budgeted dictionary diff must not be empty"];
            must[
                any {0<count x ss "budget exhausted"} each result;
                "budget exhaustion must be explicit"];
        };
        .tst.assertHardening.withGlobals[
            enlist `.tst.DIFF_SCAN_ITEMS;
            enlist 4;
            body];
    };

    should["stop before re-comparing a huge equal nested prefix"]{
        hugePrefix:til 1000000;
        left:(hugePrefix;0);
        right:(hugePrefix;1);
        result:.tst.diffKnownMismatch[left;right];
        must[0<count result;
            "known mismatch diagnostics must never return empty"];
        must[
            any {0<count x ss "budget exhausted"} each result;
            "nested equality uncertainty must report budget exhaustion"];
        must[
            not any {"[1]:"~4#x} each result;
            "diagnostics must not invent a mismatch beyond an unknown prefix"];
    };

    should["bound huge common dictionary key prefixes"]{
        n:100000;
        leftKeys:til n;
        rightKeys:leftKeys;
        rightKeys[n-1]:n;
        left:leftKeys!til n;
        right:rightKeys!til n;
        result:.tst.diff[left;right];
        must[
            any {0<count x ss "99999"} each result;
            "late dictionary key mismatch position must be reported"];
    };

    should["bound zero-row ultra-wide table metadata scans"]{
        n:1000000;
        leftNames:n#`a;
        rightNames:leftNames;
        rightNames[n-1]:`b;
        emptyColumns:n#enlist `long$();
        left:flip leftNames!emptyColumns;
        right:flip rightNames!emptyColumns;
        result:.tst.diff[left;right];
        must[0<count result;"ultra-wide table diff must not be empty"];
        must[
            any {0<count x ss "budget exhausted"} each result;
            "ultra-wide metadata exhaustion must be explicit"];
    };

    should["bound deep recursion normalization lines and characters"]{
        deepLeft:20 enlist/0;
        deepRight:20 enlist/1;
        deepDiff:.tst.diff[deepLeft;deepRight];
        must[0<count deepDiff;"deep mismatch must not yield an empty diff"];
        must[
            any {0<count x ss "budget exhausted"} each deepDiff;
            "deep mismatch must disclose recursion exhaustion"];

        hostile:10000#enlist 1000#"x";
        normalized:.tst.normalizeDiff hostile;
        must[count[normalized]<=40;"normalizeDiff line count must be capped"];
        must[
            sum[count each normalized]<=20000;
            "normalizeDiff characters must be capped"];

        budgetBody:{
            limited:.tst.normalizeDiff 100#enlist 100#"x";
            must[count[limited]<=3;
                "lowered diff line budget must be exact"];
            serializedChars:
                (sum count each limited)+
                (0 | (count[limited]-1));
            must[serializedChars<=64;
                "lowered diff character budget must include separators"];
        };
        .tst.assertHardening.withGlobals[
            (
                `.tst.DIFF_MAX_LINES;
                `.tst.DIFF_MAX_CHARS);
            (3;64);
            budgetBody];
    };

    should["honour literal diff ceilings when seams are raised or corrupt"]{
        names:(
            `.tst.DIFF_MAX_DEPTH;
            `.tst.DIFF_MAX_NODES;
            `.tst.DIFF_MAX_LINES;
            `.tst.DIFF_MAX_CHARS;
            `.tst.DIFF_SCAN_ITEMS;
            `.tst.DIFF_TABLE_CELL_SCAN;
            `.tst.DIFF_COLUMN_SCAN;
            `.tst.DIFF_CHUNK_SIZE;
            `.tst.DIFF_MISMATCH_LIMIT;
            `.tst.DIFF_PROBE_ITEMS);
        hostile:(
            0W;
            "bad";
            1000000;
            1000000000;
            0W;
            {x};
            0N;
            1000000;
            0W;
            "corrupt");
        body:{
            result:.tst.diff[til 100000;neg til 100000];
            must[count[result]<=40;"raised diff seam must not raise line cap"];
            must[
                sum[count each result]<=20000;
                "raised diff seam must not raise character cap"];
        };
        .tst.assertHardening.withGlobals[names;hostile;body];
    };
};

.tst.desc["assertion hardening: resilient evaluation"]{
    should["record predicate renderer and diff failures exactly once"]{
        predicate:.tst.assertHardening.captureAssertion[
            {mustlt[{x};1]}];
        predicateState:predicate[`state];
        predicateState[`assertsRun] musteq 1;
        count[predicateState[`failures]] musteq 1;
        first[predicateState[`failures]] mustlike "*predicate failed*";

        renderBody:{
            .tst.assertHardening.captureAssertion[
                {musteq[10000#"x";10000#"y"]}]
        };
        rendered:.tst.assertHardening.withGlobals[
            enlist `.tst.renderNode;
            enlist {'"renderer probe"};
            renderBody];
        renderedState:rendered[`state];
        renderedState[`assertsRun] musteq 1;
        count[renderedState[`failures]] musteq 1;
        first[renderedState[`failures]] mustlike "*render unavailable*";

        diffBody:{
            .tst.assertHardening.captureAssertion[
                {musteq[1;2]}]
        };
        diffed:.tst.assertHardening.withGlobals[
            enlist `.tst.diffKnownMismatch;
            enlist {'"diff probe"};
            diffBody];
        diffState:diffed[`state];
        diffState[`assertsRun] musteq 1;
        count[diffState[`failures]] musteq 1;
    };

    should["trap arithmetic and malformed dirty comparisons contextually"]{
        arithmetic:.tst.assertHardening.captureAssertion[
            {mustdelta[{x};1;2]}];
        arithmeticState:arithmetic[`state];
        arithmeticState[`assertsRun] musteq 1;
        count[arithmeticState[`failures]] musteq 1;
        first[arithmeticState[`failures]] mustlike "*predicate failed*";

        dirty:.tst.assertHardening.captureAssertion[
            {mustlike[{x};("*x*";42)]}];
        dirtyState:dirty[`state];
        dirtyState[`assertsRun] musteq 1;
        count[dirtyState[`failures]] musteq 1;
    };

    should["cap final assertion messages at the configured safe limit"]{
        body:{
            result:.tst.assertHardening.captureAssertion[
                {musteq[100000#"a";100000#"b"]}];
            state:result[`state];
            state[`assertsRun] musteq 1;
            count[state[`failures]] musteq 1;
            must[count[first state[`failures]]<=256;
                "final assertion failure must obey reportLimit"];
        };
        .tst.assertHardening.withGlobals[
            enlist `.tst.output.reportLimit;
            enlist 256;
            body];
    };

    should["fail safely on tiny containers with hostile nested payloads"]{
        .tst.assertHardening.nestedPayload:til 100000;
        result:.tst.assertHardening.captureAssertion[
            {
                musteq[
                    enlist .tst.assertHardening.nestedPayload;
                    enlist .tst.assertHardening.nestedPayload]
            }];
        result[`state][`assertsRun] musteq 1;
        count[result[`state][`failures]] musteq 1;
        first[result[`state][`failures]]
            mustlike "*comparison budget exhausted*";

        diffResult:.tst.diff[
            enlist .tst.assertHardening.nestedPayload;
            enlist .tst.assertHardening.nestedPayload];
        must[
            any {0<count x ss "budget exhausted"} each diffResult;
            "public diff must report unknown nested equality explicitly"];
    };

    should["bound retained failure accumulation and sanitize counters"]{
        failureBody:{
            captured:.tst.assertHardening.captureAssertion[
                {
                    i:0;
                    while[i<20;
                        must[0b;1000#"failure"];
                        i+:1]
                }];
            state:captured[`state];
            state[`assertsRun] musteq 20;
            must[count[state[`failures]]<=3;
                "retained failure count must be capped"];
            must[
                sum[count each state[`failures]]<=128;
                "retained failure characters must be capped"];
            last[state[`failures]]
                mustlike "*additional assertion failures omitted*";
        };
        .tst.assertHardening.withGlobals[
            (
                `.tst.ASSERT_FAILURE_MAX_COUNT;
                `.tst.ASSERT_FAILURE_MAX_CHARS);
            (3;128);
            failureBody];

        malformedCounter:.tst.assertHardening.captureAssertion[
            {
                .tst.assertState.assertsRun:"corrupt";
                must[1b;"counter must recover"]
            }];
        malformedCounter[`state][`assertsRun]
            musteq 2;
        count[malformedCounter[`state][`failures]] musteq 1;
        first[malformedCounter[`state][`failures]]
            mustlike "*assertion state corrupted*";

        saturated:.tst.assertHardening.captureAssertion[
            {
                .tst.assertState.assertsRun:1000000;
                must[1b;"counter must saturate"]
            }];
        saturated[`state][`assertsRun]
            musteq 1000000;
    };

    should["retain bounded failure details before the omission marker"]{
        body:{
            .tst.assertHardening.captureAssertion[
                {
                    .tst.assertState.failures:
                        ("first";"second";"third";"fourth");
                    .tst.assertRecordFailure[
                        "retention probe";
                        "must not replace the retained prefix"]
                }]
        };
        captured:.tst.assertHardening.withGlobals[
            (
                `.tst.ASSERT_FAILURE_MAX_COUNT;
                `.tst.ASSERT_FAILURE_MAX_CHARS);
            (4;256);
            body];
        failures:captured[`state][`failures];
        count[failures] musteq 4;
        (failures 0) mustmatch "first";
        (failures 1) mustmatch "second";
        (failures 2) mustmatch "third";
        (failures 3)
            mustlike "*additional assertion failures omitted*";
    };

    should["short circuit message rendering after failure saturation"]{
        .tst.assertHardening.renderProbe:0;
        body:{
            .tst.assertHardening.captureAssertion[
                {
                    .tst.assertState.failures:
                        enlist .tst.assertFailureMarker;
                    .tst.assertRecordFailure[
                        "saturation probe";
                        {x}]
                }]
        };
        captured:.tst.assertHardening.withGlobals[
            enlist `.tst.assertMessageValue;
            enlist .tst.assertHardening.renderProbeFn;
            body];
        .tst.assertHardening.renderProbe musteq 0;
        count[captured[`state][`failures]] musteq 1;
        first[captured[`state][`failures]]
            mustmatch .tst.assertFailureMarker;
    };

    should["preserve failure status through malformed and missing state"]{
        malformed:.tst.assertHardening.captureAssertion[
            {
                must[0b;"failure before state corruption"];
                .tst.assertState:42;
                must[1b;"corruption repair must remain failed"]
            }];
        malformed[`state][`assertsRun]
            musteq 2;
        count[malformed[`state][`failures]] musteq 1;
        first[malformed[`state][`failures]]
            mustlike "*assertion state corrupted*";

        missing:.tst.assertHardening.captureAssertion[
            {
                .tst.assertState:
                    (enlist `failures)!enlist enlist "prior failure";
                must[1b;"missing state field must remain failed"]
            }];
        missing[`state][`assertsRun]
            musteq 2;
        count[missing[`state][`failures]] musteq 1;
        first[missing[`state][`failures]]
            mustlike "*assertion state corrupted*";
    };

    should["classify final state corruption as a framework error"]{
        captured:.tst.assertHardening.captureAssertion[
            .tst.assertHardening.corruptFinalExtraction];
        first[captured`outcome] mustmatch `error;
        (first last captured`outcome)
            mustlike "*assertion state corrupted*";
        captured[`state][`assertsRun] musteq 1;
        count[captured[`state][`failures]] musteq 1;
        first[captured[`state][`failures]]
            mustlike "*assertion state corrupted*";

        second:.tst.assertHardening.captureAssertion[
            .tst.assertHardening.corruptFinalExtraction];
        first[second`outcome] mustmatch `error;
        (sum (
            captured[`state][`assertsRun];
            second[`state][`assertsRun]))
                musteq 2;
    };

    should["preserve mustne compatibility and bound every predicate path"]{
        passing:.tst.assertHardening.captureAssertion[
            {mustne[1 2;3 4]}];
        passing[`state][`assertsRun] musteq 1;
        count[passing[`state][`failures]] musteq 0;

        failing:.tst.assertHardening.captureAssertion[
            {mustne[1 2;3 2]}];
        failing[`state][`assertsRun] musteq 1;
        count[failing[`state][`failures]] musteq 1;
        first[failing[`state][`failures]]
            mustlike "*NOT to equal*";

        dictDifferent:.tst.assertHardening.captureAssertion[
            {mustne[`a`b!1 2;`a`b!1 3]}];
        count[dictDifferent[`state][`failures]] musteq 0;
        dictEqual:.tst.assertHardening.captureAssertion[
            {mustne[`a`b!1 2;`a`b!1 2]}];
        count[dictEqual[`state][`failures]] musteq 1;

        tableDifferent:.tst.assertHardening.captureAssertion[
            {
                mustne[
                    ([] a:1 2;b:3 4);
                    ([] a:1 2;b:3 5)]
            }];
        count[tableDifferent[`state][`failures]] musteq 0;

        keyedDifferent:.tst.assertHardening.captureAssertion[
            {
                mustne[
                    `id xkey ([] id:1 2;v:10 20);
                    `id xkey ([] id:1 2;v:10 21)]
            }];
        count[keyedDifferent[`state][`failures]] musteq 0;

        rowMembership:.tst.assertHardening.captureAssertion[
            {mustin[(1;3);([] a:1 2;b:3 4)]}];
        count[rowMembership[`state][`failures]] musteq 0;
        dictMembership:.tst.assertHardening.captureAssertion[
            {mustin[`a`b!1 3;([] a:1 2;b:3 4)]}];
        count[dictMembership[`state][`failures]] musteq 0;
        missingMembership:.tst.assertHardening.captureAssertion[
            {mustnin[`a`b!9 9;([] a:1 2;b:3 4)]}];
        count[missingMembership[`state][`failures]] musteq 0;

        body:{
            .tst.assertHardening.captureAssertion each
                .tst.assertHardening.predicateCases
        };
        bounded:.tst.assertHardening.withGlobals[
            enlist `.tst.ASSERT_PREDICATE_MAX_ITEMS;
            enlist 3;
            body];
        count[bounded] musteq
            count .tst.assertHardening.predicateCases;
        must[
            all {1=x[`state][`assertsRun]} each bounded;
            "every bounded predicate must count exactly once"];
        must[
            all {1=count x[`state][`failures]} each bounded;
            "every bounded predicate must record exactly one failure"];
        must[
            all {
                first[x[`state][`failures]]
                    like "*structural safety budget*"
              } each bounded;
            "every bounded predicate must disclose its safety limit"];
    };
};

.tst.desc["assertion hardening: throw capture and patterns"]{
    should["never confuse a normal old-sentinel-shaped return with an error"]{
        result:.tst.assertHardening.captureAssertion[
            {mustthrow[();{(`err0x;"boom")}]}];
        state:result[`state];
        state[`assertsRun] musteq 1;
        count[state[`failures]] musteq 1;
        first[state[`failures]] mustlike "*No error thrown*";
    };

    should["reject invalid patterns before executing code"]{
        .tst.assertHardening.probe:0;
        mixed:.tst.assertHardening.captureAssertion[
            {
                mustthrow[
                    ("*boom*";42);
                    {
                        .tst.assertHardening.probe+:1;
                        '"boom"
                    }]
            }];
        first[mixed[`outcome]] mustmatch `error;
        mixed[`state][`assertsRun] musteq 1;
        .tst.assertHardening.probe musteq 0;
        first[last mixed[`outcome]] mustlike "*patterns must be strings*";

        excessive:.tst.assertHardening.captureAssertion[
            {
                mustnotthrow[
                    300#"x";
                    {
                        .tst.assertHardening.probe+:1;
                        1
                    }]
            }];
        first[excessive[`outcome]] mustmatch `error;
        excessive[`state][`assertsRun] musteq 1;
        .tst.assertHardening.probe musteq 0;
        first[last excessive[`outcome]] mustlike "*length exceeds safety limit*";

        symbolic:.tst.assertHardening.captureAssertion[
            {
                mustthrow[
                    `boom;
                    {
                        .tst.assertHardening.probe+:1;
                        '"boom"
                    }]
            }];
        first[symbolic`outcome] mustmatch `ok;
        symbolic[`state][`assertsRun] musteq 1;
        count[symbolic[`state][`failures]] musteq 0;
        .tst.assertHardening.probe musteq 1;

        symbolVector:.tst.assertHardening.captureAssertion[
            {
                mustthrow[
                    `boom`other;
                    {
                        .tst.assertHardening.probe+:1;
                        '"boom"
                    }]
            }];
        first[symbolVector`outcome] mustmatch `ok;
        symbolVector[`state][`assertsRun] musteq 1;
        count[symbolVector[`state][`failures]] musteq 0;
        .tst.assertHardening.probe musteq 2;

        .tst.assertHardening.oversizedPatternSymbol:
            `$300#"s";
        oversizedSymbol:.tst.assertHardening.captureAssertion[
            {
                mustthrow[
                    .tst.assertHardening.oversizedPatternSymbol;
                    {
                        .tst.assertHardening.probe+:1;
                        '"boom"
                    }]
            }];
        first[oversizedSymbol`outcome] mustmatch `error;
        oversizedSymbol[`state][`assertsRun] musteq 1;
        .tst.assertHardening.probe musteq 2;
        first[last oversizedSymbol[`outcome]]
            mustlike "*length exceeds safety limit*";
    };

    should["execute valid throw assertion code exactly once"]{
        .tst.assertHardening.probe:0;
        thrown:.tst.assertHardening.captureAssertion[
            {
                mustthrow[
                    "*boom*";
                    {
                        .tst.assertHardening.probe+:1;
                        '"boom"
                    }]
            }];
        thrown[`state][`assertsRun] musteq 1;
        count[thrown[`state][`failures]] musteq 0;
        .tst.assertHardening.probe musteq 1;

        filtered:.tst.assertHardening.captureAssertion[
            {
                mustnotthrow[
                    "*other*";
                    {
                        .tst.assertHardening.probe+:1;
                        '"boom"
                    }]
            }];
        filtered[`state][`assertsRun] musteq 1;
        count[filtered[`state][`failures]] musteq 0;
        .tst.assertHardening.probe musteq 2;
    };
};

.tst.desc["assertion hardening: specialist assertions"]{
    should["cap ignoring-order work without false passes"]{
        body:{
            identical:.tst.assertHardening.captureAssertion[
                {mustmatchignoringorder[1 2 3;1 2 3]}];
            count[identical[`state][`failures]] musteq 0;

            oversizedEqual:.tst.assertHardening.captureAssertion[
                {mustmatchignoringorder[1 2 3 4;1 2 3 4]}];
            count[oversizedEqual[`state][`failures]] musteq 1;
            first[oversizedEqual[`state][`failures]]
                mustlike "*safety limit*";

            mismatch:.tst.assertHardening.captureAssertion[
                {mustmatchignoringorder[1 2 3 4;1 2 3 5]}];
            mismatch[`state][`assertsRun] musteq 1;
            count[mismatch[`state][`failures]] musteq 1;
            first[mismatch[`state][`failures]] mustlike "*safety limit*";
        };
        .tst.assertHardening.withGlobals[
            enlist `.tst.ORDER_ASSERT_MAX_ITEMS;
            enlist 3;
            body];
    };

    should["apply row and cell caps before included-column projection"]{
        rowBody:{
            result:.tst.assertHardening.captureAssertion[
                {
                    mustincludecols[
                        ([] a:til 4);
                        ([] a:til 4)]
                }];
            result[`state][`assertsRun] musteq 1;
            count[result[`state][`failures]] musteq 1;
            first[result[`state][`failures]]
                mustlike "*row safety limit*";
        };
        .tst.assertHardening.withGlobals[
            enlist `.tst.INCLUDE_COLS_MAX_ROWS;
            enlist 3;
            rowBody];

        cellBody:{
            result:.tst.assertHardening.captureAssertion[
                {
                    mustincludecols[
                        ([] a:1 2;b:3 4);
                        ([] a:1 2;b:3 4)]
                }];
            result[`state][`assertsRun] musteq 1;
            count[result[`state][`failures]] musteq 1;
            first[result[`state][`failures]]
                mustlike "*cell safety limit*";
        };
        .tst.assertHardening.withGlobals[
            enlist `.tst.INCLUDE_COLS_MAX_CELLS;
            enlist 3;
            cellBody];
    };

    should["reject tiny order and column inputs with nested huge cells"]{
        .tst.assertHardening.specialistPayload:til 1000000;
        ordered:.tst.assertHardening.captureAssertion[
            {
                mustmatchignoringorder[
                    enlist .tst.assertHardening.specialistPayload;
                    enlist .tst.assertHardening.specialistPayload]
            }];
        ordered[`state][`assertsRun] musteq 1;
        count[ordered[`state][`failures]] musteq 1;
        first[ordered[`state][`failures]]
            mustlike "*structural safety budget*";

        nestedTable:([] payload:
            enlist .tst.assertHardening.specialistPayload);
        / Keep the table in a global because q nested lambdas do not capture
        / enclosing locals.
        .tst.assertHardening.specialistTable:nestedTable;
        included:.tst.assertHardening.captureAssertion[
            {
                mustincludecols[
                    .tst.assertHardening.specialistTable;
                    .tst.assertHardening.specialistTable]
            }];
        included[`state][`assertsRun] musteq 1;
        count[included[`state][`failures]] musteq 1;
        first[included[`state][`failures]]
            mustlike "*nested composite values*";
    };

    should["fail included-column and benchmark invalid inputs contextually"]{
        included:.tst.assertHardening.captureAssertion[
            {mustincludecols[{x};([] a:enlist 1)]}];
        included[`state][`assertsRun] musteq 1;
        count[included[`state][`failures]] musteq 1;
        first[included[`state][`failures]] mustlike "*table left argument*";

        .tst.assertHardening.probe:0;
        benchmarked:.tst.assertHardening.captureAssertion[
            {
                mustBeFasterThan[
                    {.tst.assertHardening.probe+:1};
                    "bad"]
            }];
        benchmarked[`state][`assertsRun] musteq 1;
        count[benchmarked[`state][`failures]] musteq 1;
        .tst.assertHardening.probe musteq 0;
    };

    should["cap spy scans and report exhaustion"]{
        body:{
            wanted:enlist 3;
            calls:(enlist 1;enlist 2;enlist 3);
            callsByName:(enlist `probeFunction)!enlist calls;
            spyBody:{
                .tst.assertHardening.captureAssertion[
                    {mustHaveBeenCalledWith[`probeFunction;enlist 3]}]
            };
            result:.tst.assertHardening.withGlobals[
                enlist `.tst.spyLog.calls;
                enlist callsByName;
                spyBody];
            result[`state][`assertsRun] musteq 1;
            count[result[`state][`failures]] musteq 1;
            first[result[`state][`failures]] mustlike "*safety limit*";
        };
        .tst.assertHardening.withGlobals[
            enlist `.tst.SPY_ASSERT_MAX_CALLS;
            enlist 2;
            body];
    };

    should["reject oversized and malformed spy state before lookup"]{
        namesBody:{
            callsByName:`first`second!((enlist enlist 1);enlist enlist 2);
            spyBody:{
                .tst.assertHardening.captureAssertion[
                    {mustHaveBeenCalledWith[`first;enlist 1]}]
            };
            result:.tst.assertHardening.withGlobals[
                enlist `.tst.spyLog.calls;
                enlist callsByName;
                spyBody];
            count[result[`state][`failures]] musteq 1;
            first[result[`state][`failures]]
                mustlike "*name safety limit*";
        };
        .tst.assertHardening.withGlobals[
            enlist `.tst.SPY_ASSERT_MAX_NAMES;
            enlist 1;
            namesBody];

        malformedBody:{
            result:.tst.assertHardening.captureAssertion[
                {mustHaveBeenCalledWith[`probeFunction;enlist 1]}];
            result[`state][`assertsRun] musteq 1;
            count[result[`state][`failures]] musteq 1;
            first[result[`state][`failures]] mustlike "*malformed*";
        };
        .tst.assertHardening.withGlobals[
            enlist `.tst.spyLog.calls;
            enlist 42;
            malformedBody];
    };

    should["bound structural comparisons of individual spy calls"]{
        hugePrefix:til 100000;
        loggedArgs:(hugePrefix;0);
        wantedArgs:(hugePrefix;1);
        .tst.assertHardening.spyWantedArgs:wantedArgs;
        callsByName:(enlist `probeFunction)!
            enlist enlist loggedArgs;
        spyBody:{
            .tst.assertHardening.captureAssertion[
                {
                    mustHaveBeenCalledWith[
                        `probeFunction;
                        .tst.assertHardening.spyWantedArgs]
                }]
        };
        result:.tst.assertHardening.withGlobals[
            enlist `.tst.spyLog.calls;
            enlist callsByName;
            spyBody];
        result[`state][`assertsRun] musteq 1;
        count[result[`state][`failures]] musteq 1;
        first[result[`state][`failures]]
            mustlike "*structural safety budget*";
    };
};

.tst.desc["assertion hardening: color and symbol safety"]{
    should["apply every color gate dynamically and fail closed off Linux"]{
        body:{
            detected:.tst.detectTty[];
            must[-1h=type detected;
                "TTY detection must return a boolean"];
            must[
                .tst.ttyProbeIsTerminal enlist "/dev/pts/7";
                "a bounded PTY link must be accepted"];
            must[
                not .tst.ttyProbeIsTerminal enlist 300#"x";
                "oversized TTY probe output must fail closed"];
            must[
                not .tst.ttyProbeIsTerminal (
                    "/dev/pts/7";
                    "/dev/pts/8");
                "multi-line TTY probe output must fail closed"];

            setenv[`NO_COLOR;""];
            .tst.useColor:1b;
            .tst.diffColors:1b;
            .tst.fmt.color[`red;"X"] mustmatch "\033[31mX\033[0m";
            .resq.color[`green;"X"] mustmatch "\033[32mX\033[0m";

            .tst.diffColors:0b;
            .tst.fmt.color[`red;"X"] mustmatch "X";
            .resq.color[`green;"X"] mustmatch "X";

            .tst.diffColors:1b;
            setenv[`NO_COLOR;"yes"];
            .tst.fmt.color[`red;"X"] mustmatch "X";
            .resq.color[`green;"X"] mustmatch "X";

            setenv[`NO_COLOR;""];
            .utl.isLinux:0b;
            .tst.detectTty[] mustmatch 0b;
        };
        .tst.assertHardening.withColorState body;
    };

    should["restore color globals and environment after an error"]{
        originalUse:.tst.useColor;
        originalDiff:.tst.diffColors;
        originalLinux:.utl.isLinux;
        originalNoColor:getenv `NO_COLOR;
        restoreBody:{
            .tst.assertHardening.withColorState[
                {
                    .tst.useColor:not .tst.useColor;
                    .tst.diffColors:not .tst.diffColors;
                    .utl.isLinux:not .utl.isLinux;
                    setenv[`NO_COLOR;"changed"];
                    '"color restore probe"
                }]
        };
        mustthrow[
            "*color restore probe*";
            restoreBody];
        .tst.useColor mustmatch originalUse;
        .tst.diffColors mustmatch originalDiff;
        .utl.isLinux mustmatch originalLinux;
        (getenv `NO_COLOR) mustmatch originalNoColor;
    };

    should["never intern diagnostic strings or add root names"]{
        symbolsBefore:.Q.w[]`syms;
        rootBefore:key `;
        dynamicText:"diagnostic-",200000#"z";
        left:(enlist dynamicText)!enlist 1;
        right:(enlist dynamicText)!enlist 2;
        .tst.renderValue[dynamicText;512];
        .tst.diff[left;right];
        captured:.tst.assertHardening.captureAssertion[
            {musteq[100000#"a";100000#"b"]}];
        count[captured[`state][`failures]] musteq 1;
        .Q.w[][`syms] musteq symbolsBefore;
        (key `) mustmatch rootBefore;
    };
};
