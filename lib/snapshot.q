/ snapshot.q - binary (.snap) snapshot storage + mustmatchs assertion
\d .tst

/ Snapshot configuration
snapDir: (system "cd"),"/tests/snapshots"
updateSnaps: 0b

setSnapDir:{[d] .tst.snapDir: d}
setUpdateSnaps:{[b] .tst.updateSnaps: b}

.tst.recordSnapshotEvent:{[backend;name;status;path]
    if[not `currentSnapshots in key `.tst;.tst.currentSnapshots:()];
    .tst.currentSnapshots,:enlist `backend`name`status`path`timestamp!(
        backend;.tst.toString name;status;.tst.repoRelativePath .utl.pathToString path;
        .tst.isoTimestamp .z.p);
    ::
 };

/ A snapshot name must be a single path leaf: reject "." / "..", path
/ separators, Windows drive colons, and control characters so a crafted name
/ can never read or write outside snapDir. Dotfile-style names are allowed.
validSnapLeaf:{[n]
    if[not 10h = type n; :0b];
    if[0 = count n; :0b];
    if[any n ~/: ("."; ".."); :0b];
    if[any n in "/\\:"; :0b];
    codes: "i"$n;
    not (any 32 > codes) or any 127 = codes
 };

snapPath:{[name]
    n: $[10h = type name; name;
         -11h = type name; string name;
         '"Invalid snapshot name: expected a string or symbol"];
    if[not .tst.validSnapLeaf n;
        '"Invalid snapshot name '", n, "': must be a bare file name (no path separators, no leading dot)"];
    n: $[n like "*.snap"; n; n, ".snap"];
    .utl.pathToHsym .tst.snapDir, "/", n
 };

ensureDir:{[path]
    .utl.ensureDir path;
 };

loadSnap:{[name]
    p: .tst.snapPath name;
    if[not type key p; :()];
    get p
 }

/ Existence by FILE PRESENCE, not by value. loadSnap returns () for both a
/ missing file and a stored empty list/dict/table, so callers must use this to
/ decide "missing vs present" -- otherwise an empty-list snapshot re-creates
/ every run and never validates. key hsym: () for a missing file, the path
/ symbol (type -11h) for an existing file.
snapExists:{[name] not () ~ key .tst.snapPath name }

saveSnap:{[name;data]
    .tst.ensureDir[.tst.snapDir];
    p: .tst.snapPath name;
    p set data;
 }

mustmatchSnap:{[actual;name]
    / Validate before any filesystem access, and pass the raw name through so
    / loadSnap/snapExists/saveSnap all share snapPath's single derivation.
    validatedPath: .tst.snapPath name;
    n: $[10h=type name; name; string name];
    stored: .tst.loadSnap[name];
    / Decide existence by FILE PRESENCE, not by ()~stored: an empty-list,
    / empty-dict or empty-table snapshot all load back as a value that may
    / match (), so aliasing them to "missing" would re-create them every run
    / and fail under -strict despite the file existing on disk.
    missing: not .tst.snapExists name;

    / Explicit update intent always (re)writes and passes, with a NOTE.
    if[.tst.updateSnaps;
        .tst.saveSnap[name;actual];
        .tst.recordSnapshotEvent[`binary;n;`updated;validatedPath];
        -1 "NOTE: snapshot created: ", n, " (", .tst.snapDir, ") - review and commit it";
        :1b;
    ];

    / First-run (no stored snapshot). Under -strict, refuse to auto-create-and-
    / pass: a fresh CI workspace must fail loudly instead of green-washing. Guard
    / the strict lookup since .tst.app.strict may be undefined in bare sessions.
    if[missing;
        if[1b ~ @[get; `.tst.app.strict; 0b];
            .tst.recordSnapshotEvent[`binary;n;`missing;validatedPath];
            ' "Snapshot missing under -strict: ", n, " (run without -strict once to create it)";
        ];
        .tst.saveSnap[name;actual];
        .tst.recordSnapshotEvent[`binary;n;`created;validatedPath];
        -1 "NOTE: snapshot created: ", n, " (", .tst.snapDir, ") - review and commit it";
        :1b;
    ];

    if[not actual~stored;
        .tst.recordSnapshotEvent[`binary;n;`mismatch;validatedPath];
        -1 "Snapshot mismatch for '",n,"'";
        / .tst.diff returns a flat list of plain strings; print each line, but a
        / rendering failure must not mask the snapshot mismatch signal below.
        @[{ -1 each .tst.diff[x 0; x 1] }; (stored;actual); {[err] -1 "  (diff rendering failed: ", err, ")" }];
        errSym: `$"Snapshot mismatch for '",n,"'";
        ' errSym
    ];
    
    .tst.recordSnapshotEvent[`binary;n;`matched;validatedPath];
    1b
 }

\d .
