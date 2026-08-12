/ coverage.q - runtime coverage instrumentation and LCOV/HTML reporting (load-safe)
.utl.require .utl.PKGLOADING,"/static_analysis.q"
/ For .tst.bracketDelta, used to find where a function definition closes.
/ .utl.require is idempotent, so this is a no-op in a normal run (init.q has
/ already loaded it) and a real load when coverage.q is pulled in on its own.
.utl.require .utl.PKGLOADING,"/loader.q"

/ State
.tst.coverageData: ()!();        / file -> func -> count
.tst.coverageEnabled: 0b;
.tst.trackedFiles: ();
.tst.origFuncs: ()!();           / name -> original function
.tst.lastCoverageSummary: `linesFound`linesHit`linePercent`functionsFound`functionsHit`functionPercent!(0j;0j;0f;0j;0j;0f);
.tst.lastCoverageModel: ()!();
.tst.covWrappers: ()!();         / name -> installed wrapper (live identity)
.tst.coverageLoadedFiles: `symbol$(); / files observed by the runtime loader
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
/ Trapped assignment, used to put an original definition back when
/ statement instrumentation is abandoned.
.tst.safeSet:{[sym;val] @[set; (sym; val); {[e] }]; };

.tst.ensureCoverageEntry:{[fileSym]
    if[not fileSym in key .tst.coverageData;
        .tst.coverageData[fileSym]: ()!();
        .tst.trackedFiles,: fileSym;
    ];
 };

/ Apply include/exclude rules consistently to both statically inventoried files
/ and files observed at runtime. `explicit` means the user named a source root;
/ that is authoritative and may intentionally include resQ's own lib directory.
.tst.coveragePathIncluded:{[absPath;explicit]
    includes: @[get; `.tst.app.coverageInclude; {()}];
    excludes: @[get; `.tst.app.coverageExclude; {()}];
    if[count includes; if[not any absPath like/: includes; :0b]];
    if[count excludes; if[any absPath like/: excludes; :0b]];
    if[(not explicit) and 0=count includes;
        home: @[get; `.resq.HOME; {""}];
        if[(0<count home) and absPath like home,"/lib/*"; :0b]];
    1b
 };

