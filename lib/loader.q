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
/ Rules (column-1 backslash only - q requires system commands at column 1):
/   * A line that is exactly "/" (trailing whitespace ignored) opens a block
/     comment ONLY when the preceding line is blank (or it is the first line) -
/     this matches q's own rule, where a bare "/" sitting amongst other "/"
/     line-comments is just an empty comment, not a block-comment opener. A line
/     that is exactly "\" closes the block. The whole block (the "/", its
/     interior, and the closing "\") is DROPPED: q's own `value` cannot parse
/     block comments (it signals on the "\" / interior), so emitting them
/     verbatim would break loading. Dropping them is comment-equivalent and
/     guarantees nothing inside the block - including a fake \l - is executed.
/   * Outside a block comment, a column-1 "\" line:
/       - exactly "\"  -> end of script: drop this and all following lines.
/       - otherwise     -> rewrite "\cmd rest" to system "cmd rest" (backslashes
/                          and quotes in the remainder escaped).
.tst.preprocessScript:{[lines]
    lines: .utl.pathToString each lines;
    state: 0b;                 / 1b while inside a block comment
    prevBlank: 1b;             / 1b when the previous line was blank (start = 1b)
    out: enlist ();            / sentinel keeps the accumulator heterogeneous
    i: 0;
    n: count lines;
    while[i < n;
        ln: lines i;
        trimmed: .tst.rstrip ln;
        $[state;
            / Inside a block comment: drop the line; watch for the "\" closer.
            if[trimmed ~ enlist "\\"; state: 0b];
            / Outside a block comment.
            [ $[(0 < count ln) and "\\" = first ln;
                  / Column-1 system command.
                  $[trimmed ~ enlist "\\";
                      i: n;                          / lone "\": terminate script
                      / Rewrite \cmd -> system "cmd"; the trailing ";" terminates
                      / the statement so it does not chain into the next line when
                      / the whole file is joined and value'd (\cmd was line-
                      / terminated; system "..." is not).
                      [ esc: ssr[ssr[1 _ ln; "\\"; "\\\\"]; "\""; "\\\""];
                        out,: enlist "system \"", esc, "\";" ] ];
                (trimmed ~ enlist "/") and prevBlank;
                  / Opens a block comment - drop the "/" line itself too.
                  / Only a bare "/" preceded by a blank line opens a block; a
                  / bare "/" amongst other comment lines is just an empty comment.
                  state: 1b;
                / Ordinary line.
                out,: enlist ln ] ] ];
        / Track blankness of THIS source line for the next iteration's block-open
        / decision (only meaningful when we did not terminate via "\").
        prevBlank: 0 = count trimmed;
        i +: 1;
    ];
    1 _ out
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
        absPath: $["/" = first p; p; (system "cd"), "/", p];
        absPath: .utl.normalizePath absPath;

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
        code: "\n" sv .tst.preprocessScript content;
        res: @[value; code; {(`err0x; x)}];
        if[(2 = count res) and (first res) ~ `err0x;
            e: last res;
            -1 "CRITICAL LOAD ERROR in ", p, ": ", e;
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
    ps: distinct .utl.pathToString each ps;

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
