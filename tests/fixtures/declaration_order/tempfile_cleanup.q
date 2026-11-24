/ Suites that check what an earlier suite in this file did. resQ runs
/ files, suites and the tests in them in any order under -random-order, so
/ tests/hardening/test_resource_cleanup.q runs this file in a child resQ of its own, where declaration
/ order holds.

.tst.desc["Phase 1 Hardening: Resource Management"; {
    .tst.should["cleanup temporary files auto-registered via tempFile"; {
        tf: .tst.tempFile ".txt";
        hsym[`$tf] 0: enlist "test content";
        must[.utl.isFile tf; "temp file not created"];
        .tst.tf:: tf; / Use simplified global assignment
    }];

    .tst.should["have already cleaned up the previous temp file"; {
        must[not .utl.isFile .tst.tf; "temp file not cleaned up"];
    }];
}];
