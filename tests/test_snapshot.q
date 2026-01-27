
.tst.desc["Snapshot Verification"]{
    
    should["verify snapshot creation"]{
        
        data: `a`b`c!1 2 3;
        snapName: "test_snap_1";
        snapFile: .utl.pathToHsym .tst.snapDir, "/", snapName, ".snap";
        
        system "rm -f ",1_string snapFile;
        
        .tst.setUpdateSnaps[1b];
        .tst.mustmatchs[data; snapName];
        
        type[key snapFile] musteq -11h; 
        
        .tst.setUpdateSnaps[0b];
        
        .tst.mustmatchs[data; snapName] musteq 1b;
        
        mustthrow["*Snapshot mismatch*"]{
            .tst.mustmatchs[`a`b`c!1 2 4; "test_snap_1"];
        };
    };
};
