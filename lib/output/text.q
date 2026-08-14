/ Standard console reporter shared by all text-based invocations.

/ Render a message/failure value for the console. A LIST of strings (type 0h
/ whose items are all char vectors) is joined with an indented newline so it
/ reads as separate lines instead of q's `,"..."` enlisted-string literal. A
/ plain string passes through .tst.toString unchanged.
/ Drop an appended structural diff from ONE message. A failing musteq records
/ "<summary>\n--- diff ---\n<diff>" so the machine reports carry the diff too,
/ but the console already streamed that diff at failure time, labelled with its
/ suite and test. Reprinting it in the summary would double every failure in the
/ log for no new information, so the console keeps the summary line.
.resq.summaryOnly:{[s]
    if[not 10h = abs type s; :s];
    marker: @[get; `.tst.diffDetailMarker; {"\n--- diff ---\n"}];
    at: ss[s; marker];
    $[count at; (first at) # s; s]
 };

.resq.renderMsg:{[v]
    if[(0h = type v) and all 10h = type each v;
        :"\n    " sv .resq.summaryOnly each v];
    .resq.summaryOnly .tst.toString v
 };

/ Extract the machine-retained structural diff from a failure value. Streaming
/ remains the default diagnostic path; this is used only by the opt-in final
/ report mode for CI systems that surface the end of a long log.
.resq.diffDetail:{[v]
    s:.tst.toString v;
    marker:@[get;`.tst.diffDetailMarker;{"\n--- diff ---\n"}];
    at:ss[s;marker];
    $[count at;(first[at]+count marker)_s;""]
 };

.resq.firstDiffDetail:{[message;failures]
    values:(enlist message),(),failures;
    details:.resq.diffDetail each values;
    details:details where 0<count each details;
    $[count details;first details;""]
 };

.resq.printFinalDiff:{[detail]
    if[not 1b~@[get;`.tst.app.finalDiffs;0b];:()];
    remaining:"j"$@[get;`.tst.app.finalDiffRemaining;0j];
    if[(remaining<=0) or 0=count detail;:()];
    shown:remaining sublist detail;
    -1 "  Final diff (bounded):";
    -1 shown;
    .tst.app.finalDiffRemaining:remaining-count shown;
    if[count[shown]<count detail;
        -1 "  ... [final diff output limit reached]";
        .tst.app.finalDiffRemaining:0j];
 };

/ Colorize console text using the SAME central gate as diff.q (.tst.useColor,
/ computed once at load from NO_COLOR + .tst.diffColors + TTY auto-detect). When
/ color is off this is a no-op so CI logs / redirected files stay plain.
.resq.color:{[c;txt]
    if[not $[`useColor in key `.tst; .tst.useColor; 1b]; :txt];
    .tst.fmt.color[c; txt]
 };

/ A test that executed but ran zero assertions proves nothing: in q a bare
/ `0 < count warnings;` is a value the block discards, not a check, and the test
/ passes however broken the code is. Reported even under -quiet -- this is a
/ correctness warning, not a diagnostic trailer -- but silent when there are
/ none, so an ordinary green run is unchanged.
.resq.reportSilentTests:{[results; statusNorm]
    executed: results where statusNorm = `pass;
    if[0 = count executed; :()];
    silent: select from executed where 0 = assertsRun;
    / A perf block is a measurement, not an assertion test. Its benchmark result
    / row legitimately carries assertsRun=0, so do not diagnose it as an empty
    / should block.
    perfRowsForAudit: @[get; `.tst.app.perfResults; {()}];
    if[(98h = type perfRowsForAudit) and
       (0 < count perfRowsForAudit) and
       0 < count silent;
        perfKeys: {string[x 0], "|", string x 1} each
            flip (perfRowsForAudit`suite; perfRowsForAudit`description);
        silentKeys: {string[x 0], "|", string x 1} each
            flip (silent`suite; silent`description);
        silent: silent where not silentKeys in perfKeys;
    ];
    if[0 = count silent; :()];
    -1 "\n----------------------------------------------------------------";
    -1 .resq.color[`yellow; "TESTS THAT ASSERTED NOTHING: ", string count silent];
    -1 "  These passed without checking anything. In q a bare expression";
    -1 "  is discarded, so wrap it: must[cond; \"message\"].";
    { [r] -1 "  - ", string[r`suite], ": ", string[r`description] }
        each 10 sublist 0!select suite, description from silent;
    if[10 < count silent;
        -1 "  ... and ", string[(count silent) - 10], " more"];
 };

.resq.reportFlakeStates:{[results]
    if[not `quarantine in cols results;:()];
    interesting:results where {[qstate]
        if[not 99h=type qstate;:0b];
        if[not `state in key qstate;:0b];
        .tst.toString[qstate`state] in ("suspect";"quarantined";"expired")
      } each results`quarantine;
    if[0=count interesting;:()];
    -1 "\n----------------------------------------------------------------";
    -1 "FLAKE / QUARANTINE STATE (",string[count interesting],"):";
    {[row]
        qstate:row`quarantine;
        line:"  ",string[row`suite],": ",string[row`description],"  [",
            .tst.toString[qstate`state],"] ",string[qstate`observations]," observations, ",
            string[qstate`failures]," failures, ",string[qstate`passes]," passes";
        if[1b~qstate`nonBlocking;line,:"; NON-BLOCKING (explicit opt-in)"];
        if["expired"~.tst.toString qstate`state;line,:"; expiry restored blocking"];
        if[count .tst.toString qstate`owner;line,:"; owner=",.tst.toString qstate`owner];
        -1 line
      } each interesting;
 };

