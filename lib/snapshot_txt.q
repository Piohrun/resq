/ snapshot_txt.q - text (.snap.txt) snapshot storage + mustmatchst assertion
\d .tst

/ Snapshot configuration
/ NOTE: text snapshots live under tests/__snapshots__ as <name>.snap.txt, a
/ DIFFERENT directory + extension convention than binary snapshots (snapshot.q
/ stores tests/snapshots/<name>.snap). Both conventions are kept as-is for
/ backward compatibility.
snapTxtRoot: @[get;`.resq.startCwd;{system "cd"}]
snapTxtDir: snapTxtRoot,"/tests/__snapshots__"

setSnapTxtDir:{[d] .tst.snapTxtDir: d}

/ Same leaf containment as snapshot.q's snapPath: a snapshot name must be a
/ bare file name, so it can never resolve outside snapTxtDir.
snapTxtPath:{[name]
    n: $[10h = type name; name;
         -11h = type name; string name;
         '"Invalid snapshot name: expected a string or symbol"];
    if[not .tst.validSnapLeaf n;
        '"Invalid snapshot name '", n, "': must be a bare file name (no path separators, no leading dot)"];
    ` sv (hsym `$.tst.snapTxtDir; `$n,".snap.txt")
 }

/ Existence by FILE PRESENCE (mirrors snapshot.q's snapExists). A stored empty
/ value otherwise round-trips as "" and could be confused with "missing".
snapTxtExists:{[name] not () ~ key .tst.snapTxtPath name }

loadSnapTxt:{[name]
    p: .tst.snapTxtPath name;
    if[not type key p; :()];
    "\n" sv read0 p
 }

saveSnapTxt:{[name;data]
    .tst.ensureDir[.tst.snapTxtDir];
    p: .tst.snapTxtPath name;
    txt: .Q.s1 data;
    hsym[p] 0: enlist txt;
 }

mustmatchTxtSnap:{[actual;name]
    / Validate before any filesystem access or snapshot creation.
    validatedPath: .tst.snapTxtPath name;
    n: $[10h=type name; name; string name];
    actTxt: .Q.s1 actual;
    / Decide existence by FILE PRESENCE, not by ()~stored.
    missing: not .tst.snapTxtExists n;

    / Explicit update intent always (re)writes and passes, with a NOTE.
    if[@[get;`.tst.updateSnaps;{0b}];
        .tst.saveSnapTxt[n;actual];
        .tst.recordSnapshotEvent[`text;n;`updated;validatedPath];
        -1 "NOTE: text snapshot created: ", n, " (", .tst.snapTxtDir, ") - review and commit it";
        :1b;
    ];

    / First-run (no stored snapshot). Under -strict, refuse to auto-create-and-
    / pass so a fresh CI workspace fails loudly instead of green-washing. Guard
    / the strict lookup since .tst.app.strict may be undefined in bare sessions.
    if[missing;
        if[1b ~ @[get; `.tst.app.strict; 0b];
            .tst.recordSnapshotEvent[`text;n;`missing;validatedPath];
            ' "Snapshot missing under -strict: ", n, " (run without -strict once to create it)";
        ];
        .tst.saveSnapTxt[n;actual];
        .tst.recordSnapshotEvent[`text;n;`created;validatedPath];
        -1 "NOTE: text snapshot created: ", n, " (", .tst.snapTxtDir, ") - review and commit it";
        :1b;
    ];

    stored: .tst.loadSnapTxt[n];
    if[not actTxt~stored;
        .tst.recordSnapshotEvent[`text;n;`mismatch;validatedPath];
        -1 "SNAPSHOT MISMATCH for '",n,"'";
        -1 "----------------------------------------------------------------";
        -1 "Expected (Stored):";
        -1 stored;
        -1 "Actual (Current):";
        -1 actTxt;
        -1 "----------------------------------------------------------------";
        'snapshotTxtMismatch
    ];

    .tst.recordSnapshotEvent[`text;n;`matched;validatedPath];
    1b
 }

\d .
