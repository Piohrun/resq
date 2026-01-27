/ Runtime coverage module (instrumentation reintroduced, load-safe)
.utl.require "lib/static_analysis.q"

/ State
.tst.coverageData: ()!();        / file -> func -> count
.tst.coverageEnabled: 0b;
.tst.trackedFiles: ();
.tst.origFuncs: ()!();           / name -> original function
.tst.loadingStack: ();
.tst._covMissing: `resqCovMissing;

/ Functions that must never be wrapped (avoid recursion/self-instrumentation)
.tst.coverageSkipNames: `$(".tst.initCoverage";".tst.recordExecution";".tst.resolvePath";".tst.wrapFunc";".tst.instrumentFile";".tst.loadSource";".tst.generateLCOV";".tst.generateHTML");

/ Helpers
.tst.resolvePath:{[path]
    s: $[10h = abs type path; path; string path];
    if[s like ":*"; s: 1 _ s];
    if[not s like "/*"; s: (system "cd"), "/", s];
    .utl.normalizePath s
 };

.tst._covNameStr:{[x]
    s: -3! x;
    if[(count s) > 0;
        if[first s = "`"; s: 1 _ s];
    ];
    s
 };

.tst._covNumStr:{[x] string `long$x };

.tst.safeValue:{[sym]
    s: string sym;
    if[not s like ".*";
        if[sym in key `.; :get sym];
        :.tst._covMissing
    ];

    parts: "." vs s;
    if[count parts < 3; :.tst._covMissing];

    nsSym: `$"." sv -1 _ parts;
    vnSym: `$last parts;

    if[not nsSym in key `.; :.tst._covMissing];

    nsKeys: key nsSym;
    if[() ~ nsKeys; :.tst._covMissing];
    if[not vnSym in nsKeys; :.tst._covMissing];

    get ` sv nsSym, vnSym
 };

.tst.ensureCoverageEntry:{[fileSym]
    if[not fileSym in key .tst.coverageData;
        .tst.coverageData[fileSym]: ()!();
        .tst.trackedFiles,: fileSym;
    ];
 };

/ Record execution (called by wrappers)
.tst.recordExecution:{[file;funcName]
    if[not .tst.coverageEnabled; :()];

    fileSym: $[10h = abs type file; `$file; file];
    .tst.ensureCoverageEntry[fileSym];

    if[not funcName in key .tst.coverageData[fileSym];
        .tst.coverageData[fileSym;funcName]: 0;
    ];

    .tst.coverageData[fileSym;funcName]+: 1;
 };

/ Wrap a function with tracking logic
/ @param name (symbol) Function name (e.g. `.user.create`)
/ @param fileSym (symbol) Source file symbol
.tst.wrapFunc:{[name;fileSym]
    / Skip coverage internals and already-wrapped names
    if[name in .tst.coverageSkipNames; :()];
    if[name in key .tst.origFuncs; :()];

    orig: .tst.safeValue name;
    if[orig ~ .tst._covMissing; :()];
    if[not type[orig] within (100h;104h); :()];

    .tst.origFuncs[name]: orig;

    args: value[orig] 1;
    argStr: $[0 < count args; ";" sv string args; ""];
    callArgs: "[", argStr, "]";

    wrapperCode: "{", callArgs,
        " .tst.recordExecution[`", string fileSym, "`;`", string name, "];",
        " .tst.origFuncs[`", string name, "]", callArgs,
        " }";

    @[name set; value wrapperCode; {[n;e]
        -1 "Coverage wrap failed for ", string n, ": ", .Q.s1 e;
        :()
    }[name]];
 };

/ Instrument a loaded file (analyze and wrap functions)
/ @param pathStr (string) Absolute normalized path
.tst.instrumentFile:{[pathStr]
    if[not .tst.coverageEnabled; :()];

    absPath: .tst.resolvePath pathStr;
    fileSym: `$absPath;
    .tst.ensureCoverageEntry[fileSym];

    fHandle: hsym (`$":" , absPath);
    if[() ~ key fHandle; :()];

    fns: @[.tst.static.exploreFile; fHandle; {() }];
    if[not 98h = type fns; :()];
    if[0 = count fns; :()];

    {[fs;row] .tst.wrapFunc[row`name; fs]}[fileSym] each fns;
 };

/ Load and instrument a source file explicitly
.tst.loadSource:{[file]
    pathStr: .tst.resolvePath file;

    if[pathStr in .tst.loadingStack; :()];
    .tst.loadingStack,: enlist pathStr;

    @[system; "l ", pathStr; {[e]
        .tst.loadingStack:: -1 _ .tst.loadingStack;
        'e
    }];

    .tst.instrumentFile pathStr;
    .tst.loadingStack:: -1 _ .tst.loadingStack;
 };

/ Instrument already-loaded .q files once coverage is enabled
.tst.instrumentLoadedFiles:{[]
    if[not `utl in key `.; :()];
    if[not `loaded in key `.utl; :()];

    loaded: .utl.loaded;
    if[0 = count loaded; :()];

    files: loaded where (loaded like "*.q") and not loaded like "*coverage.q";
    files: files where 0 < count each files;

    { .tst.instrumentFile .tst.resolvePath x } each files;
 };

/ Initialize coverage and instrument already-loaded files
.tst.initCoverage:{[files]
    fs: $[10h = type files; enlist `$files; files];
    .tst.trackedFiles:: fs;
    .tst.coverageData:: ()!();
    .tst.origFuncs:: ()!();
    .tst.loadingStack:: ();
    .tst.coverageEnabled:: 1b;

    {[f] .tst.ensureCoverageEntry f} each fs;

    / Wrap what is already loaded so coverage has a chance to observe calls
    .tst.instrumentLoadedFiles[];

    -1 "Coverage tracking initialized.";
 };

