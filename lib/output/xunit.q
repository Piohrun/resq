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
    $[-16h = type raw; raw % 1e9; 0f]
 };

.tst.output.normalizeRows:{[rows]
    .tst.resultRows rows
 };

.tst.output.buildXunitCase:{[rec]
    recStatus: .tst.normalizeResultStatus $[`status in key rec; rec`status; `pass];
    recSuite:  $[`namespace in key rec; rec`namespace; ""];
    statusDesc: $[0<count rec`description; .tst.toString rec`description; "unspecified"];
    suite: .tst.output.escapeXml recSuite;
    msg: .tst.output.escapeXml rec`message;
    t: .tst.output.toSeconds $[`time in key rec; rec`time; 0Nn];
    attrs: " type=\"", suite, "\" name=\"", .tst.output.escapeXml[statusDesc], "\" time=\"", string[t], "\"";
    caseOpen: "    <test",attrs,">";
    caseClose: "    </test>";
    if[recStatus in `pass;
        :caseOpen,caseClose
    ];
    if[recStatus in `skip`pending;
        :caseOpen,"    <reason/>",caseClose
    ];
    if[(recStatus ~ `error) or recStatus like "*Error";
        :caseOpen,"    <error message=\"",msg,"\">",msg,"</error>",caseClose
    ];
    :caseOpen,"    <failure message=\"",msg,"\">",msg,"</failure>",caseClose
 };

.tst.output.top:{[results]
    rows: .tst.output.normalizeRows results;
    if[0=count rows; :"<assemblies></assemblies>"];
    / normalizeRows may hand back either a list of row dicts or an already
    / assembled table; .tst.resultTable canonicalises both to a 98h table.
    t: .tst.resultTable results;
    if[not 98h = type t; :"<assemblies/>"];

    suites: distinct t`suite;
    / q lambdas do not close over outer locals, so the per-suite table t is
    / passed in explicitly as the first projected argument.
    suiteBlocks: raze {[t; x]
        suiteName: .tst.output.escapeXml x;
        suiteRows: t where (t`suite) = x;
        testCount: count suiteRows;
        suiteStatus: .tst.normalizeResultStatus each suiteRows`status;
        errMask: suiteStatus = `error;
        skipMask: suiteStatus in `skip`pending;
        failMask: suiteStatus = `fail;
        failCount: sum failMask;
        errCount: sum errMask;
        skipCount: sum skipMask;
        suiteTime: .tst.output.toSeconds sum suiteRows`time;
        header: "<assembly name=\"",suiteName,"\" total=\"",string[testCount],"\" failures=\"",string[failCount],"\" errors=\"",string[errCount],"\" skipped=\"",string[skipCount],"\" time=\"",string[suiteTime],"\">";
        bodyLines: .tst.output.buildXunitCase each suiteRows;
        body: "\n" sv bodyLines;
        footer: "</assembly>";
        $[0<count body; header,"\n",body,"\n",footer; header,"\n",footer]
    }[t;] each suites;

    "<assemblies>\n",suiteBlocks,"\n</assemblies>"
 };
