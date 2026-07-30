/ Coverage lifecycle, authority, and report-publication regressions.
.utl.require .utl.PKGLOADING,"/coverage.q";

.tst.coverageHardening.captureState:{[]
  `coverageData`coverageEnabled`trackedFiles`origFuncs`covWrappers`loadingStack!(
    .tst.coverageData;
    .tst.coverageEnabled;
    .tst.trackedFiles;
    .tst.origFuncs;
    .tst.covWrappers;
    .tst.loadingStack)
 };

.tst.coverageHardening.restoreState:{[state]
  @[.tst.restoreCoverageInstrumentation;();{}];
  .tst.coverageData:state`coverageData;
  .tst.coverageEnabled:state`coverageEnabled;
  .tst.trackedFiles:state`trackedFiles;
  .tst.origFuncs:state`origFuncs;
  .tst.covWrappers:state`covWrappers;
  .tst.loadingStack:state`loadingStack;
  ::
 };

.tst.desc["coverage hardening: lifecycle authority"]{
  before{
    .tst.testState.coverageHardeningState:
      .tst.coverageHardening.captureState[];
    .tst.testState.coverageHardeningFunctions:
      .tst.captureNamedLifecycle
        `.tst.coverageLoadFile`.tst.instrumentFile;
    .tst.coverageData:()!();
    .tst.coverageEnabled:0b;
    .tst.trackedFiles:`symbol$();
    .tst.origFuncs:()!();
    .tst.covWrappers:()!();
    .tst.loadingStack:();
  };
  after{
    .tst.restoreNamedLifecycle
      .tst.testState.coverageHardeningFunctions;
    .tst.coverageHardening.restoreState
      .tst.testState.coverageHardeningState;
    @[{delete covhard from `.};::;{}];
    ![`.tst.testState;();0b;
      `coverageHardeningState`coverageHardeningFunctions];
  };

  should["preserve active wrapper ownership across module reload"]{
    name:`.covhard.reloadTarget;
    original:{[x]x+1};
    wrapper:{[x]x+10};
    name set wrapper;
    .tst.origFuncs[name]:original;
    .tst.covWrappers[name]:wrapper;
    .tst.coverageEnabled:1b;

    .Q.trp[
      {[path]system ("l ",path)};
      .resq.HOME,"/lib/coverage.q";
      {[err;backtrace]
        '"Coverage reload regression failed: ",err,
          "\n",.Q.sbt backtrace}];

    name mustin key .tst.origFuncs;
    name mustin key .tst.covWrappers;
    ((get name)5) musteq 15;
    .tst.restoreCoverageInstrumentation[];
    ((get name)5) musteq 6;
  };

  should["reject malformed reload state without publishing helpers"]{
    .tst.origFuncs:
      (enlist `.covhard.invalidReload)!enlist {[x]x};
    .tst.covWrappers:()!();
    beforeOriginals:.tst.origFuncs;
    beforeWrappers:.tst.covWrappers;

    outcome:.utl.attempt[
      system;
      enlist "l ",.resq.HOME,"/lib/coverage.q"];

    (first outcome) musteq 0b;
    .tst.origFuncs mustmatch beforeOriginals;
    .tst.covWrappers mustmatch beforeWrappers;
    must[
      not `coverageReloadBootstrap in key `.tst;
      "failed reload leaked its bootstrap helper"];
    must[
      not `coverageReloadState in key `.tst;
      "failed reload published transient state"];
  };

  should["normalize a legacy per-file registry during reload"]{
    file:`legacy_coverage.q;
    .tst.coverageData:
      (enlist file)!enlist (()!());
    .tst.trackedFiles:enlist file;

    .Q.trp[
      {[path]system ("l ",path)};
      .resq.HOME,"/lib/coverage.q";
      {[err;backtrace]
        '"Coverage legacy reload failed: ",err,
          "\n",.Q.sbt backtrace}];

    raw:.tst.coverageData file;
    (count raw) musteq 1;
    (type first raw) musteq 99h;
    (count .tst.coverageFunctionData file) musteq 0;
  };

  should["leave legacy state untouched when late reload validation fails"]{
    file:`legacy_failed_reload.q;
    .tst.coverageData:
      (enlist file)!enlist (()!());
    .tst.trackedFiles:enlist file;
    .tst.loadingStack:enlist 1;
    beforeData:.tst.coverageData;
    beforeTracked:.tst.trackedFiles;

    outcome:.utl.attempt[
      system;
      enlist "l ",.resq.HOME,"/lib/coverage.q"];

    (first outcome) musteq 0b;
    .tst.coverageData mustmatch beforeData;
    .tst.trackedFiles mustmatch beforeTracked;
    .tst.loadingStack mustmatch enlist 1;
  };

  should["restore loadingStack when instrumentation throws"]{
    stackBefore:enlist "/prior/source.q";
    .tst.loadingStack:stackBefore;
    .tst.coverageLoadFile:{[path]::};
    .tst.instrumentFile:{[path]'"instrument boom"};

    outcome:.utl.attempt[
      .tst.loadSource;
      enlist "/tmp/resq-coverage-stack.q"];

    (first outcome) musteq 0b;
    .tst.loadingStack mustmatch stackBefore;
  };

  should["load a regular source while restoring process context"]{
    path:.tst.tempFile ".q";
    .tst.registerCleanup[
      {[target]@[hdel;hsym `$target;{}]};
      enlist path];
    (hsym `$path)0:(
      "system \"d .covhard\";";
      "loadedByCoverage:42;";
      "system \"cd /\";");
    cwdBefore:system "cd";
    namespaceBefore:system "d";

    .tst.coverageLoadFile path;

    (system "cd") mustmatch cwdBefore;
    (system "d") mustmatch namespaceBefore;
    .covhard.loadedByCoverage musteq 42;
  };

  should["reject whitespace load paths before execution"]{
    seed:.tst.tempFile ".coverage-load";
    path:seed," space.q";
    .tst.registerCleanup[
      {[target]@[hdel;hsym `$target;{}]};
      enlist path];
    (hsym `$path)0:enlist
      ".covhard.whitespaceLoadExecuted:1;";
    cwdBefore:system "cd";
    namespaceBefore:system "d";

    outcome:.utl.attempt[
      .tst.coverageLoadFile;
      enlist path];

    (first outcome) musteq 0b;
    (system "cd") mustmatch cwdBefore;
    (system "d") mustmatch namespaceBefore;
    must[
      (.tst.safeValue `.covhard.whitespaceLoadExecuted)~
        .tst._covMissing;
      "rejected coverage source executed"];
  };

  should["retire an earlier coverage session before reinitializing"]{
    name:`.covhard.reinitTarget;
    original:{[x]x+1};
    wrapper:{[x]x+10};
    name set wrapper;
    .tst.origFuncs[name]:original;
    .tst.covWrappers[name]:wrapper;
    .tst.coverageEnabled:1b;

    .tst.initCoverageWith[
      .tst.restoreCoverageInstrumentation;
      {[]::};
      ()];

    ((get name)5) musteq 6;
    (count key .tst.origFuncs) musteq 0;
    (count key .tst.covWrappers) musteq 0;
    .tst.coverageEnabled musteq 1b;
  };

  should["unwind wrappers when coverage initialization fails"]{
    name:`.covhard.initFailureTarget;
    name set {[x]x+1};
    initialized:{[]
      .tst.wrapFunc[
        `.covhard.initFailureTarget;
        `:/tmp/coverage-init-failure.q];
      '"instrument initialization boom"};

    outcome:.utl.attempt[
      .tst.initCoverageWith;
      (.tst.restoreCoverageInstrumentation;initialized;())];

    (first outcome) musteq 0b;
    ((get name)5) musteq 6;
    (count key .tst.origFuncs) musteq 0;
    (count key .tst.covWrappers) musteq 0;
    (count key .tst.coverageData) musteq 0;
    (count .tst.trackedFiles) musteq 0;
    .tst.coverageEnabled musteq 0b;
  };
};

