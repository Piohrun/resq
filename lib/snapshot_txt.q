\d .tst

/ Snapshot configuration
snapTxtDir: (system "cd"),"/tests/__snapshots__"

setSnapTxtDir:{[d] .tst.snapTxtDir: d}

loadSnapTxt:{[name]
    p: ` sv (hsym `$.tst.snapTxtDir; `$name,".snap.txt");
    if[not type key p; :()];
    "\n" sv read0 p
 }

saveSnapTxt:{[name;data]
    .tst.ensureDir[.tst.snapTxtDir];
    p: ` sv (hsym `$.tst.snapTxtDir; `$name,".snap.txt");
    txt: .Q.s1 data;
    hsym[p] 0: enlist txt;
 }

mustmatchTxtSnap:{[actual;name]
    n: $[10h=type name; name; string name];
    stored: .tst.loadSnapTxt[n];
    actTxt: .Q.s1 actual;
    
    if[(()~stored) or @[get;`.tst.updateSnaps;{0b}];
        .tst.saveSnapTxt[n;actual];
        :1b;
    ];
    
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
