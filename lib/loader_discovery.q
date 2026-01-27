/ lib/loader_discovery.q - Automatic Loader Detection & Hijacking
/ ============================================================================

\d .tst.loader

/ Dependencies
.utl.require "lib/static_analysis.q"
.utl.require "lib/coverage.q"

/ Check if a function body contains loading logic
/ @param body (string) Function body
/ @return (boolean) True if it looks like a loader
isLoader:{[body]
    / Normalize body
    s: body;
    / Simple check for system "l" or value "\l"
    hasSystem: (s like "*system*\"l*" ) or (s like "*system* \"l*" );
    hasValue: (s like "*value*\"\\l*" ) or (s like "*value* \"\\l*" );
    
    hasSystem or hasValue
 };

/ Scan directory for potential loaders
/ @param dir (symbol/string) Directory to scan
/ @return (table) Candidates [name; file; args]
findLoaders:{[dir]
    files: .tst.static.findSources dir;
    
    candidates: raze {[f]
        fns: .tst.static.exploreFile hsym `$f;
        if[not count fns; :()];
        
        found: select name, file:srcFile, args:count each args from fns where isLoader each body;
        
        / Normalize
        update args:1 from found / Default to 1 arg for now
    } each files;
    
    candidates
 };
/ Hijack a specific loader function
/ @param funcName (symbol) The function to hijack (e.g. `.core.load`)
/ @param argIdx (int) The index of the file path argument (0-based)
hijack:{[funcName; argIdx]
    if[not funcName in key `; :()]; / Must be loaded to hijack
    
    / 1. Save Original
    origName: ` sv `.tst.origLoader, funcName;
    if[not origName in key `; 
        origName set value funcName;
    ];
    
    / 2. Create Wrapper
    / We assume the function takes arguments. We need to preserve them.
    / We will use a generic apply definition.
    
    wrapper: { [funcName; origName; argIdx; args] 
        / Call original first
        res: origName . args;
        
        / Extract file path
        path: args argIdx;
        
        / Instrument if enabled
        if[.tst.coverageEnabled;
            / We need to handle if path is symbol or string
            / instrumentFile handles resolution
            .tst.instrumentFile path;
        ];
        
        res
    };
    
    / 3. Apply Patch
    / We need to know arity to generate correct lambda signature?
    / Or we can use .z.s style?
    / Kdb functions must declare args to accept them cleanly.
    
    origVal: value funcName;
    paramList: value[origVal] 1;
    paramStr: ";" sv string paramList;
    
    body: ".tst.loader.wrapper[`" ,string[funcName],";`",string[origName],";",string[argIdx],";(",paramStr,")]";
    
    code: "{[ ",paramStr,"] ",body,"}";
    
    -1 "Hijacking Loader: ", string[funcName];
    funcName set value code;
 };

/ Auto-Discover and Hijack
/ @param dir (string) Directory to scan for loaders
autoHijack:{[dir]
    loaders: findLoaders dir;
    if[0<count loaders;
        -1 "Found ",string[count loaders]," potential loaders.";
        { hijack[x`name; 0] } each loaders; / Assume arg 0 is file
    ];
 };

\d 
