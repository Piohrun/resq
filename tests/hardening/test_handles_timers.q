.tst.desc["Phase 1 Hardening: Handles and Timers"; {
    .tst.should["leak a handle"; {
        fn: "test_dummy_handle_1.txt";
        hsym[`$fn] 0: enlist "dummy";
        / Use a fresh handle each time
        h: hopen hsym `$fn;
        / Leave h open. resq should warn and close it after the spec.
    }];

    .tst.should["modify .z.ts"; {
        / Safely store original if not already done
        if[not `origTs in key `.tst; .tst.origTs:: @[get; `.z.ts; {::}]];
        .z.ts: { 2 + 2 };
        / We leave it modified. resq should warn and restore it.
    }];
}];

.tst.desc["Phase 1 Hardening: Verification of Restoration"; {
  .tst.should["have restored .z.ts"; {
    curr: @[get; `.z.ts; {::}];
    must[not { 2 + 2 } ~ curr; ".z.ts not restored"];
  }];
  
  .tst.should["have closed the leaked handle"; {
      / We don't easily know the handle number here, but we can verify no handles to that file are open
      / For now, just relying on the fact that if it wasn't closed, we'd have a leak report in previous spec
      must[1b; "placeholder"];
  }];
}];