/ Why a discovered function lacks measured statements. This is derived from
/ canonical runtime state so every reporter uses the same classification.
.tst.coverageFallbackReason:{[fileSym;name]
    if[not 1b~@[get;`.tst.coverageStatements;0b]; :`statement_mode_disabled];
    if[not fileSym in .tst.coverageLoadedFiles; :`source_not_loaded];
    if[not name in key .tst.covWrappers; :`function_wrapper_unavailable];
    measured:$[fileSym in key .tst.stmtInstrumented;
        .tst.stmtInstrumented fileSym;`symbol$()];
    $[name in measured;`none;`rewrite_rejected]
 };

/ Aggregate instrumentation eligibility/completeness. Function coverage counts
/ every static function; statement completeness counts how many of those same
/ functions were safely rewritten with real probes.
.tst.coverageInstrumentationSummary:{[]
    files:key .tst.coverageData;
    found:sum 0,count each value .tst.coverageData;
    wrapped:sum 0,{[d] sum (key d) in key .tst.covWrappers} each value .tst.coverageData;
    measured:sum 0,{[f;d]
        names:$[f in key .tst.stmtInstrumented;.tst.stmtInstrumented f;`symbol$()];
        sum (key d) in names
    }'[files;value .tst.coverageData];
    loaded:sum 0,files in .tst.coverageLoadedFiles;
    filesMeasured:sum 0,{[f] $[f in key .tst.stmtInstrumented;
        0<count .tst.stmtInstrumented f;0b]} each files;
    stmtMode:1b~@[get;`.tst.coverageStatements;0b];
    fnPct:$[0=found;0f;100f*wrapped%found];
    stmtPct:$[0=found;0f;100f*measured%found];
    reasons:raze {[f;d] .tst.coverageFallbackReason[f;] each key d}'[
        files;value .tst.coverageData];
    reasonNames:`statement_mode_disabled`source_not_loaded`function_wrapper_unavailable`rewrite_rejected;
    reasonCounts:reasonNames!{[allReasons;reason] sum 0,allReasons=reason}[
        reasons;] each reasonNames;
    `filesFound`filesLoaded`filesWithStatements`functionsEligible`functionsInstrumented`functionInstrumentationPercent`statementMode`statementFunctionsEligible`statementFunctionsInstrumented`statementInstrumentationPercent`statementInstrumentationComplete`fallbackCounts!(
        count files;loaded;filesMeasured;found;wrapped;fnPct;stmtMode;found;measured;stmtPct;stmtMode and found=measured;reasonCounts)
 };

/ Resolve explicit roots to the canonical set of source files. Empty or invalid
/ declarations fail closed: a typo must not produce a green 0/0 coverage run.
.tst.coverageManifest:{[roots]
    rs: $[10h=type roots; enlist roots;
          -11h=type roots; enlist string roots;
          11h=type roots; string each roots;
          0h=type roots; {$[10h=type x;x;string x]} each roots;
          ()];
    if[0=count rs; '"Coverage source manifest is empty"];
    discovered: raze {[root]
        absRoot: .tst.resolvePath root;
        .tst.static.findSources absRoot
    } each rs;
    paths: distinct .tst.resolvePath each string each discovered;
    paths: paths where .tst.coveragePathIncluded[;1b] each paths;
    if[0=count paths;
        '"Coverage source manifest matched 0 .q files: ", ", " sv rs];
    `$paths
 };

/ Seed every statically discoverable function at zero before tests load code.
/ Runtime wrappers increment these same keys, making the source manifest the
/ denominator rather than the accidental set of modules a test happened to load.
.tst.seedCoverageFile:{[file]
    absPath: .tst.resolvePath file;
    fileSym: `$absPath;
    .tst.ensureCoverageEntry fileSym;
    fHandle: hsym (`$":" , absPath);
    fns: @[.tst.static.exploreFile; fHandle; {([] name:`$(); line:`int$())}];
    if[not 98h=type fns; :()];
    srcLines: @[read0; fHandle; {()}];
    nsAt: .tst.coverageSysDNamespaces srcLines;
    {[fs;namespaces;row]
        nm: .tst.coverageQualifyName[namespaces;row`line;row`name];
        if[not nm in key .tst.coverageData fs;
            .tst.coverageData[fs;nm]: 0j]
    }[fileSym;nsAt] each fns;
    ::
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

/ @param name (symbol) Function name (e.g. `.user.create`)
/ @param fileSym (symbol) Source file symbol
.tst.wrapFunc:{[name;fileSym]
    / Skip coverage internals.
    if[name in .tst.coverageSkipNames; :()];

    / Already-wrapped guard, RELOAD-AWARE. The old guard skipped on mere name
    / membership in .tst.origFuncs, so after a file reload (which installs a
    / fresh UNWRAPPED definition) re-instrumenting was a no-op: the name was
    / still registered, the live function stayed unwrapped, and hits were zero.
    / Instead compare the LIVE value to the wrapper we installed (kept in
    / covWrappers). `~` on lambdas is structural and each wrapper embeds its own
    / name, so wrappers for different names differ - a true identity test.
    /   - live value IS our wrapper  -> already instrumented, skip.
    /   - name registered but live value differs (reload) -> fall through,
    /     re-capture the fresh live value as orig below, and re-wrap.
    if[name in key .tst.covWrappers;
        if[(.tst.safeValue name) ~ .tst.covWrappers name; :()];
    ];

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
    / applies both args. On failure, drop the half-registered entries so a later
    / re-instrument retries cleanly.
    ok: .[{[n;w] set[n; w]; 1b}; (name; wrapFn); {[n;e]
        -1 "Coverage wrap failed for ", string n, ": ", .Q.s1 e;
        0b
    }[name]];
    if[not ok; .tst.origFuncs _: name; :()];

    / Record the installed wrapper's identity so the reload-aware guard above can
    / tell "still our wrapper" from "reloaded behind our back".
    .tst.covWrappers[name]: wrapFn;
 };

/ Instrument a loaded file (analyze and wrap functions)
/ @param pathStr (string) Absolute normalized path
.tst.instrumentFile:{[pathStr]
    if[not .tst.coverageEnabled; :()];

    absPath: .tst.resolvePath pathStr;
    
    if[not .tst.coveragePathIncluded[absPath;0b]; :()];


    fileSym: `$absPath;
    .tst.ensureCoverageEntry[fileSym];

    fHandle: hsym (`$":" , absPath);
    if[() ~ key fHandle; :()];

    fns: @[.tst.static.exploreFile; fHandle; {() }];
    if[not 98h = type fns; :()];
    if[0 = count fns; :()];
    .tst.coverageLoadedFiles: distinct .tst.coverageLoadedFiles,fileSym;

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

    / Statement probes go in BEFORE the function wrapper, so the wrapper closes
    / over the instrumented body. Each attempt is independent: a function that
    / cannot be rewritten safely simply keeps derived line records.
    starts: "j"$ $[`line in cols fns; fns`line; `long$()];
    starts: starts where not null starts;
    if[1b ~ @[get; `.tst.coverageStatements; 0b];
        {[fs; nsAt; srcLines; starts; row]
            nm: .tst.coverageQualifyName[nsAt; row`line; row`name];
            span: .tst.covFunctionSpan[srcLines; row`line; starts];
            if[span[1] >= span[0];
                / Trapped per function: a rewrite that throws must cost only this
                / function its statement data, never abort instrumentation of the
                / rest of the file (or, via the caller, of every later file).
                okStmt: @[.tst.covInstrumentStatements[nm; fs; srcLines; span 0;]; span 1; {[e] 0b}];
                if[1b ~ okStmt;
                    d: $[fs in key .tst.stmtInstrumented; .tst.stmtInstrumented fs; `symbol$()];
                    .tst.stmtInstrumented[fs]: distinct d, nm];
            ];
        }[fileSym; nsAt; lines; starts] each fns;
    ];

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

