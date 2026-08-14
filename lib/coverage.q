/ coverage.q - runtime coverage instrumentation and LCOV/HTML reporting (load-safe)
.utl.require .utl.PKGLOADING,"/static_analysis.q"
/ For .tst.bracketDelta, used to find where a function definition closes.
/ .utl.require is idempotent, so this is a no-op in a normal run (init.q has
/ already loaded it) and a real load when coverage.q is pulled in on its own.
.utl.require .utl.PKGLOADING,"/loader.q"

/ State. Preserve live ownership on a defensive module reload: resetting these
/ maps while wrappers are installed is precisely how a wrapper can be captured
/ as the next session's "original" and recurse forever.
if[not `coverageData in key `.tst;.tst.coverageData:()!()]; / file -> func -> count
if[not `coverageEnabled in key `.tst;.tst.coverageEnabled:0b];
if[not `trackedFiles in key `.tst;.tst.trackedFiles:()];
if[not `origFuncs in key `.tst;.tst.origFuncs:()!()];       / name -> original
if[not `lastCoverageSummary in key `.tst;
    .tst.lastCoverageSummary:
        `linesFound`linesHit`linePercent`functionsFound`functionsHit`functionPercent`branchesFound`branchesHit`branchPercent!(
            0j;0j;0f;0j;0j;0f;0j;0j;0f)];
if[not `lastCoverageModel in key `.tst;.tst.lastCoverageModel:()!()];
if[not `covWrappers in key `.tst;.tst.covWrappers:()!()]; / name -> owned wrapper
if[not `coverageInstallOrder in key `.tst;.tst.coverageInstallOrder:`symbol$()];
if[not `coverageBlockedValues in key `.tst;.tst.coverageBlockedValues:()!()];
if[not `coverageLifecycleDiagnostics in key `.tst;.tst.coverageLifecycleDiagnostics:()];
if[not `coverageLifecycleFailed in key `.tst;.tst.coverageLifecycleFailed:0b];
if[not `coverageInstallFailed in key `.tst;.tst.coverageInstallFailed:0b];
if[not `coverageInstallErrors in key `.tst;.tst.coverageInstallErrors:()];
if[not `coverageLoadedFiles in key `.tst;.tst.coverageLoadedFiles:`symbol$()];
if[not `loadingStack in key `.tst;.tst.loadingStack:()];
if[not (`$"_covMissing") in key `.tst;.tst._covMissing:`resqCovMissing];

