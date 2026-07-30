/ Reporter selection and publication authority regressions.

/ Seed named exports before per-expectation lifecycle snapshots. Subsequent
/ loads may be registry hits, so deleting a named export would correctly make
/ the cached module fail closed rather than silently re-execute it.
.tst.loadOutputModule "junit";
.tst.loadOutputModule "xunit";
.tst.loadOutputModule "text";

.tst.reporterHardening.capture:{[]
  .tst.captureNamedLifecycle
    (`.resq.report`.resq.config.fmt`.resq.config.outDir),
    (`.tst.app.xmlOutput`.tst.app.baseDir`.tst.output.top),
    (`.tst.output.junitTop`.tst.output.xunitTop`.tst.MAX_REPORT_BYTES),
    (`.tst.MAX_REPORT_ROWS`.tst.output.reportLimit),
    (`.tst.output.reportListLimit`.tst.sanitizeExpectation),
    enlist `.tst.sanitizeExpectationFromFields
 };

.tst.desc["reporter hardening: selection authority"]{
  before{
    .tst.testState.reporterHardeningState:
      .tst.reporterHardening.capture[];
  };
  after{
    .tst.restoreNamedLifecycle
      .tst.testState.reporterHardeningState;
    ![`.tst.testState;();0b;enlist `reporterHardeningState];
  };

  should["select the requested XML builder after repeated format switches"]{
    .tst.loadOutputModule "junit";
    (.tst.output.top[]) mustmatch
      "<testsuites></testsuites>";

    .tst.loadOutputModule "xunit";
    (.tst.output.top[]) mustmatch
      "<assemblies></assemblies>";

    .tst.loadOutputModule "junit";
    (.tst.output.top[]) mustmatch
      "<testsuites></testsuites>";
  };

  should["reset the active reporter when returning from JSON to text"]{
    .tst.app.xmlOutput:0b;
    .resq.config.fmt:`json;
    .tst.initReporting[];
    must[
      .resq.report~.resq.reportJson;
      "JSON format did not select the JSON reporter"];

    .tst.app.xmlOutput:0b;
    .resq.config.fmt:`text;
    .tst.initReporting[];
    must[
      .resq.report~.resq.reportText;
      "text format retained a stale file reporter"];
  };

  should["reset the active reporter when returning from JUnit to text"]{
    .tst.app.xmlOutput:0b;
    .resq.config.fmt:`junit;
    .tst.initReporting[];
    must[
      .resq.report~.resq.reportXml;
      "JUnit format did not select the XML reporter"];

    / No manual xmlOutput reset: initReporting must not persist its derived
    / format choice into the next initialization.
    .resq.config.fmt:`text;
    .tst.initReporting[];
    must[
      .resq.report~.resq.reportText;
      "text format retained a stale XML reporter"];
  };

  should["signal XML serialization failures without replacing a valid report"]{
    item:.tst.tempFile ".reporter";
    outDir:.tst.static.getDir item;
    output:outDir,"/test-results.xml";
    (.utl.pathToHsym output)0:enlist "sentinel";

    .tst.app.baseDir:system "cd";
    .tst.app.xmlOutput:1b;
    .resq.config.fmt:`junit;
    .resq.config.outDir:outDir;
    .tst.output.junitTop:{[rows]'"forced XML serialization failure"};
    .tst.initReporting[];

    outcome:.utl.attempt[
      .resq.reportXml;
      enlist ()];

    (first outcome) musteq 0b;
    (raze read0 .utl.pathToHsym output) mustmatch "sentinel";
  };

  should["capture the XML builder selected for the current run"]{
    item:.tst.tempFile ".reporter";
    outDir:.tst.static.getDir item;
    output:outDir,"/test-results.xml";

    .tst.app.baseDir:system "cd";
    .tst.app.xmlOutput:1b;
    .resq.config.fmt:`junit;
    .resq.config.outDir:outDir;
    .tst.initReporting[];
    .tst.loadOutputModule "xunit";
    .resq.reportXml[];

    xml:raze read0 .utl.pathToHsym output;
    must[xml like "<testsuites>*";
      "a later module load changed the active run's XML format"];
  };

  should["fail closed when a cached output module lost its named export"]{
    .tst.deleteVar `.tst.output.junitTop;
    (0b) musteq .tst.loadOutputModule "junit";

    .tst.app.xmlOutput:1b;
    .resq.config.fmt:`junit;
    outcome:.utl.attempt[
      .tst.initReporting;
      ()];
    (first outcome) musteq 0b;
  };

  should["reject a non-callable cached output-module export"]{
    .tst.output.junitTop:42;
    (0b) musteq .tst.loadOutputModule "junit";
  };
};

.tst.desc["reporter hardening: atomic publication"]{
  before{
    .tst.testState.reporterHardeningState:
      .tst.reporterHardening.capture[];
  };
  after{
    .tst.restoreNamedLifecycle
      .tst.testState.reporterHardeningState;
    ![`.tst.testState;();0b;enlist `reporterHardeningState];
  };

  should["enforce the report byte budget before replacing an artifact"]{
    output:.tst.tempFile ".json";
    (.utl.pathToHsym output)0:enlist "sentinel";
    .tst.MAX_REPORT_BYTES:8;

    outcome:.utl.attempt[
      .tst.publishReportText;
      (output;"replacement")];

    (first outcome) musteq 0b;
    (raze read0 .utl.pathToHsym output) mustmatch "sentinel";
  };

  should["admit the complete JSON body before replacing an artifact"]{
    item:.tst.tempFile ".reporter";
    outDir:.tst.static.getDir item;
    output:outDir,"/test-results.json";
    (.utl.pathToHsym output)0:enlist "sentinel";
    .tst.app.baseDir:system "cd";
    .resq.config.outDir:outDir;
    .tst.MAX_REPORT_BYTES:256;
    loaded:.tst.loadOutputModule "json";
    loaded musteq 1b;
    raw:
      `suite`description`status!(
        "suite";
        1000#"d";
        `pass);

    outcome:.utl.attempt[
      .resq.reportJson;
      enlist enlist raw];

    (first outcome) musteq 0b;
    (raze read0 .utl.pathToHsym output) mustmatch "sentinel";
  };

  should["preserve an artifact and remove the temporary file when rename fails"]{
    output:.tst.tempFile ".xml";
    (.utl.pathToHsym output)0:enlist "sentinel";
    capabilities:.utl.atomicTextCapabilities[];
    capabilities[`command]:
      {[commandText]'"forced text publication failure"};

    outcome:.utl.attempt[
      .utl.atomicTextWriteWith;
      (capabilities;output;"replacement";1024;"Test report")];

    (first outcome) musteq 0b;
    (raze read0 .utl.pathToHsym output) mustmatch "sentinel";
    parent:.tst.static.getDir output;
    base:.tst.static.getBase output;
    entries:string key .utl.pathToHsym parent;
    must[
      not any entries like base,".resq-publish-*";
      "failed report publication leaked a temporary file"];
  };

  should["reject a symlink report target without touching its referent"]{
    if[.utl.isWindows;
      must[1b;"POSIX symlink regression"];
      :()];
    target:.tst.tempFile ".target";
    link:.tst.tempFile ".link";
    (.utl.pathToHsym target)0:enlist "sentinel";
    system "ln -s ",.utl.shellQuote[target]," ",.utl.shellQuote[link];

    outcome:.utl.attempt[
      .tst.publishReportText;
      (link;"replacement")];
    unlinked:.utl.attempt[
      system;
      enlist "unlink ",.utl.shellQuote link];

    (first unlinked) musteq 1b;
    (first outcome) musteq 0b;
    (raze read0 .utl.pathToHsym target) mustmatch "sentinel";
  };

  should["reject malformed output-directory state at the path boundary"]{
    .resq.config.outDir:42;
    outcome:.utl.attempt[
      .tst.reportOutputPath;
      enlist "test-results.json"];
    (first outcome) musteq 0b;
  };

  should["reject a report filename that can escape its output directory"]{
    outcome:.utl.attempt[
      .tst.reportOutputPath;
      enlist "../outside.json"];
    (first outcome) musteq 0b;
  };
};

.tst.desc["reporter hardening: serialization admission"]{
  before{
    .tst.testState.reporterHardeningState:
      .tst.reporterHardening.capture[];
  };
  after{
    .tst.restoreNamedLifecycle
      .tst.testState.reporterHardeningState;
    ![`.tst.testState;();0b;enlist `reporterHardeningState];
  };

  should["normalize direct result rows to the complete reporter schema"]{
    raw:
      `suite`description`status!(
        "direct suite";
        "direct result";
        `pass);
    normalized:first .tst.resultRows enlist raw;

    key[normalized] mustmatch
      `suite`description`status`message`time`failures,
      `assertsRun`file`namespace`tags;
    normalized[`message] mustmatch "";
    normalized[`failures] mustmatch ();
  };

  should["classify malformed expectation data as an error"]{
    spec:
      `title`expectations!(
        "suite";
        enlist 42);
    normalized:first .tst.resultRows enlist spec;

    normalized[`description] mustmatch
      "Unavailable expectation";
    normalized[`status] musteq `error;
  };

  should["normalize malformed timing and non-finite counters"]{
    timeTable:([] elapsed:enlist 0D00:00:01);
    raw:
      `suite`description`status`time`assertsRun!(
        "suite";
        "result";
        `pass;
        timeTable;
        0W);
    malformed:first .tst.resultRows enlist raw;
    infiniteRaw:
      `suite`description`status`time!(
        "suite";
        "result";
        `pass;
        0Wn);
    infinite:first .tst.resultRows enlist infiniteRaw;

    (type malformed`time) musteq -16h;
    must[null malformed`time;
      "malformed time was retained"];
    malformed[`assertsRun] musteq 0j;
    must[null infinite`time;
      "non-finite time was retained"];
  };

  should["bound direct row text fields before serialization"]{
    .tst.output.reportLimit:32;
    .tst.output.reportListLimit:2;
    raw:
      ((`suite`description`status`message`time`failures),
       (`assertsRun`file`namespace`tags))!(
        1000#"s";
        1000#"d";
        `fail;
        1000#"m";
        0Nn;
        ("first";"second";"third");
        1i;
        1000#"f";
        1000#"n";
        `one`two`three);
    normalized:first .tst.resultRows enlist raw;

    must[count[normalized`suite]<=32;
      "suite exceeded reportLimit"];
    must[count[normalized`description]<=32;
      "description exceeded reportLimit"];
    must[count[normalized`message]<=32;
      "message exceeded reportLimit"];
    must[count[normalized`file]<=32;
      "file exceeded reportLimit"];
    must[count[normalized`namespace]<=32;
      "namespace exceeded reportLimit"];
  };

  should["bound direct row list fields before serialization"]{
    .tst.output.reportLimit:32;
    .tst.output.reportListLimit:2;
    raw:
      ((`suite`description`status`message`time`failures),
       (`assertsRun`file`namespace`tags))!(
        "suite";
        "result";
        `fail;
        "message";
        0Nn;
        ("first";"second";"third");
        1i;
        "";
        "";
        `one`two`three);
    normalized:first .tst.resultRows enlist raw;
    failureCount:count normalized`failures;
    tagCount:count normalized`tags;
    must[2=failureCount;
      "failure list did not honor reportListLimit"];
    must[2=tagCount;
      "tag list did not honor reportListLimit"];
    must[
      (sum count each normalized`failures)<=32;
      "failure list exceeded the aggregate reportLimit"];
    must[
      (sum count each normalized`tags)<=32;
      "tag list exceeded the aggregate reportLimit"];
    failureMarker:(last normalized`failures) ss "truncated";
    tagMarker:(last normalized`tags) ss "truncated";
    must[0<count failureMarker;
      "failure-list truncation was not visible"];
    must[0<count tagMarker;
      "tag-list truncation was not visible"];
  };

  should["apply reportListLimit while rendering failure messages"]{
    .tst.output.reportLimit:128;
    .tst.output.reportListLimit:2;
    message:.tst.renderReportMessage
      ("first";"second";"third");
    marker:message ss "truncated";

    must[not message~"first\nsecond\nthird";
      "renderReportMessage traversed beyond reportListLimit"];
    must[0<count marker;
      "bounded failure message omitted its truncation marker"];
  };

  should["preserve list shape at a one-character item ceiling"]{
    .tst.output.reportLimit:2;
    .tst.output.reportListLimit:2;
    items:1 _ ((::);enlist "a";enlist "b");
    rendered:.tst.sanitizeReportList items;
    message:.tst.renderReportMessage items;

    (type rendered) musteq 0h;
    (count rendered) musteq 2;
    must[all 10h=type each rendered;
      "bounded report items collapsed into character atoms"];
    (type message) musteq 10h;
    must[count[message]<=2;
      "two-character report ceiling was exceeded"];

    .tst.output.reportLimit:1;
    (count .tst.sanitizeReportList items) musteq 1;
    .tst.output.reportLimit:0;
    (.tst.sanitizeReportList items) mustmatch ();
    (.tst.renderReportMessage items) mustmatch "";
  };

  should["reject an assembly line before it exceeds the byte budget"]{
    .tst.MAX_REPORT_BYTES:12;
    state:.tst.reportLineState[];
    state:.tst.appendReportLine[state;"abc"];
    state:.tst.appendReportLine[state;"def"];
    outcome:.utl.attempt[
      .tst.appendReportLine;
      (state;"1234")];
    malformed:(state 0;0j;state 2;state 3);
    malformedOutcome:.utl.attempt[
      .tst.reportLines;
      enlist malformed];

    (first outcome) musteq 0b;
    (first malformedOutcome) musteq 0b;
    (state 1) musteq 8j;
    (.tst.finalizeReportLines state) mustmatch "abc\ndef";
  };

  should["preserve every line across bounded assembly chunks"]{
    .tst.MAX_REPORT_BYTES:1024;
    state:.tst.reportLineState[];
    index:0;
    while[index<257;
      state:.tst.appendReportLine[state;"x"];
      index+:1];
    lines:.tst.reportLines state;

    (count lines) musteq 257;
    must[all (enlist "x")~/:lines;
      "chunked report assembly changed a line"];
    (state 1) musteq 514j;
  };

  should["emit exactly one XML block per suite and case"]{
    rows:(
      `suite`description`status!("alpha";"one";`pass);
      `suite`description`status!("beta";"two";`fail);
      `suite`description`status!("alpha";"three";`skip));
    junit:.tst.output.junitTop rows;
    xunit:.tst.output.xunitTop rows;
    junitSuites:junit ss "<testsuite name=";
    junitCases:junit ss "<testcase";
    xunitSuites:xunit ss "<assembly name=";
    xunitCases:xunit ss "<test ";

    must[2=count junitSuites;
      "JUnit did not emit exactly one block per suite"];
    must[3=count junitCases;
      "JUnit did not emit exactly one case per row"];
    must[2=count xunitSuites;
      "xUnit did not emit exactly one block per suite"];
    must[3=count xunitCases;
      "xUnit did not emit exactly one case per row"];
  };

  should["reject excess result rows at the reporter boundary"]{
    .tst.MAX_REPORT_ROWS:2;
    row:
      `suite`description`status!(
        "suite";
        "result";
        `pass);
    outcome:.utl.attempt[
      .tst.resultRows;
      enlist 3#enlist row];

    (first outcome) musteq 0b;
  };

  should["admit aggregate row expansion before rendering values"]{
    .tst.MAX_REPORT_ROWS:2;
    expectations:
      flip `desc`result!(
        ("one";"two");
        `pass`pass);
    spec:`title`expectations!(
      "suite";
      expectations);
    .tst.sanitizeExpectationFromFields:
      {[suite;file;namespace;tags;expectation]
        '"rendered before aggregate admission"};
    outcome:.utl.attempt[
      .tst.resultRows;
      enlist (spec;42)];

    (first outcome) musteq 0b;
    (last outcome) mustmatch "Test report row limit exceeded";
  };

  should["fail closed for a malformed report row ceiling"]{
    .tst.MAX_REPORT_ROWS:"invalid";
    row:
      `suite`description`status!(
        "suite";
        "result";
        `pass);
    outcome:.utl.attempt[
      .tst.resultRows;
      enlist enlist row];

    (first outcome) musteq 0b;
  };
};