/ Load a .q file by absolute path, tolerating spaces in the path.
/ q's `\l` (system "l ...") cannot parse a path containing spaces - it splits on
/ whitespace and raises 'nyi. The portable workaround is to chdir into the file's
/ directory (q's `system "cd <dir>"` IS the supported way to chdir the q process,
/ and it does accept a spaced directory) and `\l` the bare basename, then restore
/ the previous working directory. The cwd is restored on BOTH success and error.
.tst.coverageLoadFile:{[pathStr]
    .utl.loadQFile pathStr
 };

/ Load and instrument a source file explicitly
.tst.loadSource:{[file]
    pathStr: .tst.resolvePath file;

    if[pathStr in .tst.loadingStack; :()];
    .tst.loadingStack,: enlist pathStr;

    @[.tst.coverageLoadFile; pathStr; {[e]
        .tst.loadingStack:: -1 _ .tst.loadingStack;
        'e
    }];

    .tst.instrumentFile pathStr;
    .tst.loadingStack:: -1 _ .tst.loadingStack;
 };

/ Instrument already-loaded .q files once coverage is enabled
.tst.instrumentLoadedFiles:{[]
    / `utl in key `.` is ALWAYS false: q's root key list does not report child
    / namespaces (`key `.` is empty even when .utl exists, while `key `.utl`
    / works). This guard therefore returned before instrumenting anything, so
    / coverage only ever saw files loaded through .tst.sysl (\l) and nothing
    / loaded via .utl.require. Probe the variable itself instead.
    loaded: @[get; `.utl.loaded; {()}];
    if[0 = count loaded; :()];

    files: loaded where (loaded like "*.q") and not loaded like "*coverage.q";
    files: files where 0 < count each files;

    / Trapped per file for the same reason: one unreadable or unparseable source
    / must not stop the remaining files being instrumented.
    { @[.tst.instrumentFile; .tst.resolvePath x; {[p;e]
          -1 "Coverage: could not instrument ", p, ": ", .tst.toString e
        }[.tst.resolvePath x]] } each files;
 };

/ Initialize coverage and instrument already-loaded files
.tst.initCoverage:{[files]
    raw: $[10h=type files; enlist files;
           -11h=type files; enlist string files;
           11h=type files; string each files;
           0h=type files; {$[10h=type x;x;string x]} each files;
           ()];
    fs: `$distinct .tst.resolvePath each raw;
    .tst.trackedFiles:: `symbol$();
    .tst.coverageData:: ()!();
    .tst.origFuncs:: ()!();
    .tst.covWrappers:: ()!();
    .tst.coverageLoadedFiles:: `symbol$();
    .tst.lastCoverageModel:: ()!();
    .tst.loadingStack:: ();
    .tst.lineCoverageData:: ()!();
    .tst.stmtInstrumented:: ()!();
    .tst.stmtProbeLines:: ()!();
    .tst.coverageEnabled:: 1b;

    .tst.seedCoverageFile each fs;

    / Wrap what is already loaded so coverage has a chance to observe calls
    .tst.instrumentLoadedFiles[];

    -1 "Coverage tracking initialized.";
 };

/ Lines that carry executable code, as a boolean per source line. Masking blanks
/ out comments, strings and block comments first, so a comment-only or blank line
/ is never counted as coverable.
.tst.coverableLines:{[srcLines]
    if[0 = count srcLines; :`boolean$()];
    / Fall back to the raw lines if masking is unavailable or changes the line
    / count; a comment-only line then still fails the trim test below only if it
    / is genuinely blank, which is the safe direction (over-counting coverable
    / lines understates coverage rather than overstating it).
    masked: @[.tst.static.maskLines; srcLines; {[e] `maskFailed}];
    if[not (0h = type masked) and (count masked) = count srcLines;
        masked: srcLines];
    {0 < count trim x} each masked
 };

/ Source lines a function spans: (startLine; endLine). exploreFile flattens a
/ function's body to a single line, so height cannot come from there -- a
/ function instead runs to the line before the next function starts, and the
/ last one to end of file. Blank and comment lines in that range are filtered
/ out by the caller, so trailing gaps between functions do not inflate the count.
.tst.functionLineSpan:{[startLine; allStarts; totalLines]
    st: "j"$ startLine;
    if[(null st) or st < 1; :(0j; -1j)];
    later: allStarts where allStarts > st;
    endLine: $[count later; (min later) - 1; totalLines];
    if[endLine > totalLines; endLine: totalLines];
    (st; endLine)
 };

/ The last line of a function DEFINITION, found by balancing brackets from its
/ first line. `maxEnd` is the search bound from .tst.functionLineSpan.
/ .
/ The bound alone is too generous: it stops at the line before the NEXT
/ definition, so the last function in a file absorbed everything after it. For
/ the common `\d .` footer that meant the statement rewriter tried to `value` a
/ system command, which it cannot -- the rewrite was rejected and the file's last
/ function silently lost its line records while still reporting FN:/FNDA:. The
/ same over-reach would have swallowed any top-level statement sitting between
/ two definitions, probing it and re-running it at instrumentation time.
/ .
/ Fails open to `maxEnd` when the brackets never balance (an unterminated
/ definition, or a body extending past the bound), preserving the old behaviour
/ for anything this cannot parse.
.tst.covDefinitionEnd:{[srcLines; startLine; maxEnd]
    if[startLine < 1; :maxEnd];
    if[maxEnd > count srcLines; :maxEnd];
    delta: @[get; `.tst.bracketDelta; {::}];
    if[not (type delta) within 100 104h; :maxEnd];
    depth: 0;
    i: startLine;
    while[i <= maxEnd;
        depth+: delta srcLines[i - 1];
        if[depth <= 0; :i];
        i+: 1];
    maxEnd
 };

