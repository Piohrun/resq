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
    / Check if directory exists
    h: hsym `$path;
    exists: not () ~ key h;

    if[not exists;
        / Try to create it
        @[system; "mkdir -p ", path; {[p;e]
            -1 "WARNING: Failed to create directory ", p, ": ", e
        }[path]]
    ];
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
    
    if[(.tst.updateSnaps) or (()~stored);
        .tst.saveSnap[snapName;actual];
        :1b;
    ];
    
    if[not actual~stored;
        diffs: .tst.diff[stored;actual];
        -1 "Snapshot mismatch for '",n,"'";
        -1 diffs;
        '"Snapshot mismatch for '",n,"'"
    ];
    
    1b
 }

\d .
