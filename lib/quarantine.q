\d .tst

/ Evidence-based flake history and explicit quarantine policy. History is an
/ observation cache; only the separately reviewed manifest is authoritative.
.tst.FLAKE_HISTORY_VERSION:2;
.tst.QUARANTINE_MANIFEST_VERSION:2;
.tst.FLAKE_PROPOSAL_VERSION:2;
.tst.FLAKE_HISTORY_MAX_TESTS:100000j;
.tst.FLAKE_HISTORY_UNSEEN_LIMIT:20j;
.tst.FLAKE_HISTORY_UNPLACED_AGE:30D;

.tst.flakeConfiguredPath:{[setting;fallback;sharded]
    configured:.tst.toString @[get;` sv (`.tst.app;setting);{fallback}];
    base:.tst.toString @[get;`.tst.app.baseDir;{system "cd"}];
    path:$[count[configured] and "/"=first configured;
        .resq.util.normalizePath configured;
        .resq.util.normalizePath base,"/",configured];
    shardCount:"j"$@[get;`.tst.app.shardCount;1j];
    shardIndex:"j"$@[get;`.tst.app.shardIndex;0j];
    if[sharded and shardCount>1;
        suffix:".shard-",string[shardIndex],"-of-",string shardCount;
        path:$[path like "*.json";((count[path]-5)#path),suffix,".json";path,suffix]];
    path
 };

.tst.flakeHistoryPath:{[].tst.flakeConfiguredPath[`flakeHistoryFile;".resq/flake-history.json";1b]};
.tst.quarantineManifestPath:{[].tst.flakeConfiguredPath[`quarantineFile;".resq/quarantine.json";0b]};
.tst.flakeProposalPath:{[].tst.flakeConfiguredPath[`flakeProposalFile;".resq/quarantine-proposals.json";1b]};

.tst.emptyFlakeHistory:{[statusName]
    `status`diagnostic`updatedAt`tests!(statusName;"";"";())
 };

.tst.emptyQuarantineManifest:{[statusName]
    `status`diagnostic`updatedAt`entries!(statusName;"";"";())
 };

.tst.jsonObjectRows:{[items]
    if[0=count items;:()];
    if[98h=type items;:items];
    if[99h=type items;:enlist items];
    if[not 0h=type items;:()];
    items where 99h=type each items
 };