/ Span of a function definition: the search bound, tightened to where the
/ definition actually closes.
.tst.covFunctionSpan:{[srcLines; startLine; allStarts]
    span: .tst.functionLineSpan[startLine; allStarts; count srcLines];
    if[span[1] < span[0]; :span];
    (span 0; .tst.covDefinitionEnd[srcLines; span 0; span 1])
 };

/ ---------------------------------------------------------------------------
/ Statement-level instrumentation.
/ .
/ Function-level wrapping cannot say WHICH lines of a called function ran, so
/ line records derived from it read as covered even for a branch that never
/ executed. Real per-line data needs a probe on each statement, which means
/ rewriting the function's source at load time -- a transformation on the user's
/ own code. It is therefore attempted per function and abandoned per function:
/ any parse failure, rank change or exception restores the original definition
/ and that function falls back to derived lines. Correctness of the code under
/ test always wins over resolution of the report.
/ ---------------------------------------------------------------------------

/ line -> hit count, per file. Separate from coverageData (function hits).
.tst.lineCoverageData: ()!();
/ Files whose lines are genuinely MEASURED (not derived), per function name.
.tst.stmtInstrumented: ()!();
/ Lines carrying a probe, per file -- the denominator for measured coverage.
.tst.stmtProbeLines: ()!();

