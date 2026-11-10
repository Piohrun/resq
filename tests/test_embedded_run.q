/ Run against a fresh host process so the outer self-suite cannot mask leaks.
.tst.testState.embedded.run:{[scenario]
    wd:first system "mktemp -d ",.utl.shellQuote[.utl.tempRoot[],"/resq-embedded-test-XXXXXXXX"];
    .tst.registerCleanup[{system "rm -rf -- ",.utl.shellQuote x};enlist wd];
    probe:.resq.HOME,"/tests/fixtures/embedded/probe.q";
    cmd:"cd ",.utl.shellQuote[wd]," && timeout -k 2 45 q ",.utl.shellQuote[probe],
        " ",.utl.shellQuote[.resq.HOME]," ",scenario," -q -e 1 > out.txt 2>&1; echo $?";
    code:"J"$last system "sh -c ",.utl.shellQuote cmd;
    output:"\n" sv read0 hsym `$wd,"/out.txt";
    must[0=code;output];
    must["EMBEDDED_OK" in "\n" vs output;output];
 };
.tst.desc["embedded public run API #slow"]{
    should["return independent results across success, failure and filtering"]{
        .tst.testState.embedded.run "repeated";
    };
    should["restore host callbacks, timer, directory and namespace"]{
        .tst.testState.embedded.run "callbacks";
    };
    should["clean fixtures, mocks, tasks and handles after a load failure"]{
        .tst.testState.embedded.run "cleanup";
    };
    should["reject unsupported and nested calls before loading tests"]{
        .tst.testState.embedded.run "validation";
    };
    should["restore coverage instrumentation across repeated calls"]{
        .tst.testState.embedded.run "coverage";
    };
    should["fail cleanly when temporary history cannot be created"]{
        .tst.testState.embedded.run "tempFailure";
    };
    should["preserve an existing qutil application loader across runs"]{
        .tst.testState.embedded.run "qutil";
    };
    should["restore host state after a framework setup exception"]{
        .tst.testState.embedded.run "setupFailure";
    };
};
