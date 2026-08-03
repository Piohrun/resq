/ tests/hardening/test_stack_trace_phase2.q
/ Runtime backtraces and enhanced assertions.

/ Named helpers are intentional: the contract is that a trapped runtime error
/ retains the nested q frames a user needs to diagnose it.
.tst.stackFixtureLeaf:{[] '"resq_nested_trace_boom"};
.tst.stackFixtureMiddle:{[] .tst.stackFixtureLeaf[]};
.tst.stackFixtureOuter:{[] .tst.stackFixtureMiddle[]};

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

    should["retain nested function frames at the real test-body trap boundary"]{
        expec: .tst.internals.testObj,
            `desc`code!("nested runtime error";.tst.stackFixtureOuter);
        outcome: @[
            {[e] (`ok;.tst.runners[`test] e)};
            expec;
            {[err] (`error;err)}];
        musteq[`error; first outcome];
        diagnostic: .tst.pendingBacktrace;
        .tst.pendingBacktrace: "";
        must[0 < count ss[diagnostic;"resq_nested_trace_boom"];
             "the original q error must survive"];
        must[0 < count ss[diagnostic;"Q Backtrace:"];
             "the diagnostic must label the formatted q backtrace"];
        must[0 < count ss[diagnostic;".tst.stackFixtureLeaf"];
             "the leaf frame must survive: ",diagnostic];
        must[0 < count ss[diagnostic;".tst.stackFixtureMiddle"];
             "the middle frame must survive: ",diagnostic];
        must[0 < count ss[diagnostic;".tst.stackFixtureOuter"];
             "the outer frame must survive: ",diagnostic];
    };
};

.tst.desc["Enhanced Assertion Messages"]{
    should["musteq exists and is callable"]{
        / Verify musteq is defined in .tst namespace - type 100h is function
        musteq[100h; type .tst.asserts`musteq];
    };
};
