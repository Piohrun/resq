\d .tst

/ Configuration file support
/ Loads settings from resq.json at project root

/ Default configuration
defaultConfig:`fmt`outDir`describeOnly`xmlOutput`runPerformance`excludeSpecs`runSpecs`passOnly`exit`strict`fuzzLimit`failFast`failHard`pollutionGuard`maxTestTime`reportLimit`reportListLimit`qNamespaceExports`expectationLineAnnotations`diffLargeTableThreshold`diffHugeTableThreshold`testFilePatterns`qspecCompat`covStatements`coverageMin`coverageFunctionMin`coverageLineMin`coverageCompletenessMin`allowPartialLineCoverage`coverageSources`randomOrder`seed`lastFailed`failedFirst`stateFile`shardIndex`shardCount`strictPlugins`pluginFiles`covBranches`coverageBranchMin`coverageBranchCompletenessMin`covContexts`covAttemptContexts`coverageContextMax`coverageContextEntryMax`shardUnit`quarantineNonBlocking`flakeProposals`flakeHistoryFile`quarantineFile`flakeProposalFile`flakeEvidenceMin`flakeFailureMin`flakeWindow`snapshotAudit`snapshotGate`benchmarkBaseline`benchmarkGate`benchmarkAcceptEnvironment`benchmarkAlphaPercent`benchmarkEffectMin`benchmarkMinSamples`reportProfile`labels`vcsProbe!(`text;".";0b;0b;0b;();();0b;1b;0b;100;0b;0b;1b;0;50000;1000;0b;1b;1000;10000;("test_*.q"; "*_test.q");0b;0b;0;0;0;0;0b;();0b;0j;0b;0b;".resq/last-run.json";0j;1j;0b;();0b;0;0;0b;0b;10000j;250000j;`file;0b;0b;".resq/flake-history.json";".resq/quarantine.json";".resq/quarantine-proposals.json";3j;2j;20j;0b;0b;"";0b;0b;5j;5j;5j;`full;()!();1b)

.tst.LABEL_MAX_COUNT:32j;
.tst.LABEL_MAX_KEY:64j;
.tst.LABEL_MAX_VALUE:256j;
.tst.LABEL_MAX_TOTAL:4096j;
.tst.standardLabelKeys:("environment";"service";"deploymentId";"artifactDigest";
    "cluster";"region";"hostGroup");

.tst.labelSkipWhitespace:{[text;start]
    i:start;
    while[(i<count text) and text[i] in " \t\r\n";i+:1];
    i
 };

.tst.labelScanString:{[text;start;allowEscapes]
    if[(start>=count text) or not "\""=text start;
        :`ok`error`next`value!(0b;"expected JSON string";start;"")];
    i:start+1;escaped:0b;
    while[i<count text;
        ch:text i;
        wasEscaped:escaped;
        if[wasEscaped;escaped:0b;i+:1];
        if[not wasEscaped;
            if[ch="\\";
                if[not allowEscapes;
                    :`ok`error`next`value!(0b;"label keys must not contain JSON escapes";i;"")];
                escaped:1b;i+:1];
            if[(not escaped) and ch="\"";
                :`ok`error`next`value!(1b;"";i+1;(i-(start+1))#(start+1)_text)];
            if[(not escaped) and ("i"$ch)<32;
                :`ok`error`next`value!(0b;"label strings must not contain control characters";i;"")];
            if[not escaped;i+:1]
        ];
    ];
    `ok`error`next`value!(0b;"unterminated JSON string";i;"")
 };

.tst.validLabelKey:{[keyText]
    if[not 10h=type keyText;:0b];
    if[(0=count keyText) or count[keyText]>.tst.LABEL_MAX_KEY;:0b];
    letters:"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
    allowed:letters,"0123456789_.-";
    if[not first[keyText] in letters;:0b];
    if[not all keyText in allowed;:0b];
    if[(keyText like "resq.*") or (keyText like "vcs.*") or
       (keyText like "ci.*") or keyText like "__*";:0b];
    1b
 };

/ Lexically validate the flat string-to-string JSON object before .j.k can
/ intern object keys. Invalid/oversized hostile input therefore causes no
/ symbol-table growth; only at most 32 already-valid keys reach the decoder.
.tst.preflightLabelJson:{[raw]
    text:.tst.toString raw;
    fail:{[message] `ok`error`labelKeys!(0b;message;())};
    if[count[text]>.tst.LABEL_MAX_TOTAL;:fail "labels JSON exceeds 4096 bytes"];
    i:.tst.labelSkipWhitespace[text;0];
    if[(i>=count text) or not "{"=text i;:fail "labels must be a JSON object"];
    i:.tst.labelSkipWhitespace[text;i+1];
    labelKeys:();
    if[(i<count text) and "}"=text i;
        i:.tst.labelSkipWhitespace[text;i+1];
        if[i=count text;:`ok`error`labelKeys!(1b;"";labelKeys)]];
    while[i<count text;
        scanned:.tst.labelScanString[text;i;0b];
        if[not scanned`ok;:fail scanned`error];
        keyText:scanned`value;
        if[not .tst.validLabelKey keyText;
            :fail "invalid label key: ",keyText];
        if[any keyText~/:labelKeys;:fail "duplicate label key: ",keyText];
        labelKeys,:enlist keyText;
        if[count[labelKeys]>.tst.LABEL_MAX_COUNT;:fail "labels exceed maximum count 32"];
        i:.tst.labelSkipWhitespace[text;scanned`next];
        if[(i>=count text) or not ":"=text i;:fail "expected ':' after label key"];
        i:.tst.labelSkipWhitespace[text;i+1];
        scanned:.tst.labelScanString[text;i;1b];
        if[not scanned`ok;:fail "label values must be JSON strings"];
        i:.tst.labelSkipWhitespace[text;scanned`next];
        if[i>=count text;:fail "unterminated labels object"];
        delimiter:text i;
        if[","=delimiter;i:.tst.labelSkipWhitespace[text;i+1]];
        if["}"=delimiter;
            i:.tst.labelSkipWhitespace[text;i+1];
            if[not i=count text;:fail "unexpected content after labels object"];
            :`ok`error`labelKeys!(1b;"";labelKeys)];
        if[not delimiter in ",}";:fail "expected ',' or '}' after label value"];
    ];
    fail "unterminated labels object"
 };

