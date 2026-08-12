.tst.desc["Phase 1 Hardening: Handles and Timers"; {
    .tst.should["leak a handle"; {
        fn: "test_dummy_handle_1.txt";
        / Spec-scope so the unlink runs AFTER the runner closes the leaked handle.
        .tst.registerSpecCleanup[{[p] @[hdel; hsym `$p; {}]}; enlist fn];
        hsym[`$fn] 0: enlist "dummy";
        / Use a fresh handle each time
        h: hopen hsym `$fn;
        .tst.testState.handlecheck.leakedHandle:h;
        / Leave h open. resq should warn and close it after the spec.
        must[0 < h; "the handle this test deliberately leaks must actually be open"];
    }];

    .tst.should["modify .z.ts"; {
        / Safely store original if not already done
        if[not `origTs in key `.tst; .tst.origTs:: @[get; `.z.ts; {::}]];
        .z.ts: { 2 + 2 };
        / We leave it modified. resq should warn and restore it.
        must[{ 2 + 2 } ~ @[get; `.z.ts; {::}]; "the .z.ts override must be in place for the guard to restore"];
    }];
}];

.tst.desc["Phase 1 Hardening: Verification of Restoration"; {
  .tst.should["have restored .z.ts"; {
    curr: @[get; `.z.ts; {::}];
    must[not { 2 + 2 } ~ curr; ".z.ts not restored"];
  }];
  
  .tst.should["have closed the leaked handle"; {
      fdCommand:"readlink /proc/",string[.z.i],"/fd/* 2>/dev/null";
      openTargets:@[system;fdCommand;{()}];
      leakedHandle:.tst.testState.handlecheck.leakedHandle;
      handleProbe:@[read1;leakedHandle;{[e] `closed}];
      must[handleProbe~`closed;
        "the suite boundary must close logical handle ",string[leakedHandle],
        "; probe=",.Q.s1[handleProbe],"; targets=",.Q.s1 openTargets];
      diagnostics:@[get;`.tst.app.diagnostics;{()}];
      must[`resource in diagnostics`type;
        "resource restoration must be visible as a structured diagnostic"];
  }];
}];
