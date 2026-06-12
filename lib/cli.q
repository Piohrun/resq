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

/ Describe-only reporter. Installed as the `.resq.report` hook (replacing the
/ text reporter) when -desc/-describe is set, so the normal summary path -- which
/ consumes the EMPTY results table and prints "( passed, failed, ...)" garbage in
/ describe mode -- is bypassed entirely. In describe mode runDiscoveredSpecs
/ leaves specs UNEXECUTED and stores them in .tst.app.results, so we list from
/ there (the `results` arg, the .resq.state.results table, is empty by design).
.tst.describeReport:{[results]
    specs: $[`results in key `.tst.app; .tst.app.results; ()];
    specsList: $[98h = type specs;
                 {[tbl; idx] tbl idx}[specs] each til count specs;
                 specs];
    / Keep only genuine spec dicts (skip any synthetic/empty entries).
    specsList: specsList where {[s] (99h = type s) and `title in key s} each specsList;
    nSuites: count specsList;
    nTests: sum {[s] $[`expectations in key s; count s`expectations; 0]} each specsList;
    -1 "";
    -1 "Discovered ", string[nSuites], " suite(s), ", string[nTests], " test(s):";
    -1 "----------------------------------------------------------------------";
    {[s]
        -1 "  ", .tst.toString s`title;
        exs: $[`expectations in key s; s`expectations; ()];
        exsList: $[98h = type exs;
                   {[tbl; idx] tbl idx}[exs] each til count exs;
                   exs];
        {[e] if[(99h = type e) and `desc in key e; -1 "      - ", .tst.toString e`desc]} each exsList;
    } each specsList;
    -1 "----------------------------------------------------------------------";
 };

validModes:`test`cover`discover`watch;

parseModeArgs:{[args]
    mode:`test;
    rest: args;
    if[0 < count args;
        cmd: `$first args;
        if[cmd in .tst.validModes;
            mode: cmd;
            rest: 1 _ args;
        ];
    ];
    `mode`args!(mode; rest)
 };
    
initCLI:{[]
    / Manual Argument Parsing (CLI overrides config file)
    if[any .z.x like "-perf"; .tst.app.runPerformance: 1b];
    if[any .z.x in ("-junit";"-xml"); .resq.config.fmt: `junit; .tst.app.xmlOutput: 1b];
    if[any .z.x like "-xunit"; .resq.config.fmt: `xunit; .resq.config.outDir: "test-results"; .tst.app.xmlOutput: 1b];
    if[any .z.x like "-json"; .resq.config.fmt: `json; .tst.app.xmlOutput: 0b];
    if[any .z.x like "-noquit"; .tst.app.exit: 0b];
    if[any .z.x like "-exit"; .tst.app.exit: 1b];
    if[getFlag[`strict]; .tst.app.strict: 1b];
    if[getFlag[`quiet]; .tst.app.quiet: 1b];

    maxTestTime: getArg[`$"maxTestTime"; ""];
    if[0<count maxTestTime; .tst.app.maxTestTime: "I"$maxTestTime];

    fuzzLimit: getArg[`$"fuzzLimit"; ""];
    if[0<count fuzzLimit; .tst.output.fuzzLimit: "I"$fuzzLimit];

    / Coverage Support
    .tst.app.runCoverage: 0b;
    if[any .z.x in ("-cov";"-coverage"); .tst.app.runCoverage: 1b];
    
    / Coverage include/exclude filters.
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
    
    / runSpecs / excludeSpecs are TITLE glob patterns matched with `like` in
    / runner.q's filterSpecs (`spec[`title] like pattern`). `like` requires a
    / STRING pattern -- a symbol pattern raises 'type -- so these must be lists
    / of strings, not symbols (cf. tests/test_runner.q which sets `enlist "a*"`).
    exc: getArg[`exclude; ""];
    / Handle string vs list of strings safely.
    if[0<count exc; .tst.app.excludeSpecs: "," vs " " sv $[10h=abs type exc; enlist exc; exc]];

    only: getArg[`only; ""];
    if[0<count only; .tst.app.runSpecs: "," vs " " sv $[10h=abs type only; enlist only; only]];

    / Tag-based filtering. Tags are matched by `in` against spec[`tags] in
    / runner.q's filterSpecs. The DSL (ui.q) stores a title tag WITH its leading
    / "#" (e.g. "describe ... #fast" -> `#fast), while config/programmatic tags
    / use the bare symbol (`fast). A user typing `-tag fast` means either, so we
    / expand each entry to BOTH the bare and "#"-prefixed symbol; `in` then
    / matches whichever form the suite actually carries.
    tagExpand: {[s] raze {[t] s: string t; t, $["#" = first s; `$1 _ s; `$"#", s]} each `$"," vs s};
    tagFilter: getArg[`tag; ""];
    if[0<count tagFilter; .tst.app.tagFilter: tagExpand tagFilter];

    excludeTag: getArg[`$"exclude-tag"; ""];
    if[0<count excludeTag; .tst.app.excludeTagFilter: tagExpand excludeTag];
 };
\d .
