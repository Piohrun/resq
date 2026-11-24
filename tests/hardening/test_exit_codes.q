/ tests/hardening/test_exit_codes.q
/ Phase 1: Verify exit code logic and execution state tracking

.tst.desc["Exit Code Logic"]{

    should["define all exit code constants"]{
        / Verify the emitted exit codes are defined. Codes 2 (CONFIG_ERROR) and
        / 5 (PARTIAL) were removed: no dispatcher path ever emitted them.
        .resq.EXIT.PASS musteq 0;
        .resq.EXIT.FAIL musteq 1;
        .resq.EXIT.NO_TESTS musteq 3;
        .resq.EXIT.LOAD_ERROR musteq 4;
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
        / The counters cover tests that have finished, so they are all 0 when
        / this test runs first, as -random-order can arrange. What holds in any
        / order is that every executed test is one that passed, failed or
        / errored.
        .tst.app.expectationsRan musteq .tst.app.expectationsPassed + .tst.app.expectationsFailed + .tst.app.expectationsErrored;
    };

};
