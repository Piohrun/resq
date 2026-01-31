/ lib/loader_discovery.q - Automatic Loader Detection & Hijacking
/ ============================================================================

/ Dependencies
.utl.require "lib/static_analysis.q"
.utl.require "lib/coverage.q"

/ Check if a function body contains loading logic
/ @param body (string) Function body
/ @return (boolean) True if it looks like a loader
.tst.loader.isLoader:{[body]
    / Normalize body to flat string
    s: raze body;
    if[not 10h=abs type s; :0b];
    
    / Simple check for system "l" or value "\l"
    / Use ss to avoid regex issues
    hasSystem: (0 < count s ss "system") and (0 < count s ss "\"l");
    hasValue: (0 < count s ss "value") and (0 < count s ss "\"\\l");
    
    hasSystem or hasValue
 };

/ Scan directory for potential loaders
/ @param dir (symbol/string) Directory to scan
/ @return (table) Candidates [name; file; args]
.tst.loader.findLoaders:{[dir]
    files: .tst.static.findSources dir;
    
    candidates: raze {[f]
        hs: $[10h=type f; hsym `$f; -11h=type f; hsym f; hsym `$string f];
        fns: .tst.static.exploreFile hs;
        if[not count fns; :()];
        
        found: select name, file:srcFile, args:count each args from fns where .tst.loader.isLoader each body;
        
        / Normalize
        update args:1 from found / Default to 1 arg for now
    } each files;
    
    candidates
 };

/ Wrapper function definition (must be global for injection)
.tst.loader.wrapper: { [funcName; origName; argIdx; args] 
    / Call original first
    res: (value origName) . args;
    
    / Extract file path
    path: $[10h=abs type args; args; args argIdx];
    
    / Instrument if enabled
    if[.tst.coverageEnabled;
        .tst.instrumentFile path;
    ];
    
    res
 };

/ Hijack a specific loader function
/ @param funcName (symbol) The function to hijack (e.g. `.core.load`)
/ @param argIdx (int) The index of the file path argument (0-based)
.tst.loader.hijack:{[funcName; argIdx]
    if[() ~ key funcName; 
        -1 "DEBUG: ", string[funcName], " has no key entry";
        :()
    ]; / Must be loaded to hijack
    
    / 1. Save Original
    origName: ` sv `.tst.origLoader, funcName;
    if[not origName in key `; 
        origName set value funcName;
    ];
    
    / 2. Apply Patch
    origVal: value funcName;
    paramList: value[origVal] 1;
    paramStr: ";" sv string paramList;
    
    body: ".tst.loader.wrapper[`" ,string[funcName],";`",string[origName],";",string[argIdx],";",
        $[1=count paramList; "enlist ",paramStr; "(",paramStr,")"], "]";
    
    code: "{[ ",paramStr,"] ",body,"}";
    
    -1 "Hijacking Loader: ", string[funcName];
    funcName set value code;
 };

/ Auto-Discover and Hijack
/ @param dir (string) Directory to scan for loaders
.tst.loader.autoHijack:{[dir]
    loaders: .tst.loader.findLoaders dir;
    if[0<count loaders;
        -1 "Found ",string[count loaders]," potential loaders.";
        { .tst.loader.hijack[x`name; 0] } each loaders; / Assume arg 0 is file
    ];
 };