/ Optional attribution is deliberately separate from the aggregate maps above.
/ Aggregate probes are updated first; context accounting is trapped and bounded,
/ so enabling it cannot change application execution or a coverage gate.
if[not `coverageContextRegistry in key `.tst;.tst.coverageContextRegistry:()!()];
if[not `coverageContextMetricMeta in key `.tst;.tst.coverageContextMetricMeta:()!()];
if[not `coverageContextMetricHits in key `.tst;.tst.coverageContextMetricHits:(`symbol$())!`long$()];
if[not `coverageActiveContext in key `.tst;.tst.coverageActiveContext:()!()];
if[not `coverageContextOverflowActivations in key `.tst;.tst.coverageContextOverflowActivations:0j];
if[not `coverageContextDroppedHits in key `.tst;.tst.coverageContextDroppedHits:0j];
/ Context-independent metric identities and context/metric entry lookups are
/ cached for the lifetime of one coverage session. Probe execution must not
/ normalize paths or hash identities on every hit.
if[not `coverageMetricDefinitions in key `.tst;.tst.coverageMetricDefinitions:()!()];
if[not `coverageFunctionMetricKeys in key `.tst;.tst.coverageFunctionMetricKeys:()!()];
if[not `coverageStatementMetricKeys in key `.tst;.tst.coverageStatementMetricKeys:(`symbol$())!`symbol$()];
if[not `coverageBranchTrueMetricKeys in key `.tst;.tst.coverageBranchTrueMetricKeys:(`symbol$())!`symbol$()];
if[not `coverageBranchFalseMetricKeys in key `.tst;.tst.coverageBranchFalseMetricKeys:(`symbol$())!`symbol$()];
if[not `coverageContextEntryCache in key `.tst;.tst.coverageContextEntryCache:()!()];
if[not `coverageParseDiagnostics in key `.tst;.tst.coverageParseDiagnostics:()];
if[not `coverageParseFailed in key `.tst;.tst.coverageParseFailed:0b];

/ Functions that must never be wrapped (avoid recursion/self-instrumentation)
.tst.coverageSkipNames: `$(".tst.initCoverage";".tst.stopCoverage";".tst.recordExecution";".tst.resolvePath";".tst.wrapFunc";".tst.instrumentFile";".tst.loadSource";".tst.generateLCOV";".tst.generateHTML");

/ Helpers
.tst.resolvePath:{[path]
    s: $[10h = abs type path; path; string path];
    if[s like ":*"; s: 1 _ s];
    if[not s like "/*"; s: (system "cd"), "/", s];
    .utl.normalizePath s
 };

.tst._covNameStr:{[x]
    $[-11h=type x;string x;
      10h=type x;x;
      .tst.renderValueFull x]
 };

.tst._covNumStr:{[x] string `long$x };

/ Resolve a (possibly dotted, possibly namespaced) name to its value, returning
/ the `.tst._covMissing` sentinel when the name is unbound. The previous walk
/ gated on `nsSym in key \`.`, which is false for dotted CHILD namespaces
/ (e.g. \`.user.create lives under \`.user, not \`.), so it rejected every
/ \`.ns.func and wrapped nothing. A trapped `get` resolves any bound name -
/ root, namespaced, or nested - and the lambda handler keeps the sentinel
/ contract for unbound names. (\`get\` SIGNALS on an unknown name; the trap is
/ mandatory and its handler MUST be a lambda - \`@[f;x;e]\` requires it.)
.tst.safeValue:{[sym] @[get; sym; {[e] .tst._covMissing}] };
/ Trapped assignment, used to put an original definition back when
/ statement instrumentation is abandoned.
.tst.safeSet:{[sym;val] .[set;(sym;val);{[e] ::}]; };

/ One assignment boundary for installation and restoration. Returning a tagged
/ outcome lets tests inject failures without relying on q's eager trap fallback
/ behavior, and lets stopCoverage continue restoring every other function.
.tst.coverageAssign:{[name;definition]
    outcome:.[
        {[n;v] n set v;(1b;"")};
        (name;definition);
        {[e](0b;.tst.toString e)}];
    `ok`error!(first outcome;last outcome)
 };

.tst.recordCoverageLifecycle:{[phase;name;status;message]
    row:`phase`name`status`message!(
        phase;.tst.toString name;status;.tst.toString message);
    .tst.coverageLifecycleDiagnostics,:enlist row;
    ::
 };

.tst.coverageDropOwnership:{[name]
    if[name in key .tst.origFuncs;.tst.origFuncs _:name];
    if[name in key .tst.covWrappers;.tst.covWrappers _:name];
    .tst.coverageInstallOrder:.tst.coverageInstallOrder except enlist name;
    ::
 };

/ Clear measurement state only after wrapper ownership has been handled.
.tst.resetCoverageMeasurements:{[]
    .tst.trackedFiles::`symbol$();
    .tst.coverageData::()!();
    .tst.coverageLoadedFiles::`symbol$();
    .tst.lastCoverageModel::()!();
    .tst.loadingStack::();
    .tst.lineCoverageData::()!();
    .tst.stmtInstrumented::()!();
    .tst.stmtProbeLines::()!();
    .tst.statementCoverageData::(`symbol$())!`long$();
    .tst.statementSiteInstrumented::()!();
    .tst.branchCoverageData::(`symbol$())!();
    .tst.branchInstrumented::()!();
    .tst.coverageContextRegistry::()!();
    .tst.coverageContextMetricMeta::()!();
    .tst.coverageContextMetricHits::(`symbol$())!`long$();
    .tst.coverageActiveContext::()!();
    .tst.coverageContextOverflowActivations::0j;
    .tst.coverageContextDroppedHits::0j;
    .tst.coverageMetricDefinitions::()!();
    .tst.coverageFunctionMetricKeys::()!();
    .tst.coverageStatementMetricKeys::(`symbol$())!`symbol$();
    .tst.coverageBranchTrueMetricKeys::(`symbol$())!`symbol$();
    .tst.coverageBranchFalseMetricKeys::(`symbol$())!`symbol$();
    .tst.coverageContextEntryCache::()!();
    .tst.coverageParseDiagnostics::();
    .tst.coverageParseFailed::0b;
    ::
 };

/ Restore one wrapper only when the live definition is still the wrapper resQ
/ installed. A foreign replacement is never overwritten or captured as a new
/ original; it is blocked until a genuine source reload changes it.
.tst.restoreCoverageOne:{[name]
    if[not ((name in key .tst.origFuncs) and name in key .tst.covWrappers);
        msg:"incomplete coverage ownership metadata";
        .tst.recordCoverageLifecycle[`restore;name;`error;msg];
        :msg];
    original:.tst.origFuncs name;
    wrapper:.tst.covWrappers name;
    live:.tst.safeValue name;
    if[(live~wrapper) or live~.tst._covMissing;
        assigned:.tst.coverageAssign[name;original];
        if[not 1b~assigned`ok;
            msg:"assignment failed: ",assigned`error;
            .tst.recordCoverageLifecycle[`restore;name;`error;msg];
            :msg];
        .tst.coverageDropOwnership name;
        if[name in key .tst.coverageBlockedValues;
            .tst.coverageBlockedValues _:name];
        .tst.recordCoverageLifecycle[`restore;name;`restored;""];
        :""];
    if[live~original;
        .tst.coverageDropOwnership name;
        .tst.recordCoverageLifecycle[`restore;name;`already_restored;""];
        :""];
    .tst.coverageBlockedValues[name]:live;
    .tst.coverageDropOwnership name;
    msg:"live definition is not the owned wrapper; foreign value left untouched";
    .tst.recordCoverageLifecycle[`restore;name;`ownership_conflict;msg];
    msg
 };

/ Disable probes first, restore in reverse installation order, retain ownership
/ only for wrappers whose assignment failed (so they remain callable), and then
/ clear measurement state. Repeated stop calls are safe and retry retained work.
.tst.stopCoverage:{[]
    .tst.coverageEnabled::0b;
    order:reverse .tst.coverageInstallOrder;
    errors:$[count order;.tst.restoreCoverageOne each order;()];
    errors:errors where 0<count each errors;
    .tst.coverageInstallOrder::
        .tst.coverageInstallOrder where .tst.coverageInstallOrder in key .tst.covWrappers;
    .tst.resetCoverageMeasurements[];
    .tst.coverageInstallFailed::0b;
    .tst.coverageInstallErrors::();
    .tst.coverageLifecycleFailed::0<count errors;
    if[count errors;'"Coverage restoration failed: ","; " sv errors];
    1b
 };

.tst.ensureCoverageEntry:{[fileSym]
    if[not fileSym in key .tst.coverageData;
        .tst.coverageData[fileSym]: ()!();
        .tst.trackedFiles,: fileSym;
    ];
 };

.tst.coverageContextReserved:`unattributed`overflow;

.tst.coverageContextMeta:{[contextId;kind;testId;attempt;suite;description;file]
    `contextId`kind`testId`attempt`suite`description`file!(
        .tst.toString contextId;.tst.toString kind;.tst.toString testId;
        "j"$attempt;.tst.toString suite;.tst.toString description;
        .tst.repoRelativePath .tst.toString file)
 };

/ Register one context or fold it into the reserved overflow bucket. The limit
/ applies only to test/attempt contexts; the two reserved buckets never evict a
/ real context and make unattributed/overflow work visible even at the limit.
.tst.ensureCoverageContext:{[metadata]
    id:`$.tst.toString metadata`contextId;
    if[id in key .tst.coverageContextRegistry;
        :.tst.coverageContextRegistry id];
    if[(not id in .tst.coverageContextReserved) and
       count[(key .tst.coverageContextRegistry) except .tst.coverageContextReserved]>=
         "j"$@[get;`.tst.coverageContextMax;10000j];
        .tst.coverageContextOverflowActivations+:1;
        id:`overflow;
        metadata:.tst.coverageContextMeta[
            "overflow";"overflow";"";0j;"";"contexts beyond the configured limit";""]];
    if[not id in key .tst.coverageContextRegistry;
        .tst.coverageContextRegistry[id]:metadata];
    .tst.coverageContextRegistry id
 };

.tst.coverageCurrentContext:{[]
    if[(99h=type .tst.coverageActiveContext) and
       `contextId in key .tst.coverageActiveContext;
        :.tst.coverageActiveContext];
    .tst.ensureCoverageContext .tst.coverageContextMeta[
        "unattributed";"unattributed";"";0j;"";
        "work outside an active test attempt";""]
 };

/ Begin/end are called by the expectation runner. In test-detail mode every
/ retry shares one context; attempt-detail mode creates a stable child context.
.tst.coverageBeginAttempt:{[spec;expec;attempt]
    if[not 1b~@[get;`.tst.coverageContexts;0b];
        .tst.coverageActiveContext:()!();:()];
    testId:.tst.rerunTestId[spec;expec];
    caseId:.tst.expectationCaseId[spec;expec];
    executionId:$[count caseId;caseId;testId];
    detail:1b~@[get;`.tst.coverageAttemptContexts;0b];
    contextId:$[detail;
        "attempt_",.tst.stableHashText[executionId,"\n",string["j"$attempt]];
        executionId];
    file:$[`tstPath in key spec;.utl.pathToString spec`tstPath;""];
    metadata:.tst.coverageContextMeta[
        contextId;$[detail;"attempt";"test"];testId;
        $[detail;"j"$attempt;0j];
        $[`title in key spec;spec`title;`];
        $[`desc in key expec;expec`desc;`];file];
    .tst.coverageActiveContext:.tst.ensureCoverageContext metadata;
    ::
 };

.tst.coverageEndAttempt:{[]
    .tst.coverageActiveContext:()!();
    ::
 };

.tst.coverageMetricMeta:{[contextId;metricId;kind;file;functionName;siteId;edgeIndex]
    `contextId`metricId`kind`file`function`siteId`edgeIndex`edgeLabel!(
        .tst.toString contextId;.tst.toString metricId;.tst.toString kind;
        .tst.repoRelativePath .tst.toString file;.tst.toString functionName;
        .tst.toString siteId;"j"$edgeIndex;
        $[0=edgeIndex;"true";1=edgeIndex;"false";""])
 };

/. Create one stable, context-independent metric definition. The definition
/ count is bounded by the context-entry limit: probes beyond it remain present
/ in aggregate coverage, increment droppedMetricHits, and cannot grow caches.
.tst.defineCoverageMetric:{[kind;file;functionName;siteId;edgeIndex]
    path:.tst.repoRelativePath .tst.toString file;
    identity:(.tst.toString kind),"\n",path,"\n",
        (.tst.toString functionName),"\n",(.tst.toString siteId),"\n",
        string["j"$edgeIndex];
    metricText:"metric_",.tst.stableHashText identity;
    metricKey:`$metricText;
    if[metricKey in key .tst.coverageMetricDefinitions;:metricKey];
    if[count[.tst.coverageMetricDefinitions]>=
       "j"$@[get;`.tst.coverageContextEntryMax;250000j];:`];
    .tst.coverageMetricDefinitions[metricKey]:
        `metricId`kind`file`function`siteId`edgeIndex`edgeLabel!(
            metricText;.tst.toString kind;path;.tst.toString functionName;
            .tst.toString siteId;"j"$edgeIndex;
            $[0=edgeIndex;"true";1=edgeIndex;"false";""]);
    metricKey
 };

.tst.ensureCoverageFunctionMetric:{[file;functionName]
    fileSym:$[10h=abs type file;`$file;file];
    byFunction:$[fileSym in key .tst.coverageFunctionMetricKeys;
        first .tst.coverageFunctionMetricKeys fileSym;()!()];
    if[functionName in key byFunction;:byFunction functionName];
    metricKey:.tst.defineCoverageMetric[
        `function;fileSym;functionName;`; -1j];
    if[not null metricKey;
        byFunction[functionName]:metricKey;
        / Box the nested dictionary. Unboxed dictionary assignment promotes the
        / outer map to a keyed table and later files with different function
        / names fail schema conformance.
        .tst.coverageFunctionMetricKeys[fileSym]:enlist byFunction];
    metricKey
 };

.tst.ensureCoverageStatementMetric:{[siteId;file]
    siteText:.tst.toString siteId;
    siteKey:`$siteText;
    if[siteKey in key .tst.coverageStatementMetricKeys;
        :.tst.coverageStatementMetricKeys siteKey];
    metricKey:.tst.defineCoverageMetric[`statement;file;`;siteText;-1j];
    if[not null metricKey;.tst.coverageStatementMetricKeys[siteKey]:metricKey];
    metricKey
 };

.tst.ensureCoverageBranchMetrics:{[siteId;file;functionName]
    siteText:.tst.toString siteId;
    siteKey:`$siteText;
    if[(siteKey in key .tst.coverageBranchTrueMetricKeys) and
       siteKey in key .tst.coverageBranchFalseMetricKeys;
        :`trueMetric`falseMetric!(
            .tst.coverageBranchTrueMetricKeys siteKey;
            .tst.coverageBranchFalseMetricKeys siteKey)];
    metricKeys:.tst.defineCoverageMetric[
        `branch;file;functionName;siteText;] each 0 1j;
    if[(2=count metricKeys) and not any null metricKeys;
        .tst.coverageBranchTrueMetricKeys[siteKey]:first metricKeys;
        .tst.coverageBranchFalseMetricKeys[siteKey]:last metricKeys];
    `trueMetric`falseMetric!(first metricKeys;last metricKeys)
 };

.tst.coverageBranchMetricKey:{[siteId;file;functionName;edgeIndex]
    metrics:.tst.ensureCoverageBranchMetrics[siteId;file;functionName];
    index:"j"$edgeIndex;
    $[0=index;metrics`trueMetric;1=index;metrics`falseMetric;`]
 };

.tst.coverageMetricKey:{[kind;file;functionName;siteId;edgeIndex]
    kindText:.tst.toString kind;
    kindKey:`$kindText;
    $[kindKey=`function;
        .tst.ensureCoverageFunctionMetric[file;functionName];
      kindKey=`statement;
        .tst.ensureCoverageStatementMetric[siteId;file];
      kindKey=`branch;
        .tst.coverageBranchMetricKey[
            siteId;file;functionName;edgeIndex];
      `]
 };

/. The hot path accepts a precomputed metric key. Its nested cache is the
/ (context, site/edge) join index; only a first-seen pair hashes the private
/ entry ID and constructs public metadata.
.tst.recordCoverageContextMetricKey:{[metricKey]
    if[null metricKey;.tst.coverageContextDroppedHits+:1j;:()];
    if[not metricKey in key .tst.coverageMetricDefinitions;
        .tst.coverageContextDroppedHits+:1j;:()];
    ctx:.tst.coverageCurrentContext[];
    contextId:.tst.toString ctx`contextId;
    contextKey:`$contextId;
    byMetric:$[contextKey in key .tst.coverageContextEntryCache;
        first .tst.coverageContextEntryCache contextKey;()!()];
    if[metricKey in key byMetric;
        cachedEntry:byMetric metricKey;
        if[cachedEntry in key .tst.coverageContextMetricHits;
            .tst.coverageContextMetricHits[cachedEntry]+:1j;:()]];
    if[count[.tst.coverageContextMetricHits]>=
       "j"$@[get;`.tst.coverageContextEntryMax;250000j];
        .tst.coverageContextDroppedHits+:1j;:()];
    definition:.tst.coverageMetricDefinitions metricKey;
    entryText:"entry_",.tst.stableHashText[
        contextId,"\n",.tst.toString definition`metricId];
    entryId:`$entryText;
    metadata:`contextId`metricId`kind`file`function`siteId`edgeIndex`edgeLabel!(
        contextId;definition`metricId;definition`kind;definition`file;
        definition`function;definition`siteId;definition`edgeIndex;
        definition`edgeLabel);
    .tst.coverageContextMetricMeta[entryId]:metadata;
    .tst.coverageContextMetricHits[entryId]:1j;
    byMetric[metricKey]:entryId;
    .tst.coverageContextEntryCache[contextKey]:enlist byMetric;
    ::
 };

/ Add one attributed hit. A unique context/metric pair consumes one bounded
/ entry; once full, existing entries keep counting and only new pairs are
/ dropped. The aggregate hit has already been recorded by every caller.
.tst.recordCoverageContextMetric:{[kind;file;functionName;siteId;edgeIndex]
    if[not 1b~@[get;`.tst.coverageContexts;0b];:()];
    metricKey:.tst.coverageMetricKey[
        kind;file;functionName;siteId;edgeIndex];
    .tst.recordCoverageContextMetricKey metricKey
 };

/ Apply include/exclude rules consistently to both statically inventoried files
/ and files observed at runtime. `explicit` means the user named a source root;
/ that is authoritative and may intentionally include resQ's own lib directory.
.tst.coveragePathIncluded:{[absPath;explicit]
    includes: @[get; `.tst.app.coverageInclude; {()}];
    excludes: @[get; `.tst.app.coverageExclude; {()}];
    if[count includes; if[not any absPath like/: includes; :0b]];
    if[count excludes; if[any absPath like/: excludes; :0b]];
    if[(not explicit) and 0=count includes;
        home: @[get; `.resq.HOME; {""}];
        if[(0<count home) and absPath like home,"/lib/*"; :0b]];
    1b
 };

/ Why a discovered function lacks measured statements. This is derived from
/ canonical runtime state so every reporter uses the same classification.
.tst.coverageFallbackReason:{[fileSym;name]
    if[not 1b~@[get;`.tst.coverageStatements;0b]; :`statement_mode_disabled];
    if[not fileSym in .tst.coverageLoadedFiles; :`source_not_loaded];
    if[not name in key .tst.covWrappers; :`function_wrapper_unavailable];
    measured:$[fileSym in key .tst.stmtInstrumented;
        .tst.stmtInstrumented fileSym;`symbol$()];
    $[name in measured;`none;`rewrite_rejected]
 };

/ Aggregate instrumentation eligibility/completeness. Function coverage counts
/ every static function; statement completeness counts how many of those same
/ functions were safely rewritten with real probes.
.tst.coverageInstrumentationSummary:{[]
    files:key .tst.coverageData;
    found:sum 0,count each value .tst.coverageData;
    wrapped:sum 0,{[d] sum (key d) in key .tst.covWrappers} each value .tst.coverageData;
    measured:sum 0,{[f;d]
        names:$[f in key .tst.stmtInstrumented;.tst.stmtInstrumented f;`symbol$()];
        sum (key d) in names
    }'[files;value .tst.coverageData];
    loaded:sum 0,files in .tst.coverageLoadedFiles;
    filesMeasured:sum 0,{[f] $[f in key .tst.stmtInstrumented;
        0<count .tst.stmtInstrumented f;0b]} each files;
    stmtMode:1b~@[get;`.tst.coverageStatements;0b];
    fnPct:$[0=found;0f;100f*wrapped%found];
    stmtPct:$[0=found;0f;100f*measured%found];
    reasons:raze {[f;d] .tst.coverageFallbackReason[f;] each key d}'[
        files;value .tst.coverageData];
    reasonNames:`statement_mode_disabled`source_not_loaded`function_wrapper_unavailable`rewrite_rejected;
    reasonCounts:reasonNames!{[allReasons;reason] sum 0,allReasons=reason}[
        reasons;] each reasonNames;
    `filesFound`filesLoaded`filesWithStatements`functionsEligible`functionsInstrumented`functionInstrumentationPercent`statementMode`statementFunctionsEligible`statementFunctionsInstrumented`statementInstrumentationPercent`statementInstrumentationComplete`fallbackCounts!(
        count files;loaded;filesMeasured;found;wrapped;fnPct;stmtMode;found;measured;stmtPct;stmtMode and found=measured;reasonCounts)
 };

/ Resolve explicit roots to the canonical set of source files. Empty or invalid
/ declarations fail closed: a typo must not produce a green 0/0 coverage run.
.tst.coverageManifest:{[roots]
    rs: $[10h=type roots; enlist roots;
          -11h=type roots; enlist string roots;
          11h=type roots; string each roots;
          0h=type roots; {$[10h=type x;x;string x]} each roots;
          ()];
    if[0=count rs; '"Coverage source manifest is empty"];
    discovered: raze {[root]
        absRoot: .tst.resolvePath root;
        .tst.static.findSources absRoot
    } each rs;
    paths: distinct .tst.resolvePath each string each discovered;
    paths: paths where .tst.coveragePathIncluded[;1b] each paths;
    if[0=count paths;
        '"Coverage source manifest matched 0 .q files: ", ", " sv rs];
    `$paths
 };

/ Seed every statically discoverable function at zero before tests load code.
/ Runtime wrappers increment these same keys, making the source manifest the
/ denominator rather than the accidental set of modules a test happened to load.
.tst.seedCoverageFile:{[file]
    absPath: .tst.resolvePath file;
    fileSym: `$absPath;
    .tst.ensureCoverageEntry fileSym;
    fHandle: hsym (`$":" , absPath);
    fns: @[.tst.static.exploreFile; fHandle; {([] name:`$(); line:`int$())}];
    if[not 98h=type fns; :()];
    srcLines: @[read0; fHandle; {()}];
    nsAt: .tst.coverageSysDNamespaces srcLines;
    {[fs;namespaces;row]
        nm: .tst.coverageQualifyName[namespaces;row`line;row`name];
        if[not nm in key .tst.coverageData fs;
            .tst.coverageData[fs;nm]: 0j]
    }[fileSym;nsAt] each fns;
    ::
 };

/ Record execution (called by wrappers)
.tst.recordExecution:{[file;funcName]
    if[not .tst.coverageEnabled; :()];

    fileSym: $[10h = abs type file; `$file; file];
    .tst.ensureCoverageEntry[fileSym];

    if[not funcName in key .tst.coverageData[fileSym];
        .tst.coverageData[fileSym;funcName]: 0;
    ];

    .tst.coverageData[fileSym;funcName]+: 1;
    .[.tst.recordCoverageContextMetric;
        (`function;fileSym;funcName;`; -1j);{[e] ::}];
 };

/ @param name (symbol) Function name (e.g. `.user.create`)
/ @param fileSym (symbol) Source file symbol
.tst.wrapFunc:{[name;fileSym]
    / Skip coverage internals.
    if[name in .tst.coverageSkipNames; :()];

    live:.tst.safeValue name;
    if[name in key .tst.coverageBlockedValues;
        if[live~.tst.coverageBlockedValues name;
            msg:"foreign/stale wrapper still owns the live definition";
            .tst.recordCoverageLifecycle[`install;name;`blocked;msg];
            .tst.coverageInstallFailed::1b;
            .tst.coverageInstallErrors,:enlist .tst.toString[name],": ",msg;
            :()];
        / A source reload replaced the blocked value, so it is safe to consider
        / the new definition for a fresh session.
        .tst.coverageBlockedValues _:name;
    ];

    / Already-wrapped guard, RELOAD-AWARE. The old guard skipped on mere name
    / membership in .tst.origFuncs, so after a file reload (which installs a
    / fresh UNWRAPPED definition) re-instrumenting was a no-op: the name was
    / still registered, the live function stayed unwrapped, and hits were zero.
    / Instead compare the LIVE value to the wrapper we installed (kept in
    / covWrappers). `~` on lambdas is structural and each wrapper embeds its own
    / name, so wrappers for different names differ - a true identity test.
    /   - live value IS our wrapper  -> already instrumented, skip.
    /   - live value is the registered original (same-source reload) -> re-wrap.
    /   - any other live value -> diagnose an ownership conflict and fail closed.
    orig:live;
    if[name in key .tst.covWrappers;
        if[live~.tst.covWrappers name; :()];
        if[not ((name in key .tst.origFuncs) and live~.tst.origFuncs name);
            msg:"live definition changed while an owned wrapper was registered";
            .tst.coverageBlockedValues[name]:live;
            .tst.coverageDropOwnership name;
            .tst.recordCoverageLifecycle[`install;name;`ownership_conflict;msg];
            .tst.coverageInstallFailed::1b;
            .tst.coverageInstallErrors,:enlist .tst.toString[name],": ",msg;
            :()
        ];
        orig:.tst.origFuncs name;
    ];
    if[orig ~ .tst._covMissing; :()];
    
    / Handle potential projections or lists with metadata
    if[0h = type orig; orig: first orig];
    
    if[not type[orig] within (100h;104h); :()];

    / Introspect the original to recover its argument names so the wrapper can
    / forward them positionally. `value[f] 1` resolves BOTH explicit ({[x;y]..})
    / and implicit ({x+y} -> `x`y) lambdas to their canonical arg names, so the
    / rebuilt {[x;y] ...} preserves the original rank and call semantics. But it
    / SIGNALS 'type for compiled operators/derived functions (102h/103h), which
    / pass the type guard above; trap it and skip rather than crash. The handler
    / must be a lambda (q's @[f;x;e] requires it).
    args: @[{value[x] 1}; orig; {(::)}];
    if[args ~ (::); :()];

    .tst.origFuncs[name]: orig;

    / Function probes use this lookup after every call. Build the stable metric
    / identity while installing the wrapper so the execution path only performs
    / bounded dictionary lookups and increments.
    if[1b~@[get;`.tst.coverageContexts;0b];
        .tst.ensureCoverageFunctionMetric[fileSym;name]];

    argStr: $[0 < count args; ";" sv string args; ""];
    callArgs: "[", argStr, "]";

    / The recorded file key MUST equal the symbol ensureCoverageEntry / the LCOV
    / writer use (\`$absPath, NO ":" prefix). recordExecution does `\`$file` for a
    / string arg, so embed the path as an ESCAPED STRING LITERAL and let it
    / symbol-ize - identical to \`$absPath. A backtick-symbol literal can't be
    / used here: a path starts with "/", and `\`/tmp/x` does not parse as a
    / symbol. (The previous code wrote `hsym "..."`, producing \`:absPath, so
    / hits landed under a key the report never read - always-empty coverage.)
    pathLit: ssr[ssr[string fileSym; "\\"; "\\\\"]; "\""; "\\\""];
    wrapperCode: raze ("{"; callArgs;
        " .tst.recordExecution[\"", pathLit, "\";`"; string name; " ];";
        " .tst.origFuncs[`"; string name; " ]"; callArgs;
        " }");

    / Parse the wrapper text; a failure here (exotic arg names, etc.) must leave
    / the original definition untouched, so trap it and bail.
    wrapFn: @[value; wrapperCode; {(::)}];
    if[wrapFn ~ (::);.tst.coverageDropOwnership name;:()];

    / Install the wrapper. MUST use the .[set;args;h] (dot-apply) trap form, not
    / @[set;args;h]: `set` is dyadic, and @[f;x;e] applies it MONADICALLY to the
    / 2-list - a no-op that silently leaves the original in place (and so wrapped
    / nothing, the deepest cause of the empty-coverage bug). .[set;(name;val);h]
    / applies both args. On failure, drop the half-registered entries so a later
    / re-instrument retries cleanly.
    assigned:.tst.coverageAssign[name;wrapFn];
    if[not 1b~assigned`ok;
        msg:"Coverage wrap failed for ",string[name],": ",assigned`error;
        -1 msg;
        .tst.coverageDropOwnership name;
        .tst.recordCoverageLifecycle[`install;name;`error;msg];
        .tst.coverageInstallFailed::1b;
        .tst.coverageInstallErrors,:enlist msg;
        :()];

    / Record the installed wrapper's identity so the reload-aware guard above can
    / tell "still our wrapper" from "reloaded behind our back".
    .tst.covWrappers[name]: wrapFn;
    .tst.coverageInstallOrder:distinct .tst.coverageInstallOrder,name;
 };

/ Instrument a loaded file (analyze and wrap functions)
/ @param pathStr (string) Absolute normalized path
.tst.instrumentFile:{[pathStr]
    if[not .tst.coverageEnabled; :()];

    absPath: .tst.resolvePath pathStr;
    
    if[not .tst.coveragePathIncluded[absPath;0b]; :()];


    fileSym: `$absPath;
    .tst.ensureCoverageEntry[fileSym];

    fHandle: hsym (`$":" , absPath);
    if[() ~ key fHandle; :()];

    fns: @[.tst.static.exploreFile; fHandle; {() }];
    if[not 98h = type fns; :()];
    if[0 = count fns; :()];
    .tst.coverageLoadedFiles: distinct .tst.coverageLoadedFiles,fileSym;

    / exploreFile applies `\d <ns>` namespacing, but NOT the runtime
    / `system "d <ns>"` form some sources use to open a namespace - those
    / functions are returned BARE (e.g. `create` for a fn that actually loaded
    / as `.user.create`), so wrapping the bare name finds nothing. Re-derive the
    / runtime-`d` namespace active at each function's line and qualify any bare
    / name accordingly, so the wrapped (and recorded) name matches the loaded
    / definition and the LCOV report. Names exploreFile already qualified (`.*`)
    / are left as-is.
    lines: @[read0; fHandle; {()}];
    nsAt: .tst.coverageSysDNamespaces lines;

    / Statement probes go in BEFORE the function wrapper, so the wrapper closes
    / over the instrumented body. Each attempt is independent: a function that
    / cannot be rewritten safely simply keeps derived line records.
    starts: "j"$ $[`line in cols fns; fns`line; `long$()];
    starts: starts where not null starts;
    if[(1b~@[get;`.tst.coverageStatements;0b]) or
       1b~@[get;`.tst.coverageBranches;0b];
        {[fs; nsAt; srcLines; starts; row]
            nm: .tst.coverageQualifyName[nsAt; row`line; row`name];
            span: .tst.covFunctionSpan[srcLines; row`line; starts];
            if[span[1] >= span[0];
                / Trapped per function: a rewrite that throws must cost only this
                / function its statement data, never abort instrumentation of the
                / rest of the file (or, via the caller, of every later file).
                okStmt: @[.tst.covInstrumentStatements[nm; fs; srcLines; span 0;]; span 1; {[e] 0b}];
                if[(1b~okStmt) and 1b~@[get;`.tst.coverageStatements;0b];
                    d: $[fs in key .tst.stmtInstrumented; .tst.stmtInstrumented fs; `symbol$()];
                    .tst.stmtInstrumented[fs]: distinct d, nm];
            ];
        }[fileSym; nsAt; lines; starts] each fns;
    ];

    {[fs;nsAt;row]
        nm: row`name;
        nm: .tst.coverageQualifyName[nsAt; row`line; nm];
        .tst.wrapFunc[nm; fs]
    }[fileSym; nsAt] each fns;
 };

