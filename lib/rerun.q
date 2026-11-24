\d .tst

/ Versioned, repository-local execution history for --last-failed and
/ --failed-first. This is deliberately a cache, never an authority: missing or
/ malformed history falls back to the complete selected suite.
.tst.rerunStateVersion:2;

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
        .resq.util.normalizePath configured;
        .resq.util.normalizePath base,"/",configured]
 };

.tst.emptyRerunState:{[statusName]
    `status`diagnostic`failedTestIds`failedTests`runId`updatedAt!(statusName;"";();();"";"")
 };

/ The failed tests of a state document with the file each is in, as a list
/ of (testId; file; carried). A document from before files were recorded
/ has only IDs: the file is then "".
.tst.rerunFailedTests:{[doc;ids]
    listed:$[`failedTests in key doc;@[.tst.jsonObjectRows;doc`failedTests;{[err]()}];()];
    usable:listed where {[entry]
        (99h=type entry) and $[all `testId`file in key entry;
            all (type each entry`testId`file) in 10 -10h;0b]} each listed;
    known:{[entry]
        (.tst.toString entry`testId;.tst.toString entry`file;
         $[`carried in key entry;"j"$entry`carried;0j])} each usable;
    knownIds:known[;0];
    known,{[id](id;"";0j)} each ids where not ids in knownIds
 };

.tst.validFailedIds:{[ids]
    if[0=count ids;:1b];
    (0h=type ids) and all 10h=type each ids
 };

