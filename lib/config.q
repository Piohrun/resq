\d .tst

/ Configuration file support
/ Loads settings from resq.json at project root

/ Default configuration
defaultConfig:`fmt`outDir`describeOnly`xmlOutput`runPerformance`excludeSpecs`runSpecs`passOnly`exit`fuzzLimit`failFast`failHard`maxTestTime`reportLimit`reportListLimit`qNamespaceExports!(`text;".";0b;0b;0b;();();0b;0b;100;0b;0b;0;50000;1000;1b)

/ Load configuration from JSON file
/ @param path (string) Path to config file (default: "resq.json")
/ @return (dict) Configuration dictionary
loadConfig:{[path] p:$[10h=type path; path; "resq.json"]; cfgText:$[0<count key hsym `$p; "\n" sv read0 hsym `$p; ""]; cfg:$[0<count cfgText; @[.j.k; cfgText; {[e] -1 "WARNING: Failed to parse config JSON: ", e; ()!()}]; ()!()]; merged:$[0<count cfg; .tst.defaultConfig, cfg; .tst.defaultConfig]; if[10h = type merged`excludeSpecs; merged[`excludeSpecs]: `$"," vs merged`excludeSpecs]; if[10h = type merged`runSpecs; merged[`runSpecs]: `$"," vs merged`runSpecs]; if[`fmt in key merged; merged[`fmt]: .tst.normalizeFmt merged`fmt]; if[10h = type merged`fuzzLimit; merged[`fuzzLimit]: "I"$merged`fuzzLimit]; if[10h = type merged`maxTestTime; merged[`maxTestTime]: "I"$merged`maxTestTime]; if[10h = type merged`reportLimit; merged[`reportLimit]: "I"$merged`reportLimit]; if[10h = type merged`reportListLimit; merged[`reportListLimit]: "I"$merged`reportListLimit]; merged}

.tst.normalizeFmtInput:{[fmt]
    $[10h = type fmt; `$lower string fmt;
      11h = type fmt; lower fmt;
      0h = type fmt; `text;
      `$lower string fmt]
 }

.tst.normalizeFmt:{[fmt]
    rawFmt: .tst.normalizeFmtInput fmt;
    $[rawFmt = `console; `text;
      rawFmt = `xml; `junit;
      rawFmt in (`text; `junit; `xunit; `json); rawFmt;
      `text]
 }

/ Phase 4: Configuration validation
/ @param cfg (dict) Configuration dictionary
/ @return (list) List of warning messages (empty if valid)
validateConfig:{[cfg] warnings:(); knownKeys:key .tst.defaultConfig; unknownKeys:(key cfg) except knownKeys; if[0<count unknownKeys; warnings: warnings, enlist "Unknown config keys: ", ", " sv string unknownKeys]; cfgFmtRaw: .tst.normalizeFmtInput $[`fmt in key cfg; cfg`fmt; "text"]; if[`fmt in key cfg and not cfgFmtRaw in (`text; `console; `xml; `junit; `xunit; `json); warnings: warnings, enlist "Unsupported format: ", string cfgFmtRaw, " (expected text, console, junit, xunit, or json)"]; if[`describeOnly in key cfg and 1h <> type cfg`describeOnly; warnings: warnings, enlist "describeOnly must be a boolean"]; if[`xmlOutput in key cfg and 1h <> type cfg`xmlOutput; warnings: warnings, enlist "xmlOutput must be a boolean"]; if[`runPerformance in key cfg and 1h <> type cfg`runPerformance; warnings: warnings, enlist "runPerformance must be a boolean"]; if[`passOnly in key cfg and 1h <> type cfg`passOnly; warnings: warnings, enlist "passOnly must be a boolean"]; if[`exit in key cfg and 1h <> type cfg`exit; warnings: warnings, enlist "exit must be a boolean"]; if[`failFast in key cfg and 1h <> type cfg`failFast; warnings: warnings, enlist "failFast must be a boolean"]; if[`failHard in key cfg and 1h <> type cfg`failHard; warnings: warnings, enlist "failHard must be a boolean"]; if[`qNamespaceExports in key cfg and 1h <> type cfg`qNamespaceExports; warnings: warnings, enlist "qNamespaceExports must be a boolean"]; if[`fuzzLimit in key cfg and not (type cfg`fuzzLimit) in -7 -6; warnings: warnings, enlist "fuzzLimit must be an integer"]; if[`maxTestTime in key cfg and not (type cfg`maxTestTime) in -7 -6; warnings: warnings, enlist "maxTestTime must be an integer"]; if[`reportLimit in key cfg and not (type cfg`reportLimit) in -7 -6; warnings: warnings, enlist "reportLimit must be an integer"]; if[`reportListLimit in key cfg and not (type cfg`reportListLimit) in -7 -6; warnings: warnings, enlist "reportListLimit must be an integer"]; if[`outDir in key cfg and not (type cfg`outDir) in (10h;11h); warnings: warnings, enlist "outDir must be a string or symbol"]; if[`excludeSpecs in key cfg and not (type cfg`excludeSpecs) in (0h;11h;-11); warnings: warnings, enlist "excludeSpecs should be a symbol list or comma-separated string"]; if[`runSpecs in key cfg and not (type cfg`runSpecs) in (0h;11h;-11); warnings: warnings, enlist "runSpecs should be a symbol list or comma-separated string"]; if[0<count warnings; {-1 "CONFIG WARNING: ", x} each warnings]; warnings}

/ Apply configuration to .tst.app and .resq.config
/ @param cfg (dict) Configuration dictionary
applyConfig:{[cfg] if[`describeOnly in key cfg; .tst.app.describeOnly: cfg`describeOnly]; if[`xmlOutput in key cfg; .tst.app.xmlOutput: cfg`xmlOutput]; if[`runPerformance in key cfg; .tst.app.runPerformance: cfg`runPerformance]; if[`excludeSpecs in key cfg; .tst.app.excludeSpecs: cfg`excludeSpecs]; if[`runSpecs in key cfg; .tst.app.runSpecs: cfg`runSpecs]; if[`passOnly in key cfg; .tst.app.passOnly: cfg`passOnly]; if[`exit in key cfg; .tst.app.exit: cfg`exit]; if[`failFast in key cfg; .tst.app.failFast: cfg`failFast]; if[`failHard in key cfg; .tst.app.failHard: cfg`failHard]; if[`fuzzLimit in key cfg; .tst.output.fuzzLimit: cfg`fuzzLimit]; if[`maxTestTime in key cfg; .tst.app.maxTestTime: cfg`maxTestTime]; if[`reportLimit in key cfg; .tst.output.reportLimit: cfg`reportLimit]; if[`reportListLimit in key cfg; .tst.output.reportListLimit: cfg`reportListLimit]; if[`qNamespaceExports in key cfg; if[`setQNamespaceExports in key `.tst; .tst.setQNamespaceExports cfg`qNamespaceExports; .tst.qNamespaceExports: cfg`qNamespaceExports]]; if[`fmt in key cfg; .resq.config.fmt: cfg`fmt]; if[`outDir in key cfg; .resq.config.outDir: cfg`outDir]}

/ Merge CLI arguments into configuration (CLI takes precedence)
/ @param cfg (dict) Base configuration
/ @param args (dict) CLI arguments
/ @return (dict) Merged configuration
mergeCLIArgs:{[cfg; args] cfg, args where not null args}

\d .
::
