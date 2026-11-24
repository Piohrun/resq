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
    badManifest:`schemaVersion`identityAlgorithm`identityCodec`kind`entries!(
      2j;.tst.IDENTITY_ALGORITHM;.tst.identityCodecMetadata[];
      "resq-quarantine-manifest";"bad");
    (hsym `$manifest) 0:enlist .j.j badManifest;
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
    must[not .utl.pathExists history;
         "unsupported identity history must be removed from the live cache path"];
    archives:string key hsym `$wd;
    archives:archives where archives like "flake.json.identity-mismatch.*.bak";
    count[archives] musteq 1;
    must[.utl.pathExists wd,"/",first archives;
         "unsupported identity history must remain recoverable for migration"];

    mismatched:`schemaVersion`identityAlgorithm`identityCodec`kind`tests!(
      2j;"resq-test-case-id-v2";.tst.identityCodecMetadata[];
      "resq-flake-history";());
    (hsym `$history) 0:enlist .j.j mismatched;
    .tst.loadFlakeState[];
    .tst.app.flakeHistory[`status] musteq `unsupported;
    must[.tst.app.flakeHistory[`diagnostic] like "*identity algorithm or codec*";
         "a mixed identity generation must be rejected before history joins"];
    archives:string key hsym `$wd;
    archives:archives where archives like "flake.json.identity-mismatch.*.bak";
    count[archives] musteq 2;
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
    initial:`schemaVersion`identityAlgorithm`identityCodec`kind`updatedAt`window`tests!(
      2j;.tst.IDENTITY_ALGORITHM;.tst.identityCodecMetadata[];
      "resq-flake-history";"2026-08-14T00:00:00Z";20j;
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
    count[(.tst.flakeStateEntry[filtered;b])`observations] musteq 1;

    .tst.app.runSpecs:();
    .resq.state.results:(.tst.oneResultTable rowA) upsert rowB;
    must[.tst.persistFlakeState[];"complete merge must publish"];
    complete:.tst.readFlakeHistoryAt path;
    count[(.tst.flakeStateEntry[complete;a])`observations] musteq 3;
    count[(.tst.flakeStateEntry[complete;b])`observations] musteq 2;

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
    count[(.tst.flakeStateEntry[final;a])`observations] musteq 4;
    count[(.tst.flakeStateEntry[final;b])`observations] musteq 3;
  };
 };

.tst.desc["state directory stays out of version control"]{
  should["write a self-ignoring .gitignore into a .resq directory, once"]{
    / A first run in a checkout used to leave .resq/ untracked in git status.
    base:.utl.tempRoot[],"/resq_statedir_",string[.z.i],"_",string `long$.z.p;
    dir:base,"/.resq";
    .tst.ensureStateDir dir;
    ignore:hsym `$dir,"/.gitignore";
    lines:read0 ignore;
    (enlist "*") mustin lines;
    "!quarantine.json" mustin lines;
    ignore 0: enlist "custom";
    .tst.ensureStateDir dir;
    (read0 ignore) musteq enlist "custom";
    other:base,"/reports";
    .tst.ensureStateDir other;
    (key hsym `$other) musteq `symbol$();
    system "rm -rf ",.utl.shellQuote base;
  };
 };
::

/ A workspace used by two q runtimes (q 4.0 at work, q 4.1 on a laptop). Each
/ runtime writes its own identity envelope, so each sees the other's state as
/ a different generation.
.tst.desc["state written by another q runtime"]{
  before{
    wd:.resq.util.tempRoot[],"/resq_two_runtimes_",string[.z.i],"_",string `long$.z.p;
    .resq.util.ensureDir wd;
    `.tst.testState.twoRuntimes.wd set wd;
    `.tst.app.flakeHistoryFile mock wd,"/flake.json";
    `.tst.app.quarantineFile mock wd,"/quarantine.json";
    `.tst.app.stateFile mock wd,"/rerun.json";
    `.tst.app.baseDir mock wd;
    `.tst.app.shardCount mock 1j;
    `.tst.app.passOnly mock 1b;
    / the same documents as this runtime writes, stamped with another q build
    other:.tst.identityCodecMetadata[];
    other[`qVersion]:"3.9";
    other[`qRelease]:"2001.01.01";
    `.tst.testState.twoRuntimes.other set other;
    .tst.registerCleanup[{[d] @[system;"rm -rf -- ",.resq.util.shellQuote d;{}]};enlist wd];
  };
  should["leave the quarantine manifest where it is, and ignore it"]{
    wd:.tst.testState.twoRuntimes.wd;
    manifest:`schemaVersion`identityAlgorithm`identityCodec`kind`entries!(
      2j;.tst.IDENTITY_ALGORITHM;.tst.testState.twoRuntimes.other;
      "resq-quarantine-manifest";());
    text:enlist .j.j manifest;
    (hsym `$wd,"/quarantine.json") 0:text;
    .tst.loadFlakeState[];
    .tst.app.quarantineManifest[`status] musteq `unsupported;
    (read0 hsym `$wd,"/quarantine.json") musteq text;
    names:string key hsym `$wd;
    (count names where names like "quarantine.json.identity-mismatch.*") musteq 0;
    (0<count .tst.app.quarantineManifest[`diagnostic] ss "left in place and ignored") musteq 1b;
  };
  should["keep one archive per runtime however often they take turns"]{
    wd:.tst.testState.twoRuntimes.wd;
    history:`schemaVersion`identityAlgorithm`identityCodec`kind`tests!(
      2j;.tst.IDENTITY_ALGORITHM;.tst.testState.twoRuntimes.other;"resq-flake-history";());
    / a last parameter left open keeps these as functions to call later
    writeOther:{[wd;history;u] (hsym `$wd,"/flake.json") 0:enlist .j.j history}[wd;history];
    archives:{[wd;u] names:string key hsym `$wd; names where names like "flake.json.identity-mismatch.*"}[wd];
    writeOther[::]; .tst.loadFlakeState[];
    writeOther[::]; .tst.loadFlakeState[];
    writeOther[::]; .tst.loadFlakeState[];
    archives[::] musteq enlist "flake.json.identity-mismatch.",.tst.IDENTITY_ALGORITHM,".q3.9-2001.01.01.bak";
  };
  should["take up this runtime's own history where the other runtime left it"]{
    wd:.tst.testState.twoRuntimes.wd;
    mine:`schemaVersion`identityAlgorithm`identityCodec`kind`updatedAt`tests!(
      2j;.tst.IDENTITY_ALGORITHM;.tst.identityCodecMetadata[];"resq-flake-history";
      "2026-11-24T00:00:00.000000000Z";());
    theirs:mine;
    theirs[`identityCodec]:.tst.testState.twoRuntimes.other;
    / this runtime ran earlier and its history was archived by the other one
    own:.tst.identityArchivePath[wd,"/flake.json";.tst.currentIdentityGenerationLabel[]];
    (hsym `$own) 0:enlist .j.j mine;
    (hsym `$wd,"/flake.json") 0:enlist .j.j theirs;
    .tst.loadFlakeState[];
    .tst.app.flakeHistory[`status] musteq `ok;
    .tst.app.flakeHistory[`updatedAt] musteq "2026-11-24T00:00:00.000000000Z";
    .resq.util.pathExists[own] musteq 0b;
    .resq.util.pathExists[.tst.identityArchivePath[wd,"/flake.json";.tst.IDENTITY_ALGORITHM,".q3.9-2001.01.01"]] musteq 1b;
  };
 };

.tst.desc["a quarantine entry has to be filled in"]{
  should["reject an entry whose owner, reason, issue or expiry is empty"]{
    full:`testId`owner`reason`evidence`issue`createdAt`expiresAt!(
      "test_abc";"team";"flaky vendor sandbox";(enlist `observations)!enlist 3;"Q-1";
      "2026-11-24T00:00:00.000000000Z";"2099-01-01");
    .tst.validQuarantineEntry[full] musteq 1b;
    blanked:{[entry;field] entry[field]:""; .tst.validQuarantineEntry entry}[full] each `owner`reason`issue`createdAt`expiresAt`testId;
    blanked musteq 6#0b;
  };
  should["not treat a missing expiry date as never expiring"]{
    .tst.quarantineExpired[enlist[`expiresAt]!enlist ""] musteq 1b;
    .tst.quarantineExpired[enlist[`expiresAt]!enlist "2099-01-01"] musteq 0b;
    .tst.quarantineExpired[enlist[`expiresAt]!enlist "2001-01-01"] musteq 1b;
    .tst.quarantineExpired[enlist[`expiresAt]!enlist "not a date"] musteq 1b;
  };
 };

