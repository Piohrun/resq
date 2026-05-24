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
    payload: summary, enlist[`tests]!enlist reportRows;
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
