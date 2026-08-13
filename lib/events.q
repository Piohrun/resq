/ Versioned execution manifest, canonical lifecycle events, and trusted
/ in-process plugin registration. Events are projected after execution from the
/ merged canonical model, so isolation/concurrency cannot reorder semantics.

.tst.EVENT_SCHEMA_VERSION:1j;
.tst.MANIFEST_SCHEMA_VERSION:1j;

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

.tst.executionManifest:{[runModel]
    rows:.tst.resultRows runModel;
    allFiles:(),@[get;`.tst.app.allDiscoveredFiles;{()}];
    selected:(),@[get;`.tst.app.discoveredFiles;{()}];
    if[0=count allFiles;allFiles:selected];
    allPaths:.tst.repoRelativePath each allFiles;
    / Discovery is sorted today, but the manifest contract must not depend on a
    / caller preserving that implementation detail.
    fileOrder:iasc allPaths;
    allFiles:allFiles fileOrder;
    allPaths:allPaths fileOrder;
    selectedPaths:.tst.repoRelativePath each selected;
    shardCount:"j"$@[get;`.tst.app.shardCount;1j];
    fileEntries:{[selectedPaths;shardCount;index;file;path]
        `fileId`path`sourceDigest`assignedShard`selected`shardable!(
            .tst.manifestFileId path;path;.tst.fileContentDigest file;
            "j"$index mod shardCount;path in selectedPaths;1b)
      }[selectedPaths;shardCount]'[til count allFiles;allFiles;allPaths];
    testEntries:{[row]
        path:.tst.toString row`file;
        suite:.tst.toString row`suite;
        `testId`suiteId`fileId`file`suite`description`line`kind`tags`shardKey!(
            .tst.toString row`testId;
            .tst.manifestSuiteId[path;suite];
            .tst.manifestFileId path;
            path;suite;.tst.toString row`description;"j"$row`line;
            .tst.toString row`kind;string each (),row`tags;
            .tst.manifestFileId path)
      } each rows;
    fileRows:.tst.eventRows fileEntries;
    sourceBasis:{[entry]
        (.tst.toString entry`path),"\t",(.tst.toString entry`sourceDigest),
            "\t",string[entry`assignedShard]
      } each fileRows;
    digest:"manifest_",.tst.stableHash "\n" sv ((
        "resq-execution-manifest-v1";
        .tst.toString @[get;`.resq.VERSION;{"unknown"}]),sourceBasis);
    run:$[`run in key runModel;runModel`run;()!()];
    revision:$[(99h=type run) and `vcs in key run;run`vcs;()!()];
    `schemaVersion`kind`digest`digestAlgorithm`identityAlgorithm`frameworkVersion`revision`shard`files`tests!(
        .tst.MANIFEST_SCHEMA_VERSION;"resq-execution-manifest";digest;
        "md5-source-inventory-v1";"resq-test-id-v1";
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
    events,:.tst.oneEventTable .tst.eventRecord[sequence;"manifest.published";runId;manifest`digest;runId;started;manifest];
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
        events,:.tst.oneEventTable .tst.eventRecord[sequence;"file.started";runId;fileId;runId;started;fileEntry];
        sequence+:1;
        suites:distinct {.tst.toString x`suite} each fileRows;
        si:0;
        while[si<count suites;
            suiteName:suites si;
            suiteId:.tst.manifestSuiteId[filePath;suiteName];
            suiteRows:fileRows where {[name;x].tst.toString[x`suite]~name}[suiteName;] each fileRows;
            events,:.tst.oneEventTable .tst.eventRecord[sequence;"suite.started";runId;suiteId;fileId;started;
                `file`suite`testCount!(filePath;suiteName;"j"$count suiteRows)];
            sequence+:1;
            ti:0;
            while[ti<count suiteRows;
                row:suiteRows ti;
                testId:.tst.toString row`testId;
                identity:`file`suite`description`line`kind`tags!(
                    filePath;suiteName;.tst.toString row`description;"j"$row`line;
                    .tst.toString row`kind;string each (),row`tags);
                events,:.tst.oneEventTable .tst.eventRecord[sequence;"test.started";runId;testId;suiteId;started;identity];
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
                    attemptId:testId,"/attempt/",string attemptNo;
                    events,:.tst.oneEventTable .tst.eventRecord[sequence;"attempt.started";runId;attemptId;testId;started;
                        enlist[`attempt]!enlist attemptNo];
                    sequence+:1;
                    events,:.tst.oneEventTable .tst.eventRecord[sequence;"attempt.finished";runId;attemptId;testId;finished;attempt];
                    sequence+:1;
                    ai+:1];
                cases:.tst.caseRows row`parameterCases;
                ci:0;
                while[ci<count cases;
                    case:cases ci;
                    caseId:$[`caseId in key case;.tst.toString case`caseId;
                        "case_",.tst.stableHash[testId,"\n",string ci,"\n",.Q.s1 case`parameters]];
                    events,:.tst.oneEventTable .tst.eventRecord[sequence;"case.started";runId;caseId;testId;started;
                        `index`parameters!("j"$ci;case`parameters)];
                    sequence+:1;
                    events,:.tst.oneEventTable .tst.eventRecord[sequence;"case.finished";runId;caseId;testId;finished;case];
                    sequence+:1;
                    ci+:1];
                bench:row`benchmark;
                if[(99h=type bench) and count bench;
                    events,:.tst.oneEventTable .tst.eventRecord[sequence;"benchmark.finished";runId;testId;testId;finished;bench];
                    sequence+:1];
                testDiags:.tst.caseRows row`diagnostics;
                di:0;
                while[di<count testDiags;
                    diagnostic:testDiags di;
                    diagId:"diagnostic_",.tst.stableHash[testId,"\n",string di,"\n",.Q.s1 diagnostic];
                    events,:.tst.oneEventTable .tst.eventRecord[sequence;"diagnostic.recorded";runId;diagId;testId;finished;diagnostic];
                    sequence+:1;
                    di+:1];
                events,:.tst.oneEventTable .tst.eventRecord[sequence;"test.finished";runId;testId;suiteId;finished;
                    `status`duration`durationSeconds`assertsRun`attempts`retried`flaky`caseId!(
                        .tst.toString row`status;string row`time;
                        .tst.output.jsonDurationSeconds row`time;
                        "j"$row`assertsRun;"j"$row`attempts;row`retried;row`flaky;.tst.toString row`caseId)];
                sequence+:1;
                ti+:1];
            events,:.tst.oneEventTable .tst.eventRecord[sequence;"suite.finished";runId;suiteId;fileId;finished;
                .tst.resultStatusSummary suiteRows];
            sequence+:1;
            si+:1];
        events,:.tst.oneEventTable .tst.eventRecord[sequence;"file.finished";runId;fileId;runId;finished;
            .tst.resultStatusSummary fileRows];
        sequence+:1;
        fi+:1];
    coverage:runModel`coverage;
    if[(99h=type coverage) and count coverage;
        events,:.tst.oneEventTable .tst.eventRecord[sequence;"coverage.finished";runId;"coverage";runId;finished;coverage];
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
    .tst.oneResultTable base
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