.tst.covL:{[f;n]
    d: $[f in key .tst.lineCoverageData; .tst.lineCoverageData f; (`long$())!`long$()];
    d[n]: 1 + $[n in key d; d n; 0];
    .tst.lineCoverageData[f]: d;
 };

/ Split a function body into top-level statements, returning the source line
/ each one starts on. Depth-, string- and comment-aware.
/ Statements nested in `if[...]`, `do[...]` and `while[...]` count too: those
/ forms evaluate every argument after the first, so each is a real statement and
/ q guard clauses (`if[bad; :error]`) are exactly what needs measuring.
/ `$[...]` is deliberately NOT descended into -- it is a conditional EXPRESSION
/ whose branches are values, and probing there would change what it returns.
.tst.covStatementPositions:{[bodyLines]
    depth: 0; inStr: 0b; esc: 0b;
    atStart: 1b;
    stmtDepths: enlist 0;    / bracket depths that hold a statement LIST
    word: "";                / identifier immediately before the next "["
    starts: ();
    i: 0;
    while[i < count bodyLines;
        lineNo: bodyLines[i;0];
        / A one-character source line (a lone `}`) is a char ATOM, not a string.
        txt: (), bodyLines[i;1];
        j: 0;
        while[j < count txt;
            c: txt j;
            $[inStr;
                $[esc; esc: 0b; c = "\\"; esc: 1b; c = "\""; inStr: 0b; ::];
              c = "\"";
                [ inStr: 1b;
                  if[atStart and 0 = depth; starts,: lineNo; atStart: 0b] ];
              (c = "/") and ((j = 0) or txt[j-1] in " \t");
                j: count txt;
              c in "{([";
                [ if[atStart and depth in stmtDepths; starts,: enlist (lineNo; j); atStart: 0b];
                  depth+: 1;
                  / `if`/`do`/`while` open a statement list; anything else does not.
                  if[(c = "[") and word in ("if"; "do"; "while");
                      stmtDepths,: depth];
                  word: "" ];
              c in "})]";
                [ stmtDepths: stmtDepths except depth;
                  depth-: 1; if[depth < 0; depth: 0];
                  word: "" ];
              (c = ";") and depth in stmtDepths;
                [ atStart: 1b; word: "" ];
              c in " \t";
                word: "";
                [ if[atStart and depth in stmtDepths; starts,: enlist (lineNo; j); atStart: 0b];
                  word: $[c in .Q.a, .Q.A; word, c; ""] ]];
            j+: 1];
        i+: 1];
    distinct starts
 };

/ Backwards-compatible view: just the lines that begin a statement.
.tst.covStatementLines:{[bodyLines] distinct .tst.covStatementPositions[bodyLines][;0] };

/ Offset just past a lambda's opening `{` and optional `[params]`, i.e. where
/ the body begins on the definition's first line. Null when not a lambda open.
.tst.covBodyStart:{[txt]
    t: (), txt;
    b: t ? "{";
    if[b >= count t; :0N];
    k: b + 1;
    while[(k < count t) and t[k] in " \t"; k+: 1];
    if[(k < count t) and t[k] = "[";
        depth: 0;
        while[k < count t;
            $[t[k] = "["; depth+: 1; t[k] = "]"; depth-: 1; ::];
            k+: 1;
            if[depth = 0; :k]];
        :0N];
    b + 1
 };

/ Rewrite one function definition, inserting a probe at the start of every line
/ that begins a statement. Returns (newSourceText; probedLineNumbers), or `::`
/ when the shape is not one we will touch. The probed lines are returned rather
/ than recomputed later: the report must count exactly the lines that carry a
/ probe, and recomputing invites the two views drifting apart.
.tst.covRewriteFunction:{[srcLines; startLine; endLine; fileSym]
    if[(startLine < 1) or endLine > count srcLines; :(::)];
    idx: (startLine - 1) + til 1 + endLine - startLine;
    seg: srcLines idx;
    firstTxt: (), first seg;
    bodyAt: .tst.covBodyStart firstTxt;
    if[null bodyAt; :(::)];

    / Statement starts are computed over the BODY only: the signature's brackets
    / would otherwise be read as an open expression.
    bodyFirst: bodyAt _ firstTxt;
    bodyLines: enlist (startLine; bodyFirst);
    if[1 < count seg;
        bodyLines,: flip (startLine + 1 + til -1 + count seg; 1 _ seg)];
    / Positions, not just lines: a statement nested in `if[...]` must get its
    / probe INSIDE that bracket. Inserting at the start of the line would place
    / it in whatever encloses the line -- for `$[c; if[a;b:1]; ...]` that means
    / landing in the conditional expression's branch list and shifting every
    / branch, which silently changes what the expression returns.
    positions: .tst.covStatementPositions bodyLines;
    if[0 = count positions; :(::)];
    / Columns on the definition's first line are body-relative; shift them back.
    positions: {[b; st; p] $[p[0] = st; (p 0; b + p 1); p]}[bodyAt; startLine;] each positions;
    stmtLines: distinct positions[;0];

    / The file symbol is written as `$"..." -- a path contains slashes and a bare
    / backtick literal would not parse. Escape so any path survives embedding.
    pathTxt: string fileSym;
    pathTxt: ssr[ssr[pathTxt; "\\"; "\\\\"]; "\""; "\\\""];
    probeFor: {[p;n] ".tst.covL[`$\"", p, "\";", string[n], "];"}[pathTxt;];
    out: ();
    i: 0;
    while[i < count seg;
        lineNo: startLine + i;
        txt: (), seg i;
        / Insert from the rightmost column so earlier offsets stay valid.
        / NB: not `cols` -- that is a q keyword and assigning it signals 'assign.
        insCols: desc positions[;1] where positions[;0] = lineNo;
        newTxt: txt;
        j: 0;
        while[j < count insCols;
            c: insCols j;
            newTxt: (c # newTxt), probeFor[lineNo], c _ newTxt;
            j+: 1];
        out,: enlist newTxt;
        i+: 1];
    ("\n" sv out; stmtLines)
 };

/ Apply the rewrite to one function and prove it survived, or put the original
/ back. Returns 1b only when the instrumented definition is in place AND still
/ looks like the same function.
.tst.covInstrumentStatements:{[name; fileSym; srcLines; startLine; endLine]
    orig: .tst.safeValue name;
    if[not (type orig) within 100 104h; :0b];
    / q exposes a lambda's structure: [1] parameters, [2] locals, [3] the globals
    / it references. Comparing those before and after is a far stronger check
    / than "it still parses" -- a probe inserted somewhere that changes how a
    / name binds shows up as a different local or global set.
    origShape: 1 3 sublist value orig;   / (params; locals; globals)

    rw: @[.tst.covRewriteFunction[srcLines; startLine; endLine;]; fileSym; {[e] (::)}];
    if[(::) ~ rw; :0b];
    if[not 2 = count rw; :0b];
    newSrc: rw 0;
    probedLines: rw 1;
    if[not 10h = type newSrc; :0b];

    / The rewritten text already carries the definition verbatim, including the
    / name exactly as the source wrote it. Evaluate it in the same context the
    / file used, so unqualified references inside the body resolve as before:
    / a source that wrote `.calc.f:{...}` is evaluated at root; one that wrote
    / `f:{...}` under a `\d .calc` is evaluated with that namespace current.
    srcName: trim (newSrc ? ":") # newSrc;
    nm: string name;
    dotAt: (count nm) - (reverse nm) ? ".";
    ns: $[dotAt > 1; dotAt - 1; 0] # nm;
    evalNs: $[(0 < count srcName) and "." = first srcName; ""; ns];
    prevCtx: system "d";

    ok: @[{[a]
        if[count a 0; system "d ", a 0];
        value a 1;
        1b
      }; (evalNs; newSrc); {[e] 0b}];
    system "d ", string prevCtx;

    if[not ok; .tst.safeSet[name; orig]; :0b];

    / Same shape? A rewrite that parsed but changed the function's parameters,
    / locals, or which globals it binds has changed the function. Refuse it.
    now: .tst.safeValue name;
    if[not (type now) within 100 104h; .tst.safeSet[name; orig]; :0b];
    newShape: 1 3 sublist value now;
    / The probe itself is the one global legitimately added.
    newShape[2]: newShape[2] except `.tst.covL;
    if[not origShape ~ newShape; .tst.safeSet[name; orig]; :0b];

    / Remember which lines carry a probe, so the report counts exactly those.
    pl: $[fileSym in key .tst.stmtProbeLines; .tst.stmtProbeLines fileSym; `long$()];
    .tst.stmtProbeLines[fileSym]: asc distinct pl, "j"$ probedLines;
    1b
 };

