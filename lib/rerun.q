\d .tst

/ Versioned, repository-local execution history for --last-failed and
/ --failed-first. This is deliberately a cache, never an authority: missing or
/ malformed history falls back to the complete selected suite.
.tst.rerunStateVersion:1;

.tst.rerunStatePath:{[]
    configured:.tst.toString @[get;`.tst.app.stateFile;{".resq/last-run.json"}];
    base:.tst.toString @[get;`.tst.app.baseDir;{system "cd"}];
    shardCount:"j"$@[get;`.tst.app.shardCount;1j];
    shardIndex:"j"$@[get;`.tst.app.shardIndex;0j];
    if[shardCount>1;
        suffix:".shard-",string[shardIndex],"-of-",string shardCount;
        configured:$[configured like "*.json";
            ((count[configured]-5)#configured),suffix,".json";
            configured,suffix]];
    $[count[configured] and "/"=first configured;
        .utl.normalizePath configured;
        .utl.normalizePath base,"/",configured]
 };

.tst.emptyRerunState:{[statusName]
    `status`failedTestIds`runId`updatedAt!(statusName;();"";"")
 };

.tst.validFailedIds:{[ids]
    if[0=count ids;:1b];
    if[10h=type ids;:1b];
    (0h=type ids) and all 10h=type each ids
 };

.tst.decodeRerunState:{[lines]
    if[0=count lines;:.tst.emptyRerunState `missing];
    decoded:@[{[text](0b;.j.k text)};"\n" sv lines;{[err](1b;err)}];
    if[first decoded;:.tst.emptyRerunState `invalid];
    doc:last decoded;
    if[not 99h=type doc;:.tst.emptyRerunState `invalid];
    if[not all `schemaVersion`failedTestIds in key doc;
        :.tst.emptyRerunState `invalid];
    if[not .tst.rerunStateVersion="j"$doc`schemaVersion;
        :.tst.emptyRerunState `unsupported];
    if[not .tst.validFailedIds doc`failedTestIds;
        :.tst.emptyRerunState `invalid];
    ids:$[10h=type doc`failedTestIds;enlist doc`failedTestIds;doc`failedTestIds];
    ids:distinct .tst.toString each ids;
    `status`failedTestIds`runId`updatedAt!(
        `ok;ids;
        $[`runId in key doc;.tst.toString doc`runId;""];
        $[`updatedAt in key doc;.tst.toString doc`updatedAt;""])
 };

.tst.loadRerunState:{[]
    path:.tst.rerunStatePath[];
    state:$[.utl.pathExists path;
        .tst.decodeRerunState @[read0;hsym `$path;{()}];
        .tst.emptyRerunState `missing];
    .tst.app.rerunState:state;
    .tst.app.rerunStateStatus:state`status;
    if[(state`status) in `invalid`unsupported;
        .tst.recordDiagnostic[`rerun;`warning;`selection;
            "Ignoring malformed or unsupported rerun state; running the full selection";
            `path`status!(.tst.repoRelativePath path;state`status)]];
    state
 };

