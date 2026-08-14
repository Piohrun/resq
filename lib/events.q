/ Versioned execution manifest, canonical lifecycle events, and trusted
/ in-process plugin registration. Events are projected after execution from the
/ merged canonical model, so isolation/concurrency cannot reorder semantics.

.tst.EVENT_SCHEMA_VERSION:2j;
.tst.MANIFEST_SCHEMA_VERSION:2j;

/ Persistent registries: watch/repeated runs keep registrations, while each run
/ gets a fresh event projection. Registering the same name replaces it, making
/ test bootstrap files idempotent when reloaded.
.resq.plugins.init_:1b;
if[not `observers in key `.resq.plugins;.resq.plugins.observers:()!()];
if[not `reporters in key `.resq.plugins;.resq.plugins.reporters:()!()];

.resq.pluginName:{[name]
    text:.tst.toString name;
    if[0=count text;'"plugin name must not be empty"];
    `$text
 };

.resq.registerObserver:{[name;callback]
    if[not type[callback] within 100 104h;'"observer must be a q function"];
    keyName:.resq.pluginName name;
    .resq.plugins.observers[keyName]:callback;
    keyName
 };

.resq.registerReporter:{[name;callback]
    if[not type[callback] within 100 104h;'"reporter must be a q function"];
    keyName:.resq.pluginName name;
    .resq.plugins.reporters[keyName]:callback;
    keyName
 };

.resq.unregisterObserver:{[name]
    keyName:.resq.pluginName name;
    if[keyName in key .resq.plugins.observers;
        .resq.plugins.observers:(key[.resq.plugins.observers] except enlist keyName)#.resq.plugins.observers];
    ::
 };

.resq.unregisterReporter:{[name]
    keyName:.resq.pluginName name;
    if[keyName in key .resq.plugins.reporters;
        .resq.plugins.reporters:(key[.resq.plugins.reporters] except enlist keyName)#.resq.plugins.reporters];
    ::
 };

.resq.clearPlugins:{[]
    .resq.plugins.observers:()!();
    .resq.plugins.reporters:()!();
    ::
 };

.resq.setStrictPlugins:{[enabled]
    if[not -1h=type enabled;'"strict plugin policy expects a boolean"];
    .tst.app.strictPlugins:enabled;
    enabled
 };

.tst.fileContentDigest:{[file]
    path:.utl.pathToString file;
    lines:@[read0;hsym `$path;{()}];
    $[count lines;.tst.stableHash "\n" sv lines;""]
 };

.tst.manifestFileId:{[path] "file_",.tst.stableHash .tst.toString path};
.tst.manifestSuiteId:{[file;suite]
    "suite_",.tst.stableHash[.tst.toString[file],"\n",.tst.toString suite]
 };

