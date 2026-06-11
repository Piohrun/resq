/ Runtime coverage module (instrumentation reintroduced, load-safe)
.utl.require .utl.PKGLOADING,"/static_analysis.q"

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

/ Resolve a (possibly dotted, possibly namespaced) name to its value, returning
/ the `.tst._covMissing` sentinel when the name is unbound. The previous walk
/ gated on `nsSym in key \`.`, which is false for dotted CHILD namespaces
/ (e.g. \`.user.create lives under \`.user, not \`.), so it rejected every
/ \`.ns.func and wrapped nothing. A trapped `get` resolves any bound name -
/ root, namespaced, or nested - and the lambda handler keeps the sentinel
/ contract for unbound names. (\`get\` SIGNALS on an unknown name; the trap is
/ mandatory and its handler MUST be a lambda - \`@[f;x;e]\` requires it.)
.tst.safeValue:{[sym] @[get; sym; {[e] .tst._covMissing}] };

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

/ Generic wrapper for any function
/ @param f (function) Original function
/ @param fileSym (symbol) Source file
/ @param name (symbol) Function name
/ @param args (list) Arguments passed to the function
.tst.genericWrapper:{[f;fileSym;name;args]
    .tst.recordExecution[fileSym;name];
    f . args
 };
/ @param name (symbol) Function name (e.g. `.user.create`)
/ @param fileSym (symbol) Source file symbol
.tst.wrapFunc:{[name;fileSym]
    / Skip coverage internals and already-wrapped names
    if[name in .tst.coverageSkipNames; :()];
    if[name in key .tst.origFuncs; :()];

    orig: .tst.safeValue name;
    if[orig ~ .tst._covMissing; :()];
    
    / Handle potential projections or lists with metadata
    if[0h = type orig; orig: first orig];
    
    if[not type[orig] within (100h;104h); :()];

    / Introspect the original to recover its argument names so the wrapper can
    / forward them positionally. `value[f] 1` resolves BOTH explicit ({[x;y]..})
    / and implicit ({x+y} -> `x`y) lambdas to their canonical arg names, so the
    / rebuilt {[x;y] ...} preserves the original rank and call semantics. But it
    / SIGNALS 'type for compiled operators/derived functions (102h/103h), which
    / pass the type guard above; trap it and skip rather than crash. The handler
    / must be a lambda (q's @[f;x;e] requires it).
    args: @[{value[x] 1}; orig; {(::)}];
    if[args ~ (::); :()];

    .tst.origFuncs[name]: orig;

    argStr: $[0 < count args; ";" sv string args; ""];
    callArgs: "[", argStr, "]";

    / The recorded file key MUST equal the symbol ensureCoverageEntry / the LCOV
    / writer use (\`$absPath, NO ":" prefix). recordExecution does `\`$file` for a
    / string arg, so embed the path as an ESCAPED STRING LITERAL and let it
    / symbol-ize - identical to \`$absPath. A backtick-symbol literal can't be
    / used here: a path starts with "/", and `\`/tmp/x` does not parse as a
    / symbol. (The previous code wrote `hsym "..."`, producing \`:absPath, so
    / hits landed under a key the report never read - always-empty coverage.)
    pathLit: ssr[ssr[string fileSym; "\\"; "\\\\"]; "\""; "\\\""];
    wrapperCode: raze ("{"; callArgs;
        " .tst.recordExecution[\"", pathLit, "\";`"; string name; " ];";
        " .tst.origFuncs[`"; string name; " ]"; callArgs;
        " }");

    / Parse the wrapper text; a failure here (exotic arg names, etc.) must leave
    / the original definition untouched, so trap it and bail.
    wrapFn: @[value; wrapperCode; {(::)}];
    if[wrapFn ~ (::); .tst.origFuncs _: name; :()];

    / Install the wrapper. MUST use the .[set;args;h] (dot-apply) trap form, not
    / @[set;args;h]: `set` is dyadic, and @[f;x;e] applies it MONADICALLY to the
    / 2-list - a no-op that silently leaves the original in place (and so wrapped
    / nothing, the deepest cause of the empty-coverage bug). .[set;(name;val);h]
    / applies both args.
    .[set; (name; wrapFn); {[n;e]
        -1 "Coverage wrap failed for ", string n, ": ", .Q.s1 e;
        :()
    }[name]];
 };

