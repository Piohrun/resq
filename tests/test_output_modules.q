.tst.desc["Output Module Support"]{
    should["load text output module"]{
        .tst.loadOutputModule["text"];
        `reportText in key `.resq;
    };

    should["load console alias as text module"]{
        .tst.app.xmlOutput: 0b;
        .tst.loadOutputModule["console"];
        `reportText in key `.resq;
    };

    should["load uppercase aliases safely"]{
        .tst.app.xmlOutput: 0b;
        .tst.loadOutputModule["XML"];
        `top in key `.tst.output;
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
        result
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
