
.tst.desc["Snapshot Verification"]{
    
    should["verify snapshot creation"]{
        
        data: `a`b`c!1 2 3;
        snapName: "tmp_resq_snapshot_test";
        snapFile: .utl.pathToHsym .tst.snapDir, "/", snapName, ".snap";
        
        @[hdel; snapFile; {}];
        .tst.registerCleanup[{[p] @[hdel; p; {}]}; enlist snapFile];
        
        .tst.setUpdateSnaps[1b];
        .tst.mustmatchs[data; snapName];
        
        type[key snapFile] musteq -11h; 
        
        .tst.setUpdateSnaps[0b];
        
        .tst.mustmatchs[data; snapName] musteq 1b;
        
        mustthrow["*Snapshot mismatch*"]{
            .tst.mustmatchs[`a`b`c!1 2 4; "tmp_resq_snapshot_test"];
        };
    };

    / --- Bug 3: empty-value snapshots must persist and VALIDATE, not re-create ---
    / loadSnap returns () for a missing file AND for a stored empty value, so the
    / old `()~stored` existence test aliased empties as missing: they re-created
    / every run (never compared) and failed under -strict. Existence is now keyed
    / off file presence via .tst.snapExists. The reusable check below: create once,
    / then with updateSnaps OFF the SAME value must COMPARE+pass (no re-create), and
    / a DIFFERENT value must THROW the mismatch signal (proving it did not re-create).
    / Reusable: create an empty-value snapshot under a FIXED name, then prove it
    / VALIDATES (does not re-create). Sets up the file + cleanup and asserts
    / existence + same-value pass. The caller asserts the DIFFERENT-value mismatch
    / via mustthrow against the same fixed name (DSL block bodies are separate
    / lambdas that cannot see the setup's locals, so the name must be a literal).
    .tst.testState.emptySnapSetup:{[empty; snapName]
        snapFile: .utl.pathToHsym .tst.snapDir, "/", snapName, ".snap";
        @[hdel; snapFile; {}];
        .tst.registerCleanup[{[p] @[hdel; p; {}]}; enlist snapFile];

        .tst.setUpdateSnaps[1b];
        .tst.mustmatchs[empty; snapName];
        / File exists and snapExists agrees, even though loadSnap may match ().
        must[.tst.snapExists[`$snapName, ".snap"]; "snapshot file must exist after create"];

        / Updates OFF: same empty value must COMPARE and pass (not re-create).
        .tst.setUpdateSnaps[0b];
        must[1b ~ .tst.mustmatchs[empty; snapName]; "same empty value must validate and pass"];
      };

    should["validate an empty-LIST snapshot without re-creating"]{
        .tst.testState.emptySnapSetup[(); "tmp_resq_emptysnap_list"];
        / A different value must fail the comparison (proves it validated and did
        / not silently re-create a fresh snapshot of the new value).
        mustthrow["*Snapshot mismatch*"]{ .tst.mustmatchs[enlist 1; "tmp_resq_emptysnap_list"] };
    };
    should["validate an empty-DICT snapshot without re-creating"]{
        .tst.testState.emptySnapSetup[()!(); "tmp_resq_emptysnap_dict"];
        mustthrow["*Snapshot mismatch*"]{ .tst.mustmatchs[(enlist `x)!enlist 1; "tmp_resq_emptysnap_dict"] };
    };
    should["validate an empty-TABLE snapshot without re-creating"]{
        .tst.testState.emptySnapSetup[([] x:`long$()); "tmp_resq_emptysnap_table"];
        mustthrow["*Snapshot mismatch*"]{ .tst.mustmatchs[([] x:enlist 1); "tmp_resq_emptysnap_table"] };
    };

    should["reject hostile snapshot names before resolving a path"]{
        badNames:(
            "";
            ".";
            "..";
            "../outside";
            "nested/name";
            "nested\\name";
            "/tmp/resq_snapshot_outside";
            "C:resq_snapshot_outside";
            "C:\\resq_snapshot_outside";
            "control\001name");

        {mustthrow["*Invalid snapshot name*"; (.tst.snapPath;x)]} each badNames;
        {mustthrow["*Invalid snapshot name*"; (.tst.snapTxtPath;x)]} each badNames;
    };

    should["keep valid string and symbol leaf names with automatic extensions"]{
        binString: .utl.pathToString .tst.snapPath "orders-v1.2_final (eu)!";
        binSymbol: .utl.pathToString .tst.snapPath `$"orders-v1.2 final";
        txtString: .utl.pathToString .tst.snapTxtPath "...";
        txtSymbol: .utl.pathToString .tst.snapTxtPath `$".orders-v1.2 final";

        (last "/" vs binString) musteq "orders-v1.2_final (eu)!.snap";
        (last "/" vs binSymbol) musteq "orders-v1.2 final.snap";
        (last "/" vs txtString) musteq "....snap.txt";
        (last "/" vs txtSymbol) musteq ".orders-v1.2 final.snap.txt";
    };

    should["never read or overwrite a file outside the binary snapshot root"]{
        cwd: system "cd";
        oldDir: .tst.snapDir;
        root: cwd, "/tests/snapshots/tmp_resq_boundary_root";
        sentinel: cwd, "/tests/snapshots/tmp_resq_boundary_sentinel.snap";
        sentinelHandle: .utl.pathToHsym sentinel;

        .utl.ensureDir root;
        sentinelHandle set `untouched;
        .tst.registerCleanup[{[d] .tst.setSnapDir d}; enlist oldDir];
        .tst.registerCleanup[{[p] @[hdel; .utl.pathToHsym p; {}]}; enlist sentinel];
        .tst.registerCleanup[{[p] @[hdel; .utl.pathToHsym p; {}]}; enlist root];
        .tst.setSnapDir root;

        mustthrow["*Invalid snapshot name*"]{.tst.saveSnap["../tmp_resq_boundary_sentinel"; `overwritten]};
        mustthrow["*Invalid snapshot name*"]{.tst.loadSnap "../tmp_resq_boundary_sentinel"};
        mustthrow["*Invalid snapshot name*"]{.tst.snapExists "../tmp_resq_boundary_sentinel"};
        (get sentinelHandle) musteq `untouched;
    };
};

/ --- Text snapshot parity with binary snapshots (Fix 5) ---------------------
/ mustmatchst must mirror mustmatchs: print a NOTE on first-run create, and
/ under -strict FAIL loudly on a missing snapshot instead of green-washing.
.tst.desc["Text Snapshot Verification"]{

    should["create on first run and validate on the next (no -strict)"]{
        data: `a`b`c!1 2 3;
        snapName: "tmp_resq_txtsnap_test";
        snapFile: .utl.pathToHsym .tst.snapTxtDir, "/", snapName, ".snap.txt";

        @[hdel; snapFile; {}];
        .tst.registerCleanup[{[p] @[hdel; p; {}]}; enlist snapFile];

        / First run creates the file and passes.
        .tst.mustmatchst[data; snapName] musteq 1b;
        must[.tst.snapTxtExists[snapName]; "text snapshot file must exist after create"];

        / Same value must compare and pass (not re-create).
        .tst.mustmatchst[data; snapName] musteq 1b;

        / A different value must throw the mismatch signal.
        mustthrow["*snapshotTxtMismatch*"]{
            .tst.mustmatchst[`a`b`c!1 2 4; "tmp_resq_txtsnap_test"];
        };
    };

    should["fail loudly under -strict when the text snapshot is missing"]{
        snapName: "tmp_resq_txtsnap_strict";
        snapFile: .utl.pathToHsym .tst.snapTxtDir, "/", snapName, ".snap.txt";
        @[hdel; snapFile; {}];
        .tst.registerCleanup[{[p] @[hdel; p; {}]}; enlist snapFile];

        / Simulate -strict for this assertion only, restore afterwards.
        oldStrict: @[get; `.tst.app.strict; 0b];
        .tst.app.strict: 1b;
        mustthrow["*Snapshot missing under -strict*"]{
            .tst.mustmatchst[`a`b!1 2; "tmp_resq_txtsnap_strict"];
        };
        .tst.app.strict: oldStrict;

        / The file must NOT have been created under -strict.
        must[not .tst.snapTxtExists[snapName]; "missing text snapshot must not be auto-created under -strict"];
    };

    should["never read or overwrite a file outside the text snapshot root"]{
        cwd: system "cd";
        oldDir: .tst.snapTxtDir;
        root: cwd, "/tests/__snapshots__/tmp_resq_boundary_root";
        sentinel: cwd, "/tests/__snapshots__/tmp_resq_boundary_sentinel.snap.txt";
        sentinelHandle: .utl.pathToHsym sentinel;

        .utl.ensureDir root;
        sentinelHandle 0: enlist "untouched";
        .tst.registerCleanup[{[d] .tst.setSnapTxtDir d}; enlist oldDir];
        .tst.registerCleanup[{[p] @[hdel; .utl.pathToHsym p; {}]}; enlist sentinel];
        .tst.registerCleanup[{[p] @[hdel; .utl.pathToHsym p; {}]}; enlist root];
        .tst.setSnapTxtDir root;

        mustthrow["*Invalid snapshot name*"]{.tst.saveSnapTxt["../tmp_resq_boundary_sentinel"; `overwritten]};
        mustthrow["*Invalid snapshot name*"]{.tst.loadSnapTxt "../tmp_resq_boundary_sentinel"};
        mustthrow["*Invalid snapshot name*"]{.tst.snapTxtExists "../tmp_resq_boundary_sentinel"};
        (first read0 sentinelHandle) musteq "untouched";
    };
};
