\d .tst

/ ============================================================================
/ State Initialization - Safe Defaults
/ These ensure variables exist before any module tries to use them
/ Using direct assignment to create namespace structure (like init.q does)
/ ============================================================================

/ Ensure namespaces exist by touching variables
/ This is the safe pattern - setting a variable creates its parent namespaces
if[not `app in key `.tst; .tst.app.init_: 1b];
if[not `output in key `.tst; .tst.output.init_: 1b];

/ App configuration (with safe defaults) - only set if not already defined
if[not `excludeSpecs in key `.tst.app; .tst.app.excludeSpecs: ()];
if[not `runSpecs in key `.tst.app; .tst.app.runSpecs: ()];
if[not `args in key `.tst.app; .tst.app.args: ()];
if[not `describeOnly in key `.tst.app; .tst.app.describeOnly: 0b];
if[not `xmlOutput in key `.tst.app; .tst.app.xmlOutput: 0b];
if[not `runPerformance in key `.tst.app; .tst.app.runPerformance: 0b];
if[not `runCoverage in key `.tst.app; .tst.app.runCoverage: 0b];
if[not `exit in key `.tst.app; .tst.app.exit: 0b];
if[not `failFast in key `.tst.app; .tst.app.failFast: 0b];
if[not `failHard in key `.tst.app; .tst.app.failHard: 0b];
if[not `pollutionGuard in key `.tst.app; .tst.app.pollutionGuard: 1b];
if[not `maxTestTime in key `.tst.app; .tst.app.maxTestTime: 0];
if[not `passOnly in key `.tst.app; .tst.app.passOnly: 0b];
if[not `quiet in key `.tst.app; .tst.app.quiet: 0b];
if[not `allSpecs in key `.tst.app; .tst.app.allSpecs: ()];
if[not `passed in key `.tst.app; .tst.app.passed: 1b];

/ Counters (reset on each run)
if[not `expectationsRan in key `.tst.app; .tst.app.expectationsRan: 0];
if[not `expectationsPassed in key `.tst.app; .tst.app.expectationsPassed: 0];
if[not `expectationsFailed in key `.tst.app; .tst.app.expectationsFailed: 0];
if[not `expectationsErrored in key `.tst.app; .tst.app.expectationsErrored: 0];

/ Output configuration
if[not `mode in key `.tst.output; .tst.output.mode: `run];
if[not `fuzzLimit in key `.tst.output; .tst.output.fuzzLimit: 10];
if[not `reportLimit in key `.tst.output; .tst.output.reportLimit: 50000];
if[not `reportListLimit in key `.tst.output; .tst.output.reportListLimit: 1000];

/ Private diagnostic budgets. These are deliberately independent of user
/ configuration: a hostile reportLimit must not turn diagnostics into an
/ unbounded allocation request.
.tst.DIAGNOSTIC_MAX_CHARS:50000;
.tst.VALUE_RENDER_MAX_DEPTH:4;
.tst.VALUE_RENDER_MAX_NODES:64;
.tst.VALUE_RENDER_MAX_CHILDREN:8;

/ Normalize a direct output cap defensively. Authoritative config validation
/ accepts the same finite, non-negative integer scalar contract.
.tst.capLimit:{[limit]
    if[not ((type limit) in -5 -6 -7h); :0];
    if[null limit; :0];
    if[limit in (0Wh;-0Wh;0Wi;-0Wi;0W;-0W); :0];
    if[0>limit; :0];
    50000 & "j"$limit
 };

.tst.truncationMarker:{[removed]
    "... [truncated ",string[removed]," chars]"
 };

/ Cap an already-rendered string without ever exceeding limit. The informative
/ marker is included only when its complete and accurate text fits.
.tst.capString:{[text;limit]
    cap:.tst.capLimit limit;
    n:count text;
    if[n<=cap; :text];
    if[0=cap; :""];
    marker:.tst.truncationMarker n;
    if[cap<count marker; :cap#text];
    prefix:cap-count marker;
    done:0b;
    while[not done;
        marker:.tst.truncationMarker n-prefix;
        nextPrefix:cap-count marker;
        if[0>nextPrefix; :cap#text];
        done:nextPrefix=prefix;
        prefix:nextPrefix;
    ];
    (prefix#text),marker
 };

/ Read a mutable test seam without trusting it as an allocation authority.
/ Invalid values fall back to the literal default; valid values may only lower
/ the literal ceiling.
.tst.safeDiagnosticBudget:{[name;default;hardMax]
    raw:@[get;name;{[fallback;err] fallback}[default;]];
    if[not ((type raw) in -5 -6 -7h);
        :default & hardMax];
    if[null raw; :default & hardMax];
    if[raw in (0Wh;-0Wh;0Wi;-0Wi;0W;-0W);
        :default & hardMax];
    if[0>raw; :default & hardMax];
    hardMax & "j"$raw
 };

.tst.renderDepthLimit:{[]
    .tst.safeDiagnosticBudget[
        `.tst.VALUE_RENDER_MAX_DEPTH;
        4;
        4]
 };