.tst.manifestInventoryFromResults:{[runModel]
    rows:.tst.resultRows runModel;
    {[row]
        executionId:$[count .tst.toString row`caseId;row`caseId;row`testId];
        `executionId`testId`caseId`file`suite`description`line`kind`parameters`tags`testShardKey`caseShardKey`shardable!(
            executionId;.tst.toString row`testId;.tst.toString row`caseId;
            .tst.toString row`file;.tst.toString row`suite;
            .tst.toString row`description;"j"$row`line;row`kind;
            $[`parameters in key row;row`parameters;()!()];(),row`tags;
            .tst.toString row`testId;executionId;0b)
    } each rows
 };

.tst.manifestTestEntry:{[allPaths;selectedPaths;unit;shardIndex;shardCount;row]
    path:.tst.toString row`file;
    suite:.tst.toString row`suite;
    testId:.tst.toString row`testId;
    caseId:.tst.toString row`caseId;
    executionId:.tst.toString row`executionId;
    shardable:$[`shardable in key row;1b~row`shardable;1b];
    shardKey:$[unit~`file;.tst.manifestFileId path;
        unit~`test;testId;executionId];
    assigned:$[not shardable;0j;unit~`file;
        "j"$(allPaths?path) mod shardCount;
        .tst.shardBucket[shardKey;shardCount]];
    `executionId`testId`caseId`suiteId`fileId`file`suite`description`line`kind`parameters`tags`shardKey`assignedShard`selected`shardable!(
        executionId;testId;caseId;.tst.manifestSuiteId[path;suite];
        .tst.manifestFileId path;path;suite;.tst.toString row`description;
        "j"$row`line;.tst.toString row`kind;
        $[`parameters in key row;row`parameters;()!()];
        string each (),$[`tags in key row;row`tags;()];
        shardKey;assigned;$[shardable;assigned=shardIndex;1b];shardable)
 };

.tst.manifestInventoryIds:{[rows]
    if[0=count rows;:()];
    $[98h=type rows;
        .tst.toString each rows`executionId;
        .tst.toString each {x`executionId} each rows]
 };

.tst.manifestRowsMissing:{[rows;knownIds]
    if[0=count rows;:rows];
    mask:not .tst.manifestInventoryIds[rows] in knownIds;
    rows where mask
 };

.tst.manifestEntriesFor:{[allPaths;selectedPaths;unit;shardIndex;shardCount;rows]
    if[0=count rows;:()];
    $[98h=type rows;
        {[allPaths;selectedPaths;unit;shardIndex;shardCount;table;i]
            .tst.manifestTestEntry[allPaths;selectedPaths;unit;shardIndex;shardCount;table i]
          }[allPaths;selectedPaths;unit;shardIndex;shardCount;rows;] each til count rows;
        .tst.manifestTestEntry[allPaths;selectedPaths;unit;shardIndex;shardCount;] each rows]
 };

.tst.executionManifest:{[runModel]
    snapshot:.tst.runSnapshot[];
    allFiles:(),$[`allDiscoveredFiles in key snapshot;
        snapshot`allDiscoveredFiles;@[get;`.tst.app.allDiscoveredFiles;{()}]];
    selected:(),$[`discoveredFiles in key snapshot;
        snapshot`discoveredFiles;@[get;`.tst.app.discoveredFiles;{()}]];
    if[0=count allFiles;allFiles:selected];
    allPaths:.tst.repoRelativePath each allFiles;
    / Discovery is sorted today, but the manifest contract must not depend on a
    / caller preserving that implementation detail.
    fileOrder:iasc allPaths;
    allFiles:allFiles fileOrder;
    allPaths:allPaths fileOrder;
    selectedPaths:.tst.repoRelativePath each selected;
    run:$[`run in key runModel;runModel`run;()!()];
    runShard:$[(99h=type run) and `shard in key run;run`shard;()!()];
    shardCount:"j"$$[`count in key runShard;runShard`count;1j];
    shardIndex:"j"$$[`index in key runShard;runShard`index;0j];
    unit:`$$[`unit in key runShard;runShard`unit;"file"];
    fileEntries:{[selectedPaths;unit;shardCount;index;file;path]
        `fileId`path`sourceDigest`assignedShard`selected`shardable!(
            .tst.manifestFileId path;path;.tst.fileContentDigest file;
            $[unit~`file;"j"$index mod shardCount;-1j];
            any path~/:selectedPaths;1b)
      }[selectedPaths;unit;shardCount]'[til count allFiles;allFiles;allPaths];
    inventory:$[`executionInventory in key snapshot;
        snapshot`executionInventory;@[get;`.tst.app.executionInventory;{()}]];
    inventoryRows:.tst.eventRows inventory;
    resultInventory:.tst.eventRows .tst.manifestInventoryFromResults runModel;
    existingIds:.tst.manifestInventoryIds inventoryRows;
    extraRows:.tst.manifestRowsMissing[resultInventory;existingIds];
    testEntries:.tst.manifestEntriesFor[
        allPaths;selectedPaths;unit;shardIndex;shardCount;inventoryRows];
    testEntries,:.tst.manifestEntriesFor[
        allPaths;selectedPaths;unit;shardIndex;shardCount;extraRows];
    selectedIds:.tst.toString each $[`selectedExecutionIds in key runShard;
        runShard`selectedExecutionIds;()];
    testEntries:{[ids;entry]
        out:entry;
        out[`selected]:any .tst.toString[out`executionId]~/:ids;
        out
      }[selectedIds;] each testEntries;
    fileRows:.tst.eventRows fileEntries;
    sourceBasis:{[entry]
        (.tst.toString entry`path),"\t",(.tst.toString entry`sourceDigest),
            "\t",string[entry`assignedShard]
      } each fileRows;
    digest:"manifest_",.tst.stableHash "\n" sv ((
        "resq-execution-manifest-v2";
        "unit=",string[unit],";count=",string shardCount;
        .tst.toString @[get;`.resq.VERSION;{"unknown"}]),sourceBasis);
    revision:$[(99h=type run) and `vcs in key run;run`vcs;()!()];
    `schemaVersion`kind`digest`digestAlgorithm`identityAlgorithm`frameworkVersion`revision`shard`files`tests!(
        .tst.MANIFEST_SCHEMA_VERSION;"resq-execution-manifest";digest;
        "md5-source-topology-v2";"resq-test-case-id-v2";
        .tst.toString @[get;`.resq.VERSION;{"unknown"}];revision;
        $[(99h=type run) and `shard in key run;run`shard;()!()];
        fileEntries;testEntries)
 };

