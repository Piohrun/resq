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

.tst.output.buildXunitCase:{[rec]
    recStatus: .tst.normalizeResultStatus $[`status in key rec; rec`status; `pass];
    / type/classname fallback chain: namespace -> suite name -> "resq". An empty
    / namespace would otherwise emit type="" and group poorly in CI UIs.
    recNs:     $[`namespace in key rec; .tst.toString rec`namespace; ""];
    recSuiteName: $[`suite in key rec; .tst.toString rec`suite; ""];
    recSuite:  $[0 < count recNs; recNs;
                 0 < count recSuiteName; recSuiteName;
                 "resq"];
    statusDesc: $[0<count rec`description; .tst.toString rec`description; "unspecified"];
    suite: .tst.output.escapeXml recSuite;
    / The message column carries the raw failures LIST (a list of strings) built
    / upstream. Render it to a single plain char vector (joined with "\n", capped
    / at reportLimit) so escapeXml never emits the q literal form (`,"..."` ->
    / `,&quot;...`). Fall back to escapeXml directly if the helper isn't loaded.
    rawMsg: $[`renderReportMessage in key `.tst; .tst.renderReportMessage rec`message; rec`message];
    msg: .tst.output.escapeXml rawMsg;
    t: .tst.output.toSeconds $[`time in key rec; rec`time; 0Nn];
    / xUnit v2 consumers read per-test status from `result`, NOT from the
    / presence of a child element. Without it every test is indeterminate and a
    / red run can be read as green. An errored test reports Fail: the schema has
    / no third outcome, and the <error> child still carries the detail.
    resultWord: $[recStatus in `pass;         "Pass";
                  recStatus in `skip`pending; "Skip";
                  "Fail"];
    attrs: " type=\"", suite, "\" name=\"", .tst.output.escapeXml[statusDesc],
           "\" time=\"", string[t], "\" result=\"", resultWord, "\"";
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

/ Named per-format so a later loadOutputModule call can re-select the builder:
/ .utl.require is idempotent, so junit-then-xunit in one process would
/ otherwise leave .tst.output.top pointing at whichever loaded first.
.tst.output.xunitTop:{[results]
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
        / xUnit v2 names the pass/fail totals `passed`/`failed`; `failures` is
        / JUnit's spelling. Emit both so either consumer reads real numbers.
        passCount: sum suiteStatus = `pass;
        suiteTime: .tst.output.toSeconds sum suiteRows`time;
        header: "<assembly name=\"",suiteName,"\" total=\"",string[testCount],"\" passed=\"",string[passCount],"\" failed=\"",string[failCount],"\" failures=\"",string[failCount],"\" errors=\"",string[errCount],"\" skipped=\"",string[skipCount],"\" time=\"",string[suiteTime],"\">";
        bodyLines: .tst.output.buildXunitCase each suiteRows;
        body: "\n" sv bodyLines;
        footer: "</assembly>";
        $[0<count body; header,"\n",body,"\n",footer; header,"\n",footer]
    }[t;] each suites;

    "<assemblies>\n",suiteBlocks,"\n</assemblies>"
 };

.tst.output.top: .tst.output.xunitTop;