.tst.renderNodeLimit:{[]
    .tst.safeDiagnosticBudget[
        `.tst.VALUE_RENDER_MAX_NODES;
        64;
        64]
 };

.tst.renderChildLimit:{[]
    .tst.safeDiagnosticBudget[
        `.tst.VALUE_RENDER_MAX_CHILDREN;
        8;
        8]
 };

/ Clamp a requested diagnostic cap to the private allocation ceiling.
.tst.diagnosticCap:{[limit]
    hardCap:.tst.safeDiagnosticBudget[
        `.tst.DIAGNOSTIC_MAX_CHARS;
        50000;
        50000];
    hardCap & .tst.capLimit limit
 };

.tst.renderOmitted:{[body;omitted;unit;cap]
    if[0>=omitted; :.tst.capString[body;cap]];
    .tst.capString[
        body," ... [truncated; ",string[omitted]," ",unit," omitted]";
        cap]
 };

/ Render a fixed-size atom. Symbols are irreducible in q: obtaining even their
/ first character requires converting the complete interned name to a string.
/ Use a bounded placeholder rather than allocating an attacker-sized copy.
.tst.renderAtom:{[val;t;cap]
    if[-11h=t; :.tst.capString["<symbol>";cap]];
    if[101h=t;
        genericNull:@[
            {[box] (::)~first box};
            enlist val;
            {[err] 0b}];
        :.tst.capString[
            $[genericNull;"::";"<callable/opaque type=101>"];
            cap]];
    if[t>=100h;
        :.tst.capString["<callable/opaque type=",string[t],">";cap]];
    rendered:@[
        { -3!x };
        val;
        {[err] "<atom render unavailable>"}];
    $[10h=type rendered;
        .tst.capString[rendered;cap];
        .tst.capString["<atom type=",string[t],">";cap]]
 };

/ Render only a bounded prefix of a homogeneous vector. The prefix is serialized
/ only after it has been cut to a fixed item count (or a cap-derived char count).
.tst.renderSimple:{[val;t;cap]
    n:count val;
    if[11h=t;
        :.tst.capString[
            "<symbol vector count=",string[n],"; contents omitted>";
            cap]];
    takeN:$[
        10h=t;
        n & (1 | cap div 4);
        n & .tst.renderChildLimit[]];
    prefix:takeN sublist val;
    rendered:@[
        { -3!x };
        prefix;
        {[err] "<vector prefix render unavailable>"}];
    if[not 10h=type rendered;
        rendered:"<vector type=",string[t],">"];
    .tst.renderOmitted[rendered;n-takeN;"items";cap]
 };

/ Render a mixed list with bounded fan-out. Node budgets are divided among
/ children, keeping the total recursive work bounded without a whole-list walk.
.tst.renderList:{[val;cap;depth;nodes]
    n:count val;
    if[0>=depth;
        :.tst.capString[
            "<list count=",string[n],"; depth limit>";
            cap]];
    takeN:n & .tst.renderChildLimit[] & (0 | nodes-1);
    if[0=takeN;
        :.tst.capString[
            "<list count=",string[n],"; node limit>";
            cap]];
    childNodes:1 | (nodes-1) div takeN;
    childCap:512 & (1 | cap div takeN);
    parts:{
        [source;childCap;childDepth;childNodes;i]
        .tst.renderNode[source i;childCap;childDepth;childNodes]
      }[val;childCap;depth-1;childNodes;] each til takeN;
    .tst.renderOmitted[
        "(",("; " sv parts),")";
        n-takeN;
        "items";
        cap]
 };

/ Render an ordinary dictionary by bounded key/value positions. A keyed table is
/ represented by its key and value tables, avoiding materializing whole rows.
.tst.renderDict:{[val;cap;depth;nodes]
    ks:key val;
    vals:value val;
    n:count ks;
    if[98h=type ks;
        if[0>=depth;
            :.tst.capString[
                "<keyed table rows=",string[count val],"; depth limit>";
                cap]];
        if[3>nodes;
            :.tst.capString[
                "<keyed table rows=",string[count val],"; node limit>";
                cap]];
        childCap:cap div 2;
        keyNodes:(nodes-1) div 2;
        valNodes:(nodes-1)-keyNodes;
        keyText:.tst.renderNode[ks;childCap;depth-1;keyNodes];
        valText:.tst.renderNode[vals;childCap;depth-1;valNodes];
        :.tst.capString[
            "keyed(",keyText,"; ",valText,")";
            cap]
    ];
    if[0>=depth;
        :.tst.capString[
            "<dict count=",string[n],"; depth limit>";
            cap]];
    takeN:n & .tst.renderChildLimit[] & ((0 | nodes-1) div 2);
    if[0=takeN;
        :.tst.capString[
            "<dict count=",string[n],"; node limit>";
            cap]];
    childNodes:(nodes-1) div (2*takeN);
    childCap:256 & (1 | cap div (2*takeN));
    parts:{
        [keys;vals;childCap;childDepth;childNodes;i]
        (.tst.renderNode[keys i;childCap;childDepth;childNodes]),
        ": ",
        .tst.renderNode[vals i;childCap;childDepth;childNodes]
      }[ks;vals;childCap;depth-1;childNodes;] each til takeN;
    .tst.renderOmitted[
        "{",("; " sv parts),"}";
        n-takeN;
        "entries";
        cap]
 };

/ Render a table column-wise. This touches only a bounded number of column
/ prefixes and never constructs a row containing every column.
.tst.renderTable:{[val;cap;depth;nodes]
    rows:count val;
    cs:cols val;
    ncols:count cs;
    if[0>=depth;
        :.tst.capString[
            "<table rows=",string[rows],"; cols=",string[ncols],
            "; depth limit>";
            cap]];
    takeN:ncols & .tst.renderChildLimit[] & (0 | nodes-1);
    if[0=takeN;
        :.tst.capString[
            "<table rows=",string[rows],"; cols=",string[ncols],
            "; node limit>";
            cap]];
    childNodes:1 | (nodes-1) div takeN;
    childCap:512 & (1 | cap div takeN);
    parts:{
        [table;columns;childCap;childDepth;childNodes;i]
        "col[",string[i],"]=",
        .tst.renderNode[
            table[columns i];
            childCap;
            childDepth;
            childNodes]
      }[val;cs;childCap;depth-1;childNodes;] each til takeN;
    .tst.renderOmitted[
        "table[rows=",string[rows],"; cols=",string[ncols],"]{",
        ("; " sv parts),"}";
        ncols-takeN;
        "columns";
        cap]
 };

/ Recursive bounded renderer. Every dispatcher branch returns through capString;
/ unsupported and dirty objects are described by type instead of inspected.
.tst.renderNode:{[val;cap;depth;nodes]
    if[0>=nodes; :.tst.capString["<node limit>";cap]];
    t:type val;
    if[98h=t; :.tst.capString[
        .tst.renderTable[val;cap;depth;nodes];
        cap]];
    if[99h=t; :.tst.capString[
        .tst.renderDict[val;cap;depth;nodes];
        cap]];
    if[0h=t; :.tst.capString[
        .tst.renderList[val;cap;depth;nodes];
        cap]];
    if[t within 1 19h; :.tst.capString[
        .tst.renderSimple[val;t;cap];
        cap]];
    if[(t>=20h) and t<98h;
        n:@[count;val;{[err] 1}];
        :.tst.capString[
            "<enumerated/opaque type=",string[t],"; count=",string[n],">";
            cap]];
    .tst.capString[.tst.renderAtom[val;t;cap];cap]
 };

/ Public bounded value renderer. The outer trap is the final containment layer:
/ malformed values and unexpected renderer bugs become a capped placeholder.
.tst.renderValue:{[val;limit]
    cap:.tst.diagnosticCap limit;
    fallback:{[cap;err]
        detail:.tst.capString[err;128];
        .tst.capString["<render unavailable: ",detail,">";cap]
      }[cap;];
    rendered:.[
        .tst.renderNode;
        (val;cap;.tst.renderDepthLimit[];.tst.renderNodeLimit[]);
        fallback];
    if[not 10h=type rendered;
        rendered:"<render unavailable>"];
    .tst.capString[rendered;cap]
 };

/ Compatibility entry point, now allocation-bounded before serialization.
.tst.truncate:{[val;maxLen]
    .tst.renderValue[val;maxLen]
 };

/ Initialize .resq namespace if not exists
if[not `resq in key `.; .resq.state.init_: 1b; .resq.config.init_: 1b];

/ Resq config defaults
if[not `fmt in key `.resq.config; .resq.config.fmt: `text];
if[not `outDir in key `.resq.config; .resq.config.outDir: "."];

/ Resq state - results table
if[not `results in key `.resq.state; .resq.state.results: .resq.state.emptyResults[]];

/ Default reporter (can be overridden)
if[not `report in key `.resq; .resq.report: {[x]}];

/ ============================================================================

.tst.defaultAssertState:.tst.assertState:``failures`assertsRun!(::;();0);
.tst.tstPath: `;
/ When true, failing assertions skip the per-call FAILURE DIFF banner.
/ The fuzz runner flips this on inside its iteration + shrink loops so
/ a single fuzz spec does not flood stdout with one banner per attempt
/ (the runner reports a single shrunk repro at the end instead).
if[not `suppressAssertionDiff in key `.tst; .tst.suppressAssertionDiff: 0b];

/ Type-safe string conversion
/ Handles: symbols, strings, atoms, lists, nulls
/ Use this instead of `string` when concatenating with strings
.tst.toString:{
    t: type x;
    $[10h = t; x;                           / Already a string - return as-is
      -11h = t; string x;                   / Symbol - convert normally
      11h = t; " " sv string x;             / Symbol list - join with spaces
      t within -19 -1h; string x;           / Negative atom types (atoms)
      t within 1 19h; -3!x;                 / Positive simple list types
      0h = t; -3!x;                         / General list - use -3!
      99h = t; -3!x;                        / Dictionary
      98h = t; -3!x;                        / Table
      null x; "";                           / Null - empty string
      -3!x]                                 / Fallback - use -3! (show)
 };

/ Normalize internal execution states to the public result contract.
/ returns: one of `pass`fail`error`skip`pending
.tst.normalizeResultStatus:{[status]
    if[not -11h = type status; :`error];
    $[status in `pass`skip`pending; status;
      status in `fail`testFail`fuzzFail; `fail;
      status ~ `error; `error;
      status like "*Error"; `error;
      `error]
 };

/ Capture mutable process-level state affected while loading and running tests.
/ returns: dictionary suitable for .tst.restoreRuntimeContext
.tst.captureRuntimeContext:{[]
    `namespace`context`tstPath`currentNs`fileLoadingSet`fileLoading`cwd!(
        system "d";
        @[get; `.tst.context; `.];
        @[get; `.tst.tstPath; `];
        @[get; `.tst.currentNs; `];
        `FILELOADING in key `.utl;
        @[get; `.utl.FILELOADING; {::}];
        system "cd")
 };

/ Restore state captured by .tst.captureRuntimeContext.
/ side effects: current namespace, current directory, loader bookkeeping, test context
.tst.restoreRuntimeContext:{[ctx]
    if[not 99h = type ctx; :()];

    if[`context in key ctx; .tst.context: ctx`context];
    if[`tstPath in key ctx; .tst.tstPath: ctx`tstPath];
    if[`currentNs in key ctx; .tst.currentNs: ctx`currentNs];

    if[`fileLoadingSet in key ctx;
        if[ctx`fileLoadingSet; .utl.FILELOADING: ctx`fileLoading];
        if[not ctx`fileLoadingSet; delete FILELOADING from `.utl];
    ];

    if[`cwd in key ctx;
        cwd: .tst.toString ctx`cwd;
        if[0 < count cwd; @[system; "cd ", cwd; {}]];
    ];

    if[`namespace in key ctx;
        ns: .tst.toString ctx`namespace;
        if[0 < count ns; @[system; "d ", ns; {}]];
    ];

    :: 
 };

.tst.printRunAudit:{[]
    if[$[`quiet in key `.tst.app; .tst.app.quiet; 0b]; :()];
    discovered: $[`discoveredFiles in key `.tst.app; count .tst.app.discoveredFiles; 0];
    loaded: $[`loadedFiles in key `.tst.app; count .tst.app.loadedFiles; 0];
    empty: $[`emptyFiles in key `.tst.app; count .tst.app.emptyFiles; 0];
    specs: $[`allSpecs in key `.tst.app; count .tst.app.allSpecs; 0];
    executed: $[`expectationsRan in key `.tst.app; .tst.app.expectationsRan; 0];

    -1 "\nRUN AUDIT";
    -1 "---------";
    -1 "Files discovered:      ", string discovered;
    -1 "Files loaded:          ", string loaded;
    -1 "Files with no tests:   ", string empty;
    -1 "Specs registered:      ", string specs;
    -1 "Expectations executed: ", string executed;
 };

/ Pollution snapshots are internal lifecycle data, not diagnostic renderings.
/ Literal ceilings keep acquisition bounded even if mutable framework state has
/ been damaged by a test.
.tst.pollutionNamespaceLimit:{[] 256};
.tst.pollutionMemberLimit:{[] 4096};
.tst.pollutionTotalMemberLimit:{[] 16384};
.tst.pollutionNameLimit:{[] 256};
.tst.pollutionErrorLimit:{[] 160};

.tst.pollutionBoundedError:{[err]
    if[not (type err) in -10 10h;
        :"pollution operation failed"];
    limit:.tst.pollutionErrorLimit[] & count err;
    limit#(),err
 };

.tst.pollutionEmptyEntries:{[]
    flip `member`state`payload`detail!(
        `symbol$();
        `symbol$();
        ();
        ())
 };

.tst.pollutionSnapshotRecord:{[namespace;state;entries;detail]
    `schema`namespace`state`entries`detail!(
        `pollutionSnapshotV1;
        namespace;
        state;
        entries;
        detail)
 };

