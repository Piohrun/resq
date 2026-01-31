.tst.loadTests:{[paths]
    tests: .tst.findTests paths;
    if[0 = count tests; -1 "WARNING: No test files found"; :()];

    {[x]
        / Normalize path
        p: .utl.pathToString x;

        / Verify file exists
        if[not .utl.pathExists p; -1 "ERROR: Test file not found: ", p; :()];

        -1 "Loading Test: ", p;

        / Namespace Sandbox
        / Sanitize path to create unique namespace
        / Replace non-alphanumeric chars with _
        cleanP: p;
        cleanP[where not cleanP in .Q.a,.Q.A,.Q.n]: first "_";
        nsName: `$".sandbox_S", cleanP;
        
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
        if[0 = count content; :()];

        / Snapshot spec count
        preCount: count .tst.app.allSpecs;

        / Inject namespace logic
        / 1. Init: ensure namespace exists
        / 2. Switch: system "d .ns"
        / 3. Restore: system "d ."
        
        / Inject namespace logic
        
        nsInit: string[nsName],".init:0;";
        
        nsSwitch: "@[system; \"d ", string[nsName], "\"; { -1 \"FAIL FULL namespace switch ", string[nsName], ": \", x }];";
        nsRestore: "system \"d .\";";
        
        content: enlist[nsInit], enlist[nsSwitch], content, enlist[nsRestore];



        @[{value "\n" sv x}; content; {[p;preCount;e] 
            -1 "CRITICAL LOAD ERROR in ", p, ": ", e;
             `.tst.app.loadErrors upsert `file`error`type!(`$p; e; `load);

             / Rollback partial specs
             if[(count .tst.app.allSpecs) > preCount;
                .tst.app.allSpecs: preCount # .tst.app.allSpecs;
                -1 "  -> Rolled back partial specs from ", p;
             ];
        }[p;preCount]];

        / Warn if no tests loaded
        if[(count .tst.app.allSpecs) = preCount;
            msg: "File ", p, " loaded but added no tests.";
            -1 "WARNING: ", msg;
            if[.tst.app.strict;
                `.tst.app.loadErrors upsert `file`error`type!(`$p; msg; `emptyFile);
            ];
        ];

        / Reset current namespace
        .tst.currentNs: `;
        
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