/ Build a per-line active-namespace vector from a file's `system "d <ns>"`
/ directives (the runtime equivalent of `\d <ns>`). Returns a list of strings,
/ one per source line, giving the namespace string ("" at root, ".user", ...)
/ in effect ON that line. `system "d ."` / `system "d \`."` resets to root.
.tst.coverageSysDNamespaces:{[lines]
    {[acc;ln]
        cur: last acc;
        t: trim ln;
        / Match a `system "d <ns>"` directive and pull <ns> from between the two
        / double-quotes. "d ." / "d `." reset to root.
        if[t like "system \"d *";
            q1: t ? "\"";
            rest: (q1+1) _ t;
            q2: rest ? "\"";
            arg: trim q2 # rest;                / e.g. "d .user"
            if[arg like "d *";
                ns: trim 2 _ arg;
                ns: $[ns like "`*"; 1 _ ns; ns]; / tolerate `.user spelling
                cur: $[(ns ~ ".") or (0 = count ns); ""; ns];
            ];
        ];
        acc, enlist cur
    }/[enlist ""; lines]
 };

/ Qualify a bare function name with the runtime-`d` namespace active at `line`
/ (1-based, as exploreFile reports). Already-dotted names pass through.
.tst.coverageQualifyName:{[nsAt;line;name]
    s: string name;
    if[s like ".*"; :name];                 / already namespaced
    idx: line - 1;                          / nsAt is 0-based per source line
    if[(idx < 0) or idx >= count nsAt; :name];
    ns: nsAt idx;
    if[0 = count ns; :name];
    `$ns, ".", s
 };

/ Load a .q file by absolute path, tolerating spaces in the path.
/ q's `\l` (system "l ...") cannot parse a path containing spaces - it splits on
/ whitespace and raises 'nyi. The portable workaround is to chdir into the file's
/ directory (q's `system "cd <dir>"` IS the supported way to chdir the q process,
/ and it does accept a spaced directory) and `\l` the bare basename, then restore
/ the previous working directory. The cwd is restored on BOTH success and error.
.tst.coverageLoadFile:{[pathStr]
    .utl.loadQFile pathStr
 };

/ Load and instrument a source file explicitly
.tst.loadSource:{[file]
    pathStr: .tst.resolvePath file;

    if[any pathStr~/:.tst.loadingStack; :()];
    .tst.loadingStack,: enlist pathStr;

    @[.tst.coverageLoadFile; pathStr; {[e]
        .tst.loadingStack:: -1 _ .tst.loadingStack;
        'e
    }];

    .tst.instrumentFile pathStr;
    .tst.loadingStack:: -1 _ .tst.loadingStack;
 };

/ Instrument already-loaded .q files once coverage is enabled
.tst.instrumentLoadedFiles:{[]
    / `utl in key `.` is ALWAYS false: q's root key list does not report child
    / namespaces (`key `.` is empty even when .utl exists, while `key `.utl`
    / works). This guard therefore returned before instrumenting anything, so
    / coverage only ever saw files loaded through .tst.sysl (\l) and nothing
    / loaded via .utl.require. Probe the variable itself instead.
    loaded: @[get; `.utl.loaded; {()}];
    if[0 = count loaded; :()];

    files: loaded where (loaded like "*.q") and not loaded like "*coverage.q";
    files: files where 0 < count each files;

    / Trapped per file for the same reason: one unreadable or unparseable source
    / must not stop the remaining files being instrumented.
    { @[.tst.instrumentFile; .tst.resolvePath x; {[p;e]
          -1 "Coverage: could not instrument ", p, ": ", .tst.toString e
        }[.tst.resolvePath x]] } each files;
 };

/ Initialize coverage and instrument already-loaded files
.tst.initCoverage:{[files]
    / Never clear ownership before unwinding the preceding session.
    .tst.stopCoverage[];
    .tst.coverageLifecycleDiagnostics::();
    .tst.coverageLifecycleFailed::0b;
    .tst.coverageInstallFailed::0b;
    .tst.coverageInstallErrors::();
    raw: $[10h=type files; enlist files;
           -11h=type files; enlist string files;
           11h=type files; string each files;
           0h=type files; {$[10h=type x;x;string x]} each files;
           ()];
    fs: `$distinct .tst.resolvePath each raw;
    .tst.resetCoverageMeasurements[];
    .tst.coverageEnabled:: 1b;

    .tst.seedCoverageFile each fs;

    / Wrap what is already loaded so coverage has a chance to observe calls
    .tst.instrumentLoadedFiles[];

    if[.tst.coverageInstallFailed;
        installErrors:.tst.coverageInstallErrors;
        rollback:@[
            {[fn]fn[];(0b;"")};
            .tst.stopCoverage;
            {[e](1b;.tst.toString e)}];
        msg:"Coverage initialization failed: ","; " sv installErrors;
        if[first rollback;msg,:"; rollback failed: ",last rollback];
        'msg];

    -1 "Coverage tracking initialized.";
 };

/ Lines that carry executable code, as a boolean per source line. Masking blanks
/ out comments, strings and block comments first, so a comment-only or blank line
/ is never counted as coverable.
.tst.coverableLines:{[srcLines]
    if[0 = count srcLines; :`boolean$()];
    / Fall back to the raw lines if masking is unavailable or changes the line
    / count; a comment-only line then still fails the trim test below only if it
    / is genuinely blank, which is the safe direction (over-counting coverable
    / lines understates coverage rather than overstating it).
    masked: @[.tst.static.maskLines; srcLines; {[e] `maskFailed}];
    if[not (0h = type masked) and (count masked) = count srcLines;
        masked: srcLines];
    {0 < count trim x} each masked
 };

/ Source lines a function spans: (startLine; endLine). exploreFile flattens a
/ function's body to a single line, so height cannot come from there -- a
/ function instead runs to the line before the next function starts, and the
/ last one to end of file. Blank and comment lines in that range are filtered
/ out by the caller, so trailing gaps between functions do not inflate the count.
.tst.functionLineSpan:{[startLine; allStarts; totalLines]
    st: "j"$ startLine;
    if[(null st) or st < 1; :(0j; -1j)];
    later: allStarts where allStarts > st;
    endLine: $[count later; (min later) - 1; totalLines];
    if[endLine > totalLines; endLine: totalLines];
    (st; endLine)
 };

/ The last line of a function DEFINITION, found by balancing brackets from its
/ first line. `maxEnd` is the search bound from .tst.functionLineSpan.
/ .
/ The bound alone is too generous: it stops at the line before the NEXT
/ definition, so the last function in a file absorbed everything after it. For
/ the common `\d .` footer that meant the statement rewriter tried to `value` a
/ system command, which it cannot -- the rewrite was rejected and the file's last
/ function silently lost its line records while still reporting FN:/FNDA:. The
/ same over-reach would have swallowed any top-level statement sitting between
/ two definitions, probing it and re-running it at instrumentation time.
/ .
/ Fails open to `maxEnd` when the brackets never balance (an unterminated
/ definition, or a body extending past the bound), preserving the old behaviour
/ for anything this cannot parse.
.tst.covDefinitionEnd:{[srcLines; startLine; maxEnd]
    if[startLine < 1; :maxEnd];
    if[maxEnd > count srcLines; :maxEnd];
    delta: @[get; `.tst.bracketDelta; {::}];
    if[not (type delta) within 100 104h; :maxEnd];
    depth: 0;
    i: startLine;
    while[i <= maxEnd;
        depth+: delta srcLines[i - 1];
        if[depth <= 0; :i];
        i+: 1];
    maxEnd
 };

/ Span of a function definition: the search bound, tightened to where the
/ definition actually closes.
.tst.covFunctionSpan:{[srcLines; startLine; allStarts]
    span: .tst.functionLineSpan[startLine; allStarts; count srcLines];
    if[span[1] < span[0]; :span];
    (span 0; .tst.covDefinitionEnd[srcLines; span 0; span 1])
 };

/ ---------------------------------------------------------------------------
/ Statement-level instrumentation.
/ .
/ Function-level wrapping cannot say WHICH lines of a called function ran, so
/ line records derived from it read as covered even for a branch that never
/ executed. Real per-line data needs a probe on each statement, which means
/ rewriting the function's source at load time -- a transformation on the user's
/ own code. It is therefore attempted per function and abandoned per function:
/ any parse failure, rank change or exception restores the original definition
/ and that function falls back to derived lines. Correctness of the code under
/ test always wins over resolution of the report.
/ ---------------------------------------------------------------------------

/ line -> hit count, per file. Separate from coverageData (function hits).
if[not `lineCoverageData in key `.tst;.tst.lineCoverageData:()!()];
/ Files whose lines are genuinely MEASURED (not derived), per function name.
if[not `stmtInstrumented in key `.tst;.tst.stmtInstrumented:()!()];
/ Lines carrying a probe, per file -- the denominator for measured coverage.
if[not `stmtProbeLines in key `.tst;.tst.stmtProbeLines:()!()];
/ Stable statement-site id -> executions. Line totals remain a separate LCOV
/ roll-up because several outer/anonymous statements may share one source line.
if[not `statementCoverageData in key `.tst;.tst.statementCoverageData:(`symbol$())!`long$()];
/ Files -> stable statement-site ids whose enclosing named-function rewrite
/ survived as one unit.
if[not `statementSiteInstrumented in key `.tst;.tst.statementSiteInstrumented:()!()];
/ Stable branch-site id -> two edge counters (`true` then `false`).
if[not `branchCoverageData in key `.tst;.tst.branchCoverageData:(`symbol$())!()];
/ Files -> stable branch-site ids whose enclosing function rewrite survived.
if[not `branchInstrumented in key `.tst;.tst.branchInstrumented:()!()];

.tst.covL:{[f;n]
    if[not f in key .tst.lineCoverageData;
        .tst.lineCoverageData[f]:(`long$())!`long$()];
    if[not n in key .tst.lineCoverageData f;
        .tst.lineCoverageData[f;n]:0j];
    / Amend the nested counter in place. Copying the whole per-file dictionary
    / made one statement hit scale with the number of sites in its source file.
    .tst.lineCoverageData[f;n]+:1j;
 };

.tst.covS:{[siteId;f;n]
    siteKey:`$.tst.toString siteId;
    .tst.statementCoverageData[siteKey]:1+$[siteKey in key .tst.statementCoverageData;
        .tst.statementCoverageData siteKey;0j];
    .tst.covL[f;n];
    .[.tst.recordCoverageContextMetric;
        (`statement;f;`;siteId;-1j);{[e] ::}]
 };

/ Record one condition evaluation and return the value byte-for-byte. q control
/ forms accept numeric truthy/falsy atoms as well as booleans, so classification
/ uses q's own conditional semantics. Invalid conditions are trapped only for
/ accounting, then reach the original control form and raise their original
/ error; neither edge is credited for a condition that cannot select one.
.tst.covC:{[siteId;file;functionName;condition]
    siteKey:`$.tst.toString siteId;
    outcome:@[{[x](1b;$[x;1b;0b])};condition;{[e](0b;0b)}];
    if[first outcome;
        hits:$[siteKey in key .tst.branchCoverageData;
            .tst.branchCoverageData siteKey;0 0j];
        edge:$[last outcome;0;1];
        hits[edge]+:1;
        .tst.branchCoverageData[siteKey]:hits;
        .[.tst.recordCoverageContextMetric;
            (`branch;file;functionName;siteId;"j"$edge);{[e] ::}]];
    condition
 };

