.tst.desc["Output Module Support"]{
    should["load text output module"]{
        .tst.loadOutputModule["text"];
        must[`reportText in key `.resq; "the text module must publish .resq.reportText"];
    };

    should["load console alias as text module"]{
        .tst.app.xmlOutput: 0b;
        .tst.loadOutputModule["console"];
        must[`reportText in key `.resq; "the console alias must resolve to the text module"];
    };

    should["load uppercase aliases safely"]{
        .tst.app.xmlOutput: 0b;
        .tst.loadOutputModule["XML"];
        must[`top in key `.tst.output; "an uppercase alias must still load the xml module"];
    };

    should["reporting mode can map xml format to junit output"]{
        prevFmt: .resq.config.fmt;
        prevXmlOutput: .tst.app.xmlOutput;
        prevReport: .resq.report;
        .resq.config.fmt: `xml;
        .tst.initReporting[];
        result: .tst.app.xmlOutput and (`top in key `.tst.output);
        .resq.config.fmt: prevFmt;
        .tst.app.xmlOutput: prevXmlOutput;
        .resq.report: prevReport;
        must[result; "fmt `xml must select the junit/xml reporter and publish .tst.output.top"];
    };

    should["sanitize converts suite specs into flat rows"]{
        spec: `title`expectations`result!(
            "Suite A";
            (`desc`result`time`message`failures!("Example";`pass;0Nn;"ok";()));
            `pass
        );
        rows: .tst.sanitize spec;
        firstRow: rows 0;
        musteq[firstRow`status; `pass];
        musteq[firstRow`suite; "Suite A"];
        musteq[firstRow`description; "Example"];
    };

    should["unknown output module is warned and rejected safely"]{
        0b musteq .tst.loadOutputModule["missing-module"];
    };

    should["builds canonical report topology once for multi-format dispatch"]{
        .tst.testState.canonicalBuilds:0;
        .tst.testState.canonicalStub:`diagnostics`manifest!(();()!());
        `.tst.canonicalRunModel mock {[rows]
            .tst.testState.canonicalBuilds+:1;
            .tst.testState.canonicalStub};
        `.tst.canonicalDiagnosticOverlay mock {[model]model};
        `.resq.reportText mock {[model]::};
        `.resq.reportJson mock {[model]::};
        rows:enlist `suite`description`status`message`time`failures`assertsRun!(
            "S";"ok";`pass;"";0Nn;();1i);
        .resq.reportSelected[`text`json;11b;rows];
        .tst.testState.canonicalBuilds musteq 1;
    };

    should["tries every selected reporter and then fails closed"]{
        .tst.loadOutputModule["json"];
        diagnosticsBefore:.tst.app.diagnostics;
        `diagnostics mustin key .tst.captureRunState[];
        .tst.testState.reporterContinuation: 0;
        `.resq.reportJson mock {[rows] '"json exploded"};
        `.resq.reportText mock {[rows] .tst.testState.reporterContinuation+:1; ::};
        rows: enlist `suite`description`status`message`time`failures`assertsRun!(
            "S";"ok";`pass;"";0Nn;();1i);
        outcome:.tst.withIsolatedRunState[{[payload]
            @[
                {[data] .resq.reportSelected[`json`text;11b;data]; (0b;"")};
                payload;
                {[e] (1b;.tst.toString e)}]
          };enlist rows];
        .tst.app.diagnostics mustmatch diagnosticsBefore;
        must[first outcome; "a reporter failure must make the reporting phase fail"];
        .tst.testState.reporterContinuation musteq 1;
        must[(0 < count ss[last outcome;"REPORTER_FAILURE"]) and
             (0 < count ss[last outcome;"json exploded"]);
             "the aggregate error must identify the failed reporter; got ",last outcome];
    };

    should["attempts loaded reporters but fails when a requested module is unavailable"]{
        diagnosticsBefore:.tst.app.diagnostics;
        .tst.testState.availableReporterRan: 0;
        `.resq.reportText mock {[rows] .tst.testState.availableReporterRan+:1; ::};
        rows: enlist `suite`description`status`message`time`failures`assertsRun!(
            "S";"ok";`pass;"";0Nn;();1i);
        outcome:.tst.withIsolatedRunState[{[payload]
            @[
                {[data] .resq.reportSelected[`junit`text;01b;data]; (0b;"")};
                payload;
                {[e] (1b;.tst.toString e)}]
          };enlist rows];
        .tst.app.diagnostics mustmatch diagnosticsBefore;
        must[first outcome; "an unavailable requested reporter must fail the phase"];
        .tst.testState.availableReporterRan musteq 1;
        must[(0 < count ss[last outcome;"junit"]) and
             (0 < count ss[last outcome;"unavailable"]);
             "the error must identify the unavailable requested format"];
    };

    should["writes a parseable XML diagnostic and signals when serialization fails"]{
        reportDir: .utl.tempRoot[], "/resq_reporter_", string[.z.i], "_", string `long$.z.p;
        .utl.ensureDir reportDir;
        .tst.registerCleanup[{[p]
            safePrefix: .utl.tempRoot[], "/resq_reporter_";
            if[p like safePrefix,"*";
                system "rm -rf -- ", .utl.shellQuote p]
        };enlist reportDir];
        `.resq.config.outDir mock reportDir;
        `.tst.app.runOutputDir mock reportDir;
        rows: enlist `suite`description`status`message`time`failures`assertsRun!(
            "S";"ok";`pass;"";0Nn;();1i);
        outcome: @[
            {[payload] .resq.writeXmlReport[payload;{[ignored] '"serialize boom"};"broken.xml"];
                       (0b;"")};
            rows;
            {[e] (1b;.tst.toString e)}];
        artifact: reportDir,"/broken.xml";
        must[first outcome; "XML serialization failure must be signalled"];
        must[0 < count ss[last outcome;"XML reporter failed: serialize boom"];
             "the signal must retain the serializer error"];
        must[.utl.pathExists artifact; "a diagnostic XML artifact must still be written"];
        xml: raze read0 .utl.pathToHsym artifact;
        must[xml like "<?xml version=\"1.0\" encoding=\"UTF-8\"?>*";
             "the fallback artifact must declare its encoding"];
        must[0 < count ss[xml;"<error message=\"reporter_failed\">"];
             "the fallback artifact must expose the reporter error"];
    };

    / --- Fix 1: report message rendering (sanitize.q .tst.renderReportMessage) -
    should["renders a list of two failures joined with newline, no q-literal artifact"]{
        msg: .tst.renderReportMessage ("Expected 1 to match 2"; "second failure line");
        / Joined on "\n", a single plain char vector.
        musteq[10h; type msg];
        musteq[msg; "Expected 1 to match 2\nsecond failure line"];
        / No leading `,"` artifact from -3! on a 1-element list shape.
        must[not "," = first msg; "rendered message must not start with a comma"];
    };

    should["renders a single-element failure list with no leading comma-quote"]{
        msg: .tst.renderReportMessage enlist "Expected 1 to match 2";
        musteq[msg; "Expected 1 to match 2"];
        must[not (msg like ",\"*"); "single failure must not render as the q literal ,\"...\""];
    };

    should["caps a huge failure message at reportLimit with a truncation marker"]{
        limit: .tst.output.reportLimit;
        msg: .tst.renderReportMessage enlist 100000 # "x";
        must[(count msg) <= limit; "message must be capped at reportLimit"];
        / NB: both `like` and `ss` treat "[" as a char-class opener, so detect the
        / marker by a literal sliding-window match over the tail rather than a
        / pattern. The marker always lands in the final stretch of the message.
        marker: "... [truncated ";
        tail: (neg 60) # msg;
        windows: { x (til 1 + (count x) - y) +\: til y }[tail; count marker];
        must[any marker ~/: windows; "truncation marker should be present"];
    };

    / --- Fix 2: stripAnsi edge cases (sanitize.q .tst.stripAnsi) --------------
    should["stripAnsi keeps text after a lone ESC"]{
        esc: "\033";
        musteq[.tst.stripAnsi "before",esc,"AFTER"; "beforeAFTER"];
    };

    should["stripAnsi never loses the tail after a non-SGR escape"]{
        esc: "\033";
        out: .tst.stripAnsi "x",esc,"[2J","TAIL";
        must[out like "*TAIL"; "the tail after a non-SGR sequence must survive"];
    };

    should["stripAnsi fully strips a well-formed SGR colour run"]{
        esc: "\033";
        musteq[.tst.stripAnsi "a",esc,"[31m","red",esc,"[0m","b"; "aredb"];
    };

    should["stripAnsi handles empty string and a lone ESC"]{
        esc: "\033";
        musteq[.tst.stripAnsi ""; ""];
        / A string of only ESC drops to empty without error.
        musteq[.tst.stripAnsi enlist esc; ""];
    };

    / --- Fix 1: SLOWEST TESTS must not repeat rows on small suites (5 sublist) -
    / q's take (#) WRAPS when fewer rows exist (5 # 2-row table -> 5 rows); the
    / reporter uses `5 sublist` which caps without wrapping.
    should["5 sublist caps a small table without repeating rows"]{
        t: ([] description: `a`b);
        musteq[5; count 5 # t];
        musteq[2; count 5 sublist t];
    };

    / --- Fix 2/3: central color gate (.tst.useColor) drives fmt.color ----------
    should["color gate globals are defined at load"]{
        must[`useColor in key `.tst; ".tst.useColor must be defined at load"];
        must[`diffColors in key `.tst; ".tst.diffColors must be defined at load"];
    };

    should["fmt.color emits SGR escapes when the gate is on"]{
        `.tst.useColor mock 1b;
        musteq[.tst.fmt.color[`red; "X"]; "\033[31mX\033[0m"];
    };

    should["fmt.color is plain text with no escapes when the gate is off"]{
        `.tst.useColor mock 0b;
        musteq[.tst.fmt.color[`red; "X"]; "X"];
        must[not any "\033" in .resq.color[`green; "OK"]; "no ESC when color off"];
    };

    should["NO_COLOR env keeps the color gate off"]{
        must[(0 = count getenv `NO_COLOR) or not .tst.useColor; "NO_COLOR set => color off"];
    };

    / --- Fix 4: a single failing assertion renders its message ONCE -----------
    / When the joined failures equal the message, the reporter drops the
    / redundant "Error:" line; this exercises the exact dup predicate it uses.
    should["detects when the message duplicates the failures content"]{
        spec: `title`expectations`result!("S"; enlist (`desc`result`time`message`failures!("t"; `fail; 0Nn; "G"; enlist "G")); `fail);
        r: first .tst.sanitize spec;
        flStr: "\n    " sv .resq.renderMsg each (),r`failures;
        must[(.resq.renderMsg r`message) ~ flStr; "dup message must be detected so it prints once"];
    };

    should["extract final structural diffs without repeating summaries"]{
        marker:.tst.diffDetailMarker;
        message:"Expected 1 to match 2",marker,"Value mismatch: 1 vs 2";
        .resq.summaryOnly[message] musteq "Expected 1 to match 2";
        .resq.diffDetail[message] musteq "Value mismatch: 1 vs 2";
        .resq.firstDiffDetail[message;enlist message] musteq "Value mismatch: 1 vs 2";
        .resq.diffDetail["plain failure"] musteq "";
    };
 };

