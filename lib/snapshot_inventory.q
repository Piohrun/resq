/ snapshot_inventory.q - read-only snapshot reference inventory and CI gate
\d .tst

.tst.SNAPSHOT_INVENTORY_VERSION:1;

.tst.snapshotRows:{[items]
    if[0=count items;:()];
    if[98h=type items;:{[table;i]table i}[items] each til count items];
    if[99h=type items;:enlist items];
    if[0h=type items;:items where 99h=type each items];
    ()
 };

/ q promotes same-key dictionaries to a table. Applying a unary function to a
/ table iterates COLUMNS, not rows, so every inventory traversal goes through
/ this explicit row mapper.
.tst.snapshotApply:{[fn;items]
    if[98h=type items;
        :{[f;table;i]f table i}[fn;items;] each til count items];
    fn each items
 };

.tst.snapshotBackendRoot:{[backend]
    $[backend~`binary;.tst.snapshotAbsolutePath .tst.snapDir;
      backend~`text;.tst.snapshotAbsolutePath .tst.snapTxtDir;
      '"Unknown snapshot backend: ",.tst.toString backend]
 };

.tst.snapshotBackendPath:{[backend;name]
    .utl.pathToString $[backend~`binary;.tst.snapPath name;
      backend~`text;.tst.snapTxtPath name;
      '"Unknown snapshot backend: ",.tst.toString backend]
 };

/ Dynamic names cannot be recovered reliably from source text. Register the
/ concrete identities next to the generator that owns them. Declarations are
/ references, not writes, and are carried into partial/sharded inventories.
.tst.declareSnapshot:{[backend;names]
    b:`$lower .tst.toString backend;
    if[not b in `binary`text;'"Snapshot declaration backend must be binary or text"];
    values:$[10h=type names;enlist names;-11h=type names;enlist names;(),names];
    if[0=count values;'"Snapshot declaration requires at least one name"];
    if[not `snapshotDeclarations in key `.tst.app;.tst.app.snapshotDeclarations:()];
    {[b;name]
        path:.tst.snapshotBackendPath[b;name];
        root:.tst.snapshotBackendRoot b;
        .tst.app.snapshotDeclarations,:enlist
            `backend`name`path`root`absolutePath`executionId`observedStatus`declared`dynamic!(
                b;.tst.toString name;.tst.repoRelativePath path;
                .tst.repoRelativePath root;.tst.snapshotAbsolutePath path;"";"declared";1b;1b)
      }[b;] each values;
    ::
 };

if[not `snapshot in key `.resq;.resq.snapshot.init_:1b];
.resq.snapshot.declare:.tst.declareSnapshot;

.tst.emptySnapshotInventory:{[enabled]
    counts:`referenced`missing`obsolete`unverified`unsafe`stored`declared!(0j;0j;0j;0j;0j;0j;0j);
    gate:`enabled`passed`reasons!(0b;1b;());
    `schemaVersion`kind`enabled`generatedAt`complete`completenessReasons`roots`entries`counts`gate!(
        .tst.SNAPSHOT_INVENTORY_VERSION;"resq-snapshot-inventory";enabled;
        .tst.isoTimestamp .z.p;0b;$[enabled;enlist "not-evaluated";enlist "disabled"];
        ();();counts;gate)
 };

.tst.snapshotReferenceRows:{[rows]
    out:();
    ri:0;
    while[ri<count rows;
        row:rows ri;
        executionId:$[count .tst.toString row`caseId;.tst.toString row`caseId;.tst.toString row`testId];
        snaps:.tst.snapshotRows row`snapshots;
        si:0;
        while[si<count snaps;
            snap:snaps si;
            backend:`$lower .tst.toString snap`backend;
            path:.tst.toString snap`path;
            root:$[`root in key snap;.tst.toString snap`root;.tst.repoRelativePath .tst.snapshotBackendRoot backend];
            out,:enlist `backend`name`path`root`absolutePath`executionId`observedStatus`declared`dynamic!(
                backend;.tst.toString snap`name;path;root;
                .tst.snapshotAbsolutePath path;executionId;
                .tst.toString snap`status;0b;0b);
            si+:1];
        ri+:1];
    .tst.snapshotRows out
 };

.tst.snapshotRootRow:{[backend;root]
    absolute:.tst.snapshotAbsolutePath root;
    `backend`path`absolutePath`symlink!(backend;.tst.repoRelativePath absolute;absolute;.tst.snapshotIsSymlink absolute)
 };

.tst.snapshotRootKey:{[row].tst.toString[row`backend],"\n",.tst.toString row`absolutePath};
.tst.snapshotEntryKey:{[row].tst.toString[row`backend],"\n",.tst.toString row`absolutePath};

.tst.snapshotDistinctRows:{[rows;keyFn]
    items:.tst.snapshotRows rows;
    if[0=count items;:()];
    rowKeys:.tst.snapshotApply[keyFn;items];
    items rowKeys?distinct rowKeys
 };

.tst.snapshotStoredForRoot:{[rootRow]
    if[1b~rootRow`symlink;:()];
    backend:rootRow`backend;
    root:.tst.toString rootRow`absolutePath;
    children:@[key;hsym `$root;{`symbol$()}];
    if[not 11h=type children;:()];
    names:.tst.toString each children;
    suffix:$[backend~`binary;".snap";".snap.txt"];
    names:names where names like "*",suffix;
    if[backend~`binary;names:names where not names like "*.snap.txt"];
    out:();
    i:0;
    while[i<count names;
        fileName:names i;
        absolute:.tst.snapshotAbsolutePath root,"/",fileName;
        if[.utl.isFile absolute or .tst.snapshotIsSymlink absolute;
            snapName:(neg count suffix)_fileName;
            out,:enlist `backend`name`path`root`absolutePath`executionId`observedStatus`declared`dynamic!(
                backend;snapName;.tst.repoRelativePath absolute;rootRow`path;absolute;"";"stored";0b;0b)];
        i+:1];
    .tst.snapshotRows out
 };

.tst.snapshotCompletenessReasons:{[]
    reasons:();
    if[not 1b~@[get;`.tst.app.passed;0b];reasons,:enlist "run-failed"];
    if[not `completed~@[get;`.tst.app.executionState;`notStarted];reasons,:enlist "interrupted"];
    filtered:(0<count @[get;`.tst.app.runSpecs;{()}]) or
        (0<count @[get;`.tst.app.excludeSpecs;{()}]) or
        (0<count @[get;`.tst.app.tagFilter;{()}]) or
        (0<count @[get;`.tst.app.excludeTagFilter;{()}]);
    if[filtered;reasons,:enlist "filtered"];
    if[not `all~@[get;`.tst.app.rerunMode;`all];reasons,:enlist "rerun-selection"];
    if[1<"j"$@[get;`.tst.app.shardCount;1j];reasons,:enlist "sharded"];
    if[1b~@[get;`.tst.app.isolateChild;0b];reasons,:enlist "isolate-child"];
    if[1b~@[get;`.tst.app.describeOnly;0b];reasons,:enlist "describe-only"];
    distinct reasons
 };

.tst.snapshotEntryForKey:{[refs;decls;stored;roots;complete;entryKey]
    allRows:.tst.snapshotRows (refs,decls,stored);
    matches:allRows where entryKey~/:.tst.snapshotApply[.tst.snapshotEntryKey;allRows];
    firstRow:first matches;
    absolute:.tst.toString firstRow`absolutePath;
    backend:firstRow`backend;
    refRows:matches where 0<count each .tst.snapshotApply[{.tst.toString x`executionId};matches];
    decRows:matches where .tst.snapshotApply[{1b~x`declared};matches];
    isReferenced:((count refRows)>0) or ((count decRows)>0);
    exists:.utl.isFile absolute;
    rootAbsolute:.tst.snapshotAbsolutePath firstRow`root;
    rootRows:roots where rootAbsolute~/:
        .tst.snapshotApply[{.tst.toString x`absolutePath};roots];
    rootSymlink:$[count rootRows;1b~(first rootRows)`symlink;0b];
    unsafe:rootSymlink or .tst.snapshotIsSymlink absolute;
    status:$[isReferenced;$[exists;"referenced";"missing"];
        complete;"obsolete";"unverified"];
    ids:distinct .tst.snapshotApply[{.tst.toString x`executionId};refRows];
    ids:ids where 0<count each ids;
    observed:distinct .tst.snapshotApply[{.tst.toString x`observedStatus};refRows];
    `backend`name`path`root`absoluteRoot`absolutePath`status`referenced`declared`dynamic`exists`unsafe`executionIds`observedStatuses!(
        .tst.toString backend;.tst.toString firstRow`name;
        .tst.repoRelativePath absolute;.tst.repoRelativePath rootAbsolute;rootAbsolute;absolute;status;
        (count refRows)>0;(count decRows)>0;any .tst.snapshotApply[{1b~x`dynamic};matches];
        exists;unsafe;ids;observed)
 };

.tst.buildSnapshotInventory:{[results]
    enabled:(1b~@[get;`.tst.app.snapshotAudit;0b]) or 1b~@[get;`.tst.app.snapshotGate;0b];
    if[not enabled;:.tst.emptySnapshotInventory 0b];
    rows:.tst.resultRows results;
    refs:.tst.snapshotReferenceRows rows;
    decls:.tst.snapshotRows @[get;`.tst.app.snapshotDeclarations;{()}];
    rootCandidates:(.tst.snapshotRootRow[`binary;.tst.snapDir];.tst.snapshotRootRow[`text;.tst.snapTxtDir]);
    extraRoots:(refs,decls);
    if[count extraRoots;
        rootCandidates,:.tst.snapshotApply[{[row].tst.snapshotRootRow[row`backend;row`root]};extraRoots]];
    roots:.tst.snapshotDistinctRows[rootCandidates;.tst.snapshotRootKey];
    stored:raze .tst.snapshotApply[.tst.snapshotStoredForRoot;roots];
    stored:.tst.snapshotRows stored;
    candidates:.tst.snapshotRows (refs,decls,stored);
    reasons:.tst.snapshotCompletenessReasons[];
    complete:0=count reasons;
    entries:$[count candidates;
        .tst.snapshotEntryForKey[refs;decls;stored;roots;complete;] each
            distinct .tst.snapshotApply[.tst.snapshotEntryKey;candidates];
        ()];
    statuses:.tst.snapshotApply[{.tst.toString x`status};entries];
    unsafeCount:(sum .tst.snapshotApply[{1b~x`unsafe};entries])+
        sum .tst.snapshotApply[{1b~x`symlink};roots];
    counts:`referenced`missing`obsolete`unverified`unsafe`stored`declared!(
        "j"$sum statuses~\:"referenced";"j"$sum statuses~\:"missing";
        "j"$sum statuses~\:"obsolete";"j"$sum statuses~\:"unverified";
        "j"$unsafeCount;"j"$count stored;"j"$sum .tst.snapshotApply[{1b~x`declared};entries]);
    gateEnabled:1b~@[get;`.tst.app.snapshotGate;0b];
    gateReasons:();
    if[gateEnabled and not complete;gateReasons,:enlist "inventory-incomplete"];
    if[gateEnabled and 0<counts`missing;gateReasons,:enlist "missing-snapshots"];
    if[gateEnabled and 0<counts`obsolete;gateReasons,:enlist "obsolete-snapshots"];
    if[gateEnabled and 0<counts`unsafe;gateReasons,:enlist "unsafe-snapshot-paths"];
    gate:`enabled`passed`reasons!(gateEnabled;$[gateEnabled;0=count gateReasons;1b];gateReasons);
    `schemaVersion`kind`enabled`generatedAt`complete`completenessReasons`roots`entries`counts`gate!(
        .tst.SNAPSHOT_INVENTORY_VERSION;"resq-snapshot-inventory";1b;
        .tst.isoTimestamp .z.p;complete;reasons;roots;entries;counts;gate)
 };

.tst.applySnapshotAudit:{[]
    inventory:.tst.buildSnapshotInventory .resq.state.results;
    .tst.app.snapshotInventory:inventory;
    gate:inventory`gate;
    if[1b~gate`enabled;
        if[not 1b~gate`passed;
            message:"Snapshot gate failed: ",", " sv gate`reasons;
            .tst.recordDiagnostic[`snapshot;`error;`inventory;message;
                `complete`counts`reasons!(inventory`complete;inventory`counts;gate`reasons)];
            .tst.app.passed:0b]];
    inventory
 };

.tst.writeSnapshotInventory:{[]
    if[1b~@[get;`.tst.app.isolateChild;0b];:1b];
    inventory:@[get;`.tst.app.snapshotInventory;{.tst.emptySnapshotInventory 0b}];
    if[not 99h=type inventory;:1b];
    if[not 1b~inventory`enabled;:1b];
    outDir:.tst.toString .tst.runOutputDir[];
    if[0=count outDir;outDir:"."];
    base:.tst.toString @[get;`.tst.app.baseDir;{system "cd"}];
    if[not "/"=first outDir;outDir:base,"/",outDir];
    outDir:.utl.normalizePath outDir;
    .utl.ensureDir outDir;
    path:outDir,"/snapshot-manifest.json";
    hsym[`$path] 0:enlist .j.j inventory;
    -1 "Snapshot manifest written to ",path;
    1b
 };

\d .
::
