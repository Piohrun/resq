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
        :`suite`description`status`message`time`failures`assertsRun`file`line`namespace`tags`output!(
            suite;
            "Unavailable expectation";
            `pass;
            "";
            0Nn;
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
    `suite`description`status`message`time`failures`assertsRun`file`line`namespace`tags`output!(
        suite;
        exDesc;
        exResult;
        exMsg;
        exTime;
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
        :enlist `suite`description`status`message`time`failures`assertsRun`file`line`namespace`tags`output!(
            suite;
            "No expectations";
            .tst.normalizeResultStatus $[`result in key spec; spec`result; `pass];
            "";
            0Nn;
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
        bench:`status`runs`measurement`limits!(
            .tst.normalizeResultStatus e`result;
            "j"$$[`runs in key perfOpts;perfOpts`runs;0];
            e`perf;
            `maxTimeMs`maxSpaceBytes!(
                $[`maxTime in key perfOpts;"f"$perfOpts`maxTime;0nf];
                $[`maxSpace in key perfOpts;"f"$perfOpts`maxSpace;0nf]))];
    `testId`caseId`kind`parameters`attempts`retried`flaky`attemptHistory`parameterCases`property`diagnostics`snapshots`benchmark`quarantine!(
        testId;caseId;$[`type in key e;e`type;`test];
        $[`case~$[`type in key e;e`type;`test];e`parameters;()!()];attempts;
        $[`retried in key e;1b~e`retried;attempts>1];
        $[`flaky in key e;1b~e`flaky;(attempts>1) and `pass~.tst.normalizeResultStatus e`result];
        history;cases;prop;.tst.expectationDiagnostics e;snaps;bench;()!())
 };

