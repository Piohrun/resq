if[not `utl in key `; .utl:(enlist `)!enlist (::)];
if[not `PKGLOADING in key .utl; .utl.PKGLOADING:"lib"];
.utl.DEBUG: 0b;

/ Initialize .resq namespace and state
if[not `resq in key `; .resq.tmp:1; .resq.state.tmp:1; .resq.config.tmp:1];
.resq.VERSION: "0.1.0-alpha";

/ Exit code constants for CI/CD integration
.resq.EXIT.PASS: 0;        / All tests passed
.resq.EXIT.FAIL: 1;        / One or more tests failed
.resq.EXIT.CONFIG_ERROR: 2; / Configuration/CLI parsing error
.resq.EXIT.NO_TESTS: 3;    / No tests found (strict mode)
.resq.EXIT.LOAD_ERROR: 4;  / File load/syntax error

.resq.state.results: flip `suite`description`status`message`time`failures`assertsRun!(`symbol$(); `symbol$(); `symbol$(); (); `timespan$(); (); `int$());
if[not `fmt in key .resq.config; .resq.config.fmt: `text; .resq.config.outDir: ":."];

/ Project Libraries
.utl.require .utl.PKGLOADING,"/mock.q"
.utl.require .utl.PKGLOADING,"/benchmark.q"
.utl.require .utl.PKGLOADING,"/promise.q"
.utl.require .utl.PKGLOADING,"/fixture.q"
.utl.require .utl.PKGLOADING,"/diff.q"
.utl.require .utl.PKGLOADING,"/snapshot.q"
.utl.require .utl.PKGLOADING,"/snapshot_txt.q"
.utl.require .utl.PKGLOADING,"/tests/internals.q"
.utl.require .utl.PKGLOADING,"/output/sanitize.q"
.utl.require .utl.PKGLOADING,"/tests/assertions.q"
.utl.require .utl.PKGLOADING,"/deps.q"
.utl.require .utl.PKGLOADING,"/diff_assertions.q"
.utl.require .utl.PKGLOADING,"/parallel_runner.q"
.utl.require .utl.PKGLOADING,"/watch.q"
.utl.require .utl.PKGLOADING,"/tests/ui.q"
.utl.require .utl.PKGLOADING,"/tests/spec.q"
.utl.require .utl.PKGLOADING,"/tests/expec.q"
.utl.require .utl.PKGLOADING,"/tests/fuzz.q"
.utl.require .utl.PKGLOADING,"/loader.q"
.utl.require .utl.PKGLOADING,"/test_finder.q"

/ Alias .resq expansion functions to .tst for backward compatibility with example tests
if[`resq in key `;
    / Fix: Use key `.resq to get symbols in namespace
    { if[not x in key `.tst; .[`.tst; (enlist x); :; get ` sv `.resq, x]] } each key `.resq;
 ];

/ Define report function
/ Define report function for flat table results
.tst.app.loadErrors: flip `file`error`type!(`symbol$(); (); `symbol$());
if[not `strict in key .tst.app; .tst.app.strict: 0b];