/ Instrument a loaded file (analyze and wrap functions)
/ @param pathStr (string) Absolute normalized path
.tst.instrumentFile:{[pathStr]
    if[not .tst.coverageEnabled; :()];

    absPath: .tst.resolvePath pathStr;
    
    / Apply --cov-include / --cov-exclude filters.
    if[`coverageInclude in key `.tst.app;
        if[0 < count .tst.app.coverageInclude;
            if[not any absPath like/: .tst.app.coverageInclude; :()]
        ]
    ];
    if[`coverageExclude in key `.tst.app;
        if[any absPath like/: .tst.app.coverageExclude; :()]
    ];
    
    fileSym: `$absPath;
    .tst.ensureCoverageEntry[fileSym];

    fHandle: hsym (`$":" , absPath);
    if[() ~ key fHandle; :()];

    fns: @[.tst.static.exploreFile; fHandle; {() }];
    if[not 98h = type fns; :()];
    if[0 = count fns; :()];

    / exploreFile applies `\d <ns>` namespacing, but NOT the runtime
    / `system "d <ns>"` form some sources use to open a namespace - those
    / functions are returned BARE (e.g. `create` for a fn that actually loaded
    / as `.user.create`), so wrapping the bare name finds nothing. Re-derive the
    / runtime-`d` namespace active at each function's line and qualify any bare
    / name accordingly, so the wrapped (and recorded) name matches the loaded
    / definition and the LCOV report. Names exploreFile already qualified (`.*`)
    / are left as-is.
    lines: @[read0; fHandle; {()}];
    nsAt: .tst.coverageSysDNamespaces lines;
    {[fs;nsAt;row]
        nm: row`name;
        nm: .tst.coverageQualifyName[nsAt; row`line; nm];
        .tst.wrapFunc[nm; fs]
    }[fileSym; nsAt] each fns;
 };