.tst.covOffsetLocation:{[flat;startLine;offset]
    prefix:offset#flat;
    breaks:where prefix="\n";
    line:"j"$startLine+count breaks;
    column:"j"$$[count breaks;offset-(1+last breaks);offset];
    (line;column)
 };

.tst.covTrimRange:{[flat;range]
    firstAt:"j"$range 0;
    afterAt:"j"$range 1;
    whitespace:" \t\r\n";
    while[(firstAt<afterAt) and flat[firstAt] in whitespace;firstAt+:1];
    while[(afterAt>firstAt) and flat[afterAt-1] in whitespace;afterAt-:1];
    (firstAt;afterAt)
 };

/ Return half-open argument ranges for a bracket call. Strings/comments have
/ already been space-masked, so delimiters inside them cannot participate.
.tst.covCallArgumentRanges:{[masked;openAt]
    if[(openAt<0) or openAt>=count masked;:()];
    if[not "["=masked openAt;:()];
    square:1;round:0;curly:0;
    starts:enlist 1+openAt;
    ends:`long$();
    i:1+openAt;
    while[i<count masked;
        c:masked i;
        if[(c=";") and square=1 and round=0 and curly=0;
            ends,:i;starts,:i+1];
        $[c="[";square+:1;
          c="]";[square-:1;if[square=0;ends,:i;:flip (starts;ends)]];
          c="(";round+:1;
          c=")";round-:1;
          c="{";curly+:1;
          c="}";curly-:1;
          ::];
        i+:1];
    ()
 };

.tst.covKeywordBoundary:{[masked;at;length]
    ident:.Q.a,.Q.A,"0123456789_.";
    beforeOk:(at=0) or not masked[at-1] in ident;
    afterAt:at+length;
    afterOk:(afterAt>=count masked) or not masked[afterAt] in ident;
    beforeOk and afterOk
 };

.tst.covNextCodeAt:{[masked;at]
    i:at;
    while[(i<count masked) and masked[i] in " \t\r\n";i+:1];
    i
 };

/. A mask failure means source syntax cannot be inventoried safely. Record one
/. deduplicated diagnostic, return a tagged outcome, and let callers omit the
/. unsafe rewrite while the canonical model and aggregate artifacts still form.
/. The runner later treats sourceParseComplete=false as an unconditional
/. coverage error, after LCOV/JSON/HTML evidence has been written.
.tst.recordCoverageParseFailure:{[file;functionName;phase;message]
    row:`file`function`phase`message!(
        .tst.repoRelativePath .tst.toString file;
        .tst.toString functionName;.tst.toString phase;.tst.toString message);
    duplicate:any {x~y}[row;] each .tst.coverageParseDiagnostics;
    if[not duplicate;.tst.coverageParseDiagnostics,:enlist row];
    .tst.coverageParseFailed::1b;
    ::
 };

.tst.coverageMaskForParsing:{[file;functionName;phase;srcLines]
    outcome:@[
        {[lines](1b;.tst.static.maskLines lines)};
        srcLines;
        {[e](0b;.tst.toString e)}];
    if[not first outcome;
        message:"source masking failed: ",.tst.toString last outcome;
        .tst.recordCoverageParseFailure[file;functionName;phase;message];
        :`ok`lines`error!(0b;();message)];
    masked:last outcome;
    if[(not 0h=type masked) or not count[masked]=count srcLines;
        message:"source masking returned an invalid line structure";
        .tst.recordCoverageParseFailure[file;functionName;phase;message];
        :`ok`lines`error!(0b;();message)];
    `ok`lines`error!(1b;masked;"")
 };