/ Trap a unary lookup while boxing its payload. The explicit state tag cannot
/ collide with any legitimate user value, including the old GENERIC_ERROR
/ sentinel shape.
.tst.pollutionCaptureValue:{[lookup;argument]
    .[
        {[fn;arg]
            (`ok;enlist fn arg;"")
          };
        (lookup;argument);
        {[err]
            (`error;enlist(::);.tst.pollutionBoundedError err)
          }]
 };

.tst.pollutionNamespaceRoot:{[namespace]
    if[not .tst.pollutionMemberValid namespace;
        '"pollution namespace name is invalid"];
    ` sv (`;namespace)
 };

.tst.pollutionMemberValid:{[member]
    if[-11h<>type member; :0b];
    if[null member; :0b];
    text:string member;
    if[(0=count text) or
       count[text]>.tst.pollutionNameLimit[];
        :0b];
    firstChars:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
    remainingChars:
        firstChars,"0123456789_";
    ((first text) in firstChars)
        and all text in remainingChars
 };

/ Snapshot one namespace without matching, invoking, or rendering any member.
/ Lookup failures remain tagged entries; callers decide whether an acquisition
/ or restoration can proceed safely.
.tst.snapshotNamespaceValues:{[namespace]
    rootNs:.tst.pollutionNamespaceRoot namespace;
    namespaceState:.tst.pollutionCaptureValue[get;rootNs];
    if[`error~first namespaceState;
        :.tst.pollutionSnapshotRecord[
            rootNs;
            `error;
            .tst.pollutionEmptyEntries[];
            "pollution namespace lookup failed"]];
    bareState:.tst.diffSafeMatchState[
        first namespaceState 1;
        ::];
    if[`equal~bareState`state;
        :.tst.pollutionSnapshotRecord[
            rootNs;
            `ok;
            .tst.pollutionEmptyEntries[];
            ""]];
    keyState:.tst.pollutionCaptureValue[key;rootNs];
    if[`error~first keyState;
        :.tst.pollutionSnapshotRecord[
            rootNs;
            `error;
            .tst.pollutionEmptyEntries[];
            "pollution namespace lookup failed"]];
    members:first keyState 1;
    if[-11h=type members;members:enlist members];
    if[11h<>type members;
        :.tst.pollutionSnapshotRecord[
            rootNs;
            `error;
            .tst.pollutionEmptyEntries[];
            "pollution namespace keys have invalid type"]];
    / q exposes a namespace's fully-qualified root symbol as a metadata marker.
    / It is not an addressable member and must not be fed back through .Q.dd.
    members:members where (not null members) and members<>rootNs;
    if[count[members]>.tst.pollutionMemberLimit[];
        :.tst.pollutionSnapshotRecord[
            rootNs;
            `error;
            .tst.pollutionEmptyEntries[];
            "pollution namespace member limit exceeded"]];
    if[not all .tst.pollutionMemberValid each members;
        :.tst.pollutionSnapshotRecord[
            rootNs;
            `error;
            .tst.pollutionEmptyEntries[];
            "pollution namespace member name is invalid"]];
    if[0=count members;
        :.tst.pollutionSnapshotRecord[
            rootNs;
            `ok;
            .tst.pollutionEmptyEntries[];
            ""]];
    paths:.Q.dd[rootNs;] each members;
    captured:.tst.pollutionCaptureValue[get;] each paths;
    states:first each captured;
    payloads:{x 1} each captured;
    details:last each captured;
    entries:flip `member`state`payload`detail!(
        members;
        states;
        payloads;
        details);
    snapshotState:$[all states=`ok;`ok;`error];
    .tst.pollutionSnapshotRecord[
        rootNs;
        snapshotState;
        entries;
        $[`ok~snapshotState;
          "";
          "pollution member lookup failed"]]
 };

.tst.pollutionPayloadBoxValid:{[payload]
    payloadType:type payload;
    if[(0>payloadType) or 99h<payloadType; :0b];
    1=@[count;payload;{[err] 0}]
 };

.tst.pollutionEntriesValidUnsafe:{[entries]
    if[98h<>type entries; :0b];
    if[not (cols entries)~`member`state`payload`detail;
        :0b];
    n:count entries;
    if[n>.tst.pollutionMemberLimit[]; :0b];
    if[11h<>type entries`member; :0b];
    if[11h<>type entries`state; :0b];
    if[not all entries[`state] in `ok`error; :0b];
    if[not all .tst.pollutionMemberValid each entries`member;
        :0b];
    if[n<>count distinct entries`member; :0b];
    if[not all .tst.pollutionPayloadBoxValid each entries`payload;
        :0b];
    details:entries`detail;
    if[not all 10h=type each details; :0b];
    all (count each details)<=.tst.pollutionErrorLimit[]
 };

.tst.pollutionEntriesValid:{[entries]
    @[
        .tst.pollutionEntriesValidUnsafe;
        entries;
        {[err] 0b}]
 };

/ Validate metadata and entry shape without inspecting any captured payload.
.tst.pollutionSnapshotValidUnsafe:{[namespace;snapshot]
    if[99h<>type snapshot; :0b];
    fields:`schema`namespace`state`entries`detail;
    if[not (key snapshot)~fields; :0b];
    if[not `pollutionSnapshotV1~snapshot`schema; :0b];
    expected:@[
        .tst.pollutionNamespaceRoot;
        namespace;
        {[err] `}];
    if[null expected; :0b];
    if[not expected~snapshot`namespace; :0b];
    if[not snapshot[`state] in `ok`error; :0b];
    if[10h<>type snapshot`detail; :0b];
    if[count[snapshot`detail]>.tst.pollutionErrorLimit[];
        :0b];
    if[not .tst.pollutionEntriesValid snapshot`entries;
        :0b];
    entryStates:snapshot[`entries;`state];
    $[
        `ok~snapshot`state;
        all entryStates=`ok;
        (0=count entryStates) or any entryStates=`error]
 };

.tst.pollutionSnapshotValid:{[namespace;snapshot]
    .[
        .tst.pollutionSnapshotValidUnsafe;
        (namespace;snapshot);
        {[err] 0b}]
 };

halt:0b
internals:()!()
internals[`]:()!()
internals[`specObj]:`result`title`failHard!(`didNotRun;"";0b)
/ Shared key superset so every DSL constructor (should/skip/pending/retry/
/ testOnly/holds/perf) emits the SAME columns. In q, `enlist d` is a TABLE, so
/ `.tst.expecList,: enlist d` only works when every appended dict has identical
/ keys. The `type` value still distinguishes test/fuzz/perf. fuzz-specific keys
/ (runs/vars/maxFailRate) live in the base too; holds[] overrides them directly.
/ NOTE: before/after are deliberately NOT in the base - fillExpecBA attaches them
/ uniformly and its `not `before in key ex` guard must still fire.
internals[`defaultExpecObj]:`result`errorText`desc`code`tags`namespace`skipReason`retries`only`props`runs`vars`maxFailRate!(
    `didNotRun;();"";{};`symbol$();`.;"";0;0b;()!();100;`int;0f)
internals[`testObj]: internals[`defaultExpecObj], ((),`type)!(),`test
internals[`fuzzObj]: internals[`defaultExpecObj], ((),`type)!(),`fuzz
internals[`perfObj]: internals[`defaultExpecObj], ((),`type)!(),`perf

/ Callbacks - must exist before any test loading
if[not `callbacks in key `.tst; .tst.callbacks.descLoaded: {[specObj]}; .tst.callbacks.expecRan: {[spec;expec]}];