/ Aggregate the standard LCOV summary records emitted below. Keeping the gate
/ based on the artifact itself guarantees that the percentage printed to users
/ is exactly what downstream coverage services will calculate.
.tst.lcovTotal:{[lines;prefix]
    matches: lines where lines like prefix,"*";
    if[0 = count matches; :0j];
    sum "J"$ {[n;line] n _ line}[count prefix;] each matches
 };

.tst.coverageSummaryFromLines:{[lines]
    linesFound: .tst.lcovTotal[lines;"LF:"];
    linesHit: .tst.lcovTotal[lines;"LH:"];
    functionsFound: .tst.lcovTotal[lines;"FNF:"];
    functionsHit: .tst.lcovTotal[lines;"FNH:"];
    linePercent: $[0 = linesFound; 0f; 100f * linesHit % linesFound];
    functionPercent: $[0 = functionsFound; 0f; 100f * functionsHit % functionsFound];
    `linesFound`linesHit`linePercent`functionsFound`functionsHit`functionPercent!(
        linesFound;linesHit;linePercent;functionsFound;functionsHit;functionPercent)
 };

/ ---------------------------------------------------------------------------
/ Canonical coverage model and renderers.
/ Every artifact below consumes this one immutable snapshot. This prevents an
/ LCOV denominator, JSON total, HTML table, or state dump from independently
/ rediscovering the source and silently disagreeing with another artifact.
/ ---------------------------------------------------------------------------

.tst.coverageStatementModel:{[hitMap;lineNo]
    hits:$[lineNo in key hitMap;"j"$hitMap lineNo;0j];
    `line`hits`covered!("j"$lineNo;hits;hits>0)
 };

.tst.coverageFunctionModel:{[fileSym;fData;srcLines;nsAt;starts;row]
    nm:.tst.coverageQualifyName[nsAt;row`line;row`name];
    hits:$[nm in key fData;"j"$fData nm;0j];
    measuredNames:$[fileSym in key .tst.stmtInstrumented;
        .tst.stmtInstrumented fileSym;`symbol$()];
    measured:nm in measuredNames;
    span:.tst.covFunctionSpan[srcLines;row`line;starts];
    probes:$[fileSym in key .tst.stmtProbeLines;
        .tst.stmtProbeLines fileSym;`long$()];
    inSpan:$[measured and span[1]>=span[0];
        probes where probes within (span 0;span 1);`long$()];
    hitMap:$[fileSym in key .tst.lineCoverageData;
        .tst.lineCoverageData fileSym;(`long$())!`long$()];
    statements:.tst.coverageStatementModel[hitMap;] each inSpan;
    statementHits:sum 0,{x`covered} each statements;
    reason:.tst.coverageFallbackReason[fileSym;nm];
    `name`line`hits`covered`functionEligible`functionInstrumented`statementEligible`statementInstrumented`fallbackReason`statementFound`statementHit`statements!(
        .tst._covNameStr[nm];"j"$row`line;hits;hits>0;1b;
        nm in key .tst.covWrappers;1b;measured;string reason;
        count statements;statementHits;statements)
 };

.tst.coverageFileModel:{[fileSym]
    path:string fileSym;
    if[path like ":*";path:1 _ path];
    fHandle:hsym (`$":" , path);
    staticFns:@[.tst.static.exploreFile;fHandle;{([] name:`$();line:`int$())}];
    if[not 98h=type staticFns;staticFns:([] name:`$();line:`int$())];
    srcLines:@[read0;fHandle;{()}];
    nsAt:.tst.coverageSysDNamespaces srcLines;
    starts:"j"$$[`line in cols staticFns;staticFns`line;`long$()];
    starts:starts where not null starts;
    fData:.tst.coverageData fileSym;
    fnRows:.tst.coverageFunctionModel[fileSym;fData;srcLines;nsAt;starts;] each staticFns;
    lineRows:raze {x`statements} each fnRows;
    functionHit:sum 0,{x`covered} each fnRows;
    lineHit:sum 0,{x`covered} each lineRows;
    measuredFns:sum 0,{x`statementInstrumented} each fnRows;
    `path`loaded`functionFound`functionHit`statementFunctionsInstrumented`lineFound`lineHit`functions`lines`sourceLines!(
        path;fileSym in .tst.coverageLoadedFiles;count fnRows;functionHit;
        measuredFns;count lineRows;lineHit;fnRows;lineRows;srcLines)
 };

.tst.coverageModel:{[]
    fileRows:.tst.coverageFileModel each key .tst.coverageData;
    fnFound:sum 0,{x`functionFound} each fileRows;
    fnHit:sum 0,{x`functionHit} each fileRows;
    lineFound:sum 0,{x`lineFound} each fileRows;
    lineHit:sum 0,{x`lineHit} each fileRows;
    base:`linesFound`linesHit`linePercent`functionsFound`functionsHit`functionPercent!(
        lineFound;lineHit;$[0=lineFound;0f;100f*lineHit%lineFound];
        fnFound;fnHit;$[0=fnFound;0f;100f*fnHit%fnFound]);
    instrumentation:.tst.coverageInstrumentationSummary[];
    `summary`files!(base,instrumentation;fileRows)
 };

.tst.coveragePublicFile:{[fileRow]
    publicKeys:(key fileRow) except `sourceLines;
    publicKeys!fileRow publicKeys
 };

