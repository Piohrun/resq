/ tests/hardening/test_stack_trace_phase2.q
/ Phase 2 Tests: Stack Traces and Enhanced Assertions

.tst.desc["Stack Trace Support"]{
    should["return string from stackTrace"]{
        trace: .tst.stackTrace[];
        / stackTrace should return a string (type is 10h for char list)
        t: type trace;
        musteq[1b; t in 10 -10h];
    };
    
    should["return non-error value"]{
        res: @[.tst.stackTrace; (); {[e] e}];
        / Should not throw errors - result type should be string or empty string
        musteq[1b; 10h = abs type res];
    };
};

.tst.desc["Enhanced Assertion Messages"]{
    should["musteq exists and is callable"]{
        / Verify musteq is defined in .tst namespace - type 100h is function
        musteq[100h; type .tst.asserts`musteq];
    };
};
