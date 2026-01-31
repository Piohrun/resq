.tst.desc["Phase 1 Hardening: Resource Management"; {
    .tst.should["inspect tempFile definition"; {
        -1 "DEBUG: .q.tempFile definition: ", .Q.s1 value .tst.tempFile;
        -1 "DEBUG: .tst.tempFile value: ", .Q.s1 .tst.tempFile;
    }];

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
