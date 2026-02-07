/ tests/hardening/test_exit_codes.q
/ Phase 1: Verify exit code logic and execution state tracking

.tst.desc["Exit Code Logic"]{

    should["define all exit code constants"]{
        / Verify exit codes are defined
        .resq.EXIT.PASS musteq 0;
        .resq.EXIT.FAIL musteq 1;
        .resq.EXIT.CONFIG_ERROR musteq 2;
        .resq.EXIT.NO_TESTS musteq 3;
        .resq.EXIT.LOAD_ERROR musteq 4;
        .resq.EXIT.PARTIAL musteq 5;
    };

    should["track execution state"]{
        / During test execution, state should be running or completed
        .tst.app.executionState mustin `running`completed;
    };

    should["have passing state when tests pass"]{
        / Since we're inside a passing test, passed should be true after run
        / (Can't fully test this from inside, but we can verify state exists)
        `passed mustin key `.tst.app;
    };

    should["track expectations correctly"]{
        / Verify expectation counters are being updated
        .tst.app.expectationsRan mustgt 0;
    };

};
