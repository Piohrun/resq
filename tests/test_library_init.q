/ Exercise the library entry point from another application's working directory.
/ Each probe starts a fresh process; preloading resQ would mask bootstrap bugs.
.tst.testState.libraryInit.run:{[withQutil;packageLoad;missingBootstrap]
    wd:.utl.tempRoot[],"/resq_library_",string[.z.i],"_",string `long$.z.p;
    .utl.ensureDir wd;
    .tst.registerCleanup[{system "rm -rf -- ",.utl.shellQuote x};enlist wd];
    target:.resq.HOME,"/lib/init.q";
    if[missingBootstrap;
        .utl.ensureDir wd,"/incomplete";
        target:wd,"/incomplete/init.q";
        (hsym `$target) 0: read0 hsym `$.resq.HOME,"/lib/init.q"];
    lines:("beforeCwd:system \"cd\";";
           "beforeQ:key `.q;";
           "beforeQValues:get each .Q.dd[`.q;] each beforeQ;");
    if[withQutil;
        .utl.ensureDir wd,"/packages/resq-adoption-probe";
        (hsym `$wd,"/packages/resq-adoption-probe/init.q") 0: enlist ".application.probe:42;";
        lines,:enlist "system \"l \",",.j.j[.resq.HOME,"/pilots/vendor/nugend-qutil/lib/bootstrap.q"],";";
        lines,:enlist ".utl.QPATH:enlist hsym `$",.j.j[wd,"/packages"],";";
        lines,:(".utl.DEBUG:1b;";
                 ".utl.PKGLOADING:\"application-package\";";
                 ".utl.FILELOADING:`:application.q;";
                 "beforeRequire:.utl.require;")];
    loadExpr:$[packageLoad;".utl.require ";"system \"l \","],.j.j target;
    lines,:enlist "outcome:@[{",loadExpr,";(0b;\"\")};();{[e](1b;e)}];";
    lines,:("-1 \"LOAD_FAILED=\",string first outcome;";
             "-1 \"CWD_OK=\",string beforeCwd~system \"cd\";";
             "-1 \"Q_OK=\",string (beforeQ~key `.q) and beforeQValues~get each .Q.dd[`.q;] each beforeQ;");
    if[not missingBootstrap;
        lines,:("-1 \"READY=\",string 100h=type .tst.desc;";
                 "-1 \"ERROR=\",last outcome;")];
    if[withQutil;
        lines,:("-1 \"QUTIL_OK=\",string (beforeRequire~.resq.qutilRequire) and .utl.DEBUG and (\"application-package\"~.utl.PKGLOADING) and `:application.q~.utl.FILELOADING;";
                 ".utl.require \"resq-adoption-probe\";";
                 "-1 \"QUTIL_CALL=\",string 42~.application.probe;")];
    lines,:enlist "exit 0;";
    (hsym `$wd,"/probe.q") 0: lines;
    cmd:"cd ",.utl.shellQuote[wd]," && timeout -k 2 30 q probe.q -q -e 1 > out.txt 2>&1; echo $?";
    code:"J"$last system "sh -c ",.utl.shellQuote cmd;
    `code`output!(code;"\n" sv read0 hsym `$wd,"/out.txt")
 };

.tst.desc["library initialization in an existing application #slow"]{
    should["bootstrap a nested native load from an unrelated working directory"]{
        r:.tst.testState.libraryInit.run[0b;0b;0b];
        r[`code] musteq 0;
        must[all ("LOAD_FAILED=0";"CWD_OK=1";"Q_OK=1";"READY=1") in "\n" vs r`output;r`output];
    };
    should["bootstrap with qutil already loaded and preserve its state"]{
        r:.tst.testState.libraryInit.run[1b;0b;0b];
        r[`code] musteq 0;
        must[all ("LOAD_FAILED=0";"CWD_OK=1";"Q_OK=1";"READY=1";"QUTIL_OK=1";"QUTIL_CALL=1") in "\n" vs r`output;r`output];
    };
    should["load through qutil require without preloading resQ bootstrap"]{
        r:.tst.testState.libraryInit.run[1b;1b;0b];
        r[`code] musteq 0;
        must[all ("LOAD_FAILED=0";"CWD_OK=1";"Q_OK=1";"READY=1";"QUTIL_OK=1";"QUTIL_CALL=1") in "\n" vs r`output;r`output];
    };
    should["restore the application directory when bootstrap fails"]{
        r:.tst.testState.libraryInit.run[0b;0b;1b];
        r[`code] musteq 0;
        must[all ("LOAD_FAILED=1";"CWD_OK=1";"Q_OK=1") in "\n" vs r`output;r`output];
    };
};