.tst.eventRecord:{[sequence;typeName;runId;entityId;parentId;occurredAt;payload]
    `schemaVersion`sequence`type`runId`entityId`parentId`occurredAt`payload!(
        .tst.EVENT_SCHEMA_VERSION;"j"$sequence;.tst.toString typeName;
        .tst.toString runId;.tst.toString entityId;.tst.toString parentId;
        .tst.toString occurredAt;payload)
 };

/ `enlist dict` infers typed string columns; concatenating a later row whose
/ strings have different lengths then signals 'length. Enlist every field
/ separately so strings and heterogeneous payload dictionaries remain cells.
.tst.oneEventTable:{[event] flip enlist each event};

.tst.eventRows:{[events]
    $[98h=type events;{[table;i]table i}[events] each til count events;
      99h=type events;enlist events;
      0h=type events;events;
      ()]
 };

.tst.resultStatusSummary:{[rows]
    statuses:.tst.toString each {.tst.normalizeResultStatus x`status} each rows;
    `testCount`passCount`failCount`errorCount`skipCount!(
        "j"$count rows;"j"$sum {x~"pass"} each statuses;
        "j"$sum {x~"fail"} each statuses;
        "j"$sum {x~"error"} each statuses;
        "j"$sum {x in ("skip";"pending")} each statuses)
 };

.tst.caseRows:{[cases]
    $[98h=type cases;{[table;i]table i}[cases] each til count cases;
      99h=type cases;enlist cases;
      0h=type cases;cases;
      ()]
 };

.tst.eventTimestamp:{[row;field;fallback]
    if[not field in key row;:fallback];
    raw:row field;
    $[10h=type raw;raw;fallback]
 };

.tst.eventInterval:{[rows;fallbackStart;fallbackFinished]
    if[0=count rows;:(fallbackStart;fallbackFinished)];
    starts:{[fallback;row].tst.eventTimestamp[row;`startedAt;fallback]}[fallbackStart;] each rows;
    finishes:{[fallback;row].tst.eventTimestamp[row;`finishedAt;fallback]}[fallbackFinished;] each rows;
    (first asc starts;last asc finishes)
 };

.tst.lifecycleEvents:{[runModel;manifest]
    run:runModel`run;
    runId:.tst.toString run`id;
    started:.tst.toString run`startedAt;
    finished:.tst.toString run`finishedAt;
    rows:.tst.resultRows runModel;
    events:();
    sequence:1j;
    events,:.tst.oneEventTable .tst.eventRecord[sequence;"run.started";runId;runId;"";started;
        `frameworkVersion`ordering`selection`shard!(
            runModel`frameworkVersion;run`ordering;run`selection;run`shard)];
    sequence+:1;
    manifestNotice:`schemaVersion`kind`digest`digestAlgorithm`identityAlgorithm`frameworkVersion`fileCount`testCount!(
        manifest`schemaVersion;manifest`kind;manifest`digest;manifest`digestAlgorithm;
        manifest`identityAlgorithm;manifest`frameworkVersion;
        "j"$count manifest`files;"j"$count manifest`tests);
    events,:.tst.oneEventTable .tst.eventRecord[sequence;"manifest.published";runId;manifest`digest;runId;started;manifestNotice];
    sequence+:1;

    manifestFiles:.tst.eventRows manifest`files;
    selectedFiles:manifestFiles where {1b~x`selected} each manifestFiles;
    resultFiles:distinct {.tst.toString x`file} each rows;
    knownPaths:{.tst.toString x`path} each selectedFiles;
    extraPaths:resultFiles except knownPaths;
    if[count extraPaths;
        selectedFiles,:{[path]
            `fileId`path`sourceDigest`assignedShard`selected`shardable!(
                .tst.manifestFileId path;path;"";0j;1b;0b)
          } each extraPaths];

    fi:0;
    while[fi<count selectedFiles;
        fileEntry:selectedFiles fi;
        filePath:.tst.toString fileEntry`path;
        fileId:.tst.toString fileEntry`fileId;
        fileRows:rows where {[path;x].tst.toString[x`file]~path}[filePath;] each rows;
        fileInterval:.tst.eventInterval[fileRows;started;finished];
        events,:.tst.oneEventTable .tst.eventRecord[sequence;"file.started";runId;fileId;runId;first fileInterval;fileEntry];
        sequence+:1;
        suites:distinct {.tst.toString x`suite} each fileRows;
        si:0;
        while[si<count suites;
            suiteName:suites si;
            suiteId:.tst.manifestSuiteId[filePath;suiteName];
            suiteRows:fileRows where {[name;x].tst.toString[x`suite]~name}[suiteName;] each fileRows;
            suiteInterval:.tst.eventInterval[suiteRows;first fileInterval;last fileInterval];
            events,:.tst.oneEventTable .tst.eventRecord[sequence;"suite.started";runId;suiteId;fileId;first suiteInterval;
                `file`suite`testCount!(filePath;suiteName;"j"$count suiteRows)];
            sequence+:1;
            ti:0;
            while[ti<count suiteRows;
                row:suiteRows ti;
                testId:.tst.toString row`testId;
                caseId:.tst.toString row`caseId;
                executionId:$[count caseId;caseId;testId];
                testStarted:.tst.eventTimestamp[row;`startedAt;first suiteInterval];
                testFinished:.tst.eventTimestamp[row;`finishedAt;last suiteInterval];
                identity:`file`suite`description`line`kind`tags`parameters!(
                    filePath;suiteName;.tst.toString row`description;"j"$row`line;
                    .tst.toString row`kind;string each (),row`tags;
                    $[`parameters in key row;row`parameters;()!()]);
                events,:.tst.oneEventTable .tst.eventRecord[sequence;"test.started";runId;executionId;suiteId;testStarted;identity];
                sequence+:1;
                attempts:.tst.caseRows row`attemptHistory;
                if[0=count attempts;
                    attempts:enlist `attempt`status`duration`durationSeconds`message`failures`assertsRun!(
                        1j;row`status;string row`time;0f;.tst.toString row`message;
                        (),row`failures;"j"$row`assertsRun)];
                ai:0;
                while[ai<count attempts;
                    attempt:attempts ai;
                    attemptNo:"j"$$[`attempt in key attempt;attempt`attempt;ai+1];
                    attemptId:executionId,"/attempt/",string attemptNo;
                    attemptStarted:.tst.eventTimestamp[attempt;`startedAt;testStarted];
                    attemptFinished:.tst.eventTimestamp[attempt;`finishedAt;testFinished];
                    events,:.tst.oneEventTable .tst.eventRecord[sequence;"attempt.started";runId;attemptId;executionId;attemptStarted;
                        enlist[`attempt]!enlist attemptNo];
                    sequence+:1;
                    events,:.tst.oneEventTable .tst.eventRecord[sequence;"attempt.finished";runId;attemptId;executionId;attemptFinished;attempt];
                    sequence+:1;
                    ai+:1];
                cases:.tst.caseRows row`parameterCases;
                ci:0;
                while[ci<count cases;
                    case:cases ci;
                    caseId:$[`caseId in key case;.tst.toString case`caseId;
                        "case_",.tst.stableHash[testId,"\n",string ci,"\n",.Q.s1 case`parameters]];
                    caseStarted:.tst.eventTimestamp[case;`startedAt;testStarted];
                    caseFinished:.tst.eventTimestamp[case;`finishedAt;testFinished];
                    events,:.tst.oneEventTable .tst.eventRecord[sequence;"case.started";runId;caseId;testId;caseStarted;
                        `index`parameters!("j"$ci;case`parameters)];
                    sequence+:1;
                    events,:.tst.oneEventTable .tst.eventRecord[sequence;"case.finished";runId;caseId;testId;caseFinished;case];
                    sequence+:1;
                    ci+:1];
                bench:row`benchmark;
                if[(99h=type bench) and count bench;
                    benchmarkId:.tst.toString bench`benchmarkId;
                    events,:.tst.oneEventTable .tst.eventRecord[sequence;"benchmark.finished";runId;benchmarkId;testId;testFinished;bench];
                    sequence+:1];
                testDiags:.tst.caseRows row`diagnostics;
                di:0;
                while[di<count testDiags;
                    diagnostic:testDiags di;
                    diagId:"diagnostic_",.tst.stableHash[testId,"\n",string di,"\n",.Q.s1 diagnostic];
                    events,:.tst.oneEventTable .tst.eventRecord[sequence;"diagnostic.recorded";runId;diagId;testId;testFinished;diagnostic];
                    sequence+:1;
                    di+:1];
                testFinishedPayload:`status`duration`durationSeconds`assertsRun`attempts`retried`flaky!(
                        .tst.toString row`status;string row`time;
                        .tst.output.jsonDurationSeconds row`time;
                        "j"$row`assertsRun;"j"$row`attempts;row`retried;row`flaky);
                qstate:$[`quarantine in key row;row`quarantine;()!()];
                if[(99h=type qstate) and 0<count qstate;
                    testFinishedPayload[`quarantine]:qstate];
                events,:.tst.oneEventTable .tst.eventRecord[sequence;"test.finished";runId;executionId;suiteId;testFinished;testFinishedPayload];
                sequence+:1;
                ti+:1];
            events,:.tst.oneEventTable .tst.eventRecord[sequence;"suite.finished";runId;suiteId;fileId;last suiteInterval;
                .tst.resultStatusSummary suiteRows];
            sequence+:1;
            si+:1];
        events,:.tst.oneEventTable .tst.eventRecord[sequence;"file.finished";runId;fileId;runId;last fileInterval;
            .tst.resultStatusSummary fileRows];
        sequence+:1;
        fi+:1];
    coverage:runModel`coverage;
    if[(99h=type coverage) and count coverage;
        events,:.tst.oneEventTable .tst.eventRecord[sequence;"coverage.finished";runId;"coverage";runId;finished;coverage];
        sequence+:1];
    snapshotInventory:$[`snapshotInventory in key runModel;runModel`snapshotInventory;()!()];
    if[(99h=type snapshotInventory) and 1b~snapshotInventory`enabled;
        events,:.tst.oneEventTable .tst.eventRecord[sequence;"snapshots.audited";runId;"snapshots";runId;finished;snapshotInventory];
        sequence+:1];
    benchmarkAnalysis:$[`benchmarkAnalysis in key runModel;runModel`benchmarkAnalysis;()!()];
    if[(99h=type benchmarkAnalysis) and 1b~benchmarkAnalysis`enabled;
        events,:.tst.oneEventTable .tst.eventRecord[sequence;"benchmarks.compared";runId;"benchmarks";runId;finished;benchmarkAnalysis];
        sequence+:1];
    runDiags:.tst.caseRows runModel`diagnostics;
    di:0;
    while[di<count runDiags;
        diagnostic:runDiags di;
        diagId:"diagnostic_",.tst.stableHash[runId,"\n",string di,"\n",.Q.s1 diagnostic];
        events,:.tst.oneEventTable .tst.eventRecord[sequence;"diagnostic.recorded";runId;diagId;runId;finished;diagnostic];
        sequence+:1;
        di+:1];
    events,:.tst.oneEventTable .tst.eventRecord[sequence;"run.finished";runId;runId;"";finished;runModel`summary];
    .tst.eventRows events
 };

.tst.pluginFailureRow:{[kind;name;message]
    base:`suite`description`status`message`time`failures`assertsRun`file`line`namespace`tags`output`kind!(
        `PLUGIN_FAILURE;`$(.tst.toString kind),":",.tst.toString name;`error;
        message;0Nn;enlist message;0i;"";0Ni;"";`symbol$();"";`plugin);
    .tst.oneResultTable .tst.completeResultRow base
 };

.tst.invokePluginProtected:{[callback;args]
    savedResults:.resq.state.results;
    savedPassed:@[get;`.tst.app.passed;1b];
    savedDiagnostics:@[get;`.tst.app.diagnostics;{()}];
    outcome:.[
        {[fn;arguments](0b;fn . arguments)};
        (callback;args);
        {[err](1b;.tst.toString err)}];
    / Callback return values and direct verdict mutations are never authoritative.
    .resq.state.results:savedResults;
    .tst.app.passed:savedPassed;
    .tst.app.diagnostics:savedDiagnostics;
    outcome
 };

.tst.recordPluginFailure:{[kind;name;message]
    strict:1b~@[get;`.tst.app.strictPlugins;0b];
    severity:$[strict;`error;`warning];
    .tst.recordDiagnostic[`plugin;severity;`plugin;
        .tst.toString[kind]," '",.tst.toString[name],"' failed: ",message;
        `kind`name`strict!(kind;name;strict)];
    -1 "PLUGIN ",string[severity],": ",.tst.toString[kind]," '",.tst.toString[name],"' failed: ",message;
    if[strict;
        .resq.state.results:.resq.state.results upsert .tst.pluginFailureRow[kind;name;message]];
    ::
 };

.tst.runRegisteredPlugins:{[]
    / The aggregate parent owns plugin dispatch. A child has neither the parent
    / registry nor the complete merged run, and duplicate callbacks would make
    / concurrent output nondeterministic.
    if[1b~@[get;`.tst.app.isolateChild;0b];:()];
    preliminary:.tst.canonicalRunModel .resq.state.results;
    events:preliminary`events;
    observers:.resq.plugins.observers;
    observerNames:key observers;
    oi:0;
    while[oi<count observerNames;
        name:observerNames oi;
        callback:observers name;
        failed:0b;
        ei:0;
        while[(ei<count events) and not failed;
            outcome:.tst.invokePluginProtected[callback;enlist events ei];
            if[first outcome;
                failed:1b;
                .tst.recordPluginFailure[`observer;name;last outcome]];
            ei+:1];
        oi+:1];
    model:.tst.canonicalRunModel .resq.state.results;
    reporters:.resq.plugins.reporters;
    reporterNames:key reporters;
    ri:0;
    while[ri<count reporterNames;
        name:reporterNames ri;
        / A previous reporter may have failed under strict policy. Rebuild so
        / later reporters observe that diagnostic/error, never a stale model.
        model:.tst.canonicalRunModel .resq.state.results;
        outcome:.tst.invokePluginProtected[reporters name;(model;model`events)];
        if[first outcome;.tst.recordPluginFailure[`reporter;name;last outcome]];
        ri+:1];
    ::
 };

.resq.loadPluginFiles:{[]
    files:(),@[get;`.tst.app.pluginFiles;{()}];
    if[0=count files;:()];
    {[path]
        p:.utl.pathToString path;
        if[not .utl.isFile p;'"plugin file is not a regular file: ",p];
        outcome:@[{[file].utl.loadQFile file;(0b;"")};p;{[e](1b;.tst.toString e)}];
        if[first outcome;'"failed to load plugin file ",p,": ",last outcome]
      } each files;
    ::
 };
