
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
};

/ --- Text snapshot parity with binary snapshots (Fix 5) ---------------------
/ mustmatchst must mirror mustmatchs: print a NOTE on first-run create, and
/ under -strict FAIL loudly on a missing snapshot instead of green-washing.
.tst.desc["Text Snapshot Verification"]{

    / Inherently incompatible with -strict: it creates a snapshot on first run,
    / which is exactly what -strict forbids. Skip rather than fail so the whole
    / suite can be run under -strict in CI.
    skipIf[1b ~ @[get; `.tst.app.strict; 0b];
           "create on first run and validate on the next (no -strict)"]{
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

    should["text snapshot full fidelity detects differences beyond the display boundary"]{
        snapName:"tmp_resq_txtsnap_full_fidelity";
        snapFile:.tst.snapTxtPath snapName;
        @[hdel;snapFile;{}];
        .tst.registerCleanup[{[p]@[hdel;p;{}]};enlist snapFile];
        priorUpdate:.tst.updateSnaps;
        .tst.registerCleanup[{[old].tst.setUpdateSnaps old};enlist priorUpdate];
        prefix:240#"a";
        original:`text`vector`nested!(prefix,"LEFT";til 160;
            (enlist `payload)!enlist (prefix,"tail-left"));
        changed:`text`vector`nested!(prefix,"RIGHT";til 160;
            (enlist `payload)!enlist (prefix,"tail-right"));

        .tst.setUpdateSnaps 1b;
        .tst.mustmatchst[original;snapName] musteq 1b;
        .tst.setUpdateSnaps 0b;
        document:.j.k .tst.loadSnapTxt snapName;
        document[`schemaVersion] musteq 2f;
        document[`kind] musteq "resq-text-snapshot";
        must[count[document`canonicalPayload]>79;
             "canonical snapshot evidence must not stop at console width"];
        must[0<count ss[document`rendering;"tail-left"];
             "full rendering must retain distinguishing tail data"];
        mustthrow["*snapshotTxtMismatch*";(.tst.mustmatchst;changed;snapName)];
    };

    should["canonical values and full rendering ignore console geometry"]{
        oldConsole:system "c";
        .tst.registerCleanup[{[dims]
            system "c ",string[dims 0]," ",string dims 1};enlist oldConsole];
        sample:`longText`numbers`nested!((300#"z"),"TAIL";til 200;
            (`a`b!((120#"q"),"END";1.2345678901234567f)));
        system "c 25 40";
        narrow:(.tst.canonicalValueBytes sample;.tst.renderValueFull sample);
        system "c 25 500";
        wide:(.tst.canonicalValueBytes sample;.tst.renderValueFull sample);
        system "c ",string[oldConsole 0]," ",string oldConsole 1;
        narrow mustmatch wide;
        rendered:last narrow;
        must[(0<count ss[rendered;"TAIL"]) and 0<count ss[rendered;"END"];
             "full renderer must retain nested tails"];
    };

    should["canonical IPC leaf oracle round-trips supported value shapes"]{
        samples:(42j;1.2345678901234567f;"full text";`symbol;
            1 2 3 4j;("nested";`a`b!1 2);`c1`c2!(`x`y;10 20j);
            ([] sym:`a`b;px:1.25 2.5f));
        must[all {x~-9!(-8!x)} each samples;
             "q IPC fidelity oracle must round-trip every supported sample"];
        must[not .tst.canonicalValueBytes[1j]~.tst.canonicalValueBytes[1f];
             "canonical framing must preserve numeric type"];
        .tst.canonicalValueBytes[1j] musteq
            "(26:resq-value-v1+q-ipc-leaves:51:(9:leaf/-7/1:34:0100000011000000f90100000000000000))";
        .tst.canonicalValueBytes[(1j;"x")] musteq
            "(26:resq-value-v1+q-ipc-leaves:131:(8:list/0/2:114:(4:item:51:(9:leaf/-7/1:34:0100000011000000f90100000000000000))(4:item:39:(10:leaf/-10/1:20:010000000a000000f678))))";
    };

    should["text snapshots distinguish precision-sensitive floats"]{
        snapName:"tmp_resq_txtsnap_float_precision";
        snapFile:.tst.snapTxtPath snapName;
        @[hdel;snapFile;{}];
        .tst.registerCleanup[{[p]@[hdel;p;{}]};enlist snapFile];
        priorUpdate:.tst.updateSnaps;
        .tst.registerCleanup[{[old].tst.setUpdateSnaps old};enlist priorUpdate];
        .tst.setUpdateSnaps 1b;
        / Both values render as "1f" through the former .Q.s1 boundary at
        / default precision, but their canonical bytes are distinct.
        must[not .tst.renderValueFull[1.0000001]~.tst.renderValueFull[1.0000002];
             "full float evidence must preserve a visible distinction"];
        .tst.mustmatchst[1.0000001;snapName] musteq 1b;
        .tst.setUpdateSnaps 0b;
        mustthrow["*snapshotTxtMismatch*";
            (.tst.mustmatchst;1.0000002;snapName)];
    };

    should["legacy text snapshots require explicit migration to v2"]{
        snapName:"tmp_resq_txtsnap_legacy";
        snapFile:.tst.snapTxtPath snapName;
        @[hdel;snapFile;{}];
        .tst.registerCleanup[{[p]@[hdel;p;{}]};enlist snapFile];
        priorUpdate:.tst.updateSnaps;
        .tst.registerCleanup[{[old].tst.setUpdateSnaps old};enlist priorUpdate];
        hsym[snapFile] 0:enlist .Q.s1 `legacy`value!(1;200#"x");
        .tst.setUpdateSnaps 0b;
        mustthrow["*Text snapshot migration required*";
            (.tst.mustmatchst;`legacy`value!(1;200#"x");snapName)];
        .tst.setUpdateSnaps 1b;
        .tst.mustmatchst[`legacy`value!(1;200#"x");snapName] musteq 1b;
        parsed:.tst.parseTextSnapshot .tst.loadSnapTxt snapName;
        parsed[`state] musteq `ok;
    };

    should["reject text snapshots from a different pinned codec build"]{
        snapName:"tmp_resq_txtsnap_codec_mismatch";
        snapFile:.tst.snapTxtPath snapName;
        @[hdel;snapFile;{}];
        .tst.registerCleanup[{[p]@[hdel;p;{}]};enlist snapFile];
        priorUpdate:.tst.updateSnaps;
        .tst.registerCleanup[{[old].tst.setUpdateSnaps old};enlist priorUpdate];
        document:.tst.textSnapshotDocument `a`b!1 2;
        codec:document`codec;
        codec[`qRelease]:"different-q-release";
        document[`codec]:codec;
        hsym[snapFile] 0:enlist .j.j document;
        .tst.setUpdateSnaps 0b;
        mustthrow["*explicit migration is required*";
            (.tst.mustmatchst;`a`b!1 2;snapName)];
    };
};

.tst.desc["Snapshot Name Containment"]{
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