.tst.readVersionedJson:{[path;expectedVersion;required]
    result:{[statusName;document;diagnostic]
        `status`document`diagnostic!(statusName;document;diagnostic)};
    if[not .resq.util.pathExists path;:result[`missing;()!();"file does not exist"]];
    readResult:@[{[p](0b;read0 hsym `$p)};path;{[err](1b;.tst.toString err)}];
    if[first readResult;:result[`invalid;()!();"read failed: ",last readResult]];
    lines:last readResult;
    if[0=count lines;:result[`invalid;()!();"file is empty"]];
    decoded:@[{[text](0b;.j.k text)};"\n" sv lines;{[err](1b;err)}];
    if[first decoded;:result[`invalid;()!();"JSON parse failed: ",.tst.toString last decoded]];
    doc:last decoded;
    if[not 99h=type doc;:result[`invalid;()!();"JSON root must be an object"]];
    if[not `schemaVersion in key doc;
        :result[`invalid;doc;"missing required key(s): schemaVersion"]];
    schema:doc`schemaVersion;
    if[not (type schema) in -5 -6 -7 -8 -9h;
        :result[`invalid;doc;"schemaVersion must be an integral JSON number"]];
    converted:@["j"$;schema;{0Nj}];
    if[null converted;:result[`invalid;doc;"schemaVersion is not representable"]];
    if[not ("f"$converted)="f"$schema;
        :result[`invalid;doc;"schemaVersion must be integral"]];
    if[expectedVersion<>converted;
        :result[`unsupported;doc;"unsupported schemaVersion ",string converted]];
    missing:required except key doc;
    if[count missing;:result[`invalid;doc;"missing required key(s): ","," sv string missing]];
    result[`ok;doc;""]
 };

.tst.requireIdentityDocument:{[raw]
    if[not `ok~raw`status;:raw];
    doc:raw`document;
    if[not all `identityAlgorithm`identityCodec in key doc;
        raw[`status]:`unsupported;
        raw[`diagnostic]:"identity metadata is missing; migrate or rebuild the state";
        :raw];
    if[not .tst.identityDocumentMatches doc;
        raw[`status]:`unsupported;
        raw[`diagnostic]:"identity algorithm or codec does not match this runtime"];
    raw
 };

.tst.archiveUnsupportedIdentityState:{[raw;path]
    if[not `unsupported~raw`status;:raw];
    archive:.tst.archiveIdentityState path;
    raw[`diagnostic]:raw[`diagnostic],$[count archive;
        "; archived at ",.tst.repoRelativePath archive;
        "; unable to archive incompatible state"];
    if[count archive;
        .tst.noteIdentityState .tst.repoRelativePath[path],
            " was written by another q runtime or resQ identity generation; kept as ",
            .tst.repoRelativePath archive];
    raw
 };

.tst.validJsonText:{[x]10h=type x};

.tst.validJsonLong:{[x;minimum]
    if[not (type x) in -5 -6 -7 -8 -9h;:0b];
    converted:@["j"$;x;{0Nj}];
    if[null converted;:0b];
    (("f"$converted)="f"$x) and converted>=minimum
 };

.tst.validJsonObjectRows:{[items]
    if[98h=type items;:1b];
    if[0=count items;:0h=type items];
    (0h=type items) and all 99h=type each items
 };

.tst.validObservation:{[obs]
    if[not 99h=type obs;:0b];
    if[not all `runId`occurredAt`status`attempts`flaky in key obs;:0b];
    (.tst.validJsonText obs`runId) and
        (.tst.validJsonText obs`occurredAt) and
        (.tst.validJsonText obs`status) and
        ((obs`status) in ("pass";"fail";"error";"skip";"pending")) and
        .tst.validJsonLong[obs`attempts;1j] and -1h=type obs`flaky
 };

/ .j.k decodes an array of uniform objects as a table. When its columns have
/ the plain decoded types, check them column-wise: history is validated on
/ every run and holds up to flakeWindow observations for every known test.
/ Anything else takes the per-row path, which defines the semantics.
.tst.validObservationRows:{[obs]
    if[98h=type obs;
        c:cols obs;
        if[all `runId`occurredAt`status`attempts`flaky in c;
            texts:obs`runId`occurredAt`status;
            attempts:obs`attempts;
            if[(all 0h=type each texts) and (1h=type obs`flaky) and (type attempts) within 5 9h;
                if[not all 10h=raze type each/: texts;:0b];
                if[not all (obs`status) in ("pass";"fail";"error";"skip";"pending");:0b];
                converted:"j"$attempts;
                :all (not null converted) and (("f"$converted)="f"$attempts) and converted>=1j]]];
    all .tst.validObservation each .tst.jsonObjectRows obs
 };

.tst.validHistoryEntry:{[entry]
    if[not 99h=type entry;:0b];
    if[not all `testId`observations in key entry;:0b];
    if[not .tst.validJsonText entry`testId;:0b];
    if[0=count entry`testId;:0b];
    if[not .tst.validJsonObjectRows entry`observations;:0b];
    if[`unseenCompleteRuns in key entry;
        if[not .tst.validJsonLong[entry`unseenCompleteRuns;0j];:0b]];
    if[`file in key entry;
        if[not type[entry`file] in 10 -10h;:0b]];
    .tst.validObservationRows entry`observations
 };

.tst.validQuarantineEntry:{[entry]
    if[not 99h=type entry;:0b];
    required:`testId`owner`reason`evidence`issue`createdAt`expiresAt;
    if[not all required in key entry;:0b];
    if[not all .tst.validJsonText each entry required except `evidence;:0b];
    / "Requires" means filled in. The proposal file suggests entries with
    / empty owner, reason, issue and expiry for a person to complete; pasted
    / into the manifest as they are, they were accepted, and the empty expiry
    / never expired.
    if[any 0=count each entry required except `evidence;:0b];
    99h=type entry`evidence
 };

.tst.loadFlakeState:{[]
    hpath:.tst.flakeHistoryPath[];
    rawHistory:.tst.readVersionedJson[hpath;.tst.FLAKE_HISTORY_VERSION;`schemaVersion`identityAlgorithm`identityCodec`kind`tests];
    rawHistory:.tst.requireIdentityDocument rawHistory;
    rawHistory:.tst.archiveUnsupportedIdentityState[rawHistory;hpath];
    / A workspace used by two q runtimes: take up this runtime's own history
    / where the other one left it.
    if[(`unsupported~rawHistory`status) and .tst.restoreIdentityState hpath;
        rawHistory:.tst.requireIdentityDocument
            .tst.readVersionedJson[hpath;.tst.FLAKE_HISTORY_VERSION;`schemaVersion`identityAlgorithm`identityCodec`kind`tests]];
    history:.tst.emptyFlakeHistory rawHistory`status;
    history[`diagnostic]:rawHistory`diagnostic;
    if[`ok~rawHistory`status;
        hdoc:rawHistory`document;
        semanticOk:.tst.validJsonText[hdoc`kind] and
            "resq-flake-history"~hdoc`kind;
        semanticOk:semanticOk and .tst.validJsonObjectRows hdoc`tests;
        entries:$[semanticOk;.tst.jsonObjectRows hdoc`tests;()];
        semanticOk:semanticOk and all .tst.validHistoryEntry each entries;
        ids:$[semanticOk;{x`testId} each entries;()];
        semanticOk:semanticOk and (count ids)=count distinct ids;
        if[semanticOk;
            history:`status`diagnostic`updatedAt`tests!(
                `ok;"";$[`updatedAt in key hdoc;.tst.toString hdoc`updatedAt;""];entries)];
        if[not semanticOk;
            history:.tst.emptyFlakeHistory `invalid;
            history[`diagnostic]:"history kind, row types, or execution IDs are invalid"]];
    mpath:.tst.quarantineManifestPath[];
    rawManifest:.tst.readVersionedJson[mpath;.tst.QUARANTINE_MANIFEST_VERSION;`schemaVersion`identityAlgorithm`identityCodec`kind`entries];
    rawManifest:.tst.requireIdentityDocument rawManifest;
    / The manifest is policy that people write and commit. It is never moved
    / or changed here: one run under another q runtime used to rename it away,
    / and every later run then failed without a word on the console. A
    / manifest from another identity generation is ignored where it is, so
    / its quarantines do not apply (the run stays blocking), and said so.
    if[`unsupported~rawManifest`status;
        rawManifest[`diagnostic]:rawManifest[`diagnostic],"; left in place and ignored";
        -1 "WARNING: quarantine manifest ",.tst.repoRelativePath[mpath],
            " was written for ",.tst.identityGenerationLabel[rawManifest`document],
            "; this run is ",.tst.currentIdentityGenerationLabel[],
            ". It is left unchanged and ignored: its quarantines do not apply.",
            " See docs/IDENTITY.md to migrate it."];
    manifest:.tst.emptyQuarantineManifest rawManifest`status;
    manifest[`diagnostic]:rawManifest`diagnostic;
    if[`ok~rawManifest`status;
        mdoc:rawManifest`document;
        manifestOk:.tst.validJsonText[mdoc`kind] and
            "resq-quarantine-manifest"~mdoc`kind;
        manifestOk:manifestOk and .tst.validJsonObjectRows mdoc`entries;
        mentries:$[manifestOk;.tst.jsonObjectRows mdoc`entries;()];
        manifestOk:manifestOk and all .tst.validQuarantineEntry each mentries;
        mids:$[manifestOk;{x`testId} each mentries;()];
        manifestOk:manifestOk and (count mids)=count distinct mids;
        if[manifestOk;
            manifest:`status`diagnostic`updatedAt`entries!(
                `ok;"";$[`updatedAt in key mdoc;.tst.toString mdoc`updatedAt;""];mentries)];
        if[not manifestOk;
            manifest:.tst.emptyQuarantineManifest `invalid;
            manifest[`diagnostic]:"manifest kind, row types, or test IDs are invalid, or an entry has an empty owner, reason, issue, createdAt or expiresAt";
            -1 "WARNING: quarantine manifest ",.tst.repoRelativePath[mpath],
                " is not valid (",manifest[`diagnostic],
                "). It is ignored: its quarantines do not apply."]];
    .tst.app.flakeHistory:history;
    .tst.app.quarantineManifest:manifest;
    .tst.app.flakeStateApplied:0b;
    if[(history`status) in `invalid`unsupported;
            .tst.recordDiagnostic[`flake;`warning;`history;
            "Ignoring malformed or unsupported flake history: ",history`diagnostic;
            `path`status`diagnostic!(.tst.repoRelativePath hpath;history`status;history`diagnostic)]];
    if[(manifest`status) in `invalid`unsupported;
        .tst.recordDiagnostic[`quarantine;`warning;`manifest;
            "Ignoring malformed or unsupported quarantine manifest; every test remains blocking: ",manifest`diagnostic;
            `path`status`diagnostic!(.tst.repoRelativePath mpath;manifest`status;manifest`diagnostic)]];
    `history`manifest!(history;manifest)
 };

/ Lookups run once per executed test against the same history and manifest
/ rows, so a linear scan per lookup made classification and persistence
/ quadratic in suite size. Keep id indexes for the few most recent id columns.
/ The cache key is the raw testId list, not the rows: history rows carry
/ nested observation tables, and an equal-but-rebuilt history would make every
/ lookup a deep compare. Comparing two equal id columns is a flat string match.
.tst.flakeIdIndexes:();
.tst.flakeIdIndex:{[rows]
    raw:$[98h=type rows;rows`testId;{x`testId} each rows];
    i:0;
    while[i<count .tst.flakeIdIndexes;
        slot:.tst.flakeIdIndexes i;
        if[raw~first slot;
            if[i>0;.tst.flakeIdIndexes:enlist[slot],.tst.flakeIdIndexes _ i];
            :last slot];
        i+:1];
    ids:`$.tst.toString each raw;
    .tst.flakeIdIndexes:4 sublist enlist[(raw;ids)],.tst.flakeIdIndexes;
    ids
 };

.tst.flakeFindById:{[rows;testId]
    if[0=count rows;:()!()];
    at:(.tst.flakeIdIndex rows)?`$.tst.toString testId;
    $[at<count rows;rows at;()!()]
 };

.tst.flakeHistoryEntry:{[testId]
    state:@[get;`.tst.app.flakeHistory;{.tst.emptyFlakeHistory `missing}];
    .tst.flakeFindById[state`tests;testId]
 };

.tst.flakeExecutionId:{[row]
    caseId:$[`caseId in key row;.tst.toString row`caseId;""];
    $[count caseId;caseId;.tst.toString row`testId]
 };

.tst.quarantineEntry:{[testId]
    state:@[get;`.tst.app.quarantineManifest;{.tst.emptyQuarantineManifest `missing}];
    .tst.flakeFindById[state`entries;testId]
 };

.tst.quarantineExpired:{[entry]
    if[not 99h=type entry;:0b];
    if[not `expiresAt in key entry;:0b];
    expires:.tst.toString entry`expiresAt;
    / No date is not "never": an entry without an expiry is not in force.
    if[0=count expires;:1b];
    expiryDate:@[{"D"$x};expires;{0Nd}];
    if[null expiryDate;:1b];
    expiryDate<.z.D
 };

.tst.activeQuarantine:{[testId]
    entry:.tst.quarantineEntry testId;
    if[not 99h=type entry;:0b];
    if[0=count entry;:0b];
    not .tst.quarantineExpired entry
 };

.tst.observationFromRow:{[row]
    runMeta:@[get;`.tst.app.runMetadata;{()!()}];
    `runId`occurredAt`status`attempts`flaky!(
        $[`id in key runMeta;.tst.toString runMeta`id;""];
        .tst.isoTimestamp .z.p;
        .tst.toString .tst.normalizeResultStatus row`status;
        "j"$row`attempts;
        1b~row`flaky)
 };

.tst.appendObservation:{[observations;observation]
    if[98h=type observations;
        names:cols observations;
        columns:{[table;obs;k](table k),enlist obs k}[observations;observation;] each names;
        :flip names!columns];
    if[0=count observations;:enlist observation];
    observations,enlist observation
 };

.tst.flakeEvidence:{[testId;row]
    entry:.tst.flakeHistoryEntry testId;
    observations:$[not 99h=type entry;();
        not `observations in key entry;();
        .tst.jsonObjectRows entry`observations];
    if[99h=type row;observations:.tst.appendObservation[observations;.tst.observationFromRow row]];
    window:"j"$@[get;`.tst.app.flakeWindow;20j];
    if[count[observations]>window;observations:(neg window)#observations];
    statuses:.tst.toString each {x`status} each observations;
    flakes:sum {1b~x`flaky} each observations;
    `observations`passes`failures`flakes!(
        "j"$count observations;
        "j"$sum statuses~\:"pass";
        "j"$sum statuses in ("fail";"error");
        "j"$flakes)
 };

.tst.flakeClassification:{[row]
    executionId:.tst.flakeExecutionId row;
    evidence:.tst.flakeEvidence[executionId;row];
    manifestEntry:.tst.quarantineEntry executionId;
    inManifest:(99h=type manifestEntry) and 0<count manifestEntry;
    expired:inManifest and .tst.quarantineExpired manifestEntry;
    minRuns:"j"$@[get;`.tst.app.flakeEvidenceMin;3j];
    minFailures:"j"$@[get;`.tst.app.flakeFailureMin;2j];
    enough:(evidence`observations)>=minRuns;
    suspect:enough and ((evidence`failures)>=minFailures) and
        (((evidence`passes)>0) or (evidence`flakes)>0);
    state:$[inManifest and not expired;`quarantined;
        expired;`expired;
        not enough;`insufficient;
        suspect;`suspect;
        `healthy];
    nonBlocking:(state~`quarantined) and
        1b~@[get;`.tst.app.quarantineNonBlocking;0b];
    base:`schemaVersion`state`active`nonBlocking`observations`passes`failures`flakes,
        `owner`reason`evidence`issue`createdAt`expiresAt;
    base!(.tst.QUARANTINE_MANIFEST_VERSION;state;state~`quarantined;nonBlocking;
        evidence`observations;evidence`passes;evidence`failures;evidence`flakes;
        $[inManifest;.tst.toString manifestEntry`owner;""];
        $[inManifest;.tst.toString manifestEntry`reason;""];
        $[inManifest;manifestEntry`evidence;()!()];
        $[inManifest;.tst.toString manifestEntry`issue;""];
        $[inManifest;.tst.toString manifestEntry`createdAt;""];
        $[inManifest;.tst.toString manifestEntry`expiresAt;""])
 };

.tst.flakeEligibleRow:{[row]
    (.tst.toString row`kind) in ("test";"case";"fuzz";"perf")
 };

.tst.annotateFlakeRow:{[row]
    out:.tst.completeResultRow row;
    if[not .tst.flakeEligibleRow out;:out];
    classification:.tst.flakeClassification out;
    / The first observations have no actionable classification. Preserve the
    / aggregate flake count, but do not repeat fourteen empty/default policy
    / fields in JSON, lifecycle payloads, JUnit, and xUnit for every test.
    out[`quarantine]:$[(classification`state)~`insufficient;()!();classification];
    if[(classification`state) in `suspect`quarantined`expired;
        diagnostic:.tst.diagnostic[`flake;
            $[(classification`state)~`healthy;`info;`warning];`classification;
            "Flake state: ",.tst.toString (classification`state);classification];
        existingDiagnostics:(),(out`diagnostics);
        out[`diagnostics]:existingDiagnostics,enlist diagnostic];
    out
 };

