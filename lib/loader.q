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

        / Namespace Sandbox
        / Sanitize path to create unique namespace
        / Replace non-alphanumeric chars with _
        cleanP: p;
        cleanP[where not cleanP in .Q.a,.Q.A,.Q.n]: first "_";
        nsName: `$".sandbox_S", cleanP;

        loadCtx: .tst.captureRuntimeContext[];
        
        / Track current namespace for DSL capture
        .tst.currentNs: nsName;
        
        / Make path absolute to avoid CWD issues when tests change directory
        absPath: $["/" = first p; p; (system "cd"), "/", p];
        absPath: .utl.normalizePath absPath;

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

        / Evaluate script content
        code: "\n" sv content;
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

    discovered: distinct raze .tst.suffixMatch[".q"] each dirs;
    isNamedTest: {[pats; p]
        base: last "/" vs p;
        any base like/: pats
    }[patterns;];
    files: distinct directFiles, discovered where isNamedTest each discovered;

    / Return convention-matching discovered tests plus explicit files.
    files
 };

.tst.suffixMatch:{[suffix;path]
    / Normalize path to string
    p: .utl.pathToString path;

    / If path is a file with matching suffix, return it
    if[p like ("*", suffix); if[.utl.isFile p; :(enlist p)]];

    / If path is not a directory, nothing more to find
    if[not .utl.isDir p; :0#enlist""];

    / Get directory contents
    h: .utl.pathToHsym p;
    contents: key h;
    if[() ~ contents; :0#enlist""];

    / Filter out hidden files (starting with .)
    contents: contents where not (string contents) like ".*";
    if[0 = count contents; :0#enlist""];

    / Build full paths - ensure we get a list of strings
    fullPaths: {[base;name] b: .utl.pathToString base; b: $["/" = last b; b; b, "/"]; b, string name}[p] each contents;

    / Separate files and directories
    files: fullPaths where .utl.isFile each fullPaths;
    dirs: fullPaths where .utl.isDir each fullPaths;

    / Find matching files
    matchingFiles: files where files like ("*", suffix);

    / Recurse into directories - use (,/) to join lists without flattening strings
    (,/) (enlist matchingFiles), .tst.suffixMatch[suffix] each dirs
 };