.tst.validLabels:{[labels]
    if[not 99h=type labels;:0b];
    if[0=count labels;:1b];
    names:.tst.toString each key labels;
    if[count[names]>.tst.LABEL_MAX_COUNT;:0b];
    if[not all .tst.validLabelKey each names;:0b];
    vals:{[d;k]d k}[labels;] each key labels;
    if[not all 10h=type each vals;:0b];
    if[any (count each vals)>.tst.LABEL_MAX_VALUE;:0b];
    ((sum (count each names))+(sum (count each vals)))<=.tst.LABEL_MAX_TOTAL
 };

.tst.normalizeLabels:{[labels]
    if[not .tst.validLabels labels;:()!()];
    order:iasc .tst.toString each key labels;
    (key[labels] order)!value[labels] order
 };

.tst.parseLabelJson:{[raw]
    checked:.tst.preflightLabelJson raw;
    if[not checked`ok;:`ok`error`labels!(0b;checked`error;()!())];
    decoded:@[{[text](0b;.j.k text)};.tst.toString raw;{[err](1b;err)}];
    if[first decoded;:`ok`error`labels!(0b;"invalid labels JSON: ",.tst.toString last decoded;()!())];
    labels:last decoded;
    if[not .tst.validLabels labels;
        :`ok`error`labels!(0b;"labels require at most 32 string values of at most 256 bytes";()!())];
    `ok`error`labels!(1b;"";.tst.normalizeLabels labels)
 };

.tst.mergeLabels:{[base;overlay]
    left:$[.tst.validLabels base;base;()!()];
    right:$[.tst.validLabels overlay;overlay;()!()];
    .tst.normalizeLabels left,right
 };

.tst.applyEnvironmentLabels:{[]
    raw:getenv `RESQ_LABELS_JSON;
    if[0=count raw;:""];
    parsed:.tst.parseLabelJson raw;
    if[not parsed`ok;:parsed`error];
    .tst.app.labels:.tst.mergeLabels[.tst.app.labels;parsed`labels];
    ""
 };

.tst.readConfigLines:{[handle] read0 handle};

/ Inspect and read as one trapped operation. `key` distinguishes a regular file
/ (hsym atom), directory (symbol list), and a missing path (empty general list).
.tst.readConfigSource:{[handle]
    info:key handle;
    if[()~info; :`state`value!(`missing;())];
    if[11h=type info;
        :`state`value!(`error;"path is a directory, not a regular file")];
    if[not -11h=type info;
        :`state`value!(`error;"path is not a regular file")];
    lines:.tst.readConfigLines handle;
    if[not 0h=type lines;
        :`state`value!(`error;"config reader returned a malformed value")];
    if[not all 10h=type each lines;
        :`state`value!(`error;"config reader returned non-text content")];
    `state`value!(`ok;lines)
 };

/ Load configuration from JSON file
/ @param path (string) Path to config file (default: "resq.json")
/ @return (dict) Configuration dictionary
loadConfig:{[path]
    p:$[10h = type path; path; "resq.json"];
    source:@[.tst.readConfigSource;hsym `$p;{[e]
        `state`value!(`error;e)
    }];
    if[`missing~source`state; :.tst.defaultConfig];
    if[`error~source`state;
        -1 "WARNING: Failed to read config '",p,"': ",
            .tst.toString[source`value],"; using defaults";
        :.tst.defaultConfig
    ];
    cfgText:"\n" sv source`value;

    cfg:()!();
    if[0 < count cfgText;
        cfg: @[.j.k; cfgText; {[e]
            -1 "WARNING: Failed to parse config JSON: ", e;
            ()!()
        }];
    ];
    if[not 99h=type cfg;
        -1 "WARNING: Config JSON root must be an object; using defaults";
        cfg:()!()
    ];

    merged:$[0 < count cfg; .tst.defaultConfig, cfg; .tst.defaultConfig];

    if[10h = type merged`excludeSpecs;
        merged[`excludeSpecs]: `$"," vs merged`excludeSpecs
    ];
    if[10h = type merged`runSpecs;
        merged[`runSpecs]: `$"," vs merged`runSpecs
    ];
    if[`fmt in key merged;
        merged[`fmt]: .tst.normalizeFmt merged`fmt
    ];
    if[10h = type merged`fuzzLimit;
        merged[`fuzzLimit]: "I"$merged`fuzzLimit
    ];
    if[10h = type merged`maxTestTime;
        merged[`maxTestTime]: "I"$merged`maxTestTime
    ];
    if[10h = type merged`reportLimit;
        merged[`reportLimit]: "I"$merged`reportLimit
    ];
    if[10h = type merged`reportListLimit;
        merged[`reportListLimit]: "I"$merged`reportListLimit
    ];
    if[10h = type merged`seed;
        merged[`seed]: "J"$merged`seed
    ];
    if[10h = type merged`shardIndex;merged[`shardIndex]:"J"$merged`shardIndex];
    if[10h = type merged`shardCount;merged[`shardCount]:"J"$merged`shardCount];
    if[10h=type merged`shardUnit;merged[`shardUnit]:`$lower merged`shardUnit];
    if[10h=type merged`reportProfile;merged[`reportProfile]:`$lower merged`reportProfile];
    coveragePercentKeys:`coverageMin`coverageFunctionMin`coverageLineMin`coverageCompletenessMin`coverageBranchMin`coverageBranchCompletenessMin`coverageContextMax`coverageContextEntryMax`flakeEvidenceMin`flakeFailureMin`flakeWindow`benchmarkAlphaPercent`benchmarkEffectMin`benchmarkMinSamples;
    {[cfg;k] if[10h=type cfg k;cfg[k]:"I"$cfg k]}[merged;] each coveragePercentKeys;
    if[`testFilePatterns in key merged;
        if[.tst.validTestFilePatterns merged`testFilePatterns;
            merged[`testFilePatterns]:.tst.normalizeTestFilePatterns merged`testFilePatterns
        ];
    ];

    merged
 }