.tst.flakeProposalFromRow:{[row]
    qstate:row`quarantine;
    `testId`state`evidence`suggestedEntry!(
        .tst.flakeExecutionId row;
        .tst.toString qstate`state;
        `observations`passes`failures`flakes!(qstate`observations;qstate`passes;qstate`failures;qstate`flakes);
        `testId`owner`reason`evidence`issue`createdAt`expiresAt!(
            .tst.toString row`testId;"";"";
            `observations`passes`failures`flakes!(qstate`observations;qstate`passes;qstate`failures;qstate`flakes);
            "";.tst.isoTimestamp .z.p;""))
 };

.tst.applyFlakeState:{[]
    if[1b~@[get;`.tst.app.flakeStateApplied;0b];:()];
    / Isolated children are execution workers, not flake-policy authorities.
    / The parent owns the merged history, classification, verdict, and durable
    / writes.  Keeping child rows raw also prevents duplicate classification
    / diagnostics when their JSON telemetry is merged back into the parent.
    if[1b~@[get;`.tst.app.isolateChild;0b];
        .tst.app.flakeProposals:();
        .tst.app.flakeStateApplied:1b;
        :()];
    rows:.tst.resultRows .resq.state.results;
    annotated:.tst.annotateFlakeRow each rows;
    .resq.state.results:$[count annotated;flip flip annotated;.tst.emptyResultTable[]];
    suspects:annotated where {[row]
        qstate:row`quarantine;
        $[not 99h=type qstate;0b;
          not `state in key qstate;0b;
          `suspect~qstate`state]
      } each annotated;
    .tst.app.flakeProposals:.tst.flakeProposalFromRow each suspects;
    .tst.app.flakeStateApplied:1b;
    ::
 };