.tst.rerunExpectations:{[spec]
    if[not `expectations in key spec;:()];
    expecs:spec`expectations;
    if[98h=type expecs;:expecs];
    if[not 0h=type expecs;expecs:enlist expecs];
    expecs where not (::)~/:expecs
 };

.tst.rerunTestId:{[spec;expec]
    file:$[`tstPath in key spec;.utl.pathToString spec`tstPath;""];
    suite:$[`title in key spec;spec`title;""];
    description:$[`desc in key expec;expec`desc;""];
    .tst.stableTestId[file;suite;description]
 };

.tst.rerunFailedMask:{[spec;expecs;failedIds]
    {[ids;s;e] any ids~\:.tst.rerunTestId[s;e]}[failedIds;spec;] each expecs
 };

.tst.rerunSpecHasFailure:{[failedIds;spec]
    expecs:.tst.rerunExpectations spec;
    if[0=count expecs;:0b];
    any .tst.rerunFailedMask[spec;expecs;failedIds]
 };

.tst.rerunAmendSpec:{[mode;failedIds;spec]
    expecs:.tst.rerunExpectations spec;
    if[0=count expecs;:spec];
    failed:.tst.rerunFailedMask[spec;expecs;failedIds];
    spec[`expectations]:$[mode~`lastFailed;
        expecs where failed;
        (expecs where failed),expecs where not failed];
    spec
 };

.tst.rerunExpectationCount:{[specs]
    sum 0,{count .tst.rerunExpectations x} each specs
 };

.tst.applyRerunSelection:{[specs]
    mode:$[1b~@[get;`.tst.app.lastFailed;0b];`lastFailed;
           1b~@[get;`.tst.app.failedFirst;0b];`failedFirst;
           `all];
    .tst.app.rerunMode:mode;
    .tst.app.rerunApplied:0b;
    state:@[get;`.tst.app.rerunState;{.tst.emptyRerunState `missing}];
    ids:$[`ok~state`status;state`failedTestIds;()];
    .tst.app.priorFailedCount:count ids;
    if[(mode~`all) or 0=count specs;
        .tst.app.selectedTestCount:.tst.rerunExpectationCount specs;
        :specs];
    if[not `ok~state`status;
        .tst.recordDiagnostic[`rerun;`info;`selection;
            "No usable rerun history; running the full selection";
            `mode`status!(mode;state`status)];
        .tst.app.selectedTestCount:.tst.rerunExpectationCount specs;
        :specs];
    if[0=count ids;
        .tst.recordDiagnostic[`rerun;`info;`selection;
            "The previous run had no failed tests; running the full selection";
            enlist[`mode]!enlist mode];
        .tst.app.selectedTestCount:.tst.rerunExpectationCount specs;
        :specs];
    amended:.tst.rerunAmendSpec[mode;ids;] each specs;
    if[mode~`lastFailed;
        amended:amended where 0<count each .tst.rerunExpectations each amended];
    if[mode~`failedFirst;
        priority:.tst.rerunSpecHasFailure[ids;] each amended;
        amended:(amended where priority),amended where not priority];
    .tst.app.rerunApplied:1b;
    .tst.app.selectedTestCount:.tst.rerunExpectationCount amended;
    amended
 };

.tst.selectionMetadata:{[]
    state:@[get;`.tst.app.rerunState;{.tst.emptyRerunState `missing}];
    `mode`stateFile`historyStatus`priorFailedCount`applied`selectedTestCount!(
        @[get;`.tst.app.rerunMode;`all];
        .tst.repoRelativePath .tst.rerunStatePath[];
        state`status;
        count state`failedTestIds;
        1b~@[get;`.tst.app.rerunApplied;0b];
        "j"$@[get;`.tst.app.selectedTestCount;0])
 };

.tst.finalizeRerunSelectionMetadata:{[selectedCount]
    mode:$[1b~@[get;`.tst.app.lastFailed;0b];`lastFailed;
           1b~@[get;`.tst.app.failedFirst;0b];`failedFirst;
           `all];
    state:@[get;`.tst.app.rerunState;{.tst.emptyRerunState `missing}];
    .tst.app.rerunMode:mode;
    .tst.app.priorFailedCount:count state`failedTestIds;
    .tst.app.rerunApplied:(not mode~`all) and (`ok~state`status) and
        0<count state`failedTestIds;
    .tst.app.selectedTestCount:"j"$selectedCount;
    ::
 };

.tst.persistRerunState:{[]
    if[1b~@[get;`.tst.app.isolateChild;0b];:1b];
    if[1b~@[get;`.tst.app.describeOnly;0b];:1b];
    path:.tst.rerunStatePath[];
    slash:where path="/";
    dir:$[count slash;(last slash)#path;"."];
    if[0=count dir;dir:"/"];
    .utl.ensureDir dir;
    rows:.tst.resultRows .resq.state.results;
    eligible:rows where {[row] (row`kind) in `test`fuzz`perf} each rows;
    / Collection/framework-only runs must not erase useful prior history.
    if[0=count eligible;:1b];
    statuses:.tst.normalizeResultStatus each {x`status} each eligible;
    failedRows:eligible where statuses in `fail`error;
    ids:distinct {.tst.toString x`testId} each failedRows;
    runMeta:@[get;`.tst.app.runMetadata;{()!()}];
    doc:`schemaVersion`framework`runId`updatedAt`testCount`failedCount`failedTestIds!(
        .tst.rerunStateVersion;"resQ";
        $[`id in key runMeta;runMeta`id;""];
        .tst.isoTimestamp .z.p;
        count eligible;count ids;ids);
    tmp:path,".tmp.",string .z.i;
    written:.[{[p;text](hsym `$p) 0:enlist text;1b};(tmp;.j.j doc);{[args;err]0b}];
    if[not written;
        .tst.recordDiagnostic[`rerun;`warning;`persistence;
            "Unable to write rerun state";enlist[`path]!enlist .tst.repoRelativePath path];
        :0b];
    moved:.[{[src;dst]system "mv -f -- ",.utl.shellQuote[src]," ",.utl.shellQuote dst;1b};
        (tmp;path);{[args;err]0b}];
    if[not moved;
        @[hdel;hsym `$tmp;{}];
        .tst.recordDiagnostic[`rerun;`warning;`persistence;
            "Unable to atomically publish rerun state";
            enlist[`path]!enlist .tst.repoRelativePath path];
        :0b];
    1b
 };

\d .
::