.resq.report:{[results]
    / Group by suite for display
    suites: distinct results`suite;
    
    { [s; res] 
        sRes: select from res where suite=s;
        -1 "\n",string[s],"::";
        
        / Print failures
        fails: select from sRes where not status=`pass;
        { [f] 
            -1 "- ",string[f`description],": [",string[f`status],"]";
            msg: .tst.toString f`message;
            if[0<count msg; -1 "  Error: ",msg];
            if[0<count f`failures;
                -1 "  Failures: ";
                { -1 "    ", .tst.toString x } each (),f`failures
            ];
        } each fails;
        
        / Print summary for suite
        -1 "  (",string[count sRes]," tests, ",string[count fails]," failed)";
    }[;results] each suites;

    / Calculate statistics
    totalTests: count results;
    passed: count select from results where status=`pass;
    failed: count select from results where status=`fail;
    errored: count select from results where status=`error;
    skipped: count select from results where status in `skip`pending;
    
    totalTime: sum results`time;
    totalAsserts: sum results`assertsRun;
    
    / Print summary statistics
    -1 "";
    -1 "======================================================================";
    -1 "SUMMARY";
    -1 "----------------------------------------------------------------------";
    -1 "Tests:      ", string[totalTests], " total (",
        string[passed], " passed, ",
        string[failed], " failed, ",
        string[errored], " error, ",
        string[skipped], " skipped)";
    -1 "Assertions: ", string[totalAsserts], " total";
    duration: $[null totalTime; "0"; string `second$totalTime];
    -1 "Duration:   ", duration, "s";
    -1 "======================================================================";

    allFails: select from results where not status=`pass;
    -1 "\n----------------------------------------------------------------";
    if[0<count allFails;
        -1 "TOTAL FAILURES: ",string[count allFails];
        -1 "Tests FAILED.";
        :()];
        
    -1 "All tests passed.";
    
    / Print Dependency Summary if tracked
    if[count .utl.testDeps;
        -1 "\n----------------------------------------------------------------";
        -1 "DEPENDENCY SUMMARY:";
        { [f; ds] -1 string[f], " depends on: ", " " sv string ds }'[key .utl.testDeps; value .utl.testDeps];
    ];

    / Wall of Fame (Slowest Tests)
    if[count results;
        -1 "\n----------------------------------------------------------------";
        -1 "SLOWEST TESTS (TOP 5):";
        slow: 5 # xdesc[ `time; 0!select last time by suite, description from results ];
        { [r] -1 "  ", .Q.s1[r`time], " - ", string[r`suite], ": ", string[r`description] } each slow;
    ];
 };

/ Namespace Safety Guards
/ Save original .q functions before overwriting
.tst.saveOriginalQ:{[]
    if[not `originalQ in key `.tst; .tst.originalQ:: ()!()];
    / Defensive: reset if corrupted by mocks or bad state
    if[not 99h = type .tst.originalQ; .tst.originalQ:: ()!()];

    / Capture all .q keys that aren't already saved
    qKeys: key `.q;
    qKeys: qKeys where not qKeys in key .tst.originalQ;

    if[0<count qKeys;
        vals: {@[get; ` sv `.q,x; {`NOTFOUND}]} each qKeys;
        mask: not vals ~\: `NOTFOUND;
        if[any mask;
            newItems: (qKeys where mask)!(vals where mask);
            .tst.originalQ:: .tst.originalQ, newItems;
            if[.utl.DEBUG;
                -1 "INFO: resQ captured ", string[count newItems], " new .q original functions."];
        ];
    ];
 };

/ Restore original .q functions
.tst.restoreOriginalQ:{[]
    if[not `originalQ in key `.tst; :()];
    / Defensive: bail out if corrupted
    if[not 99h = type .tst.originalQ; delete originalQ from `.tst; :()];
    if[0 = count .tst.originalQ; :()];

    / Restore each saved function
    {[k;v]
        qName: ` sv `.q,k;
        @[qName set; v; { [name; e] -1 "ERROR: Failed to restore ",string[name],": ",e }[qName]];
    }'[key .tst.originalQ; value .tst.originalQ];

    / Clean up
    delete originalQ from `.tst;

    if[.utl.DEBUG; -1 "Restored original .q namespace"];
 };


.tst.die:{[x] 
    .tst.restoreOriginalQ[];
    exit x
 };

/ Expose assertions to .q for infix usage
/ Save original state first
.tst.saveOriginalQ[];

/ Map all assertions from the registry to global namespace
{ (` sv(`.q;x)) set .tst.asserts[x] } each key .tst.asserts;

/ Expose utilities to .q namespace
.q.mock: .tst.mock;
.q.fixture: .tst.fixture;
.q.fixtureAs: .tst.fixtureAs;
.q.tempFile: .tst.tempFile;
.q.registerCleanup: .tst.registerCleanup;

.tst.PKGNAME: .utl.PKGLOADING

.tst.loadOutputModule:{[module];
 if[not module in ("text";"xunit";"junit";"json"); '"Unknown OutputModule ",module];
 .utl.require .tst.PKGNAME,"/output/",module,".q"
 }
