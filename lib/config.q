\d .tst

/ Configuration file support
/ Loads settings from resq.json at project root

/ Default configuration
defaultConfig:`fmt`outDir`describeOnly`xmlOutput`runPerformance`excludeSpecs`runSpecs`passOnly`exit`strict`fuzzLimit`failFast`failHard`pollutionGuard`maxTestTime`reportLimit`reportListLimit`qNamespaceExports`diffLargeTableThreshold`diffHugeTableThreshold`testFilePatterns!(`text;".";0b;0b;0b;();();0b;0b;0b;100;0b;0b;1b;0;50000;1000;1b;1000;10000;("test_*.q"; "*_test.q"))

/ Load configuration from JSON file
/ @param path (string) Path to config file (default: "resq.json")
/ @return (dict) Configuration dictionary
loadConfig:{[path]
    p:$[10h = type path; path; "resq.json"];
    cfgText:"";

    if[0 < count key hsym `$p;
        cfgText: "\n" sv read0 hsym `$p;
    ];

    cfg:()!();
    if[0 < count cfgText;
        cfg: @[.j.k; cfgText; {[e]
            -1 "WARNING: Failed to parse config JSON: ", e;
            ()!()
        }];
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

  boolNames:`describeOnly`xmlOutput`runPerformance`passOnly`exit`strict`failFast`failHard`pollutionGuard`qNamespaceExports;
  boolMsgs:("describeOnly must be a boolean";
            "xmlOutput must be a boolean";
            "runPerformance must be a boolean";
            "passOnly must be a boolean";
            "exit must be a boolean";
            "strict must be a boolean";
            "failFast must be a boolean";
            "failHard must be a boolean";
            "pollutionGuard must be a boolean";
            "qNamespaceExports must be a boolean");
  warnings,: raze checkType[cfg;;enlist -1h;]'[boolNames; boolMsgs];

  intNames:`fuzzLimit`maxTestTime`reportLimit`reportListLimit`diffLargeTableThreshold`diffHugeTableThreshold;
  intMsgs:("fuzzLimit must be an integer";
           "maxTestTime must be an integer";
           "reportLimit must be an integer";
           "reportListLimit must be an integer";
           "diffLargeTableThreshold must be an integer";
           "diffHugeTableThreshold must be an integer");
  warnings,: raze checkType[cfg;;(-7h;-6h;7h;6h);]'[intNames; intMsgs];

  / Range check: numeric keys must be non-negative. A correctly-typed but
  / negative value (e.g. fuzzLimit:-5, maxTestTime:-1) is nonsensical; warn and
  / let invalidConfigKeys ignore it (default retained). Only checked when the
  / value is an integer of the right type and not null.
  checkNonNeg:{[cfg;name;msg]
    if[not name in key cfg; :()];
    v: cfg name;
    if[not (type v) in -7 -6 7 6h; :()];
    $[(not null v) and v < 0; enlist msg; ()]
  };
  rangeMsgs:("fuzzLimit must be >= 0";
             "maxTestTime must be >= 0";
             "reportLimit must be >= 0";
             "reportListLimit must be >= 0";
             "diffLargeTableThreshold must be >= 0";
             "diffHugeTableThreshold must be >= 0");
  warnings,: raze checkNonNeg[cfg;;]'[intNames; rangeMsgs];

  warnings,: raze checkType[cfg;;(10h;-10h;11h);]'[enlist `outDir; enlist "outDir must be a string or symbol"];

  specNames:`excludeSpecs`runSpecs;
  specMsgs:("excludeSpecs should be a symbol list or comma-separated string";
            "runSpecs should be a symbol list or comma-separated string");
  warnings,: raze checkType[cfg;;(0h;11h;-11h);]'[specNames; specMsgs];

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
  boolNames:`describeOnly`xmlOutput`runPerformance`passOnly`exit`strict`failFast`failHard`pollutionGuard`qNamespaceExports;
  invalid,: boolNames where {[cfg;n] (n in key cfg) and not -1h = type cfg n}[cfg] each boolNames;

  / Integer-typed keys: must be a single integer-like value, not null, AND
  / non-negative. The null check catches loadConfig's "I"$"abc" -> 0N coercion
  / path; the >= 0 range check rejects insane-but-typed values like fuzzLimit:-5
  / or maxTestTime:-1, which pass the type guard but are nonsensical -> ignored
  / with a warning, default retained (the warn-and-ignore contract).
  intNames:`fuzzLimit`maxTestTime`reportLimit`reportListLimit`diffLargeTableThreshold`diffHugeTableThreshold;
  invalid,: intNames where {[cfg;n]
      if[not n in key cfg; :0b];
      v: cfg n;
      if[not (type v) in -7 -6 7 6h; :1b];
      (null v) or v < 0
    }[cfg] each intNames;

  / outDir: string or symbol.
  if[`outDir in key cfg; if[not (type cfg`outDir) in 10 -10 11h; invalid,: `outDir]];

  / spec lists: symbol list or comma-separated string.
  specNames:`excludeSpecs`runSpecs;
  invalid,: specNames where {[cfg;n] (n in key cfg) and not (type cfg n) in 0 11 -11h}[cfg] each specNames;

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
    if[ok`passOnly; .tst.app.passOnly: cfg`passOnly];
    if[ok`exit; .tst.app.exit: cfg`exit];
    if[ok`strict; .tst.app.strict: cfg`strict];
    if[ok`failFast; .tst.app.failFast: cfg`failFast];
    if[ok`failHard; .tst.app.failHard: cfg`failHard];
    if[ok`pollutionGuard; .tst.app.pollutionGuard: cfg`pollutionGuard];

    if[ok`fuzzLimit; .tst.output.fuzzLimit: cfg`fuzzLimit];
    if[ok`maxTestTime; .tst.app.maxTestTime: cfg`maxTestTime];
    if[ok`reportLimit; .tst.output.reportLimit: cfg`reportLimit];
    if[ok`reportListLimit; .tst.output.reportListLimit: cfg`reportListLimit];

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
    if[ok`testFilePatterns; .resq.config.testFilePatterns: cfg`testFilePatterns];
 }

/ Merge CLI arguments into configuration (CLI takes precedence)
/ @param cfg (dict) Base configuration
/ @param args (dict) CLI arguments
/ @return (dict) Merged configuration
mergeCLIArgs:{[cfg; args] cfg, args where not null args}

\d .
::
