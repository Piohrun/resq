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

/ mtime in epoch seconds. GNU `stat -c %Y` first, then BSD/macOS `stat -f %m`.
/ Each is its OWN system call - a shell `||` between them stops q from
/ capturing stdout. Failure (no stat, missing file) yields 0 -> size-only.
.tst.watch.mtime:{[p]
    g: @[{"J"$ first system "stat -c %Y ", x}; p; {0N}];
    if[not null g; :g];
    b: @[{"J"$ first system "stat -f %m ", x}; p; {0N}];
    $[null b; 0; b]
 }

/ Per-file change fingerprint. NOTE: `key` on a *file* hsym returns the symbol
/ itself (not a modtime), so the old scan stored file!file and `check` never
/ saw a difference - watch detected nothing. We fingerprint each file by
/ (size; mtime): `hcount` gives the size with no shell; mtime (above) covers
/ same-size edits. A missing file yields a sentinel.
.tst.watch.fingerprint:{[f]
    h: .utl.pathToHsym f;
    if[() ~ key h; :(-1; -1)];          / missing -> sentinel
    sz: @[hcount; h; -1];
    (sz; .tst.watch.mtime .utl.pathToString f)
 }

/ Scan and return dictionary of file->fingerprint
.tst.watch.scanFiles:{[]
    files: raze { .tst.static.findSources x } each .tst.watch.watchDirs;
    if[0 = count files; :()!()];
    files!.tst.watch.fingerprint each files
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