/ Inventory the named outer lambda and every anonymous lambda nested inside it.
/ Private offsets let both statement and branch scanners attribute sites to the
/ innermost lambda without inventing LCOV function names. Anonymous identities
/ are stable under checkout relocation and remain children of the named owner.
.tst.covLambdaSpansInFunction:{[fileSym;functionName;srcLines;startLine;endLine]
    if[(startLine<1) or (endLine>count srcLines) or endLine<startLine;:()];
    seg:srcLines[(startLine-1)+til 1+endLine-startLine];
    raw:"\n" sv {(),x} each seg;
    mask:.tst.coverageMaskForParsing[
        fileSym;functionName;`lambda_inventory;seg];
    if[not mask`ok;:()];
    maskedLines:mask`lines;
    masked:"\n" sv {(),x} each maskedLines;
    if[not (count masked)=count raw;:()];
    relativePath:.tst.repoRelativePath string fileSym;
    functionText:.tst._covNameStr functionName;
    stack:();spans:();depth:0;i:0;
    while[i<count masked;
        c:masked i;
        if[c="{";
            depth+:1;
            stack,:enlist `openAt`depth!("j"$i;"j"$depth)];
        if[c="}";
            if[count stack;
                opened:last stack;
                stack:-1 _ stack;
                openAt:opened`openAt;
                lambdaDepth:("j"$opened`depth)-1;
                bodyStart:openAt+1;
                while[(bodyStart<i) and masked[bodyStart] in " \t\r\n";
                    bodyStart+:1];
                eligible:1b;fallback:"none";
                if[(bodyStart<i) and "["=masked bodyStart;
                    square:1;k:bodyStart+1;
                    while[(k<i) and square>0;
                        $[masked[k]="[";square+:1;
                          masked[k]="]";square-:1;::];
                        k+:1];
                    if[square=0;
                        bodyStart:k;
                        while[(bodyStart<i) and masked[bodyStart] in " \t\r\n";
                            bodyStart+:1]];
                    if[square<>0;
                        eligible:0b;fallback:"invalid_parameters"]];
                location:.tst.covOffsetLocation[raw;startLine;openAt];
                anonymous:lambdaDepth>0;
                lambdaId:$[anonymous;
                    "lambda_",.tst.stableHashText[
                        relativePath,"\n",functionText,"\n",
                        string[location 0],":",string[location 1]];
                    ""];
                spans,:enlist `lambdaId`function`line`column`lambdaDepth`anonymous`eligible`fallbackReason`openAt`bodyStart`closeAt!(
                    lambdaId;functionText;location 0;location 1;lambdaDepth;
                    anonymous;eligible;fallback;openAt;"j"$bodyStart;"j"$i)];
            depth-:1;
            if[depth<0;depth:0]];
        i+:1];
    if[0=count spans;:()];
    spans:spans iasc[spans`openAt];
    spans
 };

/ Run the established statement parser over one exact lambda body and convert
/ its first-line-relative columns back to function-source coordinates.
.tst.covStatementPositionsInRange:{[masked;startLine;rangeStart;rangeEnd]
    if[rangeEnd<=rangeStart;:()];
    body:(rangeEnd-rangeStart)#rangeStart _ masked;
    if[0=count body;:()];
    location:.tst.covOffsetLocation[masked;startLine;rangeStart];
    texts:"\n" vs body;
    if[0=count texts;:()];
    lineNumbers:location[0]+til count texts;
    positions:.tst.covStatementPositions flip (lineNumbers;texts);
    if[0=count positions;:()];
    {[firstLine;firstColumn;p]
        $[p[0]=firstLine;(p 0;firstColumn+p 1);p]
    }[location 0;location 1;] each positions
 };

/ Canonical statement sites include outer and anonymous-lambda statements.
/ Each site belongs to the enclosing named function; lambdaId/lambdaDepth add
/ anonymous ownership without fabricating FN/FNDA records.
.tst.covStatementSitesInFunction:{[fileSym;functionName;srcLines;startLine;endLine]
    if[(startLine<1) or (endLine>count srcLines) or endLine<startLine;:()];
    seg:srcLines[(startLine-1)+til 1+endLine-startLine];
    raw:"\n" sv {(),x} each seg;
    mask:.tst.coverageMaskForParsing[
        fileSym;functionName;`statement_inventory;seg];
    if[not mask`ok;:()];
    maskedLines:mask`lines;
    masked:"\n" sv {(),x} each maskedLines;
    if[not (count masked)=count raw;:()];
    spans:.tst.covLambdaSpansInFunction[
        fileSym;functionName;srcLines;startLine;endLine];
    if[0=count spans;:()];
    relativePath:.tst.repoRelativePath string fileSym;
    functionText:.tst._covNameStr functionName;
    lineOffsets:0,1+where raw="\n";
    sites:();i:0;
    while[i<count spans;
        owner:spans i;
        ownerMasked:masked;
        children:spans where
            (spans[`openAt]>owner`openAt) &
            (spans[`closeAt]<owner`closeAt);
        j:0;
        while[j<count children;
            child:children j;
            childLength:max 0,(child`closeAt)-(1+child`openAt);
            childIndexes:(1+child`openAt)+til childLength;
            if[count childIndexes;
                replaceIndexes:childIndexes where ownerMasked[childIndexes]<>"\n";
                if[count replaceIndexes;
                    ownerMasked[replaceIndexes]:count[replaceIndexes]#" "]];
            j+:1];
        positions:$[1b~owner`eligible;
            .tst.covStatementPositionsInRange[
                ownerMasked;startLine;owner`bodyStart;owner`closeAt];()];
        j:0;
        while[j<count positions;
            position:positions j;
            rewriteAt:lineOffsets[("j"$position 0)-startLine]+position 1;
            siteId:"statement_",.tst.stableHashText[
                relativePath,"\n",functionText,"\n",
                string[position 0],":",string[position 1],"\n",
                .tst.toString owner`lambdaId];
            sites,:enlist `siteId`function`line`column`lambdaId`lambdaDepth`anonymous`eligible`fallbackReason`rewriteAt!(
                siteId;functionText;"j"$position 0;"j"$position 1;
                owner`lambdaId;"j"$owner`lambdaDepth;owner`anonymous;
                owner`eligible;owner`fallbackReason;"j"$rewriteAt);
            j+:1];
        i+:1];
    if[0=count sites;:()];
    sites iasc[sites`rewriteAt]
 };

/ Canonical branch inventory for one named outer lambda. Sites inside anonymous
/ lambdas retain the enclosing named function plus a stable lambda identity.
/ Private rewriteStart/rewriteEnd fields are removed by the public model.
.tst.covBranchSitesInFunction:{[fileSym;functionName;srcLines;startLine;endLine]
    if[(startLine<1) or (endLine>count srcLines) or endLine<startLine;:()];
    seg:srcLines[(startLine-1)+til 1+endLine-startLine];
    raw:"\n" sv {(),x} each seg;
    mask:.tst.coverageMaskForParsing[
        fileSym;functionName;`branch_inventory;seg];
    if[not mask`ok;:()];
    maskedLines:mask`lines;
    masked:"\n" sv {(),x} each maskedLines;
    if[not (count masked)=count raw;:()];
    relativePath:.tst.repoRelativePath string fileSym;
    functionText:.tst._covNameStr functionName;
    lambdaSpans:.tst.covLambdaSpansInFunction[
        fileSym;functionName;srcLines;startLine;endLine];
    sites:();
    i:0;
    while[i<count masked;
        c:masked i;
        token:"";tokenLength:0;openAt:-1;
        if[(2<=(count masked)-i) and "if"~2#i _ masked;
            if[.tst.covKeywordBoundary[masked;i;2];
                candidate:.tst.covNextCodeAt[masked;i+2];
                if[(candidate<count masked) and "["=masked candidate;
                    token:"if";tokenLength:2;openAt:candidate]]];
        if[(0=count token) and (5<=(count masked)-i) and "while"~5#i _ masked;
            if[.tst.covKeywordBoundary[masked;i;5];
                candidate:.tst.covNextCodeAt[masked;i+5];
                if[(candidate<count masked) and "["=masked candidate;
                    token:"while";tokenLength:5;openAt:candidate]]];
        if[(0=count token) and c="$";
            candidate:.tst.covNextCodeAt[masked;i+1];
            if[(candidate<count masked) and "["=masked candidate;
                token:enlist "$";tokenLength:1;openAt:candidate]];
        if[count token;
            args:.tst.covCallArgumentRanges[masked;openAt];
            argCount:count args;
            conditionIndexes:$[token~enlist "$";
                $[(argCount>=3) and 1=argCount mod 2;
                    2*til ((argCount-1) div 2);`long$()];
                $[argCount>=2;enlist 0j;`long$()]];
            ci:0;
            while[ci<count conditionIndexes;
                conditionIndex:conditionIndexes ci;
                range:.tst.covTrimRange[raw;args conditionIndex];
                location:.tst.covOffsetLocation[raw;startLine;range 0];
                nonempty:range[1]>range 0;
                owners:lambdaSpans where
                    ((range 0)>=lambdaSpans`bodyStart) &
                    ((range 0)<lambdaSpans`closeAt);
                owner:$[count owners;last owners;()!()];
                owned:99h=type owner;
                eligible:owned and nonempty and 1b~owner`eligible;
                fallback:$[not owned;`unowned_condition;
                    not nonempty;`empty_condition;
                    not 1b~owner`eligible;`lambda_rewrite_rejected;`none];
                lambdaId:$[owned;owner`lambdaId;""];
                lambdaDepth:$[owned;"j"$owner`lambdaDepth;0j];
                siteId:"branch_",.tst.stableHashText[
                    relativePath,"\n",functionText,"\n",token,"\n",
                    string[location 0],":",string[location 1],"\n",string ci];
                sites,:enlist `siteId`function`kind`conditionIndex`line`column`lambdaId`lambdaDepth`anonymous`eligible`fallbackReason`rewriteStart`rewriteEnd!(
                    siteId;functionText;token;"j"$ci;location 0;location 1;
                    lambdaId;lambdaDepth;lambdaDepth>0;eligible;string fallback;
                    range 0;range 1);
                ci+:1]];
        i+:1];
    sites
 };

/ Split a function body into top-level statements, returning the source line
/ each one starts on. Depth-, string- and comment-aware.
/ Statements nested in `if[...]`, `do[...]` and `while[...]` count too: those
/ forms evaluate every argument after the first, so each is a real statement and
/ q guard clauses (`if[bad; :error]`) are exactly what needs measuring.
/ `$[...]` is deliberately NOT descended into -- it is a conditional EXPRESSION
/ whose branches are values, and probing there would change what it returns.
.tst.covStatementPositions:{[bodyLines]
    depth: 0; inStr: 0b; esc: 0b;
    atStart: 1b;
    stmtDepths: enlist 0;    / bracket depths that hold a statement LIST
    word: "";                / identifier immediately before the next "["
    starts: ();
    i: 0;
    while[i < count bodyLines;
        lineNo: bodyLines[i;0];
        / A one-character source line (a lone `}`) is a char ATOM, not a string.
        txt: (), bodyLines[i;1];
        j: 0;
        while[j < count txt;
            c: txt j;
            $[inStr;
                $[esc; esc: 0b; c = "\\"; esc: 1b; c = "\""; inStr: 0b; ::];
              c = "\"";
                [ inStr: 1b;
                  if[atStart and depth in stmtDepths;
                      starts,: enlist (lineNo; j); atStart: 0b] ];
              (c = "/") and ((j = 0) or txt[j-1] in " \t");
                j: count txt;
              c in "{([";
                [ if[atStart and depth in stmtDepths; starts,: enlist (lineNo; j); atStart: 0b];
                  depth+: 1;
                  / `if`/`do`/`while` open a statement list; anything else does not.
                  if[(c = "[") and word in ("if"; "do"; "while");
                      stmtDepths,: depth];
                  word: "" ];
              c in "})]";
                [ stmtDepths: stmtDepths except depth;
                  depth-: 1; if[depth < 0; depth: 0];
                  word: "" ];
              (c = ";") and depth in stmtDepths;
                [ atStart: 1b; word: "" ];
              c in " \t";
                word: "";
                [ if[atStart and depth in stmtDepths; starts,: enlist (lineNo; j); atStart: 0b];
                  word: $[c in .Q.a, .Q.A; word, c; ""] ]];
            j+: 1];
        i+: 1];
    distinct starts
 };

/ Backwards-compatible view: just the lines that begin a statement.
.tst.covStatementLines:{[bodyLines] distinct .tst.covStatementPositions[bodyLines][;0] };

/ Offset just past a lambda's opening `{` and optional `[params]`, i.e. where
/ the body begins on the definition's first line. Null when not a lambda open.
.tst.covBodyStart:{[txt]
    t: (), txt;
    b: t ? "{";
    if[b >= count t; :0N];
    k: b + 1;
    while[(k < count t) and t[k] in " \t"; k+: 1];
    if[(k < count t) and t[k] = "[";
        depth: 0;
        while[k < count t;
            $[t[k] = "["; depth+: 1; t[k] = "]"; depth-: 1; ::];
            k+: 1;
            if[depth = 0; :k]];
        :0N];
    b + 1
 };

/ Rewrite one function definition, inserting a probe at the start of every line
/ that begins a statement. Returns (newSourceText; probedLineNumbers), or `::`
/ when the shape is not one we will touch. The probed lines are returned rather
/ than recomputed later: the report must count exactly the lines that carry a
/ probe, and recomputing invites the two views drifting apart.
.tst.covRewriteFunctionForName:{[srcLines; startLine; endLine; fileSym;functionName]
    if[(startLine < 1) or endLine > count srcLines; :(::)];
    idx: (startLine - 1) + til 1 + endLine - startLine;
    seg: srcLines idx;
    firstTxt: (), first seg;
    bodyAt: .tst.covBodyStart firstTxt;
    if[null bodyAt; :(::)];

    / Parent scans mask child bodies; every anonymous lambda is then scanned on
    / its own. Sites therefore belong once to their innermost stable owner.
    statementSites:$[1b~@[get;`.tst.coverageStatements;0b];
        .tst.covStatementSitesInFunction[
            fileSym;functionName;srcLines;startLine;endLine];()];
    eligibleStatements:$[count statementSites;
        statementSites where statementSites`eligible;()];
    statementIds:$[count eligibleStatements;eligibleStatements`siteId;()];
    stmtLines:$[count eligibleStatements;
        distinct "j"$eligibleStatements`line;`long$()];
    branchSites:$[1b~@[get;`.tst.coverageBranches;0b];
        .tst.covBranchSitesInFunction[
            fileSym;functionName;srcLines;startLine;endLine];()];
    eligibleSites:branchSites where {1b~x`eligible} each branchSites;
    branchIds:$[count eligibleSites;eligibleSites`siteId;()];
    if[(0=count eligibleStatements) and 0=count eligibleSites;:(::)];

    / Site and edge identities are context-independent. Precompute them before
    / installing probes so repeated execution never normalizes a path or hashes
    / a stable ID. Legacy direct calls still populate the same caches lazily.
    if[1b~@[get;`.tst.coverageContexts;0b];
        {[fs;site].tst.ensureCoverageStatementMetric[site`siteId;fs]}[
            fileSym;] each eligibleStatements;
        {[fs;fn;site].tst.ensureCoverageBranchMetrics[
            site`siteId;fs;fn]}[fileSym;functionName;] each eligibleSites];

    / The file symbol is written as `$"..." -- a path contains slashes and a bare
    / backtick literal would not parse. Escape so any path survives embedding.
    pathTxt: string fileSym;
    pathTxt: ssr[ssr[pathTxt; "\\"; "\\\\"]; "\""; "\\\""];
    functionTxt:.tst.toString functionName;
    functionTxt:ssr[ssr[functionTxt;"\\";"\\\\"];"\"";"\\\""];
    probeFor:{[p;site]
        ".tst.covS[`",(.tst.toString site`siteId),";`$\"",p,
        "\";",string[site`line],"];"
    }[pathTxt;];
    flat:"\n" sv {(),x} each seg;
    lineOffsets:0,1+where flat="\n";
    insertAt:`long$();
    insertText:();
    if[count eligibleStatements;
        insertAt,:"j"$eligibleStatements`rewriteAt;
        insertText,:{[probe;sites;index]probe[sites index]}[
            probeFor;eligibleStatements;] each til count eligibleStatements];
    if[count eligibleSites;
        insertAt,:"j"${x`rewriteStart} each eligibleSites;
        insertText,:{[p;fn;site]
            ".tst.covC[`",(.tst.toString site`siteId),";`$\"",p,
                "\";`$\"",fn,"\";"}[pathTxt;functionTxt;] each eligibleSites;
        insertAt,:"j"${x`rewriteEnd} each eligibleSites;
        / A one-character q literal is a char atom. Double-enlist it so each
        / site contributes one independent one-character STRING; otherwise
        / `n#enlist "]"` becomes the single string "]]..." and all closers
        / land at one offset.
        insertText,:count[eligibleSites]#enlist enlist "]"];
    order:idesc insertAt;
    newFlat:flat;
    i:0;
    while[i<count order;
        at:insertAt order i;
        insertion:insertText order i;
        newFlat:(at#newFlat),insertion,at _ newFlat;
        i+:1];
    (newFlat;stmtLines;branchIds;statementIds)
 };

/ Backward-compatible low-level statement-rewriter view used by existing
/ extension tests. Production instrumentation supplies the actual function
/ identity through covRewriteFunctionForName.
.tst.covRewriteFunction:{[srcLines;startLine;endLine;fileSym]
    statementMode:1b~@[get;`.tst.coverageStatements;0b];
    branchMode:1b~@[get;`.tst.coverageBranches;0b];
    / This exported low-level helper predates the runtime feature flags and its
    / contract is specifically "show the statement rewrite". Keep it pure and
    / deterministic even when a surrounding run enabled branch coverage.
    .tst.coverageStatements:1b;
    .tst.coverageBranches:0b;
    rw:@[{[a].tst.covRewriteFunctionForName[a 0;a 1;a 2;a 3;`anonymous]};
        (srcLines;startLine;endLine;fileSym);{[e](::)}];
    .tst.coverageStatements:statementMode;
    .tst.coverageBranches:branchMode;
    $[(::)~rw;(::);(rw 0;rw 1)]
 };

/ Recursively capture the binding surface of a named lambda and every lambda
/ constant compiled inside it. Probe helpers and q's compiler namespace marker
/ are normalized away at each level; user globals inside an anonymous lambda
/ are not. This makes the atomic rollback check cover nested bindings too.
.tst.covNestedBindingShapesAt:{[item;depth]
    itemType:type item;
    if[100h=itemType;:enlist .tst.covBindingShapeAt[item;depth]];
    if[0h=itemType;
        shapes:();
        i:0;
        while[i<count item;
            shapes,:.tst.covNestedBindingShapesAt[item i;depth];
            i+:1];
        :shapes];
    ()
 };

.tst.covBindingShapeAt:{[fn;depth]
    if[depth>64;:(`depth_limit;())];
    v:value fn;
    header:1 3 sublist v;
    globals:header 2;
    globals:globals except `.tst.covL`.tst.covS`.tst.covC;
    if[count globals;globals:1 _ globals];
    header[2]:globals;
    nested:();
    i:4;
    while[i<count v;
        nested,:.tst.covNestedBindingShapesAt[v i;depth+1];
        i+:1];
    (header;nested)
 };

.tst.covBindingShape:{[fn].tst.covBindingShapeAt[fn;0]};

/ Apply the rewrite to one function and prove it survived, or put the original
/ back. Returns 1b only when the instrumented definition is in place AND still
/ looks like the same function.
.tst.covInstrumentStatements:{[name; fileSym; srcLines; startLine; endLine]
    orig: .tst.safeValue name;
    if[not (type orig) within 100 104h; :0b];
    / q exposes a lambda's structure: [1] parameters, [2] locals, [3] the globals
    / it references. Comparing those before and after is a far stronger check
    / than "it still parses" -- a probe inserted somewhere that changes how a
    / name binds shows up as a different local or global set.
    origShape:.tst.covBindingShape orig;

    rw: @[.tst.covRewriteFunctionForName[
        srcLines;startLine;endLine;fileSym;];name;{[e](::)}];
    if[(::) ~ rw; :0b];
    if[not 4 = count rw; :0b];
    newSrc: rw 0;
    probedLines: rw 1;
    branchIds:rw 2;
    statementIds:rw 3;
    if[not 10h = type newSrc; :0b];

    / The rewritten text already carries the definition verbatim, including the
    / name exactly as the source wrote it. Evaluate it in the same context the
    / file used, so unqualified references inside the body resolve as before:
    / a source that wrote `.calc.f:{...}` is evaluated at root; one that wrote
    / `f:{...}` under a `\d .calc` is evaluated with that namespace current.
    srcName: trim (newSrc ? ":") # newSrc;
    nm: string name;
    dotAt: (count nm) - (reverse nm) ? ".";
    ns: $[dotAt > 1; dotAt - 1; 0] # nm;
    evalNs: $[(0 < count srcName) and "." = first srcName; ""; ns];
    prevCtx: system "d";

    ok: @[{[a]
        if[count a 0; system "d ", a 0];
        value a 1;
        1b
      }; (evalNs; newSrc); {[e] 0b}];
    system "d ", string prevCtx;

    if[not ok; .tst.safeSet[name; orig]; :0b];

    / Same shape? A rewrite that parsed but changed the function's parameters,
    / locals, or which globals it binds has changed the function. Refuse it.
    now: .tst.safeValue name;
    if[not (type now) within 100 104h; .tst.safeSet[name; orig]; :0b];
    newShape:.tst.covBindingShape now;
    if[not origShape ~ newShape; .tst.safeSet[name; orig]; :0b];

    / Remember which lines carry a probe, so the report counts exactly those.
    if[1b~@[get;`.tst.coverageStatements;0b];
        pl:$[fileSym in key .tst.stmtProbeLines;
            .tst.stmtProbeLines fileSym;`long$()];
        .tst.stmtProbeLines[fileSym]:asc distinct pl,"j"$probedLines;
        si:$[fileSym in key .tst.statementSiteInstrumented;
            .tst.statementSiteInstrumented fileSym;()];
        .tst.statementSiteInstrumented[fileSym]:distinct si,statementIds];
    if[1b~@[get;`.tst.coverageBranches;0b];
        bi:$[fileSym in key .tst.branchInstrumented;
            .tst.branchInstrumented fileSym;()];
        .tst.branchInstrumented[fileSym]:distinct bi,branchIds];
    1b
 };

/ Aggregate the standard LCOV summary records emitted below. Keeping the gate
/ based on the artifact itself guarantees that the percentage printed to users
/ is exactly what downstream coverage services will calculate.
.tst.lcovTotal:{[lines;prefix]
    matches: lines where lines like prefix,"*";
    if[0 = count matches; :0j];
    sum "J"$ {[n;line] n _ line}[count prefix;] each matches
 };

.tst.coverageSummaryFromLines:{[lines]
    linesFound: .tst.lcovTotal[lines;"LF:"];
    linesHit: .tst.lcovTotal[lines;"LH:"];
    functionsFound: .tst.lcovTotal[lines;"FNF:"];
    functionsHit: .tst.lcovTotal[lines;"FNH:"];
    branchesFound: .tst.lcovTotal[lines;"BRF:"];
    branchesHit: .tst.lcovTotal[lines;"BRH:"];
    linePercent: $[0 = linesFound; 0f; 100f * linesHit % linesFound];
    functionPercent: $[0 = functionsFound; 0f; 100f * functionsHit % functionsFound];
    branchPercent: $[0 = branchesFound; 0f; 100f * branchesHit % branchesFound];
    `linesFound`linesHit`linePercent`functionsFound`functionsHit`functionPercent`branchesFound`branchesHit`branchPercent!(
        linesFound;linesHit;linePercent;functionsFound;functionsHit;functionPercent;
        branchesFound;branchesHit;branchPercent)
 };

/ ---------------------------------------------------------------------------
/ Canonical coverage model and renderers.
/ Every artifact below consumes this one immutable snapshot. This prevents an
/ LCOV denominator, JSON total, HTML table, or state dump from independently
/ rediscovering the source and silently disagreeing with another artifact.
/ ---------------------------------------------------------------------------

.tst.coverageStatementModel:{[hitMap;lineNo]
    hits:$[lineNo in key hitMap;"j"$hitMap lineNo;0j];
    `line`hits`covered!("j"$lineNo;hits;hits>0)
 };

.tst.coverageStatementSiteModel:{[fileSym;site]
    siteId:site`siteId;
    siteKey:`$.tst.toString siteId;
    eligible:1b~site`eligible;
    instrumentedIds:$[fileSym in key .tst.statementSiteInstrumented;
        .tst.statementSiteInstrumented fileSym;()];
    instrumented:eligible and any siteId~/:instrumentedIds;
    hits:$[siteKey in key .tst.statementCoverageData;
        "j"$.tst.statementCoverageData siteKey;0j];
    mode:1b~@[get;`.tst.coverageStatements;0b];
    fallback:$[not mode;"statement_mode_disabled";
        not eligible;site`fallbackReason;
        not (fileSym in .tst.coverageLoadedFiles);"source_not_loaded";
        instrumented;"none";
        "rewrite_rejected"];
    `siteId`function`line`column`lambdaId`lambdaDepth`anonymous`eligible`instrumented`fallbackReason`hits`covered!(
        siteId;site`function;"j"$site`line;"j"$site`column;site`lambdaId;
        "j"$site`lambdaDepth;site`anonymous;eligible;instrumented;fallback;
        hits;hits>0)
 };

.tst.coverageBranchSiteModel:{[fileSym;block;site]
    siteId:site`siteId;
    siteKey:`$.tst.toString siteId;
    eligible:1b~site`eligible;
    instrumentedIds:$[fileSym in key .tst.branchInstrumented;
        .tst.branchInstrumented fileSym;()];
    / Site ids are char vectors. Plain `in` would test every character and
    / return a boolean vector; compare each complete id for one scalar verdict.
    instrumented:eligible and any siteId~/:instrumentedIds;
    hits:$[siteKey in key .tst.branchCoverageData;
        "j"$.tst.branchCoverageData siteKey;0 0j];
    if[2>count hits;hits:2#hits,0 0j];
    hits:2#hits;
    labels:("true";"false");
    edges:{[id;allLabels;allHits;index]
        label:allLabels index;
        hit:allHits index;
        `edgeId`index`label`hits`covered!(
            "edge_",.tst.stableHashText[id,"\n",label];"j"$index;label;
            "j"$hit;hit>0)
      }[siteId;labels;hits;] each 0 1j;
    mode:1b~@[get;`.tst.coverageBranches;0b];
    fallback:$[not mode;"branch_mode_disabled";
        not eligible;site`fallbackReason;
        not (fileSym in .tst.coverageLoadedFiles);"source_not_loaded";
        instrumented;"none";
        "rewrite_rejected"];
    `siteId`function`kind`conditionIndex`line`column`lambdaId`lambdaDepth`anonymous`block`eligible`instrumented`fallbackReason`edgesFound`edgesHit`edges!(
        siteId;site`function;site`kind;"j"$site`conditionIndex;
        "j"$site`line;"j"$site`column;site`lambdaId;"j"$site`lambdaDepth;
        site`anonymous;"j"$block;eligible;instrumented;
        fallback;2j;"j"$sum {x`covered} each edges;edges)
 };

.tst.coverageFunctionModel:{[fileSym;fData;srcLines;nsAt;starts;statementSiteRows;branchRows;row]
    nm:.tst.coverageQualifyName[nsAt;row`line;row`name];
    hits:$[nm in key fData;"j"$fData nm;0j];
    measuredNames:$[fileSym in key .tst.stmtInstrumented;
        .tst.stmtInstrumented fileSym;`symbol$()];
    measured:nm in measuredNames;
    span:.tst.covFunctionSpan[srcLines;row`line;starts];
    probes:$[fileSym in key .tst.stmtProbeLines;
        .tst.stmtProbeLines fileSym;`long$()];
    inSpan:$[measured and span[1]>=span[0];
        probes where probes within (span 0;span 1);`long$()];
    hitMap:$[fileSym in key .tst.lineCoverageData;
        .tst.lineCoverageData fileSym;(`long$())!`long$()];
    statements:.tst.coverageStatementModel[hitMap;] each inSpan;
    statementHits:sum 0,{x`covered} each statements;
    reason:.tst.coverageFallbackReason[fileSym;nm];
    fnName:.tst._covNameStr nm;
    fnStatementSites:$[count statementSiteRows;
        statementSiteRows where fnName~/:statementSiteRows`function;()];
    fnBranches:$[count branchRows;
        branchRows where fnName~/:branchRows`function;()];
    eligibleBranches:$[count fnBranches;
        fnBranches where fnBranches`eligible;()];
    `name`line`hits`covered`functionEligible`functionInstrumented`statementEligible`statementInstrumented`fallbackReason`statementFound`statementHit`statements`statementSitesFound`statementSitesHit`statementSitesInstrumented`statementSites`branchSitesEligible`branchSitesInstrumented`branchFound`branchHit`branches!(
        fnName;"j"$row`line;hits;hits>0;1b;
        nm in key .tst.covWrappers;1b;measured;string reason;
        count statements;statementHits;statements;
        count fnStatementSites;sum 0,$[count fnStatementSites;
            fnStatementSites`covered;`boolean$()];
        sum 0,$[count fnStatementSites;
            fnStatementSites`instrumented;`boolean$()];fnStatementSites;
        count eligibleBranches;sum 0,$[count eligibleBranches;
            eligibleBranches`instrumented;`boolean$()];
        sum 0,$[count eligibleBranches;eligibleBranches`edgesFound;`long$()];
        sum 0,$[count eligibleBranches;eligibleBranches`edgesHit;`long$()];fnBranches)
 };

.tst.coverageFileModel:{[fileSym]
    path:string fileSym;
    if[path like ":*";path:1 _ path];
    fHandle:hsym (`$":" , path);
    staticFns:@[.tst.static.exploreFile;fHandle;{([] name:`$();line:`int$())}];
    if[not 98h=type staticFns;staticFns:([] name:`$();line:`int$())];
    srcLines:@[read0;fHandle;{()}];
    nsAt:.tst.coverageSysDNamespaces srcLines;
    starts:"j"$$[`line in cols staticFns;staticFns`line;`long$()];
    starts:starts where not null starts;
    fData:.tst.coverageData fileSym;
    rawStatementSites:();rawBranches:();
    i:0;
    while[i<count staticFns;
        row:staticFns i;
        nm:.tst.coverageQualifyName[nsAt;row`line;row`name];
        span:.tst.covFunctionSpan[srcLines;row`line;starts];
        if[span[1]>=span 0;
            rawStatementSites,:.tst.covStatementSitesInFunction[
                fileSym;nm;srcLines;span 0;span 1];
            rawBranches,:.tst.covBranchSitesInFunction[
                fileSym;nm;srcLines;span 0;span 1]];
        i+:1];
    statementSiteRows:();
    i:0;
    while[i<count rawStatementSites;
        statementSiteRows,:enlist .tst.coverageStatementSiteModel[
            fileSym;rawStatementSites i];
        i+:1];
    branchRows:();
    i:0;
    while[i<count rawBranches;
        branchRows,:enlist .tst.coverageBranchSiteModel[fileSym;i;rawBranches i];
        i+:1];
    fnRows:.tst.coverageFunctionModel[
        fileSym;fData;srcLines;nsAt;starts;statementSiteRows;branchRows;] each staticFns;
    lineRows:raze {x`statements} each fnRows;
    functionHit:sum 0,{x`covered} each fnRows;
    lineHit:sum 0,{x`covered} each lineRows;
    measuredFns:sum 0,{x`statementInstrumented} each fnRows;
    eligibleStatementSites:$[count statementSiteRows;
        statementSiteRows where statementSiteRows`eligible;()];
    eligibleBranches:$[count branchRows;
        branchRows where branchRows`eligible;()];
    `path`loaded`functionFound`functionHit`statementFunctionsInstrumented`lineFound`lineHit`statementSitesEligible`statementSitesInstrumented`statementSitesHit`branchSitesEligible`branchSitesInstrumented`branchFound`branchHit`functions`lines`statementSites`branches`sourceLines!(
        path;fileSym in .tst.coverageLoadedFiles;count fnRows;functionHit;
        measuredFns;count lineRows;lineHit;count eligibleStatementSites;
        sum 0,$[count eligibleStatementSites;
            eligibleStatementSites`instrumented;`boolean$()];
        sum 0,$[count eligibleStatementSites;
            eligibleStatementSites`covered;`boolean$()];count eligibleBranches;
        sum 0,$[count eligibleBranches;eligibleBranches`instrumented;`boolean$()];
        sum 0,$[count eligibleBranches;eligibleBranches`edgesFound;`long$()];
        sum 0,$[count eligibleBranches;eligibleBranches`edgesHit;`long$()];
        fnRows;lineRows;statementSiteRows;branchRows;srcLines)
 };

.tst.coverageContextMetricRowsFrom:{[entryIds;metricMetadata;metricHits]
    rows:();
    i:0;
    while[i<count entryIds;
        entryId:entryIds i;
        metadata:metricMetadata entryId;
        rows,:enlist metadata,enlist[`hits]!enlist
            "j"$metricHits entryId;
        i+:1];
    if[count rows;
        order:iasc {.tst.toString x`metricId} each rows;
        rows:rows order];
    rows
 };

.tst.coverageContextRowsFrom:{[registry;metricMetadata;metricHits]
    rows:();
    ids:key registry;
    if[count ids;ids:ids iasc string each ids];
    / Index the flat entry map once. The prior implementation scanned every
    / metric once for every context, making report cost O(contexts*entries).
    entriesByContext:()!();
    entryIds:key metricMetadata;
    i:0;
    while[i<count entryIds;
        entryId:entryIds i;
        metadata:metricMetadata entryId;
        contextText:.tst.toString metadata`contextId;
        contextKey:`$contextText;
        contextEntries:$[contextKey in key entriesByContext;
            entriesByContext contextKey;`symbol$()];
        entriesByContext[contextKey]:contextEntries,entryId;
        i+:1];
    i:0;
    while[i<count ids;
        metadata:registry ids i;
        contextText:.tst.toString metadata`contextId;
        contextKey:`$contextText;
        contextEntries:$[contextKey in key entriesByContext;
            entriesByContext contextKey;`symbol$()];
        metrics:.tst.coverageContextMetricRowsFrom[
            contextEntries;metricMetadata;metricHits];
        rows,:enlist metadata,enlist[`metrics]!enlist metrics;
        i+:1];
    rows
 };

.tst.coverageContextDocument:{[state]
    enabled:1b~state`enabled;
    attemptDetail:enabled and 1b~state`attemptDetail;
    registry:state`registry;
    metricMetadata:state`metricMetadata;
    metricHits:state`metricHits;
    contexts:$[enabled;.tst.coverageContextRowsFrom[
        registry;metricMetadata;metricHits];()];
    metrics:$[count contexts;raze {x`metrics} each contexts;()];
    kinds:$[count metrics;{`$.tst.toString x`kind} each metrics;`symbol$()];
    hits:$[count metrics;"j"${x`hits} each metrics;`long$()];
    unattributedHits:0j;
    if[count contexts;
        unattributed:where {"unattributed"~.tst.toString x`contextId} each contexts;
        if[count unattributed;
            unattributedHits:sum 0j,"j"${x`hits} each
                (contexts first unattributed)`metrics]];
    normalIds:(key registry) except
        .tst.coverageContextReserved;
    summary:`contextsStored`metricEntriesStored`functionHits`statementHits`branchHits`unattributedHits`overflowActivations`droppedMetricHits`truncated!(
        "j"$count normalIds;"j"$count metricHits;
        sum 0j,hits where kinds=`function;
        sum 0j,hits where kinds=`statement;
        sum 0j,hits where kinds=`branch;
        unattributedHits;"j"$state`overflowActivations;
        "j"$state`droppedMetricHits;
        (0<state`overflowActivations) or 0<state`droppedMetricHits);
    `schemaVersion`enabled`detail`contextLimit`entryLimit`summary`contexts!(
        1j;enabled;$[attemptDetail;"attempt";"test"];
        "j"$state`contextLimit;"j"$state`entryLimit;
        summary;contexts)
 };

.tst.coverageContextModel:{[]
    .tst.coverageContextDocument
        `enabled`attemptDetail`contextLimit`entryLimit`overflowActivations`droppedMetricHits`registry`metricMetadata`metricHits!(
            1b~@[get;`.tst.coverageContexts;0b];
            1b~@[get;`.tst.coverageAttemptContexts;0b];
            "j"$@[get;`.tst.coverageContextMax;10000j];
            "j"$@[get;`.tst.coverageContextEntryMax;250000j];
            "j"$.tst.coverageContextOverflowActivations;
            "j"$.tst.coverageContextDroppedHits;
            .tst.coverageContextRegistry;.tst.coverageContextMetricMeta;
            .tst.coverageContextMetricHits)
 };

.tst.coverageCollectionCount:{[items]
    $[(::)~items;0j;99h=type items;1j;"j"$count items]
 };

.tst.coverageCollectionAt:{[items;index]
    $[99h=type items;items;items index]
 };

/ Deterministically merge context documents from workers or shards. Stable IDs
/ are the join keys, duplicate metrics are summed, and limits are applied after
/ lexical sorting so input arrival order cannot decide which data survives.
.tst.mergeCoverageContexts:{[measurements]
    n:.tst.coverageCollectionCount measurements;
    if[0=n;:.tst.coverageContextDocument
        `enabled`attemptDetail`contextLimit`entryLimit`overflowActivations`droppedMetricHits`registry`metricMetadata`metricHits!(
            0b;0b;10000j;250000j;0j;0j;()!();()!();(`symbol$())!`long$())];
    firstMeasurement:.tst.coverageCollectionAt[measurements;0];
    if[not 99h=type firstMeasurement;'"coverage context merge expects dictionaries"];
    enabled:1b~firstMeasurement`enabled;
    detail:.tst.toString firstMeasurement`detail;
    contextLimit:1j|"j"$firstMeasurement`contextLimit;
    entryLimit:1j|"j"$firstMeasurement`entryLimit;
    allRegistry:()!();
    inputOverflow:0j;
    inputDropped:0j;
    i:0;
    while[i<n;
        measurement:.tst.coverageCollectionAt[measurements;i];
        if[not 99h=type measurement;
            '"coverage context merge expects dictionaries"];
        if[not enabled~1b~measurement`enabled;
            '"cannot merge enabled and disabled coverage contexts"];
        if[not detail~.tst.toString measurement`detail;
            '"cannot merge test-detail and attempt-detail coverage contexts"];
        contextLimit:min contextLimit,1j|"j"$measurement`contextLimit;
        entryLimit:min entryLimit,1j|"j"$measurement`entryLimit;
        inputSummary:$[`summary in key measurement;measurement`summary;()!()];
        if[99h=type inputSummary;
            if[`overflowActivations in key inputSummary;
                inputOverflow+:"j"$inputSummary`overflowActivations];
            if[`droppedMetricHits in key inputSummary;
                inputDropped+:"j"$inputSummary`droppedMetricHits]];
        ctxRows:$[`contexts in key measurement;measurement`contexts;()];
        j:0;
        while[j<.tst.coverageCollectionCount ctxRows;
            ctxRow:.tst.coverageCollectionAt[ctxRows;j];
            contextId:`$.tst.toString ctxRow`contextId;
            metadataKeys:(key ctxRow) except `metrics;
            metadata:metadataKeys!ctxRow metadataKeys;
            if[contextId in key allRegistry;
                if[not metadata~allRegistry contextId;
                    '"coverage context metadata conflict for ",string contextId]];
            if[not contextId in key allRegistry;
                allRegistry[contextId]:metadata];
            j+:1];
        i+:1];
    normalIds:(key allRegistry) except .tst.coverageContextReserved;
    if[count normalIds;normalIds:normalIds iasc string each normalIds];
    keepIds:(contextLimit & count normalIds)#normalIds;
    collapsedIds:normalIds except keepIds;
    reservedIds:.tst.coverageContextReserved where
        .tst.coverageContextReserved in key allRegistry;
    registry:(keepIds,reservedIds)#allRegistry;
    if[count collapsedIds;
        if[not `overflow in key registry;
            registry[`overflow]:.tst.coverageContextMeta[
                "overflow";"overflow";"";0j;"";
                "contexts beyond the configured limit";""]]];

    metricMetadata:()!();
    metricHits:(`symbol$())!`long$();
    i:0;
    while[i<n;
        measurement:.tst.coverageCollectionAt[measurements;i];
        ctxRows:$[`contexts in key measurement;measurement`contexts;()];
        j:0;
        while[j<.tst.coverageCollectionCount ctxRows;
            ctxRow:.tst.coverageCollectionAt[ctxRows;j];
            sourceId:`$.tst.toString ctxRow`contextId;
            targetId:$[sourceId in collapsedIds;`overflow;sourceId];
            metricRows:$[`metrics in key ctxRow;ctxRow`metrics;()];
            k:0;
            while[k<.tst.coverageCollectionCount metricRows;
                metricRow:.tst.coverageCollectionAt[metricRows;k];
                metricId:.tst.toString metricRow`metricId;
                entryKey:`$"merge_",.tst.stableHashText[
                    string[targetId],"\n",metricId];
                metricKeys:(key metricRow) except `hits;
                metricMetadataRow:metricKeys!metricRow metricKeys;
                metricMetadataRow[`contextId]:.tst.toString targetId;
                if[entryKey in key metricMetadata;
                    existing:metricMetadata entryKey;
                    if[not existing~metricMetadataRow;
                        '"coverage metric metadata conflict for ",metricId]];
                if[not entryKey in key metricMetadata;
                    metricMetadata[entryKey]:metricMetadataRow;
                    metricHits[entryKey]:0j];
                metricHits[entryKey]+:"j"$metricRow`hits;
                k+:1];
            j+:1];
        i+:1];
    entryKeys:key metricMetadata;
    if[count entryKeys;
        entryOrder:iasc {[allMetadata;entryId]
            row:allMetadata entryId;
            (.tst.toString row`contextId),"\n",
                .tst.toString row`metricId
          }[metricMetadata;] each entryKeys;
        entryKeys:entryKeys entryOrder];
    keptEntryKeys:(entryLimit & count entryKeys)#entryKeys;
    droppedEntryKeys:entryKeys except keptEntryKeys;
    droppedMetricHits:inputDropped+sum 0j,$[count droppedEntryKeys;
        "j"$metricHits droppedEntryKeys;`long$()];
    metricMetadata:keptEntryKeys#metricMetadata;
    metricHits:keptEntryKeys#metricHits;
    .tst.coverageContextDocument
        `enabled`attemptDetail`contextLimit`entryLimit`overflowActivations`droppedMetricHits`registry`metricMetadata`metricHits!(
            enabled;"attempt"~detail;contextLimit;entryLimit;
            inputOverflow+count collapsedIds;droppedMetricHits;
            registry;metricMetadata;metricHits)
 };

.tst.coverageModel:{[]
    fileRows:.tst.coverageFileModel each key .tst.coverageData;
    fnFound:sum 0,{x`functionFound} each fileRows;
    fnHit:sum 0,{x`functionHit} each fileRows;
    lineFound:sum 0,{x`lineFound} each fileRows;
    lineHit:sum 0,{x`lineHit} each fileRows;
    statementSitesEligible:sum 0,{x`statementSitesEligible} each fileRows;
    statementSitesInstrumented:sum 0,{x`statementSitesInstrumented} each fileRows;
    statementSitesHit:sum 0,{x`statementSitesHit} each fileRows;
    branchSitesEligible:sum 0,{x`branchSitesEligible} each fileRows;
    branchSitesInstrumented:sum 0,{x`branchSitesInstrumented} each fileRows;
    branchFound:sum 0,{x`branchFound} each fileRows;
    branchHit:sum 0,{x`branchHit} each fileRows;
    branchMode:1b~@[get;`.tst.coverageBranches;0b];
    statementMode:1b~@[get;`.tst.coverageStatements;0b];
    base:`linesFound`linesHit`linePercent`functionsFound`functionsHit`functionPercent`statementSitesFound`statementSitesHit`statementSitePercent`statementSitesInstrumented`statementSiteInstrumentationPercent`statementSiteInstrumentationComplete`branchesFound`branchesHit`branchPercent`branchMode`branchSitesEligible`branchSitesInstrumented`branchInstrumentationPercent`branchInstrumentationComplete!(
        lineFound;lineHit;$[0=lineFound;0f;100f*lineHit%lineFound];
        fnFound;fnHit;$[0=fnFound;0f;100f*fnHit%fnFound];
        statementSitesEligible;statementSitesHit;
        $[0=statementSitesEligible;0f;100f*statementSitesHit%statementSitesEligible];
        statementSitesInstrumented;
        $[0=statementSitesEligible;0f;100f*statementSitesInstrumented%statementSitesEligible];
        statementMode and 0<statementSitesEligible and
            statementSitesEligible=statementSitesInstrumented;
        branchFound;branchHit;$[0=branchFound;0f;100f*branchHit%branchFound];
        branchMode;branchSitesEligible;branchSitesInstrumented;
        $[0=branchSitesEligible;0f;100f*branchSitesInstrumented%branchSitesEligible];
        branchMode and 0<branchSitesEligible and branchSitesEligible=branchSitesInstrumented);
    instrumentation:.tst.coverageInstrumentationSummary[];
    parseSummary:`sourceParseComplete`sourceParseDiagnostics!(
        not .tst.coverageParseFailed;.tst.coverageParseDiagnostics);
    `summary`files`contextMeasurement!(
        base,instrumentation,parseSummary;fileRows;.tst.coverageContextModel[])
 };

.tst.coveragePublicFile:{[fileRow]
    publicKeys:(key fileRow) except `sourceLines;
    public:publicKeys!fileRow publicKeys;
    public[`path]:.tst.repoRelativePath public`path;
    public
 };

.tst.coveragePublicModel:{[model]
    `summary`files`contextMeasurement!(
        model`summary;.tst.coveragePublicFile each model`files;
        $[`contextMeasurement in key model;model`contextMeasurement;
            .tst.coverageContextModel[]])
 };

.tst.coverageStateLines:{[model]
    lines:("# resQ coverage state v5";
        "# F path function hits functionInstrumented statementInstrumented fallback";
        "# S path siteId function line column lambdaId lambdaDepth anonymous eligible instrumented hits fallback";
        "# B path siteId function kind conditionIndex line column lambdaId lambdaDepth anonymous eligible instrumented fallback";
        "# E siteId edgeId index label hits covered";
        "# C contextId kind testId attempt file";
        "# M contextId metricId kind file function siteId edgeIndex edgeLabel hits");
    fileRows:model`files;
    i:0;
    do[count fileRows;
        fileRow:fileRows i;
        filePath:.tst.repoRelativePath fileRow`path;
        funcs:fileRow`functions;
        j:0;
        do[count funcs;
            fn:funcs j;
            lines,:enlist " " sv (enlist "F";filePath;fn`name;string[fn`hits];
                string[fn`functionInstrumented];
                string[fn`statementInstrumented];fn`fallbackReason);
            j+:1];
        statementSites:fileRow`statementSites;
        j:0;
        do[count statementSites;
            site:statementSites j;
            lambdaText:$[count site`lambdaId;site`lambdaId;enlist "-"];
            lines,:enlist " " sv (enlist "S";filePath;site`siteId;
                site`function;string[site`line];string[site`column];lambdaText;
                string[site`lambdaDepth];string[site`anonymous];
                string[site`eligible];string[site`instrumented];
                string[site`hits];site`fallbackReason);
            j+:1];
        branches:fileRow`branches;
        j:0;
        do[count branches;
            site:branches j;
            lambdaText:$[count site`lambdaId;site`lambdaId;enlist "-"];
            lines,:enlist " " sv (enlist "B";filePath;site`siteId;site`function;
                site`kind;string[site`conditionIndex];string[site`line];
                string[site`column];lambdaText;string[site`lambdaDepth];
                string[site`anonymous];string[site`eligible];
                string[site`instrumented];site`fallbackReason);
            edges:site`edges;
            k:0;
            do[count edges;
                edge:edges k;
                lines,:enlist " " sv (enlist "E";site`siteId;edge`edgeId;
                    string[edge`index];edge`label;string[edge`hits];
                    string[edge`covered]);
                k+:1];
            j+:1];
        i+:1];
    contextMeasurement:$[`contextMeasurement in key model;
        model`contextMeasurement;.tst.coverageContextModel[]];
    if[1b~contextMeasurement`enabled;
        contexts:contextMeasurement`contexts;
        i:0;
        while[i<count contexts;
            ctx:contexts i;
            stateText:{[v]
                s:.tst.toString v;
                if[0=count s;:enlist "-"];
                $[-10h=type s;enlist s;s]
            };
            lines,:enlist " " sv (enlist "C";stateText ctx`contextId;
                stateText ctx`kind;stateText ctx`testId;
                stateText ctx`attempt;stateText ctx`file);
            metrics:ctx`metrics;
            j:0;
            while[j<count metrics;
                metric:metrics j;
                lines,:enlist " " sv (enlist "M";
                    stateText ctx`contextId;stateText metric`metricId;
                    stateText metric`kind;stateText metric`file;
                    stateText metric`function;stateText metric`siteId;
                    stateText metric`edgeIndex;stateText metric`edgeLabel;
                    stateText metric`hits);
                j+:1];
            i+:1]];
    lines
 };

.tst.writeCoverageState:{[model;outPath]
    idx:(count outPath)-(reverse outPath)?"/";
    dir:$[idx=0;".";idx#outPath];
    (hsym `$dir,"/coverage_state.txt") 0:.tst.coverageStateLines model;
    ::
 };

.tst.generateLCOV:{[outFile]
    if[not .tst.coverageEnabled;'"Coverage not enabled"];
    outPath:.tst.resolvePath outFile;
    model:.tst.coverageModel[];
    .tst.lastCoverageModel:model;
    txt:"TN:resq\n";
    fileRows:model`files;
    i:0;
    do[count fileRows;
        fileRow:fileRows i;
        filePath:.tst.repoRelativePath fileRow`path;
        txt,:"SF:",filePath,"\n";
        funcs:fileRow`functions;
        j:0;
        do[count funcs;
            fn:funcs j;
            fnName:fn`name;
            txt,:"FN:",string[fn`line],",",fnName,"\n";
            txt,:"FNDA:",string[fn`hits],",",fnName,"\n";
            j+:1];
        lineRows:fileRow`lines;
        j:0;
        do[count lineRows;
            ln:lineRows j;
            txt,:"DA:",string[ln`line],",",string[ln`hits],"\n";
            j+:1];
        if[count lineRows;
            txt,:"LF:",string[fileRow`lineFound],"\n";
            txt,:"LH:",string[fileRow`lineHit],"\n"];
        if[1b~model[`summary;`branchMode];
            branches:fileRow`branches;
            branches:branches where {1b~x`eligible} each branches;
            j:0;
            do[count branches;
                site:branches j;
                edges:site`edges;
                siteHits:sum 0j,"j"${x`hits} each edges;
                k:0;
                do[count edges;
                    edge:edges k;
                    txt,:"BRDA:",string[site`line],",",string[site`block],",",
                        string[edge`index],",",
                        $[0j=siteHits;"-";string edge`hits],"\n";
                    k+:1];
                j+:1];
            txt,:"BRF:",string[fileRow`branchFound],"\n";
            txt,:"BRH:",string[fileRow`branchHit],"\n"];
        txt,:"FNF:",string[fileRow`functionFound],"\n";
        txt,:"FNH:",string[fileRow`functionHit],"\nend_of_record\n";
        i+:1];
    .tst.writeCoverageState[model;outPath];
    .tst.lastCoverageSummary:model`summary;
    (hsym (`$":" , outPath)) 0:enlist txt;
    -1 "LCOV report written to: ",outPath;
    if[0=count fileRows;
        -1 "WARNING: coverage instrumented 0 functions - this report is empty.";
        -1 "         Declare the source inventory with --source src/.";
    ];
    outPath
 };

.tst.generateCoverageJSON:{[outFile]
    if[not .tst.coverageEnabled;'"Coverage not enabled"];
    outPath:.tst.resolvePath outFile;
    model:$[(99h=type .tst.lastCoverageModel) and `files in key .tst.lastCoverageModel;
        .tst.lastCoverageModel;.tst.coverageModel[]];
    public:.tst.coveragePublicModel model;
    runMetadata:@[get;`.tst.app.runMetadata;{()!()}];
    runId:$[(99h=type runMetadata) and `id in key runMetadata;
        .tst.toString runMetadata`id;""];
    if[not runId like "run_????????????????????????????????";
        '"coverage JSON requires authoritative run identity"];
    payload:`schemaVersion`kind`framework`frameworkVersion`runId`summary`files`contextMeasurement!(
        2;"resq-coverage";"resQ";.tst.toString @[get;`.resq.VERSION;{"unknown"}];runId;
        public`summary;public`files;public`contextMeasurement);
    (hsym (`$":" , outPath)) 0:enlist .tst.output.strictJson payload;
    -1 "Coverage JSON written to: ",outPath;
    outPath
 };

.tst.coverageHtmlEscape:{[text]
    s:.tst.toString text;
    s:ssr[s;"&";"&amp;"];
    s:ssr[s;"<";"&lt;"];
    s:ssr[s;">";"&gt;"];
    s:ssr[s;"\"";"&quot;"];
    s
 };

.tst.coverageFunctionHtml:{[fn]
    cls:$[fn`covered;"covered";"uncovered"];
    "<tr class=\"",cls,"\"><td>",.tst.coverageHtmlEscape[fn`name],
    "</td><td>",string[fn`line],"</td><td>",string[fn`hits],
    "</td><td>",string[fn`functionInstrumented],"</td><td>",
    string[fn`statementHit]," / ",string[fn`statementFound],
    "</td><td>",string[fn`statementInstrumented],"</td><td>",
    string[fn`statementSitesHit]," / ",string[fn`statementSitesFound],
    "</td><td>",string[fn`statementSitesInstrumented],"</td><td>",
    string[fn`branchHit]," / ",string[fn`branchFound],"</td><td>",
    string[fn`branchSitesInstrumented]," / ",
    string[fn`branchSitesEligible],"</td><td>",
    .tst.coverageHtmlEscape[fn`fallbackReason],"</td></tr>"
 };

.tst.coverageStatementSiteHtml:{[site]
    cls:$[not site`eligible;"unmeasured";site`covered;"covered";"uncovered"];
    lambdaText:$[site`anonymous;site`lambdaId;"named function"];
    "<tr class=\"",cls,"\"><td>",.tst.coverageHtmlEscape[site`siteId],
    "</td><td>",.tst.coverageHtmlEscape[site`function],"</td><td>",
    string[site`line],":",string[site`column],"</td><td>",
    .tst.coverageHtmlEscape[lambdaText],"</td><td>",
    string[site`lambdaDepth],"</td><td>",string[site`hits],"</td><td>",
    string[site`instrumented],"</td><td>",
    .tst.coverageHtmlEscape[site`fallbackReason],"</td></tr>"
 };

.tst.coverageBranchHtml:{[site]
    eligible:1b~site`eligible;
    fullyCovered:(site`edgesHit)=site`edgesFound;
    cls:$[not eligible;"unmeasured";fullyCovered;"covered";"uncovered"];
    edgeText:", " sv {[edge]
        (edge`label),"=",string[edge`hits]
    } each site`edges;
    "<tr class=\"",cls,"\"><td>",.tst.coverageHtmlEscape[site`siteId],
    "</td><td>",.tst.coverageHtmlEscape[site`function],"</td><td>",
    .tst.coverageHtmlEscape[site`kind],"</td><td>",string[site`conditionIndex],
    "</td><td>",string[site`line],":",string[site`column],"</td><td>",
    .tst.coverageHtmlEscape[$[site`anonymous;site`lambdaId;"named function"]],
    "</td><td>",string[site`lambdaDepth],"</td><td>",edgeText,
    "</td><td>",string[site`instrumented],"</td><td>",
    .tst.coverageHtmlEscape[site`fallbackReason],"</td></tr>"
 };

.tst.coverageContextHtml:{[context]
    html:"<details><summary>",.tst.coverageHtmlEscape[context`contextId],
        " — ",.tst.coverageHtmlEscape[context`kind]," — ",
        .tst.coverageHtmlEscape[context`description],"</summary>";
    html,:"<p>testId=",.tst.coverageHtmlEscape[context`testId],
        "; attempt=",string[context`attempt],"; file=",
        .tst.coverageHtmlEscape[context`file],"</p>";
    html,:"<table><thead><tr><th>Metric</th><th>Kind</th><th>File</th><th>Function</th><th>Site</th><th>Edge</th><th>Hits</th></tr></thead><tbody>";
    metrics:context`metrics;
    i:0;
    while[i<count metrics;
        metric:metrics i;
        html,:"<tr><td>",.tst.coverageHtmlEscape[metric`metricId],
            "</td><td>",.tst.coverageHtmlEscape[metric`kind],
            "</td><td>",.tst.coverageHtmlEscape[metric`file],
            "</td><td>",.tst.coverageHtmlEscape[metric`function],
            "</td><td>",.tst.coverageHtmlEscape[metric`siteId],
            "</td><td>",.tst.coverageHtmlEscape[metric`edgeLabel],
            "</td><td>",string[metric`hits],"</td></tr>";
        i+:1];
    html,"</tbody></table></details>"
 };

.tst.coverageSourceHtml:{[fileRow]
    lineRows:fileRow`lines;
    numbers:{x`line} each lineRows;
    html:"<details><summary>Annotated source</summary><table><thead><tr><th>Line</th><th>Hits</th><th>Source</th></tr></thead><tbody>";
    i:0;
    do[count fileRow`sourceLines;
        lineNo:i+1;
        measured:lineNo in numbers;
        hits:$[measured;lineRows[numbers?lineNo]`hits;0j];
        cls:$[not measured;"unmeasured";hits>0;"covered";"uncovered"];
        hitText:$[measured;string hits;"not measured"];
        html,:"<tr class=\"",cls,"\"><td>",string[lineNo],"</td><td>",
            hitText,"</td><td><pre>",
            .tst.coverageHtmlEscape[(fileRow`sourceLines) i],"</pre></td></tr>";
        i+:1];
    html,"</tbody></table></details>"
 };

.tst.generateHTML:{[outFile]
    if[not .tst.coverageEnabled;'"Coverage not enabled"];
    outPath:.tst.resolvePath outFile;
    model:$[(99h=type .tst.lastCoverageModel) and `files in key .tst.lastCoverageModel;
        .tst.lastCoverageModel;.tst.coverageModel[]];
    s:model`summary;
    html:"<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>resQ Coverage</title>";
    html,:"<style>body{font-family:sans-serif;margin:2rem}table{border-collapse:collapse;width:100%;margin-bottom:1rem}th,td{border:1px solid #ccc;padding:.35rem;text-align:left}.covered{background:#e7f7ea}.uncovered{background:#fde8e8}.unmeasured{background:#f3f3f3;color:#666}pre{margin:0;white-space:pre-wrap}</style></head><body>";
    html,:"<h1>resQ Coverage</h1><p><strong>Functions:</strong> ",
        string[s`functionsHit]," / ",string[s`functionsFound]," (",
        string[s`functionPercent],"%)</p><p><strong>Measured statements:</strong> ",
        string[s`linesHit]," / ",string[s`linesFound]," (",string[s`linePercent],
        "%)</p><p><strong>Statement sites:</strong> ",
        string[s`statementSitesHit]," / ",string[s`statementSitesFound]," (",
        string[s`statementSitePercent],"%)</p><p><strong>Statement instrumentation completeness:</strong> ",
        string[s`statementFunctionsInstrumented]," / ",
        string[s`statementFunctionsEligible]," (",
        string[s`statementInstrumentationPercent],"%)</p><p><strong>Branches:</strong> ",
        string[s`branchesHit]," / ",string[s`branchesFound]," (",
        string[s`branchPercent],"%)</p><p><strong>Branch instrumentation completeness:</strong> ",
        string[s`branchSitesInstrumented]," / ",
        string[s`branchSitesEligible]," (",
        string[s`branchInstrumentationPercent],"%)</p>";
    fileRows:model`files;
    i:0;
    do[count fileRows;
        fileRow:fileRows i;
        html,:"<section><h2>",.tst.coverageHtmlEscape[fileRow`path],"</h2>";
        html,:"<p>",string[fileRow`functionHit]," / ",
            string[fileRow`functionFound]," functions covered; ",
            string[fileRow`lineHit]," / ",string[fileRow`lineFound],
            " measured statements covered; ",string[fileRow`branchHit]," / ",
            string[fileRow`branchFound]," branch edges covered; loaded=",
            string[fileRow`loaded],"</p>";
        html,:"<table><thead><tr><th>Function</th><th>Line</th><th>Hits</th><th>Function instrumented</th><th>Lines</th><th>Statement instrumented</th><th>Statement sites</th><th>Sites instrumented</th><th>Branches</th><th>Branch sites instrumented</th><th>Fallback</th></tr></thead><tbody>";
        html,:raze .tst.coverageFunctionHtml each fileRow`functions;
        html,:"</tbody></table>";
        if[count fileRow`statementSites;
            html,:"<details open><summary>Statement sites</summary><table><thead><tr><th>Site ID</th><th>Function</th><th>Location</th><th>Owner</th><th>Lambda depth</th><th>Hits</th><th>Instrumented</th><th>Fallback</th></tr></thead><tbody>";
            html,:raze .tst.coverageStatementSiteHtml each fileRow`statementSites;
            html,:"</tbody></table></details>"];
        if[count fileRow`branches;
            html,:"<details open><summary>Branch sites</summary><table><thead><tr><th>Site ID</th><th>Function</th><th>Kind</th><th>Condition</th><th>Location</th><th>Owner</th><th>Lambda depth</th><th>Edge hits</th><th>Instrumented</th><th>Fallback</th></tr></thead><tbody>";
            html,:raze .tst.coverageBranchHtml each fileRow`branches;
            html,:"</tbody></table></details>"];
        html,:.tst.coverageSourceHtml[fileRow],"</section>";
        i+:1];
    contextMeasurement:$[`contextMeasurement in key model;
        model`contextMeasurement;.tst.coverageContextModel[]];
    if[1b~contextMeasurement`enabled;
        cs:contextMeasurement`summary;
        html,:"<section><h2>Coverage contexts</h2><p>Detail: ",
            .tst.coverageHtmlEscape[contextMeasurement`detail],
            "; contexts stored: ",string[cs`contextsStored],
            "; metric entries: ",string[cs`metricEntriesStored],
            "; unattributed hits: ",string[cs`unattributedHits],
            "; overflow activations: ",string[cs`overflowActivations],
            "; dropped metric hits: ",string[cs`droppedMetricHits],
            "; truncated: ",string[cs`truncated],".</p>";
        html,:raze .tst.coverageContextHtml each contextMeasurement`contexts;
        html,:"</section>"];
    html,:"<p>Machine-readable detail: coverage.json. Raw state: coverage_state.txt.</p></body></html>";
    (hsym (`$":" , outPath)) 0:enlist html;
    -1 "HTML report written to: ",outPath;
    outPath
 };
