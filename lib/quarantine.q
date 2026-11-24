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

/ `tests` holds the entries of a history that was read whole. A history in
/ the one-test-to-a-line layout is kept as its lines instead (lineMode), and
/ an entry is read from its line when it is asked for.
.tst.emptyFlakeHistory:{[statusName]
    `status`diagnostic`updatedAt`tests`lineMode`lines`lineIds`window!(
        statusName;"";"";();0b;();`symbol$();0Wj)
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
    .tst.checkVersionedDocument[last decoded;expectedVersion;required]
 };

.tst.checkVersionedDocument:{[doc;expectedVersion;required]
    result:{[statusName;document;diagnostic]
        `status`document`diagnostic!(statusName;document;diagnostic)};
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
    rawHistory:.tst.requireIdentityDocument .tst.readFlakeHistoryRaw hpath;
    rawHistory:.tst.archiveUnsupportedIdentityState[rawHistory;hpath];
    / A workspace used by two q runtimes: take up this runtime's own history
    / where the other one left it.
    if[(`unsupported~rawHistory`status) and .tst.restoreIdentityState hpath;
        rawHistory:.tst.requireIdentityDocument .tst.readFlakeHistoryRaw hpath];
    history:.tst.flakeStateFromRaw rawHistory;
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
    / A history from another identity generation was archived and said so
    / above; a malformed one was ignored without a word.
    if[(history`status) in `invalid`unsupported;
        $[`invalid~history`status;.tst.recordStateWarning[`flake;`history];
            .tst.recordDiagnostic[`flake;`warning;`history]][
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
    .tst.flakeStateEntry[@[get;`.tst.app.flakeHistory;{.tst.emptyFlakeHistory `missing}];testId]
 };

/ One test's entry in a history that was read; ()!() when it has none.
.tst.flakeStateEntry:{[state;testId]
    if[1b~.tst.flakeStateValue[state;`lineMode;0b];
        at:(state`lineIds)?`$.tst.toString testId;
        :$[at<count state`lines;.tst.flakeLineEntry (state`lines) at;()!()]];
    .tst.flakeFindById[state`tests;testId]
 };

.tst.flakeStateValue:{[state;name;default] $[name in key state;state name;default]};

/ ----------------------------------------------------------------------------
/ The history file, one test to a line
/ ----------------------------------------------------------------------------
/ The history holds every observation in the window for every known test,
/ and every run read all of it, rebuilt all of it and wrote all of it: 9,000
/ tests at the default window are 25.7 MB, and a run of one test then took
/ 1.75 s instead of 0.29 s. Almost all of that was parsing, building and
/ freeing entries the run had nothing to say about.
/ .
/ The document is the same (schema v2, the same keys), laid out so that it
/ need not be parsed whole: a first line that ends in "tests":[, then one
/ entry to a line, then ]}. Each entry line starts with its testId and its
/ file. A run reads the lines, parses the entries of the tests it ran and of
/ those it has to age, and writes the others back as the text they were.
/ A history in any other layout (written by an earlier version, or by a
/ tool) is read whole as before and written back in this one.

.tst.FLAKE_LINE_START:"{\"testId\":\"";
.tst.FLAKE_LINE_FILE:"\",\"file\":\"";

/ An entry as its line: the keys in a fixed order, the observations last.
.tst.flakeEntryLine:{[entry]
    .tst.output.strictJson `testId`file`unseenCompleteRuns`observations!(
        .tst.toString entry`testId;
        $[`file in key entry;.tst.toString entry`file;""];
        "j"$$[`unseenCompleteRuns in key entry;entry`unseenCompleteRuns;0j];
        .tst.jsonObjectRows entry`observations)
 };

