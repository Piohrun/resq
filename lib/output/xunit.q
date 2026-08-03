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

.tst.output.xunitUuid:{[seed]
    h: raze string md5 .tst.toString seed;
    (8 # h), "-", (4 # 8 _ h), "-", (4 # 12 _ h), "-",
        (4 # 16 _ h), "-", (12 # 20 _ h)
 };

.tst.output.xunitTimestamp:{[]
    parts: "D" vs string .z.p;
    / xUnit's round-trippable form specifies seven fractional-second digits.
    (ssr[first parts; "."; "-"]), "T", (16 # last parts), "Z"
 };

.tst.output.buildXunitCase:{[rec;idSeed]
    recStatus: .tst.normalizeResultStatus $[`status in key rec; rec`status; `pass];
    / type/classname fallback chain: suite name -> namespace -> "resq". The suite
    / name leads deliberately: a test's namespace is its generated SANDBOX name,
    / which embeds the file's absolute path, so it changes with the checkout
    / directory and cannot be matched against a historical run. See junit.q.
    recNs:     $[`namespace in key rec; .tst.toString rec`namespace; ""];
    recSuiteName: $[`suite in key rec; .tst.toString rec`suite; ""];
    recSuite:  $[0 < count recSuiteName; recSuiteName;
                 0 < count recNs; recNs;
                 "resq"];
    statusDesc: $[0<count rec`description; .tst.toString rec`description; "unspecified"];
    suite: .tst.output.escapeXml recSuite;
    / The message column carries the raw failures LIST (a list of strings) built
    / upstream. Render it to a single plain char vector (joined with "\n", capped
    / at reportLimit) so escapeXml never emits the q literal form (`,"..."` ->
    / `,&quot;...`). Fall back to escapeXml directly if the helper isn't loaded.
    rawMsg: $[`renderReportMessage in key `.tst; .tst.renderReportMessage rec`message; rec`message];
    msg: .tst.output.escapeXml rawMsg;
    rawOutput: $[`output in key rec; .tst.toString rec`output; ""];
    outputNode: $[count rawOutput;
        "<output>",.tst.output.escapeXml[rawOutput],"</output>";
        ""];
    t: .tst.output.toSeconds $[`time in key rec; rec`time; 0Nn];
    / xUnit v2 has no per-test Error outcome: an errored resQ expectation is a
    / failed test with a distinct exception-type on its <failure> node.
    resultWord: $[recStatus in `pass;         "Pass";
                  recStatus in `skip`pending; "Skip";
                  "Fail"];
    testId: .tst.output.xunitUuid idSeed;
    attrs: " id=\"", testId, "\" type=\"", suite, "\" name=\"",
           .tst.output.escapeXml[statusDesc], "\" time=\"", string[t],
           "\" result=\"", resultWord, "\"";
    if[`file in key rec;
        fileStr: .tst.toString rec`file;
        if[count fileStr; attrs,: " source-file=\"", .tst.output.escapeXml[fileStr], "\""];
    ];
    if[`line in key rec;
        sourceLine: "i"$rec`line;
        if[(not null sourceLine) and sourceLine > 0;
            attrs,: " source-line=\"", string[sourceLine], "\""];
    ];
    caseOpen: "      <test",attrs,">";
    caseClose: "      </test>";
    if[recStatus in `pass;
        :caseOpen,outputNode,caseClose
    ];
    if[recStatus in `skip`pending;
        reason: $[count rawMsg; msg; "Skipped"];
        :caseOpen,"\n        <reason>",reason,"</reason>\n",outputNode,caseClose
    ];
    failureType: $[(recStatus ~ `error) or recStatus like "*Error";
                   "resQ.Error";
                   "resQ.AssertionFailure"];
    :caseOpen,"\n        <failure exception-type=\"",failureType,"\"><message>",msg,
        "</message></failure>\n",outputNode,caseClose
 };

/ Named per-format so a later loadOutputModule call can re-select the builder:
/ .utl.require is idempotent, so junit-then-xunit in one process would
/ otherwise leave .tst.output.top pointing at whichever loaded first.
.tst.output.xunitTop:{[results]
    rows: .tst.output.normalizeRows results;
    stamp: .tst.output.xunitTimestamp[];
    runSeed: stamp, "/", string .z.i;
    rootOpen: "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<assemblies schema-version=\"2\" id=\"",
        .tst.output.xunitUuid[runSeed], "\" start-rtf=\"", stamp,
        "\" finish-rtf=\"", stamp, "\" timestamp=\"", stamp, "\">";
    if[0=count rows; :rootOpen,"\n</assemblies>"];
    / normalizeRows may hand back either a list of row dicts or an already
    / assembled table; .tst.resultTable canonicalises both to a 98h table.
    t: .tst.resultTable results;
    if[not 98h = type t; :"<assemblies/>"];

    statuses: .tst.normalizeResultStatus each t`status;
    totalCount: count t;
    passCount: sum statuses = `pass;
    failedCount: sum statuses in `fail`error;
    skipCount: sum statuses in `skip`pending;
    totalTime: .tst.output.toSeconds sum t`time;
    framework: "resQ ", $[`VERSION in key `.resq; .tst.toString .resq.VERSION; "unknown"];
    assemblyName: $[`HOME in key `.resq; .tst.toString[.resq.HOME], "/resq.q"; "resQ"];
    runDate: 10 # stamp;
    runTime: 8 # 11 _ stamp;
    assemblyId: .tst.output.xunitUuid runSeed, "/assembly";
    assemblyOpen: "  <assembly id=\"", assemblyId, "\" name=\"",
        .tst.output.escapeXml[assemblyName], "\" environment=\"kdb+ q ",
        .tst.output.escapeXml[string .z.K], "\" test-framework=\"",
        .tst.output.escapeXml[framework], "\" run-date=\"", runDate,
        "\" run-time=\"", runTime, "\" total=\"", string[totalCount],
        "\" passed=\"", string[passCount], "\" failed=\"", string[failedCount],
        "\" skipped=\"", string[skipCount], "\" errors=\"0\" time=\"",
        string[totalTime], "\" not-run=\"0\">";

    suites: distinct t`suite;
    collectionBlocks: raze {[t;runSeed;x]
        suiteName: .tst.output.escapeXml x;
        suiteRows: t where (t`suite) = x;
        testCount: count suiteRows;
        suiteStatus: .tst.normalizeResultStatus each suiteRows`status;
        skipMask: suiteStatus in `skip`pending;
        failMask: suiteStatus in `fail`error;
        failCount: sum failMask;
        skipCount: sum skipMask;
        passCount: sum suiteStatus = `pass;
        suiteTime: .tst.output.toSeconds sum suiteRows`time;
        collectionId: .tst.output.xunitUuid runSeed, "/collection/", .tst.toString x;
        header: "    <collection id=\"", collectionId, "\" name=\"", suiteName,
            "\" total=\"", string[testCount], "\" passed=\"", string[passCount],
            "\" failed=\"", string[failCount], "\" skipped=\"", string[skipCount],
            "\" time=\"", string[suiteTime], "\" not-run=\"0\">";
        indices: til count suiteRows;
        bodyLines: {[rs;seed;i]
            .tst.output.buildXunitCase[rs i; seed, "/test/", string i]
          }[suiteRows;collectionId;] each indices;
        body: "\n" sv bodyLines;
        footer: "    </collection>";
        $[0<count body; header,"\n",body,"\n",footer; header,"\n",footer]
    }[t;runSeed;] each suites;

    rootOpen,"\n",assemblyOpen,"\n",collectionBlocks,
        "\n  </assembly>\n</assemblies>"
 };

.tst.output.top: .tst.output.xunitTop;
