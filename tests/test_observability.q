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

  should["capture complete run metadata without absolute test identity noise"]{
    .tst.beginRunMetadata[];
    runInfo:.tst.finishRunMetadata[];
    metadataKeys:`id`startedAt`finishedAt`durationSeconds`hostname`cwd,
      `qVersion`qRelease`os`resqVersion`vcs`ci`config`ordering`selection`shard;
    key[runInfo] mustin metadataKeys;
    runInfo[`id] mustlike "run_*";
    count[runInfo`finishedAt] mustgt 0;
    must[runInfo[`durationSeconds]>=0f;"run duration must be non-negative"];
    `sha`branch`dirty mustin key runInfo`vcs;
  };

  should["preserve complete retry history and mark only late passes flaky"]{
    spec:(enlist `title)!enlist `suite;
    hist:(
      `attempt`status`duration`durationSeconds`message`failures`assertsRun!(1;`fail;"0D00:00:00.1";0.1;"no";enlist "no";1);
      `attempt`status`duration`durationSeconds`message`failures`assertsRun!(2;`pass;"0D00:00:00.1";0.1;"";();1));
    expec:`desc`type`result`attempts`retried`flaky`attemptHistory!(
      "eventually";`test;`pass;2;1b;1b;hist);
    telemetry:.tst.expectationTelemetry[spec;expec;"tests/test_retry.q"];
    telemetry[`attempts] musteq 2i;
    telemetry[`retried] musteq 1b;
    telemetry[`flaky] musteq 1b;
    count[telemetry`attemptHistory] musteq 2;
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
    .tst.beginRunMetadata[];
    row:.tst.oneResultTable `suite`description`status`file`assertsRun!(
      `suite;`test;`pass;"tests/test_observability.q";1i);
    model:.tst.canonicalRunModel row;
    model[`schemaVersion] musteq 2;
    model[`framework] musteq "resQ";
    model[`summary;`testCount] musteq 1;
    modelRows:model`tests;
    firstRow:modelRows 0;
    firstRow[`testId] mustlike "test_*";
    firstRow[`file] musteq "tests/test_observability.q";
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
};

::
