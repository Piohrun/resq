/ Strip trailing spaces and tabs from a string (no regex; pure char ops).
/ Robust against a single-char (atomic) argument.
.tst.rstrip:{[s]
    s: $[10h = type s; s; enlist s];
    i: where not s in " \t";
    $[0 = count i; ""; (1 + last i) # s]
 };

/ Preprocess a test file (a list of source lines, as read by read0) into a list
/ of lines safe for `value "\n" sv ...`. q's `value` cannot execute lines that
/ start with a backslash system command (\l, \d, \t, ...) - they fail with 'nyi.
/ This rewrites them to the equivalent `system "..."` call, which q treats
/ identically (e.g. system "l x" == \l x, CWD-relative resolution included),
/ and honours the `\` script terminator. Block comments are tracked so a
/ system-command-looking line inside one is never executed.
/ Rules (aligned EXACTLY with q's own `\l` lexer):
/   * A line that rstrips to exactly "/" ALWAYS opens a block comment (trailing
/     whitespace ignored, preceding line irrelevant - real q opens a block here
/     regardless of what came before). The block is terminated by a line that
/     rstrips to exactly "\"; if no such line exists, the block runs to EOF and
/     the rest of the file is comment (matching real q). The whole block (the
/     "/", its interior, and the closing "\") is DROPPED: q's own `value` cannot
/     parse block comments, so emitting them verbatim would break loading.
/     Dropping is comment-equivalent and guarantees nothing inside the block -
/     including a fake \l - is executed.
/   * Outside a block comment, a column-1 "\" line:
/       - rstrips to exactly "\"  -> end of script: drop this and all following
/                                    lines.
/       - otherwise                -> rewrite "\cmd rest" to system "cmd rest"
/                                     (backslashes and quotes escaped).
/   * "/"-prefixed line comments ("/ text") and ordinary lines pass through.
/ Check order matters: inside a block we ONLY look for the closing "\".
/ Otherwise we test block-open (lone "/") BEFORE the terminator / system-command
/ rewrite - a lone "/" is never a system command, and a lone "\" outside a block
/ is the terminator, never a block close.
/ Canonical absolute+normalized form of a path. Absolutizes against the current
/ working directory when relative, then resolves "." / ".." segments. Two
/ different spellings of the same file (./x.q vs x.q vs an absolute path) all
/ collapse to one string here, so it is the right key for de-duplication and for
/ deriving a stable sandbox name.
.tst.canonicalPath:{[p]
    s: .utl.pathToString p;
    absPath: $["/" = first s; s; (system "cd"), "/", s];
    .utl.normalizePath absPath
 };

/ Load a q script the way `\l <path>` does, then (when coverage is enabled)
/ instrument the functions it just defined. preprocessScript rewrites a test
/ file's `\l <path>` to a call to this wrapper so that source-under-test loaded
/ with `\l` becomes visible to coverage (a bare `system "l ..."` is not). The
/ load runs FIRST - the definitions must exist before they can be wrapped - and
/ instrumentation is best-effort: a wrapping failure must never break the load
/ of correct user code. `path` is whatever followed "\l " (relative or
/ absolute); both `system "l"` and instrumentFile resolve it against the CWD the
/ same way, so it is passed through unchanged.
.tst.sysl:{[path]
    system "l ", path;
    if[1b ~ @[get; `.tst.coverageEnabled; 0b];
        if[`instrumentFile in key `.tst;
            @[.tst.instrumentFile; path; {[p;e]
                -1 "Coverage: could not instrument ", p, ": ", .tst.toString e
            }[path]];
        ];
    ];
 };