/ A complete run of one file says nothing about tests in another. Entries
/ name their test file, and a run ages only the entries it can speak for.
.tst.quarantineTest.scopeRow:{[testId;file]
  row:.tst.quarantineTest.rowId[testId;`pass];
  row[`file]:file;
  row
 };

.tst.quarantineTest.placedEntry:{[testId;file;occurredAt]
  `testId`file`observations`unseenCompleteRuns!(
    testId;file;
    enlist `runId`occurredAt`status`attempts`flaky!(
      "run_0123456789abcdef0123456789abcdef";occurredAt;"pass";1j;0b);
    0j)
 };

.tst.desc["a run ages only the flake history it can speak for"]{
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
    base:.utl.tempRoot[],"/resq_flake_scope_",string[.z.i],"_",string `long$.z.p;
    .utl.ensureDir base,"/tests";
    (hsym `$base,"/tests/test_a.q") 0: enlist "/ a";
    (hsym `$base,"/tests/test_b.q") 0: enlist "/ b";
    .tst.registerCleanup[{[d] @[system;"rm -rf -- ",.utl.shellQuote d;{}]};enlist base];
    `.tst.app.baseDir mock base;
    / the run looked at test_a.q only
    `.tst.app.allDiscoveredFiles mock enlist base,"/tests/test_a.q";
    `scopeBase mock base;
  };

  should["record the file of every test it observes"]{
    a:"test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    `.tst.app.flakeHistory mock .tst.emptyFlakeHistory `missing;
    `.tst.app.selectedExecutionIds mock enlist a;
    entries:.tst.appendFlakeObservations enlist .tst.quarantineTest.scopeRow[a;scopeBase,"/tests/test_a.q"];
    ((first entries)`file) musteq "tests/test_a.q";
  };

  should["leave a test in a file it did not look at exactly as it was"]{
    a:"test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    b:"test_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    now:.tst.isoTimestamp .z.p;
    `.tst.app.flakeHistory mock `status`diagnostic`updatedAt`tests!(
      `ok;"";"";(.tst.quarantineTest.placedEntry[a;"tests/test_a.q";now];
                 .tst.quarantineTest.placedEntry[b;"tests/test_b.q";now]));
    `.tst.app.selectedExecutionIds mock enlist a;
    entries:.tst.appendFlakeObservations enlist .tst.quarantineTest.scopeRow[a;scopeBase,"/tests/test_a.q"];
    kept:.tst.flakeFindById[entries;b];
    kept[`unseenCompleteRuns] musteq 0j;
    kept[`file] musteq "tests/test_b.q";
    count[kept`observations] musteq 1;
  };

  should["age a test that is gone from a file it looked at, or whose file is gone"]{
    a:"test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    removed:"test_cccccccccccccccccccccccccccccccc";
    orphan:"test_dddddddddddddddddddddddddddddddd";
    now:.tst.isoTimestamp .z.p;
    `.tst.app.flakeHistory mock `status`diagnostic`updatedAt`tests!(
      `ok;"";"";(.tst.quarantineTest.placedEntry[a;"tests/test_a.q";now];
                 .tst.quarantineTest.placedEntry[removed;"tests/test_a.q";now];
                 .tst.quarantineTest.placedEntry[orphan;"tests/test_deleted.q";now]));
    `.tst.app.selectedExecutionIds mock enlist a;
    entries:.tst.appendFlakeObservations enlist .tst.quarantineTest.scopeRow[a;scopeBase,"/tests/test_a.q"];
    ((.tst.flakeFindById[entries;removed])`unseenCompleteRuns) musteq 1j;
    ((.tst.flakeFindById[entries;orphan])`unseenCompleteRuns) musteq 1j;
    ((.tst.flakeFindById[entries;a])`unseenCompleteRuns) musteq 0j;
  };

  should["keep an entry with no file on record until it has not been seen for a month"]{
    a:"test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    recent:"test_eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee";
    old:"test_ffffffffffffffffffffffffffffffff";
    entry:{[id;at] (.tst.quarantineTest.placedEntry[id;"";at]) _ `file};
    `.tst.app.flakeHistory mock `status`diagnostic`updatedAt`tests!(
      `ok;"";"";(entry[recent;.tst.isoTimestamp .z.p-5D];
                 entry[old;.tst.isoTimestamp .z.p-40D]));
    `.tst.app.selectedExecutionIds mock enlist a;
    entries:.tst.appendFlakeObservations enlist .tst.quarantineTest.scopeRow[a;scopeBase,"/tests/test_a.q"];
    ids:{.tst.toString x`testId} each entries;
    (recent in ids) musteq 1b;
    (old in ids) musteq 0b;
    / not placed, so not aged either
    ((.tst.flakeFindById[entries;recent])`unseenCompleteRuns) musteq 0j;
  };
 };

/ The lock around the flake history was reclaimed only when its PID was not
/ running. In a container the PID a killed run left behind is running again,
/ as something else: every run then waited five seconds and saved nothing.
.tst.desc["a flake-history lock that nobody holds is reclaimed"]{
  before{
    dir:.utl.tempRoot[],"/resq_flake_lock_",string[.z.i],"_",string `long$.z.p;
    .utl.ensureDir dir;
    .tst.registerCleanup[{[d] @[system;"rm -rf -- ",.utl.shellQuote d;{}]};enlist dir];
    `historyPath mock dir,"/flake.json";
    / do not wait five seconds for a lock that is held
    `.tst.FLAKE_LOCK_TRIES mock 2;
    `hold mock {[path;lines]
      system "mkdir ",.utl.shellQuote path,".lock";
      if[count lines;(hsym `$path,".lock/pid") 0: lines];};
    `started mock {[pid] first system "ps -o lstart= -p ",string pid};
  };

  should["take a free lock, write down who holds it, and give it back"]{
    .tst.acquireFlakeHistoryLock[historyPath] musteq 0j;
    owner:read0 hsym `$historyPath,".lock/pid";
    (first owner) musteq string .z.i;
    (count owner) musteq 2;
    .tst.releaseFlakeHistoryLock historyPath;
    (() ~ key hsym `$historyPath,".lock") musteq 1b;
  };

  should["honour a lock held by a process that is running"]{
    hold[historyPath;(string .z.i;started .z.i)];
    .tst.acquireFlakeHistoryLock[historyPath] musteq 75j;
  };

  should["reclaim a lock whose process is gone"]{
    hold[historyPath;enlist "999999999"];
    .tst.acquireFlakeHistoryLock[historyPath] musteq 0j;
  };

  should["reclaim a lock whose PID now belongs to another process"]{
    / this process's PID, with a start time that is not this process's
    hold[historyPath;(string .z.i;"Thu Jan  1 00:00:00 1970")];
    .tst.acquireFlakeHistoryLock[historyPath] musteq 0j;
    (first read0 hsym `$historyPath,".lock/pid") musteq string .z.i;
  };

  should["reclaim a lock that is older than any writer needs, with or without a PID"]{
    hold[historyPath;enlist string .z.i];
    / fresh, and its PID is running: honoured
    .tst.acquireFlakeHistoryLock[historyPath] musteq 75j;
    system "touch -d '10 minutes ago' ",.utl.shellQuote historyPath,".lock";
    .tst.acquireFlakeHistoryLock[historyPath] musteq 0j;
    .tst.releaseFlakeHistoryLock historyPath;
    hold[historyPath;()];
    system "touch -d '10 minutes ago' ",.utl.shellQuote historyPath,".lock";
    .tst.acquireFlakeHistoryLock[historyPath] musteq 0j;
  };

  should["say on the console when a run could not save its evidence"]{
    hold[historyPath;(string .z.i;started .z.i)];
    `.tst.flakeHistoryPath mock {[] historyPath};
    `.tst.app.isolateChild mock 0b;
    `.tst.app.describeOnly mock 0b;
    `.tst.app.passOnly mock 0b;
    `.resq.state.results mock .tst.oneResultTable .tst.quarantineTest.rowId["test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";`pass];
    `.tst.testState.lockNotes mock ();
    `.tst.noteStateProblem mock {[text] .tst.testState.lockNotes,: enlist text;};
    `.tst.recordDiagnostic mock {[a;b;c;d;e] ::};
    .tst.persistFlakeState[] musteq 0b;
    (count .tst.testState.lockNotes) musteq 1;
    ((first .tst.testState.lockNotes) like "the flake history is locked by another run*") musteq 1b;
  };
 };

/ State problems reached the report's diagnostics and nothing else: a run
/ that ignored a corrupt state file, or could not save its own, looked like
/ any other on the console.
.tst.desc["state problems are said on the console, once"]{
  before{
    `.tst.app.stateNotes mock ();
    `.tst.app.passOnly mock 1b;
    `.tst.app.diagnostics mock ();
  };

  should["say a problem once however often it is met"]{
    .tst.noteStateProblem "the same thing";
    .tst.noteStateProblem "the same thing";
    .tst.noteStateProblem "another thing";
    .tst.app.stateNotes musteq ("the same thing";"another thing");
  };

  should["record the diagnostic and say it with its path"]{
    .tst.recordStateWarning[`rerun;`persistence;"Unable to write rerun state";enlist[`path]!enlist "out/s.json"];
    (count .tst.app.diagnostics) musteq 1;
    ((first .tst.app.diagnostics)`severity) musteq `warning;
    .tst.app.stateNotes musteq enlist "Unable to write rerun state (out/s.json)";
  };

  should["say once that a state directory cannot be made, and not try again loudly"]{
    / nothing can be made under /dev/null, whoever runs this
    .tst.stateDirReady["/dev/null/resq"] musteq 0b;
    .tst.stateDirReady["/dev/null/resq"] musteq 0b;
    (count .tst.app.stateNotes) musteq 1;
    ((first .tst.app.stateNotes) like "cannot create the state directory /dev/null/resq;*") musteq 1b;
    .resq.util.tryEnsureDir["/dev/null/resq"] musteq 0b;
    dir:.utl.tempRoot[],"/resq_state_dir_",string[.z.i],"_",string `long$.z.p;
    .tst.registerCleanup[{[d] @[system;"rm -rf -- ",.utl.shellQuote d;{}]};enlist dir];
    .tst.stateDirReady[dir,"/a/b"] musteq 1b;
    (.utl.pathExists dir,"/a/b") musteq 1b;
  };
 };