.tst.normalizeFmtInput:{[fmt]
    $[10h = type fmt; `$lower fmt;
      -11h = type fmt; `$lower string fmt;
      11h = type fmt; `$lower string first fmt;
      0h = type fmt; `text;
      `$lower string fmt]
 }

.tst.normalizeFmt:{[fmt]
    rawFmt: .tst.normalizeFmtInput fmt;
    $[rawFmt ~ `console; `text;
      rawFmt ~ `xml; `junit;
      rawFmt in (`text; `junit; `xunit; `json); rawFmt;
      `text]
 }

/ A configured test pattern must be a basename-only glob that q `like` can
/ evaluate safely. q signals 'nyi for patterns containing multiple stars.
.tst.validTestFilePattern:{[pattern]
    if[not 10h=type pattern; :0b];
    if[0=count pattern; :0b];
    if[any pattern in "/\\"; :0b];
    codes:"i"$pattern;
    if[(any 32>codes) or any 127=codes; :0b];
    if[1<count where pattern="*"; :0b];
    @[{[p] "" like p;1b};pattern;{[e] 0b}]
 };

.tst.validTestFilePatterns:{[patterns]
    if[10h=type patterns; :.tst.validTestFilePattern patterns];
    if[not 0h=type patterns; :0b];
    if[0=count patterns; :0b];
    all .tst.validTestFilePattern each patterns
 };

.tst.normalizeTestFilePatterns:{[patterns]
    $[10h=type patterns;enlist patterns;patterns]
 };

/ Coverage source roots accept one path or a list of string/symbol paths. Keep
/ them as strings so filesystem discovery never interns user-controlled text.
.tst.validCoverageSources:{[sources]
    if[10h=type sources; :0<count sources];
    if[-11h=type sources; :0<count string sources];
    if[11h=type sources; :0<count sources];
    if[not 0h=type sources; :0b];
    all {[x] ((10h=type x) or -11h=type x) and 0<count string x} each sources
 };

.tst.normalizeCoverageSources:{[sources]
    $[10h=type sources; enlist sources;
      -11h=type sources; enlist string sources;
      11h=type sources; string each sources;
      0h=type sources; {$[10h=type x;x;string x]} each sources;
      ()]
 };

/ True only for finite, non-null integer atoms accepted by config.
.tst.validConfigInteger:{[v]
    if[not (type v) in -5 -6 -7h; :0b];
    if[null v; :0b];
    if[v in (0Wh;-0Wh;0Wi;-0Wi;0W;-0W); :0b];
    1b
 };

.tst.validNonNegativeConfigInteger:{[v]
    if[not .tst.validConfigInteger v; :0b];
    0<=v
 };

