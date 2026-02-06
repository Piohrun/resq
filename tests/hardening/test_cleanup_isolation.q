/ tests/hardening/test_cleanup_isolation.q
/ Phase 1 Tests: Cleanup Error Isolation and Exit Codes

.tst.desc["Exit Code Constants"]{
    should["have all exit codes defined"]{
        / Check each exit code exists and is a number
        musteq[-7h; type .resq.EXIT.PASS];
        musteq[-7h; type .resq.EXIT.FAIL];
        musteq[-7h; type .resq.EXIT.CONFIG_ERROR];
        musteq[-7h; type .resq.EXIT.NO_TESTS];
        musteq[-7h; type .resq.EXIT.LOAD_ERROR];
    };
    
    should["have distinct exit codes"]{
        codes: (.resq.EXIT.PASS; .resq.EXIT.FAIL; .resq.EXIT.CONFIG_ERROR; .resq.EXIT.NO_TESTS; .resq.EXIT.LOAD_ERROR);
        musteq[5; count distinct codes];
    };
};

.tst.desc["Cleanup Error Isolation"]{
    should["have protected cleanup function"]{
        / Verify cleanup functions exist
        musteq[100h; type .tst.cleanupAllFixtures];
        musteq[100h; type .tst.restore];
    };
};
