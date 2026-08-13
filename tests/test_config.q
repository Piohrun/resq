.tst.desc["Configuration File Support"]{
 after{
  @[hdel; hsym `$":test_config.json"; {}];
  @[hdel; hsym `$":test_config_directory.json"; {}];
  };

 should["load default config when file does not exist"]{
  cfg: .tst.loadConfig["nonexistent.json"];
  cfg[`fmt] musteq `text;
  cfg[`exit] musteq 1b;
 cfg[`pollutionGuard] musteq 1b;
 cfg[`fuzzLimit] musteq 100;
  cfg[`qNamespaceExports] musteq 0b;
  cfg[`expectationLineAnnotations] musteq 1b;
  cfg[`coverageMin] musteq 0;
  cfg[`covBranches] musteq 0b;
  cfg[`coverageBranchMin] musteq 0;
  cfg[`coverageBranchCompletenessMin] musteq 0;
  cfg[`covContexts] musteq 0b;
  cfg[`covAttemptContexts] musteq 0b;
  cfg[`coverageContextMax] musteq 10000j;
  cfg[`coverageContextEntryMax] musteq 250000j;
  cfg[`coverageSources] mustmatch ();
  cfg[`randomOrder] musteq 0b;
  cfg[`seed] musteq 0j;
  cfg[`lastFailed] musteq 0b;
  cfg[`failedFirst] musteq 0b;
  cfg[`stateFile] musteq ".resq/last-run.json";
  cfg[`shardIndex] musteq 0j;
  cfg[`shardCount] musteq 1j;
  cfg[`shardUnit] musteq `file;
  cfg[`strictPlugins] musteq 0b;
  cfg[`pluginFiles] mustmatch ();
  };

 should["accept but ignore the deprecated qNamespaceExports switch"]{
  qKeysBefore:key `.q;
  qValuesBefore:{get .Q.dd[`.q;x]} each qKeysBefore;
  .tst.setQNamespaceExports 1b;
  qKeysAfter:key `.q;
  qValuesAfter:{get .Q.dd[`.q;x]} each qKeysAfter;
  .tst.qNamespaceExports musteq 0b;
  must[(qKeysBefore~qKeysAfter) and qValuesBefore~qValuesAfter;
       "the deprecated switch must leave .q byte-for-byte equivalent"];
  };

 should["apply the expectation-line annotation kill switch"]{
  previous: @[get;`.tst.app.expectationLineAnnotations;1b];
  .tst.applyConfig enlist[`expectationLineAnnotations]!enlist 0b;
  applied: .tst.app.expectationLineAnnotations;
  .tst.app.expectationLineAnnotations: previous;
  applied musteq 0b;
  };
 should["validate and apply replayable ordering settings"]{
  warnings:.tst.validateConfig `randomOrder`seed!(1b;42j);
  warnings mustmatch ();
  previousOrder:.tst.app.randomOrder;
  previousSeed:.tst.app.executionSeed;
  .tst.applyConfig `randomOrder`seed!(1b;42j);
  appliedOrder:.tst.app.randomOrder;
  appliedSeed:.tst.app.executionSeed;
  .tst.app.randomOrder:previousOrder;
  .tst.app.executionSeed:previousSeed;
  appliedOrder musteq 1b;
  appliedSeed musteq 42j;
  badWarnings:.tst.validateConfig (enlist `seed)!enlist -1;
  must[any badWarnings like "seed must be >= 0*";"negative seeds must be rejected"];
  };
 should["validate rerun selection settings"]{
  warnings:.tst.validateConfig `lastFailed`failedFirst`stateFile!(1b;0b;"cache/state.json");
  warnings mustmatch ();
  conflict:.tst.invalidConfigKeys `lastFailed`failedFirst!(1b;1b);
  `lastFailed`failedFirst mustin conflict;
  emptyPath:.tst.invalidConfigKeys (enlist `stateFile)!enlist "";
  emptyPath musteq enlist `stateFile;
  };
 should["validate native shard bounds"]{
  warnings:.tst.validateConfig `shardIndex`shardCount`shardUnit!(1j;3j;`case);
  warnings mustmatch ();
  badCount:.tst.invalidConfigKeys (enlist `shardCount)!enlist 0;
  badCount musteq enlist `shardCount;
  badIndex:.tst.invalidConfigKeys `shardIndex`shardCount!(3;3);
  `shardIndex`shardCount mustin badIndex;
  .tst.invalidConfigKeys[(enlist `shardUnit)!enlist `process]
      musteq enlist `shardUnit;
  previousUnit:.tst.app.shardUnit;
  .tst.applyConfig (enlist `shardUnit)!enlist `test;
  .tst.app.shardUnit musteq `test;
  .tst.app.shardUnit:previousUnit;
  };
 should["validate and apply trusted plugin settings"]{
  cfg:`strictPlugins`pluginFiles!(1b;("plugins/a.q";"plugins/b.q"));
  .tst.validateConfig[cfg] mustmatch ();
  previousStrict:.tst.app.strictPlugins;
  previousFiles:.tst.app.pluginFiles;
  .tst.applyConfig cfg;
  appliedStrict:.tst.app.strictPlugins;
  appliedFiles:.tst.app.pluginFiles;
  .tst.app.strictPlugins:previousStrict;
  .tst.app.pluginFiles:previousFiles;
  appliedStrict musteq 1b;
  appliedFiles musteq ("plugins/a.q";"plugins/b.q");
  .tst.invalidConfigKeys[(enlist `strictPlugins)!enlist "yes"] musteq enlist `strictPlugins;
  .tst.invalidConfigKeys[(enlist `pluginFiles)!enlist 42] musteq enlist `pluginFiles;
  };
 should["validate and apply branch coverage settings without enabling zero defaults"]{
  previousMode:@[get;`.tst.coverageBranches;0b];
  previousMin:@[get;`.tst.app.coverageBranchMin;0];
  previousCompleteness:@[get;`.tst.app.coverageBranchCompletenessMin;0];
  .tst.coverageBranches:0b;
  .tst.applyConfig `covBranches`coverageBranchMin`coverageBranchCompletenessMin!(
      0b;0;0);
  .tst.coverageBranches musteq 0b;
  cfg:`covBranches`coverageBranchMin`coverageBranchCompletenessMin!(1b;75;90);
  .tst.validateConfig[cfg] mustmatch ();
  .tst.applyConfig cfg;
  .tst.coverageBranches musteq 1b;
  .tst.app.coverageBranchMin musteq 75;
  .tst.app.coverageBranchCompletenessMin musteq 90;
  .tst.coverageBranches:previousMode;
  .tst.app.coverageBranchMin:previousMin;
  .tst.app.coverageBranchCompletenessMin:previousCompleteness;
  .tst.invalidConfigKeys[(enlist `covBranches)!enlist "yes"]
      musteq enlist `covBranches;
  must[all `coverageBranchMin`coverageBranchCompletenessMin in
      .tst.invalidConfigKeys `coverageBranchMin`coverageBranchCompletenessMin!(101;-1);
      "branch coverage percentages must stay in 0..100"];
  };
 should["validate and apply bounded coverage context settings"]{
  previousContexts:@[get;`.tst.coverageContexts;0b];
  previousAttempts:@[get;`.tst.coverageAttemptContexts;0b];
  previousMax:@[get;`.tst.coverageContextMax;10000j];
  previousEntryMax:@[get;`.tst.coverageContextEntryMax;250000j];
  cfg:`covContexts`covAttemptContexts`coverageContextMax`coverageContextEntryMax!(
      0b;1b;25j;500j);
  .tst.validateConfig[cfg] mustmatch ();
  .tst.applyConfig cfg;
  .tst.coverageContexts musteq 1b;
  .tst.coverageAttemptContexts musteq 1b;
  .tst.coverageContextMax musteq 25j;
  .tst.coverageContextEntryMax musteq 500j;
  .tst.coverageContexts:previousContexts;
  .tst.coverageAttemptContexts:previousAttempts;
  .tst.coverageContextMax:previousMax;
  .tst.coverageContextEntryMax:previousEntryMax;
  must[all `coverageContextMax`coverageContextEntryMax in
      .tst.invalidConfigKeys `coverageContextMax`coverageContextEntryMax!(0;-1);
      "coverage context limits must be positive"];
  .tst.invalidConfigKeys[(enlist `covContexts)!enlist "yes"]
      musteq enlist `covContexts;
  };
 should["load and parse JSON config file"]{
  / Create test config file
  testCfg: "{ \"fmt\": \"junit\", \"exit\": true, \"failFast\": true }";
  hsym[`$":test_config.json"] 0: enlist testCfg;
  
  cfg: .tst.loadConfig["test_config.json"];
  cfg[`fmt] musteq `junit;
  cfg[`exit] musteq 1b;
  cfg[`failFast] musteq 1b;
  };
 should["normalize supported format aliases in config"]{
  testCfg: "{ \"fmt\": \"XML\", \"fuzzLimit\": 5 }";
  hsym[`$":test_config.json"] 0: enlist testCfg;
  
  cfg: .tst.loadConfig["test_config.json"];
  cfg[`fmt] musteq `junit;
  };
 should["warn for unsupported format"]{
  warnings: .tst.validateConfig `fmt`maxTestTime!(`unknown; 10);
  must[0 < count warnings; "an unknown format must produce a warning"];
  must[0 < count warnings where warnings like "Unsupported format*";
       "the warning must name the unsupported format"];
  };
 should["warn for non-text format type"]{
  warnings: .tst.validateConfig `fmt!5;
  must[0 < count warnings; "a non-text format must produce a warning"];
  must[0 < count warnings where warnings like "Unsupported format*";
       "the warning must name the unsupported format"];
  };
 should["warn for non-boolean pollution guard"]{
  warnings: .tst.validateConfig `pollutionGuard!5;
  must[0 < count warnings; "a non-boolean pollutionGuard must produce a warning"];
  must[0 < count warnings where warnings like "pollutionGuard must be a boolean";
       "the warning must name the pollutionGuard type requirement"];
  };
 should["merge config with defaults"]{
  testCfg: "{ \"fmt\": \"xunit\" }";
  hsym[`$":test_config.json"] 0: enlist testCfg;

  cfg: .tst.loadConfig["test_config.json"];
  cfg[`fmt] musteq `xunit;
  cfg[`fuzzLimit] musteq 100;
  };
 should["expose diff-table thresholds with sensible defaults"]{
  cfg: .tst.loadConfig["nonexistent.json"];
  cfg[`diffLargeTableThreshold] musteq 1000;
  cfg[`diffHugeTableThreshold] musteq 10000;
  };
 should["validate and apply report evidence profiles"]{
  .tst.validateConfig[(enlist `reportProfile)!enlist `telemetry] mustmatch ();
  must[`reportProfile in .tst.invalidConfigKeys `reportProfile`shardCount!(`results;2j);
    "multi-shard configuration must reject compact evidence"];
  must[`reportProfile in .tst.invalidConfigKeys (enlist `reportProfile)!enlist `tiny;
    "unknown report profiles must be invalid"];
  previous:@[get;`.tst.app.reportProfile;`full];
  .tst.applyConfig[(enlist `reportProfile)!enlist `results];
  applied:.tst.app.reportProfile;
  .tst.app.reportProfile:previous;
  applied musteq `results;
  };
 should["validate, normalize, and apply run labels and VCS policy"]{
  labels:`service`environment!("orders";"prod");
  cfg:`labels`vcsProbe!(labels;0b);
  .tst.validateConfig[cfg] mustmatch ();
  previousLabels:.tst.app.labels;
  previousProbe:.tst.app.vcsProbe;
  .tst.app.labels:()!();
  .tst.applyConfig cfg;
  appliedLabels:.tst.app.labels;
  appliedProbe:.tst.app.vcsProbe;
  .tst.app.labels:previousLabels;
  .tst.app.vcsProbe:previousProbe;
  key[appliedLabels] musteq `environment`service;
  appliedLabels[`service] musteq "orders";
  appliedProbe musteq 0b;
  .tst.invalidConfigKeys[(enlist `labels)!enlist ((enlist `service)!enlist 42)]
      musteq enlist `labels;
  .tst.invalidConfigKeys[(enlist `vcsProbe)!enlist "no"]
      musteq enlist `vcsProbe;
  };
 should["warn if diff-table thresholds are non-integer"]{
  / Build the dict explicitly: shorthand `key!`sym is parsed as enum, not dict.
  warnings: .tst.validateConfig (enlist `diffLargeTableThreshold)!enlist 1.5;
  must[0 < count warnings where warnings like "diffLargeTableThreshold must be an integer*";
       "a non-integer diffLargeTableThreshold must warn and say it must be an integer"];
  };
 should["apply config to global settings"]{
  prevFmt: .resq.config.fmt;
  prevExit: .tst.app.exit;
  prevFailFast: .tst.app.failFast;
  prevGuard: .tst.app.pollutionGuard;
  testCfg: `fmt`exit`failFast`pollutionGuard!(`console; 1b; 1b; 0b);
  .tst.applyConfig[testCfg];
  
  appliedFmt: .resq.config.fmt;
  appliedExit: .tst.app.exit;
  appliedFailFast: .tst.app.failFast;
  appliedGuard: .tst.app.pollutionGuard;
  .resq.config.fmt: prevFmt;
  .tst.app.exit: prevExit;
  .tst.app.failFast: prevFailFast;
  .tst.app.pollutionGuard: prevGuard;
  appliedFmt musteq `console;
  appliedExit musteq 1b;
  appliedFailFast musteq 1b;
  appliedGuard musteq 0b;
  };

 / --- Bug 1: validation is authoritative; applyConfig skips invalid keys ---

 should["flag a bad-boolean key as invalid"]{
  .tst.invalidConfigKeys[(enlist `exit)!enlist "yes"] musteq enlist `exit;
  };
 should["flag a null-coerced integer key as invalid"]{
  / loadConfig's "I"$"abc" yields 0Ni; a null int must be rejected, not applied.
  .tst.invalidConfigKeys[(enlist `fuzzLimit)!enlist 0Ni] musteq enlist `fuzzLimit;
  };
 should["flag an unknown key as invalid"]{
  .tst.invalidConfigKeys[(enlist `bogusKey)!enlist 1] musteq enlist `bogusKey;
  };
 should["report no invalid keys for a good config"]{
  0 musteq count .tst.invalidConfigKeys `exit`fuzzLimit`fmt!(1b; 7i; `junit);
  };

 should["NOT apply a bad-boolean value (default preserved)"]{
  prevExit: .tst.app.exit;
  .tst.app.exit: 0b;
  .tst.applyConfig[(enlist `exit)!enlist "yes"];
  applied: .tst.app.exit;
  .tst.app.exit: prevExit;
  applied musteq 0b;
  };
 should["NOT apply a null integer value (default preserved)"]{
  prevFuzz: .tst.output.fuzzLimit;
  .tst.output.fuzzLimit: 100;
  .tst.applyConfig[(enlist `fuzzLimit)!enlist 0Ni];
  applied: .tst.output.fuzzLimit;
  .tst.output.fuzzLimit: prevFuzz;
  applied musteq 100;
  };
 should["apply good keys even when a sibling key is invalid"]{
  prevExit: .tst.app.exit;
  prevFuzz: .tst.output.fuzzLimit;
  .tst.app.exit: 0b;
  .tst.output.fuzzLimit: 100;
  / `exit is bad ("yes"); `fuzzLimit is good (7i) and must still apply.
  .tst.applyConfig[`exit`fuzzLimit!("yes"; 7i)];
  appliedExit: .tst.app.exit;
  appliedFuzz: .tst.output.fuzzLimit;
  .tst.app.exit: prevExit;
  .tst.output.fuzzLimit: prevFuzz;
  appliedExit musteq 0b;
  appliedFuzz musteq 7i;
  };
 should["produce a validation warning for a bad-boolean key"]{
  warnings: .tst.validateConfig (enlist `exit)!enlist "yes";
  0 mustlt count warnings where warnings like "exit must be a boolean*";
  };

 / --- Bug 4: insane-but-typed numeric values are range-checked ---

 should["flag a negative fuzzLimit as invalid"]{
  / fuzzLimit:-5 is correctly typed (a long) but nonsensical; must be rejected.
  .tst.invalidConfigKeys[(enlist `fuzzLimit)!enlist -5] musteq enlist `fuzzLimit;
  };
 should["flag a negative maxTestTime as invalid"]{
  .tst.invalidConfigKeys[(enlist `maxTestTime)!enlist -1] musteq enlist `maxTestTime;
  };
 should["accept a zero numeric value (boundary)"]{
  0 musteq count .tst.invalidConfigKeys (enlist `fuzzLimit)!enlist 0;
  };
 should["validate and apply a coverage minimum between zero and one hundred"]{
  0 musteq count .tst.invalidConfigKeys (enlist `coverageMin)!enlist 100;
  .tst.invalidConfigKeys[(enlist `coverageMin)!enlist 101] musteq enlist `coverageMin;
  warnings: .tst.validateConfig (enlist `coverageMin)!enlist 101;
  must[any warnings like "coverageMin must be between 0 and 100*";
       "an out-of-range coverage minimum must warn"];
  previous: @[get; `.tst.app.coverageMin; 0];
  .tst.applyConfig[(enlist `coverageMin)!enlist 87];
  applied: .tst.app.coverageMin;
  .tst.app.coverageMin: previous;
  applied musteq 87;
  };
 should["validate and apply independent coverage thresholds"]{
  cfg:`coverageFunctionMin`coverageLineMin`coverageCompletenessMin`allowPartialLineCoverage!(
      81;72;93;1b);
  0 musteq count .tst.invalidConfigKeys cfg;
  priorState:(@[get;`.tst.app.coverageFunctionMin;0];
        @[get;`.tst.app.coverageLineMin;0];
        @[get;`.tst.app.coverageCompletenessMin;0];
        @[get;`.tst.app.allowPartialLineCoverage;0b]);
  .tst.applyConfig cfg;
  applied:(.tst.app.coverageFunctionMin;.tst.app.coverageLineMin;
           .tst.app.coverageCompletenessMin;.tst.app.allowPartialLineCoverage);
  .tst.app.coverageFunctionMin:priorState 0;
  .tst.app.coverageLineMin:priorState 1;
  .tst.app.coverageCompletenessMin:priorState 2;
  .tst.app.allowPartialLineCoverage:priorState 3;
  applied mustmatch (81;72;93;1b);
  };
 should["reject out-of-range independent coverage thresholds"]{
  names:`coverageFunctionMin`coverageLineMin`coverageCompletenessMin;
  { [n]
    cfg:(enlist n)!enlist 101;
    .tst.invalidConfigKeys[cfg] musteq enlist n;
    must[any .tst.validateConfig[cfg] like string[n]," must be between 0 and 100*";
         "each independent coverage threshold must be range checked"]
  } each names;
  };
 should["validate, normalize, and apply coverage source roots"]{
  good:("src";`shared);
  0 musteq count .tst.invalidConfigKeys (enlist `coverageSources)!enlist good;
  previous:@[get;`.tst.app.coverageSources;{()}];
  .tst.applyConfig[(enlist `coverageSources)!enlist good];
  applied:.tst.app.coverageSources;
  .tst.app.coverageSources:previous;
  applied mustmatch ("src";"shared");
  };
 should["reject malformed coverage source roots"]{
  cfg:(enlist `coverageSources)!enlist ("src";42);
  .tst.invalidConfigKeys[cfg] musteq enlist `coverageSources;
  warnings:.tst.validateConfig cfg;
  must[any warnings like "coverageSources must be*";
       "malformed coverageSources must produce a config warning"];
  };
 should["warn for a negative fuzzLimit"]{
  warnings: .tst.validateConfig (enlist `fuzzLimit)!enlist -5;
  0 mustlt count warnings where warnings like "fuzzLimit must be >= 0*";
  };
 should["NOT apply a negative fuzzLimit (default preserved)"]{
  prevFuzz: .tst.output.fuzzLimit;
  .tst.output.fuzzLimit: 100;
  .tst.applyConfig[(enlist `fuzzLimit)!enlist -5];
  applied: .tst.output.fuzzLimit;
  .tst.output.fuzzLimit: prevFuzz;
  applied musteq 100;
  };

 should["apply only a boolean runPerformance setting"]{
  prevPerf:.tst.app.runPerformance;
  .tst.app.runPerformance:0b;
  .tst.applyConfig[(enlist `runPerformance)!enlist 1b];
  appliedGood:.tst.app.runPerformance;
  .tst.applyConfig[(enlist `runPerformance)!enlist "yes"];
  appliedBad:.tst.app.runPerformance;
  .tst.app.runPerformance:prevPerf;
  appliedGood musteq 1b;
  appliedBad musteq 1b;
  };

 should["accept and normalize safe test file patterns"]{
  goodString:"*_spec.q";
  goodList:("test_*.q"; "*_test.q"; "exact.q");
  0 musteq count .tst.invalidConfigKeys (enlist `testFilePatterns)!enlist goodString;
  0 musteq count .tst.invalidConfigKeys (enlist `testFilePatterns)!enlist goodList;

  prevPatterns:@[get; `.resq.config.testFilePatterns; {()}];
  .tst.applyConfig[(enlist `testFilePatterns)!enlist goodString];
  applied:.resq.config.testFilePatterns;
  .resq.config.testFilePatterns:prevPatterns;
  applied mustmatch enlist goodString;
  };

 should["warn and reject unsafe test file patterns"]{
  badPatterns:(
    "";
    ();
    42;
    `test;
    ("test_*.q"; "");
    enlist "nested/test_*.q";
    enlist "nested\\test_*.q";
    enlist "test_*_*.q";
    enlist "control\001.q");
  {
    cfg:(enlist `testFilePatterns)!enlist x;
    .tst.invalidConfigKeys[cfg] musteq enlist `testFilePatterns;
    warnings:.tst.validateConfig cfg;
    must[any warnings like "testFilePatterns must be*";
         "invalid testFilePatterns must produce a config warning"];
    } each badPatterns;
  };

 should["retain existing test file patterns after invalid config"]{
  prevPatterns:@[get; `.resq.config.testFilePatterns; {()}];
  expected:("test_*.q"; "*_test.q");
  .resq.config.testFilePatterns:expected;
  .tst.applyConfig[(enlist `testFilePatterns)!enlist 42];
  applied:.resq.config.testFilePatterns;
  .resq.config.testFilePatterns:prevPatterns;
  applied mustmatch expected;
  };

 should["normalize JSON testFilePatterns strings and lists"]{
  singleJson:"{ \"testFilePatterns\": \"*_spec.q\" }";
  hsym[`$":test_config.json"] 0: enlist singleJson;
  single:.tst.loadConfig "test_config.json";

  listJson:"{ \"testFilePatterns\": [\"test_*.q\", \"*_test.q\"] }";
  hsym[`$":test_config.json"] 0: enlist listJson;
  listed:.tst.loadConfig "test_config.json";

  single[`testFilePatterns] mustmatch enlist "*_spec.q";
  listed[`testFilePatterns] mustmatch ("test_*.q"; "*_test.q");
  };

 should["reject integer vectors and infinities as config scalars"]{
  badValues:(1 2; 0W; -0W);
  {
    cfg:(enlist `reportLimit)!enlist x;
    .tst.invalidConfigKeys[cfg] musteq enlist `reportLimit;
    } each badValues;
  };

 should["fail soft on malformed config roots"]{
  prevPerf:.tst.app.runPerformance;
  .tst.app.runPerformance:0b;
  mustnotthrow[();(.tst.applyConfig;42)];
  applied:.tst.app.runPerformance;

  hsym[`$":test_config.json"] 0:enlist "[1, 2]";
  loaded:.tst.loadConfig "test_config.json";
  .tst.app.runPerformance:prevPerf;

  applied musteq 0b;
  loaded[`testFilePatterns] mustmatch .tst.defaultConfig`testFilePatterns;
  };

 should["use defaults when the config path is a directory"]{
  path:"test_config_directory.json";
  .utl.ensureDir path;
  cfg:.tst.loadConfig path;
  @[hdel;hsym `$path;{}];

  cfg[`runPerformance] musteq .tst.defaultConfig`runPerformance;
  cfg[`testFilePatterns] mustmatch .tst.defaultConfig`testFilePatterns;
  };

 should["use defaults when reading an existing config fails"]{
  hsym[`$":test_config.json"] 0:enlist "{\"runPerformance\":true}";
  `.tst.readConfigLines mock {[handle] '"simulated config read failure"};
  cfg:.tst.loadConfig "test_config.json";

  cfg[`runPerformance] musteq .tst.defaultConfig`runPerformance;
  cfg[`testFilePatterns] mustmatch .tst.defaultConfig`testFilePatterns;
  };
 };

::
