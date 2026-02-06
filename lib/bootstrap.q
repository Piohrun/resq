/ lib/bootstrap.q - Clean & Robust Loader
if[not `utl in key `; .utl: enlist[`]!enlist (::)];
if[not `loaded in key `.utl; .utl.loaded: enlist ""];
.utl.PKGLOADING: "lib";
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
  if[p in .utl.loaded; :(::)];

  if[.utl.DEBUG; -1 "DEBUG: loading ", p];
  
  / Try load
  res: @[{system "l ", x; 1b}; p; { [p;e] 
    / Silently ignore qspec/qutil if missing from vendor but handled by init
    if[not (p like "qutil*") or (p like "qspec*") or (p like "*coverage.q");
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

/ ============================================================================

.utl.addOpt: {[a;b;c]};
.utl.addArg: {[a;b;c;d]};
.utl.parseArgs: {[]};

.tst.die: {[x] exit x};
