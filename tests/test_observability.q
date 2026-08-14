.tst.desc["Observability contract v2"]{
  should["derive stable test identities from repository-relative paths"]{
    oldRoot:.tst.app.baseDir;
    .tst.app.baseDir:"/checkout/a";
    leftId:.tst.stableTestId["/checkout/a/tests/test_orders.q";`orders;"accepts"];
    .tst.app.baseDir:"/different/root";
    rightId:.tst.stableTestId["/different/root/tests/test_orders.q";`orders;"accepts"];
    .tst.app.baseDir:oldRoot;
    leftId musteq rightId;
    leftId mustlike "test_*";
  };

  should["derive geometry-independent typed identity-v3 goldens"]{
    oldConsole:system "c";
    oldPrecision:system "P";
    prefix:240#"x";
    leftParams:`value`kind!((prefix,"left-tail");1j);
    rightParams:`value`kind!((prefix,"right-tail");1j);
    typedParams:`value`kind!((prefix,"left-tail");1f);
    system "c 20 35";
    system "P 3";
    narrow:(.tst.stableTestId["tests/test_identity.q";`identity;"long case"];
      .tst.stableCaseId["test_0123456789abcdef0123456789abcdef";0j;leftParams]);
    system "c 80 500";
    system "P 17";
    wide:(.tst.stableTestId["tests/test_identity.q";`identity;"long case"];
      .tst.stableCaseId["test_0123456789abcdef0123456789abcdef";0j;leftParams]);
    system "c ",string[oldConsole 0]," ",string oldConsole 1;
    system "P ",string oldPrecision;
    narrow musteq wide;
    last[narrow] mustne .tst.stableCaseId[
      "test_0123456789abcdef0123456789abcdef";0j;rightParams];
    last[narrow] mustne .tst.stableCaseId[
      "test_0123456789abcdef0123456789abcdef";0j;typedParams];
    first[narrow] musteq "test_fb3a48a62c4ab9456444ee9869a3851c";
    last[narrow] musteq "case_a2782e7e50990daae89c8a7babaa6aad";
  };

  should["derive precision-independent diagnostic identities"]{
    oldConsole:system "c";
    oldPrecision:system "P";
    diagnostic:`type`severity`phase`message`data!(
      `probe;`info;`execution;"float payload";
      enlist[`elapsed]!enlist 0.123456789123456);
    / Differs from `diagnostic` only past 7 significant digits, the default \P.
    sibling:`type`severity`phase`message`data!(
      `probe;`info;`execution;"float payload";
      enlist[`elapsed]!enlist 0.123456789999999);
    system "c 20 35";
    system "P 3";
    narrow:.tst.stableDiagnosticId["test_0123456789abcdef0123456789abcdef";0j;diagnostic];
    system "c 80 500";
    system "P 17";
    wide:.tst.stableDiagnosticId["test_0123456789abcdef0123456789abcdef";0j;diagnostic];
    system "c ",string[oldConsole 0]," ",string oldConsole 1;
    system "P ",string oldPrecision;
    narrow musteq wide;
    narrow mustne .tst.stableDiagnosticId[
      "test_0123456789abcdef0123456789abcdef";0j;sibling];
    narrow mustne .tst.stableDiagnosticId[
      "test_0123456789abcdef0123456789abcdef";1j;diagnostic];
  };

  should["capture complete run metadata without absolute test identity noise"]{
    runInfo:.tst.withIsolatedRunState[{[]
      .tst.beginRunMetadata[];
      .tst.finishRunMetadata[]};()];
    metadataKeys:`id`startedAt`finishedAt`durationSeconds`hostname`cwd,
      `wallDurationSeconds`qVersion`qRelease`os`resqVersion`labels`vcs`ci`config`ordering`selection`shard;
    key[runInfo] mustin metadataKeys;
    runInfo[`id] mustlike "run_*";
    count[runInfo`finishedAt] mustgt 0;
    must[runInfo[`durationSeconds]>=0f;"run duration must be non-negative"];
    runInfo[`wallDurationSeconds] musteq runInfo`durationSeconds;
    `sha`branch`dirty`status mustin key runInfo`vcs;
  };

  should["probe VCS at most once and honor the safe opt-out"]{
    probes:.tst.withIsolatedRunState[{[]
      .tst.app.vcsProbe:1b;
      .tst.beginRunMetadata[];
      ignored:.tst.vcsContext .utl.normalizePath system "cd";
      .tst.app.vcsProbeCount};()];
    probes musteq 1j;
    disabled:.tst.withIsolatedRunState[{[]
      .tst.app.vcsProbe:0b;
      .tst.beginRunMetadata[];
      (.tst.app.runMetadata`vcs;.tst.app.vcsProbeCount)};()];
    first[disabled][`status] musteq "disabled";
    last[disabled] musteq 0j;
  };

  should["normalize supported CI providers deterministically"]{
    githubEnv:(`GITHUB_ACTIONS`GITHUB_RUN_ID`GITHUB_RUN_ATTEMPT,
      `GITHUB_SHA`GITHUB_REF_NAME`GITHUB_REPOSITORY`GITHUB_WORKFLOW`GITHUB_JOB`GITHUB_SERVER_URL)!(
        "true";"41";"2";"abc";"main";"acme/orders";"verify";"test";"https://github.example");
    github:.tst.ciContextFrom githubEnv;
    github[`provider] musteq "github";
    github[`pipelineId] musteq "41";
    github[`buildUrl] musteq "https://github.example/acme/orders/actions/runs/41";
    gitlabEnv:(`GITLAB_CI`CI_PIPELINE_ID`CI_JOB_ID`CI_COMMIT_SHA,
      `CI_COMMIT_BRANCH`CI_PROJECT_PATH`CI_JOB_NAME`CI_JOB_URL)!(
        "true";"51";"9";"def";"release";"acme/orders";"verify";"https://gitlab/job/9");
    gitlab:.tst.ciContextFrom gitlabEnv;
    gitlab[`provider] musteq "gitlab";
    gitlab[`jobId] musteq enlist "9";
    azureEnv:(`TF_BUILD`BUILD_BUILDID`SYSTEM_JOBID`BUILD_SOURCEVERSION,
      `BUILD_SOURCEBRANCHNAME`BUILD_REPOSITORY_NAME`BUILD_DEFINITIONNAME)!(
        "True";"61";"job";"fed";"main";"orders";"verify");
    azure:.tst.ciContextFrom azureEnv;
    azure[`provider] musteq "azure";
    azure[`pipelineId] musteq "61";
    jenkinsEnv:(`JENKINS_URL`BUILD_ID`JOB_NAME`BUILD_NUMBER,
      `GIT_COMMIT`GIT_BRANCH`BUILD_URL)!(
        "https://jenkins";"71";"orders";"3";"cab";"main";"https://jenkins/71");
    jenkins:.tst.ciContextFrom jenkinsEnv;
    jenkins[`provider] musteq "jenkins";
    jenkins[`buildUrl] musteq "https://jenkins/71";
  };

  should["preserve complete retry history and mark only late passes flaky"]{
    spec:(enlist `title)!enlist `suite;
    hist:(
      `attempt`status`duration`durationSeconds`startedAt`finishedAt`message`failures`assertsRun!(1;`fail;"0D00:00:00.1";0.1;"2026-08-14T10:00:00.000000000Z";"2026-08-14T10:00:00.100000000Z";"no";enlist "no";1);
      `attempt`status`duration`durationSeconds`startedAt`finishedAt`message`failures`assertsRun!(2;`pass;"0D00:00:00.1";0.1;"2026-08-14T10:00:00.100000000Z";"2026-08-14T10:00:00.200000000Z";"";();1));
    expec:`desc`type`result`attempts`retried`flaky`attemptHistory!(
      "eventually";`test;`pass;2;1b;1b;hist);
    telemetry:.tst.expectationTelemetry[spec;expec;"tests/test_retry.q"];
    telemetry[`attempts] musteq 2i;
    telemetry[`retried] musteq 1b;
    telemetry[`flaky] musteq 1b;
    count[telemetry`attemptHistory] musteq 2;
    first[telemetry`attemptHistory][`startedAt]
      musteq "2026-08-14T10:00:00.000000000Z";
  };

  should["record parameter cases independently with stable case identities"]{
    .tst.currentParameterCases:();
    .tst.assertState:.tst.defaultAssertState;
    .tst.parametrize[`x`y!(1 2;10 20);{[x;y] (x+y) mustgt 0}];
    spec:(enlist `title)!enlist `params;
    expec:`desc`type`result`parameterCases!("matrix";`test;`pass;.tst.currentParameterCases);
    telemetry:.tst.expectationTelemetry[spec;expec;"tests/test_params.q"];
    cases:telemetry`parameterCases;
    count[cases] musteq 4;
    all[{x like "case_*"} each cases[;`caseId]] musteq 1b;
    count[distinct cases[;`caseId]] musteq 4;
    all[cases[;`status]=`pass] musteq 1b;
    must[all {all `startedAt`finishedAt in key x} each cases;
         "parameter cases must retain observed intervals"];
  };

  should["replay property generation from a private seed without touching q random"]{
    firstValues:.tst.pickFuzzSeeded[`int;20;4242;"root"];
    secondValues:.tst.pickFuzzSeeded[`int;20;4242;"root"];
    otherValues:.tst.pickFuzzSeeded[`int;20;4243;"root"];
    firstValues musteq secondValues;
    firstValues mustne otherValues;

    oldSeed:system "S";
    system "S 991";
    expectedRandom:8?1000;
    system "S 991";
    ignored:.tst.pickFuzzSeeded[`int;100;77;"private"];
    actualRandom:8?1000;
    system "S ",string oldSeed;
    actualRandom musteq expectedRandom;
  };

  should["replay execution permutations without consuming q random state"]{
    items:`a`b`c`d`e`f`g`h;
    firstOrder:.tst.seededPermutation[items;2026;"tests"];
    replayOrder:.tst.seededPermutation[items;2026;"tests"];
    otherOrder:.tst.seededPermutation[items;2027;"tests"];
    firstOrder musteq replayOrder;
    firstOrder mustne otherOrder;
    sortedOrder:asc firstOrder;
    sortedItems:asc items;
    sortedOrder musteq sortedItems;

    oldSeed:system "S";
    system "S 712";
    expectedRandom:8?1000;
    system "S 712";
    ignored:.tst.seededPermutation[items;99;"private-order"];
    actualRandom:8?1000;
    system "S ",string oldSeed;
    actualRandom musteq expectedRandom;
  };

  should["build one canonical model for every reporter"]{
    row:.tst.oneResultTable `suite`description`status`file`assertsRun!(
      `suite;`test;`pass;"tests/test_observability.q";1i);
    model:.tst.withIsolatedRunState[{[payload]
      .tst.beginRunMetadata[];
      .tst.canonicalRunModel payload};enlist row];
    model[`schemaVersion] musteq 2;
    model[`framework] musteq "resQ";
    model[`summary;`testCount] musteq 1;
    modelRows:model`tests;
    firstRow:modelRows 0;
    firstRow[`testId] mustlike "test_*";
    firstRow[`file] musteq "tests/test_observability.q";
    model[`manifest;`schemaVersion] musteq 3j;
    model[`manifest;`identityAlgorithm] musteq "resq-test-case-id-v3";
    model[`manifest;`identityCodec] mustmatch .tst.identityCodecMetadata[];
    count[.tst.resultRows model] musteq 1;
  };

  should["structure diagnostics, snapshots and benchmark lifecycle data"]{
    .tst.currentSnapshots:();
    .tst.recordSnapshotEvent[`text;"orders";`matched;"tests/__snapshots__/orders.snap.txt"];
    count[.tst.currentSnapshots] musteq 1;
    snapRows:.tst.currentSnapshots;
    snapRec:snapRows 0;
    snapRec[`status] musteq `matched;

    spec:(enlist `title)!enlist `perfSuite;
    measure:`time`space!((`min`med`max`avg`dev!1 1 1 1 0f);(`min`med`max`avg`dev!2 2 2 2 0f));
    expec:`desc`type`result`props`perf!("fast";`perf;`pass;`runs`maxTime!(5;10f);measure);
    telemetry:.tst.expectationTelemetry[spec;expec;"tests/test_perf.q"];
    telemetry[`benchmark;`status] musteq `pass;
    telemetry[`benchmark;`runs] musteq 5;
    telemetry[`benchmark;`limits;`maxTimeMs] musteq 10f;

    diagnostic:.tst.diagnostic[`cleanup;`error;`cleanup;"boom";enlist[`scope]!enlist `suite];
    `type`severity`phase`message`data mustin key diagnostic;
  };

  should["timestamp a test diagnostic at its owning test finish"]{
    diagnostic:.tst.diagnostic[`probe;`info;`execution;"observed";()!()];
    started:"2026-08-12T12:00:00.100000Z";
    finished:"2026-08-12T12:00:00.101000Z";
    row:.tst.oneResultTable `suite`description`status`file`assertsRun`startedAt`finishedAt`diagnostics!(
      `suite;`test;`pass;"tests/test_observability.q";1i;started;finished;enlist diagnostic);
    model:.tst.withIsolatedRunState[{[payload]
      .tst.beginRunMetadata[];
      .tst.canonicalRunModel payload};enlist row];
    diagnostics:.tst.eventRows model`events;
    diagnostics:diagnostics where {"diagnostic.recorded"~x`type} each diagnostics;
    count[diagnostics] musteq 1;
    first[diagnostics][`occurredAt] musteq finished;
  };
};

::