.resq.reportSnapshotInventory:{[inventory]
    if[not 99h=type inventory;:()];
    if[not 1b~inventory`enabled;:()];
    counts:inventory`counts;
    -1 "\n----------------------------------------------------------------";
    -1 "SNAPSHOT INVENTORY: ",$[inventory`complete;"complete";"partial"],
        " (",string[count inventory`entries]," identities)";
    -1 "  referenced=",string[counts`referenced],
        " missing=",string[counts`missing],
        " obsolete=",string[counts`obsolete],
        " unverified=",string[counts`unverified],
        " unsafe=",string[counts`unsafe];
    if[not inventory`complete;
        -1 "  incomplete because: ",", " sv inventory`completenessReasons];
    if[1b~inventory[`gate;`enabled];
        -1 "  gate: ",$[inventory[`gate;`passed];"PASS";"FAIL (",", " sv inventory[`gate;`reasons],")"]];
 };

.resq.reportBenchmarkAnalysis:{[analysis]
    if[not 99h=type analysis;:()];
    if[not 1b~analysis`enabled;:()];
    counts:analysis`counts;
    -1 "\n----------------------------------------------------------------";
    -1 "BENCHMARK REGRESSION: ",string[counts`total]," compared; ",
        string[counts`improved]," improved, ",string[counts`stable]," stable, ",
        string[counts`inconclusive]," inconclusive, ",string[counts`regressed]," regressed";
    -1 "  baseline: ",.tst.toString[analysis`baselinePath]," [",
        .tst.toString[analysis`baselineStatus],"]";
    {[comparison]
        if[not (comparison`classification) in `regressed`inconclusive;:()];
        line:"  ",.tst.toString[comparison`classification],"  ",
            .tst.toString[comparison`suite],": ",.tst.toString comparison`description;
        if[not null comparison`relativeChangePercent;
            line,:"  change=",.Q.f[2;"f"$comparison`relativeChangePercent],"%"];
        if[count .tst.toString comparison`reason;line,:"  (",.tst.toString[comparison`reason],")"];
        -1 line
      } each .tst.benchmarkRows analysis`comparisons;
    if[1b~analysis[`gate;`enabled];
        gateText:$[1b~$[`deferred in key analysis`gate;analysis[`gate;`deferred];0b];
            "DEFERRED (strict shard merge is authoritative)";
          analysis[`gate;`passed];"PASS";
            "FAIL (",(", " sv analysis[`gate;`reasons]),")"];
        -1 "  gate: ",gateText]
 };

.resq.reportText:{[results]
    .tst.app.finalDiffRemaining:"j"$@[get;`.tst.app.finalDiffLimit;4000j];
    snapshotInventory:$[(99h=type results) and `snapshotInventory in key results;
        results`snapshotInventory;.tst.emptySnapshotInventory 0b];
    benchmarkAnalysis:$[(99h=type results) and `benchmarkAnalysis in key results;
        results`benchmarkAnalysis;.tst.emptyBenchmarkAnalysis 0b];
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
            fl: (),f`failures;
            / Avoid double-printing: the per-test "Error:" line and the
            / "Failures:" block frequently carry the SAME verbatim text (a
            / single failing assertion populates both). When the joined
            / failures equal the message, print it once as Failures and drop
            / the redundant Error line.
            flStr: "\n    " sv .resq.renderMsg each fl;
            dup: (0 < count fl) and (0 < count msg) and msg ~ flStr;
            if[(0<count msg) and not dup; -1 "  Error: ",msg];
            if[0<count fl;
                -1 "  Failures: ";
                { -1 "    ", .resq.renderMsg x } each fl
            ];
            .resq.printFinalDiff .resq.firstDiffDetail[f`message;fl];
            captured: $[`output in key f; .tst.toString f`output; ""];
            if[count captured;
                -1 "  Captured child output:";
                -1 captured];
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
    / Printed BEFORE the verdict, on red runs as well as green. This used to sit
    / after the "Tests FAILED." early return, so the moment a suite had one real
    / failure its vacuous tests went unmentioned -- exactly when someone is
    / working through that suite and would want to know which of its passing
    / tests prove nothing. Ordering on a green run is unchanged.
    .resq.reportSilentTests[results; statusNorm];
    .resq.reportFlakeStates results;
    .resq.reportSnapshotInventory snapshotInventory;
    .resq.reportBenchmarkAnalysis benchmarkAnalysis;
    blockingFails:allFails;
    if[count allFails;
        failRows:{[table;i]table i}[allFails] each til count allFails;
        blockingFails:allFails where not .tst.rowIsNonBlockingQuarantine each failRows];
    if[0<count blockingFails;
        -1 "TOTAL FAILURES: ",string[count allFails];
        -1 .resq.color[`red; "Tests FAILED."];
        :()];
    if[0<count allFails;
        -1 "QUARANTINED FAILURES: ",string[count allFails],
            " (raw results retained; non-blocking policy explicitly enabled)";
        -1 .resq.color[`yellow; "Run passed with quarantined failures."];
        :()];
    if[(99h=type snapshotInventory) and 1b~snapshotInventory[`gate;`enabled] and
       not 1b~snapshotInventory[`gate;`passed];
        -1 "TOTAL FAILURES: snapshot inventory gate";
        -1 .resq.color[`red;"Tests FAILED."];
        :()];
    if[(99h=type benchmarkAnalysis) and 1b~benchmarkAnalysis[`gate;`enabled] and
       not 1b~benchmarkAnalysis[`gate;`passed];
        -1 "TOTAL FAILURES: benchmark regression gate";
        -1 .resq.color[`red;"Tests FAILED."];
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

    / Benchmark measurements from perf blocks. Printed whenever any ran, pass or
    / fail: the point of a benchmark is the number, not only the verdict.
    / NB: not named `perf` -- the DSL exports `perf` into .q, and q signals
    / 'assign for a local shadowing a .q name (only bites lazily-loaded modules).
    perfRows: @[get; `.tst.app.perfResults; {()}];
    if[98h = type perfRows; if[count perfRows;
        -1 "\n----------------------------------------------------------------";
        -1 "PERFORMANCE (", string[count perfRows], " benchmark", $[1 = count perfRows; ""; "s"], "):";
        { [r]
            line: "  ", string[r`suite], ": ", string[r`description];
            line,: "  avg ", .tst.fmtMs[r`avgTimeMs], "ms";
            line,: " (min ", .tst.fmtMs[r`minTimeMs], " / max ", .tst.fmtMs[r`maxTimeMs];
            line,: " / sd ", .tst.fmtMs[r`devTimeMs], ")";
            line,: " over ", string[r`runs], " runs";
            if[not null r`avgSpaceBytes; line,: ", ", string[`long$r`avgSpaceBytes], " bytes"];
            / Show the budget alongside the measurement so the margin is visible.
            if[not null r`timeLimitMs;    line,: "  [limit ", .tst.fmtMs[r`timeLimitMs], "ms]"];
            if[not null r`spaceLimitBytes; line,: "  [limit ", string[`long$r`spaceLimitBytes], " bytes]"];
            if[(99h=type r`comparison) and `classification in key r`comparison;
                line,:"  [",.tst.toString[r[`comparison;`classification]],
                    $[null r[`comparison;`relativeChangePercent];"";
                      " ",.Q.f[2;"f"$r[`comparison;`relativeChangePercent]],"%"],"]"];
            -1 line;
        } each perfRows;
    ]];

    if[count results;
        -1 "\n----------------------------------------------------------------";
        -1 "SLOWEST TESTS (TOP 5):";
        / q's take (#) WRAPS when fewer rows exist, repeating entries on small
        / suites; `5 sublist` caps without wrapping.
        slow: 5 sublist xdesc[ `time; 0!select last time by suite, description from results ];
        { [r] -1 "  ", .Q.s1[r`time], " - ", string[r`suite], ": ", string[r`description] } each slow;
    ];
 };

/ Sub-millisecond benchmarks are common, so a plain `string` of a float prints
/ scientific notation. .Q.f gives fixed-decimal formatting.
.tst.fmtMs:{[v]
    if[null v; :"n/a"];
    .Q.f[4; "f"$v]
 };

.resq.report: .resq.reportText;