.tst.rowIsNonBlockingQuarantine:{[row]
    if[not `quarantine in key row;:0b];
    qstate:row`quarantine;
    if[not 99h=type qstate;:0b];
    if[not `nonBlocking in key qstate;:0b];
    1b~qstate`nonBlocking
 };

.tst.rowBlocksRun:{[row]
    status:.tst.normalizeResultStatus row`status;
    if[status in `pass`skip`pending;:0b];
    not .tst.rowIsNonBlockingQuarantine row
 };

/ What a run may conclude from not seeing a test. A complete run of
/ tests/test_a.q says nothing about a test in tests/test_b.q: it used to age
/ every test it did not see, 21 runs of one file erased the history of all
/ the others, and one such run emptied the failed list -last-failed reads.
/ State entries therefore name their test file, and a run speaks only for the
/ files it looked at, and for files that are no longer there.

/ The files this run looked at, as state entries name them.
.tst.runScopeFiles:{[]
    distinct .tst.repoRelativePath each @[get;`.tst.app.allDiscoveredFiles;{()}]
 };

.tst.stateFileExists:{[file]
    if[0=count file;:1b];
    root:.resq.util.normalizePath @[get;`.tst.app.baseDir;{system "cd"}];
    .resq.util.pathExists $["/"=first file;file;root,"/",file]
 };

/ The files, of those named, that this run can speak for.
.tst.stateFilesInScope:{[files]
    files:distinct files where 0<count each files;
    looked:.tst.runScopeFiles[];
    seen:files where files in looked;
    other:files where not files in looked;
    seen,other where not .tst.stateFileExists each other
 };

.tst.stateRowFile:{[row]
    .tst.repoRelativePath $[`file in key row;.tst.toString row`file;""]
 };

/ When an entry was last observed; null when that cannot be read.
.tst.flakeLastObserved:{[observations]
    obs:.tst.jsonObjectRows observations;
    if[0=count obs;:0Np];
    text:.tst.toString (last obs)`occurredAt;
    "P"$text where text in "0123456789-:.T"
 };

/ Only an unfiltered, unsharded, completed inventory may age entries that were
/ not observed. Partial evidence is merge-only and can never erase history.
.tst.flakeCompleteInventoryRun:{[rows]
    if[not `completed~@[get;`.tst.app.executionState;`notStarted];:0b];
    if[count .tst.toString @[get;`.tst.app.executionIncompleteReason;""];:0b];
    if[1b~@[get;`.tst.app.describeOnly;0b];:0b];
    if[1b~@[get;`.tst.app.isolateChild;0b];:0b];
    if[1<"j"$@[get;`.tst.app.shardCount;1j];:0b];
    if[not `all~@[get;`.tst.app.rerunMode;`all];:0b];
    filters:(@[get;`.tst.app.runSpecs;{()}];@[get;`.tst.app.excludeSpecs;{()}];
        @[get;`.tst.app.tagFilter;{()}];@[get;`.tst.app.excludeTagFilter;{()}]);
    if[any 0<count each filters;:0b];
    selected:distinct .tst.toString each
        @[get;`.tst.app.selectedExecutionIds;{()}];
    if[0=count selected;:0b];
    executed:distinct .tst.flakeExecutionId each rows;
    all selected in executed
 };

