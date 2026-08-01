/ Regression tests for test-scoped fixture unwinding in runners[`test]:
/ teardown must run in LIFO order, must run when the test body throws, and a
/ failing setup must unwind the successfully-installed prefix. These drive the
/ runner directly with fabricated expec dicts so a throwing body can be
/ asserted on without failing this suite.

.tst.desc["fixture teardown unwinding"]{
    after{
        / Drop the probe fixtures so later suites see a clean registry.
        / (multi-key dict drop takes the key list on the LEFT of _)
        .tst.fixtures:: `td_a`td_b`td_bad`td_zza`td_zzb _ .tst.fixtures;
    };

    should["registry survives collapse to a typed value vector"]{
        / Simulate the sentinel-loss state: a registry holding only bare symbol
        / references collapses to an 11h value vector, after which amending a
        / definition dict used to die with 'type.
        .tst.fixtures:: `td_zza`td_zzb!`refa`refb;
        r: @[{.tst.registerFixtureWithOpts[`td_a; 1; enlist[`scope]!enlist `test]; `ok};
            (); {[e] e}];
        r musteq `ok;
        / Both prior symbol references must survive the repair.
        (.tst.fixtures`td_zza) musteq `refa;
        (.tst.fixtures`td_zzb) musteq `refb;
    };

    should["tear down test fixtures in LIFO order on normal return"]{
        .tst.testState.tdunwind:: ();
        .tst.registerFixtureWithOpts[`td_a; 1;
            `scope`teardown!(`test; {[v] .tst.testState.tdunwind,: enlist `a})];
        .tst.registerFixtureWithOpts[`td_b; 2;
            `scope`teardown!(`test; {[v] .tst.testState.tdunwind,: enlist `b})];
        expec: `type`code`desc!(`test; {[td_a;td_b] }; "lifo");
        r: .tst.runners[`test] expec;
        .tst.testState.tdunwind musteq `b`a;
    };

    should["tear down fixtures when the test body throws"]{
        .tst.testState.tdunwind:: ();
        .tst.registerFixtureWithOpts[`td_a; 1;
            `scope`teardown!(`test; {[v] .tst.testState.tdunwind,: enlist `a})];
        r: @[.tst.runners[`test]; `type`code`desc!(`test; {[td_a] '"boom"}; "throws");
            {[e] `caught}];
        r musteq `caught;
        .tst.testState.tdunwind musteq enlist `a;
    };

    should["unwind the installed prefix when a later setup throws"]{
        .tst.testState.tdunwind:: ();
        .tst.registerFixtureWithOpts[`td_a; 1;
            `scope`teardown!(`test; {[v] .tst.testState.tdunwind,: enlist `a})];
        .tst.registerFixtureWithOpts[`td_bad; 1;
            `scope`setup!(`test; {[v] '"setup boom"})];
        r: @[.tst.runners[`test];
            `type`code`desc!(`test; {[td_a;td_bad] }; "prefix");
            {[e] `caught}];
        r musteq `caught;
        / td_a was installed before td_bad's setup threw, so it must unwind.
        .tst.testState.tdunwind musteq enlist `a;
    };
 };
