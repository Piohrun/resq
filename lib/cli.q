\d .tst

/ Authoritative CLI option schema. Aliases are stored as strings so unknown
/ user input is never interned as a symbol. Every alias accepts both -x and --x.
.tst.cli.specNames:`perf`junit`xunit`json`noquit`exit`strict`quiet`isolate`coverage`version`describe`failFast`failHard`debug`interactive`qspecCompat`isolateTimeout`maxTestTime`fuzzLimit`coverageInclude`coverageExclude`outDir`exclude`only`tag`excludeTag;
.tst.cli.specAliases:(enlist "perf";("junit";"xml");enlist "xunit";enlist "json";enlist "noquit";enlist "exit";enlist "strict";enlist "quiet";enlist "isolate";("cov";"coverage");("v";"version");("desc";"describe");("ff";"fail-fast");("fh";"fail-hard");enlist "debug";enlist "interactive";("qspec-compat";"qspecCompat");enlist "isolateTimeout";enlist "maxTestTime";enlist "fuzzLimit";enlist "cov-include";enlist "cov-exclude";enlist "outDir";enlist "exclude";enlist "only";enlist "tag";enlist "exclude-tag");
.tst.cli.specKinds:(17 # `flag), 10 # `value;
.tst.cli.numericNames: `isolateTimeout`maxTestTime`fuzzLimit;

/ The three spec lists are positionally coupled; refuse to load if an edit to
/ one of them ever leaves them misaligned (a silent mislabel otherwise).
if[not (count .tst.cli.specNames) = count .tst.cli.specAliases;
    '"cli option schema mismatch: specNames vs specAliases"];
if[not (count .tst.cli.specNames) = count .tst.cli.specKinds;
    '"cli option schema mismatch: specNames vs specKinds"];
if[not all .tst.cli.numericNames in .tst.cli.specNames;
    '"cli option schema mismatch: numericNames not in specNames"];

.tst.cli.expandAliases:{[aliases]
    raze {("-",x; "--",x)} each aliases
 };

.tst.cli.optionTokens:raze .tst.cli.expandAliases each .tst.cli.specAliases;
.tst.cli.optionNames:raze {[name; aliases] (2 * count aliases) # enlist name}'[.tst.cli.specNames; .tst.cli.specAliases];
.tst.cli.optionKinds:raze {[kind; aliases] (2 * count aliases) # enlist kind}'[.tst.cli.specKinds; .tst.cli.specAliases];

.tst.cli.emptyOptions:{[]
    .tst.cli.specNames!
        {$[x ~ `flag; 0b; ""]} each .tst.cli.specKinds
 };

.tst.cli.error:{[message]
    `ok`error`mode`args`options!(
        0b;
        message;
        `test;
        ();
        .tst.cli.emptyOptions[])
 };

.tst.cli.startsDash:{[token]
    (1 < count token) and "-" = first token
 };

.tst.cli.isIntegerText:{[text]
    if[not 10h = abs type text; :0b];
    if[0 = count text; :0b];
    body: $[first[text] in "+-"; 1 _ text; text];
    (0 < count body) and all body in "0123456789"
 };

