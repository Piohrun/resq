\d .tst

.tst.quarantineTest.row:{[statusName]
  .tst.completeResultRow `suite`description`status`assertsRun`testId!(
    `flakeTest;`controlled;statusName;1i;"test_0123456789abcdef0123456789abcdef")
 };

.tst.quarantineTest.rowId:{[testId;statusName]
  .tst.completeResultRow `suite`description`status`assertsRun`testId!(
    `flakeTest;`controlled;statusName;1i;testId)
 };

.tst.quarantineTest.historyEntry:{[testId;missed]
  `testId`observations`unseenCompleteRuns!(
    testId;enlist .tst.quarantineTest.observation[`pass;0b];missed)
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

  should["omit insufficient per-row boilerplate while retaining aggregate state"]{
    .tst.app.flakeHistory:.tst.emptyFlakeHistory `missing;
    .tst.app.quarantineManifest:.tst.emptyQuarantineManifest `missing;
    annotated:.tst.annotateFlakeRow .tst.quarantineTest.row `pass;
    annotated[`quarantine] mustmatch ()!();
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

.tst.desc["partial runs preserve flake history"]{
  before{
    `.tst.app.executionState mock `completed;
    `.tst.app.executionIncompleteReason mock "";
    `.tst.app.describeOnly mock 0b;
    `.tst.app.isolateChild mock 0b;
    `.tst.app.shardCount mock 1j;
    `.tst.app.rerunMode mock `all;
    `.tst.app.runSpecs mock ();
    `.tst.app.excludeSpecs mock ();
    `.tst.app.tagFilter mock ();
    `.tst.app.excludeTagFilter mock ();
    `.tst.app.flakeWindow mock 20j;
  };

  should["merge filtered and incomplete evidence without erasing or aging unseen IDs"]{
    a:"test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    b:"test_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    .tst.app.flakeHistory:`status`diagnostic`updatedAt`tests!(
      `ok;"";"";(.tst.quarantineTest.historyEntry[a;0j];
                    .tst.quarantineTest.historyEntry[b;0j]));
    .tst.app.selectedExecutionIds:(a;b);
    .tst.app.runSpecs:enlist "only-a";
    filtered:.tst.appendFlakeObservations enlist .tst.quarantineTest.rowId[a;`pass];
    filteredB:.tst.flakeFindById[filtered;b];
    filteredB[`unseenCompleteRuns] musteq 0j;
    count[filteredB`observations] musteq 1;

    .tst.app.runSpecs:();
    incomplete:.tst.appendFlakeObservations enlist .tst.quarantineTest.rowId[a;`pass];
    incompleteB:.tst.flakeFindById[incomplete;b];
    incompleteB[`unseenCompleteRuns] musteq 0j;

    full:.tst.appendFlakeObservations (
      .tst.quarantineTest.rowId[a;`pass];.tst.quarantineTest.rowId[b;`pass]);
    ({x`testId} each full) musteq asc (a;b);
    count[(.tst.flakeFindById[full;a])`observations] musteq 2;
    count[(.tst.flakeFindById[full;b])`observations] musteq 2;
  };

  should["age deleted IDs only after a complete inventory and prune at the documented bound"]{
    live:"test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    deleted:"test_cccccccccccccccccccccccccccccccc";
    .tst.app.flakeHistory:`status`diagnostic`updatedAt`tests!(
      `ok;"";"";(.tst.quarantineTest.historyEntry[live;0j];
                    .tst.quarantineTest.historyEntry[
                      deleted;.tst.FLAKE_HISTORY_UNSEEN_LIMIT]));
    .tst.app.selectedExecutionIds:enlist live;
    afterComplete:.tst.appendFlakeObservations enlist
      .tst.quarantineTest.rowId[live;`pass];
    must[not deleted in {.tst.toString x`testId} each afterComplete;
         "a deleted identity is retained for the bounded grace period, then pruned"];
  };

  should["key parameterized evidence by stable execution ID"]{
    row:.tst.quarantineTest.rowId["test_base";`pass];
    row[`caseId]:"case_stable";
    .tst.app.flakeHistory:.tst.emptyFlakeHistory `missing;
    .tst.app.selectedExecutionIds:enlist "case_stable";
    entries:.tst.appendFlakeObservations enlist row;
    ((first entries)`testId) musteq "case_stable";
  };
 };

.tst.desc["malformed cache schemas fail open"]{
  should["return structured invalid or unsupported state without throwing"]{
    wd:.utl.tempRoot[],"/resq_bad_cache_",string[.z.i],"_",string `long$.z.p;
    .utl.ensureDir wd;
    history:wd,"/flake.json";
    manifest:wd,"/quarantine.json";
    rerun:wd,"/rerun.json";
    `.tst.app.flakeHistoryFile mock history;
    `.tst.app.quarantineFile mock manifest;
    `.tst.app.stateFile mock rerun;
    `.tst.app.baseDir mock wd;
    `.tst.app.shardCount mock 1j;
    (hsym `$history) 0:enlist
      "{\"schemaVersion\":\"one\",\"kind\":\"resq-flake-history\",\"tests\":[]}";
    (hsym `$manifest) 0:enlist
      "{\"schemaVersion\":1,\"kind\":\"resq-quarantine-manifest\",\"entries\":\"bad\"}";
    (hsym `$rerun) 0:enlist
      "{\"schemaVersion\":{},\"failedTestIds\":\"test_bad\"}";
    outcome:@[{.tst.loadFlakeState[];.tst.loadRerunState[];0b};::;{[e]1b}];
    must[not outcome;"malformed caches must never abort the run"];
    .tst.app.flakeHistory[`status] musteq `invalid;
    .tst.app.quarantineManifest[`status] musteq `invalid;
    .tst.app.rerunState[`status] musteq `invalid;
    must[0<count .tst.app.flakeHistory`diagnostic;
         "invalid history must retain a structured diagnostic"];
    must[0<count .tst.app.rerunState`diagnostic;
         "invalid rerun state must retain a structured diagnostic"];

    (hsym `$history) 0:enlist
      "{\"schemaVersion\":99,\"kind\":\"resq-flake-history\",\"tests\":[]}";
    .tst.loadFlakeState[];
    .tst.app.flakeHistory[`status] musteq `unsupported;
    system "rm -rf -- ",.utl.shellQuote wd;
  };
 };

.tst.desc["flake history durable merge sequences"]{
  before{
    .tst.testState.quarantinePersistenceResults:.resq.state.results;
  };
  after{
    .resq.state.results:.tst.testState.quarantinePersistenceResults;
    wd:@[get;`.tst.testState.quarantinePersistenceDir;{""}];
    if[count[wd] and wd like .utl.tempRoot[],"/resq_flake_merge_*";
      system "rm -rf -- ",.utl.shellQuote wd];
  };

  should["preserve full -> filtered -> full and full -> shard -> full evidence"]{
    wd:.utl.tempRoot[],"/resq_flake_merge_",string[.z.i],"_",string `long$.z.p;
    .tst.testState.quarantinePersistenceDir:wd;
    .utl.ensureDir wd;
    path:wd,"/history.json";
    a:"test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    b:"test_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    initial:`schemaVersion`kind`updatedAt`window`tests!(
      1j;"resq-flake-history";"2026-08-14T00:00:00Z";20j;
      (.tst.quarantineTest.historyEntry[a;0j];
       .tst.quarantineTest.historyEntry[b;0j]));
    (hsym `$path) 0:enlist .j.j initial;
    `.tst.app.flakeHistoryFile mock path;
    `.tst.app.flakeProposalFile mock wd,"/proposals.json";
    `.tst.app.quarantineFile mock wd,"/quarantine.json";
    `.tst.app.baseDir mock wd;
    `.tst.app.executionState mock `completed;
    `.tst.app.executionIncompleteReason mock "";
    `.tst.app.describeOnly mock 0b;
    `.tst.app.isolateChild mock 0b;
    `.tst.app.shardCount mock 1j;
    `.tst.app.shardIndex mock 0j;
    `.tst.app.rerunMode mock `all;
    `.tst.app.runSpecs mock ();
    `.tst.app.excludeSpecs mock ();
    `.tst.app.tagFilter mock ();
    `.tst.app.excludeTagFilter mock ();
    `.tst.app.flakeWindow mock 20j;
    `.tst.app.flakeProposalsEnabled mock 0b;
    `.tst.app.runMetadata mock enlist[`id]!enlist "run_merge";
    .tst.loadFlakeState[];

    rowA:.tst.quarantineTest.rowId[a;`pass];
    rowB:.tst.quarantineTest.rowId[b;`pass];
    .resq.state.results:.tst.oneResultTable rowA;
    .tst.app.selectedExecutionIds:(a;b);
    .tst.app.runSpecs:enlist "only-a";
    must[.tst.persistFlakeState[];"filtered merge must publish"];
    filtered:.tst.readFlakeHistoryAt path;
    count[(.tst.flakeFindById[filtered`tests;b])`observations] musteq 1;

    .tst.app.runSpecs:();
    .resq.state.results:(.tst.oneResultTable rowA) upsert rowB;
    must[.tst.persistFlakeState[];"complete merge must publish"];
    complete:.tst.readFlakeHistoryAt path;
    count[(.tst.flakeFindById[complete`tests;a])`observations] musteq 3;
    count[(.tst.flakeFindById[complete`tests;b])`observations] musteq 2;

    baseBefore:"\n" sv read0 hsym `$path;
    .tst.app.shardCount:2j;
    .resq.state.results:.tst.oneResultTable rowA;
    .tst.app.selectedExecutionIds:enlist a;
    must[.tst.persistFlakeState[];"shard-local history must publish"];
    baseAfter:"\n" sv read0 hsym `$path;
    baseAfter musteq baseBefore;

    .tst.app.shardCount:1j;
    .resq.state.results:(.tst.oneResultTable rowA) upsert rowB;
    .tst.app.selectedExecutionIds:(a;b);
    must[.tst.persistFlakeState[];"post-shard full merge must publish"];
    final:.tst.readFlakeHistoryAt path;
    count[(.tst.flakeFindById[final`tests;a])`observations] musteq 4;
    count[(.tst.flakeFindById[final`tests;b])`observations] musteq 3;
  };
 };
::