.tst.coveragePublicModel:{[model]
    `summary`files!(model`summary;.tst.coveragePublicFile each model`files)
 };

.tst.coverageStateLines:{[model]
    lines:("# resQ coverage state v2";
        "# path function hits functionInstrumented statementInstrumented fallback");
    fileRows:model`files;
    i:0;
    do[count fileRows;
        fileRow:fileRows i;
        filePath:fileRow`path;
        funcs:fileRow`functions;
        j:0;
        do[count funcs;
            fn:funcs j;
            lines,:enlist filePath," ",(fn`name)," ",string[fn`hits]," ",
                string[fn`functionInstrumented]," ",
                string[fn`statementInstrumented]," ",fn`fallbackReason;
            j+:1];
        i+:1];
    lines
 };

.tst.writeCoverageState:{[model;outPath]
    idx:(count outPath)-(reverse outPath)?"/";
    dir:$[idx=0;".";idx#outPath];
    (hsym `$dir,"/coverage_state.txt") 0:.tst.coverageStateLines model;
    ::
 };

.tst.generateLCOV:{[outFile]
    if[not .tst.coverageEnabled;'"Coverage not enabled"];
    outPath:.tst.resolvePath outFile;
    model:.tst.coverageModel[];
    .tst.lastCoverageModel:model;
    txt:"TN:resq\n";
    fileRows:model`files;
    i:0;
    do[count fileRows;
        fileRow:fileRows i;
        filePath:fileRow`path;
        txt,:"SF:",filePath,"\n";
        funcs:fileRow`functions;
        j:0;
        do[count funcs;
            fn:funcs j;
            fnName:fn`name;
            txt,:"FN:",string[fn`line],",",fnName,"\n";
            txt,:"FNDA:",string[fn`hits],",",fnName,"\n";
            j+:1];
        lineRows:fileRow`lines;
        j:0;
        do[count lineRows;
            ln:lineRows j;
            txt,:"DA:",string[ln`line],",",string[ln`hits],"\n";
            j+:1];
        if[count lineRows;
            txt,:"LF:",string[fileRow`lineFound],"\n";
            txt,:"LH:",string[fileRow`lineHit],"\n"];
        txt,:"FNF:",string[fileRow`functionFound],"\n";
        txt,:"FNH:",string[fileRow`functionHit],"\nend_of_record\n";
        i+:1];
    .tst.writeCoverageState[model;outPath];
    .tst.lastCoverageSummary:model`summary;
    (hsym (`$":" , outPath)) 0:enlist txt;
    -1 "LCOV report written to: ",outPath;
    if[0=count fileRows;
        -1 "WARNING: coverage instrumented 0 functions - this report is empty.";
        -1 "         Declare the source inventory with --source src/.";
    ];
    outPath
 };

.tst.generateCoverageJSON:{[outFile]
    if[not .tst.coverageEnabled;'"Coverage not enabled"];
    outPath:.tst.resolvePath outFile;
    model:$[(99h=type .tst.lastCoverageModel) and `files in key .tst.lastCoverageModel;
        .tst.lastCoverageModel;.tst.coverageModel[]];
    public:.tst.coveragePublicModel model;
    payload:`schemaVersion`framework`frameworkVersion`summary`files!(
        1;"resQ";.tst.toString @[get;`.resq.VERSION;{"unknown"}];
        public`summary;public`files);
    (hsym (`$":" , outPath)) 0:enlist .j.j payload;
    -1 "Coverage JSON written to: ",outPath;
    outPath
 };

.tst.coverageHtmlEscape:{[text]
    s:.tst.toString text;
    s:ssr[s;"&";"&amp;"];
    s:ssr[s;"<";"&lt;"];
    s:ssr[s;">";"&gt;"];
    s:ssr[s;"\"";"&quot;"];
    s
 };

.tst.coverageFunctionHtml:{[fn]
    cls:$[fn`covered;"covered";"uncovered"];
    "<tr class=\"",cls,"\"><td>",.tst.coverageHtmlEscape[fn`name],
    "</td><td>",string[fn`line],"</td><td>",string[fn`hits],
    "</td><td>",string[fn`functionInstrumented],"</td><td>",
    string[fn`statementHit]," / ",string[fn`statementFound],
    "</td><td>",string[fn`statementInstrumented],"</td><td>",
    .tst.coverageHtmlEscape[fn`fallbackReason],"</td></tr>"
 };

.tst.coverageSourceHtml:{[fileRow]
    lineRows:fileRow`lines;
    numbers:{x`line} each lineRows;
    html:"<details><summary>Annotated source</summary><table><thead><tr><th>Line</th><th>Hits</th><th>Source</th></tr></thead><tbody>";
    i:0;
    do[count fileRow`sourceLines;
        lineNo:i+1;
        measured:lineNo in numbers;
        hits:$[measured;lineRows[numbers?lineNo]`hits;0j];
        cls:$[not measured;"unmeasured";hits>0;"covered";"uncovered"];
        hitText:$[measured;string hits;"not measured"];
        html,:"<tr class=\"",cls,"\"><td>",string[lineNo],"</td><td>",
            hitText,"</td><td><pre>",
            .tst.coverageHtmlEscape[(fileRow`sourceLines) i],"</pre></td></tr>";
        i+:1];
    html,"</tbody></table></details>"
 };

.tst.generateHTML:{[outFile]
    if[not .tst.coverageEnabled;'"Coverage not enabled"];
    outPath:.tst.resolvePath outFile;
    model:$[(99h=type .tst.lastCoverageModel) and `files in key .tst.lastCoverageModel;
        .tst.lastCoverageModel;.tst.coverageModel[]];
    s:model`summary;
    html:"<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>resQ Coverage</title>";
    html,:"<style>body{font-family:sans-serif;margin:2rem}table{border-collapse:collapse;width:100%;margin-bottom:1rem}th,td{border:1px solid #ccc;padding:.35rem;text-align:left}.covered{background:#e7f7ea}.uncovered{background:#fde8e8}.unmeasured{background:#f3f3f3;color:#666}pre{margin:0;white-space:pre-wrap}</style></head><body>";
    html,:"<h1>resQ Coverage</h1><p><strong>Functions:</strong> ",
        string[s`functionsHit]," / ",string[s`functionsFound]," (",
        string[s`functionPercent],"%)</p><p><strong>Measured statements:</strong> ",
        string[s`linesHit]," / ",string[s`linesFound]," (",string[s`linePercent],
        "%)</p><p><strong>Statement instrumentation completeness:</strong> ",
        string[s`statementFunctionsInstrumented]," / ",
        string[s`statementFunctionsEligible]," (",
        string[s`statementInstrumentationPercent],"%)</p>";
    fileRows:model`files;
    i:0;
    do[count fileRows;
        fileRow:fileRows i;
        html,:"<section><h2>",.tst.coverageHtmlEscape[fileRow`path],"</h2>";
        html,:"<p>",string[fileRow`functionHit]," / ",
            string[fileRow`functionFound]," functions covered; ",
            string[fileRow`lineHit]," / ",string[fileRow`lineFound],
            " measured statements covered; loaded=",string[fileRow`loaded],"</p>";
        html,:"<table><thead><tr><th>Function</th><th>Line</th><th>Hits</th><th>Function instrumented</th><th>Statements</th><th>Statement instrumented</th><th>Fallback</th></tr></thead><tbody>";
        html,:raze .tst.coverageFunctionHtml each fileRow`functions;
        html,:"</tbody></table>",.tst.coverageSourceHtml[fileRow],"</section>";
        i+:1];
    html,:"<p>Machine-readable detail: coverage.json. Raw state: coverage_state.txt.</p></body></html>";
    (hsym (`$":" , outPath)) 0:enlist html;
    -1 "HTML report written to: ",outPath;
    outPath
 };