/ The history is one JSON document, and every run parsed, rebuilt and wrote
/ all of it. It is now laid out one test to a line, and a run parses only
/ the entries it has something to say about.
.tst.desc["the flake history is kept one test to a line"]{
  before{
    wd:.utl.tempRoot[],"/resq_flake_lines_",string[.z.i],"_",string `long$.z.p;
    .utl.ensureDir wd,"/tests";
    (hsym `$wd,"/tests/test_a.q") 0: enlist "/ a";
    (hsym `$wd,"/tests/test_b.q") 0: enlist "/ b";
    .tst.registerCleanup[{[d] @[system;"rm -rf -- ",.utl.shellQuote d;{}]};enlist wd];
    `historyPath mock wd,"/history.json";
    `.tst.app.flakeHistoryFile mock wd,"/history.json";
    `.tst.app.flakeProposalFile mock wd,"/proposals.json";
    `.tst.app.quarantineFile mock wd,"/quarantine.json";
    `.tst.app.baseDir mock wd;
    `.tst.app.allDiscoveredFiles mock enlist wd,"/tests/test_a.q";
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
    `.tst.app.runMetadata mock enlist[`id]!enlist "run_lines";
    `.tst.app.flakeHistory mock .tst.emptyFlakeHistory `missing;
    `.resq.state.results mock .resq.state.results;
    `idA mock "test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    `idB mock "test_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    `runOnly mock {[wd;id;file]
      .resq.state.results:.tst.oneResultTable .tst.quarantineTest.scopeRow[id;wd,"/tests/",file];
      .tst.app.selectedExecutionIds:enlist id;
      .tst.loadFlakeState[];
      .tst.persistFlakeState[]}[wd];
  };

  should["write a document that is still one valid JSON document"]{
    must[runOnly[idA;"test_a.q"];"the history must be saved"];
    lines:read0 hsym `$historyPath;
    (count lines) musteq 3;
    ((first lines) like "*\"tests\":[[]") musteq 1b;
    (last lines) musteq "]}";
    doc:.j.k "\n" sv lines;
    (doc`schemaVersion) musteq 2f;
    ({x`testId} each doc`tests) musteq enlist idA;
    ((first doc`tests)`file) musteq "tests/test_a.q";
    / the keys every earlier version reads are all there
    (asc key first doc`tests) musteq asc `testId`file`unseenCompleteRuns`observations;
  };

  should["read it back without parsing the entries, and find one when asked"]{
    runOnly[idA;"test_a.q"];
    state:.tst.readFlakeHistoryAt historyPath;
    (state`status) musteq `ok;
    (state`lineMode) musteq 1b;
    (state`lineIds) musteq enlist `$idA;
    (count state`tests) musteq 0;
    entry:.tst.flakeStateEntry[state;idA];
    (entry`testId) musteq idA;
    (count entry`observations) musteq 1;
    (.tst.flakeStateEntry[state;idB]) musteq ()!();
  };

  should["carry the entry of a test it did not run as the text it was"]{
    runOnly[idB;"test_b.q"];
    before:read0 hsym `$historyPath;
    runOnly[idA;"test_a.q"];
    after:read0 hsym `$historyPath;
    (count after) musteq 4;
    / test_b's line is untouched, apart from the comma that now follows it
    lineOf:{[lines;id] first lines where lines like "{\"testId\":\"",id,"*"};
    (lineOf[after;idB]) musteq lineOf[before;idB];
    / entries are in ID order
    ((after 1) like "{\"testId\":\"",idA,"*") musteq 1b;
    ((after 1) like "*,") musteq 1b;
  };

  should["read a history in any other layout whole, and write it back in lines"]{
    whole:`schemaVersion`identityAlgorithm`identityCodec`kind`updatedAt`window`tests!(
      2j;.tst.IDENTITY_ALGORITHM;.tst.identityCodecMetadata[];
      "resq-flake-history";"2026-08-14T00:00:00Z";20j;
      (.tst.quarantineTest.placedEntry[idA;"tests/test_a.q";.tst.isoTimestamp .z.p];
       .tst.quarantineTest.placedEntry[idB;"tests/test_b.q";.tst.isoTimestamp .z.p]));
    (hsym `$historyPath) 0: enlist .j.j whole;
    state:.tst.readFlakeHistoryAt historyPath;
    (state`status) musteq `ok;
    (state`lineMode) musteq 0b;
    (count state`tests) musteq 2;
    runOnly[idA;"test_a.q"];
    again:.tst.readFlakeHistoryAt historyPath;
    (again`lineMode) musteq 1b;
    (count (.tst.flakeStateEntry[again;idA])`observations) musteq 2;
    (count (.tst.flakeStateEntry[again;idB])`observations) musteq 1;
  };

  should["not take a file for the line layout when a line is not an entry"]{
    runOnly[idA;"test_a.q"];
    runOnly[idB;"test_b.q"];
    lines:read0 hsym `$historyPath;
    / a line that was cut short
    (hsym `$historyPath) 0: @[lines;1;:;30 sublist lines 1];
    (first .tst.splitFlakeHistoryLines read0 hsym `$historyPath) musteq 0b;
    ((.tst.readFlakeHistoryAt historyPath)`status) musteq `invalid;
    / two entries with one ID
    (hsym `$historyPath) 0: (lines 0;lines 1;-1 _ lines 1;lines 3);
    (first .tst.splitFlakeHistoryLines read0 hsym `$historyPath) musteq 0b;
  };

  should["cut carried entries down when the window is made shorter"]{
    `.tst.app.flakeWindow mock 5j;
    do[4;runOnly[idB;"test_b.q"]];
    (count (.tst.flakeStateEntry[.tst.readFlakeHistoryAt historyPath;idB])`observations) musteq 4;
    `.tst.app.flakeWindow mock 2j;
    runOnly[idA;"test_a.q"];
    (count (.tst.flakeStateEntry[.tst.readFlakeHistoryAt historyPath;idB])`observations) musteq 2;
  };

  should["read a test's file and last observation from where they stand in the line"]{
    entry:.tst.quarantineTest.placedEntry[idA;"tests/dir with space/test_a.q";"2026-11-01T10:00:00.000000000Z"];
    line:.tst.flakeEntryLine entry;
    (.tst.flakeLineId line) musteq idA;
    (.tst.flakeLineFile[line;idA]) musteq "tests/dir with space/test_a.q";
    (.tst.flakeLineLastObserved line) musteq 2026.11.01D10:00:00.000000000;
    / a path that JSON has to escape is read from the parsed entry instead
    odd:.tst.flakeEntryLine .tst.quarantineTest.placedEntry[idA;"tests/a\"b.q";"2026-11-01T10:00:00Z"];
    (.tst.flakeLineFile[odd;idA]) musteq "tests/a\"b.q";
    / and a line and its entry are the same thing
    back:.tst.flakeLineEntry line;
    (back`file) musteq "tests/dir with space/test_a.q";
    (back`unseenCompleteRuns) musteq 0j;
    (.tst.flakeEntryLine back) musteq line;
  };
 };

