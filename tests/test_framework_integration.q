/ test/test_framework_integration.q
/ Meta-tests: Testing the test framework stability and features

.tst.desc["Framework Isolation"; {
    
    should["restore .q namespace after tests"; {
        / Define a unique symbol in .q that we know isn't there
        marker: `$"__tst_marker_",string[.z.i];

        / Define it in .q (to simulate existing function)
        (` sv `.q,marker) set 42;

        / Re-run init logic to "save" this marker
        .tst.saveOriginalQ[];

        / Overwrite it in the framework (simulating mock/assertion injection)
        (` sv `.q,marker) set 99;
        (get ` sv `.q,marker) musteq 99;

        / Trigger restoration
        .tst.restoreOriginalQ[];

        / Verify it's back to 42
        (get ` sv `.q,marker) musteq 42;

        / Note: Marker persists in .q but uses unique name per process
    }];
    
    should["not leak state between tests"; {
        .test.leakyValue: 42;
        .tst.mock[`.test.leakyValue; 100];
        .test.leakyValue musteq 100;
    }];
}];

.tst.desc["Fixture System Stability"; {
    
    before ({
        .tst.registerFixture[`integrationFix; 100];
    });

    should["handle missing fixtures gracefully"; {
        / Trigger injection error
        err: @[{
            / We use a dummy lambda that expects a non-existent fixture
            .tst.runners[`test][`desc`code! ("Dummy"; {[nonExistentFixture] 1+1})];
            "no error"
        }; (); {x}];
        
        (err like "*Fixture Injection Error*") musteq 1b;
        (err like "*nonExistentFixture*") musteq 1b;
    }];
    
    should["clean up session fixtures"; {
        / Register session fixture with teardown
        .tst.teardownRan: 0b;
        .tst.registerFixtureWithOpts[`sessionCleanTest; 123; `scope`teardown!(`session; {.tst.teardownRan: 1b})];
        
        / Instantiate it
        val: .tst.getFixture[`sessionCleanTest];
        val musteq 123;
        
        / Verify it is NOT torn down yet
        .tst.teardownRan musteq 0b;
        
        / Run cleanup
        .tst.cleanupAllFixtures[];
        
        / Verify it HAS been torn down
        .tst.teardownRan musteq 1b;
        
        / Verify instance is cleared
        (.tst.fixtures[`sessionCleanTest; `instance] ~ (::)) musteq 1b;
    }];
}];

.tst.desc["Mock and Spy Robustness"; {
    
    should["restore mocked functions correctly"; {
        .test.origFunc: {[x] x * 2};
        .tst.mock[`.test.origFunc; {[x] x * 3}];
        
        .test.origFunc[10] musteq 30;
        
        .tst.restore[];
        
        .test.origFunc[10] musteq 20;
    }];
    
    should["spy on function calls with validation"; {
        .test.spyMe: {[a;b] a + b};
        .tst.spy[`.test.spyMe; (::)];
        
        .test.spyMe[10; 20];
        .test.spyMe[1; 2];
        
        / Verify calls directly in spyLog
        .tst.calledWith[`.test.spyMe; (10; 20)] musteq 1b;
        .tst.calledWith[`.test.spyMe; (1; 2)] musteq 1b;
        
        .tst.restore[];
    }];

    should["err on spying non-existent functions"; {
        err: @[{.tst.spy[`nonExistent; (::)]; "no err"}; (); {x}];
        (err like "*undefined function*") musteq 1b;
    }];
}];
