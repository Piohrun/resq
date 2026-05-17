/ JSON reporter.

/ JSON reporter.

.resq.reportJson:{[results]
    reportRows: .tst.resultRows results;
    reportTable: .tst.resultTable reportRows;
    statusNorm: .tst.normalizeResultStatus each reportTable`status;
    summary: (`fmt`suiteCount`testCount`failCount`errorCount`skipCount`duration)!(
        `json;
        count distinct reportTable`suite;
        count reportTable;
        sum statusNorm = `fail;
        sum statusNorm = `error;
        sum statusNorm in `skip`pending;
        string sum $[98h = type reportTable; reportTable`time; 0N]
    );
    payload: summary, enlist[`tests]!enlist reportRows;
    jsonReport: .j.j payload;

    outDirStr: .tst.toString .resq.config.outDir;
    if[0 = count outDirStr; outDirStr: "."];
    baseDirStr: .tst.toString .tst.app.baseDir;
    if[0 = count baseDirStr; baseDirStr: system "cd"];
    if[not outDirStr like "/*"; outDirStr: baseDirStr, "/", outDirStr];
    outDirStr: .utl.normalizePath outDirStr;
    outFile: outDirStr, "/test-results_", string[.z.i], ".json";
    .utl.ensureDir outDirStr;
    hsym[`$outFile] 0: enlist jsonReport;
    -1 "JSON Report written to ", outFile;
 };
