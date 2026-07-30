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

    outFile:.tst.reportOutputPath "test-results.json";
    .tst.publishReportText[outFile;jsonReport];
    -1 "JSON Report written to ", outFile;
    ::
 };
