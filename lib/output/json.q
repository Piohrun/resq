/ JSON reporter.

.resq.reportJson:{[results]
    reportRows: .tst.resultRows results;
    reportTable: .tst.resultTableFromRows reportRows;
    summaryStats: .tst.resultSummaryFromTable reportTable;
    summary: (`fmt`suiteCount`testCount`failCount`errorCount`skipCount`duration)!(
        `json;
        summaryStats`suiteCount;
        summaryStats`testCount;
        summaryStats`failCount;
        summaryStats`errorCount;
        summaryStats`skipCount;
        string summaryStats`duration
    );
    summaryJson:.j.j summary;
    if[(not 10h=type summaryJson) or
       (not count summaryJson) or
       not "}"=last summaryJson;
      '"JSON report summary serialization failed"];
    state:.tst.reportLineState[];
    state:.tst.appendReportLine[
      state;
      (-1 _ summaryJson),",\"tests\":["];
    index:0;
    while[index<count reportRows;
      rowJson:.j.j reportRows index;
      if[not 10h=type rowJson;
        '"JSON report row serialization failed"];
      line:$[0=index;rowJson;",",rowJson];
      state:.tst.appendReportLine[state;line];
      index+:1];
    state:.tst.appendReportLine[state;"]}"];

    outFile:.tst.reportOutputPath "test-results.json";
    .tst.publishReportText[outFile;.tst.reportLines state];
    -1 "JSON Report written to ", outFile;
    ::
 };