.tst.preprocessScript:{[lines]
    lines: .utl.pathToString each lines;
    state: 0b;                 / 1b while inside a block comment
    out: enlist ();            / sentinel keeps the accumulator heterogeneous
    i: 0;
    n: count lines;
    while[i < n;
        ln: lines i;
        trimmed: .tst.rstrip ln;
        $[state;
            / Inside a block comment: drop the line; watch for the "\" closer.
            if[trimmed ~ enlist "\\"; state: 0b];
          trimmed ~ enlist "/";
            / Lone "/" outside a block ALWAYS opens a block comment (drop it).
            state: 1b;
          (0 < count ln) and "\\" = first ln;
            / Column-1 backslash: terminator or system command.
            $[trimmed ~ enlist "\\";
                i: n;                              / lone "\": terminate script
                / Rewrite \cmd -> system "cmd"; the trailing ";" terminates the
                / statement so it does not chain into the next line when the whole
                / file is joined and value'd (\cmd was line-terminated; system
                / "..." is not).
                [ body: 1 _ ln;
                  esc: ssr[ssr[body; "\\"; "\\\\"]; "\""; "\\\""];
                  / A `\l <path>` loads the code-under-test. Route it through
                  / .tst.sysl instead of bare `system "l ..."` so coverage can
                  / instrument the freshly-loaded source (system "l" is invisible
                  / to the require/loaded-files hooks). Only the `l` command is
                  / special-cased - the arg is whatever follows "\l " (path,
                  / possibly relative; .tst.sysl resolves it the same way q does).
                  / Every other \cmd keeps the plain system rewrite. Match "l "
                  / (load with an argument) precisely so "\l" alone and unrelated
                  / commands fall through unchanged.
                  $[(body ~ "l") or body like "l *";
                      / strip the leading "l" + following whitespace to get the path
                      [ pathArg: $[body ~ "l"; ""; trim 2 _ body];
                        pEsc: ssr[ssr[pathArg; "\\"; "\\\\"]; "\""; "\\\""];
                        out,: enlist ".tst.sysl \"", pEsc, "\";" ];
                      out,: enlist "system \"", esc, "\";" ] ] ];
            / Ordinary line (includes "/ text" line comments).
            out,: enlist .tst.rewriteSystemLoad ln ];
        i +: 1;
    ];
    1 _ out
 };

