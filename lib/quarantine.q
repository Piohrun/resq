\d .tst

/ Evidence-based flake history and explicit quarantine policy. History is an
/ observation cache; only the separately reviewed manifest is authoritative.
.tst.FLAKE_HISTORY_VERSION:1;
.tst.QUARANTINE_MANIFEST_VERSION:1;
.tst.FLAKE_PROPOSAL_VERSION:1;

.tst.flakeConfiguredPath:{[setting;fallback;sharded]
    configured:.tst.toString @[get;` sv (`.tst.app;setting);{fallback}];
    base:.tst.toString @[get;`.tst.app.baseDir;{system "cd"}];
    path:$[count[configured] and "/"=first configured;
        .utl.normalizePath configured;
        .utl.normalizePath base,"/",configured];
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
    `status`updatedAt`tests!(statusName;"";())
 };

.tst.emptyQuarantineManifest:{[statusName]
    `status`updatedAt`entries!(statusName;"";())
 };

.tst.jsonObjectRows:{[items]
    if[0=count items;:()];
    if[98h=type items;:items];
    if[99h=type items;:enlist items];
    if[not 0h=type items;:()];
    items where 99h=type each items
 };

.tst.readVersionedJson:{[path;expectedVersion;required]
    if[not .utl.pathExists path;:`status`document!(`missing;()!())];
    lines:@[read0;hsym `$path;{()}];
    if[0=count lines;:`status`document!(`invalid;()!())];
    decoded:@[{[text](0b;.j.k text)};"\n" sv lines;{[err](1b;err)}];
    if[first decoded;:`status`document!(`invalid;()!())];
    doc:last decoded;
    if[not 99h=type doc;:`status`document!(`invalid;()!())];
    if[not all required in key doc;:`status`document!(`invalid;doc)];
    if[expectedVersion<>"j"$doc`schemaVersion;:`status`document!(`unsupported;doc)];
    `status`document!(`ok;doc)
 };

.tst.validObservation:{[obs]
    if[not 99h=type obs;:0b];
    all `runId`occurredAt`status`attempts`flaky in key obs
 };

.tst.validHistoryEntry:{[entry]
    if[not 99h=type entry;:0b];
    if[not all `testId`observations in key entry;:0b];
    observations:.tst.jsonObjectRows entry`observations;
    all .tst.validObservation each observations
 };

.tst.validQuarantineEntry:{[entry]
    if[not 99h=type entry;:0b];
    all `testId`owner`reason`evidence`issue`createdAt`expiresAt in key entry
 };

.tst.loadFlakeState:{[]
    hpath:.tst.flakeHistoryPath[];
    rawHistory:.tst.readVersionedJson[hpath;.tst.FLAKE_HISTORY_VERSION;`schemaVersion`kind`tests];
    history:.tst.emptyFlakeHistory rawHistory`status;
    if[`ok~rawHistory`status;
        hdoc:rawHistory`document;
        entries:.tst.jsonObjectRows hdoc`tests;
        $[("resq-flake-history"~.tst.toString hdoc`kind) and all .tst.validHistoryEntry each entries;
          history:`status`updatedAt`tests!(`ok;$[`updatedAt in key hdoc;.tst.toString hdoc`updatedAt;""];entries);
          history:.tst.emptyFlakeHistory `invalid]];
    mpath:.tst.quarantineManifestPath[];
    rawManifest:.tst.readVersionedJson[mpath;.tst.QUARANTINE_MANIFEST_VERSION;`schemaVersion`kind`entries];
    manifest:.tst.emptyQuarantineManifest rawManifest`status;
    if[`ok~rawManifest`status;
        mdoc:rawManifest`document;
        mentries:.tst.jsonObjectRows mdoc`entries;
        $[("resq-quarantine-manifest"~.tst.toString mdoc`kind) and all .tst.validQuarantineEntry each mentries;
          manifest:`status`updatedAt`entries!(`ok;$[`updatedAt in key mdoc;.tst.toString mdoc`updatedAt;""];mentries);
          manifest:.tst.emptyQuarantineManifest `invalid]];
    .tst.app.flakeHistory:history;
    .tst.app.quarantineManifest:manifest;
    .tst.app.flakeStateApplied:0b;
    if[(history`status) in `invalid`unsupported;
        .tst.recordDiagnostic[`flake;`warning;`history;
            "Ignoring malformed or unsupported flake history";
            `path`status!(.tst.repoRelativePath hpath;history`status)]];
    if[(manifest`status) in `invalid`unsupported;
        .tst.recordDiagnostic[`quarantine;`warning;`manifest;
            "Ignoring malformed or unsupported quarantine manifest; every test remains blocking";
            `path`status!(.tst.repoRelativePath mpath;manifest`status)]];
    `history`manifest!(history;manifest)
 };

.tst.flakeFindById:{[rows;testId]
    if[0=count rows;:()!()];
    ids:.tst.toString each {x`testId} each rows;
    at:where ids~\:.tst.toString testId;
    $[count at;rows first at;()!()]
 };

.tst.flakeHistoryEntry:{[testId]
    state:@[get;`.tst.app.flakeHistory;{.tst.emptyFlakeHistory `missing}];
    .tst.flakeFindById[state`tests;testId]
 };

.tst.quarantineEntry:{[testId]
    state:@[get;`.tst.app.quarantineManifest;{.tst.emptyQuarantineManifest `missing}];
    .tst.flakeFindById[state`entries;testId]
 };

.tst.quarantineExpired:{[entry]
    if[not 99h=type entry;:0b];
    if[not `expiresAt in key entry;:0b];
    expires:.tst.toString entry`expiresAt;
    if[0=count expires;:0b];
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
    testId:.tst.toString row`testId;
    evidence:.tst.flakeEvidence[testId;row];
    manifestEntry:.tst.quarantineEntry testId;
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
        .tst.toString row`testId;
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

.tst.appendFlakeObservations:{[rows]
    historyState:@[get;`.tst.app.flakeHistory;{.tst.emptyFlakeHistory `missing}];
    entries:$[`ok~(historyState`status);historyState`tests;()];
    eligible:rows where .tst.flakeEligibleRow each rows;
    ids:distinct .tst.toString each {x`testId} each eligible;
    window:"j"$@[get;`.tst.app.flakeWindow;20j];
    {[historyEntries;allRows;limit;id]
        priorEntry:.tst.flakeFindById[historyEntries;id];
        obs:$[not 99h=type priorEntry;();
            not `observations in key priorEntry;();
            .tst.jsonObjectRows priorEntry`observations];
        rowIds:.tst.toString each {x`testId} each allRows;
        current:allRows where rowIds~\:id;
        ci:0;
        while[ci<count current;
            obs:.tst.appendObservation[obs;.tst.observationFromRow current ci];
            ci+:1];
        if[count[obs]>limit;obs:(neg limit)#obs];
        `testId`observations!(id;obs)
      }[entries;eligible;window;] each ids
 };

.tst.atomicWriteJson:{[path;doc;kind]
    slash:where path="/";
    dir:$[count slash;(last slash)#path;"."];
    if[0=count dir;dir:"/"];
    .utl.ensureDir dir;
    tmp:path,".tmp.",string .z.i;
    written:.[{[p;text](hsym `$p) 0:enlist text;1b};(tmp;.j.j doc);{[args;err]0b}];
    if[not written;
        .tst.recordDiagnostic[kind;`warning;`persistence;"Unable to write state";
            enlist[`path]!enlist .tst.repoRelativePath path];
        :0b];
    moved:.[{[src;dst]system "mv -f -- ",.utl.shellQuote[src]," ",.utl.shellQuote dst;1b};
        (tmp;path);{[args;err]0b}];
    if[not moved;
        @[hdel;hsym `$tmp;{}];
        .tst.recordDiagnostic[kind;`warning;`persistence;"Unable to atomically publish state";
            enlist[`path]!enlist .tst.repoRelativePath path]];
    moved
 };

.tst.persistFlakeState:{[]
    if[1b~@[get;`.tst.app.isolateChild;0b];:1b];
    if[1b~@[get;`.tst.app.describeOnly;0b];:1b];
    rows:.tst.resultRows .resq.state.results;
    eligible:rows where .tst.flakeEligibleRow each rows;
    if[0=count eligible;:1b];
    entries:.tst.appendFlakeObservations eligible;
    now:.tst.isoTimestamp .z.p;
    hdoc:`schemaVersion`kind`updatedAt`window`tests!(
        .tst.FLAKE_HISTORY_VERSION;"resq-flake-history";now;
        "j"$@[get;`.tst.app.flakeWindow;20j];entries);
    ok:.tst.atomicWriteJson[.tst.flakeHistoryPath[];hdoc;`flake];
    if[1b~@[get;`.tst.app.flakeProposalsEnabled;0b];
        proposals:@[get;`.tst.app.flakeProposals;{()}];
        pdoc:`schemaVersion`kind`generatedAt`historyPath`manifestPath`proposals!(
            .tst.FLAKE_PROPOSAL_VERSION;"resq-quarantine-proposals";now;
            .tst.repoRelativePath .tst.flakeHistoryPath[];
            .tst.repoRelativePath .tst.quarantineManifestPath[];proposals);
        ok:ok and .tst.atomicWriteJson[.tst.flakeProposalPath[];pdoc;`flake]];
    ok
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
