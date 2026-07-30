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

/ Colorize console text using diff.q's shared dynamic gate. fmt.color performs
/ the same check as a final guard, so no text path can bypass NO_COLOR,
/ diffColors, or the compatibility useColor seam.
.resq.color:{[c;txt]
    if[
        not $[
            `colorEnabled in key `.tst;
            .tst.colorEnabled[];
            0b];
        :txt];
    .tst.fmt.color[c; txt]
 };

.resq.reportText:{[results]
    results: .tst.resultTable results;
    suiteGroups:group results`suite;
    suites:key suiteGroups;
    suiteRows:value suiteGroups;
    quiet: $[`quiet in key `.tst.app; .tst.app.quiet; 0b];

    suiteIndex:0;
    while[suiteIndex<count suites;
        s:suites suiteIndex;
        rowIndices:(),suiteRows suiteIndex;
        sRes:results rowIndices;
        sStatus: .tst.normalizeResultStatus each sRes`status;
        fails: sRes where sStatus in `fail`error;
        / In quiet mode, only show suites that have failures.
        if[not (quiet and 0=count fails);
            -1 "\n",.tst.toString[s],"::";
            { [f]
                -1 "- ",.tst.toString[f`description],": [",
                  string[f`status],"]";
                msg: .resq.renderMsg f`message;
                fl: (),f`failures;
                / Avoid double-printing: the per-test "Error:" line and the
                / "Failures:" block frequently carry the SAME verbatim text.
                flStr: "\n    " sv .resq.renderMsg each fl;
                dup: (0 < count fl) and (0 < count msg) and msg ~ flStr;
                if[(0<count msg) and not dup; -1 "  Error: ",msg];
                if[0<count fl;
                    -1 "  Failures: ";
                    { -1 "    ", .resq.renderMsg x } each fl
                ];
            } each fails;
            -1 "  (",string[count sRes]," tests, ",
              string[count fails]," failed)";
            ];
        suiteIndex+:1];

    summary: .tst.resultSummaryFromTable results;
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
    / Color the failed/error counts red when nonzero; leave the rest plain so
    / the overall "N total (...)" line format is byte-for-byte unchanged when
    / color is off (goldens pin this line).
    failedStr:  $[failed  > 0; .resq.color[`red; string failed];  string failed];
    erroredStr: $[errored > 0; .resq.color[`red; string errored]; string errored];
    -1 "Tests:      ", string[totalTests], " total (",
        string[passed], " passed, ",
        failedStr, " failed, ",
        erroredStr, " error, ",
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
        -1 .resq.color[`red; "Tests FAILED."];
        :()];

    if[0 = totalTests;
        -1 "No tests ran.";
        :()];

    -1 .resq.color[`green; "All tests passed."];

    / Diagnostic trailers (DEPENDENCY SUMMARY, SLOWEST TESTS) are noise on a
    / fully-green -quiet run: suppress them so a green -quiet run prints just
    / warnings (if any) + the SUMMARY box + verdict. Failures still print fully
    / (we already returned above when allFails was nonzero).
    if[quiet; :()];

    if[count .utl.testDeps;
        -1 "\n----------------------------------------------------------------";
        -1 "DEPENDENCY SUMMARY:";
        { [f; ds] -1 string[f], " depends on: ", " " sv string ds }'[key .utl.testDeps; value .utl.testDeps];
    ];

    if[count results;
        -1 "\n----------------------------------------------------------------";
        -1 "SLOWEST TESTS (TOP 5):";
        / q's take (#) WRAPS when fewer rows exist, repeating entries on small
        / suites; `5 sublist` caps without wrapping.
        slow: 5 sublist xdesc[ `time; 0!select last time by suite, description from results ];
        { [r]
          -1 "  ",.Q.s1[r`time]," - ",
            .tst.toString[r`suite],": ",
            .tst.toString[r`description]
        } each slow;
    ];
 };

.resq.report: .resq.reportText;
