/ JSON reporter.

.tst.output.jsonDurationSeconds:{[v]
    raw: $[0h = type v; 0N; 98h = type v; first v; v];
    $[null raw; 0f; -16h = type raw; raw % 1e9; 0f]
 };

/ Stable schema-v1 test row. In particular `message is ALWAYS a string and
/ `failures is ALWAYS a list of strings; q's native values otherwise make the
/ JSON type depend on pass/fail/error status.
.tst.output.jsonRow:{[row]
    out: row;
    rawMsg: $[`message in key row; row`message; ""];
    out[`message]: .tst.renderReportMessage rawMsg;
    rawFailures: $[`failures in key row; row`failures; ()];
    out[`failures]: $[0 = count rawFailures; ();
                      10h = type rawFailures; enlist rawFailures;
                      0h = type rawFailures;
                        {[v] $[10h = type v; v; .tst.toString v]} each rawFailures;
                      enlist .tst.toString rawFailures];
    rawTime: $[`time in key row; row`time; 0Nn];
    out[`time]: string rawTime;
    out[`durationSeconds]: .tst.output.jsonDurationSeconds rawTime;
    if[not `file in key out; out[`file]: ""];
    if[not `line in key out; out[`line]: 0Ni];
    if[not `namespace in key out; out[`namespace]: ""];
    if[not `tags in key out; out[`tags]: `symbol$()];
    rawOutput: $[`output in key out; out`output; ""];
    out[`output]: .tst.stripAnsi .tst.renderReportMessage rawOutput;
    out
 };

.resq.reportJson:{[results]
    rawRows: .tst.resultRows results;
    reportTable: .tst.resultTable rawRows;
    summaryStats: .tst.resultSummary reportTable;
    reportRows: .tst.output.jsonRow each rawRows;
    summary: (`schemaVersion`framework`frameworkVersion`fmt`suiteCount`testCount`assertionCount`passCount`failCount`errorCount`skipCount`duration`durationSeconds)!(
        1;
        "resQ";
        $[`VERSION in key `.resq; .tst.toString .resq.VERSION; "unknown"];
        `json;
        summaryStats`suiteCount;
        summaryStats`testCount;
        summaryStats`assertsRun;
        summaryStats`passCount;
        summaryStats`failCount;
        summaryStats`errorCount;
        summaryStats`skipCount;
        string summaryStats`duration;
        .tst.output.jsonDurationSeconds summaryStats`duration
    );
    / Benchmark measurements from perf blocks, so a dashboard can chart timings
    / over releases rather than only seeing pass/fail. Absent when none ran, so
    / the document shape is unchanged for suites without benchmarks.
    / NB: not named `perf` -- the DSL exports `perf` into .q, and q signals
    / 'assign for a local shadowing a .q name (only bites lazily-loaded modules).
    perfRows: @[get; `.tst.app.perfResults; {()}];
    payload: summary, enlist[`tests]!enlist reportRows;
    if[98h = type perfRows; if[count perfRows;
        payload: payload, enlist[`performance]!enlist 0!perfRows]];
    if[1b ~ @[get; `.tst.app.runCoverage; 0b];
        coverageStats: @[get; `.tst.lastCoverageSummary; {()!()}];
        if[99h = type coverageStats;
            coverageStats: coverageStats,
                `minimum`passed`basis!(
                    @[get; `.tst.app.coverageMin; 0];
                    @[get; `.tst.app.coveragePercent; 0f] >= @[get; `.tst.app.coverageMin; 0];
                    @[get; `.tst.app.coverageBasis; "functions"]);
            payload: payload, enlist[`coverage]!enlist coverageStats;
        ];
    ];
    jsonReport: .j.j payload;

    outDirStr: .tst.toString .resq.config.outDir;
    if[0 = count outDirStr; outDirStr: "."];
    baseDirStr: .tst.toString .tst.app.baseDir;
    if[0 = count baseDirStr; baseDirStr: system "cd"];
    if[not outDirStr like "/*"; outDirStr: baseDirStr, "/", outDirStr];
    outDirStr: .utl.normalizePath outDirStr;
    outFile: outDirStr, "/test-results.json";
    .utl.ensureDir outDirStr;
    hsym[`$outFile] 0: enlist jsonReport;
    -1 "JSON Report written to ", outFile;
 };
