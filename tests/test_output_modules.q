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
 };

/ Nothing pinned the emitted XML, so a reporter could publish structurally
/ meaningless output and stay green. These build a mixed result set and assert
/ on the generated document directly.
.tst.desc["Reporter XML structure"]{
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
        / 2 Fail: the failure AND the error (xUnit v2 has no third outcome).
        (count xml ss "result=\"Fail\"") musteq 2;
        must[xml like "*passed=\"1\"*"; "the assembly must report its passed count"];
        must[xml like "*failed=\"1\"*"; "the assembly must report its failed count"];
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
