.tst.loadTests:{[paths]
    tests: .tst.findTests paths;
    if[0 = count tests; -1 "WARNING: No test files found"; :()];

    {[x]
        / Normalize path
        p: .utl.pathToString x;

        / Verify file exists
        if[not .utl.pathExists p; -1 "ERROR: Test file not found: ", p; :()];

        -1 "Loading Test: ", p;

        / Ensure we are in root namespace
        system "d .";

        / Make path absolute to avoid CWD issues when tests change directory
        absPath: $["/" = first p; p; (system "cd"), "/", p];
        absPath: .utl.normalizePath absPath;

        / Set loading context with absolute path
        .utl.FILELOADING: .utl.pathToHsym absPath;

        / Read and evaluate
        content: @[read0; .utl.FILELOADING; {[p;e] -1 "ERROR reading ", p, ": ", e; ()}[p]];
        if[0 = count content; :()];

        @[{value "\n" sv x}; content; {[p;e] -1 "CRITICAL LOAD ERROR in ", p, ": ", e}[p]];

        / If coverage is enabled and available, instrument the just-loaded file.
        covSuppressed: $[`tst in key `.; 1b ~ @[get; `.tst.coverageLoading; 0b]; 0b];
        if[not covSuppressed;
            if[all `instrumentFile`coverageEnabled in key `.tst;
                if[.tst.coverageEnabled;
                    covAbs: $[`resolvePath in key `.tst; .tst.resolvePath absPath; absPath];
                    @[.tst.instrumentFile; covAbs; {[cp;e]
                        -1 "WARNING: coverage instrumentation failed for ", cp, ": ", e
                    }[covAbs]];
                ];
            ];
        ];
    } each tests;
 };

.tst.findTests:{[paths]
    / Ensure paths is a list
    ps: $[10h = type paths; enlist paths; 0h = type paths; paths; enlist paths];
    ps: distinct ps;

    / Find all .q files matching patterns
    files: distinct raze .tst.suffixMatch[".q"] each ps;

    / Return files - suffixMatch already handles test_ filtering
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
