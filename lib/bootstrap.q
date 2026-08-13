/ lib/bootstrap.q - Clean & Robust Loader
if[not `utl in key `; .utl: enlist[`]!enlist (::)];
if[not `loaded in key `.utl; .utl.loaded: enlist ""];
/ Anchor at the install root when resq.q has set it; falls back to "lib"
/ for direct invocations from inside the repo.
.utl.resqHomeAtBoot: @[get; `.resq.HOME; {""}];
.utl.PKGLOADING: $[count .utl.resqHomeAtBoot; .utl.resqHomeAtBoot,"/lib"; "lib"];
.utl.DEBUG: 0b;

/ OS Detection Utilities
.utl.OS: $[(string .z.o) like "l*"; `linux; (string .z.o) like "m*"; `macos; `windows];
.utl.isLinux: .utl.OS = `linux;
.utl.isMac: .utl.OS = `macos;
.utl.isWindows: .utl.OS = `windows;

.utl.require: {[path]
  / Convert to string
  p: $[10h=abs type path; path; string path];
  
  / Validation: ignore empty, namespace-like, or bracketed paths
  if[(not count p) or (p like ".*"); :(::)];
  / Check for leading bracket safely
  if["[" = first p; :(::)];
  
  / Track dependency
  if[not `testDeps in key `.utl; .utl.testDeps: ()!()];
  if[`FILELOADING in key `.utl;
     caller: .utl.pathToHsym .utl.FILELOADING;
     req: .utl.pathToHsym p;
     .utl.testDeps[caller]: distinct except[ (),.utl.testDeps[caller], req; (::) ];
  ];
  if[count .utl.testDeps; .utl.testDeps: (key[.utl.testDeps] except hsym `) # .utl.testDeps];

  / Avoid double loading
  if[any p ~/: .utl.loaded; :(::)];

  if[.utl.DEBUG; -1 "DEBUG: loading ", p];
  
  / Try load
  res: @[{.utl.loadQFile x; 1b}; p; { [p;e]
    / Coverage is loaded lazily by the runner only when -cov is passed, so a
    / MISSING coverage.q is expected and stays quiet. One that EXISTS but fails
    / to load is a real defect: suppressing that hid a half-loaded coverage
    / module -- initCoverage defined, generateLCOV not -- behind the vague
    / "Coverage LCOV generator not available", and cost a long bisect to find.
    quiet: (p like "*coverage.q") and not .utl.pathExists p;
    if[not quiet;
        -1 "WARNING: Failed to load ", p, " (", e, ")"];
    0b
  }[p]];
  
  if[res;
    .utl.loaded,: enlist p;

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

/ ============================================================================
/ Path Utilities
/ ============================================================================

/ Convert any path representation to a clean string
/ Handles: strings, symbols, hsym symbols, file handles
.utl.pathToString:{[p]
    $[10h = type p; $[p like ":*"; 1 _ p; p];
      -11h = type p; $[(s:string p) like ":*"; 1 _ s; s];
      p]
 };

/ Convert any path to hsym (file handle symbol)
.utl.pathToHsym:{[p] hsym `$.utl.pathToString p};

/ Load a q file/directory through its basename while visiting its parent.
/ q's `system "l <path>"` splits an absolute path containing spaces, whereas
/ `system "cd <dir>"` accepts the rest of the command as one directory. Module
/ and application filenames still follow the normal no-newline q convention.
/ q source-file loads leave cwd unchanged; directory/database loads deliberately
/ change it to the loaded root. Preserve that native distinction, and always
/ restore cwd on error.
.utl.loadQFile:{[path]
    s:.utl.pathToString path;
    if[0=count s;'"cannot load an empty q path"];
    if[not "/"=first s;s:(system "cd"),"/",s];
    slashes:where s="/";
    at:last slashes;
    dir:$[0=at;"/";at#s];
    base:(1+at)_s;
    previous:system "cd";
    isDirectory:.utl.isDir s;
    outcome:@[
        {[pair]system "cd ",pair 0;system "l ",pair 1;(0b;"")};
        (dir;base);
        {[e](1b;e)}];
    if[(first outcome) or not isDirectory;system "cd ",previous];
    if[first outcome;'last outcome];
    ::
 };

/ Normalize path - resolve . and .. components
.utl.normalizePath:{[path]
    s: .utl.pathToString path;
    parts: "/" vs s;
    isAbs: (count s) and "/" = first s;
    stack: {[state;p] $[p ~ ".."; $[count state; -1 _ state; state]; (p ~ enlist ".") or (0 = count p); state; state, enlist p]}/[(); parts];
    result: $[isAbs; "/"; ""], "/" sv stack;
    $[0 = count result; "."; result]
 };

/ Check if path exists (file or directory)
.utl.pathExists:{[p] not () ~ key .utl.pathToHsym p};

/ Check if path is a directory
.utl.isDir:{[p] k: key .utl.pathToHsym p; $[() ~ k; 0b; 11h = type k; 1b; 0b]};

/ Check if path is a file
.utl.isFile:{[p] k: key .utl.pathToHsym p; $[() ~ k; 0b; 11h = type k; 0b; 1b]};

/ Quote a path for POSIX shell commands.
.utl.shellQuote:{[p]
    s: .utl.pathToString p;
    $[.utl.isWindows;
        "\"", ssr[s; "\""; "\\\""], "\"";
        "'", ssr[s; "'"; "'\"'\"'"], "'"]
 };

/ Root directory for scratch files, honouring TMPDIR. On many systems /tmp is
/ tmpfs (RAM-backed), so anything written there costs memory rather than disk —
/ respecting TMPDIR lets a caller point scratch at real storage.
/ Returns a normalized absolute path with no trailing slash.
.utl.tempRoot:{[]
    root: getenv `TMPDIR;
    if[0 = count root; root: "/tmp"];
    root: .utl.normalizePath root;
    if[(0 = count root) or not "/" = first root; root: "/tmp"];
    $[(1 < count root) and "/" = last root; -1 _ root; root]
 };

/ Ensure a directory exists. Centralizes shell use and path quoting.
.utl.ensureDir:{[path]
    p: .utl.normalizePath path;
    if[0 = count p; p: "."];
    if[.utl.isDir p; :p];
    cmd: $[.utl.isWindows; "mkdir ", .utl.shellQuote p; "mkdir -p -- ", .utl.shellQuote p];
    @[system; cmd; {[p;e]
        -1 "WARNING: Failed to create directory ", p, ": ", e;
        :()
    }[p]];
    p
 };

/ ============================================================================

.tst.die: {[x] exit x};

/ Canonical empty results table. Defined here so every module (bootstrap
/ order: bootstrap -> init -> dsl/internals -> runner) can call it without
/ re-typing the schema. Returns a fresh table each call -- it's a builder,
/ not a shared instance, to avoid accidental aliasing.
.resq.state.emptyResults:{[]
    columns:`suite`description`status`message`time`failures`assertsRun`file`line`namespace`tags`output,
        `testId`caseId`kind`parameters`attempts`retried`flaky`attemptHistory`parameterCases`property`diagnostics`snapshots`benchmark;
    flip columns!(
        `symbol$(); `symbol$(); `symbol$(); (); `timespan$(); (); `int$();
        (); `int$(); (); (); ();
        (); (); `symbol$(); (); `int$(); `boolean$(); `boolean$(); (); (); (); (); (); ())
 };
