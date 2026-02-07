\d .tst

/ Configuration file support
/ Loads settings from resq.json at project root

/ Default configuration
defaultConfig:`fmt`outDir`describeOnly`xmlOutput`runPerformance`excludeSpecs`runSpecs`passOnly`exit`fuzzLimit`failFast`failHard`maxTestTime`reportLimit`reportListLimit!(
    `text;                / Output format
    ".";                  / Output directory
    0b;                   / Describe only mode
    0b;                   / XML output
    0b;                   / Run performance tests
    ();                   / Exclude specs
    ();                   / Run specific specs
    0b;                   / Pass only
    0b;                   / Exit after tests
    100;                  / Fuzz display limit
    0b;                   / Fail fast
    0b;                   / Fail hard
    0;                    / Max test time (seconds), 0 = no timeout
    50000;                / Reporting string limit
    1000                  / Reporting list/table row limit
 );

/ Load configuration from JSON file
/ @param path (string) Path to config file (default: "resq.json")
/ @return (dict) Configuration dictionary
loadConfig:{[path]
    p: $[10h = abs type path; path; "resq.json"];
    
    / Check if file exists
    if[0<count key hsym `$p;
        / File exists, load and parse JSON
        lines: read0 hsym `$p;
        if[not count lines; :.tst.defaultConfig];
        content: "\n" sv lines;
        cfg: @[.j.k; content; { [e] -1 "WARNING: Failed to parse config JSON: ", e; ()!() }];
        
        / Merge with defaults
        merged: .tst.defaultConfig, cfg;
        
        / Convert exclude/runSpecs from strings to symbols if needed
        if[10h = type merged`excludeSpecs; merged[`excludeSpecs]: `$"," vs merged`excludeSpecs];
        if[10h = type merged`runSpecs; merged[`runSpecs]: `$"," vs merged`runSpecs];
        if[10h = type merged`fmt; merged[`fmt]: `$merged`fmt];
        if[10h = type merged`fuzzLimit; merged[`fuzzLimit]: "I"$merged`fuzzLimit];
        if[10h = type merged`maxTestTime; merged[`maxTestTime]: "I"$merged`maxTestTime];
        if[10h = type merged`reportLimit; merged[`reportLimit]: "I"$merged`reportLimit];
        if[10h = type merged`reportListLimit; merged[`reportListLimit]: "I"$merged`reportListLimit];
        
        :merged;
    ];
    
    / File doesn't exist, return defaults
    .tst.defaultConfig
 };

/ Phase 4: Configuration validation
/ @param cfg (dict) Configuration dictionary to validate
/ @return (list) List of warning messages (empty if valid)
validateConfig:{[cfg]
    warnings: ();
    
    / Check for unknown keys
    knownKeys: key .tst.defaultConfig;
    unknownKeys: (key cfg) except knownKeys;
    if[0 < count unknownKeys;
        warnings,: enlist "Unknown config keys: ", ", " sv string unknownKeys
    ];
    
    / Check type mismatches
    if[`fmt in key cfg;
        if[not (type cfg`fmt) in -11 10h;
            warnings,: enlist "fmt must be a symbol or string"
        ]
    ];
    if[`maxTestTime in key cfg;
        if[not (type cfg`maxTestTime) in -6 -7h;
            warnings,: enlist "maxTestTime must be an integer"
        ]
    ];
    if[`reportLimit in key cfg;
        if[not (type cfg`reportLimit) in -6 -7h;
            warnings,: enlist "reportLimit must be an integer"
        ]
    ];
    
    / Log warnings
    if[0 < count warnings;
        {-1 "CONFIG WARNING: ", x} each warnings
    ];
    
    warnings
 };

/ Apply configuration to .tst.app and .resq.config
/ @param cfg (dict) Configuration dictionary
applyConfig:{[cfg]
    / Map to .tst.app settings (only when keys exist)
    if[`describeOnly in key cfg; .tst.app.describeOnly: cfg`describeOnly];
    if[`xmlOutput in key cfg; .tst.app.xmlOutput: cfg`xmlOutput];
    if[`runPerformance in key cfg; .tst.app.runPerformance: cfg`runPerformance];
    if[`excludeSpecs in key cfg; .tst.app.excludeSpecs: cfg`excludeSpecs];
    if[`runSpecs in key cfg; .tst.app.runSpecs: cfg`runSpecs];
    if[`passOnly in key cfg; .tst.app.passOnly: cfg`passOnly];
    if[`exit in key cfg; .tst.app.exit: cfg`exit];
    if[`failFast in key cfg; .tst.app.failFast: cfg`failFast];
    if[`failHard in key cfg; .tst.app.failHard: cfg`failHard];
    if[`fuzzLimit in key cfg; .tst.output.fuzzLimit: cfg`fuzzLimit];
    if[`maxTestTime in key cfg; .tst.app.maxTestTime: cfg`maxTestTime];
    if[`reportLimit in key cfg; .tst.output.reportLimit: cfg`reportLimit];
    if[`reportListLimit in key cfg; .tst.output.reportListLimit: cfg`reportListLimit];
    
    / Map to .resq.config
    if[`fmt in key cfg; .resq.config.fmt: cfg`fmt];
    if[`outDir in key cfg; .resq.config.outDir: cfg`outDir];
 };

/ Merge CLI arguments into configuration (CLI takes precedence)
/ @param cfg (dict) Base configuration
/ @param args (dict) CLI arguments
/ @return (dict) Merged configuration
mergeCLIArgs:{[cfg; args]
    / CLI args override config file settings
    cfg, args where not null args
 };

\d .
::
