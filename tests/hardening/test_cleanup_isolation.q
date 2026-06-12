/ tests/hardening/test_cleanup_isolation.q
/ Phase 1 Tests: Cleanup Error Isolation and Exit Codes

.tst.desc["Exit Code Constants"]{
    should["have all exit codes defined"]{
        / Check each emitted exit code exists and is a number. CONFIG_ERROR(2)
        / and PARTIAL(5) were removed (never emitted by the dispatcher).
        musteq[-7h; type .resq.EXIT.PASS];
        musteq[-7h; type .resq.EXIT.FAIL];
        musteq[-7h; type .resq.EXIT.NO_TESTS];
        musteq[-7h; type .resq.EXIT.LOAD_ERROR];
    };

    should["have distinct exit codes"]{
        codes: (.resq.EXIT.PASS; .resq.EXIT.FAIL; .resq.EXIT.NO_TESTS; .resq.EXIT.LOAD_ERROR);
        musteq[4; count distinct codes];
    };
};

.tst.desc["Cleanup Error Isolation"]{
    should["have protected cleanup function"]{
        / Verify cleanup functions exist
        musteq[100h; type .tst.cleanupAllFixtures];
        musteq[100h; type .tst.restore];
    };
};