/ Validate a configuration dictionary. Returns a list of warning messages
/ (empty if the config is valid).
validateConfig:{[cfg]
  if[(type cfg) in -20 20h; cfg:(enlist key cfg)!enlist value cfg];
  if[not 99h = type cfg; cfg:()!()];

  warnings:();
  knownKeys:key .tst.defaultConfig;
  unknownKeys:(key cfg) except knownKeys;
  if[0<count unknownKeys; warnings,: enlist "Unknown config keys: ", ", " sv string unknownKeys];

  cfgFmtRaw: .tst.normalizeFmtInput $[`fmt in key cfg; cfg`fmt; "text"];
  if[`fmt in key cfg;
    if[not cfgFmtRaw in `text`console`xml`junit`xunit`json;
      warnings,: enlist "Unsupported format: ", (string cfgFmtRaw), " (expected text, console, junit, xunit, or json)"
    ];
  ];

  checkType:{[cfg;name;allowed;msg]
    if[not name in key cfg; :()];
    $[(type cfg name) in allowed; (); enlist msg]
  };

  boolNames:`describeOnly`xmlOutput`runPerformance`passOnly`exit`strict`failFast`failHard`pollutionGuard`qNamespaceExports`expectationLineAnnotations`qspecCompat`covStatements`allowPartialLineCoverage`randomOrder`lastFailed`failedFirst`strictPlugins`covBranches`covContexts`covAttemptContexts`quarantineNonBlocking`flakeProposals`snapshotAudit`snapshotGate`benchmarkGate`benchmarkAcceptEnvironment`vcsProbe;
  boolMsgs:("describeOnly must be a boolean";
            "xmlOutput must be a boolean";
            "runPerformance must be a boolean";
            "passOnly must be a boolean";
            "exit must be a boolean";
            "strict must be a boolean";
            "failFast must be a boolean";
            "failHard must be a boolean";
            "pollutionGuard must be a boolean";
            "qNamespaceExports must be a boolean";
            "expectationLineAnnotations must be a boolean";
            "qspecCompat must be a boolean";
            "covStatements must be a boolean";
            "allowPartialLineCoverage must be a boolean";
            "randomOrder must be a boolean";
            "lastFailed must be a boolean";
            "failedFirst must be a boolean";
            "strictPlugins must be a boolean";
            "covBranches must be a boolean";
            "covContexts must be a boolean";
            "covAttemptContexts must be a boolean";
            "quarantineNonBlocking must be a boolean";
            "flakeProposals must be a boolean";
            "snapshotAudit must be a boolean";
            "snapshotGate must be a boolean";
            "benchmarkGate must be a boolean";
            "benchmarkAcceptEnvironment must be a boolean";
            "vcsProbe must be a boolean");
  warnings,: raze checkType[cfg;;enlist -1h;]'[boolNames; boolMsgs];

  intNames:`fuzzLimit`maxTestTime`reportLimit`reportListLimit`diffLargeTableThreshold`diffHugeTableThreshold`coverageMin`coverageFunctionMin`coverageLineMin`coverageCompletenessMin`coverageBranchMin`coverageBranchCompletenessMin`coverageContextMax`coverageContextEntryMax`seed`shardIndex`shardCount`flakeEvidenceMin`flakeFailureMin`flakeWindow`benchmarkAlphaPercent`benchmarkEffectMin`benchmarkMinSamples;
  intMsgs:("fuzzLimit must be an integer scalar";
           "maxTestTime must be an integer scalar";
           "reportLimit must be an integer scalar";
           "reportListLimit must be an integer scalar";
           "diffLargeTableThreshold must be an integer scalar";
           "diffHugeTableThreshold must be an integer scalar";
           "coverageMin must be an integer scalar";
           "coverageFunctionMin must be an integer scalar";
           "coverageLineMin must be an integer scalar";
           "coverageCompletenessMin must be an integer scalar";
           "coverageBranchMin must be an integer scalar";
           "coverageBranchCompletenessMin must be an integer scalar";
           "coverageContextMax must be an integer scalar";
           "coverageContextEntryMax must be an integer scalar";
           "seed must be an integer scalar";
           "shardIndex must be an integer scalar";
           "shardCount must be an integer scalar";
           "flakeEvidenceMin must be an integer scalar";
           "flakeFailureMin must be an integer scalar";
           "flakeWindow must be an integer scalar";
           "benchmarkAlphaPercent must be an integer scalar";
           "benchmarkEffectMin must be an integer scalar";
           "benchmarkMinSamples must be an integer scalar");
  warnings,: raze checkType[cfg;;(-5h;-6h;-7h);]'[intNames; intMsgs];

  / Range check: numeric keys must be non-negative. A correctly-typed but
  / negative value (e.g. fuzzLimit:-5, maxTestTime:-1) is nonsensical; warn and
  / let invalidConfigKeys ignore it (default retained). Only checked when the
  / value is an integer of the right type and not null.
  checkNonNeg:{[cfg;name;msg]
    if[not name in key cfg; :()];
    v: cfg name;
    if[not (type v) in -5 -6 -7h; :()];
    if[(null v) or v in (0Wh;-0Wh;0Wi;-0Wi;0W;-0W);
      :enlist string[name]," must be a finite non-null integer scalar"];
    $[v < 0; enlist msg; ()]
  };
  rangeMsgs:("fuzzLimit must be >= 0";
             "maxTestTime must be >= 0";
             "reportLimit must be >= 0";
             "reportListLimit must be >= 0";
             "diffLargeTableThreshold must be >= 0";
             "diffHugeTableThreshold must be >= 0";
             "coverageMin must be between 0 and 100";
             "coverageFunctionMin must be between 0 and 100";
             "coverageLineMin must be between 0 and 100";
             "coverageCompletenessMin must be between 0 and 100";
             "coverageBranchMin must be between 0 and 100";
             "coverageBranchCompletenessMin must be between 0 and 100";
             "coverageContextMax must be > 0";
             "coverageContextEntryMax must be > 0";
             "seed must be >= 0";
             "shardIndex must be >= 0";
             "shardCount must be > 0";
             "flakeEvidenceMin must be >= 2";
             "flakeFailureMin must be > 0";
             "flakeWindow must be >= flakeEvidenceMin";
             "benchmarkAlphaPercent must be between 1 and 100";
             "benchmarkEffectMin must be between 0 and 100";
             "benchmarkMinSamples must be >= 2");
  warnings,: raze checkNonNeg[cfg;;]'[intNames; rangeMsgs];
  if[`coverageMin in key cfg;
    if[(type cfg`coverageMin) in -5 -6 -7h;
      if[(not null cfg[`coverageMin]) and (cfg[`coverageMin] > 100);
        warnings,: enlist "coverageMin must be between 0 and 100"]]];
  percentNames:`coverageFunctionMin`coverageLineMin`coverageCompletenessMin`coverageBranchMin`coverageBranchCompletenessMin`benchmarkAlphaPercent`benchmarkEffectMin;
  checkPercentMax:{[cfg;n]
      if[not n in key cfg;:()];
      if[not (type cfg n) in -5 -6 -7h;:()];
      if[(null cfg n) or cfg[n]<=100;:()];
      enlist string[n]," must be between 0 and 100"
  };
  warnings,:raze checkPercentMax[cfg;] each percentNames;
  if[`shardCount in key cfg;
    if[(type cfg`shardCount) in -5 -6 -7h;
      if[(not null cfg`shardCount) and 1>cfg`shardCount;
        warnings,:enlist "shardCount must be > 0"]]];
  if[`coverageContextMax in key cfg;
    if[(type cfg`coverageContextMax) in -5 -6 -7h;
      if[(not null cfg`coverageContextMax) and 1>cfg`coverageContextMax;
        warnings,:enlist "coverageContextMax must be > 0"]]];
  if[`coverageContextEntryMax in key cfg;
    if[(type cfg`coverageContextEntryMax) in -5 -6 -7h;
      if[(not null cfg`coverageContextEntryMax) and 1>cfg`coverageContextEntryMax;
        warnings,:enlist "coverageContextEntryMax must be > 0"]]];
  if[`flakeEvidenceMin in key cfg;
    if[(type cfg`flakeEvidenceMin) in -5 -6 -7h;
      if[(not null cfg`flakeEvidenceMin) and 2>cfg`flakeEvidenceMin;
        warnings,:enlist "flakeEvidenceMin must be >= 2"]]];
  if[`flakeFailureMin in key cfg;
    if[(type cfg`flakeFailureMin) in -5 -6 -7h;
      if[(not null cfg`flakeFailureMin) and 1>cfg`flakeFailureMin;
        warnings,:enlist "flakeFailureMin must be > 0"]]];
  if[`benchmarkAlphaPercent in key cfg;
    if[(type cfg`benchmarkAlphaPercent) in -5 -6 -7h;
      if[(not null cfg`benchmarkAlphaPercent) and 1>cfg`benchmarkAlphaPercent;
        warnings,:enlist "benchmarkAlphaPercent must be between 1 and 100"]]];
  if[`benchmarkMinSamples in key cfg;
    if[(type cfg`benchmarkMinSamples) in -5 -6 -7h;
      if[(not null cfg`benchmarkMinSamples) and 2>cfg`benchmarkMinSamples;
        warnings,:enlist "benchmarkMinSamples must be >= 2"]]];
  if[all `flakeWindow`flakeEvidenceMin in key cfg;
    if[(type cfg`flakeWindow) in -5 -6 -7h;
      if[(type cfg`flakeEvidenceMin) in -5 -6 -7h;
        if[(not null cfg`flakeWindow) and (not null cfg`flakeEvidenceMin) and
           cfg[`flakeWindow]<cfg`flakeEvidenceMin;
          warnings,:enlist "flakeWindow must be >= flakeEvidenceMin"]]]];
  if[all `shardIndex`shardCount in key cfg;
    if[(type cfg`shardIndex) in -5 -6 -7h;
      if[(type cfg`shardCount) in -5 -6 -7h;
        if[(not null cfg`shardIndex) and (not null cfg`shardCount) and
           cfg[`shardIndex]>=cfg`shardCount;
          warnings,:enlist "shardIndex must be less than shardCount"]]]];
  if[`reportProfile in key cfg;
    if[(not -11h=type cfg`reportProfile) or not (cfg`reportProfile) in `full`results`telemetry;
      warnings,:enlist "reportProfile must be one of: full, results, telemetry"]];
  if[`labels in key cfg;
    if[not .tst.validLabels cfg`labels;
      warnings,:enlist "labels must be a bounded string-to-string object with valid keys"]];
  if[all `reportProfile`shardCount in key cfg;
    if[(type cfg`shardCount) in -5 -6 -7h;
      if[((not null cfg`shardCount) and cfg[`shardCount]>1) and not ((cfg`reportProfile)~`full);
        warnings,:enlist "sharded runs require reportProfile full"]]];

  warnings,: raze checkType[cfg;;(10h;-10h;11h);]'[enlist `outDir; enlist "outDir must be a string or symbol"];
  warnings,: raze checkType[cfg;;(10h;-10h);]'[enlist `stateFile; enlist "stateFile must be a nonempty string or symbol"];
  if[`stateFile in key cfg;if[0=count .tst.toString cfg`stateFile;
      warnings,:enlist "stateFile must be a nonempty string or symbol"]];
  pathNames:`flakeHistoryFile`quarantineFile`flakeProposalFile;
  pathMsgs:("flakeHistoryFile must be a nonempty string or symbol";
      "quarantineFile must be a nonempty string or symbol";
      "flakeProposalFile must be a nonempty string or symbol");
  warnings,:raze checkType[cfg;;(10h;-10h);]'[pathNames;pathMsgs];
  warnings,:raze {[cfg;n]
      $[(n in key cfg) and 0=count .tst.toString cfg n;
        enlist string[n]," must be nonempty";()]}[cfg;] each pathNames;
  warnings,:raze checkType[cfg;;(10h;-10h);]'[
      enlist `benchmarkBaseline;enlist "benchmarkBaseline must be a string or symbol"];
  if[(1b~$[`lastFailed in key cfg;cfg`lastFailed;0b]) and
     1b~$[`failedFirst in key cfg;cfg`failedFirst;0b];
      warnings,:enlist "lastFailed and failedFirst cannot both be true"];

  specNames:`excludeSpecs`runSpecs;
  specMsgs:("excludeSpecs should be a symbol list or comma-separated string";
            "runSpecs should be a symbol list or comma-separated string");
  warnings,: raze checkType[cfg;;(0h;11h;-11h);]'[specNames; specMsgs];
  warnings,: raze checkType[cfg;;(0h;10h;11h;-11h);]'[
      enlist `pluginFiles;enlist "pluginFiles must be a string/symbol or list"];

  if[`testFilePatterns in key cfg;
    if[not .tst.validTestFilePatterns cfg`testFilePatterns;
      warnings,:enlist "testFilePatterns must be a nonempty string or list of safe basename glob strings"
    ];
  ];

  if[`coverageSources in key cfg;
    if[not .tst.validCoverageSources cfg`coverageSources;
      warnings,:enlist "coverageSources must be a nonempty path string/symbol or list of paths"
    ];
  ];

  warnings
 }

/ Identify which config keys are INVALID and must not be applied. A key is
/ invalid if it is unknown, fails its expected type, has an unsupported format
/ value, or coerced to a null (e.g. "I"$"abc" -> 0N). Returned as a symbol
/ list; applyConfig consults this so validation is authoritative -- a warned
/ value is never written into .tst.app / .resq.config.
invalidConfigKeys:{[cfg]
  if[(type cfg) in -20 20h; cfg:(enlist key cfg)!enlist value cfg];
  if[not 99h = type cfg; cfg:()!()];

  invalid:`symbol$();
  knownKeys:key .tst.defaultConfig;
  invalid,: (key cfg) except knownKeys;

  / fmt: invalid if it does not normalize to a supported format.
  if[`fmt in key cfg;
    cfgFmtRaw: .tst.normalizeFmtInput cfg`fmt;
    if[not cfgFmtRaw in `text`console`xml`junit`xunit`json; invalid,: `fmt];
  ];

  / Boolean-typed keys: must be a single boolean.
  boolNames:`describeOnly`xmlOutput`runPerformance`passOnly`exit`strict`failFast`failHard`pollutionGuard`qNamespaceExports`expectationLineAnnotations`qspecCompat`covStatements`allowPartialLineCoverage`randomOrder`lastFailed`failedFirst`strictPlugins`covBranches`covContexts`covAttemptContexts`quarantineNonBlocking`flakeProposals`snapshotAudit`snapshotGate`benchmarkGate`benchmarkAcceptEnvironment`vcsProbe;
  invalid,: boolNames where {[cfg;n] (n in key cfg) and not -1h = type cfg n}[cfg] each boolNames;

  / Integer-typed keys: must be a single integer-like value, not null, AND
  / non-negative. The null check catches loadConfig's "I"$"abc" -> 0N coercion
  / path; the >= 0 range check rejects insane-but-typed values like fuzzLimit:-5
  / or maxTestTime:-1, which pass the type guard but are nonsensical -> ignored
  / with a warning, default retained (the warn-and-ignore contract).
  intNames:`fuzzLimit`maxTestTime`reportLimit`reportListLimit`diffLargeTableThreshold`diffHugeTableThreshold`coverageMin`coverageFunctionMin`coverageLineMin`coverageCompletenessMin`coverageBranchMin`coverageBranchCompletenessMin`coverageContextMax`coverageContextEntryMax`seed`shardIndex`shardCount`flakeEvidenceMin`flakeFailureMin`flakeWindow;
  invalid,: intNames where {[cfg;n]
      if[not n in key cfg; :0b];
      v: cfg n;
      not .tst.validNonNegativeConfigInteger v
    }[cfg] each intNames;
  if[`coverageMin in key cfg;
    if[(type cfg`coverageMin) in -5 -6 -7h;
      if[(not null cfg[`coverageMin]) and (cfg[`coverageMin] > 100); invalid,:`coverageMin]]];
  percentNames:`coverageFunctionMin`coverageLineMin`coverageCompletenessMin`coverageBranchMin`coverageBranchCompletenessMin;
  invalid,:percentNames where {[cfg;n]
      if[not n in key cfg;:0b];
      if[not (type cfg n) in -5 -6 -7h;:0b];
      if[null cfg n;:0b];
      cfg[n]>100
    }[cfg] each percentNames;
  if[`shardCount in key cfg;
    if[(type cfg`shardCount) in -5 -6 -7h;
      if[(not null cfg`shardCount) and 1>cfg`shardCount;invalid,:`shardCount]]];
  if[`coverageContextMax in key cfg;
    if[(type cfg`coverageContextMax) in -5 -6 -7h;
      if[(not null cfg`coverageContextMax) and 1>cfg`coverageContextMax;
        invalid,:`coverageContextMax]]];
  if[`coverageContextEntryMax in key cfg;
    if[(type cfg`coverageContextEntryMax) in -5 -6 -7h;
      if[(not null cfg`coverageContextEntryMax) and 1>cfg`coverageContextEntryMax;
        invalid,:`coverageContextEntryMax]]];
  if[`flakeEvidenceMin in key cfg;
    if[(type cfg`flakeEvidenceMin) in -5 -6 -7h;
      if[(not null cfg`flakeEvidenceMin) and 2>cfg`flakeEvidenceMin;invalid,:`flakeEvidenceMin]]];
  if[`benchmarkAlphaPercent in key cfg;
    if[(type cfg`benchmarkAlphaPercent) in -5 -6 -7h;
      if[(not null cfg`benchmarkAlphaPercent) and 1>cfg`benchmarkAlphaPercent;invalid,:`benchmarkAlphaPercent]]];
  if[`benchmarkMinSamples in key cfg;
    if[(type cfg`benchmarkMinSamples) in -5 -6 -7h;
      if[(not null cfg`benchmarkMinSamples) and 2>cfg`benchmarkMinSamples;invalid,:`benchmarkMinSamples]]];
  if[`flakeFailureMin in key cfg;
    if[(type cfg`flakeFailureMin) in -5 -6 -7h;
      if[(not null cfg`flakeFailureMin) and 1>cfg`flakeFailureMin;invalid,:`flakeFailureMin]]];
  if[all `flakeWindow`flakeEvidenceMin in key cfg;
    if[(type cfg`flakeWindow) in -5 -6 -7h;
      if[(type cfg`flakeEvidenceMin) in -5 -6 -7h;
        if[(not null cfg`flakeWindow) and (not null cfg`flakeEvidenceMin) and
           cfg[`flakeWindow]<cfg`flakeEvidenceMin;invalid,:`flakeWindow`flakeEvidenceMin]]]];
  if[all `shardIndex`shardCount in key cfg;
    if[(type cfg`shardIndex) in -5 -6 -7h;
      if[(type cfg`shardCount) in -5 -6 -7h;
        if[(not null cfg`shardIndex) and (not null cfg`shardCount) and
           cfg[`shardIndex]>=cfg`shardCount;
          invalid,:`shardIndex`shardCount]]]];

  / outDir: string or symbol.
  if[`outDir in key cfg; if[not (type cfg`outDir) in 10 -10 11h; invalid,: `outDir]];
  if[`stateFile in key cfg;
    if[(not (type cfg`stateFile) in 10 -10h) or 0=count .tst.toString cfg`stateFile;
      invalid,:`stateFile]];
  pathNames:`flakeHistoryFile`quarantineFile`flakeProposalFile;
  invalid,:pathNames where {[cfg;n]
      (n in key cfg) and ((not (type cfg n) in 10 -10h) or 0=count .tst.toString cfg n)
    }[cfg] each pathNames;
  if[`benchmarkBaseline in key cfg;
    if[not (type cfg`benchmarkBaseline) in 10 -10h;invalid,:`benchmarkBaseline]];
  if[`shardUnit in key cfg;
    if[(not -11h=type cfg`shardUnit) or not (cfg`shardUnit) in `file`test`case;
      invalid,:`shardUnit]];
  if[`reportProfile in key cfg;
    if[(not -11h=type cfg`reportProfile) or not (cfg`reportProfile) in `full`results`telemetry;
      invalid,:`reportProfile]];
  if[`labels in key cfg;
    if[not .tst.validLabels cfg`labels;invalid,:`labels]];
  if[all `reportProfile`shardCount in key cfg;
    if[(type cfg`shardCount) in -5 -6 -7h;
      if[((not null cfg`shardCount) and cfg[`shardCount]>1) and not ((cfg`reportProfile)~`full);
        invalid,:`reportProfile]]];
  if[(1b~$[`lastFailed in key cfg;cfg`lastFailed;0b]) and
     1b~$[`failedFirst in key cfg;cfg`failedFirst;0b];
      invalid,:`lastFailed`failedFirst];

  / spec lists: symbol list or comma-separated string.
  specNames:`excludeSpecs`runSpecs;
  invalid,: specNames where {[cfg;n] (n in key cfg) and not (type cfg n) in 0 11 -11h}[cfg] each specNames;
  if[`pluginFiles in key cfg;
    if[not (type cfg`pluginFiles) in 0 10 11 -11h;invalid,:`pluginFiles]];

  if[`testFilePatterns in key cfg;
    if[not .tst.validTestFilePatterns cfg`testFilePatterns; invalid,:`testFilePatterns]];

  if[`coverageSources in key cfg;
    if[not .tst.validCoverageSources cfg`coverageSources; invalid,:`coverageSources]];

  distinct invalid
 }

/ Print validation warnings (separated from validateConfig so unit tests can
/ inspect warnings without polluting the run output).
printConfigWarnings:{[warnings]
    if[0<count warnings; {-1 "CONFIG WARNING: ", .tst.toString x} each warnings];
 }

/ Apply configuration to .tst.app and .resq.config
/ @param cfg (dict) Configuration dictionary
/ Validation is authoritative: any key flagged by invalidConfigKeys is skipped
/ (its current default is preserved) and a warning is printed. This stops a
/ warned-but-wrong value -- e.g. the string "yes" for `exit -- from being
/ written into .tst.app where if[] would treat it as truthy.
applyConfig:{[cfg]
    if[(type cfg) in -20 20h; cfg:(enlist key cfg)!enlist value cfg];
    if[not 99h=type cfg;
        -1 "CONFIG WARNING: ignoring malformed configuration (expected dictionary)";
        :()
    ];

    invalid: .tst.invalidConfigKeys cfg;
    if[0 < count invalid;
        -1 "CONFIG WARNING: ignoring invalid value(s) for: ", ", " sv string invalid;
    ];
    / ok[k] is true when key k is present AND passed validation.
    ok:{[cfg;invalid;k] (k in key cfg) and not k in invalid}[cfg;invalid];

    if[ok`describeOnly; .tst.app.describeOnly: cfg`describeOnly];
    if[ok`xmlOutput; .tst.app.xmlOutput: cfg`xmlOutput];
    if[ok`runPerformance; .tst.app.runPerformance: cfg`runPerformance];
    if[ok`excludeSpecs; .tst.app.excludeSpecs: cfg`excludeSpecs];
    if[ok`runSpecs; .tst.app.runSpecs: cfg`runSpecs];
    if[ok`passOnly;
        .tst.app.passOnly: cfg`passOnly;
        if[cfg`passOnly; .tst.app.quiet: 1b]];
    if[ok`exit; .tst.app.exit: cfg`exit];
    if[ok`strict; .tst.app.strict: cfg`strict];
    / qspec source-compatibility switch (musteq `=`, mustne `<>`).
    if[ok`qspecCompat; .tst.app.qspecCompat: cfg`qspecCompat];
    if[ok`covStatements; .tst.coverageStatements: cfg`covStatements];
    if[ok`allowPartialLineCoverage;
        .tst.app.allowPartialLineCoverage: cfg`allowPartialLineCoverage];
    if[ok`failFast; .tst.app.failFast: cfg`failFast];
    if[ok`failHard; .tst.app.failHard: cfg`failHard];
    if[ok`pollutionGuard; .tst.app.pollutionGuard: cfg`pollutionGuard];
    if[ok`expectationLineAnnotations;
        .tst.app.expectationLineAnnotations: cfg`expectationLineAnnotations];
    if[ok`randomOrder; .tst.app.randomOrder: cfg`randomOrder];
    if[ok`seed; .tst.app.executionSeed: "j"$cfg`seed];
    if[ok`lastFailed; .tst.app.lastFailed: cfg`lastFailed];
    if[ok`failedFirst; .tst.app.failedFirst: cfg`failedFirst];
    if[ok`strictPlugins;.tst.app.strictPlugins:cfg`strictPlugins];
    if[ok`pluginFiles;
        .tst.app.pluginFiles:$[10h=type cfg`pluginFiles;"," vs cfg`pluginFiles;
            -11h=type cfg`pluginFiles;enlist .tst.toString cfg`pluginFiles;
            .tst.toString each (),cfg`pluginFiles]];
    if[ok`stateFile; .tst.app.stateFile: .tst.toString cfg`stateFile];
    if[ok`shardIndex; .tst.app.shardIndex:"j"$cfg`shardIndex];
    if[ok`shardCount; .tst.app.shardCount:"j"$cfg`shardCount];
    if[ok`shardUnit;.tst.app.shardUnit:cfg`shardUnit];
    if[ok`reportProfile;.tst.app.reportProfile:cfg`reportProfile];
    if[ok`labels;.tst.app.labels:.tst.mergeLabels[.tst.app.labels;cfg`labels]];
    if[ok`vcsProbe;.tst.app.vcsProbe:cfg`vcsProbe];
    if[ok`quarantineNonBlocking;.tst.app.quarantineNonBlocking:cfg`quarantineNonBlocking];
    if[ok`flakeProposals;.tst.app.flakeProposalsEnabled:cfg`flakeProposals];
    if[ok`snapshotAudit;.tst.app.snapshotAudit:cfg`snapshotAudit];
    if[ok`snapshotGate;
        .tst.app.snapshotGate:cfg`snapshotGate;
        if[cfg`snapshotGate;.tst.app.snapshotAudit:1b]];
    if[ok`benchmarkBaseline;
        .tst.app.benchmarkBaseline:.tst.toString cfg`benchmarkBaseline;
        if[count .tst.app.benchmarkBaseline;.tst.app.runPerformance:1b]];
    if[ok`benchmarkGate;
        .tst.app.benchmarkGate:cfg`benchmarkGate;
        if[cfg`benchmarkGate;.tst.app.runPerformance:1b]];
    if[ok`benchmarkAcceptEnvironment;
        .tst.app.benchmarkAcceptEnvironment:cfg`benchmarkAcceptEnvironment];
    if[ok`benchmarkAlphaPercent;.tst.app.benchmarkAlphaPercent:"j"$cfg`benchmarkAlphaPercent];
    if[ok`benchmarkEffectMin;.tst.app.benchmarkEffectMin:"j"$cfg`benchmarkEffectMin];
    if[ok`benchmarkMinSamples;.tst.app.benchmarkMinSamples:"j"$cfg`benchmarkMinSamples];
    if[ok`flakeHistoryFile;.tst.app.flakeHistoryFile:.tst.toString cfg`flakeHistoryFile];
    if[ok`quarantineFile;.tst.app.quarantineFile:.tst.toString cfg`quarantineFile];
    if[ok`flakeProposalFile;.tst.app.flakeProposalFile:.tst.toString cfg`flakeProposalFile];
    if[ok`flakeEvidenceMin;.tst.app.flakeEvidenceMin:"j"$cfg`flakeEvidenceMin];
    if[ok`flakeFailureMin;.tst.app.flakeFailureMin:"j"$cfg`flakeFailureMin];
    if[ok`flakeWindow;.tst.app.flakeWindow:"j"$cfg`flakeWindow];

    if[ok`fuzzLimit; .tst.output.fuzzLimit: cfg`fuzzLimit];
    if[ok`maxTestTime; .tst.app.maxTestTime: cfg`maxTestTime];
    if[ok`reportLimit; .tst.output.reportLimit: cfg`reportLimit];
    if[ok`reportListLimit; .tst.output.reportListLimit: cfg`reportListLimit];
    if[ok`coverageMin; .tst.app.coverageMin: cfg`coverageMin];
    if[ok`coverageFunctionMin; .tst.app.coverageFunctionMin: cfg`coverageFunctionMin];
    if[ok`coverageLineMin; .tst.app.coverageLineMin: cfg`coverageLineMin];
    if[ok`coverageCompletenessMin;
        .tst.app.coverageCompletenessMin: cfg`coverageCompletenessMin];
    if[ok`covBranches;.tst.coverageBranches:cfg`covBranches];
    if[ok`covContexts;.tst.coverageContexts:cfg`covContexts];
    if[ok`covAttemptContexts;
        .tst.coverageAttemptContexts:cfg`covAttemptContexts;
        if[cfg`covAttemptContexts;.tst.coverageContexts:1b]];
    if[ok`coverageContextMax;
        .tst.coverageContextMax:"j"$cfg`coverageContextMax];
    if[ok`coverageContextEntryMax;
        .tst.coverageContextEntryMax:"j"$cfg`coverageContextEntryMax];
    if[ok`coverageBranchMin;
        .tst.app.coverageBranchMin:cfg`coverageBranchMin;
        if[0<cfg`coverageBranchMin;.tst.coverageBranches:1b]];
    if[ok`coverageBranchCompletenessMin;
        .tst.app.coverageBranchCompletenessMin:cfg`coverageBranchCompletenessMin;
        if[0<cfg`coverageBranchCompletenessMin;.tst.coverageBranches:1b]];
    if[ok`coverageSources;
        .tst.app.coverageSources: .tst.normalizeCoverageSources cfg`coverageSources];

    if[ok`qNamespaceExports;
        if[`setQNamespaceExports in key `.tst;
            .tst.setQNamespaceExports cfg`qNamespaceExports;
            .tst.qNamespaceExports: cfg`qNamespaceExports
        ];
    ];

    if[ok`fmt; .resq.config.fmt: cfg`fmt];
    if[ok`outDir; .resq.config.outDir: cfg`outDir];

    if[ok`diffLargeTableThreshold; .resq.config.diffLargeTableThreshold: cfg`diffLargeTableThreshold];
    if[ok`diffHugeTableThreshold; .resq.config.diffHugeTableThreshold: cfg`diffHugeTableThreshold];
    if[ok`testFilePatterns;
        .resq.config.testFilePatterns:.tst.normalizeTestFilePatterns cfg`testFilePatterns];
 }


\d .
::