.tst.completeResultRow:{[row]
    fields:`suite`description`status`message`time`failures`assertsRun`file`line`namespace`tags`output,
        `testId`caseId`kind`parameters`attempts`retried`flaky`attemptHistory`parameterCases`property`diagnostics`snapshots`benchmark`quarantine;
    defaults:fields!(`;`;`pass;"";0Nn;();0i;"";0Ni;"";`symbol$();"";
        "";"";`test;()!();1i;0b;0b;();();()!();();();()!();()!());
    if[99h=type row;defaults[key row]:value row];
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
    columns:`suite`description`status`message`time`failures`assertsRun`file`line`namespace`tags`output,
        `testId`caseId`kind`parameters`attempts`retried`flaky`attemptHistory`parameterCases`property`diagnostics`snapshots`benchmark`quarantine;
    flip columns!(
        ();
        ();
        `symbol$();
        ();
        `timespan$();
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

.tst.selectedConfig:{[]
    names:`strict`quiet`failFast`failHard`passOnly`describeOnly`pollutionGuard,
        `runCoverage`coverageStatements`coverageMin`coverageFunctionMin,
        `coverageLineMin`coverageCompletenessMin`allowPartialLineCoverage,
        `runPerformance`maxTestTime`isolate`isolateWorkers`isolateTimeout,
        `qspecCompat`annotationEnabled`reportFormats`runSpecs`excludeSpecs,
        `randomOrder`executionSeed`lastFailed`failedFirst`stateFile`shardIndex`shardCount`shardUnit,
        `quarantineNonBlocking`flakeProposalsEnabled`flakeHistoryFile`quarantineFile,
        `flakeProposalFile`flakeEvidenceMin`flakeFailureMin`flakeWindow,
        `tagFilter`excludeTagFilter`coverageSources`strictPlugins`pluginFiles;
    names,:`coverageBranches`coverageBranchMin`coverageBranchCompletenessMin;
    appKeys:key `.tst.app;
    present:names where names in appKeys;
    cfg:present!(get each {` sv (`.tst.app;x)} each present);
    rcfg:key `.resq.config;
    extra:`fmt`outDir inter rcfg;
    cfg,(extra!(get each {` sv (`.resq.config;x)} each extra))
 };

.tst.vcsContext:{[root]
    quoted:.utl.shellQuote root;
    prefix:"git -C ",quoted," ";
    sha:.tst.firstCommandLine prefix,"rev-parse HEAD 2>/dev/null";
    branch:.tst.firstCommandLine prefix,"rev-parse --abbrev-ref HEAD 2>/dev/null";
    dirty:0<count .tst.firstCommandLine prefix,"status --porcelain 2>/dev/null";
    `sha`branch`dirty!(sha;branch;dirty)
 };

.tst.ciContext:{[]
    names:`CI`CI_JOB_ID`CI_PIPELINE_ID`CI_COMMIT_SHA`CI_COMMIT_BRANCH,
        `GITHUB_ACTIONS`GITHUB_RUN_ID`GITHUB_RUN_ATTEMPT`GITHUB_SHA,
        `GITHUB_REF_NAME`BUILD_BUILDID`BUILD_SOURCEVERSION`JENKINS_URL;
    vals:getenv each names;
    mask:0<count each vals;
    (names where mask)!(vals where mask)
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

.tst.beginRunMetadata:{[]
    started:.z.p;
    root:.utl.normalizePath system "cd";
    host:getenv `HOSTNAME;
    if[0=count host;host:.tst.firstCommandLine "hostname 2>/dev/null"];
    runId:"run_",.tst.stableHash[string[started],"\n",root,"\n",host];
    .tst.app.runStartedAt:started;
    .tst.app.runFinishedAt:0Np;
    ordering:`randomized`seed`algorithm!(
        1b~@[get;`.tst.app.randomOrder;0b];
        "j"$@[get;`.tst.app.executionSeed;0j];
        "md5-counter-v1");
    metaKeys:`id`startedAt`finishedAt`durationSeconds`hostname`cwd,
        `qVersion`qRelease`os`resqVersion`vcs`ci`config`ordering`selection`shard;
    .tst.app.runMetadata:metaKeys!(
        runId;.tst.isoTimestamp started;"";0f;host;root;string .z.K;
        string .z.k;string .z.o;$[`VERSION in key `.resq;.resq.VERSION;"unknown"];
        .tst.vcsContext root;.tst.ciContext[];.tst.selectedConfig[];ordering;
        .tst.selectionMetadata[];.tst.shardMetadata[]);
    .tst.app.diagnostics:();
    ::
 };

.tst.finishRunMetadata:{[]
    if[not `runMetadata in key `.tst.app;.tst.beginRunMetadata[]];
    finished:.z.p;
    .tst.app.runFinishedAt:finished;
    runMeta:.tst.app.runMetadata;
    runMeta[`finishedAt]:.tst.isoTimestamp finished;
    runMeta[`durationSeconds]:("f"$finished-.tst.app.runStartedAt)%1000000000;
    runMeta[`config]:.tst.selectedConfig[];
    runMeta[`selection]:.tst.selectionMetadata[];
    runMeta[`shard]:.tst.shardMetadata[];
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
    / Reporter/model construction is allowed repeatedly in one process (and the
    / self-suite deliberately builds synthetic models). Extend the discovered
    / selection for synthetic framework/plugin rows while building this model,
    / then restore it before returning so a projection cannot pollute a later
    / real report. Keeping the discovered IDs here is essential for fail-fast:
    / its manifest intentionally records selected tests that were not executed.
    savedSelectedExecutionIds:@[get;`.tst.app.selectedExecutionIds;{()}];
    .tst.app.selectedExecutionIds:distinct
        (.tst.toString each savedSelectedExecutionIds),resultExecutionIds;
    stats:.tst.resultSummary rawRows;
    rows:rawRows;
    summaryKeys:`suiteCount`testCount`assertionCount`passCount`failCount`errorCount,
        `skipCount`duration`durationSeconds;
    summary:summaryKeys!(
        stats`suiteCount;stats`testCount;stats`assertsRun;stats`passCount;
        stats`failCount;stats`errorCount;stats`skipCount;string stats`duration;
        .tst.output.jsonDurationSeconds stats`duration);
    performance:@[get;`.tst.app.perfResults;{()}];
    if[98h=type performance;performance:0!performance];
    coverage:$[1b~@[get;`.tst.app.runCoverage;0b];
        @[get;`.tst.lastCoverageSummary;{()!()}];()!()];
    if[(99h=type coverage) and count coverage;
        coverage:coverage,`basis`minimum`passed!(
            @[get;`.tst.app.coverageBasis;"functions"];
            @[get;`.tst.app.coverageEffectiveMinimum;0];
            @[get;`.tst.app.coveragePassed;0b])];
    modelKeys:`schemaVersion`framework`frameworkVersion`run`summary`tests`performance,
        `coverage`diagnostics`flake;
    model:modelKeys!(2;"resQ";
        $[`VERSION in key `.resq;.resq.VERSION;"unknown"];
        .tst.finishRunMetadata[];summary;rows;performance;coverage;
        @[get;`.tst.app.diagnostics;{()}];
        $[`flakeMetadata in key `.tst;.tst.flakeMetadata[];()!()]);
    manifest:.tst.executionManifest model;
    events:.tst.lifecycleEvents[model;manifest];
    complete:model,`manifest`events!(manifest;events);
    .tst.app.selectedExecutionIds:savedSelectedExecutionIds;
    complete
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
