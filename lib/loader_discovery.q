/ lib/loader_discovery.q - Automatic Loader Detection & Hijacking
/ ============================================================================

/ Dependencies
.utl.require .utl.PKGLOADING,"/static_analysis.q"
.utl.require .utl.PKGLOADING,"/coverage.q"

/ Experimental loader hijacking is OFF by default. autoHijack/hijack rewrite
/ user functions via string-built code (value), so they must be opted into
/ explicitly by setting `.tst.loaderHijackEnabled: 1b` from code. `resq
/ discover` does not use hijacking, so it is unaffected by this gate.
if[not `loaderHijackEnabled in key `.tst; .tst.loaderHijackEnabled: 0b];

/ Check if a function body contains loading logic
/ @param body (string) Function body
/ @return (boolean) True if it looks like a loader
.tst.loader.isLoader:{[body]
    / Normalize body to flat string
    s: raze body;
    if[not 10h=abs type s; :0b];

    / Require the actual loading SEQUENCES, not independent substrings:
    / `system "l` or `value "\l`. ss returns match positions; a non-empty
    / result means the sequence is present. This kills false positives like
    / "latency" (contains "l" near "system"-ish text) matching on fragments.
    hasSystem: 0 < count s ss "system \"l";
    hasValue: 0 < count s ss "value \"\\l";

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
    if[not 1b ~ .tst.loaderHijackEnabled;
        '"loader hijacking is disabled; set .tst.loaderHijackEnabled:1b to enable (experimental)"
    ];
    if[() ~ key funcName;
        if[.utl.DEBUG; -1 "DEBUG: ", string[funcName], " has no key entry"];
        :()
    ]; / Must be loaded to hijack

    / 1. Save Original. Use a FLAT backing name: `` ` sv `.tst.origLoader, `.ns.fn ``
    / would produce an invalid double-dot symbol (`.tst.origLoader..ns.fn`), so
    / encode the dotted function name into a single flat symbol instead.
    fnStr: string funcName;
    fnStr: $["." = first fnStr; 1 _ fnStr; fnStr];  / drop only a leading dot
    origName: `$".tst.origLoader_", ssr[fnStr; "."; "_"];
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
    if[not 1b ~ .tst.loaderHijackEnabled;
        '"loader hijacking is disabled; set .tst.loaderHijackEnabled:1b to enable (experimental)"
    ];
    loaders: .tst.loader.findLoaders dir;
    if[0<count loaders;
        -1 "Found ",string[count loaders]," potential loaders.";
        { .tst.loader.hijack[x`name; 0] } each loaders; / Assume arg 0 is file
    ];
 };
