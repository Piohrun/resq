/ coverage.q - runtime coverage instrumentation and LCOV/HTML reporting (load-safe)
.utl.require .utl.PKGLOADING,"/static_analysis.q"

/ State
.tst.coverageData: ()!();        / file -> func -> count
.tst.coverageEnabled: 0b;
.tst.trackedFiles: ();
.tst.origFuncs: ()!();           / name -> original function
.tst.lastCoverageSummary: `linesFound`linesHit`linePercent`functionsFound`functionsHit`functionPercent!(0j;0j;0f;0j;0j;0f);
.tst.covWrappers: ()!();         / name -> installed wrapper (live identity)
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
    
    / Apply --cov-include / --cov-exclude filters.
    if[`coverageInclude in key `.tst.app;
        if[0 < count .tst.app.coverageInclude;
            if[not any absPath like/: .tst.app.coverageInclude; :()]
        ]
    ];
    if[`coverageExclude in key `.tst.app;
        if[any absPath like/: .tst.app.coverageExclude; :()]
    ];

    / Never instrument resQ's own modules by default. Now that .utl.require
    / actually reaches instrumentation, the framework's internals would
    / otherwise be wrapped on every `resq cover` run: that slows the run and
    / buries the user's own functions in the report. An explicit -cov-include
    / overrides this, which is how resQ measures coverage of itself.
    / Scope this to <HOME>/lib specifically, NOT all of <HOME>: a project can
    / legitimately keep its own sources under the install root (the bundled
    / examples do), and excluding those would silently report nothing for them.
    if[0 = count @[get; `.tst.app.coverageInclude; ()];
        home: @[get; `.resq.HOME; {""}];
        if[(0 < count home) and absPath like home, "/lib/*"; :()];
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

    / Statement probes go in BEFORE the function wrapper, so the wrapper closes
    / over the instrumented body. Each attempt is independent: a function that
    / cannot be rewritten safely simply keeps derived line records.
    starts: "j"$ $[`line in cols fns; fns`line; `long$()];
    starts: starts where not null starts;
    if[1b ~ @[get; `.tst.coverageStatements; 0b];
        {[fs; nsAt; srcLines; starts; row]
            nm: .tst.coverageQualifyName[nsAt; row`line; row`name];
            span: .tst.functionLineSpan[row`line; starts; count srcLines];
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
    slashes: where pathStr = "/";
    dir: $[count slashes; (last slashes) # pathStr; "."];
    base: $[count slashes; (1 + last slashes) _ pathStr; pathStr];
    prevCd: system "cd";
    / chdir, then load basename; any failure restores cwd before re-raising.
    @[{[d;b] system "cd ", d; system "l ", b}[dir];
      base;
      {[pc;e] system "cd ", pc; 'e}[prevCd]];
    system "cd ", prevCd;
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
    fs: $[10h = type files; enlist `$files; files];
    .tst.trackedFiles:: fs;
    .tst.coverageData:: ()!();
    .tst.origFuncs:: ()!();
    .tst.covWrappers:: ()!();
    .tst.loadingStack:: ();
    .tst.coverageEnabled:: 1b;

    {[f] .tst.ensureCoverageEntry f} each fs;

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
        / DA (line) records are DERIVED: every executable line of a function
        / inherits that function's hit count. resQ instruments whole functions,
        / not statements, so this is function coverage projected onto lines --
        / it makes standard coverage tooling work, but an unexecuted branch
        / inside a called function still reads as covered. See docs/COVERAGE.md.
        coverable: .tst.coverableLines srcLines;
        fnStarts: "j"$ $[`line in cols fns; fns`line; `long$()];
        fnStarts: fnStarts where not null fnStarts;
        / Measured per-line hits for this file, and which functions carry them.
        stmtNames: $[fileSym in key .tst.stmtInstrumented; .tst.stmtInstrumented fileSym; `symbol$()];
        measuredMap: $[fileSym in key .tst.lineCoverageData; .tst.lineCoverageData fileSym; (`long$())!`long$()];
        fileLines: {[m;n] $[n in key m; m n; 0j]}[measuredMap;] each 1 + til count srcLines;
        probeLines: $[fileSym in key .tst.stmtProbeLines; .tst.stmtProbeLines fileSym; `long$()];
        lineHits: (count srcLines) # 0j;
        lineSeen: (count srcLines) # 0b;

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

            / Where the function's statements were instrumented, its lines are
            / MEASURED and only probed statements count. Otherwise fall back to
            / projecting the function's hit count across its span (derived).
            span: .tst.functionLineSpan[row`line; fnStarts; count srcLines];
            measured: nm in stmtNames;
            if[span[1] >= span[0];
                $[measured;
                    [ / Only statement starts are countable; a continuation line
                      / or a `];` is not an independently executable statement.
                      bodyIdx: (span[0] - 1) + til 1 + span[1] - span[0];
                      bodyIdx: bodyIdx where bodyIdx < count srcLines;
                      inSpan: probeLines where probeLines within (span 0; span 1);
                      sIdx: (inSpan - 1) where (inSpan - 1) < count srcLines;
                      if[count sIdx;
                          lineSeen[sIdx]: 1b;
                          / fileLines is 0-indexed by (line - 1), which is what
                          / sIdx already holds.
                          lineHits[sIdx]: lineHits[sIdx] | "j"$fileLines sIdx ];
                    ];
                    [ idx: (span[0] - 1) + til 1 + span[1] - span[0];
                      idx: idx where idx < count srcLines;
                      if[count coverable; idx: idx where coverable idx];
                      if[count idx;
                          lineSeen[idx]: 1b;
                          lineHits[idx]: lineHits[idx] | "j"$hit ];
                    ]];
            ];

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

        / DA records first (LCOV convention), then the line summary.
        daIdx: where lineSeen;
        txt,: raze {[i; h] "DA:", string[i + 1], ",", string[h], "\n"}'[daIdx; lineHits daIdx];
        txt,: "LF:", string[count daIdx], "\n";
        txt,: "LH:", string[sum 0 < lineHits daIdx], "\n";

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

    .tst.lastCoverageSummary: .tst.coverageSummaryFromLines "\n" vs txt;
    outH 0: enlist txt;
    -1 "LCOV report written to: ", outPath;
    / An empty report is the one result that looks like success but measures
    / nothing. The usual cause is loading the code under test with a loader the
    / instrumenting hook does not see -- only `\l` and `system "l "` are
    / intercepted (docs/COVERAGE.md) -- which otherwise yields a silently blank
    / LCOV and a green run.
    if[0 = count files;
        -1 "WARNING: coverage instrumented 0 functions - this report is empty.";
        -1 "         Source must be loaded with `\\l path` or `system \"l \", path`;";
        -1 "         other loaders (including .utl.require) are not intercepted.";
    ];
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