/ Rewrite a runtime `system "l ", <expr>` load (the form real suites use to load
/ their code-under-test, e.g. `system "l ", root, "/src/x.q"`) into an
/ equivalent `.tst.sysl (<expr>)` so coverage can instrument it. `system "l "`
/ runs the load command whose argument (the file path) is everything AFTER the
/ "l " prefix; here that prefix lives in the leading string literal and the path
/ is the concatenation that follows the comma, so passing that concatenation to
/ .tst.sysl loads the same file (and then instruments it). Only the exact
/ leading token `system "l ", ` is matched so arbitrary `system` calls and
/ string occurrences mid-line are left untouched; the original line is returned
/ verbatim when it does not match.
.tst.rewriteSystemLoad:{[ln]
    lt: .tst.lstrip ln;
    pfx: "system \"l \", ";
    if[not lt like pfx, "*"; :ln];
    rt: .tst.rstrip lt;
    / Only the clean, single-statement form `... ;` is rewritten. A trailing
    / line comment, a missing terminator, or extra statements on the line are
    / left verbatim rather than risk a malformed rewrite - coverage is
    / best-effort, correctness of the load is not.
    if[(0 = count rt) or ";" <> last rt; :ln];
    / Preserve leading indentation so column-sensitive checks elsewhere are
    / unaffected, then swap the prefix for the .tst.sysl call. Drop the trailing
    / ";" before wrapping in parens (".tst.sysl (expr;)" would not parse) and
    / re-add it after so the call still terminates cleanly.
    indent: (count ln) - count lt;
    rest: -1 _ (count pfx) _ rt;
    (indent # ln), ".tst.sysl (", rest, ");"
 };

/ Strip leading spaces/tabs (mirror of .tst.rstrip).
.tst.lstrip:{[s]
    s: $[10h = type s; s; enlist s];
    i: where not s in " \t";
    $[0 = count i; ""; (first i) _ s]
 };

/ Count the net bracket-nesting contribution of a line: +1 for each of { ( [
/ and -1 for each } ) ], skipping any char inside a "..." string. Approximate
/ (does not track \ block comments -- the caller's grouping drops those), but
/ enough to tell whether a statement's brackets are still open across lines.
.tst.bracketDelta:{[ln]
    ln: .utl.pathToString ln;
    inStr: 0b; delta: 0; i: 0; n: count ln;
    while[i < n;
        c: ln i;
        $[inStr;
            $[c = "\\"; i +: 1;                   / skip escaped char in string
              c = "\""; inStr: 0b; ::];
          c = "\"";    inStr: 1b;
          c in "{(["; delta +: 1;
          c in "})]"; delta -: 1;
          ::];
        i +: 1;
    ];
    delta
 };

/ Group raw source lines into top-level statements. A new top-level statement
/ begins only when bracket nesting is back to 0 AND the line is a non-blank
/ column-1 line (q's script continuation rule: leading whitespace continues the
/ previous statement). A line inside an unbalanced {([ ... keeps accumulating
/ regardless of its leading column, so a multi-line `desc[...]{ ... };` block
/ stays ONE statement (and thus parses as a unit). Returns (startLineNo; lines)
/ pairs with the 1-based ORIGINAL file line of each statement's first line.
.tst.groupStatements:{[lines]
    lines: .utl.pathToString each lines;
    out: ();              / list of (startLineNo; list-of-lines)
    depth: 0;             / current unbalanced bracket depth
    i: 0;
    n: count lines;
    while[i < n;
        ln: lines i;
        blank: 0 = count .tst.rstrip ln;
        leadWs: (0 < count ln) and (first ln) in " \t";
        / Continue the current statement when brackets are still open, or this is
        / a whitespace-led continuation line, or a blank line inside a statement.
        cont: (0 < count out) and ((depth > 0) or leadWs or blank);
        $[blank and 0 = depth;
            ::;                                   / separator between statements
          cont;
            out[(count out)-1; 1]: (out[(count out)-1; 1]), enlist ln;
            out,: enlist (i+1; enlist ln)         / start a new top-level stmt
        ];
        depth +: .tst.bracketDelta ln;
        if[depth < 0; depth: 0];                  / defensive: never go negative
        i +: 1;
    ];
    out
 };

/ Parse-only localization of a load error. Re-grouping the ORIGINAL source into
/ top-level statements and `parse`-ing each (NOT `value`) finds the first
/ statement q cannot PARSE -- i.e. the syntax error -- with ZERO side effects
/ (no re-execution, so already-run statements are never run twice). System
/ commands (\l, \d, ...) and comment/terminator statements are skipped because
/ `parse` cannot handle them and they are not where a user's syntax error lives.
/ Returns the 1-based original line of the first un-parseable statement, or 0N
/ when every statement parses (a RUNTIME error -- caller keeps the plain message).
.tst.localizeSyntaxError:{[content]
    stmts: .tst.groupStatements content;
    if[0 = count stmts; :0N];
    / 1b = "fine / not parseable in isolation" (system command, comment, or a
    / multi-line {} fragment that only parses whole); 0b = genuine parse failure.
    okFlags: {[st]
        joined: "\n" sv @[.tst.preprocessScript; st 1; {()}];
        lt: .tst.lstrip joined;
        if[0 = count lt; :1b];
        if[(lt like "system \"*") or lt like ".tst.sysl*"; :1b];
        @[{parse x; 1b}; joined; {0b}]
    } each stmts;
    bad: where not okFlags;
    $[count bad; stmts[first bad; 0]; 0N]
 };

.tst.loadTests:{[paths]
    tests: .tst.findTests paths;
    .tst.app.discoveredFiles: tests;
    .tst.app.loadedFiles: ();
    .tst.app.emptyFiles: ();
    if[0 = count tests; -1 "WARNING: No test files found"; :()];

    {[x]
        / Normalize path
        p: .utl.pathToString x;

        / Verify file exists
        if[not .utl.pathExists p; -1 "ERROR: Test file not found: ", p; :()];

        if[not .tst.app.quiet; -1 "Loading Test: ", p];
        .tst.app.loadedFiles,: enlist p;

        / Make path absolute to avoid CWD issues when tests change directory.
        / Done first so both the sandbox name and its hash derive from the
        / canonical absolute path - the sandbox is then stable regardless of how
        / the path was passed (relative or absolute).
        absPath: .tst.canonicalPath p;

        / Namespace Sandbox
        / Sanitize path to create unique namespace
        / Replace non-alphanumeric chars with _, then append a short content-
        / independent hash of the absolute path. Without the hash, paths that
        / differ only in non-alphanumeric chars (test_a.q / test-a.q / test a.q)
        / collapse to the same sandbox and clobber each other's globals.
        cleanP: absPath;
        cleanP[where not cleanP in .Q.a,.Q.A,.Q.n]: first "_";
        hashStr: 8 # raze string md5 absPath;
        nsName: `$".sandbox_S", cleanP, "_", hashStr;

        loadCtx: .tst.captureRuntimeContext[];

        / Track current namespace for DSL capture
        .tst.currentNs: nsName;

        / Set loading context with absolute path
        .utl.FILELOADING: .utl.pathToHsym absPath;

        / Read content
        content: @[read0; .utl.FILELOADING; {[p;e] 
            -1 "ERROR reading ", p, ": ", e; 
            `.tst.app.loadErrors upsert `file`error`type!(`$p; e; `read);
            ()
        }[p]];
        if[0 = count content;
            .tst.restoreRuntimeContext loadCtx;
            :()
        ];

        / Snapshot spec count
        preCount: count .tst.app.allSpecs;

        / Ensure namespace exists and switch to it
        nsInit: string[nsName],".init:0;";
        @[value; nsInit; {[p;e]
            -1 "CRITICAL LOAD ERROR in ", p, ": ", e;
            `.tst.app.loadErrors upsert `file`error`type!(`$p; e; `load);
        }[p]];

        @[system; "d ", string nsName; {[p;e]
            -1 "CRITICAL LOAD ERROR in ", p, ": ", e;
            `.tst.app.loadErrors upsert `file`error`type!(`$p; e; `load);
        }[p]];

        / Evaluate script content. Preprocess first so q system commands (\l, \d,
        / \t, ...) that `value` cannot execute become equivalent `system "..."`
        / calls, and trailing `\` script terminators are honoured.
        / Execution path is UNCHANGED: value the whole preprocessed file (a
        / partial failure rolls back below). Only AFTER a failure do we localize,
        / and we localize with `parse`, not `value`, so no successful statement is
        / ever re-executed (re-running would fire side effects twice).
        / Parse-localization pinpoints the common case (a SYNTAX error); a pure
        / runtime error parses cleanly and keeps the original whole-file message.
        code: "\n" sv .tst.preprocessScript content;
        res: @[value; code; {(`err0x; x)}];
        if[(2 = count res) and (first res) ~ `err0x;
            e: last res;
            lineNo: @[.tst.localizeSyntaxError; content; {0N}];
            if[not null lineNo;
                stmtsForMsg: @[.tst.groupStatements; content; {()}];
                excerpt: $[count stmtsForMsg;
                    [ hit: first stmtsForMsg where stmtsForMsg[;0] = lineNo;
                      stmtTxt: .tst.lstrip "\n" sv hit 1;
                      (80 & count stmtTxt) # stmtTxt ];
                    ""];
                e: e, " (near line ", string[lineNo], $[count excerpt; ": ", excerpt; ""], ")";
            ];
            -1 "CRITICAL LOAD ERROR in ", p, $[not null lineNo; " near line ", string[lineNo]; ""], ": ", e;
            `.tst.app.loadErrors upsert `file`error`type!(`$p; e; `load);
            if[(count .tst.app.allSpecs) > preCount;
                .tst.app.allSpecs: preCount # .tst.app.allSpecs;
                -1 "  -> Rolled back partial specs from ", p;
            ];
        ];

        / Restore root namespace
        @[system; "d ."; {}];

        / Warn if no tests loaded
        if[(count .tst.app.allSpecs) = preCount;
            msg: "File ", p, " loaded but added no tests.";
            -1 "WARNING: ", msg;
            .tst.app.emptyFiles,: enlist p;
            if[.tst.app.strict;
                `.tst.app.loadErrors upsert `file`error`type!(`$p; msg; `emptyFile);
            ];
        ];

        / Restore loader bookkeeping
        .tst.restoreRuntimeContext loadCtx;
        
    } each tests;
 };

.tst.findTests:{[paths]
    / Ensure paths is a list
    ps: $[10h = type paths; enlist paths; 0h = type paths; paths; enlist paths];
    / De-dup on the CANONICAL absolute path, not the raw spelling: passing the
    / same file under two spellings (resq test ./x.q x.q) must register and run
    / it ONCE. Raw-string `distinct` saw "./x.q" and "x.q" as different, so the
    / file loaded - and DEFINED - twice. Absolutizing+normalizing first unifies
    / them. loadTests later derives its sandbox from the same canonical form, so
    / making paths absolute here is invariant-preserving.
    ps: distinct .tst.canonicalPath each ps;

    / Explicit q file paths are always honored. Directory scans are filtered
    / to a configurable list of test-file glob patterns so we don't load
    / helper/repro/dependency files. Defaults preserve historical behavior
    / (test_*.q, *_test.q); override via .resq.config.testFilePatterns
    / (a list of strings) or the testFilePatterns key in resq.json.
    patterns: @[get; `.resq.config.testFilePatterns; {("test_*.q"; "*_test.q")}];
    if[10h = type patterns; patterns: enlist patterns];

    directFiles: ps where {(.utl.isFile x) and x like "*.q"} each ps;
    dirs: ps where .utl.isDir each ps;

    / Any explicit arg that is neither an existing file nor an existing
    / directory is a user mistake (typo, deleted path, ...). Historically these
    / were silently dropped, so a run could "succeed" while quietly skipping the
    / file the user asked for. Record each as a load error so the run fails with
    / EXIT.LOAD_ERROR (4) and the missing path is reported. Guard the table init
    / in case findTests is reached before lib/init.q seeded it.
    missing: ps where not (.utl.isFile each ps) or .utl.isDir each ps;
    if[0 < count missing;
        if[not `loadErrors in key `.tst.app;
            .tst.app.loadErrors: flip `file`error`type!(`symbol$(); (); `symbol$());
        ];
        {[m]
            -1 "ERROR: Explicit test path not found: ", m;
            `.tst.app.loadErrors upsert `file`error`type!(`$m; "Explicit test path not found"; `missing);
        } each missing;
    ];

    discovered: distinct raze .tst.suffixMatch[".q"] each dirs;
    isNamedTest: {[pats; p]
        base: last "/" vs p;
        any base like/: pats
    }[patterns;];
    files: distinct directFiles, discovered where isNamedTest each discovered;

    / Return convention-matching discovered tests plus explicit files.
    files
 };

/ Trapped predicates: .utl.isFile/.utl.isDir call `key`, which SIGNALS an OS
/ error on a broken symlink or a permission-denied entry. Untrapped, that kills
/ the whole run mid-discovery. These wrappers treat an unreadable entry as
/ "neither file nor dir" so it is simply skipped.
.tst.safeIsFile:{[p] @[.utl.isFile; p; {[e] 0b}]};
.tst.safeIsDir:{[p] @[.utl.isDir; p; {[e] 0b}]};

/ True when `p` is a symbolic link. q has no native lstat, so we shell out to
/ `test -L <p>; echo $?` - the same exit-code-absorbing idiom the golden harness
/ uses. `test -L` exits 0 for a symlink, 1 otherwise; appending `; echo $?` makes
/ the shell always exit 0 (so q's `system` never signals 'os) and prints the real
/ exit code on the last stdout line, which we read back. The path is shell-quoted
/ (its closing quote must stay attached to the path, so quote in a separate step:
/ q is right-to-left and would otherwise fold the trailing text into the path
/ before quoting).
.tst.isSymlink:{[p]
    q: .utl.shellQuote .utl.pathToString p;
    out: @[system; "test -L ", q, "; echo $?"; {[e] enlist "1"}];
    / `echo $?` captures as a 1-char string ("0"), so compare as a string and
    / parse it: exit code 0 from `test -L` means the path is a symlink.
    $[0 = count out; 0b; 0 = "J" $ last out]
 };

/ Public entry point - depth starts at 0.
.tst.suffixMatch:{[suffix;path] .tst.suffixMatchDepth[suffix;path;0]};

/ Recursively collect files under `path` whose name ends in `suffix`.
/ `depth` guards against symlink loops: a directory tree that cycles back on
/ itself would otherwise recurse until q dies with an OS error. Above the cap we
/ warn once and stop descending that branch.
.tst.suffixMatchDepth:{[suffix;path;depth]
    / Bail out of pathological recursion (symlink loops, absurdly deep trees).
    if[depth > 32;
        -1 "WARNING: max directory depth exceeded, skipping: ", .utl.pathToString path;
        :0#enlist""
    ];

    / Normalize path to string
    p: .utl.pathToString path;

    / If path is a file with matching suffix, return it
    if[p like ("*", suffix); if[.tst.safeIsFile p; :(enlist p)]];

    / If path is not a directory, nothing more to find
    if[not .tst.safeIsDir p; :0#enlist""];

    / Get directory contents. `key` can signal on a bad entry; trap to a clean
    / empty so one broken dir does not abort the entire run.
    h: .utl.pathToHsym p;
    contents: @[key; h; {[e] ()}];
    if[() ~ contents; :0#enlist""];

    / Filter out hidden files (starting with .)
    contents: contents where not (string contents) like ".*";
    if[0 = count contents; :0#enlist""];

    / Build full paths - ensure we get a list of strings
    fullPaths: {[base;name] b: .utl.pathToString base; b: $["/" = last b; b; b, "/"]; b, string name}[p] each contents;

    / Separate files and directories (trapped predicates skip unreadable entries)
    files: fullPaths where .tst.safeIsFile each fullPaths;
    dirs: fullPaths where .tst.safeIsDir each fullPaths;

    / Do NOT follow symlinked directories: a symlink cycle would rediscover the
    / same test file under N loop paths (one file ran 17x before this). Standard
    / tools (find, rg) skip symlinked dirs by default; we match that. Symlinked
    / FILES are fine - only directory symlinks are dropped here.
    dirs: dirs where not .tst.isSymlink each dirs;

    / Find matching files
    matchingFiles: files where files like ("*", suffix);

    / Recurse into directories - use (,/) to join lists without flattening strings
    (,/) (enlist matchingFiles), .tst.suffixMatchDepth[suffix;;depth+1]'[dirs]
 };
