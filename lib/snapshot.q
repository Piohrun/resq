\d .tst

/ Snapshot configuration
snapDir: (system "cd"),"/tests/snapshots"
updateSnaps: 0b

setSnapDir:{[d] .tst.snapDir: d}
setUpdateSnaps:{[b] .tst.updateSnaps: b}

snapPath:{[name]
    n: $[10h = type name; name; string name];
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
    n: $[10h=type name; name; string name];
    snapName: `$n,".snap";
    stored: .tst.loadSnap[snapName];
    / Decide existence by FILE PRESENCE, not by ()~stored: an empty-list,
    / empty-dict or empty-table snapshot all load back as a value that may
    / match (), so aliasing them to "missing" would re-create them every run
    / and fail under -strict despite the file existing on disk.
    missing: not .tst.snapExists snapName;

    / Explicit update intent always (re)writes and passes, with a NOTE.
    if[.tst.updateSnaps;
        .tst.saveSnap[snapName;actual];
        -1 "NOTE: snapshot created: ", n, " (", .tst.snapDir, ") - review and commit it";
        :1b;
    ];

    / First-run (no stored snapshot). Under -strict, refuse to auto-create-and-
    / pass: a fresh CI workspace must fail loudly instead of green-washing. Guard
    / the strict lookup since .tst.app.strict may be undefined in bare sessions.
    if[missing;
        if[1b ~ @[get; `.tst.app.strict; 0b];
            ' "Snapshot missing under -strict: ", n, " (run without -strict once to create it)";
        ];
        .tst.saveSnap[snapName;actual];
        -1 "NOTE: snapshot created: ", n, " (", .tst.snapDir, ") - review and commit it";
        :1b;
    ];

    if[not actual~stored;
        -1 "Snapshot mismatch for '",n,"'";
        / .tst.diff returns a flat list of plain strings; print each line, but a
        / rendering failure must not mask the snapshot mismatch signal below.
        @[{ -1 each .tst.diff[x 0; x 1] }; (stored;actual); {[err] -1 "  (diff rendering failed: ", err, ")" }];
        errSym: `$"Snapshot mismatch for '",n,"'";
        ' errSym
    ];
    
    1b
 }

\d .
