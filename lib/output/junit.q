.tst.output.escapeXml:{[val]
    s: .tst.toString val;
    if[0=count s; :""];
    s: ssr[s;"&";"&amp;"];
    s: ssr[s;"<";"&lt;"];
    s: ssr[s;">";"&gt;"];
    s: ssr[s;"\"";"&quot;"];
    s: ssr[s;"'";"&apos;"];
    / Strip control chars (0x00-0x1F) illegal in XML 1.0, keeping tab/LF/CR.
    s: s where (s in "\t\n\r") or not s within ("\000";"\037");
    s
 };

.tst.output.toSeconds:{[v]
    raw: $[0h = type v; 0N; 98h = type v; first v; v];
    / Null guard FIRST: a null timespan/float (e.g. 0Nn from a synthetic row)
    / would otherwise become 0Nf -> string "" -> time="" (invalid xsd:decimal).
    $[null raw; 0f; -16h = type raw; raw % 1e9; 0f]
 };

.tst.output.normalizeRows:{[rows]
    .tst.resultRows rows
 };

.tst.output.buildJUnitCase:{[rec]
    recStatus: .tst.normalizeResultStatus $[`status in key rec; rec`status; `pass];
    / classname fallback chain: namespace -> suite name -> "resq". An empty
    / namespace would otherwise emit classname="" and group poorly in CI UIs.
    recNs:     $[`namespace in key rec; .tst.toString rec`namespace; ""];
    recSuiteName: $[`suite in key rec; .tst.toString rec`suite; ""];
    recSuite:  $[0 < count recNs; recNs;
                 0 < count recSuiteName; recSuiteName;
                 "resq"];
    statusDesc: $[0=count rec`description; "unspecified"; .tst.toString rec`description];
    suite: .tst.output.escapeXml recSuite;
    / The message column carries the raw failures LIST (a list of strings) built
    / upstream. Render it to a single plain char vector (joined with "\n", capped
    / at reportLimit) so escapeXml never emits the q literal form (`,"..."` ->
    / `,&quot;...`). Fall back to escapeXml directly if the helper isn't loaded.
    rawMsg: $[`renderReportMessage in key `.tst; .tst.renderReportMessage rec`message; rec`message];
    msg: .tst.output.escapeXml rawMsg;
    t: .tst.output.toSeconds $[`time in key rec; rec`time; 0Nn];
    attrs: " classname=\"", suite, "\" name=\"", .tst.output.escapeXml[statusDesc], "\" time=\"", string[t], "\"";
    caseOpen: "    <testcase",attrs,">";
    caseClose: "    </testcase>";
    if[recStatus in `pass;
        :caseOpen,caseClose
    ];
    if[recStatus in `skip`pending;
        :caseOpen,"    <skipped/>",caseClose
    ];
    if[(recStatus ~ `error) or recStatus like "*Error";
        :caseOpen,"    <error message=\"",msg,"\">",msg,"</error>",caseClose
    ];
    :caseOpen,"    <failure message=\"",msg,"\">",msg,"</failure>",caseClose
 };

.tst.output.junitTop:{[results]
    rows: .tst.output.normalizeRows results;
    state:.tst.reportLineState[];
    if[0=count rows;
        state:.tst.appendReportLine[
          state;
          "<testsuites></testsuites>"];
        :.tst.finalizeReportLines state];
    / Rows have already crossed the reporter boundary; assembling them directly
    / avoids repeating normalization and its allocation cost.
    t: .tst.resultTableFromRows rows;

    groups:group t`suite;
    suites:key groups;
    groupRows:value groups;
    state:.tst.appendReportLine[state;"<testsuites>"];
    suiteIndex:0;
    while[suiteIndex<count suites;
        suiteName:.tst.output.escapeXml suites suiteIndex;
        rowIndices:(),groupRows suiteIndex;
        suiteRows:t rowIndices;
        testCount: count suiteRows;
        suiteStatus: .tst.normalizeResultStatus each suiteRows`status;
        errMask: suiteStatus = `error;
        skipMask: suiteStatus in `skip`pending;
        failMask: suiteStatus = `fail;
        failCount: sum failMask;
        errCount: sum errMask;
        skipCount: sum skipMask;
        suiteTime: sum suiteRows`time;
        suiteTimeSec: .tst.output.toSeconds suiteTime;
        header: "<testsuite name=\"",suiteName,"\" tests=\"",string[testCount],"\" failures=\"",string[failCount],"\" errors=\"",string[errCount],"\" skipped=\"",string[skipCount],"\" time=\"",string[suiteTimeSec],"\">";
        state:.tst.appendReportLine[state;header];
        rowIndex:0;
        while[rowIndex<testCount;
          state:.tst.appendReportLine[
            state;
            .tst.output.buildJUnitCase suiteRows rowIndex];
          rowIndex+:1];
        state:.tst.appendReportLine[state;"</testsuite>"];
        suiteIndex+:1];
    state:.tst.appendReportLine[state;"</testsuites>"];
    .tst.finalizeReportLines state
 };

/ Compatibility alias. loadOutputModule re-selects this named builder even
/ when the module is already present in the require registry.
.tst.output.top:.tst.output.junitTop;