.tst.desc["coverage hardening: report encoding"]{
  before{
    .tst.testState.coverageHardeningState:
      .tst.coverageHardening.captureState[];
    .tst.testState.coverageHardeningReportLimit:
      .tst.MAX_COVERAGE_REPORT_BYTES;
    .tst.coverageData:()!();
    .tst.coverageEnabled:1b;
    .tst.trackedFiles:`symbol$();
    .tst.origFuncs:()!();
    .tst.covWrappers:()!();
    .tst.loadingStack:();
  };
  after{
    .tst.coverageHardening.restoreState
      .tst.testState.coverageHardeningState;
    .tst.MAX_COVERAGE_REPORT_BYTES:
      .tst.testState.coverageHardeningReportLimit;
    ![`.tst.testState;();0b;
      `coverageHardeningState`coverageHardeningReportLimit];
  };

  should["escape source paths before embedding them in HTML"]{
    seed:.tst.tempFile ".coverage-path";
    path:seed,"-<script>&\"coverage.q";
    output:.tst.tempFile ".html";
    .tst.registerCleanup[
      {[targets]{[target]@[hdel;hsym `$target;{}]} each targets};
      enlist (path;output)];
    (hsym `$path)0:enlist "/ coverage path escaping";
    file:`$path;
    .tst.coverageData[file]:enlist (()!());
    .tst.trackedFiles:enlist file;

    .tst.generateHTML output;
    html:raze read0 hsym `$output;

    must[not html like "*<script>*";
      "coverage HTML embedded an executable path"];
    must[html like "*&lt;script&gt;&amp;&quot;coverage.q*";
      "coverage HTML did not encode the source path"];
  };

  should["reject corrupt counters before overwriting a report"]{
    source:.tst.tempFile ".q";
    output:.tst.tempFile ".html";
    .tst.registerCleanup[
      {[targets]{[target]@[hdel;hsym `$target;{}]} each targets};
      enlist (source;output)];
    (hsym `$source)0:enlist "covered:{[]1};";
    (hsym `$output)0:enlist "sentinel";
    file:`$source;
    .tst.coverageData[file]:
      enlist ((enlist `covered)!enlist -1j);
    .tst.trackedFiles:enlist file;

    outcome:.utl.attempt[
      .tst.generateHTML;
      enlist output];

    (first outcome) musteq 0b;
    (raze read0 hsym `$output) mustmatch "sentinel";
  };

  should["preserve an existing report when atomic publication fails"]{
    output:.tst.tempFile ".html";
    .tst.registerCleanup[
      {[target]@[hdel;hsym `$target;{}]};
      enlist output];
    (hsym `$output)0:enlist "sentinel";

    outcome:.utl.attempt[
      {[target]
        .tst.coveragePublishTextWith[
          .utl.attempt;
          {[commandText]'"forced publication failure"};
          .utl.shellQuoteForHost;
          .utl.isWindows;
          .utl.fsSnapshot;
          .utl.pathToHsym;
          target;
          enlist "replacement"]};
      enlist output];

    (first outcome) musteq 0b;
    (raze read0 hsym `$output) mustmatch "sentinel";
    parent:.tst.static.getDir output;
    base:.tst.static.getBase output;
    entries:string key hsym `$parent;
    must[
      not any entries like base,".resq-publish-*";
      "failed coverage publication leaked a temporary file"];
  };

  should["enforce the report byte budget before publication"]{
    source:.tst.tempFile ".q";
    output:.tst.tempFile ".html";
    .tst.registerCleanup[
      {[targets]{[target]@[hdel;hsym `$target;{}]} each targets};
      enlist (source;output)];
    (hsym `$source)0:enlist "covered:{[]1};";
    (hsym `$output)0:enlist "sentinel";
    file:`$source;
    .tst.coverageData[file]:enlist (()!());
    .tst.trackedFiles:enlist file;
    .tst.MAX_COVERAGE_REPORT_BYTES:32;

    outcome:.utl.attempt[
      .tst.generateHTML;
      enlist output];

    (first outcome) musteq 0b;
    (raze read0 hsym `$output) mustmatch "sentinel";
  };

  should["publish an empty coverage-state artifact safely"]{
    output:.tst.tempFile ".coverage-state";
    .tst.registerCleanup[
      {[target]@[hdel;hsym `$target;{}]};
      enlist output];

    .tst.publishCoverageText[output;()];

    snapshot:
      ((.utl.fsSnapshot[])`readRegular)[output;1024];
    (count snapshot`bytes) musteq 0;
  };
};

.tst.desc["coverage hardening: bounded accounting"]{
  before{
    .tst.testState.coverageHardeningState:
      .tst.coverageHardening.captureState[];
    .tst.testState.coverageHardeningLimits:
      .tst.MAX_COVERAGE_FILES,.tst.MAX_COVERAGE_FUNCTIONS;
    .tst.coverageData:()!();
    .tst.coverageEnabled:1b;
    .tst.trackedFiles:`symbol$();
    .tst.origFuncs:()!();
    .tst.covWrappers:()!();
    .tst.loadingStack:();
  };
  after{
    .tst.MAX_COVERAGE_FILES:
      first .tst.testState.coverageHardeningLimits;
    .tst.MAX_COVERAGE_FUNCTIONS:
      last .tst.testState.coverageHardeningLimits;
    .tst.coverageHardening.restoreState
      .tst.testState.coverageHardeningState;
    ![`.tst.testState;();0b;
      `coverageHardeningState`coverageHardeningLimits];
  };

  should["reject incoherent file state without mutation"]{
    .tst.coverageData:
      (enlist `orphan.q)!enlist (()!());
    beforeData:.tst.coverageData;
    beforeTracked:.tst.trackedFiles;

    outcome:.utl.attempt[
      .tst.ensureCoverageEntry;
      enlist `new.q];

    (first outcome) musteq 0b;
    .tst.coverageData mustmatch beforeData;
    .tst.trackedFiles mustmatch beforeTracked;
  };

  should["enforce the file budget transactionally"]{
    .tst.MAX_COVERAGE_FILES:1;
    .tst.ensureCoverageEntry `first.q;
    beforeData:.tst.coverageData;
    beforeTracked:.tst.trackedFiles;

    outcome:.utl.attempt[
      .tst.ensureCoverageEntry;
      enlist `second.q];

    (first outcome) musteq 0b;
    .tst.coverageData mustmatch beforeData;
    .tst.trackedFiles mustmatch beforeTracked;
  };

  should["enforce the function budget transactionally"]{
    .tst.MAX_COVERAGE_FUNCTIONS:1;
    .tst.recordExecution[`sample.q;`first];
    beforeData:.tst.coverageData;

    outcome:.utl.attempt[
      .tst.recordExecution;
      (`sample.q;`second)];

    (first outcome) musteq 0b;
    .tst.coverageData mustmatch beforeData;
  };

  should["use long counters and reject corrupt counts"]{
    .tst.recordExecution[`sample.q;`add];
    functionData:.tst.coverageFunctionData `sample.q;
    (-7h) musteq type functionData`add;
    1j musteq functionData`add;
    functionData[`add]:-1j;
    .tst.coverageData[`sample.q]:enlist functionData;
    beforeData:.tst.coverageData;

    outcome:.utl.attempt[
      .tst.recordExecution;
      (`sample.q;`add)];

    (first outcome) musteq 0b;
    .tst.coverageData mustmatch beforeData;
  };

  should["reject malformed enabled state before accounting"]{
    .tst.coverageEnabled:1;
    beforeData:.tst.coverageData;

    outcome:.utl.attempt[
      .tst.recordExecution;
      (`sample.q;`add)];

    (first outcome) musteq 0b;
    .tst.coverageData mustmatch beforeData;
  };
};