.tst.appendFlakeObservations:{[rows]
    historyState:@[get;`.tst.app.flakeHistory;{.tst.emptyFlakeHistory `missing}];
    entries:$[`ok~(historyState`status);historyState`tests;()];
    eligible:rows where .tst.flakeEligibleRow each rows;
    rowIds:.tst.flakeExecutionId each eligible;
    ids:distinct rowIds;
    / Group once; re-deriving every row's id per test was quadratic.
    positions:group `$rowIds;
    window:"j"$@[get;`.tst.app.flakeWindow;20j];
    updated:{[historyEntries;allRows;positions;limit;id]
        priorEntry:.tst.flakeFindById[historyEntries;id];
        obs:$[not 99h=type priorEntry;();
            not `observations in key priorEntry;();
            .tst.jsonObjectRows priorEntry`observations];
        current:allRows positions `$id;
        ci:0;
        while[ci<count current;
            obs:.tst.appendObservation[obs;.tst.observationFromRow current ci];
            ci+:1];
        if[count[obs]>limit;obs:(neg limit)#obs];
        `testId`file`observations`unseenCompleteRuns!(id;.tst.stateRowFile first current;obs;0j)
      }[entries;eligible;positions;window;] each ids;
    priorIds:$[count entries;{.tst.toString x`testId} each entries;()];
    unseenIds:priorIds except ids;
    complete:.tst.flakeCompleteInventoryRun eligible;
    preserved:{[historyEntries;limit;id]
        entry:.tst.flakeFindById[historyEntries;id];
        obs:.tst.jsonObjectRows entry`observations;
        if[count[obs]>limit;obs:(neg limit)#obs];
        missed:"j"$$[`unseenCompleteRuns in key entry;entry`unseenCompleteRuns;0j];
        `testId`file`observations`unseenCompleteRuns!(
            id;$[`file in key entry;.tst.toString entry`file;""];obs;missed)
      }[entries;window;] each unseenIds;
    updated:.tst.eventRows updated;
    preserved:.tst.eventRows preserved;
    if[complete and count preserved;
        / Not seen in a complete run: one more step towards being dropped,
        / for a test whose file this run can speak for.
        files:{x`file} each preserved;
        aged:files in .tst.stateFilesInScope files;
        preserved:{[row;age] if[age;row[`unseenCompleteRuns]+:1];row}'[preserved;aged];
        preserved:preserved where {
            (x`unseenCompleteRuns)<=.tst.FLAKE_HISTORY_UNSEEN_LIMIT
        } each preserved;
        / An entry from before files were recorded cannot be placed. It is
        / kept until it has not been observed for a month.
        cutoff:.z.p-.tst.FLAKE_HISTORY_UNPLACED_AGE;
        preserved:preserved where {[cutoff;row]
            if[count row`file;:1b];
            seen:.tst.flakeLastObserved row`observations;
            (null seen) or seen>=cutoff
        }[cutoff] each preserved];
    sortRows:{[items]
        rows:.tst.eventRows items;
        $[0=count rows;rows;rows iasc {.tst.toString x`testId} each rows]};
    updated:sortRows updated;
    preserved:sortRows preserved;
    bounded:.tst.FLAKE_HISTORY_MAX_TESTS sublist updated,preserved;
    sortRows bounded
 };

