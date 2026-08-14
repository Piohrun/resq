/ Dedicated subprocess probe for coverage ownership and rollback. This file is
/ intentionally not named test_*.q, so normal discovery never runs it directly.
.utl.require .utl.PKGLOADING,"/coverage.q";
.tst.testState.coverageLifecycle.init_:1b;
`.tst.testState.coverageLifecycle.setFn set .tst.coverageAssign;
.tst.testState.coverageLifecycle.src:.tst.tempFile ".q";
(hsym `$.tst.testState.coverageLifecycle.src) 0:(
    "\\d .covcycle";
    "a:{[x]x+1};";
    "b:{[x]x+2};";
    "c:{[x]x+3};";
    "\\d .");
system "l ",.tst.testState.coverageLifecycle.src;
.utl.loaded:enlist .tst.testState.coverageLifecycle.src;

.tst.desc["coverage repeated lifecycle child"]{
    should["restore, roll back, and reject foreign ownership"]{
        src:.tst.testState.coverageLifecycle.src;
        fileSym:`$.tst.resolvePath src;
        original:.covcycle.a;
        observed:`long$();

        / Three clean sessions must each start at one hit and restore the exact
        / source lambda rather than layering another wrapper around it.
        do[3;
            .tst.initCoverage enlist src;
            .covcycle.a[10] musteq 11;
            observed,:enlist .tst.coverageData[fileSym;`.covcycle.a];
            .tst.stopCoverage[];
            must[original~.tst.safeValue `.covcycle.a;
                 "the exact original lambda must be restored after every cycle"];
        ];
        observed musteq 1 1 1j;
        must[(0=count .tst.origFuncs) and 0=count .tst.covWrappers;
             "clean stop must empty ownership maps"];

        / Fail the third install. The first two assignments must unwind b,a.
        .tst.testState.coverageLifecycle.assignments:`symbol$();
        `.tst.coverageAssign set {[name;definition]
            .tst.testState.coverageLifecycle.assignments,:name;
            if[3=count .tst.testState.coverageLifecycle.assignments;
                :`ok`error!(0b;"injected install failure")];
            .tst.testState.coverageLifecycle.setFn[name;definition]
        };
        installErr:@[.tst.initCoverage;enlist src;{[e]e}];
        `.tst.coverageAssign set .tst.testState.coverageLifecycle.setFn;
        must[0<count ss[.tst.toString installErr;"injected install failure"];
             "partial installation must fail closed"];
        installLog:.tst.testState.coverageLifecycle.assignments;
        (3#installLog) musteq `.covcycle.a`.covcycle.b`.covcycle.c;
        (-2#installLog) musteq `.covcycle.b`.covcycle.a;
        .covcycle.a[1] musteq 2;
        .covcycle.b[1] musteq 3;
        .covcycle.c[1] musteq 4;

        / A failed restore retains only that wrapper and original, keeping the
        / live function callable until an idempotent retry succeeds.
        .tst.initCoverage enlist src;
        .tst.testState.coverageLifecycle.restoreLog:`symbol$();
        `.tst.coverageAssign set {[name;definition]
            .tst.testState.coverageLifecycle.restoreLog,:name;
            if[name~`.covcycle.b;
                :`ok`error!(0b;"injected restore failure")];
            .tst.testState.coverageLifecycle.setFn[name;definition]
        };
        restoreErr:@[.tst.stopCoverage;();{[e]e}];
        `.tst.coverageAssign set .tst.testState.coverageLifecycle.setFn;
        must[0<count ss[.tst.toString restoreErr;"injected restore failure"];
             "restore failure must be visible"];
        .tst.testState.coverageLifecycle.restoreLog musteq
            `.covcycle.c`.covcycle.b`.covcycle.a;
        (key .tst.covWrappers) musteq enlist `.covcycle.b;
        .covcycle.b[1] musteq 3;
        statuses:{x`status} each .tst.eventRows .tst.coverageLifecycleDiagnostics;
        `error mustin statuses;
        .tst.stopCoverage[];

        / A foreign replacement is never overwritten or blessed as an original.
        / It remains blocked until loading the source produces a different value.
        .tst.initCoverage enlist src;
        `.covcycle.b set {[x]x+100};
        ownershipErr:@[.tst.stopCoverage;();{[e]e}];
        must[0<count ss[.tst.toString ownershipErr;"foreign value left untouched"];
             "ownership conflict must fail closed"];
        .covcycle.b[1] musteq 101;
        `.covcycle.b mustin key .tst.coverageBlockedValues;
        mustthrow["*foreign/stale wrapper still owns the live definition";
            (.tst.initCoverage;enlist src)];
        system "l ",src;
        .tst.initCoverage enlist src;
        .covcycle.b[1] musteq 3;
        .tst.stopCoverage[];
    };
 };
