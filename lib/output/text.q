/ Standard console reporter shared by all text-based invocations.

.resq.reportText:{[results]
    results: .tst.resultTable results;
    suites: distinct results`suite;
    
    { [s; res] 
        sRes: select from res where suite=s;
        -1 "\n",string[s],"::";
        
        sStatus: .tst.normalizeResultStatus each sRes`status;
        fails: sRes where sStatus in `fail`error;
        { [f] 
            -1 "- ",string[f`description],": [",string[f`status],"]";
            msg: .tst.toString f`message;
            if[0<count msg; -1 "  Error: ",msg];
            if[0<count f`failures;
                -1 "  Failures: ";
                { -1 "    ", .tst.toString x } each (),f`failures
            ];
        } each fails;
        
        -1 "  (",string[count sRes]," tests, ",string[count fails]," failed)";
    }[;results] each suites;

    totalTests: count results;
    statusNorm: .tst.normalizeResultStatus each results`status;
    passed: sum statusNorm = `pass;
    failed: sum statusNorm = `fail;
    errored: sum statusNorm = `error;
    skipped: sum statusNorm in `skip`pending;
    
    totalTime: sum results`time;
    totalAsserts: sum results`assertsRun;
    
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

    allFails: results where statusNorm in `fail`error;
    -1 "\n----------------------------------------------------------------";
    if[0<count allFails;
        -1 "TOTAL FAILURES: ",string[count allFails];
        -1 "Tests FAILED.";
        :()];
        
    -1 "All tests passed.";
    
    if[count .utl.testDeps;
        -1 "\n----------------------------------------------------------------";
        -1 "DEPENDENCY SUMMARY:";
        { [f; ds] -1 string[f], " depends on: ", " " sv string ds }'[key .utl.testDeps; value .utl.testDeps];
    ];

    if[count results;
        -1 "\n----------------------------------------------------------------";
        -1 "SLOWEST TESTS (TOP 5):";
        slow: 5 # xdesc[ `time; 0!select last time by suite, description from results ];
        { [r] -1 "  ", .Q.s1[r`time], " - ", string[r`suite], ": ", string[r`description] } each slow;
    ];
 };

.resq.report: .resq.reportText;
