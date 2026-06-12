/ lib/watch.q - Smart Watch Mode
/ ============================================================================

/ Dependencies
.utl.require .utl.PKGLOADING,"/static_analysis.q"

/ Configuration
.tst.watch.watchDirs: enlist "."
.tst.watch.fileStates: ()!()
.tst.watch.lastScan: 0p
/ Poll interval in seconds, consumed by the watch loop's sleep. The 1s rescan
/ walks the whole tree via recursive `key` each tick, so raising this trades
/ latency for less churn on large trees.
.tst.watch.interval: 1

/ Default runner command (can be overridden). Accepts a (possibly empty) list
/ of files as symbols and/or strings.
.tst.watch.runnerCmd: {
    files: x;
    / Reload runner state to clear previous runs. Anchor at install root
    / so this works no matter where the user invoked resq from.
    home: @[get; `.resq.HOME; {"."}];
    system "l ", home, "/lib/runner.q";

    / Force no exit for watch mode runner
    .tst.app.exit: 0b;

    / Set args for runner. The runner expects a list of path STRINGS (as the
    / CLI passes); check[] yields symbols, so normalize each entry to a string.
    .tst.app.args: {$[-11h = type x; string x; x]} each files;

    -1 ">> Running tests internally...";
    @[.tst.runAll; ::; {-1 "Error during test run: ", x}];
    -1 ">> Done.";
 };

/ Batch-stat a list of path STRINGS in ONE subprocess and return a path->mtime
/ (epoch seconds) dict. The old code spawned one `stat` PER FILE PER TICK
/ (~2.6 ms each), so a 500-file tree blew past the 1s poll interval. Here every
/ tracked path is shell-quoted (.utl.shellQuote - spaces in paths are safe) and
/ passed to a SINGLE GNU `stat -c '%Y %n'` (BSD `stat -f '%m %N'` fallback).
/ .
/ q's `system` THROWS on a nonzero child exit, and `stat` exits nonzero if ANY
/ argument is missing - but it still PRINTS the lines for the files that exist.
/ We therefore suffix `; true` to force a zero exit and parse whatever stdout we
/ got; a path with no line (deleted mid-tick) is simply absent and defaults to
/ mtime 0 in the caller. Output is `%Y %n` so we split each line on the FIRST
/ space only - paths may themselves contain spaces.
.tst.watch.statBatch:{[paths]
    if[0 = count paths; :()!()];
    quoted: " " sv .utl.shellQuote each paths;
    / q's `system` does NOT capture stdout when the command string contains
    / shell metacharacters like `;` (it streams them to the console instead and
    / returns nothing). So the WHOLE compound - `stat ... ; true` to swallow the
    / nonzero exit on a missing file - is wrapped as a single `sh -c <quoted>`
    / argument; q then sees one simple command and captures its stdout normally.
    runner: {[inner] system "sh -c ", .utl.shellQuote inner};
    / GNU form first; if it yields nothing usable, try the BSD form.
    out: @[runner; "stat -c '%Y %n' ", quoted, " 2>/dev/null ; true"; {()}];
    if[0 = count out;
        out: @[runner; "stat -f '%m %N' ", quoted, " 2>/dev/null ; true"; {()}];
    ];
    / Parse "MTIME PATH" lines; split on the FIRST space (paths may have spaces).
    parsed: {[ln]
        if[0 = count ln; :()];
        sp: ln ? " ";
        if[sp <= 0; :()];
        m: "J"$ sp # ln;
        p: (sp + 1) _ ln;
        if[null m; :()];
        enlist[p]!enlist m
    } each out;
    parsed: parsed where 0 < count each parsed;
    $[0 = count parsed; ()!(); (,/) parsed]
 }

/ Stat ALL tracked paths for one tick. Command-line length is bounded by
/ chunking at 200 paths per `stat` call (1-3 calls/tick even for huge trees),
/ then merging the chunk dicts.
.tst.watch.statAll:{[paths]
    if[0 = count paths; :()!()];
    chunks: 0N 200 # paths;
    dicts: .tst.watch.statBatch each chunks;
    (,/) dicts
 }

/ Per-file change fingerprint built from a PRECOMPUTED mtime map (mtimeMap:
/ path-string -> epoch seconds from statAll). NOTE: `key` on a *file* hsym
/ returns the symbol itself (not a modtime), so the old scan stored file!file
/ and `check` never saw a difference - watch detected nothing. We fingerprint
/ each file by (size; mtime): `hcount` gives the size with NO shell (cheap, kept
/ per-file); mtime comes from the batched stat above and covers same-size edits.
/ A missing file (absent from mtimeMap) yields mtime 0; a missing handle yields
/ the (-1;-1) sentinel.
.tst.watch.fingerprintWith:{[mtimeMap;f]
    h: .utl.pathToHsym f;
    if[() ~ key h; :(-1; -1)];          / missing -> sentinel
    sz: @[hcount; h; -1];
    ps: .utl.pathToString f;
    mt: $[ps in key mtimeMap; mtimeMap ps; 0];
    (sz; mt)
 }

/ Single-file fingerprint convenience (used by tests). Runs its own one-path
/ stat batch so callers need not pre-build a map.
.tst.watch.fingerprint:{[f]
    .tst.watch.fingerprintWith[.tst.watch.statAll enlist .utl.pathToString f; f]
 }

/ Scan and return dictionary of file->fingerprint. Collects every tracked path,
/ stats them ALL in one (chunked) subprocess, then builds fingerprints from the
/ resulting mtime map - one batch per tick instead of one stat per file.
.tst.watch.scanFiles:{[]
    files: raze { .tst.static.findSources x } each .tst.watch.watchDirs;
    if[0 = count files; :()!()];
    mtimeMap: .tst.watch.statAll .utl.pathToString each files;
    files!.tst.watch.fingerprintWith[mtimeMap] each files
 }

/ Initialize
.tst.watch.init:{[dirs]
    .tst.watch.watchDirs:: dirs;
    .tst.watch.fileStates:: .tst.watch.scanFiles[];
    -1 ">> Watch initialized. Tracking ",string[count .tst.watch.fileStates]," files.";
    -1 ">> Directories: ", ", " sv dirs;
 }

/ Check for changes
.tst.watch.check:{[]
    curr: .tst.watch.scanFiles[];
    
    / New files
    new: (key curr) except key .tst.watch.fileStates;
    
    / Deleted files
    del: (key .tst.watch.fileStates) except key curr;
    
    / Changed files (intersection)
    common: (key curr) inter key .tst.watch.fileStates;
    changed: common where not (curr common) ~' (.tst.watch.fileStates common);
    
    / Update state
    .tst.watch.fileStates:: curr;
    
    / Return list of changed/new files (ignore deletes for now)
    new, changed
 }

/ ----------------------------------------------------------------------------
/ Path classification helpers.
/ q's `like` accepts at most ONE `*` per pattern; the old `*test_*.q` and
/ `*/test/*.q` patterns had two stars each and threw 'nyi for every changed
/ file. These split the path into segments and match each piece with a
/ single-star (or star-free) pattern instead.
/ ----------------------------------------------------------------------------

/ A test file is a .q file whose BASENAME matches test_*.q (e.g. test_foo.q).
.tst.watch.isTestFile:{[s]
    s: $[10h = type s; s; string s];
    if[not count s; :0b];
    base: last "/" vs s;
    (".q" ~ -2 # s) and base like "test_*"
 }

/ A test-dir file lives under a directory segment named exactly "test"
/ (e.g. proj/test/bar.q). Only the directory components are considered.
.tst.watch.inTestDir:{[s]
    s: $[10h = type s; s; string s];
    if[not count s; :0b];
    segs: "/" vs s;
    if[2 > count segs; :0b];           / no directory component
    any (-1 _ segs) ~\: "test"
 }

/ Run tests for changed files
.tst.watch.onChanges:{[files]
    -1 ">> Changes detected in: ", ", " sv string files;

    / Heuristic:
    / 1. Is it a test file? Run it.
    / 2. Is it a source file? Find dependent tests?

    testsToRun: distinct raze {[f]
        s: string f;
        $[.tst.watch.isTestFile s;
            enlist f;
            .tst.watch.inTestDir s;
            enlist f;
            [
                / It's a source file. Find mapping.
                / Simple mapping: src/foo.q -> test/test_foo.q
                base: .tst.static.getBase f;
                name: base;
                if[".q" ~ -2 # name; name: (count[name]-2)#name];

                / Search for test_NAME.q. Single `*` at the front only, so
                / this is a legal one-star pattern.
                candidates: key .tst.watch.fileStates;
                matches: candidates where (string candidates) like "*test_",name,".q";

                $[0<count matches; matches; enlist `ALL]
            ]
        ]
    } each files;
    
    / Run
    $[(`ALL in testsToRun) or (0=count testsToRun);
        [
            -1 ">> Running ALL tests.";
            .tst.watch.runnerCmd[()];
        ];
        [
            -1 ">> Running target tests: ", ", " sv string testsToRun;
            .tst.watch.runnerCmd[testsToRun];
        ]
    ];
 }
