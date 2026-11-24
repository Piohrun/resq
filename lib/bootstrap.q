/ lib/bootstrap.q - Clean & Robust Loader
/ resQ keeps its own helpers and state in .resq. `.utl` is the name of qutil's
/ namespace, and also what many teams call their own utilities: a codebase
/ that defined .utl.isDir or .utl.require with a different meaning used to
/ break resQ, and resQ used to overwrite theirs. resQ now reads nothing from
/ .utl. It only offers names there for existing test code (see the end of
/ this file), and never replaces one it did not put there itself.
if[not `utl in key `; .utl: enlist[`]!enlist (::)];
if[not `loaded in @[key; `.resq; {`symbol$()}]; .resq.loaded: enlist ""];
/ .utl names resQ has set, with the value it gave each.
if[not `utlOffered in @[key; `.resq; {`symbol$()}]; .resq.utlOffered: (enlist `)!enlist (::)];
/ Set .utl.<name> when nobody else owns it: the name is absent, or it still
/ holds what resQ last put there.
.resq.offerUtl:{[name;val]
    present: name in key `.utl;
    ours: $[name in key .resq.utlOffered; .resq.utlOffered[name] ~ @[get; ` sv `.utl,name; {::}]; 0b];
    if[present and not ours; :0b];
    (` sv `.utl,name) set val;
    .resq.utlOffered[name]: val;
    1b
 };

/ qspec requires qutil, so a qspec shop's q.q usually loads qutil's bootstrap
/ before resQ starts. qutil owns .utl.require (packages on QPATH, signalling
/ on failure), .utl.PKGLOADING, .utl.FILELOADING and .utl.DEBUG. Overwriting
/ them broke `.utl.require "mypkg"` in migrated suites, so resQ keeps its own
/ loader state under .resq and only fills the .utl names qutil did not define.
.resq.bootKeys: @[key; `.resq; {`symbol$()}];
if[(not `qutilRequire in .resq.bootKeys) and `requireVH in key `.utl;
    .resq.qutilRequire: .utl.require];
.resq.hasQutil: `qutilRequire in @[key; `.resq; {`symbol$()}];

/ Anchor at the install root when resq.q has set it; falls back to "lib"
/ for direct invocations from inside the repo.
.resq.homeAtBoot: @[get; `.resq.HOME; {""}];
.resq.PKGLOADING: $[count .resq.homeAtBoot; .resq.homeAtBoot,"/lib"; "lib"];
if[not .resq.hasQutil; .resq.offerUtl[`PKGLOADING; .resq.PKGLOADING]];
if[not `DEBUG in key `.resq; .resq.DEBUG: 0b];

/ OS Detection Utilities
.resq.util.OS: $[(string .z.o) like "l*"; `linux; (string .z.o) like "m*"; `macos; `windows];
.resq.util.isLinux: .resq.util.OS = `linux;
.resq.util.isMac: .resq.util.OS = `macos;
.resq.util.isWindows: .resq.util.OS = `windows;

.resq.require: {[path]
  / Convert to string
  p: $[10h=abs type path; path; string path];
  
  / Validation: ignore empty, namespace-like, or bracketed paths. A leading
  / dot alone does not make a namespace: ./src/x.q and ../lib/x.q are paths,
  / and so is a dot-file that exists.
  namespaceLike: (p like ".*") and not any (p like "./*"; p like "../*"; .resq.util.pathExists p);
  if[(not count p) or namespaceLike; :(::)];
  / Check for leading bracket safely
  if["[" = first p; :(::)];
  
  / Track dependency
  if[not `testDeps in key `.resq; .resq.testDeps: ()!()];
  if[`FILELOADING in key `.resq;
     caller: .resq.util.pathToHsym .resq.FILELOADING;
     req: .resq.util.pathToHsym p;
     .resq.testDeps[caller]: distinct except[ (),.resq.testDeps[caller], req; (::) ];
  ];
  if[count .resq.testDeps; .resq.testDeps: (key[.resq.testDeps] except hsym `) # .resq.testDeps];

  / Avoid double loading
  if[any p ~/: .resq.loaded; :(::)];

  if[.resq.DEBUG; -1 "DEBUG: loading ", p];
  
  / Try load. A file that cannot be loaded is an error, as it is for `\l`:
  / a warning here let a test file run without the code it asked for, and
  / pass. The one quiet case is the optional coverage module being absent.
  failure: "";
  res: @[{.resq.util.loadQFile x; 1b}; p; { [p;e]
    / Coverage is loaded lazily by the runner only when -cov is passed, so a
    / MISSING coverage.q is expected and stays quiet. One that EXISTS but fails
    / to load is a real defect: suppressing that hid a half-loaded coverage
    / module -- initCoverage defined, generateLCOV not -- behind the vague
    / "Coverage LCOV generator not available", and cost a long bisect to find.
    quiet: (p like "*coverage.q") and not .resq.util.pathExists p;
    if[quiet; :0b];
    if[(not "/" in p) and not p like "*.q";
        -1 "  '", p, "' looks like a qutil package name. qspec ran with qutil, whose ",
           ".utl.require finds packages on QPATH; load qutil's bootstrap (q.q or ",
           "QINIT) before resQ and resQ will hand package names to it."];
    `resqRequireFailed, enlist "failed to load ", p, ": ", e
  }[p]];
  if[not -1h = type res; 'last res];
  
  if[res;
    .resq.loaded,: enlist p;

    / If coverage is enabled and the coverage module is loaded, instrument
    / any .q file that is loaded through .utl.require.
    / This branch used to be guarded by ``if[`tst in key `.]``, which is ALWAYS
    / false -- q's root key list does not report child namespaces (`key `.` is
    / empty even when .tst exists, while `key `.tst` works). The whole branch
    / was therefore dead and NOTHING loaded via .utl.require was ever
    / instrumented. Probe the namespace directly instead.
    tstKeys: @[key; `.tst; {`symbol$()}];
    covSuppressed: 1b ~ @[get; `.tst.coverageLoading; 0b];
    if[not covSuppressed;
      if[all `instrumentFile`coverageEnabled in tstKeys;
        / Parenthesised deliberately: q evaluates right-to-left with uniform
        / precedence, so the bare form parsed as
        / `p like ("*.q" and (not p like "*coverage.q"))` and signalled 'type.
        if[.tst.coverageEnabled and (p like "*.q") and (not p like "*coverage.q");
          covPath: $[p like ":*"; 1 _ p; p];
          covAbs: $[`resolvePath in key `.tst; .tst.resolvePath covPath; covPath];
          @[.tst.instrumentFile; covAbs; {[cp;e]
              -1 "WARNING: coverage instrumentation failed for ", cp, ": ", e
          }[covAbs]];
        ];
      ];
    ];
  ];
 };

