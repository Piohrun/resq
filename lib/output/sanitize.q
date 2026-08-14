/ Strip ANSI/CSI SGR color escapes (e.g. "\033[32m" ... "\033[0m") from a string
/ so junit/xunit/json reports never carry terminal control bytes. diff.q is the
/ only emitter and it always uses the CSI SGR form ESC "[" <digits/;> "m".
/ q has no regex and ssr cannot take an empty replacement, so this char-walks the
/ string. It only drops WELL-FORMED SGR sequences: on ESC, if the next char is
/ "[", it scans over "0123456789;" and requires a terminating "m" within ~16
/ chars; otherwise it drops ONLY the ESC byte and keeps the rest of the string
/ (a lone ESC or a non-SGR sequence like ESC[2J must never swallow the tail).
/ Non-string args pass through untouched.
.tst.stripAnsi:{[s]
    if[not 10h = type s; :s];
    if[not any s = "\033"; :s];
    esc: "\033";
    / Seed with "" (a char vector) so an all-stripped result is "" not () - the
    / report contract is a char vector even when every byte was a colour code.
    out: "";
    i: 0; n: count s;
    while[i < n;
        $[s[i] = esc;
            [ / Try to match a well-formed SGR sequence ESC "[" <0-9;>* "m".
              j: i + 1;
              matched: 0b;
              if[(j < n) and s[j] = "[";
                  k: j + 1;
                  / Scan over parameter bytes, capped at ~16 chars past "[".
                  while[(k < n) and (k < j + 16) and s[k] in "0123456789;"; k+:1];
                  if[(k < n) and s[k] = "m"; matched: 1b; i: k + 1]
              ];
              / Not a recognised SGR run: drop ONLY the ESC byte, keep the rest.
              if[not matched; i+:1] ];
            [ out,: s[i]; i+:1 ] ] ];
    out
 };

.tst.sanitizeToList:{[x]
    $[0h = type x; x;
      98h = type x; {[tbl; idx] tbl idx}[x] each til count x;
      99h = type x; enlist x;
      enlist x]
 };

.tst.sanitizeExpectations:{[x]
    rows: .tst.sanitizeToList x;
    rows: rows where not (::)~/: rows;
    $[0 = count rows; (); rows]
 };

/ Render a failures/error field into a single plain char vector suitable for a
/ report message: a single string passes through; a list of strings joins with
/ "\n"; non-string elements are stringified via .tst.toString each. The result
/ is then length-capped at .tst.output.reportLimit. No q literal artifacts (no
/ leading `,"` from -3! on a 1-element list), no ~80-char show truncation.
/ Empty/`(::)` inputs collapse to "".
/ NB: .tst.truncate unconditionally re-runs -3! on its val (re-quoting an
/ already-final string), so we length-cap here directly, reusing truncate's
/ "... [truncated N chars]" marker shape so the output contract is identical.
.tst.renderReportMessage:{[val]
    limit: $[`reportLimit in key `.tst.output; .tst.output.reportLimit; 50000];
    s: $[10h = type val; val;                       / already a char vector
         0h = type val;                             / general list
            "\n" sv {[e] $[10h = type e; e; .tst.toString e]} each val;
         .tst.toString val];                        / atom / symbol / other
    n: count s;
    if[n > limit;
        truncLen: limit - 30;
        s: (truncLen # s), "... [truncated ", string[n - truncLen], " chars]"
    ];
    s
 };

/ Machine-report normalization lives in the canonical boundary, not in the JSON
/ plugin: text-only and XML-only runs build the same model before format dispatch.
.tst.output.jsonDurationSeconds:{[v]
    raw:$[0h=type v;0N;98h=type v;first v;v];
    $[null raw;0f;-16h=type raw;raw%1e9;0f]
 };

.tst.output.jsonRow:{[row]
    out:row;
    rawMsg:$[`message in key row;row`message;""];
    out[`message]:.tst.renderReportMessage rawMsg;
    rawFailures:$[`failures in key row;row`failures;()];
    out[`failures]:$[0=count rawFailures;();10h=type rawFailures;enlist rawFailures;
        0h=type rawFailures;{[v]$[10h=type v;v;.tst.toString v]} each rawFailures;
        enlist .tst.toString rawFailures];
    rawTime:$[`time in key row;row`time;0Nn];
    out[`time]:string rawTime;
    out[`durationSeconds]:.tst.output.jsonDurationSeconds rawTime;
    out[`output]:.tst.stripAnsi .tst.renderReportMessage $[`output in key out;out`output;""];
    out
 };

.tst.sanitizeExpectation:{[suite; file; ns; tags; ex]
    if[not 99h = type ex;
        :`suite`description`status`message`time`startedAt`finishedAt`failures`assertsRun`file`line`namespace`tags`output!(
            suite;
            "Unavailable expectation";
            `pass;
            "";
            0Nn;
            (::);
            (::);
            ();
            0;
            file;
            0Ni;
            ns;
            tags;
            "")];

    exDesc:     $[`desc in key ex; .tst.toString ex`desc; "Unnamed expectation"];
    exResult:   .tst.normalizeResultStatus $[`result in key ex; ex`result; `pass];
    exFailures: $[`failures in key ex; ex`failures; ()];
    exErr:      $[`errorText in key ex; ex`errorText; ()];
    exOutput:   $[`output in key ex; .tst.renderReportMessage ex`output; ""];
    rawTime: $[`time in key ex; ex`time; 0Nn];
    exTime: $[(98h = type rawTime) and (0 < count rawTime); first rawTime;
              -16h = type rawTime; rawTime;
              0Nn];
    exAsserts:  $[`assertsRun in key ex;
                    $[(type ex`assertsRun) in (1h,4h,7h,-6h,-7h,6h); ex`assertsRun; 0i];
                    0i];
    / Render failure/error fields into a single plain char vector. A LIST of
    / strings must join with "\n" (NOT .tst.toString, which emits the q literal
    / form: a 1-element list comes out as `,"..."`). Single strings pass through;
    / non-string elements go via .tst.toString each. The joined string is then
    / length-capped at .tst.output.reportLimit through .tst.truncate, which only
    / length-caps an already-string val (it calls -3! on non-strings, so we
    / always hand it a string here).
    exMsg: $[0 < count exFailures; .tst.renderReportMessage exFailures;
                  0 < count exErr; .tst.renderReportMessage exErr;
                  ""];

    / Strip terminal color escapes so file reporters (junit/xunit/json) never
    / carry \033 control bytes. diff colour only ever reaches stdout, but a
    / failure string could still pick one up, so this is defence in depth.
    exMsg: .tst.stripAnsi exMsg;
    exFailures: $[10h = type exFailures; .tst.stripAnsi exFailures;
                  0h = type exFailures; .tst.stripAnsi each exFailures;
                  exFailures];
    exOutput: .tst.stripAnsi exOutput;

    exLine: $[`line in key ex; "i"$ex`line; 0Ni];
    exStarted:$[`startedAt in key ex;ex`startedAt;(::)];
    exFinished:$[`finishedAt in key ex;ex`finishedAt;(::)];
    `suite`description`status`message`time`startedAt`finishedAt`failures`assertsRun`file`line`namespace`tags`output!(
        suite;
        exDesc;
        exResult;
        exMsg;
        exTime;
        exStarted;
        exFinished;
        exFailures;
        exAsserts;
        file;
        exLine;
        ns;
        tags;
        exOutput)
 };

.tst.sanitizeSpec:{[spec]
    suite: $[`title in key spec; .tst.toString spec`title; "Unnamed suite"];
    file:  $[`tstPath in key spec; .tst.toString spec`tstPath; ""];
    ns:    $[`namespace in key spec; .tst.toString spec`namespace; ""];
    tags:  $[`tags in key spec; spec`tags; ()];
    exs:   $[`expectations in key spec; .tst.sanitizeExpectations spec`expectations; ()];

    if[0 = count exs;
        :enlist `suite`description`status`message`time`startedAt`finishedAt`failures`assertsRun`file`line`namespace`tags`output!(
            suite;
            "No expectations";
            .tst.normalizeResultStatus $[`result in key spec; spec`result; `pass];
            "";
            0Nn;
            (::);
            (::);
            ();
            0i;
            file;
            0Ni;
            ns;
            tags;
            "")
    ];
    .tst.sanitizeExpectation[suite;file;ns;tags;] each exs
 };

/ Portable path used by every reporter and by the stable test identity. A path
/ beneath the invocation directory is emitted relative to it; paths outside the
/ repository remain absolute because fabricating a relative path would be
/ misleading. Literal prefix comparison avoids q `like metacharacters in paths.
.tst.repoRelativePath:{[path]
    p: .utl.pathToString path;
    if[0 = count p; :""];
    p: .utl.normalizePath p;
    root: .utl.normalizePath @[get; `.tst.app.baseDir; {system "cd"}];
    prefix: root, "/";
    if[(count p) > count prefix;
        if[prefix ~ (count prefix) # p; :(count prefix) _ p]];
    $[p ~ root; "."; p]
 };

.tst.stableHash:{[input] raze string md5 .tst.toString input};

.tst.stableTestId:{[file;suite;description]
    "test_", .tst.stableHash[.tst.repoRelativePath[file], "\n",
        .tst.toString[suite], "\n", .tst.toString description]
 };

.tst.stableCaseId:{[testId;index;parameters]
    "case_", .tst.stableHash[testId, "\n", string[index], "\n", .Q.s1 parameters]
 };

.tst.expectationTestId:{[spec;expec]
    file:$[`tstPath in key spec;.utl.pathToString spec`tstPath;""];
    suite:$[`title in key spec;spec`title;""];
    description:$[`parentDesc in key expec;
        $[count .tst.toString expec`parentDesc;expec`parentDesc;expec`desc];
        expec`desc];
    .tst.stableTestId[file;suite;description]
 };

.tst.expectationCaseId:{[spec;expec]
    if[not `case~$[`type in key expec;expec`type;`test];:""];
    .tst.stableCaseId[.tst.expectationTestId[spec;expec];
        "j"$expec`caseIndex;expec`parameters]
 };

/ Convert the expectation-only execution state into durable telemetry fields.
/ This is deliberately a helper rather than more locals in expecRan: q limits a
/ function to 24 locals, and the callback already performs result accounting.
.tst.expectationTelemetry:{[s;e;fileText]
    testId:.tst.expectationTestId[s;e];
    caseId:.tst.expectationCaseId[s;e];
    attempts: "i"$$[`attempts in key e; e`attempts; 1];
    history: $[`attemptHistory in key e; e`attemptHistory; ()];
    cases: $[`parameterCases in key e; e`parameterCases; ()];
    cases: {[parent;rec;i]
        out: rec;
        params: $[`parameters in key out; out`parameters; ()!()];
        out[`caseId]: .tst.stableCaseId[parent;i;params];
        out[`index]: i;
        out
    }[testId;;]'[cases;til count cases];
    prop: ()!();
    if[`fuzz ~ $[`type in key e;e`type;`test];
        failedInputs:$[`failedFuzz in key e;e`failedFuzz;()];
        prop: `seed`runs`maxFailRate`failRate`passCount`failCount`failedInputs`shrunkInput!(
            $[`seed in key e;e`seed;
              (`props in key e) and 99h=type e`props;
                $[`seed in key e`props;e[`props;`seed];0Nj];
              0Nj];
            "j"$$[`runs in key e;e`runs;0];
            "f"$$[`maxFailRate in key e;e`maxFailRate;0f];
            "f"$$[`failRate in key e;e`failRate;0f];
            "j"$$[`runs in key e;e`runs;0]-count failedInputs;
            "j"$count failedInputs;
            failedInputs;
            $[`shrunkFailure in key e;e`shrunkFailure;(::)]);
        prop[`generatorProtocol]:.tst.toString $[`generatorProtocol in key e;e`generatorProtocol;`legacy];
        prop[`replayToken]:.tst.toString $[`replayToken in key e;e`replayToken;""];
        prop[`replayTokens]:$[`replayTokens in key e;e`replayTokens;()];
        prop[`originalInput]:$[`originalFailure in key e;e`originalFailure;(::)];
        prop[`minimalInput]:$[`shrunkFailure in key e;e`shrunkFailure;(::)];
        prop[`shrinkSteps]:"j"$$[`shrinkSteps in key e;e`shrinkSteps;0];
        prop[`shrinkCandidates]:"j"$$[`shrinkCandidates in key e;e`shrinkCandidates;0];
        prop[`shrinkTermination]:.tst.toString $[`shrinkTermination in key e;e`shrinkTermination;`notRun];
        prop[`failureSignature]:.tst.toString $[`shrinkFailureSignature in key e;e`shrinkFailureSignature;""];
        prop[`shrinkDurationMs]:"f"$$[`shrinkDurationMs in key e;e`shrinkDurationMs;0f];
    ];
    snaps: $[`snapshots in key e;e`snapshots;()];
    bench:()!();
    if[`perf in key e;
        perfOpts:$[`props in key e;$[99h=type e`props;e`props;()!()];()!()];
        benchmarkId:"benchmark_",.tst.stableHash[testId,"\ntime"];
        measurement:e`perf;
        workload:$[`workload in key measurement;measurement`workload;
            `runs`warmup`gcBefore`gcEach`space!(
                "j"$$[`runs in key perfOpts;perfOpts`runs;0];3j;1b;
                $[`gc in key perfOpts;1b~perfOpts`gc;1b];1b)];
        samples:$[`samples in key measurement;measurement`samples;
            `timeNs`retainedBytes`heapGrowthBytes!(`long$();`long$();`long$())];
        bench:`benchmarkId`testId`file`suite`description`status`runs`metric`unit`measurement`limits`workload`samples`comparison!(
            benchmarkId;testId;.tst.repoRelativePath fileText;
            .tst.toString $[`title in key s;s`title;""];
            .tst.toString e`desc;
            .tst.normalizeResultStatus e`result;
            "j"$$[`runs in key perfOpts;perfOpts`runs;0];
            `time;"nanoseconds";
            e`perf;
            `maxTimeMs`maxSpaceBytes!(
                $[`maxTime in key perfOpts;"f"$perfOpts`maxTime;0nf];
                $[`maxSpace in key perfOpts;"f"$perfOpts`maxSpace;0nf]);
            workload;samples;()!())];
    `testId`caseId`kind`parameters`attempts`retried`flaky`attemptHistory`parameterCases`property`diagnostics`snapshots`benchmark`quarantine!(
        testId;caseId;$[`type in key e;e`type;`test];
        $[`case~$[`type in key e;e`type;`test];e`parameters;()!()];attempts;
        $[`retried in key e;1b~e`retried;attempts>1];
        $[`flaky in key e;1b~e`flaky;(attempts>1) and `pass~.tst.normalizeResultStatus e`result];
        history;cases;prop;.tst.expectationDiagnostics e;snaps;bench;()!())
 };

.tst.completeResultRow:{[row]
    fields:`suite`description`status`message`time`startedAt`finishedAt`failures`assertsRun`file`line`namespace`tags`output,
        `testId`caseId`kind`parameters`attempts`retried`flaky`attemptHistory`parameterCases`property`diagnostics`snapshots`benchmark`quarantine;
    defaults:fields!(`;`;`pass;"";0Nn;(::);(::);();0i;"";0Ni;"";`symbol$();"";
        "";"";`test;()!();1i;0b;0b;();();()!();();();()!();()!());
    if[99h=type row;defaults[key row]:value row];
    / Keep the grouping key atomic even when embedded callers supply a q string.
    / Mixed symbol/string suite columns make `=` interpret a multi-character
    / string as a vector and can crash JUnit/xUnit grouping with a length error.
    defaults[`suite]:`$.tst.toString defaults`suite;
    if[0=count defaults`testId;
        defaults[`testId]:.tst.stableTestId[defaults`file;defaults`suite;defaults`description]];
    defaults[`file]:.tst.repoRelativePath defaults`file;
    defaults
 };

.tst.oneResultTable:{[row] flip enlist each .tst.completeResultRow row};

.tst.isResultRow:{[x]
    if[not 99h = type x; :0b];
    all `suite`description`status in key x
 };

.tst.sanitize:{[specs]
    if[0h = type specs;
        specs: specs where not (::)~/: specs;
        if[0 = count specs; :()];
    ];
    specs: .tst.sanitizeToList specs;
    if[not count specs; :()];
    specs: specs where not (::)~/: specs;
    if[not count specs; :()];
    if[all .tst.isResultRow each specs;
        :specs
    ];
    raze .tst.sanitizeSpec each specs
 };

.tst.emptyResultTable:{[]
    columns:`suite`description`status`message`time`startedAt`finishedAt`failures`assertsRun`file`line`namespace`tags`output,
        `testId`caseId`kind`parameters`attempts`retried`flaky`attemptHistory`parameterCases`property`diagnostics`snapshots`benchmark`quarantine;
    flip columns!(
        ();
        ();
        `symbol$();
        ();
        `timespan$();
        ();
        ();
        ();
        `int$();
        ();
        `int$();
        ();
        ();
        ();
        ();
        ();
        `symbol$();
        ();
        `int$();
        `boolean$();
        `boolean$();
        ();
        ();
        ();
        ();
        ();
        ();
        ())
 };

/ Canonical reporter boundary.
/ accepts: spec objects, expectation rows, flat result tables, or row dictionaries
/ returns: list of result-row dictionaries
.tst.resultRows:{[results]
    if[99h = type results;
        if[all `run`summary`tests in key results;:results`tests]];
    rows: $[`sanitize in key `.tst; .tst.sanitize results; results];
    normalized:$[0h = type rows; rows;
      98h = type rows; {[tbl; idx] tbl idx}[rows] each til count rows;
      99h = type rows; enlist rows;
      enlist rows];
    .tst.completeResultRow each normalized
 };

.tst.isoTimestamp:{[ts]
    s: string ts;
    $[11 > count s;s;(ssr[10#s;".";"-"]),"T",11 _ s,"Z"]
 };

.tst.firstCommandLine:{[command]
    got: @[system; command; {()}];
    $[(10h = type got) and count got;got;
      (0h = type got) and count got;.tst.toString first got;
      ""]
 };

.tst.commandLines:{[command]
    got:@[system;command;{()}];
    $[10h=type got;enlist got;0h=type got;got;()]
 };

.tst.selectedConfig:{[]
    names:`strict`quiet`failFast`failHard`passOnly`describeOnly`pollutionGuard,
        `runCoverage`coverageStatements`coverageMin`coverageFunctionMin,
        `coverageLineMin`coverageCompletenessMin`allowPartialLineCoverage,
        `runPerformance`maxTestTime`isolate`isolateWorkers`isolateTimeout,
        `qspecCompat`annotationEnabled`reportFormats`reportProfile`vcsProbe`runSpecs`excludeSpecs,
        `randomOrder`executionSeed`lastFailed`failedFirst`stateFile`shardIndex`shardCount`shardUnit,
        `quarantineNonBlocking`flakeProposalsEnabled`flakeHistoryFile`quarantineFile,
        `flakeProposalFile`flakeEvidenceMin`flakeFailureMin`flakeWindow,
        `tagFilter`excludeTagFilter`coverageSources`strictPlugins`pluginFiles,
        `benchmarkBaseline`benchmarkGate`benchmarkAcceptEnvironment,
        `benchmarkAlphaPercent`benchmarkEffectMin`benchmarkMinSamples;
    names,:`coverageBranches`coverageBranchMin`coverageBranchCompletenessMin;
    appKeys:key `.tst.app;
    present:names where names in appKeys;
    cfg:present!(get each {` sv (`.tst.app;x)} each present);
    rcfg:key `.resq.config;
    extra:`fmt`outDir inter rcfg;
    cfg,(extra!(get each {` sv (`.resq.config;x)} each extra))
 };

.tst.runOutputDir:{[]
    @[get;`.tst.app.runOutputDir;{.resq.config.outDir}]
 };

.tst.vcsContext:{[root]
    disabled:`sha`branch`dirty`status!("";"";0b;"disabled");
    if[not 1b~@[get;`.tst.app.vcsProbe;1b];:disabled];
    cached:@[get;`.tst.app.vcsContextCache;{()!()}];
    cachedRoot:@[get;`.tst.app.vcsContextCacheRoot;{""}];
    if[(99h=type cached) and (0<count cached) and root~cachedRoot;:cached];
    quoted:.utl.shellQuote root;
    .tst.app.vcsProbeCount:1j+"j"$@[get;`.tst.app.vcsProbeCount;0j];
    lines:.tst.commandLines "git -C ",quoted,
        " status --porcelain=v2 --branch --untracked-files=normal 2>/dev/null";
    oidLines:lines where lines like "# branch.oid *";
    headLines:lines where lines like "# branch.head *";
    sha:$[count oidLines;13 _ first oidLines;""];
    branch:$[count headLines;14 _ first headLines;""];
    if[sha~"(initial)";sha:""];
    if[branch~"(detached)";branch:""];
    dirty:any not lines like "# *";
    status:$[(count oidLines)+(count headLines);"ok";"unavailable"];
    result:`sha`branch`dirty`status!(sha;branch;dirty;status);
    .tst.app.vcsContextCacheRoot:root;
    .tst.app.vcsContextCache:result;
    result
 };

.tst.envValue:{[environment;name]
    if[not name in key environment;:""];
    rawValue:environment name;
    if[(0h=type rawValue) and (1=count rawValue) and 10h=type first rawValue;
        rawValue:first rawValue];
    .tst.toString rawValue
 };

.tst.ciContextFrom:{[environment]
    getv:.tst.envValue[environment;];
    provider:$[0<count getv `GITHUB_ACTIONS;"github";
        0<count getv `GITLAB_CI;"gitlab";
        0<count getv `TF_BUILD;"azure";
        0<count getv `JENKINS_URL;"jenkins";
        0<count getv `CIRCLECI;"circleci";
        0<count getv `BUILDKITE;"buildkite";
        0<count getv `TEAMCITY_VERSION;"teamcity";
        (0<count getv `bamboo_buildKey) or (0<count getv `bamboo_buildResultKey);"bamboo";
        0<count getv `CI;"generic";"none"];
    pipelineId:"";jobId:"";attempt:"";commitSha:"";branch:"";
    repository:"";workflow:"";buildUrl:"";
    if[provider~"github";
        pipelineId:getv `GITHUB_RUN_ID;jobId:getv `GITHUB_JOB;
        attempt:getv `GITHUB_RUN_ATTEMPT;commitSha:getv `GITHUB_SHA;
        branch:getv `GITHUB_REF_NAME;repository:getv `GITHUB_REPOSITORY;
        workflow:getv `GITHUB_WORKFLOW;
        if[all 0<count each (getv `GITHUB_SERVER_URL;repository;pipelineId);
            buildUrl:(getv `GITHUB_SERVER_URL),"/",repository,"/actions/runs/",pipelineId]];
    if[provider~"gitlab";
        pipelineId:getv `CI_PIPELINE_ID;jobId:getv `CI_JOB_ID;
        attempt:getv `CI_JOB_RETRY;commitSha:getv `CI_COMMIT_SHA;
        branch:getv `CI_COMMIT_BRANCH;repository:getv `CI_PROJECT_PATH;
        workflow:getv `CI_JOB_NAME;buildUrl:getv `CI_JOB_URL];
    if[provider~"azure";
        pipelineId:getv `BUILD_BUILDID;jobId:getv `SYSTEM_JOBID;
        attempt:getv `SYSTEM_JOBATTEMPT;commitSha:getv `BUILD_SOURCEVERSION;
        branch:getv `BUILD_SOURCEBRANCHNAME;repository:getv `BUILD_REPOSITORY_NAME;
        workflow:getv `BUILD_DEFINITIONNAME;
        if[all 0<count each (getv `SYSTEM_TEAMFOUNDATIONCOLLECTIONURI;
                getv `SYSTEM_TEAMPROJECT;pipelineId);
            buildUrl:(getv `SYSTEM_TEAMFOUNDATIONCOLLECTIONURI),
                (getv `SYSTEM_TEAMPROJECT),"/_build/results?buildId=",pipelineId]];
    if[provider~"jenkins";
        pipelineId:getv `BUILD_ID;jobId:getv `JOB_NAME;
        attempt:getv `BUILD_NUMBER;commitSha:getv `GIT_COMMIT;
        branch:getv `GIT_BRANCH;repository:getv `GIT_URL;
        workflow:getv `JOB_NAME;buildUrl:getv `BUILD_URL];
    if[provider~"circleci";
        pipelineId:getv `CIRCLE_WORKFLOW_ID;jobId:getv `CIRCLE_WORKFLOW_JOB_ID;
        if[0=count jobId;jobId:getv `CIRCLE_JOB];
        attempt:getv `CIRCLE_BUILD_NUM;commitSha:getv `CIRCLE_SHA1;
        branch:getv `CIRCLE_BRANCH;workflow:getv `CIRCLE_JOB;
        if[all 0<count each (getv `CIRCLE_PROJECT_USERNAME;getv `CIRCLE_PROJECT_REPONAME);
            repository:(getv `CIRCLE_PROJECT_USERNAME),"/",getv `CIRCLE_PROJECT_REPONAME];
        buildUrl:getv `CIRCLE_BUILD_URL];
    if[provider~"buildkite";
        pipelineId:getv `BUILDKITE_BUILD_ID;jobId:getv `BUILDKITE_JOB_ID;
        attempt:getv `BUILDKITE_RETRY_COUNT;commitSha:getv `BUILDKITE_COMMIT;
        branch:getv `BUILDKITE_BRANCH;repository:getv `BUILDKITE_REPO;
        workflow:getv `BUILDKITE_PIPELINE_SLUG;buildUrl:getv `BUILDKITE_BUILD_URL];
    if[provider~"teamcity";
        pipelineId:getv `BUILD_ID;
        if[0=count pipelineId;pipelineId:getv `BUILD_NUMBER];
        jobId:getv `TEAMCITY_BUILDCONF_NAME;attempt:getv `BUILD_NUMBER;
        commitSha:getv `BUILD_VCS_NUMBER;workflow:getv `TEAMCITY_PROJECT_NAME;
        buildUrl:getv `BUILD_URL];
    if[provider~"bamboo";
        pipelineId:getv `bamboo_buildResultKey;jobId:getv `bamboo_buildKey;
        attempt:getv `bamboo_buildNumber;commitSha:getv `bamboo_planRepository_revision;
        branch:getv `bamboo_planRepository_branch;
        repository:getv `bamboo_planRepository_repositoryUrl;
        workflow:getv `bamboo_planName;
        if[0=count workflow;workflow:getv `bamboo_buildPlanName];
        buildUrl:getv `bamboo_buildResultsUrl;
        if[0=count buildUrl;buildUrl:getv `bamboo_resultsUrl]];
    if[provider~"generic";
        pipelineId:getv `CI_PIPELINE_ID;jobId:getv `CI_JOB_ID;
        commitSha:getv `CI_COMMIT_SHA;branch:getv `CI_COMMIT_BRANCH];
    `provider`pipelineId`jobId`attempt`commitSha`branch`repository`workflow`buildUrl!(
        provider;pipelineId;jobId;attempt;commitSha;branch;repository;workflow;buildUrl)
 };

.tst.ciContext:{[]
    names:`CI`GITHUB_ACTIONS`GITHUB_RUN_ID`GITHUB_RUN_ATTEMPT`GITHUB_SHA,
        `GITHUB_REF_NAME`GITHUB_REPOSITORY`GITHUB_WORKFLOW`GITHUB_JOB`GITHUB_SERVER_URL,
        `GITLAB_CI`CI_JOB_ID`CI_PIPELINE_ID`CI_JOB_RETRY`CI_COMMIT_SHA,
        `CI_COMMIT_BRANCH`CI_PROJECT_PATH`CI_JOB_NAME`CI_JOB_URL,
        `TF_BUILD`BUILD_BUILDID`SYSTEM_JOBID`SYSTEM_JOBATTEMPT`BUILD_SOURCEVERSION,
        `BUILD_SOURCEBRANCHNAME`BUILD_REPOSITORY_NAME`BUILD_DEFINITIONNAME,
        `SYSTEM_TEAMFOUNDATIONCOLLECTIONURI`SYSTEM_TEAMPROJECT,
        `JENKINS_URL`BUILD_ID`JOB_NAME`BUILD_NUMBER`GIT_COMMIT`GIT_BRANCH`GIT_URL`BUILD_URL,
        `CIRCLECI`CIRCLE_WORKFLOW_ID`CIRCLE_WORKFLOW_JOB_ID`CIRCLE_JOB`CIRCLE_BUILD_NUM,
        `CIRCLE_SHA1`CIRCLE_BRANCH`CIRCLE_PROJECT_USERNAME`CIRCLE_PROJECT_REPONAME`CIRCLE_BUILD_URL,
        `BUILDKITE`BUILDKITE_BUILD_ID`BUILDKITE_JOB_ID`BUILDKITE_RETRY_COUNT,
        `BUILDKITE_COMMIT`BUILDKITE_BRANCH`BUILDKITE_REPO`BUILDKITE_PIPELINE_SLUG`BUILDKITE_BUILD_URL,
        `TEAMCITY_VERSION`TEAMCITY_BUILDCONF_NAME`TEAMCITY_PROJECT_NAME`BUILD_VCS_NUMBER,
        `bamboo_buildKey`bamboo_buildResultKey`bamboo_buildNumber`bamboo_planRepository_revision,
        `bamboo_planRepository_branch`bamboo_planRepository_repositoryUrl`bamboo_planName,
        `bamboo_buildPlanName`bamboo_buildResultsUrl`bamboo_resultsUrl;
    vals:{getenv x} each names;
    .tst.ciContextFrom names!vals
 };

/ Healthy and merely observed tests carry a complete quarantine state object in
/ JSON, but that boilerplate is not useful as twelve JUnit properties or xUnit
/ traits. XML publishes quarantine telemetry only when policy metadata exists.
.tst.output.quarantineCarriesInformation:{[qstate]
    if[not 99h=type qstate;:0b];
    names:key qstate;
    active:$[`active in names;1b~qstate`active;0b];
    details:{[state;name]
        $[name in key state;.tst.toString state name;""]
      }[qstate;] each `owner`reason`issue;
    active or (any 0<count each details)
 };

.tst.shardMetadata:{[]
    allFiles:@[get;`.tst.app.allDiscoveredFiles;{()}];
    selected:@[get;`.tst.app.discoveredFiles;{()}];
    unit:@[get;`.tst.app.shardUnit;`file];
    `index`count`unit`algorithm`allFileCount`selectedFileCount`allUnitCount`selectedUnitCount`selectedFiles`selectedExecutionIds!(
        "j"$@[get;`.tst.app.shardIndex;0j];
        "j"$@[get;`.tst.app.shardCount;1j];
        string unit;
        $[unit~`file;"sorted-index-mod-v1";"stable-id-weighted-hash-v1"];
        "j"$count allFiles;
        "j"$count selected;
        "j"$@[get;`.tst.app.shardAllUnitCount;0j];
        "j"$@[get;`.tst.app.shardSelectedUnitCount;0j];
        .tst.repoRelativePath each selected;
        .tst.toString each @[get;`.tst.app.selectedExecutionIds;{()}])
 };

/ The post-filter inventory is the durable evidence boundary for a run. Tests,
/ plugins and reporters are all permitted to build nested/synthetic models, so
/ the final report must not reconstruct discovery and selection from whatever
/ mutable .tst.app values happen to remain at serialization time.
.tst.runSnapshot:{[]
    snapshot:@[get;`.tst.app.canonicalRunSnapshot;{()!()}];
    $[99h=type snapshot;snapshot;()!()]
 };

.tst.captureCanonicalRunSnapshot:{[]
    .tst.app.canonicalRunSnapshot:(
        `runMetadata`runStartedAt`allDiscoveredFiles`discoveredFiles,
        `executionInventory`selectedExecutionIds`selection`shard)!(
            .tst.app.runMetadata;
            .tst.app.runStartedAt;
            (),@[get;`.tst.app.allDiscoveredFiles;{()}];
            (),@[get;`.tst.app.discoveredFiles;{()}];
            @[get;`.tst.app.executionInventory;{()}];
            .tst.toString each @[get;`.tst.app.selectedExecutionIds;{()}];
            .tst.selectionMetadata[];
            .tst.shardMetadata[]);
    ::
 };

/ Synthetic model tests execute inside the live self-test process. Preserve the
/ outer run's reporting state even if the nested callback signals: q's trap
/ handler is a function (never an eager side effect), and restoration happens
/ before a trapped error is re-signalled.
.tst.runStateKeys:`runStartedAt`runFinishedAt`runMetadata`diagnostics,
    `canonicalRunSnapshot`runOutputDir`selectedExecutionIds`selectedTestCount,
    `allDiscoveredFiles`discoveredFiles`executionInventory,
    `shardAllUnitCount`shardSelectedUnitCount`shardAllFileCount,
    `shardSelectedFileCount`executionState`executionIncompleteReason,
    `cleanupErrors`sandboxNamespaces`labels`vcsProbe,
    `vcsContextCache`vcsContextCacheRoot`vcsProbeCount;

.tst.captureRunState:{[]
    present:.tst.runStateKeys inter key `.tst.app;
    present!(get each {` sv (`.tst.app;x)} each present)
 };

.tst.restoreRunState:{[state]
    names:key state;
    i:0;
    while[i<count names;
        set[` sv (`.tst.app;names i);state names i];
        i+:1];
    ::
 };

.tst.withIsolatedRunState:{[fn;args]
    state:.tst.captureRunState[];
    .tst.app.canonicalRunSnapshot:()!();
    outcome:.[
        {[callable;arguments]
            result:$[0=count arguments;callable[];callable . arguments];
            (0b;result)};
        (fn;args);
        {[err](1b;err)}];
    .tst.restoreRunState state;
    if[first outcome;'last outcome];
    last outcome
 };

.tst.beginRunMetadata:{[]
    started:.z.p;
    root:.utl.normalizePath system "cd";
    host:getenv `HOSTNAME;
    if[0=count host;host:.tst.firstCommandLine "hostname 2>/dev/null"];
    runId:"run_",.tst.stableHash[string[started],"\n",root,"\n",host];
    .tst.app.runStartedAt:started;
    .tst.app.runFinishedAt:0Np;
    .tst.app.vcsContextCache:()!();
    .tst.app.vcsContextCacheRoot:"";
    .tst.app.vcsProbeCount:0j;
    ordering:`randomized`seed`algorithm!(
        1b~@[get;`.tst.app.randomOrder;0b];
        "j"$@[get;`.tst.app.executionSeed;0j];
        "md5-counter-v1");
    metaKeys:`id`startedAt`finishedAt`durationSeconds`wallDurationSeconds`hostname`cwd,
        `qVersion`qRelease`os`resqVersion`labels`vcs`ci`config`ordering`selection`shard;
    .tst.app.runMetadata:metaKeys!(
        runId;.tst.isoTimestamp started;"";0f;0f;host;root;string .z.K;
        string .z.k;string .z.o;$[`VERSION in key `.resq;.resq.VERSION;"unknown"];
        .tst.normalizeLabels @[get;`.tst.app.labels;{()!()}];
        .tst.vcsContext root;.tst.ciContext[];.tst.selectedConfig[];ordering;
        .tst.selectionMetadata[];.tst.shardMetadata[]);
    .tst.app.diagnostics:();
    ::
 };

.tst.finishRunMetadata:{[]
    if[not `runMetadata in key `.tst.app;.tst.beginRunMetadata[]];
    current:.tst.app.runMetadata;
    if[count .tst.toString current`finishedAt;:current];
    snapshot:.tst.runSnapshot[];
    runMeta:$[`runMetadata in key snapshot;snapshot`runMetadata;current];
    started:$[`runStartedAt in key snapshot;snapshot`runStartedAt;.tst.app.runStartedAt];
    finished:.z.p;
    .tst.app.runFinishedAt:finished;
    runMeta[`finishedAt]:.tst.isoTimestamp finished;
    runMeta[`durationSeconds]:0f|("f"$finished-started)%1000000000;
    runMeta[`wallDurationSeconds]:runMeta`durationSeconds;
    runMeta[`selection]:$[`selection in key snapshot;
        snapshot`selection;.tst.selectionMetadata[]];
    runMeta[`shard]:$[`shard in key snapshot;
        snapshot`shard;.tst.shardMetadata[]];
    .tst.app.runMetadata:runMeta;
    runMeta
 };

.tst.recordDiagnostic:{[typeName;severity;phase;message;data]
    if[not `diagnostics in key `.tst.app;.tst.app.diagnostics:()];
    .tst.app.diagnostics,:enlist `type`severity`phase`message`data`timestamp!(
        typeName;severity;phase;.tst.toString message;data;.tst.isoTimestamp .z.p);
    ::
 };

.tst.diagnostic:{[typeName;severity;phase;message;data]
    `type`severity`phase`message`data!(
        typeName;severity;phase;.tst.toString message;data)
 };

.tst.expectationDiagnostics:{[e]
    items:();
    status:.tst.normalizeResultStatus $[`result in key e;e`result;`pass];
    failures:$[`failures in key e;(),e`failures;()];
    if[status in `fail`error;
        items,:enlist .tst.diagnostic[
            $[`fuzz~$[`type in key e;e`type;`test];`property;`assertion];
            `error;`execution;
            $[count failures;.tst.renderReportMessage failures;
              `errorText in key e;e`errorText;"Expectation failed"];
            enlist[`failures]!enlist failures]];
    if[`retryNote in key e;
        items,:enlist .tst.diagnostic[`retry;`warning;`execution;e`retryNote;
            `attempts`flaky!($[`attempts in key e;e`attempts;1];1b)]];
    snapshotEvents:$[`snapshots in key e;e`snapshots;()];
    if[count snapshotEvents;
        items,:{[event]
            snapStatus:event`status;
            severity:$[snapStatus in `missing`mismatch;`error;
                snapStatus in `created`updated;`warning;`info];
            .tst.diagnostic[`snapshot;severity;`execution;
                "Snapshot ",.tst.toString[snapStatus],": ",.tst.toString[event`name];event]
        } each snapshotEvents];
    items
 };

.tst.runCompletion:{[rows;resultIds;selectedIds]
    missing:selectedIds except resultIds;
    suites:.tst.toString each {x`suite} each rows;
    kinds:.tst.toString each {x`kind} each rows;
    incomplete:.tst.toString @[get;`.tst.app.executionIncompleteReason;""];
    isDescribe:1b~@[get;`.tst.app.describeOnly;0b];
    isEmpty:1b~@[get;`.tst.app.emptyShard;0b];
    isLoad:(any kinds~\:"load") or any suites~\:"FILE_LOAD_ERROR";
    isIsolation:any {x like "ISOLATED_*"} each suites;
    reason:$[count incomplete;"frameworkError";
        isLoad;"loadError";
        isIsolation;"isolationError";
        isDescribe;"describeOnly";
        isEmpty;"emptyShard";
        count missing;$[(1b~@[get;`.tst.app.failFast;0b]) or
            1b~@[get;`.tst.app.failHard;0b];"failFast";"missingResults"];
        "completed"];
    complete:not reason in ("frameworkError";"loadError";"isolationError";
        "failFast";"missingResults");
    truncated:reason in ("frameworkError";"loadError";"isolationError";
        "failFast";"missingResults");
    `state`complete`truncated`reason`selectedTestCount`resultCount`missingExecutionIds!(
        $[complete;"complete";"incomplete"];complete;truncated;reason;
        "j"$count selectedIds;"j"$count resultIds;missing)
 };

/ One in-memory document is the source for JSON, text, JUnit, and xUnit. XML
/ builders still receive it through resultRows/resultTable, which understand
/ the model and therefore cannot silently select a different set of tests.
.tst.canonicalRunModel:{[results]
    rawRows:.tst.resultRows results;
    identityRows:$[98h=type rawRows;
        {[table;i]table i}[rawRows] each til count rawRows;
        rawRows];
    resultExecutionIds:distinct {
        caseId:.tst.toString x`caseId;
        $[count caseId;caseId;.tst.toString x`testId]
      } each identityRows;
    snapshot:.tst.runSnapshot[];
    selectedBase:$[`selectedExecutionIds in key snapshot;
        snapshot`selectedExecutionIds;
        .tst.toString each @[get;`.tst.app.selectedExecutionIds;{()}]];
    inventory:$[`executionInventory in key snapshot;
        snapshot`executionInventory;
        @[get;`.tst.app.executionInventory;{()}]];
    inventoryIds:.tst.manifestInventoryIds .tst.eventRows inventory;
    / Framework/load/plugin rows are synthesized after the selection snapshot.
    / They are genuine executed evidence, so include only those extra result
    / identities locally; never mutate the durable inventory or live app state.
    selectedIds:distinct selectedBase,resultExecutionIds except inventoryIds;
    stats:.tst.resultSummary rawRows;
    rows:rawRows;
    summaryKeys:`suiteCount`testCount`assertionCount`passCount`failCount`errorCount,
        `skipCount`duration`durationSeconds`testDurationSumSeconds;
    summary:summaryKeys!(
        stats`suiteCount;stats`testCount;stats`assertsRun;stats`passCount;
        stats`failCount;stats`errorCount;stats`skipCount;string stats`duration;
        .tst.output.jsonDurationSeconds[stats`duration];
        .tst.output.jsonDurationSeconds stats`duration);
    performance:@[get;`.tst.app.perfResults;{()}];
    if[98h=type performance;performance:0!performance];
    coverage:$[1b~@[get;`.tst.app.runCoverage;0b];
        @[get;`.tst.lastCoverageSummary;{()!()}];()!()];
    if[(99h=type coverage) and count coverage;
        coverage:(`schemaVersion`enabled`detailArtifact!(2j;1b;"coverage.json")),
            coverage,`basis`minimum`passed!(
            @[get;`.tst.app.coverageBasis;"functions"];
            @[get;`.tst.app.coverageEffectiveMinimum;0];
            @[get;`.tst.app.coveragePassed;0b])];
    run:.tst.finishRunMetadata[];
    runSelection:run`selection;
    runSelection[`selectedTestCount]:"j"$count selectedIds;
    run[`selection]:runSelection;
    runShard:run`shard;
    runShard[`selectedExecutionIds]:selectedIds;
    run[`shard]:runShard;
    run[`completion]:.tst.runCompletion[identityRows;resultExecutionIds;selectedIds];
    modelKeys:`schemaVersion`framework`frameworkVersion`run`summary`tests`performance,
        `coverage`diagnostics`flake`snapshotInventory`benchmarkAnalysis;
    model:modelKeys!(2;"resQ";
        $[`VERSION in key `.resq;.resq.VERSION;"unknown"];
        run;summary;rows;performance;coverage;
        @[get;`.tst.app.diagnostics;{()}];
        $[`flakeMetadata in key `.tst;.tst.flakeMetadata[];()!()];
        @[get;`.tst.app.snapshotInventory;{.tst.emptySnapshotInventory 0b}];
        @[get;`.tst.app.benchmarkAnalysis;{.tst.emptyBenchmarkAnalysis 0b}]);
    manifest:.tst.executionManifest model;
    events:.tst.lifecycleEvents[model;manifest];
    model,`manifest`events!(manifest;events)
 };

/ A failed earlier reporter may add a diagnostic before JSON runs. Reproject
/ just that live evidence and its lifecycle events; the immutable run, manifest,
/ summary and test rows remain byte-for-byte the same canonical build.
.tst.canonicalDiagnosticOverlay:{[model]
    current:@[get;`.tst.app.diagnostics;{()}];
    if[current~model`diagnostics;:model];
    out:model;
    out[`diagnostics]:current;
    out[`events]:.tst.lifecycleEvents[out;out`manifest];
    out
 };

/ Canonical table form for reporters that need qSQL grouping/filtering.
.tst.resultTable:{[results]
    rows: .tst.resultRows results;
    if[0 = count rows; :.tst.emptyResultTable[]];
    flip flip rows
 };

.tst.resultSummary:{[results]
    t: .tst.resultTable results;
    / `symbol$ keeps the empty case a TYPED empty vector: an empty GENERIC
    / list here makes the sums below return () instead of 0, which crashes
    / consumers that cond on the counts (e.g. the text reporter's color path).
    statusNorm: `symbol$ .tst.normalizeResultStatus each t`status;
    `suiteCount`testCount`passCount`failCount`errorCount`skipCount`duration`assertsRun!(
        count distinct t`suite;
        count t;
        sum statusNorm = `pass;
        sum statusNorm = `fail;
        sum statusNorm = `error;
        sum (statusNorm in `skip`pending);
        sum t`time;
        sum t`assertsRun)
 };
