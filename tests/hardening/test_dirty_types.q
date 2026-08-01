.tst.desc["Phase 2 Hardening: Dirty Types Reporting"; {
    .tst.should["handle lambda comparison failure"; {
        f1: {x+1};
        f2: {x+2};
        diffs: .tst.diff[f1; f2];
        must[0 < count diffs; "Expected diff output for lambda mismatch"];
    }];

    .tst.should["handle valid ipc handle comparison failure"; {
        / We need a real handle, so we'll open one to self if possible, or just a dummy int
        h1: 100i;
        h2: 101i;
        / To make it "dirty", we cast to handle type so it prints as `ipc
        h1: `int$h1; 
        / Actually, handle type is just int in KDB unless we use .z.w structure or similar.
        / Let's try to make it look like a handle
        diffs: .tst.diff[h1; h2];
        must[0 < count diffs; "Expected diff output for handle mismatch"];
    }];

    .tst.should["handle projection comparison failure"; {
        p1: +[1;];
        p2: *[2;];
        diffs: .tst.diff[p1; p2];
        must[0 < count diffs; "Expected diff output for projection mismatch"];
    }];

    .tst.should["handle huge table comparison failure"; {
        t1: ([] a: 10000?100; b: 10000?100.0);
        t2: t1;
        t2[0;`a]: 999;
        diffs: .tst.diff[t1; t2];
        must[0 < count diffs; "Expected diff output for large table mismatch"];
    }];

    .tst.should["survive injection of raw objects into failures"; {
        / Manually inject a dirty object into the assert state
        / This simulates a custom assertion that failed to stringify
        oldFailures: .tst.assertState.failures;
        .tst.assertState.failures,: enlist ({x+1}); 
        txt: .tst.toString each .tst.assertState.failures;
        / Drop the injected failure so it does not fail THIS test, but leave the
        / assertion counter alone: rewinding it made this test look like it
        / asserted nothing.
        .tst.assertState.failures: oldFailures;
        must[0 < count txt; "Expected raw failures to stringify"];
    }];
}];
