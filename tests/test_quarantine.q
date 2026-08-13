\d .tst

.tst.quarantineTest.row:{[statusName]
  .tst.completeResultRow `suite`description`status`assertsRun`testId!(
    `flakeTest;`controlled;statusName;1i;"test_0123456789abcdef0123456789abcdef")
 };

.tst.quarantineTest.observation:{[statusName;flaky]
  `runId`occurredAt`status`attempts`flaky!(
    "run_0123456789abcdef0123456789abcdef";
    "2026-08-13T00:00:00Z";string statusName;1j;flaky)
 };

.tst.quarantineTest.entry:{[expires]
  `testId`owner`reason`evidence`issue`createdAt`expiresAt!(
    "test_0123456789abcdef0123456789abcdef";"quality";"known intermittent";
    `observations`passes`failures`flakes!4 2 2 0j;
    "Q-123";"2026-08-13T00:00:00Z";expires)
 };

.tst.quarantineTest.save:{[]
  `history`manifest`evidenceMin`failureMin`window`nonBlocking`results`applied`proposals!(
    @[get;`.tst.app.flakeHistory;{.tst.emptyFlakeHistory `missing}];
    @[get;`.tst.app.quarantineManifest;{.tst.emptyQuarantineManifest `missing}];
    @[get;`.tst.app.flakeEvidenceMin;3j];
    @[get;`.tst.app.flakeFailureMin;2j];
    @[get;`.tst.app.flakeWindow;20j];
    @[get;`.tst.app.quarantineNonBlocking;0b];
    .resq.state.results;
    @[get;`.tst.app.flakeStateApplied;0b];
    @[get;`.tst.app.flakeProposals;{()}])
 };

.tst.quarantineTest.restore:{[saved]
  .tst.app.flakeHistory:saved`history;
  .tst.app.quarantineManifest:saved`manifest;
  .tst.app.flakeEvidenceMin:saved`evidenceMin;
  .tst.app.flakeFailureMin:saved`failureMin;
  .tst.app.flakeWindow:saved`window;
  .tst.app.quarantineNonBlocking:saved`nonBlocking;
  .resq.state.results:saved`results;
  .tst.app.flakeStateApplied:saved`applied;
  .tst.app.flakeProposals:saved`proposals;
  ::
 };

\d .

.tst.desc["Evidence-based flake classification"]{
  before{.tst.testState.quarantineSaved:.tst.quarantineTest.save[]};
  after{.tst.quarantineTest.restore .tst.testState.quarantineSaved};

  should["never classify a first failure as suspect"]{
    .tst.app.flakeHistory:.tst.emptyFlakeHistory `missing;
    .tst.app.quarantineManifest:.tst.emptyQuarantineManifest `missing;
    result:.tst.flakeClassification .tst.quarantineTest.row `fail;
    result[`state] musteq `insufficient;
    result[`observations] musteq 1j;
  };

  should["classify only a sufficiently observed pass/fail pattern as suspect"]{
    observations:(.tst.quarantineTest.observation[`fail;0b];
      .tst.quarantineTest.observation[`pass;0b]);
    historyEntry:`testId`observations!(
      "test_0123456789abcdef0123456789abcdef";observations);
    .tst.app.flakeHistory:`status`updatedAt`tests!(`ok;"";enlist historyEntry);
    .tst.app.quarantineManifest:.tst.emptyQuarantineManifest `missing;
    result:.tst.flakeClassification .tst.quarantineTest.row `fail;
    result[`state] musteq `suspect;
    result[`failures] musteq 2j;
    result[`passes] musteq 1j;
  };

  should["keep an active quarantine blocking unless policy is explicitly enabled"]{
    .tst.app.flakeHistory:.tst.emptyFlakeHistory `missing;
    .tst.app.quarantineManifest:`status`updatedAt`entries!(
      `ok;"";enlist .tst.quarantineTest.entry "2099-12-31");
    defaultState:.tst.flakeClassification .tst.quarantineTest.row `fail;
    defaultState[`state] musteq `quarantined;
    defaultState[`nonBlocking] musteq 0b;
    .tst.app.quarantineNonBlocking:1b;
    optedIn:.tst.flakeClassification .tst.quarantineTest.row `fail;
    optedIn[`nonBlocking] musteq 1b;
    must[not .tst.rowBlocksRun .tst.annotateFlakeRow .tst.quarantineTest.row `fail;
      "explicitly non-blocking quarantines should not block the verdict"];
  };

  should["restore expired entries to blocking while retaining metadata"]{
    .tst.app.flakeHistory:.tst.emptyFlakeHistory `missing;
    .tst.app.quarantineManifest:`status`updatedAt`entries!(
      `ok;"";enlist .tst.quarantineTest.entry "2000-01-01");
    .tst.app.quarantineNonBlocking:1b;
    result:.tst.flakeClassification .tst.quarantineTest.row `fail;
    result[`state] musteq `expired;
    result[`nonBlocking] musteq 0b;
    result[`owner] musteq "quality";
  };

  should["leave synthetic framework rows unclassified and blocking"]{
    .tst.app.flakeHistory:.tst.emptyFlakeHistory `missing;
    .tst.app.quarantineManifest:.tst.emptyQuarantineManifest `missing;
    synthetic:.tst.oneResultTable `suite`description`status`kind`quarantine!(
      `FILE_LOAD_ERROR;`missing;`error;(`$"");()!());
    .resq.state.results:synthetic;
    .tst.app.flakeStateApplied:0b;
    .tst.applyFlakeState[];
    rows:.tst.resultRows .resq.state.results;
    count[rows] musteq 1;
    ((first rows)`quarantine) musteq ()!();
    must[.tst.rowBlocksRun first rows;
      "an unclassified framework error must retain a blocking verdict"];
  };
 };
::
