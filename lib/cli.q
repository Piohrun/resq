\d .tst

/ Helper for manual arg parsing
getArg:{[name;def]
    / Use simple list of strings
    opts: (("-",string name); ("--",string name));
    idx: where .z.x in opts;
    if[not count idx; :def];
    .z.x[(last idx)+1]
 };

getFlag:{[name]
    opts: (("-",string name); ("--",string name));
    any .z.x in opts
 };
    
initCLI:{[]
    / Manual Argument Parsing (CLI overrides config file)
    if[any .z.x like "-perf"; .tst.app.runPerformance: 1b];
    if[any .z.x in ("-junit";"-xml"); .resq.config.fmt: `junit; .tst.app.xmlOutput: 1b];
    if[any .z.x like "-xunit"; .resq.config.fmt: `xunit; .resq.config.outDir: "test-results"; .tst.app.xmlOutput: 1b];
    if[any .z.x like "-json"; .resq.config.fmt: `json; .tst.app.xmlOutput: 0b];
    if[any .z.x like "-noquit"; .tst.app.exit: 0b];
    if[any .z.x like "-exit"; .tst.app.exit: 1b];

    / Coverage Support
    .tst.app.runCoverage: 0b;
    if[any .z.x in ("-cov";"-coverage"); .tst.app.runCoverage: 1b];
    
    / Coverage Include/Exclude (Phase 3 enhancement)
    covInclude: getArg[`$"cov-include"; ""];
    if[0<count covInclude; .tst.app.coverageInclude: "," vs covInclude];
    covExclude: getArg[`$"cov-exclude"; ""];
    if[0<count covExclude; .tst.app.coverageExclude: "," vs covExclude];

    / Version check
    if[getFlag[`v] or getFlag[`version]; -1 "resQ version ", .resq.VERSION; exit 0];

    / Enhanced Manual Parsing
    .resq.config.outDir: getArg[`outDir; .resq.config.outDir];
    
    if[getFlag[`desc] or getFlag[`describe]; .tst.app.describeOnly: 1b; .tst.output.mode: `describe];
    
    if[getFlag[`ff] or getFlag[`$"fail-fast"]; .tst.app.failFast: 1b];
    if[getFlag[`fh] or getFlag[`$"fail-hard"]; .tst.app.failHard: 1b];
    
    exc: getArg[`exclude; ""];
    / Fix: Handle string vs list of strings safely
    if[0<count exc; .tst.app.excludeSpecs: `$"," vs " " sv $[10h=abs type exc; enlist exc; exc]];
    
    only: getArg[`only; ""];
    if[0<count only; .tst.app.runSpecs: `$"," vs " " sv $[10h=abs type only; enlist only; only]];
    
    / Tag-based filtering
    tagFilter: getArg[`tag; ""];
    if[0<count tagFilter; .tst.app.tagFilter: `$"," vs tagFilter];
    
    excludeTag: getArg[`$"exclude-tag"; ""];
    if[0<count excludeTag; .tst.app.excludeTagFilter: `$"," vs excludeTag];
 };
\d .
