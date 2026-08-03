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

/ First line of a message, for use in an XML ATTRIBUTE. Attribute-value
/ normalization collapses newlines to spaces, so a multi-line message becomes an
/ unreadable run-on there; the element body keeps the full text. A trailing " ..."
/ marks that more detail follows rather than implying the message ended.
.tst.output.firstLine:{[val]
    s: .tst.toString val;
    if[0 = count s; :""];
    lines: "\n" vs s;
    head: first lines;
    / Drop a trailing CR from CRLF input so it cannot reach the attribute.
    if[(count head) and "\r" = last head; head: -1 _ head];
    rest: 1 _ lines;
    hasMore: any 0 < count each rest;
    $[hasMore; head, " ..."; head]
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
    / classname fallback chain: suite name -> namespace -> "resq". The suite name
    / leads deliberately. A test's namespace is its generated SANDBOX name, which
    / embeds the file's absolute path (.sandbox_S_home_user_proj_tests_x_q_a1b2c3):
    / it changes with the checkout directory, so CI systems that group or trend by
    / classname fragment across machines and can never match a historical run.
    / The suite title is stable and is what a human reads in the CI UI. Namespace
    / survives as a fallback for rows with no suite, and in full in the JSON report.
    recNs:     $[`namespace in key rec; .tst.toString rec`namespace; ""];
    recSuiteName: $[`suite in key rec; .tst.toString rec`suite; ""];
    recSuite:  $[0 < count recSuiteName; recSuiteName;
                 0 < count recNs; recNs;
                 "resq"];
    name: .tst.output.escapeXml rec`description;
    statusDesc: $[0=count rec`description; "unspecified"; .tst.toString rec`description];
    suite: .tst.output.escapeXml recSuite;
    / The message column carries the raw failures LIST (a list of strings) built
    / upstream. Render it to a single plain char vector (joined with "\n", capped
    / at reportLimit) so escapeXml never emits the q literal form (`,"..."` ->
    / `,&quot;...`). Fall back to escapeXml directly if the helper isn't loaded.
    rawMsg: $[`renderReportMessage in key `.tst; .tst.renderReportMessage rec`message; rec`message];
    msg: .tst.output.escapeXml rawMsg;
    / XML attribute-value normalization (XML 1.0 §3.3.3) turns a literal newline
    / into a space, so a multi-line error crammed into message="..." reaches the
    / consumer as one run-on line. Put a single-line summary in the attribute and
    / keep the full text in the element body, which preserves newlines verbatim.
    msgAttr: .tst.output.escapeXml .tst.output.firstLine rawMsg;
    t: .tst.output.toSeconds $[`time in key rec; rec`time; 0Nn];
    attrs: " classname=\"", suite, "\" name=\"", .tst.output.escapeXml[statusDesc], "\" time=\"", string[t], "\"";
    if[`file in key rec;
        fileStr: .tst.toString rec`file;
        if[count fileStr; attrs,: " file=\"", .tst.output.escapeXml[fileStr], "\""];
    ];
    if[`line in key rec;
        sourceLine: "i"$rec`line;
        if[(not null sourceLine) and sourceLine > 0;
            attrs,: " line=\"", string[sourceLine], "\""];
    ];
    caseOpen: "    <testcase",attrs,">";
    caseClose: "    </testcase>";
    if[recStatus in `pass;
        :caseOpen,caseClose
    ];
    if[recStatus in `skip`pending;
        reason: $[count rawMsg; msg; "Skipped"];
        reasonAttr: $[count rawMsg; msgAttr; "Skipped"];
        :caseOpen,"    <skipped message=\"",reasonAttr,"\">",reason,"</skipped>",caseClose
    ];
    if[(recStatus ~ `error) or recStatus like "*Error";
        :caseOpen,"    <error message=\"",msgAttr,"\">",msg,"</error>",caseClose
    ];
    :caseOpen,"    <failure message=\"",msgAttr,"\">",msg,"</failure>",caseClose
 };

/ Named per-format so a later loadOutputModule call can re-select the builder:
/ .utl.require is idempotent, so junit-then-xunit in one process would
/ otherwise leave .tst.output.top pointing at whichever loaded first.
.tst.output.junitTop:{[results]
    rows: .tst.output.normalizeRows results;
    if[0=count rows; :"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<testsuites></testsuites>"];
    / normalizeRows may hand back either a list of row dicts or an already
    / assembled table; .tst.resultTable canonicalises both to a 98h table.
    t: .tst.resultTable results;
    if[not 98h = type t; :"<testsuites><testsuite name=\"resq\"/></testsuites>"];

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
        suiteTime: sum suiteRows`time;
        suiteTimeSec: .tst.output.toSeconds suiteTime;
        header: "<testsuite name=\"",suiteName,"\" tests=\"",string[testCount],"\" failures=\"",string[failCount],"\" errors=\"",string[errCount],"\" skipped=\"",string[skipCount],"\" time=\"",string[suiteTimeSec],"\">";
        bodyLines: .tst.output.buildJUnitCase each suiteRows;
        body: "\n" sv bodyLines;
        footer: "</testsuite>";
        $[0<count body; header,"\n",body,"\n",footer; header,"\n",footer]
    }[t;] each suites;

    statusNorm: .tst.normalizeResultStatus each t`status;
    rootOpen: "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<testsuites tests=\"",
        string[count t], "\" failures=\"", string[sum statusNorm = `fail],
        "\" errors=\"", string[sum statusNorm = `error], "\" skipped=\"",
        string[sum statusNorm in `skip`pending], "\" time=\"",
        string[.tst.output.toSeconds sum t`time], "\">";
    rootOpen,"\n",suiteBlocks,"\n</testsuites>"
 };

.tst.output.top: .tst.output.junitTop;
