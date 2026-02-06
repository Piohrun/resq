/ tests/hardening/test_skip_pending.q
/ Phase 3 Tests: Skip/Pending Tests and Tag Filtering

.tst.desc["Skip and Pending DSL"]{
    should["normal test runs"]{
        musteq[2; 2];
    };
    
    should["skip DSL is defined in .tst"]{
        / Check in .tst namespace
        musteq[100h; type .tst.skip];
    };
    
    should["pending DSL is defined in .tst"]{
        musteq[100h; type .tst.pending];
    };
    
    should["skipIf DSL is defined in .tst"]{
        musteq[100h; type .tst.skipIf];
    };
};

.tst.desc["Tag Filtering"]{
    should["run when #slow tag included"]{
        musteq[1; 1];
    };
};