/ A line as its entry; ()!() when it does not hold one.
.tst.flakeLineEntry:{[line]
    entry:@[.j.k;line;{[err]()!()}];
    if[not .tst.validHistoryEntry entry;:()!()];
    entry[`unseenCompleteRuns]:"j"$$[`unseenCompleteRuns in key entry;entry`unseenCompleteRuns;0j];
    entry
 };

/ The testId of an entry line, read where it stands; "" when it is not there.
.tst.flakeLineId:{[line]
    start:count .tst.FLAKE_LINE_START;
    rest:start _ (start+300) sublist line;
    stop:rest?"\"";
    $[stop<count rest;stop#rest;""]
 };

/ The file of an entry line: read where it stands, or from the parsed entry
/ when the line is not laid out that way.
.tst.flakeLineFile:{[line;id]
    at:(count .tst.FLAKE_LINE_START)+count id;
    rest:at _ (at+4200) sublist line;
    intro:.tst.FLAKE_LINE_FILE;
    stop:$[intro~(count intro)#rest;((count intro)_rest)?"\"";0W];
    text:$[stop<count[rest]-count intro;stop#(count intro)_rest;"\\"];
    if[not "\\" in text;:text];
    entry:.tst.flakeLineEntry line;
    $[`file in key entry;.tst.toString entry`file;""]
 };

/ The lines of a history file in the line layout, taken apart:
/ (in that layout; the document without its tests; entry lines; their IDs).
.tst.splitFlakeHistoryLines:{[lines]
    no:(0b;()!();();`symbol$());
    if[2>count lines;:no];
    opening:"\"tests\":[";
    if[not ("]}"~last lines) and opening~(neg count opening) sublist first lines;:no];
    body:1 _ -1 _ lines;
    if[count body;
        if[any 3>count each body;:no];
        commas:","=last each body;
        if[not (all -1 _ commas) and not last commas;:no];
        body:(neg "j"$commas) _' body;
        if[not all body like .tst.FLAKE_LINE_START,"*";:no];
        if[not all "]}"~/:-2#'body;:no]];
    ids:.tst.flakeLineId each body;
    if[count ids;
        if[(any 0=count each ids) or (count ids)>count distinct ids;:no];
        if["\\" in raze ids;:no]];
    header:@[{[text](1b;.j.k text)};(first lines),"]}";{[err](0b;())}];
    if[not first header;:no];
    if[not 99h=type last header;:no];
    (1b;last header;body;`$ids)
 };

/ Read a history file: `status`document`diagnostic as readVersionedJson
/ gives them, with the entry lines when the file is in the line layout.
.tst.readFlakeHistoryRaw:{[path]
    required:`schemaVersion`identityAlgorithm`identityCodec`kind`tests;
    whole:{[raw] raw,`lineMode`lines`lineIds!(0b;();`symbol$())};
    if[not .resq.util.pathExists path;
        :whole .tst.readVersionedJson[path;.tst.FLAKE_HISTORY_VERSION;required]];
    readResult:@[{[p](1b;read0 hsym `$p)};path;{[err](0b;())}];
    parts:$[first readResult;.tst.splitFlakeHistoryLines last readResult;enlist 0b];
    if[not first parts;
        :whole .tst.readVersionedJson[path;.tst.FLAKE_HISTORY_VERSION;required]];
    raw:.tst.checkVersionedDocument[parts 1;.tst.FLAKE_HISTORY_VERSION;required];
    raw,`lineMode`lines`lineIds!(1b;parts 2;parts 3)
 };

/ What the run works with, from what was read.
.tst.flakeStateFromRaw:{[raw]
    state:.tst.emptyFlakeHistory raw`status;
    state[`diagnostic]:raw`diagnostic;
    if[not `ok~raw`status;:state];
    doc:raw`document;
    invalid:{[]
        state:.tst.emptyFlakeHistory `invalid;
        state[`diagnostic]:"history kind, row types, or execution IDs are invalid";
        state};
    if[not .tst.validJsonText[doc`kind] and "resq-flake-history"~doc`kind;:invalid[]];
    state[`updatedAt]:$[`updatedAt in key doc;.tst.toString doc`updatedAt;""];
    if[raw`lineMode;
        state[`lineMode]:1b;
        state[`lines]:raw`lines;
        state[`lineIds]:raw`lineIds;
        state[`window]:$[`window in key doc;
            $[.tst.validJsonLong[doc`window;1j];"j"$doc`window;0Wj];0Wj];
        :state];
    if[not .tst.validJsonObjectRows doc`tests;:invalid[]];
    entries:.tst.jsonObjectRows doc`tests;
    if[not all .tst.validHistoryEntry each entries;:invalid[]];
    ids:{x`testId} each entries;
    if[not (count ids)=count distinct ids;:invalid[]];
    state[`tests]:entries;
    state
 };

/ The history as entry lines, whichever way it was read:
/ (lines; their IDs; the window they were last cut to).
.tst.flakeHistoryLines:{[state]
    if[not `ok~state`status;:(();`symbol$();0Wj)];
    if[1b~.tst.flakeStateValue[state;`lineMode;0b];
        :(state`lines;state`lineIds;.tst.flakeStateValue[state;`window;0Wj])];
    entries:.tst.jsonObjectRows state`tests;
    (.tst.flakeEntryLine each entries;`$.tst.toString each {x`testId} each entries;0Wj)
 };

/ One more complete run without this test. The line as it should be
/ written, "" to drop it.
.tst.flakeAgeLine:{[line]
    entry:.tst.flakeLineEntry line;
    if[0=count entry;:line];
    entry[`unseenCompleteRuns]+:1;
    $[entry[`unseenCompleteRuns]>.tst.FLAKE_HISTORY_UNSEEN_LIMIT;"";.tst.flakeEntryLine entry]
 };

/ When the entry on a line was last observed, read from the end of the line,
/ where the last observation stands; from the parsed entry when it is not
/ found there. Null when it cannot be told.
.tst.flakeLineLastObserved:{[line]
    ending:-260 sublist line;
    marks:ss[ending;"\"occurredAt\":\""];
    if[0=count marks;
        entry:.tst.flakeLineEntry line;
        :$[count entry;.tst.flakeLastObserved entry`observations;0Np]];
    text:(14+last marks)_ending;
    text:(text?"\"")#text;
    "P"$text where text in "0123456789-:.T"
 };

.tst.flakeTrimLine:{[limit;line]
    entry:.tst.flakeLineEntry line;
    if[0=count entry;:line];
    obs:.tst.jsonObjectRows entry`observations;
    if[limit>=count obs;:line];
    entry[`observations]:(neg limit)#obs;
    .tst.flakeEntryLine entry
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

/ This run's observations merged into the history: the entry lines to write,
/ in ID order. Entries of tests the run did not see are carried as the text
/ they were, unless a complete run has to age them.
.tst.mergeFlakeLines:{[rows]
    historyState:@[get;`.tst.app.flakeHistory;{.tst.emptyFlakeHistory `missing}];
    history:.tst.flakeHistoryLines historyState;
    lines:history 0;
    lineIds:history 1;
    eligible:rows where .tst.flakeEligibleRow each rows;
    rowIds:.tst.flakeExecutionId each eligible;
    ids:distinct rowIds;
    / Group once; re-deriving every row's id per test was quadratic.
    positions:group `$rowIds;
    window:"j"$@[get;`.tst.app.flakeWindow;20j];
    updated:{[lines;lineIds;allRows;positions;limit;id]
        at:lineIds?`$id;
        priorEntry:$[at<count lines;.tst.flakeLineEntry lines at;()!()];
        obs:$[not `observations in key priorEntry;();
            .tst.jsonObjectRows priorEntry`observations];
        current:allRows positions `$id;
        ci:0;
        while[ci<count current;
            obs:.tst.appendObservation[obs;.tst.observationFromRow current ci];
            ci+:1];
        if[count[obs]>limit;obs:(neg limit)#obs];
        .tst.flakeEntryLine `testId`file`observations`unseenCompleteRuns!(
            id;.tst.stateRowFile first current;obs;0j)
      }[lines;lineIds;eligible;positions;window;] each ids;
    keep:where not lineIds in `$ids;
    preserved:lines keep;
    preservedIds:string lineIds keep;
    / Entries last cut to a longer window than this run's.
    if[(count preserved) and window<history 2;
        preserved:.tst.flakeTrimLine[window] each preserved];
    if[(count preserved) and .tst.flakeCompleteInventoryRun eligible;
        / Not seen in a complete run: one more step towards being dropped,
        / for a test whose file this run can speak for.
        files:.tst.flakeLineFile'[preserved;preservedIds];
        aged:where files in .tst.stateFilesInScope files;
        if[count aged;preserved[aged]:.tst.flakeAgeLine each preserved aged];
        / An entry from before files were recorded cannot be placed. It is
        / kept until it has not been observed for a month.
        unplaced:where 0=count each files;
        if[count unplaced;
            seen:.tst.flakeLineLastObserved each preserved unplaced;
            expired:unplaced where (not null seen) and seen<.z.p-.tst.FLAKE_HISTORY_UNPLACED_AGE;
            if[count expired;preserved[expired]:(count expired)#enlist ""]];
        kept:where 0<count each preserved;
        preserved:preserved kept;
        preservedIds:preservedIds kept];
    byId:{[items;itemIds] items iasc itemIds};
    updated:byId[updated;ids];
    preserved:byId[preserved;preservedIds];
    allIds:(asc ids),asc preservedIds;
    bounded:.tst.FLAKE_HISTORY_MAX_TESTS sublist updated,preserved;
    bounded iasc (count bounded)#allIds
 };

/ The merged history as entries.
.tst.appendFlakeObservations:{[rows] .tst.flakeLineEntry each .tst.mergeFlakeLines rows};

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
/ State problems reach the report's diagnostics. They did not reach the
/ console: a run that ignored a corrupt state file, or could not save its
/ own, looked like any other. Each is now also said once, in one line.
.tst.noteStateProblem:{[text]
    said:@[get;`.tst.app.stateNotes;{()}];
    if[any text~/:said;:()];
    .tst.app.stateNotes:said,enlist text;
    if[not 1b~@[get;`.tst.app.passOnly;0b];-1 "resQ: ",text];
 };

/ A state diagnostic that is also said on the console.
.tst.recordStateWarning:{[typeName;phase;message;data]
    .tst.recordDiagnostic[typeName;`warning;phase;message;data];
    .tst.noteStateProblem .tst.toString[message],
        $[`path in key data;" (",.tst.toString[data`path],")";""];
 };

/ Is the directory a state file goes in there, made if need be? A read-only
/ project directory printed mkdir's "Permission denied" and a warning, twice
/ a run. It is said once, and the files that would go there are not tried.
.tst.stateDirReady:{[dir]
    if[.resq.util.tryEnsureDir dir;:1b];
    .tst.noteStateProblem "cannot create the state directory ",.tst.repoRelativePath[dir],
        "; the last-failed list and the flake history are not saved for this run",
        " (-state-file and -flake-history can point somewhere writable)";
    0b
 };

.tst.ensureStateDir:{[dir]
    if[not .tst.stateDirReady dir;:dir];
    if[not ".resq"~last "/" vs .resq.util.normalizePath dir;:dir];
    ignore:dir,"/.gitignore";
    if[.resq.util.pathExists ignore;:dir];
    @[{(hsym `$x) 0: .tst.STATE_DIR_GITIGNORE};ignore;{[e]}];
    dir
 };

.tst.atomicWriteJson:{[path;doc;kind]
    .tst.atomicWriteLines[path;enlist .tst.output.strictJson doc;kind]
 };

/ The history document with one entry to a line (see splitFlakeHistoryLines).
/ `doc` is the document with tests as its last key, and empty.
.tst.atomicWriteFlakeHistory:{[path;doc;lines]
    head:.tst.output.strictJson doc;
    if[not "[]}"~-3#head;'"history document must end with its tests"];
    body:$[count lines;((-1 _ lines),\:","),enlist last lines;()];
    .tst.atomicWriteLines[path;(enlist -2 _ head),body,enlist "]}";`flake]
 };

.tst.atomicWriteLines:{[path;lines;kind]
    slash:where path="/";
    dir:$[count slash;(last slash)#path;"."];
    if[0=count dir;dir:"/"];
    .tst.ensureStateDir dir;
    tmp:path,".tmp.",string .z.i;
    written:.[{[p;text](hsym `$p) 0:text;1b};(tmp;lines);{[err]0b}];
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
    .tst.flakeStateFromRaw .tst.requireIdentityDocument .tst.readFlakeHistoryRaw path
 };

/ A short-lived directory lock makes the read/merge/atomic-publish sequence a
/ single-writer operation. The bounded wait reclaims a lock that nobody
/ holds; otherwise this run leaves the cache untouched.
/ .
/ "Nobody holds it" was "its PID is not running". In a container PIDs start
/ again from 1, so the PID a killed run left behind is running in the next
/ container too, as something else: the lock was never reclaimed, and every
/ run waited five seconds and saved nothing. A lock is now also stale when
/ the process with that PID is not the one that took it (its start time is
/ recorded beside the PID), and when it is older than any writer needs,
/ which also covers a lock with no PID in it.
.tst.FLAKE_LOCK_STALE_MINUTES:2;
/ How often a held lock is tried, a twentieth of a second apart.
.tst.FLAKE_LOCK_TRIES:100;
.tst.acquireFlakeHistoryLock:{[path]
    slash:where path="/";
    dir:$[count slash;(last slash)#path;"."];
    if[0=count dir;dir:"/"];
    .tst.ensureStateDir dir;
    if[not .resq.util.isDir dir;:73j];
    lock:path,".lock";
    quoted:.resq.util.shellQuote lock;
    / 0 = acquired, 75 = held by a live writer, 73 = cannot be created at all
    / (read-only checkout, missing or foreign-owned state directory). Without
    / the 73 exit an unwritable directory spun the full 5 s busy-wait on every
    / run and was then misreported as a live writer.
    cmd:"lock=",quoted,"; i=0; while ! mkdir \"$lock\" 2>/dev/null; do ",
        "if [ ! -d \"$lock\" ]; then mkdir \"$lock\" 2>/dev/null && break; ",
        "if [ ! -d \"$lock\" ]; then echo 73; exit 0; fi; fi; ",
        "owner=''; began=''; if [ -f \"$lock/pid\" ]; then { read owner; read began; } < \"$lock/pid\" || true; fi; ",
        "stale=0; ",
        "if [ -n \"$owner\" ] && ! kill -0 \"$owner\" 2>/dev/null; then stale=1; fi; ",
        "if [ \"$stale\" = 0 ] && [ -n \"$owner\" ] && [ -n \"$began\" ]; then ",
        "now=$(ps -o lstart= -p \"$owner\" 2>/dev/null) || now=''; ",
        "if [ -n \"$now\" ] && [ \"$now\" != \"$began\" ]; then stale=1; fi; fi; ",
        "if [ \"$stale\" = 0 ] && [ -n \"$(find \"$lock\" -prune -mmin +",
            string[.tst.FLAKE_LOCK_STALE_MINUTES]," 2>/dev/null)\" ]; then stale=1; fi; ",
        "if [ \"$stale\" = 1 ]; then rm -rf -- \"$lock\"; continue; fi; ",
        "i=$((i+1)); if [ \"$i\" -ge ",string[.tst.FLAKE_LOCK_TRIES]," ]; then echo 75; exit 0; fi; sleep 0.05; done; ",
        "{ echo ",string[.z.i],"; ps -o lstart= -p ",string[.z.i]," 2>/dev/null; } > \"$lock/pid\"; echo 0";
    lines:@[system;"sh -c ",.resq.util.shellQuote cmd;{[err]enlist "75"}];
    $[count lines;"j"$"J"$last lines;75j]
 };

.tst.releaseFlakeHistoryLock:{[path]
    lock:path,".lock";
    ownerPath:lock,"/pid";
    owner:@[read0;hsym `$ownerPath;{()}];
    if[(count owner) and (first owner)~string .z.i;
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
    dirOf:{[p] slash:where p="/"; $[count slash;$[0=last slash;"/";(last slash)#p];"."]};
    lockStatus:.tst.acquireFlakeHistoryLock path;
    if[not 0j~lockStatus;
        / A directory that cannot be made has been said already.
        $[(73j~lockStatus) and not .resq.util.isDir dirOf path;
            .tst.recordDiagnostic[`flake;`warning;`persistence;
                "Unable to create the flake history lock (is the state directory writable?); current evidence was not published";
                enlist[`path]!enlist .tst.repoRelativePath path];
            .tst.recordStateWarning[`flake;`persistence;
                $[73j~lockStatus;
                    "Unable to create the flake history lock (is the state directory writable?); current evidence was not published";
                    "the flake history is locked by another run; this run's evidence was not saved"];
                enlist[`path]!enlist .tst.repoRelativePath[path],".lock"]];
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
        lines:.tst.mergeFlakeLines eligible;
        now:.tst.isoTimestamp .z.p;
        window:"j"$@[get;`.tst.app.flakeWindow;20j];
        hdoc:`schemaVersion`identityAlgorithm`identityCodec`kind`updatedAt`window`retention`tests!(
            .tst.FLAKE_HISTORY_VERSION;.tst.IDENTITY_ALGORITHM;.tst.identityCodecMetadata[];
            "resq-flake-history";now;
            window;
            `maxTests`unseenCompleteRuns!(
                .tst.FLAKE_HISTORY_MAX_TESTS;.tst.FLAKE_HISTORY_UNSEEN_LIMIT);
            ());
        ok:.tst.atomicWriteFlakeHistory[path;hdoc;lines];
        if[ok;
            saved:.tst.emptyFlakeHistory `ok;
            saved[`updatedAt]:now;
            saved[`lineMode]:1b;
            saved[`lines]:lines;
            saved[`lineIds]:`$.tst.flakeLineId each lines;
            saved[`window]:window;
            .tst.app.flakeHistory:saved];
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
        .tst.recordStateWarning[`flake;`persistence;
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
