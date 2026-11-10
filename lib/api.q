/ Embedded execution: one invocation owns its options, registries and history.
.resq.require .resq.HOME,"/lib/config.q";
.resq.require .resq.HOME,"/lib/parametrize.q";
.resq.require .resq.HOME,"/lib/async.q";
.resq.require .resq.HOME,"/lib/bench.q";
.resq.require .resq.HOME,"/lib/cli.q";
.resq.require .resq.HOME,"/lib/runner.q";
.resq.api.active:0b;
.resq.api.appDefaults:get `.tst.app;
.resq.api.allowed:`strict`qspecCompat`failFast`runPerformance`runSpecs`excludeSpecs`testFilePatterns`maxTestTime`fuzzLimit`randomOrder`seed`runCoverage`coverageSources`covStatements`covBranches`outDir;
.resq.api.callbackNames:`.z.ts`.z.pg`.z.ps`.z.pc`.z.po`.z.ph`.z.pp`.z.ws`.z.exit;

.resq.api.options:{[options]
    if[not 99h=type options;'"resQ run: options must be a symbol-keyed dictionary"];
    if[(count options) and not 11h=type key options;'"resQ run: option keys must be symbols"];
    if[count[key options]<>count distinct key options;'"resQ run: duplicate options"];
    unknown:(key options) except .resq.api.allowed;
    if[count unknown;'"resQ run: unsupported options: ",", " sv string unknown];
    if[`runCoverage in key options;
        if[not -1h=type options`runCoverage;'"resQ run: runCoverage must be boolean"]];
    if[`outDir in key options;
        if[not (type options`outDir) in 10 -11h;'"resQ run: outDir must be a path"];
        options[`outDir]:.utl.pathToString options`outDir;
        if[0=count options`outDir;'"resQ run: outDir must not be empty"]];
    normalized:.tst.normalizeConfigDocument options;
    invalid:.tst.invalidConfigKeys `runCoverage _ normalized;
    if[count invalid;'"resQ run: invalid options: ",", " sv string invalid];
    coverage:1b~options`runCoverage;
    if[(not coverage) and any (key options) in `coverageSources`covStatements`covBranches;
        '"resQ run: coverage options require runCoverage:1b"];
    if[coverage and not `outDir in key options;
        '"resQ run: coverage requires an explicit outDir"];
    normalized
 };

.resq.api.prepare:{[paths;options;temp]
    system "t 0";
    `.tst.app set .resq.api.appDefaults;
    .resq.state.results:.resq.state.emptyResults[];
    .tst.app.diagnostics:();
    .tst.app.cleanupErrors:();
    .tst.app.loadErrors:flip `file`error`type!(`symbol$();();`symbol$());
    .tst.fixtures:(enlist `)!enlist (::);
    .tst.cleanupTasks:();.tst.specCleanupTasks:();
    .tst.mockState.store:(enlist `)!enlist (::);
    .tst.mockState.removeList:();
    .tst.deferredStates:()!();
    .tst.app.sandboxNamespaces:`symbol$();
    .tst.configTestFilePatternsExplicit:`testFilePatterns in key options;
    cfg:.tst.defaultConfig,`runCoverage _ options;
    cfg:cfg,`exit`passOnly`vcsProbe!(0b;1b;0b);
    cfg:cfg,`stateFile`flakeHistoryFile`quarantineFile`flakeProposalFile!
        temp,/:("/state.json";"/flake.json";"/quarantine.json";"/proposals.json");
    .tst.applyConfig cfg;
    .resq.config.validationWarnings:();
    .tst.app.args:paths;
    .tst.app.exitImmediately:0b;
    .tst.app.runCoverage:1b~options`runCoverage;
    .tst.app.quiet:1b;
    .tst.output.mode:`run;
    .tst.initReporting[];
    if[.tst.app.runCoverage and not 1b~@[get;`.tst._covInitOk;{0b}];
        '"resQ run: coverage initialization failed"];
    .resq.report:{[results]::};
    .tst.runAll[];
    ::
 };

/ Loading may fail before any expectation can drain registered cleanup tasks.
.resq.api.finish:{[failed;resources;timerCallback]
    .tst.runAllPhase.runSafely[`embeddedCleanupTasks;.tst.runCleanupTasks];
    .tst.runAllPhase.runSafely[`embeddedSpecCleanupTasks;.tst.runSpecCleanupTasks];
    if[failed;.tst.runAllPhase.runSafely[`cleanup;.tst.runAllPhase.finalCleanup]];
    .tst.runAllPhase.runSafely[`embeddedResources;
        .tst.finalizeSpecResources["embedded run";resources;timerCallback]];
    .tst.runAllPhase.runSafely[`cleanupErrors;.tst.runAllPhase.injectCleanupErrors];
    .tst.runAllPhase.runSafely[`resultsSummary;.tst.runAllPhase.computePassed];
    ::
 };

.resq.api.result:{[frameworkError]
    code:$[count frameworkError;1;
        count .tst.app.loadErrors;4;
        (0=count .tst.app.discoveredFiles) and 0=count .resq.state.results;3;
        not .tst.app.passed;1;0];
    `schemaVersion`exitCode`passed`results`diagnostics`loadErrors`frameworkError!(
        1j;code;0=code;.resq.state.results;
        @[get;`.tst.app.diagnostics;{()}];.tst.app.loadErrors;frameworkError)
 };

/ A setup failure before run state exists must not return the host's old rows.
.resq.api.failure:{[message]
    `schemaVersion`exitCode`passed`results`diagnostics`loadErrors`frameworkError!(
        1j;1;0b;.resq.state.emptyResults[];();
        flip `file`error`type!(`symbol$();();`symbol$());message)
 };

/ The runner retains ownership after a failed coverage assignment. Before
/ restoring the host namespace (which removes that ownership), retry exact
/ owned wrappers with native set, independently of the coverage helper.
.resq.api.unwindCoverage:{[]
    names:@[key;`.tst.covWrappers;{()}];
    raze {[name]
        @[{
            live:get x;
            if[live~.tst.covWrappers x;x set .tst.origFuncs x];
            ()};name;{[e]enlist "coverage restore: ",e}]
    } each names
 };

/ Restore independently: one failed operation must not prevent the remaining
/ callbacks or namespaces from being restored. Return errors to the caller.
.resq.api.restore:{[saved]
    errors:();
    errors,:raze {[n;v]
        .[{[n;v]n set v;()};(n;v);{[e]enlist e}]
      }'[`.tst`.utl`.resq;saved`namespaces];
    errors,:raze {[name;entry]
        @[{$[first x 1;(x 0) set last x 1;system "x ",string x 0];()};
          (name;entry);{[e]enlist e}]
      }'[saved`callbackNames;saved`callbacks];
    errors,:@[{system x;()};"cd ",saved`cwd;{[e]enlist e}];
    errors,:@[{system x;()};"t ",string saved`timer;{[e]enlist e}];
    errors,:@[{system x;()};"d ",string saved`namespace;{[e]enlist e}];
    errors
 };

/ Public API. Paths: string, symbol, or list thereof. Options: dictionary.
/ Returns schema-v1 result; invalid/busy calls signal before tests are loaded.
/ Trusted in-process tests can still exit/hang; use the launcher for containment.
.resq.run:{[paths;options]
    if[.resq.api.active or `running~@[get;`.tst.app.executionState;{`}];
        '"resQ run: an execution is already active"];
    if[1b~@[get;`.tst.coverageEnabled;{0b}];'"resQ run: coverage already active"];
    if[count @[key;`.tst.covWrappers;{()}];'"resQ run: coverage restoration is pending"];
    if[(count .tst.mockState.removeList) or count (key .tst.mockState.store) except enlist `;
        '"resQ run: restore existing mocks before starting"];
    options:.resq.api.options options;
    paths:$[(type paths) in 10 -11h;enlist paths;paths];
    if[(not (type paths) in 0 11h) or 0=count paths;'"resQ run: provide nonempty test paths"];
    if[not all (type each paths) in 10 -11h;'"resQ run: paths must be strings or symbols"];
    paths:.utl.pathToString each paths;
    if[any 0=count each paths;'"resQ run: paths must not be empty"];
    saved:`namespaces`callbackNames`callbacks`cwd`timer`namespace!(
        get each `.tst`.utl`.resq;.resq.api.callbackNames;
        {@[{(1b;get x)};x;{[e](0b;::)}]} each .resq.api.callbackNames;
        system "cd";system "t";system "d");
    restore:.resq.api.restore;
    finish:.resq.api.finish;
    resultFn:.resq.api.result;
    unwindCoverage:.resq.api.unwindCoverage;
    appBefore:get `.tst.app;
    resourceOutcome:@[{(0b;.tst.captureResourceState[])};();{[e](1b;e)}];
    `.tst.app set appBefore;
    if[first resourceOutcome;:.resq.api.failure last resourceOutcome];
    resources:last resourceOutcome;
    timerCallback:@[get;`.z.ts;{::}];
    tempOutcome:@[{(0b;first system x)};
        "mktemp -d ",.utl.shellQuote[.utl.tempRoot[],"/resq-embedded-XXXXXXXX"];
        {[e](1b;e)}];
    if[first tempOutcome;:.resq.api.failure "temporary directory: ",last tempOutcome];
    temp:last tempOutcome;
    removeCmd:"rm -rf -- ",.utl.shellQuote temp;
    .resq.api.active:1b;
    outcome:.[{[p;o;t](0b;.resq.api.prepare[p;o;t])};(paths;options;temp);{[e](1b;e)}];
    finishErrors:.[{[f;a] .[f;a];()};(finish;(first outcome;resources;timerCallback));{[e]enlist e}];
    frameworkErrors:$[first outcome;enlist last outcome;()];
    frameworkErrors,:finishErrors;
    frameworkErrors,:@[unwindCoverage;();{[e]enlist e}];
    result:resultFn "; " sv frameworkErrors;
    errors:restore saved;
    removeResult:@[{system x;()};removeCmd;{[e]enlist e}];
    errors,:removeResult;
    if[count errors;
        result[`exitCode]:1;result[`passed]:0b;
        errors:(enlist result`frameworkError),errors;
        result[`frameworkError]:"restore failed: ","; " sv errors where 0<count each errors];
    result
 };
