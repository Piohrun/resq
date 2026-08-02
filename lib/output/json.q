/ JSON reporter.

.resq.reportJson:{[results]
    reportRows: .tst.resultRows results;
    reportTable: .tst.resultTable reportRows;
    summaryStats: .tst.resultSummary reportTable;
    summary: (`fmt`suiteCount`testCount`failCount`errorCount`skipCount`duration)!(
        `json;
        summaryStats`suiteCount;
        summaryStats`testCount;
        summaryStats`failCount;
        summaryStats`errorCount;
        summaryStats`skipCount;
        string summaryStats`duration
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
