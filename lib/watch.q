/ lib/watch.q - Smart Watch Mode
/ ============================================================================

/ Dependencies
.resq.require .resq.PKGLOADING,"/static_analysis.q"
.resq.require .resq.PKGLOADING,"/load_graph.q"

/ Configuration
.tst.watch.watchDirs: enlist enlist "."
.tst.watch.fileStates: ()!()
.tst.watch.deletedFiles: `symbol$()
/ Extra loader function names, e.g. enlist ".lib.load", for a loader that is
/ defined outside the watched directories. `watchLoaders` in resq.json adds to
/ this. Loaders defined in a watched file are found without being named.
.tst.watch.loaders: ()
/ The load graph of the tracked files (lib/load_graph.q), rebuilt on change.
.tst.watch.graph: ()
/ Poll interval in seconds, consumed by the watch loop's sleep. The 1s rescan
/ walks the whole tree via recursive `key` each tick, so raising this trades
/ latency for less churn on large trees.
.tst.watch.interval: 1

/ resQ's require (.utl.require, .resq.require) loads a file once per process,
/ and watch reruns in that same process. A watched file it has loaded must be
/ forgotten before a rerun, or its edits are never read: the right tests run,
/ against the old definitions, and a broken edit stays green. resQ's own
/ modules stay loaded.
.tst.watch.forgetLoaded:{[]
    loaded: @[get; `.resq.loaded; {()}];
    if[0=count loaded; :()];
    canon: .tst.loadGraph.canonical[system "cd"];
    tracked: `$canon each key .tst.watch.fileStates;
    own: (canon .resq.PKGLOADING), "/";
    paths: canon each loaded;
    isOwn: {[own;p] (count[own]<=count p) and own~(count own)#p}[own] each paths;
    .resq.loaded: loaded where not ((`$paths) in tracked) and not isOwn;
 };