/ Resolve one canonical option from its occurrences. Flags normalize to a
/ boolean; value options use the last occurrence (last duplicate wins).
.tst.cli.resolveOption:{[occNames; occPositions; valuePositions; values; numericPositions; numericValues; name]
    matches: where occNames = name;
    kind: .tst.cli.specKinds .tst.cli.specNames ? name;
    if[kind ~ `flag; :0 < count matches];
    if[0 = count matches; :""];
    chosenPosition: occPositions last matches;
    if[chosenPosition in numericPositions;
        :numericValues numericPositions ? chosenPosition];
    values valuePositions ? chosenPosition
 };

/ Parse command-line tokens once into normalized options, mode, and positionals.
/ This is a bounded CLI state analysis: option/value positions are derived
/ vectorially, so values can never leak into positional dispatch.
.tst.parseCLI:{[args]
    separatorPositions: where {"--" ~ x} each args;
    separator: $[count separatorPositions; first separatorPositions; count args];
    preTokens: separator # args;
    postTokens: $[separator < count args; (separator + 1) _ args; ()];
    / q's native `\l -name.q` treats the leading dash as syntax. Preserve the
    / user's relative path semantics while making the downstream load safe.
    cliCwd: system "cd";
    postTokens: {[cwd; x]
        $[.tst.cli.startsDash x; cwd, "/", x; x]
    }[cliCwd;] each postTokens;

    tokenIndexes: .tst.cli.optionTokens ? preTokens;
    isOption: tokenIndexes < count .tst.cli.optionTokens;
    optionPositions: where isOption;
    occurrenceNames: .tst.cli.optionNames tokenIndexes optionPositions;
    occurrenceKinds: .tst.cli.optionKinds tokenIndexes optionPositions;
    valuePositions: optionPositions where occurrenceKinds = `value;

    missingPositions: valuePositions where valuePositions >= -1 + count preTokens;
    if[count missingPositions;
        badPosition: first missingPositions;
        :.tst.cli.error "Missing value for ", preTokens badPosition];

    values: preTokens 1 + valuePositions;
    emptyValues: where 0 = count each values;
    if[count emptyValues;
        badIndex: first emptyValues;
        :.tst.cli.error "Empty value for ", preTokens valuePositions badIndex];

    nextIndexes: .tst.cli.optionTokens ? values;
    nextIsOption: nextIndexes < count .tst.cli.optionTokens;
    if[any nextIsOption;
        badIndex: first where nextIsOption;
        :.tst.cli.error "Missing value for ", preTokens[valuePositions badIndex],
            "; next token is option ", values badIndex];

    valueNames: .tst.cli.optionNames tokenIndexes valuePositions;
    dashValues: .tst.cli.startsDash each values;
    signedNumeric: (valueNames in .tst.cli.numericNames) and
        .tst.cli.isIntegerText each values;
    invalidDash: where dashValues and not signedNumeric;
    if[count invalidDash;
        badIndex: first invalidDash;
        :.tst.cli.error "Missing value for ", preTokens[valuePositions badIndex],
            "; next token looks like option ", values badIndex];

    consumedPositions: 1 + valuePositions;
    allPositions: til count preTokens;
    unknownPositions: where
        (.tst.cli.startsDash each preTokens) and
        (not isOption) and
        not allPositions in consumedPositions;
    if[count unknownPositions;
        :.tst.cli.error "Unknown option: ", preTokens first unknownPositions];

    numericMask: valueNames in .tst.cli.numericNames;
    numericTexts: values where numericMask;
    numericOptionNames: valueNames where numericMask;
    invalidIntegers: where not .tst.cli.isIntegerText each numericTexts;
    if[count invalidIntegers;
        badIndex: first invalidIntegers;
        numericValuePositions: valuePositions where numericMask;
        :.tst.cli.error "Invalid integer for ",
            preTokens[numericValuePositions badIndex], ": ", numericTexts badIndex];

    numericValues: {"J"$x} each numericTexts;
    nullIntegers: where null numericValues;
    if[count nullIntegers;
        badIndex: first nullIntegers;
        numericValuePositions: valuePositions where numericMask;
        :.tst.cli.error "Invalid integer for ",
            preTokens[numericValuePositions badIndex], ": ", numericTexts badIndex];

    invalidRanges: where
        (numericValues < 0) or
        (numericOptionNames = `isolateTimeout) and numericValues = 0;
    if[count invalidRanges;
        badIndex: first invalidRanges;
        numericValuePositions: valuePositions where numericMask;
        requirement: $[numericOptionNames[badIndex] ~ `isolateTimeout; "> 0"; ">= 0"];
        :.tst.cli.error "Value must be ", requirement, " for ",
            preTokens[numericValuePositions badIndex], ": ", numericTexts badIndex];

    numericValuePositions: valuePositions where numericMask;
    optionValues:
        .tst.cli.resolveOption[
            occurrenceNames;
            optionPositions;
            valuePositions;
            values;
            numericValuePositions;
            numericValues;] each .tst.cli.specNames;
    options: .tst.cli.specNames ! optionValues;

    if[(1b ~ options`exit) and 1b ~ options`noquit;
        :.tst.cli.error "Options -exit and -noquit cannot be used together"];

    positionalPositions: allPositions where
        (not isOption) and
        not allPositions in consumedPositions;
    parsedMode: .tst.parseModeArgs (preTokens positionalPositions), postTokens;
    `ok`error`mode`args`options!(
        1b;
        "";
        parsedMode`mode;
        parsedMode`args;
        options)
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
    
initCLI:{[parsed]
    / Apply only normalized values from parseCLI; .z.x is never reparsed here.
    options: parsed`options;
    if[options`debug; .utl.DEBUG: 1b];
    if[options`perf; .tst.app.runPerformance: 1b];
    if[options`junit; .resq.config.fmt: `junit; .tst.app.xmlOutput: 1b];
    / -xunit used to force outDir to "test-results", so it alone wrote to a
    / SUBDIRECTORY while -junit and -json wrote to outDir itself. That was
    / undocumented -- every doc promises outDir/test-results.xml (default ".")
    / -- and made the reporters inconsistent for no stated reason. An explicit
    / -outDir still wins for all three (applied below).
    if[options`xunit; .resq.config.fmt: `xunit; .tst.app.xmlOutput: 1b];
    if[options`json; .resq.config.fmt: `json; .tst.app.xmlOutput: 0b];
    if[options`noquit; .tst.app.exit: 0b];
    if[options`exit; .tst.app.exit: 1b];
    if[options`strict; .tst.app.strict: 1b];
    / Restore qspec's musteq (`=`) and mustne (`<>`) semantics so an unported
    / qspec suite runs unchanged. See docs/MIGRATION.md.
    if[options`qspecCompat; .tst.app.qspecCompat: 1b];
    if[options`quiet; .tst.app.quiet: 1b];

    / Process-isolation mode: each discovered test FILE runs in its own q
    / subprocess (see lib/isolate.q). -isolateTimeout sets the per-FILE wall
    / clock cap in seconds (default 300), enforced via the `timeout` binary.
    if[options`isolate; .tst.app.isolate: 1b];
    if[0 < count options`isolateTimeout;
        .tst.app.isolateTimeout: options`isolateTimeout];
    if[0 < count options`maxTestTime;
        .tst.app.maxTestTime: options`maxTestTime];
    if[0 < count options`fuzzLimit;
        .tst.output.fuzzLimit: options`fuzzLimit];

    / Coverage Support
    .tst.app.runCoverage: 0b;
    if[options`coverage; .tst.app.runCoverage: 1b];
    
    / Coverage include/exclude filters.
    if[0 < count options`coverageInclude;
        .tst.app.coverageInclude: "," vs options`coverageInclude];
    if[0 < count options`coverageExclude;
        .tst.app.coverageExclude: "," vs options`coverageExclude];

    / Version check
    if[options`version; -1 "resQ version ", .resq.VERSION; exit 0];

    if[0 < count options`outDir;
        .resq.config.outDir: options`outDir];
    
    if[options`describe; .tst.app.describeOnly: 1b; .tst.output.mode: `describe];
    
    if[options`failFast; .tst.app.failFast: 1b];
    if[options`failHard; .tst.app.failHard: 1b];
    
    / runSpecs / excludeSpecs are TITLE glob patterns matched with `like` in
    / runner.q's filterSpecs (`spec[`title] like pattern`). `like` requires a
    / STRING pattern -- a symbol pattern raises 'type -- so these must be lists
    / of strings, not symbols (cf. tests/test_runner.q which sets `enlist "a*"`).
    if[0 < count options`exclude;
        .tst.app.excludeSpecs: "," vs options`exclude];
    if[0 < count options`only;
        .tst.app.runSpecs: "," vs options`only];

    / Tag-based filtering. Tags are matched by `in` against spec[`tags] in
    / runner.q's filterSpecs. The DSL (ui.q) stores a title tag WITH its leading
    / "#" (e.g. "describe ... #fast" -> `#fast), while config/programmatic tags
    / use the bare symbol (`fast). A user typing `-tag fast` means either, so we
    / expand each entry to BOTH the bare and "#"-prefixed symbol; `in` then
    / matches whichever form the suite actually carries.
    tagExpand: {[s] raze {[t] s: string t; t, $["#" = first s; `$1 _ s; `$"#", s]} each `$"," vs s};
    if[0 < count options`tag;
        .tst.app.tagFilter: tagExpand options`tag];
    if[0 < count options`excludeTag;
        .tst.app.excludeTagFilter: tagExpand options`excludeTag];
 };
\d .
