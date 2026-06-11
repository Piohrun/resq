/ Standard console reporter shared by all text-based invocations.

/ Render a message/failure value for the console. A LIST of strings (type 0h
/ whose items are all char vectors) is joined with an indented newline so it
/ reads as separate lines instead of q's `,"..."` enlisted-string literal. A
/ plain string passes through .tst.toString unchanged.
.resq.renderMsg:{[v]
    if[(0h = type v) and all 10h = type each v;
        :"\n    " sv v];
    .tst.toString v
 };

.resq.reportText:{[results]
    results: .tst.resultTable results;
    suites: distinct results`suite;
    quiet: $[`quiet in key `.tst.app; .tst.app.quiet; 0b];

    { [s; res; quiet]
        sRes: res where (res`suite) = s;
        sStatus: .tst.normalizeResultStatus each sRes`status;
        fails: sRes where sStatus in `fail`error;
        / In quiet mode, only show suites that have failures.
        if[quiet and 0 = count fails; :()];
        -1 "\n",string[s],"::";
        { [f]
            -1 "- ",string[f`description],": [",string[f`status],"]";
            msg: .resq.renderMsg f`message;
            if[0<count msg; -1 "  Error: ",msg];
            if[0<count f`failures;
                -1 "  Failures: ";
                { -1 "    ", .resq.renderMsg x } each (),f`failures
            ];
        } each fails;

        -1 "  (",string[count sRes]," tests, ",string[count fails]," failed)";
    }[;results;quiet] each suites;

    summary: .tst.resultSummary results;
    totalTests: summary`testCount;
    passed: summary`passCount;
    failed: summary`failCount;
    errored: summary`errorCount;
    skipped: summary`skipCount;
    totalTime: summary`duration;
    totalAsserts: summary`assertsRun;
    
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

    statusNorm: .tst.normalizeResultStatus each results`status;
    allFails: results where statusNorm in `fail`error;
    -1 "\n----------------------------------------------------------------";
    if[0<count allFails;
        -1 "TOTAL FAILURES: ",string[count allFails];
        -1 "Tests FAILED.";
        :()];

    if[0 = totalTests;
        -1 "No tests ran.";
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
