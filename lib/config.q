\d .tst

/ Configuration file support
/ Loads settings from resq.json at project root

/ Default configuration
defaultConfig:`fmt`outDir`describeOnly`xmlOutput`runPerformance`excludeSpecs`runSpecs`passOnly`exit`strict`fuzzLimit`failFast`failHard`pollutionGuard`maxTestTime`reportLimit`reportListLimit`qNamespaceExports!(`text;".";0b;0b;0b;();();0b;0b;0b;100;0b;0b;1b;0;50000;1000;1b)

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

/ Phase 4: Configuration validation
/ @param cfg (dict) Configuration dictionary
/ @return (list) List of warning messages (empty if valid)
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

  intNames:`fuzzLimit`maxTestTime`reportLimit`reportListLimit;
  intMsgs:("fuzzLimit must be an integer";
           "maxTestTime must be an integer";
           "reportLimit must be an integer";
           "reportListLimit must be an integer");
  warnings,: raze checkType[cfg;;(-7h;-6h;7h;6h);]'[intNames; intMsgs];

  warnings,: raze checkType[cfg;;(10h;-10h;11h);]'[enlist `outDir; enlist "outDir must be a string or symbol"];

  specNames:`excludeSpecs`runSpecs;
  specMsgs:("excludeSpecs should be a symbol list or comma-separated string";
            "runSpecs should be a symbol list or comma-separated string");
  warnings,: raze checkType[cfg;;(0h;11h;-11h);]'[specNames; specMsgs];

  warnings
 }

/ Print validation warnings (separated from validateConfig so unit tests can
/ inspect warnings without polluting the run output).
printConfigWarnings:{[warnings]
    if[0<count warnings; {-1 "CONFIG WARNING: ", .tst.toString x} each warnings];
 }

/ Apply configuration to .tst.app and .resq.config
/ @param cfg (dict) Configuration dictionary
applyConfig:{[cfg]
    if[`describeOnly in key cfg; .tst.app.describeOnly: cfg`describeOnly];
    if[`xmlOutput in key cfg; .tst.app.xmlOutput: cfg`xmlOutput];
    if[`runPerformance in key cfg; .tst.app.runPerformance: cfg`runPerformance];
    if[`excludeSpecs in key cfg; .tst.app.excludeSpecs: cfg`excludeSpecs];
    if[`runSpecs in key cfg; .tst.app.runSpecs: cfg`runSpecs];
    if[`passOnly in key cfg; .tst.app.passOnly: cfg`passOnly];
    if[`exit in key cfg; .tst.app.exit: cfg`exit];
    if[`strict in key cfg; .tst.app.strict: cfg`strict];
    if[`failFast in key cfg; .tst.app.failFast: cfg`failFast];
    if[`failHard in key cfg; .tst.app.failHard: cfg`failHard];
    if[`pollutionGuard in key cfg; .tst.app.pollutionGuard: cfg`pollutionGuard];

    if[`fuzzLimit in key cfg; .tst.output.fuzzLimit: cfg`fuzzLimit];
    if[`maxTestTime in key cfg; .tst.app.maxTestTime: cfg`maxTestTime];
    if[`reportLimit in key cfg; .tst.output.reportLimit: cfg`reportLimit];
    if[`reportListLimit in key cfg; .tst.output.reportListLimit: cfg`reportListLimit];

    if[`qNamespaceExports in key cfg;
        if[`setQNamespaceExports in key `.tst;
            .tst.setQNamespaceExports cfg`qNamespaceExports;
            .tst.qNamespaceExports: cfg`qNamespaceExports
        ];
    ];

    if[`fmt in key cfg; .resq.config.fmt: cfg`fmt];
    if[`outDir in key cfg; .resq.config.outDir: cfg`outDir];
 }

/ Merge CLI arguments into configuration (CLI takes precedence)
/ @param cfg (dict) Base configuration
/ @param args (dict) CLI arguments
/ @return (dict) Merged configuration
mergeCLIArgs:{[cfg; args] cfg, args where not null args}

\d .
::
