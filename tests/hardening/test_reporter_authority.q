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
    (`.tst.output.junitTop`.tst.output.xunitTop`.tst.MAX_REPORT_BYTES)
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
