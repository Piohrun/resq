/ tests/hardening/test_enhanced_context.q
/ Phase 3: Verify enhanced stack trace context

.tst.desc["Enhanced Error Context"]{

    should["have currentContext defined"]{
        `currentContext mustin key `.tst;
    };

    should["track context with file, suite, test keys"]{
        `file mustin key .tst.currentContext;
        `suite mustin key .tst.currentContext;
        `test mustin key .tst.currentContext;
    };

    should["have context populated during test execution"]{
        / Suite should be set during test run
        suite: .tst.currentContext`suite;
        0 mustlt count suite;
        suite musteq "Enhanced Error Context";
    };

    should["track test description"]{
        / Test name should be set
        test: .tst.currentContext`test;
        0 mustlt count test;
        test musteq "track test description";
    };

    should["have improved stackTrace function"]{
        `stackTrace mustin key `.tst;
        / Should return a string (may be empty or have content)
        10h musteq type .tst.stackTrace[];
    };

};