/ resQ's default state directory is <project>/.resq. Flake history, last-run
/ selection and quarantine proposals are run-to-run caches, so the directory
/ ignores itself in git the way .pytest_cache does: a first run in a checkout
/ leaves `git status` clean. quarantine.json is the reviewed manifest and stays
/ visible so it can be committed. Only a directory named .resq gets the file,
/ and an existing .gitignore there is never replaced.
.tst.STATE_DIR_GITIGNORE:(
    "# Written by resQ: run-to-run caches stay out of version control.";
    "# quarantine.json is the reviewed quarantine manifest; commit it.";
    enlist "*";
    "!quarantine.json");
.tst.ensureStateDir:{[dir]
    .resq.util.ensureDir dir;
    if[not ".resq"~last "/" vs .resq.util.normalizePath dir;:dir];
    ignore:dir,"/.gitignore";
    if[.resq.util.pathExists ignore;:dir];
    @[{(hsym `$x) 0: .tst.STATE_DIR_GITIGNORE};ignore;{[e]}];
    dir
 };

.tst.atomicWriteJson:{[path;doc;kind]
    slash:where path="/";
    dir:$[count slash;(last slash)#path;"."];
    if[0=count dir;dir:"/"];
    .tst.ensureStateDir dir;
    tmp:path,".tmp.",string .z.i;
    written:.[{[p;text](hsym `$p) 0:enlist text;1b};(tmp;.tst.output.strictJson doc);{[err]0b}];
    if[not written;
        .tst.recordDiagnostic[kind;`warning;`persistence;"Unable to write state";
            enlist[`path]!enlist .tst.repoRelativePath path];
        :0b];
    moved:.[{[src;dst]system "mv -f -- ",.resq.util.shellQuote[src]," ",.resq.util.shellQuote dst;1b};
        (tmp;path);{[err]0b}];
    if[not moved;
        @[hdel;hsym `$tmp;{}];
        .tst.recordDiagnostic[kind;`warning;`persistence;"Unable to atomically publish state";
            enlist[`path]!enlist .tst.repoRelativePath path]];
    moved
 };

.tst.readFlakeHistoryAt:{[path]
    raw:.tst.readVersionedJson[path;.tst.FLAKE_HISTORY_VERSION;`schemaVersion`identityAlgorithm`identityCodec`kind`tests];
    raw:.tst.requireIdentityDocument raw;
    state:.tst.emptyFlakeHistory raw`status;
    state[`diagnostic]:raw`diagnostic;
    if[not `ok~raw`status;:state];
    doc:raw`document;
    valid:.tst.validJsonText[doc`kind] and "resq-flake-history"~doc`kind;
    valid:valid and .tst.validJsonObjectRows doc`tests;
    entries:$[valid;.tst.jsonObjectRows doc`tests;()];
    valid:valid and all .tst.validHistoryEntry each entries;
    ids:$[valid;{x`testId} each entries;()];
    valid:valid and (count ids)=count distinct ids;
    if[not valid;
        state:.tst.emptyFlakeHistory `invalid;
        state[`diagnostic]:"history kind, row types, or execution IDs are invalid";
        :state];
    `status`diagnostic`updatedAt`tests!(
        `ok;"";$[`updatedAt in key doc;.tst.toString doc`updatedAt;""];entries)
 };

/ A short-lived directory lock makes the read/merge/atomic-publish sequence a
/ single-writer operation. The bounded wait reclaims only a lock whose recorded
/ PID no longer exists; otherwise this run leaves the cache untouched.
.tst.acquireFlakeHistoryLock:{[path]
    slash:where path="/";
    dir:$[count slash;(last slash)#path;"."];
    if[0=count dir;dir:"/"];
    .tst.ensureStateDir dir;
    lock:path,".lock";
    quoted:.resq.util.shellQuote lock;
    / 0 = acquired, 75 = held by a live writer, 73 = cannot be created at all
    / (read-only checkout, missing or foreign-owned state directory). Without
    / the 73 exit an unwritable directory spun the full 5 s busy-wait on every
    / run and was then misreported as a live writer.
    cmd:"lock=",quoted,"; i=0; while ! mkdir \"$lock\" 2>/dev/null; do ",
        "if [ ! -d \"$lock\" ]; then mkdir \"$lock\" 2>/dev/null && break; ",
        "if [ ! -d \"$lock\" ]; then echo 73; exit 0; fi; fi; ",
        "owner=''; if [ -f \"$lock/pid\" ]; then read owner < \"$lock/pid\" || true; fi; ",
        "if [ -n \"$owner\" ] && ! kill -0 \"$owner\" 2>/dev/null; then rm -rf -- \"$lock\"; continue; fi; ",
        "i=$((i+1)); if [ \"$i\" -ge 100 ]; then echo 75; exit 0; fi; sleep 0.05; done; ",
        "echo ",string[.z.i]," > \"$lock/pid\"; echo 0";
    lines:@[system;"sh -c ",.resq.util.shellQuote cmd;{[err]enlist "75"}];
    $[count lines;"j"$"J"$last lines;75j]
 };

.tst.releaseFlakeHistoryLock:{[path]
    lock:path,".lock";
    ownerPath:lock,"/pid";
    owner:@[read0;hsym `$ownerPath;{()}];
    if[(count owner) and (last owner)~string .z.i;
        @[hdel;hsym `$ownerPath;{()}];
        @[system;"rmdir ",.resq.util.shellQuote lock;{[err]()}]];
    ::
 };

.tst.persistFlakeState:{[]
    if[1b~@[get;`.tst.app.isolateChild;0b];:1b];
    if[1b~@[get;`.tst.app.describeOnly;0b];:1b];
    rows:.tst.resultRows .resq.state.results;
    eligible:rows where .tst.flakeEligibleRow each rows;
    if[0=count eligible;:1b];
    path:.tst.flakeHistoryPath[];
    lockStatus:.tst.acquireFlakeHistoryLock path;
    if[not 0j~lockStatus;
        .tst.recordDiagnostic[`flake;`warning;`persistence;
            $[73j~lockStatus;
                "Unable to create the flake history lock (is the state directory writable?); current evidence was not published";
                "Flake history is locked by another live writer; current evidence was not published"];
            enlist[`path]!enlist .tst.repoRelativePath path];
        :0b];
    outcome:.[{[eligible;path]
        latest:.tst.readFlakeHistoryAt path;
        if[`unsupported~latest`status;
            archive:.tst.archiveIdentityState path;
            if[0=count archive;:(0b;0b;"refusing to overwrite incompatible identity history")];
            .tst.recordDiagnostic[`flake;`warning;`persistence;
                "Archived incompatible identity history before rebuilding";
                `path`archive!(.tst.repoRelativePath path;.tst.repoRelativePath archive)]];
        .tst.app.flakeHistory:latest;
        entries:.tst.appendFlakeObservations eligible;
        now:.tst.isoTimestamp .z.p;
        hdoc:`schemaVersion`identityAlgorithm`identityCodec`kind`updatedAt`window`retention`tests!(
            .tst.FLAKE_HISTORY_VERSION;.tst.IDENTITY_ALGORITHM;.tst.identityCodecMetadata[];
            "resq-flake-history";now;
            "j"$@[get;`.tst.app.flakeWindow;20j];
            `maxTests`unseenCompleteRuns!(
                .tst.FLAKE_HISTORY_MAX_TESTS;.tst.FLAKE_HISTORY_UNSEEN_LIMIT);
            entries);
        ok:.tst.atomicWriteJson[path;hdoc;`flake];
        if[ok;
            .tst.app.flakeHistory:`status`diagnostic`updatedAt`tests!(
                `ok;"";now;entries)];
        if[1b~@[get;`.tst.app.flakeProposalsEnabled;0b];
            proposals:@[get;`.tst.app.flakeProposals;{()}];
            pdoc:`schemaVersion`identityAlgorithm`identityCodec`kind`generatedAt`historyPath`manifestPath`proposals!(
                .tst.FLAKE_PROPOSAL_VERSION;.tst.IDENTITY_ALGORITHM;.tst.identityCodecMetadata[];
                "resq-quarantine-proposals";now;
                .tst.repoRelativePath path;
                .tst.repoRelativePath .tst.quarantineManifestPath[];proposals);
            ok:ok and .tst.atomicWriteJson[.tst.flakeProposalPath[];pdoc;`flake]];
        (0b;ok;"")
      };(eligible;path);{[err](1b;0b;.tst.toString err)}];
    .tst.releaseFlakeHistoryLock path;
    if[first outcome;
        .tst.recordDiagnostic[`flake;`warning;`persistence;
            "Unable to merge flake history: ",last outcome;
            enlist[`path]!enlist .tst.repoRelativePath path]];
    outcome 1
 };

.tst.flakeMetadata:{[]
    rows:.tst.resultRows .resq.state.results;
    states:{[row]
        qstate:$[`quarantine in key row;row`quarantine;()!()];
        $[.tst.flakeEligibleRow[row] and ((not 99h=type qstate) or not `state in key qstate);"insufficient";
          not 99h=type qstate;"unclassified";
          not `state in key qstate;"unclassified";
          .tst.toString qstate`state]
      } each rows;
    historyState:@[get;`.tst.app.flakeHistory;{.tst.emptyFlakeHistory `missing}];
    manifestState:@[get;`.tst.app.quarantineManifest;{.tst.emptyQuarantineManifest `missing}];
    out:`schemaVersion`historyPath`historyStatus`manifestPath`manifestStatus!(
        .tst.FLAKE_HISTORY_VERSION;
        .tst.repoRelativePath .tst.flakeHistoryPath[];
        .tst.toString (historyState`status);
        .tst.repoRelativePath .tst.quarantineManifestPath[];
        .tst.toString (manifestState`status));
    out[`nonBlockingEnabled]:1b~@[get;`.tst.app.quarantineNonBlocking;0b];
    out[`evidenceMin]:"j"$@[get;`.tst.app.flakeEvidenceMin;3j];
    out[`failureMin]:"j"$@[get;`.tst.app.flakeFailureMin;2j];
    out[`window]:"j"$@[get;`.tst.app.flakeWindow;20j];
    out[`healthy]:"j"$sum states~\:"healthy";
    out[`suspect]:"j"$sum states~\:"suspect";
    out[`quarantined]:"j"$sum states~\:"quarantined";
    out[`expired]:"j"$sum states~\:"expired";
    out[`insufficient]:"j"$sum states~\:"insufficient";
    out[`proposalCount]:"j"$count @[get;`.tst.app.flakeProposals;{()}];
    out
 };

\d .
::
