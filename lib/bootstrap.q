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
  res: @[{system "l ", x; 1b}; p; { [p;e]
    / Coverage is loaded lazily by the runner only when -cov is passed,
    / so its absence from the require chain is expected.
    if[not p like "*coverage.q";
        -1 "WARNING: Failed to load ", p, " (", e, ")"];
    0b
  }[p]];
  
  if[res;
    .utl.loaded,: enlist p;

    / If coverage is enabled and the coverage module is loaded, instrument
    / any .q file that is loaded through .utl.require.
    covSuppressed: 0b;
    if[`tst in key `.;
      covSuppressed: 1b ~ @[get; `.tst.coverageLoading; 0b];
    ];
    if[not covSuppressed;
      if[`tst in key `.;
        if[all `instrumentFile`coverageEnabled in key `.tst;
        if[.tst.coverageEnabled and p like "*.q" and not p like "*coverage.q";
          covPath: $[p like ":*"; 1 _ p; p];
          covAbs: $[`resolvePath in key `.tst; .tst.resolvePath covPath; covPath];
          @[.tst.instrumentFile; covAbs; {[cp;e]
              -1 "WARNING: coverage instrumentation failed for ", cp, ": ", e
          }[covAbs]];
        ];
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

/ Ensure a directory exists. Centralizes shell use and path quoting.
.utl.ensureDir:{[path]
    p: .utl.normalizePath path;
    if[0 = count p; p: "."];
    if[.utl.isDir p; :p];
    cmd: $[.utl.isWindows; "mkdir ", .utl.shellQuote p; "mkdir -p ", .utl.shellQuote p];
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
    flip `suite`description`status`message`time`failures`assertsRun!(
        `symbol$(); `symbol$(); `symbol$(); (); `timespan$(); (); `int$())
 };
