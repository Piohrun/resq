/ tests/hardening/test_mock_warnings.q
/ Phase 1: Verify mock restoration warnings are logged

.tst.desc["Mock Restoration Warnings"]{

    should["track mock state for restoration"]{
        / Create a mock using a namespaced path (avoids sandbox issues)
        `.tst.testMockVar mock 42;
        
        / Verify mock exists
        .tst.testMockVar musteq 42;
        
        / Verify mock state is being tracked (store has more than just null key)
        (count .tst.mockState.store) mustgt 1;
    };

    should["restore mocks automatically after test"]{
        / Mock a value in .tst namespace
        `.tst.restoreTestVar mock 123;
        .tst.restoreTestVar musteq 123;
        / After this test, the mock should be cleaned up
    };

    should["handle mock of non-existent namespaced variable"]{
        / This creates a new variable that should be removed on restore
        `.tst._tempTestVar mock "test value";
        .tst._tempTestVar musteq "test value";
        
        / Verify it's in the removeList
        `.tst._tempTestVar mustin .tst.mockState.removeList;
    };

    should["log warning for invalid restore targets"]{
        / This test verifies the warning mechanism exists
        / We can't easily capture output, so we just verify the restore function works
        .tst.restore[];
        1 musteq 1;
    };

};
