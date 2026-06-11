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

saveSnap:{[name;data]
    .tst.ensureDir[.tst.snapDir];
    p: .tst.snapPath name;
    p set data;
 }

mustmatchSnap:{[actual;name]
    n: $[10h=type name; name; string name];
    snapName: `$n,".snap";
    stored: .tst.loadSnap[snapName];
    missing: ()~stored;

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