/ Build LCOV records for a file
.tst._lcovFileRecords:{[fileSym]
    fData: $[fileSym in key .tst.coverageData; .tst.coverageData[fileSym]; ()!()];

    pathStr: string fileSym;
    pathStr: $[pathStr like ":*"; 1 _ pathStr; pathStr];
    fHandle: hsym (`$":" , pathStr);

    fns: @[.tst.static.exploreFile; fHandle; {([] name:`$(); line:`int$())}];
    if[not 98h = type fns; fns: ([] name:`$(); line:`int$())];

    fnLines: ();
    i: 0;
    do[count fns;
        row: fns i;
        nm: row`name;
        ln: row`line;
        hit: $[nm in key fData; fData[nm]; 0];
        fnLines,: "FN:", string ln, ",", string nm;
        fnLines,: "FNDA:", string hit, ",", string nm;
        i+: 1;
    ];

    hitCount: sum (value fData) > 0;

    sfLine: "SF:", pathStr;
    fnfLine: "FNF:", string count fns;
    fnhLine: "FNH:", string hitCount;

    recs: enlist sfLine;
    j: 0;
    do[count fnLines;
        recs,: fnLines j;
        j+: 1;
    ];
    recs,: fnfLine;
    recs,: fnhLine;
    recs,: "end_of_record";
    recs
 };

/ Generate LCOV Report
.tst.generateLCOV:{[outFile]
    if[not .tst.coverageEnabled; '"Coverage not enabled"];

    outPath: .tst.resolvePath outFile;
    outH: hsym (`$":" , outPath);

    / Ultra-defensive LCOV writer: avoid adverbs and build line-by-line.
    txt: "TN:resq\n";
    files: key .tst.coverageData;

    i: 0;
    do[count files;
        fileSym: files i;
        pathStr: string fileSym;
        if[pathStr like ":*"; pathStr: 1 _ pathStr];

        fData: .tst.coverageData[fileSym];
        fHandle: hsym (`$":" , pathStr);
        fns: @[.tst.static.exploreFile; fHandle; {([] name:`$(); line:`int$())}];
        if[not 98h = type fns; fns: ([] name:`$(); line:`int$())];

        sfLine: "SF:";
        sfLine,: pathStr;
        sfLine,: "\n";
        txt,: sfLine;

        fnCount: count fns;
        hitFn: 0;
        j: 0;
        do[fnCount;
            row: fns j;
            nm: row`name;
            ln: row`line;

            hit: 0;
            if[nm in key fData; hit: fData[nm]];
            if[hit > 0; hitFn+: 1];

            nmStr: .tst._covNameStr nm;
            lnStr: .tst._covNumStr ln;
            hitStr: .tst._covNumStr hit;

            fnLine: "FN:";
            fnLine,: lnStr;
            fnLine,: ",";
            fnLine,: nmStr;
            fnLine,: "\n";

            fndaLine: "FNDA:";
            fndaLine,: hitStr;
            fndaLine,: ",";
            fndaLine,: nmStr;
            fndaLine,: "\n";

            txt,: fnLine;
            txt,: fndaLine;

            j+: 1;
        ];

        fnfLine: "FNF:";
        fnfLine,: .tst._covNumStr fnCount;
        fnfLine,: "\n";

        fnhLine: "FNH:";
        fnhLine,: .tst._covNumStr hitFn;
        fnhLine,: "\n";

        txt,: fnfLine;
        txt,: fnhLine;
        txt,: "end_of_record\n";

        i+: 1;
    ];

    / Persist raw coverage state alongside the LCOV file.
    idx: (count outPath) - (reverse outPath) ? "/";
    dir: $[idx=0; "."; idx # outPath];
    stateFile: dir, "/coverage_state.txt";
    stateH: hsym (`$":" , stateFile);
    stateH 0: enlist -3! .tst.coverageData;

    outH 0: enlist txt;
    -1 "LCOV report written to: ", outPath;
    outPath
 };

/ Generate a simple HTML summary
.tst.generateHTML:{[outFile]
    if[not .tst.coverageEnabled; '"Coverage not enabled"];

    outPath: .tst.resolvePath outFile;
    outH: hsym (`$":" , outPath);

    html: "<!DOCTYPE html><html><head><title>resQ Coverage</title></head><body>";
    html,: "<h1>resQ Coverage</h1>";
    html,: "<p>Raw coverage state written to coverage_state.txt</p>";
    html,: "</body></html>";
    outH 0: enlist html;
    -1 "HTML report written to: ", outPath;
    outPath
 };
