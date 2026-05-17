.tst.output.escapeXml:{[value]
    s: .tst.toString value;
    if[0=count s; :""];
    s: ssr[s;"&";"&amp;"];
    s: ssr[s;"<";"&lt;"];
    s: ssr[s;">";"&gt;"];
    s: ssr[s;"\"";"&quot;"];
    s: ssr[s;"'";"&apos;"];
    s
 };

.tst.output.toMillis:{[v]
    raw: $[0h = type v; 0N; 98h = type v; first v; v];
    if[-16h = type raw; raw*1e-9; 0f]
 };

.tst.output.normalizeRows:{[rows]
    .tst.resultRows rows
 };

.tst.output.buildJUnitCase:{[rec]
    recStatus: .tst.normalizeResultStatus $[`status in key rec; rec`status; `pass];
    recSuite:  $[`namespace in key rec; rec`namespace; ""];
    name: .tst.output.escapeXml rec`description;
    statusDesc: $[0=count rec`description; "unspecified"; .tst.toString rec`description];
    suite: .tst.output.escapeXml recSuite;
    msg: .tst.output.escapeXml rec`message;
    t: .tst.output.toMillis $[`time in key rec; rec`time; 0Nn];
    attrs: " classname=\"", suite, "\" name=\"", .tst.output.escapeXml statusDesc, "\" time=\"", string t, "\"";
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

.tst.output.top:{[results]
    rows: .tst.output.normalizeRows results;
    if[0=count rows; :"<testsuites></testsuites>"];
    t: flip rows;
    if[not 98h = type t; :"<testsuites><testsuite name=\"resq\"/>"];

    suites: distinct t`suite;
    suiteBlocks: raze {
        suiteName: .tst.output.escapeXml x;
        suiteRows: t where t`suite = x;
        testCount: count suiteRows;
        suiteStatus: .tst.normalizeResultStatus each suiteRows`status;
        errMask: suiteStatus = `error;
        skipMask: suiteStatus in `skip`pending;
        failMask: suiteStatus = `fail;
        failCount: sum failMask;
        errCount: sum errMask;
        skipCount: sum skipMask;
        suiteTime: sum suiteRows`time;
        suiteTimeSec: .tst.output.toMillis suiteTime;
        header: "<testsuite name=\"",suiteName,"\" tests=\"",string testCount,"\" failures=\"",string failCount,"\" errors=\"",string errCount,"\" skipped=\"",string skipCount,"\" time=\"",string[suiteTimeSec],"\">";
        bodyLines: .tst.output.buildJUnitCase each suiteRows;
        body: "\n" sv bodyLines;
        footer: "</testsuite>";
        $[0<count body; header,"\n",body,"\n",footer; header,"\n",footer]
    } each suites;

    "<testsuites>\n",suiteBlocks,"\n</testsuites>"
 };