/ Default runner command (can be overridden). Accepts a list of files as
/ symbols and/or strings; an empty list means the full suite, which is every
/ test file under the watched directories. Handing the runner the empty list
/ itself made it discover nothing, so each full-suite fallback ran no tests.
.tst.watch.runnerCmd: {
    files: $[count x; x; .tst.watch.watchDirs];
    / Reload runner state to clear previous runs. Anchor at install root
    / so this works no matter where the user invoked resq from.
    home: @[get; `.resq.HOME; {"."}];
    .resq.util.loadQFile home,"/lib/runner.q";

    / Force no exit for watch mode runner
    .tst.app.exit: 0b;

    / Selection is advisory, so a failure here must not stop the rerun.
    @[.tst.watch.forgetLoaded; ::; {[e] -1 ">> Could not reset loaded files (", e, ")."}];

    / Set args for runner. The runner expects a list of path STRINGS (as the
    / CLI passes); check[] yields symbols, so normalize each entry to a string.
    .tst.app.args: {$[-11h = type x; string x; x]} each files;

    -1 ">> Running tests internally...";
    / Recompose reporters and, when enabled, start a fresh coverage session for
    / every rerun. The preceding run's finalizer has restored all wrappers.
    .tst.initReporting[];
    @[.tst.runAll; ::; {-1 "Error during test run: ", x}];
    -1 ">> Done.";
 };

/ Batch-stat a list of path STRINGS in ONE subprocess and return a path->mtime
/ token dict. GNU stat contributes its nanosecond timestamp; the BSD fallback
/ is marked second-resolution so fingerprintWith can add a content digest. The
/ old code spawned one `stat` PER FILE PER TICK
/ (~2.6 ms each), so a 500-file tree blew past the 1s poll interval. Here every
/ tracked path is shell-quoted (.resq.util.shellQuote - spaces in paths are safe) and
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
    quoted: " " sv .resq.util.shellQuote each paths;
    / q's `system` does NOT capture stdout when the command string contains
    / shell metacharacters like `;` (it streams them to the console instead and
    / returns nothing). So the WHOLE compound - `stat ... ; true` to swallow the
    / nonzero exit on a missing file - is wrapped as a single `sh -c <quoted>`
    / argument; q then sees one simple command and captures its stdout normally.
    runner: {[inner] system "sh -c ", .resq.util.shellQuote inner};
    / Tabs separate metadata from paths; a path containing a tab is reconstructed
    / from every remaining field. `%y` retains GNU stat's fractional seconds.
    out:@[runner;"stat --printf='%Y\\t%y\\t%n\\n' ",quoted," 2>/dev/null ; true";{()}];
    highResolution:0<count out;
    if[not highResolution;
        out:@[runner;"stat -f '%m|%N' ",quoted," 2>/dev/null ; true";{()}]];
    parsed:{[high;ln]
        parts:$[high;"\t" vs ln;"|" vs ln];
        minimum:$[high;3;2];
        if[count[parts]<minimum;:()];
        epoch:first parts;
        if[null @["J"$;epoch;{0Nj}];:()];
        token:$[high;"n:",epoch,":",parts 1;"s:",epoch];
        path:$[high;"\t" sv 2_ parts;"|" sv 1_ parts];
        enlist[path]!enlist token
    }[highResolution;] each out;
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
.tst.watch.contentDigest:{[h]
    size:@[hcount;h;{[e] -1}];
    if[size<0;:""];
    state:md5 "resq-watch-content-v1";
    offset:0j;
    failed:0b;
    while[(not failed) and offset<size;
        amount:65536j&size-offset;
        chunk:@[read1;(h;offset;amount);{[e]::}];
        if[(::)~chunk;failed:1b];
        / md5 takes text. Given the bytes read1 returns it signals 'type,
        / which ended watch, and `resq mutate` in a checkout with changes,
        / wherever stat gives whole seconds only or is not there at all.
        if[not failed;state:md5 ("c"$state),"c"$md5 "c"$chunk];
        offset+:amount];
    $[failed;"";raze string state]
 };

.tst.watch.fingerprintWith:{[mtimeMap;f]
    h: .resq.util.pathToHsym f;
    if[() ~ key h; :(-1; ""; "")];     / missing -> sentinel
    sz: @[hcount; h; {[e] -1}];
    ps: .resq.util.pathToString f;
    / An empty map has no keys to look in: `ps in ()` asks about each
    / character, and the list it answers with is not a condition.
    mt:$[0=count mtimeMap;"s:0";ps in key mtimeMap;mtimeMap ps;"s:0"];
    / On platforms exposing only epoch seconds, add a fixed-width native digest.
    / This keeps the poll subprocess count batched while detecting same-size,
    / same-second rewrites that size+mtime alone cannot see.
    digest:$[mt like "s:*";.tst.watch.contentDigest h;""];
    (sz;mt;digest)
 }

/ Single-file fingerprint convenience (used by tests). Runs its own one-path
/ stat batch so callers need not pre-build a map.
.tst.watch.fingerprint:{[f]
    .tst.watch.fingerprintWith[.tst.watch.statAll enlist .resq.util.pathToString f; f]
 }

/ Scan and return dictionary of file->fingerprint. Collects every tracked path,
/ stats them ALL in one (chunked) subprocess, then builds fingerprints from the
/ resulting mtime map - one batch per tick instead of one stat per file.
.tst.watch.scanFiles:{[]
    files: raze { .tst.static.findSources x } each .tst.watch.watchDirs;
    if[0 = count files; :()!()];
    mtimeMap: .tst.watch.statAll .resq.util.pathToString each files;
    files!.tst.watch.fingerprintWith[mtimeMap] each files
 }

/ Initialize
.tst.watch.init:{[dirs]
    .tst.watch.watchDirs:: dirs;
    .tst.watch.fileStates:: .tst.watch.scanFiles[];
    .tst.watch.deletedFiles:: `symbol$();
    -1 ">> Watch initialized. Tracking ",string[count .tst.watch.fileStates]," files.";
    -1 ">> Directories: ", ", " sv dirs;
    .tst.watch.describeGraph[];
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
    .tst.watch.deletedFiles:: del;

    / A deletion is a change too. onChanges falls back to the full remaining
    / suite because a deleted file cannot itself be targeted safely.
    distinct new, changed, del
 }

/ ----------------------------------------------------------------------------
/ Path classification helpers.
/ q's `like` accepts at most ONE `*` per pattern; the old `*test_*.q` and
/ `*/test/*.q` patterns had two stars each and threw 'nyi for every changed
/ file. These split the path into segments and match each piece with a
/ single-star (or star-free) pattern instead.
/ ----------------------------------------------------------------------------

.tst.watch.testFilePatterns:{[]
    patterns: @[get; `.resq.config.testFilePatterns; {("test_*.q"; "*_test.q")}];
    $[10h = type patterns; enlist patterns; patterns]
 };

/ A test file is a .q file whose basename matches the same configured patterns
/ used by normal discovery.
.tst.watch.isTestFile:{[s]
    s: $[10h = type s; s; string s];
    if[not count s; :0b];
    base: last "/" vs s;
    (".q" ~ -2 # s) and any base like/: .tst.watch.testFilePatterns[]
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

/ ----------------------------------------------------------------------------
/ Choosing what to rerun
/ ----------------------------------------------------------------------------

.tst.watch.loaderNames:{[]
    distinct .tst.loadGraph.names[@[get; `.resq.config.watchLoaders; {()}]],
        .tst.loadGraph.names @[get; `.tst.watch.loaders; {()}]
 };

/ A file the runner can be handed: a test file, or anything under test/.
.tst.watch.runnable:{[f]
    s: string f;
    .tst.watch.isTestFile[s] or .tst.watch.inTestDir s
 };

/ Rebuild the load graph for the tracked files and return it. `test` marks the
/ runnable files. Unchanged files are served from the graph's own cache.
.tst.watch.refreshGraph:{[]
    tracked: key .tst.watch.fileStates;
    tracked: $[0=count tracked; `symbol$(); tracked];
    g: .tst.loadGraph.build[tracked; value .tst.watch.fileStates; .tst.watch.loaderNames[]];
    g[`test]: .tst.watch.runnable each tracked;
    .tst.watch.graph:: g;
    g
 };

/ The graph is advisory: if it cannot be built, watch still reruns tests, it
/ just cannot narrow a source change below the full suite.
.tst.watch.tryGraph:{[]
    @[{.tst.watch.refreshGraph[]}; ::; {[e] -1 ">> Load graph unavailable (", e, ")."; ()}]
 };

/ One line on the graph at startup, plus the loads it could not resolve: those
/ are why some tests rerun on every source change.
.tst.watch.describeGraph:{[]
    g: .tst.watch.tryGraph[];
    if[0=count g; :()];
    -1 ">> Load graph: ", string[sum 0, count each g`deps], " load(s) found between tracked files.";
    opaque: .tst.watch.opaqueTests g;
    if[0=count opaque; :()];
    -1 ">> ", string[count opaque], " test file(s) rerun on every source change: a load they reach has no fixed target.";
    dyn: where g`dynamic;
    dyn: dyn where {[g;i] any g[`test] .tst.loadGraph.loadedBy[g; enlist i]}[g] each dyn;
    lines: raze {[g;i] (string[g[`tracked] i], " ") ,/: g[`why] i}[g] each dyn;
    -1 each ">>   " ,/: 5 sublist lines;
    if[5<count lines; -1 ">>   (", string[(count lines)-5], " more)"];
 };

/ Tracked test files that load f, directly or through other files.
.tst.watch.testsLoading:{[g;f]
    i: g[`tracked]?f;
    if[i=count g`tracked; :`symbol$()];
    idx: .tst.loadGraph.loadedBy[g; enlist i] except i;
    g[`tracked] idx where g[`test] idx
 };

/ Test files that reach a file with an unresolved load. What they load cannot
/ be known, so any source change may concern them.
.tst.watch.opaqueTests:{[g]
    dyn: where g`dynamic;
    if[0=count dyn; :`symbol$()];
    idx: .tst.loadGraph.loadedBy[g; dyn];
    g[`tracked] idx where g[`test] idx
 };

/ Test files matched to a source file by name (src/foo.q -> test_foo.q,
/ foo_test.q under the default patterns). Kept alongside the load graph so a
/ test that loads its source in a way the graph cannot see is still rerun.
.tst.watch.namedTests:{[f]
    name: .tst.static.getBase f;
    if[".q" ~ -2 # name; name: (count[name]-2)#name];
    patterns: .tst.watch.testFilePatterns[];
    patterns: patterns where {any x = "*"} each patterns;
    targets: {[n; p] ssr[p; "*"; n]}[name;] each patterns;
    candidates: key .tst.watch.fileStates;
    candidates: $[0=count candidates; `symbol$(); candidates];
    candidates where {[targets; p] (last "/" vs string p) in targets}[targets] each candidates
 };

/ Decide what a set of changed files reruns. Returns
/   all    1b to run the full suite
/   tests  the files to run otherwise
/   notes  lines explaining a decision the user would not guess
/ Rules, in order:
/   - A deleted file reruns everything: what loaded it can no longer be read.
/   - A runnable file reruns itself and every test that loads it.
/   - Any other file reruns the tests that load it, plus those matching it by
/     name. If there are none, nothing is known about who uses it, so the full
/     suite runs.
/   - Unless only test files changed, tests with an unresolved load run too.
.tst.watch.plan:{[files]
    out: `all`tests`notes!(0b; `symbol$(); ());
    deleted: @[get; `.tst.watch.deletedFiles; `symbol$()];
    if[any files in deleted; out[`all]: 1b; :out];
    g: .tst.watch.tryGraph[];
    hasGraph: 0<count g;
    one: {[g;hasGraph;f]
        runnable: .tst.watch.runnable f;
        loading: $[hasGraph; .tst.watch.testsLoading[g;f]; `symbol$()];
        tests: distinct $[runnable; f, loading; loading, .tst.watch.namedTests f];
        `tests`unknown!(tests; (not runnable) and (0=count tests) or not hasGraph)
    }[g;hasGraph] each files;
    unknown: files where one[;`unknown];
    if[count unknown;
        out[`all]: 1b;
        if[hasGraph;
            out[`notes]: enlist ">> No test file is known to load ", ", " sv string unknown];
        :out];
    tests: distinct raze one[;`tests];
    sourceChanged: not all {.tst.watch.isTestFile string x} each files;
    if[hasGraph and sourceChanged;
        extra: .tst.watch.opaqueTests[g] except tests;
        if[count extra;
            tests,: extra;
            out[`notes]: enlist ">> Including ", string[count extra],
                " test file(s) whose loads have no fixed target."]];
    out[`tests]: tests;
    out
 };

/ Run tests for changed files
.tst.watch.onChanges:{[files]
    -1 ">> Changes detected in: ", ", " sv string files;
    plan: .tst.watch.plan files;
    -1 each plan`notes;
    $[plan[`all] or 0=count plan`tests;
        [
            -1 ">> Running ALL tests.";
            .tst.watch.runnerCmd[()];
        ];
        [
            -1 ">> Running target tests: ", ", " sv string plan`tests;
            .tst.watch.runnerCmd[plan`tests];
        ]
    ];
 }