/ Build a per-line active-namespace vector from a file's `system "d <ns>"`
/ directives (the runtime equivalent of `\d <ns>`). Returns a list of strings,
/ one per source line, giving the namespace string ("" at root, ".user", ...)
/ in effect ON that line. `system "d ."` / `system "d \`."` resets to root.
.tst.coverageSysDNamespaces:{[lines]
    {[acc;ln]
        cur: last acc;
        t: trim ln;
        / Match a `system "d <ns>"` directive and pull <ns> from between the two
        / double-quotes. "d ." / "d `." reset to root.
        if[t like "system \"d *";
            q1: t ? "\"";
            rest: (q1+1) _ t;
            q2: rest ? "\"";
            arg: trim q2 # rest;                / e.g. "d .user"
            if[arg like "d *";
                ns: trim 2 _ arg;
                ns: $[ns like "`*"; 1 _ ns; ns]; / tolerate `.user spelling
                cur: $[(ns ~ ".") or (0 = count ns); ""; ns];
            ];
        ];
        acc, enlist cur
    }/[enlist ""; lines]
 };

/ Qualify a bare function name with the runtime-`d` namespace active at `line`
/ (1-based, as exploreFile reports). Already-dotted names pass through.
.tst.coverageQualifyName:{[nsAt;line;name]
    s: string name;
    if[s like ".*"; :name];                 / already namespaced
    idx: line - 1;                          / nsAt is 0-based per source line
    if[(idx < 0) or idx >= count nsAt; :name];
    ns: nsAt idx;
    if[0 = count ns; :name];
    `$ns, ".", s
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

    / Qualify bare names from runtime `system "d <ns>"` modules so the lookup
    / matches the recorded (loaded) names - same correction as generateLCOV.
    srcLines: @[read0; fHandle; {()}];
    nsAt: .tst.coverageSysDNamespaces srcLines;

    fnLines: ();
    i: 0;
    do[count fns;
        row: fns i;
        nm: .tst.coverageQualifyName[nsAt; row`line; row`name];
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

        / exploreFile reports BARE names for functions opened with a runtime
        / `system "d <ns>"` (it only honours `\d`); hits, however, were recorded
        / under the QUALIFIED name (see instrumentFile). Re-derive the same
        / namespace map so the FN:/FNDA: lines and the hit lookup use the loaded
        / name, otherwise every FNDA stays 0 for system-`d` modules.
        srcLines: @[read0; fHandle; {()}];
        nsAt: .tst.coverageSysDNamespaces srcLines;

        sfLine: "SF:";
        sfLine,: pathStr;
        sfLine,: "\n";
        txt,: sfLine;

        fnCount: count fns;
        hitFn: 0;
        j: 0;
        do[fnCount;
            row: fns j;
            nm: .tst.coverageQualifyName[nsAt; row`line; row`name];
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
    / Persist the FULL coverage dict, one "file func count" line per record.
    / `-3!` of the whole dict was truncated by q's display width ("..."), losing
    / data; an explicit per-entry dump is complete and grep-friendly.
    stateLines: ();
    sf: 0;
    do[count files;
        fsym: files sf;
        fpath: string fsym;
        if[fpath like ":*"; fpath: 1 _ fpath];
        fd: .tst.coverageData[fsym];
        fnames: key fd;
        k: 0;
        do[count fnames;
            stateLines,: enlist fpath, " ", (.tst._covNameStr fnames k), " ", .tst._covNumStr fd fnames k;
            k+: 1;
        ];
        sf+: 1;
    ];
    stateH 0: stateLines;

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

    / Render a real per-file table of functions and their hit counts (covered =
    / hits>0, otherwise uncovered) rather than a placeholder. Names and lookups
    / use the same `system "d"`/`\d` qualification as the LCOV writer.
    files: key .tst.coverageData;
    f: 0;
    do[count files;
        fileSym: files f;
        pathStr: string fileSym;
        if[pathStr like ":*"; pathStr: 1 _ pathStr];
        fData: .tst.coverageData[fileSym];
        fHandle: hsym (`$":" , pathStr);
        fns: @[.tst.static.exploreFile; fHandle; {([] name:`$(); line:`int$())}];
        if[not 98h = type fns; fns: ([] name:`$(); line:`int$())];
        srcLines: @[read0; fHandle; {()}];
        nsAt: .tst.coverageSysDNamespaces srcLines;

        covered: 0;
        rowsHtml: "";
        j: 0;
        do[count fns;
            row: fns j;
            nm: .tst.coverageQualifyName[nsAt; row`line; row`name];
            hit: $[nm in key fData; fData[nm]; 0];
            if[hit > 0; covered+: 1];
            cls: $[hit > 0; "covered"; "uncovered"];
            rowsHtml,: "<tr class=\"", cls, "\"><td>", (.tst._covNameStr nm),
                "</td><td>", (.tst._covNumStr row`line),
                "</td><td>", (.tst._covNumStr hit), "</td></tr>";
            j+: 1;
        ];

        html,: "<h2>", pathStr, "</h2>";
        html,: "<p>", (.tst._covNumStr covered), " / ", (.tst._covNumStr count fns), " functions covered</p>";
        html,: "<table border=\"1\"><thead><tr><th>Function</th><th>Line</th><th>Hits</th></tr></thead><tbody>";
        html,: rowsHtml;
        html,: "</tbody></table>";
        f+: 1;
    ];

    html,: "<p>Raw coverage state written to coverage_state.txt</p>";
    html,: "</body></html>";
    outH 0: enlist html;
    -1 "HTML report written to: ", outPath;
    outPath
 };