.tst.decodeRerunState:{[lines]
    if[0=count lines;:.tst.emptyRerunState `missing];
    decoded:@[{[text](0b;.j.k text)};"\n" sv lines;{[err](1b;err)}];
    if[first decoded;
        state:.tst.emptyRerunState `invalid;
        state[`diagnostic]:"JSON parse failed: ",.tst.toString last decoded;
        :state];
    doc:last decoded;
    if[not 99h=type doc;
        state:.tst.emptyRerunState `invalid;
        state[`diagnostic]:"JSON root must be an object";
        :state];
    if[not `schemaVersion in key doc;
        state:.tst.emptyRerunState `invalid;
        state[`diagnostic]:"missing schemaVersion";
        :state];
    if[not .tst.validJsonLong[doc`schemaVersion;0j];
        state:.tst.emptyRerunState `invalid;
        state[`diagnostic]:"schemaVersion must be an integral JSON number";
        :state];
    if[not .tst.rerunStateVersion="j"$doc`schemaVersion;
        state:.tst.emptyRerunState `unsupported;
        state[`diagnostic]:"unsupported schemaVersion";
        :state];
    if[not all `failedTestIds`identityAlgorithm`identityCodec in key doc;
        state:.tst.emptyRerunState `unsupported;
        state[`diagnostic]:"identity metadata is missing; migrate or rebuild the cache";
        :state];
    if[not .tst.identityDocumentMatches doc;
        state:.tst.emptyRerunState `unsupported;
        state[`diagnostic]:"identity algorithm or codec does not match this runtime";
        :state];
    if[not .tst.validFailedIds doc`failedTestIds;
        state:.tst.emptyRerunState `invalid;
        state[`diagnostic]:"failedTestIds must be an array of strings";
        :state];
    ids:doc`failedTestIds;
    ids:distinct .tst.toString each ids;
    `status`diagnostic`failedTestIds`failedTests`runId`updatedAt!(
        `ok;"";ids;.tst.rerunFailedTests[doc;ids];
        $[`runId in key doc;.tst.toString doc`runId;""];
        $[`updatedAt in key doc;.tst.toString doc`updatedAt;""])
 };

.tst.loadRerunState:{[]
    path:.tst.rerunStatePath[];
    state:.tst.emptyRerunState `missing;
    if[.resq.util.pathExists path;
        readResult:@[{[p](0b;read0 hsym `$p)};path;{[err](1b;.tst.toString err)}];
        if[first readResult;
            state:.tst.emptyRerunState `invalid;
            state[`diagnostic]:"read failed: ",last readResult];
        if[not first readResult;state:.tst.decodeRerunState last readResult]];
    .tst.app.rerunState:state;
    .tst.app.rerunStateStatus:state`status;
    archive:"";
    if[`unsupported~state`status;
        archive:.tst.archiveIdentityState path;
        if[count archive;
            state[`diagnostic]:state[`diagnostic],"; archived at ",.tst.repoRelativePath archive;
            .tst.noteIdentityState .tst.repoRelativePath[path],
                " was written by another q runtime or resQ identity generation; kept as ",
                .tst.repoRelativePath archive];
        if[0=count archive;
            state[`diagnostic]:state[`diagnostic],"; unable to archive incompatible state"];
        / A workspace used by two q runtimes: take up this runtime's own
        / state where the other one left it.
        if[.tst.restoreIdentityState path;
            restored:@[{[p](0b;read0 hsym `$p)};path;{[err](1b;())}];
            if[not first restored;
                own:.tst.decodeRerunState last restored;
                if[`ok~own`status;
                    state:own;
                    .tst.app.rerunState:state;
                    .tst.app.rerunStateStatus:state`status]]]];
    / State from another identity generation was archived and said so
    / above; a malformed file was ignored without a word.
    if[(state`status) in `invalid`unsupported;
        $[`invalid~state`status;.tst.recordStateWarning[`rerun;`selection];
            .tst.recordDiagnostic[`rerun;`warning;`selection]][
            "Ignoring malformed or unsupported rerun state; running the full selection: ",state`diagnostic;
            `path`status`diagnostic!(.tst.repoRelativePath path;state`status;state`diagnostic)]];
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
    .tst.expectationTestId[spec;expec]
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

/ How many runs a failure with no known file is carried for.
.tst.RERUN_UNPLACED_RUNS:20j;

/ The earlier failures (testId; file; carried) that stay on the list after
/ a run that executed `executedIds`.
.tst.rerunCarriedFailures:{[previous;executedIds;complete]
    previous:previous where not previous[;0] in executedIds;
    if[0=count previous;:()];
    files:previous[;1];
    looked:.tst.runScopeFiles[];
    keep:{[looked;complete;entry]
        file:entry 1;
        / no file on record: carried for a limited number of runs
        if[0=count file;:.tst.RERUN_UNPLACED_RUNS>entry 2];
        / its file was run: gone from it if the run saw the whole file
        if[any file~/:looked;:not complete];
        .tst.stateFileExists file
    }[looked;complete] each previous;
    {[entry](entry 0;entry 1;1+entry 2)} each previous where keep
 };

.tst.persistRerunState:{[]
    if[1b~@[get;`.tst.app.isolateChild;0b];:1b];
    if[1b~@[get;`.tst.app.describeOnly;0b];:1b];
    path:.tst.rerunStatePath[];
    slash:where path="/";
    dir:$[count slash;(last slash)#path;"."];
    if[0=count dir;dir:"/"];
    rows:.tst.resultRows .resq.state.results;
    eligible:rows where {[row] (row`kind) in `test`fuzz`perf} each rows;
    / Collection/framework-only runs must not erase useful prior history, and
    / must not create the state directory either: a run whose only file failed
    / to load used to leave an empty .resq/ behind in the caller's directory.
    if[0=count eligible;:1b];
    .tst.ensureStateDir dir;
    / A directory that cannot be made has been said; nothing to try.
    if[not .resq.util.isDir dir;
        .tst.recordDiagnostic[`rerun;`warning;`persistence;
            "Unable to write rerun state";enlist[`path]!enlist .tst.repoRelativePath path];
        :0b];
    / Re-check immediately before publication: another process or operator may
    / have replaced the path after init. Never overwrite a different identity
    / generation merely because this run already loaded its selection state.
    if[.resq.util.pathExists path;
        currentRead:@[{[p](0b;read0 hsym `$p)};path;{[err](1b;())}];
        if[not first currentRead;
            currentState:.tst.decodeRerunState last currentRead;
            if[`unsupported~currentState`status;
                archive:.tst.archiveIdentityState path;
                if[0=count archive;
                    .tst.recordDiagnostic[`rerun;`warning;`persistence;
                        "Refusing to overwrite incompatible rerun identity state";
                        enlist[`path]!enlist .tst.repoRelativePath path];
                    :0b];
                .tst.recordDiagnostic[`rerun;`warning;`persistence;
                    "Archived incompatible rerun identity state before rebuilding";
                    `path`archive!(.tst.repoRelativePath path;.tst.repoRelativePath archive)]]]];
    statuses:.tst.normalizeResultStatus each {x`status} each eligible;
    failedRows:eligible where statuses in `fail`error;
    failed:{[row](.tst.toString row`testId;.tst.stateRowFile row;0j)} each failedRows;
    failed:failed (failed[;0])?distinct failed[;0];
    / A test that failed before and was not run this time is still on the
    / list: this run says nothing about it. It used to be dropped, so one
    / run of another file, or a watch-mode rerun, made -last-failed forget a
    / test that still fails. It goes when a complete run of its file no
    / longer has it, or when its file is gone.
    previous:@[get;`.tst.app.rerunState;{.tst.emptyRerunState `missing}];
    carried:.tst.rerunCarriedFailures[
        $[`ok~previous`status;previous`failedTests;()];
        distinct {.tst.toString x`testId} each eligible;
        .tst.flakeCompleteInventoryRun rows where .tst.flakeEligibleRow each rows];
    failed:failed,carried;
    ids:failed[;0];
    runMeta:@[get;`.tst.app.runMetadata;{()!()}];
    doc:`schemaVersion`identityAlgorithm`identityCodec`framework`runId`updatedAt`testCount`failedCount`failedTestIds`failedTests!(
        .tst.rerunStateVersion;.tst.IDENTITY_ALGORITHM;.tst.identityCodecMetadata[];"resQ";
        $[`id in key runMeta;runMeta`id;""];
        .tst.isoTimestamp .z.p;
        count eligible;count ids;ids;
        {[entry]`testId`file`carried!entry} each failed);
    tmp:path,".tmp.",string .z.i;
    written:.[{[p;text](hsym `$p) 0:enlist text;1b};(tmp;.tst.output.strictJson doc);{[err]0b}];
    if[not written;
        .tst.recordStateWarning[`rerun;`persistence;
            "Unable to write rerun state";enlist[`path]!enlist .tst.repoRelativePath path];
        :0b];
    moved:.[{[src;dst]system "mv -f -- ",.resq.util.shellQuote[src]," ",.resq.util.shellQuote dst;1b};
        (tmp;path);{[err]0b}];
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
