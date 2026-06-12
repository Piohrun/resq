/ snapshot_txt.q - text (.snap.txt) snapshot storage + mustmatchst assertion
\d .tst

/ Snapshot configuration
/ NOTE: text snapshots live under tests/__snapshots__ as <name>.snap.txt, a
/ DIFFERENT directory + extension convention than binary snapshots (snapshot.q
/ stores tests/snapshots/<name>.snap). Both conventions are kept as-is for
/ backward compatibility.
snapTxtDir: (system "cd"),"/tests/__snapshots__"

setSnapTxtDir:{[d] .tst.snapTxtDir: d}

snapTxtPath:{[name] ` sv (hsym `$.tst.snapTxtDir; `$name,".snap.txt") }

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
    n: $[10h=type name; name; string name];
    actTxt: .Q.s1 actual;
    / Decide existence by FILE PRESENCE, not by ()~stored.
    missing: not .tst.snapTxtExists n;

    / Explicit update intent always (re)writes and passes, with a NOTE.
    if[@[get;`.tst.updateSnaps;{0b}];
        .tst.saveSnapTxt[n;actual];
        -1 "NOTE: text snapshot created: ", n, " (", .tst.snapTxtDir, ") - review and commit it";
        :1b;
    ];

    / First-run (no stored snapshot). Under -strict, refuse to auto-create-and-
    / pass so a fresh CI workspace fails loudly instead of green-washing. Guard
    / the strict lookup since .tst.app.strict may be undefined in bare sessions.
    if[missing;
        if[1b ~ @[get; `.tst.app.strict; 0b];
            ' "Snapshot missing under -strict: ", n, " (run without -strict once to create it)";
        ];
        .tst.saveSnapTxt[n;actual];
        -1 "NOTE: text snapshot created: ", n, " (", .tst.snapTxtDir, ") - review and commit it";
        :1b;
    ];

    stored: .tst.loadSnapTxt[n];
    if[not actTxt~stored;
        -1 "SNAPSHOT MISMATCH for '",n,"'";
        -1 "----------------------------------------------------------------";
        -1 "Expected (Stored):";
        -1 stored;
        -1 "Actual (Current):";
        -1 actTxt;
        -1 "----------------------------------------------------------------";
        'snapshotTxtMismatch
    ];

    1b
 }

\d .
