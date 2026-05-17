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
        firstRow`status musteq `pass;
        firstRow`suite musteq "Suite A";
        firstRow`description musteq "Example";
    };

    should["unknown output module is warned and rejected safely"]{
        0b musteq .tst.loadOutputModule["missing-module"];
    };
 };