/ With qutil present, an existing path still loads through resQ (coverage and
/ watch-mode dependency tracking); anything else is a qutil package name.
.resq.requireOrQutil:{[path]
  p: $[10h=abs type path; path; string path];
  $[.resq.util.pathExists p; .resq.require path; .resq.qutilRequire path]
 };
/ With qutil, .utl.require is wrapped so paths still load through resQ. Without
/ it, resQ offers its own require, and leaves alone a .utl.require that some
/ other library (a team's own loader) defined first.
$[.resq.hasQutil; .utl.require: .resq.requireOrQutil; .resq.offerUtl[`require; .resq.require]];

/ ============================================================================
/ Path Utilities
/ ============================================================================

/ Convert any path representation to a clean string
/ Handles: strings, symbols, hsym symbols, file handles
.resq.util.pathToString:{[p]
    $[10h = type p; $[p like ":*"; 1 _ p; p];
      -11h = type p; $[(s:string p) like ":*"; 1 _ s; s];
      p]
 };

/ Convert any path to hsym (file handle symbol)
.resq.util.pathToHsym:{[p] hsym `$.resq.util.pathToString p};

/ Load a q file or directory as `\l <path>` does. A path without whitespace
/ goes straight to q, so the working directory stays where it is while the
/ file loads: an application that loads its own files by paths relative to
/ the project root (`\l src/util.q` inside src/app.q) keeps working, as it
/ does under plain q.
/ q's `system "l <path>"` splits a path containing spaces, whereas
/ `system "cd <dir>"` accepts the rest of the command as one directory. Only
/ such a path is loaded through its basename while visiting its parent, and
/ the working directory is that parent for the duration of the load.
/ q source-file loads leave cwd unchanged; directory/database loads deliberately
/ change it to the loaded root. Preserve that native distinction, and always
/ restore cwd on error.
.resq.util.loadQFile:{[path]
    s:.resq.util.pathToString path;
    if[0=count s;'"cannot load an empty q path"];
    if[not any s in " \t"; :system "l ",s];
    if[not "/"=first s;s:(system "cd"),"/",s];
    slashes:where s="/";
    at:last slashes;
    dir:$[0=at;"/";at#s];
    base:(1+at)_s;
    previous:system "cd";
    isDirectory:.resq.util.isDir s;
    outcome:@[
        {[pair]system "cd ",pair 0;system "l ",pair 1;(0b;"")};
        (dir;base);
        {[e](1b;e)}];
    if[(first outcome) or not isDirectory;system "cd ",previous];
    if[first outcome;'last outcome];
    ::
 };

/ Normalize path - resolve . and .. components
.resq.util.normalizePath:{[path]
    s: .resq.util.pathToString path;
    parts: "/" vs s;
    isAbs: (count s) and "/" = first s;
    stack: {[state;p] $[p ~ ".."; $[count state; -1 _ state; state]; (p ~ enlist ".") or (0 = count p); state; state, enlist p]}/[(); parts];
    result: $[isAbs; "/"; ""], "/" sv stack;
    $[0 = count result; "."; result]
 };

/ Check if path exists (file or directory)
.resq.util.pathExists:{[p] not () ~ key .resq.util.pathToHsym p};

/ Check if path is a directory
.resq.util.isDir:{[p] k: key .resq.util.pathToHsym p; $[() ~ k; 0b; 11h = type k; 1b; 0b]};

/ Check if path is a file
.resq.util.isFile:{[p] k: key .resq.util.pathToHsym p; $[() ~ k; 0b; 11h = type k; 0b; 1b]};

/ Quote a path for POSIX shell commands.
.resq.util.shellQuote:{[p]
    s: .resq.util.pathToString p;
    $[.resq.util.isWindows;
        "\"", ssr[s; "\""; "\\\""], "\"";
        "'", ssr[s; "'"; "'\"'\"'"], "'"]
 };

/ The launcher leaves this marker in its guard directory when it is told to
/ stop (INT, TERM, HUP, QUIT), before it signals q. A busy q does not stop at
/ a signal: it went on to start the next batch of isolated children, and to
/ write a report and state files from a run that had been cut short. The
/ marker holds the exit status the launcher leaves with. An isolated child
/ runs with an empty RESQ_RUN_GUARD_DIR, so only the run the launcher started
/ looks for it; without a launcher there is nothing to look for.
.resq.interruptMarker: {[dir] $[count dir; hsym `$dir, "/interrupted"; `]} getenv `RESQ_RUN_GUARD_DIR;
/ Beside it, the run notes each test as it starts and ends. A q that dies in
/ the middle of a test (out of memory under -w, a crash, an exit) leaves no
/ report and says nothing; the launcher reads the last line and names the
/ test. See .tst.noteTestProgress.
.resq.runningMarker: {[dir] $[count dir; hsym `$dir, "/running"; `]} getenv `RESQ_RUN_GUARD_DIR;
.resq.util.runInterrupted:{[]
    $[null .resq.interruptMarker; 0b; not () ~ @[key; .resq.interruptMarker; {[e] ()}]]
 };
.resq.util.interruptExitCode:{[]
    text: @[read0; .resq.interruptMarker; {[e] ()}];
    code: $[count text; "J"$first text; 0Nj];
    $[null code; 130; code]
 };

/ Root directory for scratch files, honouring TMPDIR. On many systems /tmp is
/ tmpfs (RAM-backed), so anything written there costs memory rather than disk —
/ respecting TMPDIR lets a caller point scratch at real storage.
/ Returns a normalized absolute path with no trailing slash.
.resq.util.tempRoot:{[]
    root: getenv `TMPDIR;
    if[0 = count root; root: "/tmp"];
    root: .resq.util.normalizePath root;
    if[(0 = count root) or not "/" = first root; root: "/tmp"];
    $[(1 < count root) and "/" = last root; -1 _ root; root]
 };

/ Ensure a directory exists. Centralizes shell use and path quoting.
.resq.util.ensureDir:{[path]
    p: .resq.util.normalizePath path;
    if[0 = count p; p: "."];
    if[.resq.util.isDir p; :p];
    cmd: $[.resq.util.isWindows; "mkdir ", .resq.util.shellQuote p; "mkdir -p -- ", .resq.util.shellQuote p];
    @[system; cmd; {[p;e]
        -1 "WARNING: Failed to create directory ", p, ": ", e;
        :()
    }[p]];
    p
 };

/ ============================================================================

/ The helpers above under their old .utl names, for test code written against
/ them. Each is offered only where the name is free.
{[name] .resq.offerUtl[name; .resq.util name]} each (key .resq.util) except `;

.tst.die: {[x] exit x};

/ Canonical empty results table. Defined here so every module (bootstrap
/ order: bootstrap -> init -> dsl/internals -> runner) can call it without
/ re-typing the schema. Returns a fresh table each call -- it's a builder,
/ not a shared instance, to avoid accidental aliasing.
.resq.state.emptyResults:{[]
    columns:`suite`description`status`message`time`startedAt`finishedAt`failures`assertsRun`file`line`namespace`tags`output,
        `testId`caseId`kind`parameters`attempts`retried`flaky`attemptHistory`parameterCases`property`diagnostics`snapshots`benchmark`quarantine;
    flip columns!(
        `symbol$(); `symbol$(); `symbol$(); (); `timespan$(); (); (); (); `int$();
        (); `int$(); (); (); ();
        (); (); `symbol$(); (); `int$(); `boolean$(); `boolean$(); (); (); (); (); (); (); ())
 };