/ Nothing pinned the emitted XML, so a reporter could publish structurally
/ meaningless output and stay green. These build a mixed result set and assert
/ on the generated document directly.
.tst.desc["Reporter XML structure"]{
    should["omit empty and non-material quarantine property boilerplate"]{
        row:.tst.completeResultRow `suite`description`status`assertsRun!(
            `S;"plain";`pass;1i);
        .tst.loadOutputModule["json"];
        jsonRow:.tst.output.jsonRow row;
        row[`quarantine]:`state`active`nonBlocking`observations`passes`failures`flakes`owner`reason`issue`createdAt`expiresAt!(
            "healthy";0b;0b;8j;8j;0j;0j;"";"";"";"";"");
        prevTop:@[get;`.tst.output.top;{::}];
        prevReport:.resq.report;
        .tst.loadOutputModule["junit"];
        junitProps:.tst.output.junitPropertyNode row;
        .tst.loadOutputModule["xunit"];
        xunitProps:.tst.output.xunitPropertyNode row;
        .tst.output.top:prevTop;.resq.report:prevReport;
        junitProps musteq "";
        xunitProps musteq "";
        must[not `quarantine in key jsonRow;
             "an empty quarantine object must not be serialized"];
    };

    should["emit full property replay inputs in JUnit and xUnit"]{
        tail:(240#"p"),"PROPERTY_REPLAY_TAIL";
        row:.tst.completeResultRow `suite`description`status`assertsRun!(
            `S;"property";`fail;1i);
        row[`property]:`originalInput`minimalInput!(
            `nested`input!((enlist `payload)!enlist tail;til 120);
            `nested`input!((enlist `payload)!enlist tail;til 3));
        prevTop:@[get;`.tst.output.top;{::}];
        prevReport:.resq.report;
        .tst.loadOutputModule["junit"];
        junitProps:.tst.output.junitPropertyNode row;
        .tst.loadOutputModule["xunit"];
        xunitProps:.tst.output.xunitPropertyNode row;
        .tst.output.top:prevTop;.resq.report:prevReport;
        must[0<count ss[junitProps;"PROPERTY_REPLAY_TAIL"];
             "JUnit property evidence must retain the full original/minimal input"];
        must[0<count ss[xunitProps;"PROPERTY_REPLAY_TAIL"];
             "xUnit property evidence must retain the full original/minimal input"];
    };

    should["declare exact full results and telemetry profile projections"]{
        prevTop:@[get;`.tst.output.top;{::}];
        prevReport:.resq.report;
        .tst.loadOutputModule["json"];
        row:.tst.output.jsonRow .tst.completeResultRow
            `suite`description`status`assertsRun!("S";"plain";`pass;1i);
        model:`schemaVersion`framework`frameworkVersion`run`summary`tests`performance`coverage`diagnostics`flake`snapshotInventory`benchmarkAnalysis`manifest`events!(
            2;"resQ";"1.8.0";()!();()!();enlist row;();()!();();()!();()!();()!();()!();());
        full:.tst.output.profileRunModel[model;`full];
        results:.tst.output.profileRunModel[model;`results];
        telemetry:.tst.output.profileRunModel[model;`telemetry];
        .tst.output.top:prevTop;.resq.report:prevReport;
        full[`completeness;`evidenceComplete] musteq 1b;
        must[all `manifest`events`coverage in key full;
             "full must preserve release evidence"];
        must[not any `manifest`events`coverage in key results;
             "results must omit and declare non-result sections"];
        results[`completeness;`omittedSections] mustmatch
            ("performance";"coverage";"flake";"snapshotInventory";
             "benchmarkAnalysis";"manifest";"events");
        must[not `attemptHistory in key first telemetry`tests;
             "telemetry rows must omit detailed histories"];
        must[all `testId`status`message`durationSeconds in key first telemetry`tests;
             "telemetry must retain normalized ingestion identity and verdict"];
    };

    / A test's `namespace` is its generated SANDBOX name, which embeds the file's
    / absolute path. Using it as classname/type made CI grouping depend on the
    / checkout directory, so historical runs could never be matched. The SUITE
    / title leads instead; namespace remains a fallback for rows without one.
    should["group by stable suite title, not the path-derived sandbox namespace"]{
        sandboxNs: ".sandbox_S_home_someone_checkout_tests_test_s_q_a1b2c3";
        / `suite` is a SYMBOL, as real result rows carry: the reporter groups with
        / `(t`suite) = x`, which is elementwise on a multi-character string and
        / signals 'length. Build with flip + one-element columns.
        rows: flip `suite`description`status`message`time`failures`assertsRun`file`line`namespace`tags!(
            enlist `$"Order validation"; enlist "grouped"; enlist `fail; enlist "bad";
            enlist 0Nn; enlist enlist "bad"; enlist 1i;
            enlist "/project/tests/test_s.q"; enlist 7i; enlist sandboxNs; enlist ());
        prevTop: @[get; `.tst.output.top; {::}];
        prevReport: .resq.report;
        .tst.loadOutputModule["junit"]; junitXml: .tst.output.top rows;
        .tst.loadOutputModule["xunit"]; xunitXml: .tst.output.top rows;
        .tst.output.top: prevTop; .resq.report: prevReport;

        must[0 < count ss[junitXml;"classname=\"Order validation\""];
             "JUnit classname must be the suite title"];
        must[0 < count ss[xunitXml;"type=\"Order validation\""];
             "xUnit type must be the suite title"];
        must[0 = count ss[junitXml;sandboxNs];
             "the sandbox namespace must not reach the JUnit grouping key"];
        must[0 = count ss[xunitXml;sandboxNs];
             "the sandbox namespace must not reach the xUnit grouping key"];
    };

    should["XML groups string suites"]{
        raw:(
            `suite`description`status`assertsRun!("Order validation";"from string";`pass;1i);
            `suite`description`status`assertsRun!(`$"Order validation";"from symbol";`pass;1i);
            `suite`description`status`assertsRun!("Returns";"other suite";`pass;1i));
        completed:.tst.completeResultRow each raw;
        must[all -11h=type each {x`suite} each completed;
             "completeResultRow must normalize every suite to a symbol atom"];
        rows:flip flip completed;
        prevTop:@[get;`.tst.output.top;{::}];
        prevReport:.resq.report;
        .tst.loadOutputModule["junit"];junitXml:.tst.output.top rows;
        .tst.loadOutputModule["xunit"];xunitXml:.tst.output.top rows;
        .tst.output.top:prevTop;.resq.report:prevReport;
        must[0<count ss[junitXml;"<testsuite name=\"Order validation\" tests=\"2\""];
             "JUnit must group multi-character string and symbol suites"];
        must[0<count ss[xunitXml;"type=\"Order validation\""];
             "xUnit must accept the same normalized grouping key"];
    };

    / XML attribute-value normalization collapses a newline to a space, so a
    / multi-line message crammed into message="..." reaches the consumer as one
    / run-on line. Summary in the attribute, full detail in the element body.
    should["keep the XML message attribute single-line and the body complete"]{
        multi: "type\nFile: /project/tests/test_s.q\nSuite: S\nTest: boom";
        rows: flip `suite`description`status`message`time`failures`assertsRun`file`line`namespace`tags!(
            enlist `S; enlist "boom"; enlist `error; enlist multi;
            enlist 0Nn; enlist enlist multi; enlist 0i;
            enlist "/project/tests/test_s.q"; enlist 3i; enlist ""; enlist ());
        prevTop: @[get; `.tst.output.top; {::}];
        prevReport: .resq.report;
        .tst.loadOutputModule["junit"]; junitXml: .tst.output.top rows;
        .tst.output.top: prevTop; .resq.report: prevReport;

        must[0 < count ss[junitXml;"message=\"type ...\""];
             "the attribute must carry a single-line summary with a continuation marker"];
        must[0 < count ss[junitXml;"Suite: S"];
             "the element body must retain the full multi-line detail"];
        / Find the attribute itself and prove no raw newline survives inside it.
        attrStart: first ss[junitXml;"message=\""];
        attrTail: (attrStart + 9) _ junitXml;
        attrText: (first ss[attrTail;"\""]) # attrTail;
        must[not "\n" in attrText; "no raw newline may remain inside the attribute"];
    };

    should["publish source locations in both XML schemas"]{
        rows: enlist `suite`description`status`message`time`failures`assertsRun`file`line`namespace`tags!(
            "S";"located";`fail;"bad";0Nn;enlist "bad";1i;"/project/tests/test_s.q";42i;".spec";());
        prevTop: @[get; `.tst.output.top; {::}];
        prevReport: .resq.report;
        .tst.loadOutputModule["junit"]; junitXml: .tst.output.top rows;
        .tst.loadOutputModule["xunit"]; xunitXml: .tst.output.top rows;
        .tst.output.top: prevTop; .resq.report: prevReport;
        must[0 < count ss[junitXml;"file=\"/project/tests/test_s.q\" line=\"42\""];
             "JUnit must expose file and line attributes"];
        must[0 < count ss[xunitXml;"source-file=\"/project/tests/test_s.q\" source-line=\"42\""];
             "xUnit v2 must expose source-file and source-line attributes"];
    };

    should["publish captured subprocess output in JSON, JUnit and xUnit"]{
        captured: "child says <hello> & keeps going";
        row: `suite`description`status`message`time`failures`assertsRun`file`line`namespace`tags`output!(
            `S;"isolated";`fail;"bad";0Nn;enlist "bad";1i;
            "/project/tests/test_s.q";7i;"";();captured);
        rows: enlist row;
        prevTop: @[get; `.tst.output.top; {::}];
        prevReport: .resq.report;
        .tst.loadOutputModule["junit"]; junitXml: .tst.output.top rows;
        .tst.loadOutputModule["xunit"]; xunitXml: .tst.output.top rows;
        .tst.loadOutputModule["json"]; jsonRow: .tst.output.jsonRow row;
        .tst.output.top: prevTop; .resq.report: prevReport;

        (jsonRow`output) musteq captured;
        must[0 < count ss[junitXml;"<system-out>child says &lt;hello&gt; &amp; keeps going</system-out>"];
             "JUnit must expose escaped captured output in system-out"];
        must[0 < count ss[xunitXml;"<output>child says &lt;hello&gt; &amp; keeps going</output>"];
             "xUnit must expose escaped captured output"];
    };

    should["mark every xunit test with a result CI can read"]{
        rows: (
            `suite`description`status`message`time`failures`assertsRun!("S";"passes";  `pass;  ""; 0Nn; (); 1i);
            `suite`description`status`message`time`failures`assertsRun!("S";"fails";   `fail;  "bad"; 0Nn; enlist "bad"; 1i);
            `suite`description`status`message`time`failures`assertsRun!("S";"errors";  `error; "boom"; 0Nn; enlist "boom"; 0i);
            `suite`description`status`message`time`failures`assertsRun!("S";"skipped"; `skip;  ""; 0Nn; (); 0i));
        / Only one output module is resident at a time; load xunit, then put
        / the previous reporter back so later tests are unaffected.
        prevTop: @[get; `.tst.output.top; {::}];
        prevReport: .resq.report;
        .tst.loadOutputModule["xunit"];
        xml: .tst.output.top rows;
        .tst.output.top: prevTop; .resq.report: prevReport;

        / Without result= every test is indeterminate to an xUnit consumer.
        must[xml like "*result=\"Pass\"*";  "a passing test must be result=Pass"];
        must[xml like "*result=\"Skip\"*";  "a skipped test must be result=Skip"];
        must[xml like "*result=\"Fail\"*";  "a failing test must be result=Fail"];
        / 2 Fail: the assertion failure AND the errored test (xUnit has no third
        / per-test outcome). Both must be included in the failed aggregate.
        (count xml ss "result=\"Fail\"") musteq 2;
        must[xml like "*passed=\"1\"*"; "the assembly must report its passed count"];
        must[xml like "*failed=\"2\"*"; "the assembly must count both failed tests"];
        must[xml like "*schema-version=\"2\"*"; "the root must identify xUnit schema v2"];
        must[xml like "*<collection *"; "tests must be nested inside an xUnit collection"];
        must[xml like "*<failure exception-type=\"resQ.Error\"*";
             "an errored test must be represented as a failed xUnit test"];
        must[not xml like "*<error message=*";
             "per-test errors are not valid xUnit <error> elements"];
    };

    should["mark junit failures, errors and skips with distinct elements"]{
        rows: (
            `suite`description`status`message`time`failures`assertsRun!("S";"passes";  `pass;  ""; 0Nn; (); 1i);
            `suite`description`status`message`time`failures`assertsRun!("S";"fails";   `fail;  "bad"; 0Nn; enlist "bad"; 1i);
            `suite`description`status`message`time`failures`assertsRun!("S";"errors";  `error; "boom"; 0Nn; enlist "boom"; 0i);
            `suite`description`status`message`time`failures`assertsRun!("S";"skipped"; `skip;  ""; 0Nn; (); 0i));
        prevTop: @[get; `.tst.output.top; {::}];
        prevReport: .resq.report;
        .tst.loadOutputModule["junit"];
        xml: .tst.output.top rows;
        .tst.output.top: prevTop; .resq.report: prevReport;

        must[xml like "*<failure*";  "a failing test must emit <failure>"];
        must[xml like "*<error*";    "an errored test must emit <error>"];
        must[xml like "*<skipped*";  "a skipped test must emit <skipped>"];
        must[xml like "*failures=\"1\"*"; "the testsuite must report its failure count"];
        must[xml like "*errors=\"1\"*";   "the testsuite must report its error count"];
        must[xml like "*<testsuites tests=\"4\"*";
             "the root must carry aggregate counts"];
    };

    should["escape XML-hostile characters in both reporters"]{
        rows: enlist `suite`description`status`message`time`failures`assertsRun!(
            "S"; "name <tag> & \"q\""; `fail; "msg <b> & \"q\""; 0Nn; enlist "msg <b> & \"q\""; 1i);

        prevTop: @[get; `.tst.output.top; {::}];
        prevReport: .resq.report;
        .tst.loadOutputModule["xunit"];  xunitXml: .tst.output.top rows;
        .tst.loadOutputModule["junit"];  junitXml: .tst.output.top rows;
        .tst.output.top: prevTop; .resq.report: prevReport;

        {[xml; lbl]
            must[not xml like "*<tag>*";   lbl, ": a raw < > from a test name must be escaped"];
            must[xml like "*&lt;tag&gt;*"; lbl, ": the escaped form must be present"];
            / A bare & would make the document unparseable.
            must[not xml like "*\" & \"*"; lbl, ": a raw ampersand must be escaped"];
         }[xunitXml; "xunit"];
        {[xml; lbl]
            must[not xml like "*<tag>*";   lbl, ": a raw < > from a test name must be escaped"];
            must[xml like "*&lt;tag&gt;*"; lbl, ": the escaped form must be present"];
            must[not xml like "*\" & \"*"; lbl, ": a raw ampersand must be escaped"];
         }[junitXml; "junit"];
    };
 };
