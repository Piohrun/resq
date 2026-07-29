/ lib/static_analysis.q - Static Code Analysis Utilities
/ ============================================================================

.tst.static.toStr:{[x] $[10h=type x; x; string x]};

.tst.static.getDir:{[x]
    x:.tst.static.toStr x;
    if[not count x; :""];
    i:(count x)-(reverse x)?"/";
    $[i=0; ""; i#x]
 };

.tst.static.getBase:{[x]
    x:.tst.static.toStr x;
    if[not count x; :""];
    i:(count x)-(reverse x)?"/";
    i _ x
 };

.tst.static.normalizePath:{[f;base]
    s:.tst.static.toStr f;
    s:$[s like ":*"; 1_s; s];
    b:.tst.static.toStr base;
    b:$[b like ":*"; 1_b; b];
    if[not count b; :s];
    b:$[not "/"=last b; b,"/"; b];
    $[(count b) and s like b,"*"; (count b)_s; s]
 };

.tst.static.rstrip:{[x]
    s:.tst.static.toStr x;
    keep:where not s in " \t";
    $[count keep; (1+last keep)#s; ""]
 };

.tst.static.lstrip:{[x]
    s:.tst.static.toStr x;
    keep:where not s in " \t";
    $[count keep; (first keep)_s; ""]
 };

.tst.static.warn:{[message]
    -2 "DISCOVERY WARNING: ",.tst.static.toStr message;
    (::)
 };

/ q has no lstat primitive. On POSIX, use a fully shell-quoted path solely to
/ identify symlink entries; traversal and file reads themselves remain q-native.
/ The recursion limit below is the independent fail-safe on other platforms.
.tst.static.isSymlink:{[path]
    if[1b~@[get; `.utl.isWindows; 0b]; :0b];
    quoted:.utl.shellQuote .tst.static.toStr path;
    out:@[system; "test -L ",quoted,"; echo $?"; {[e] enlist "1"}];
    $[(count out)>0; 0="J"$last out; 0b]
 };

.tst.static.keyPath:{[path]
    p:.tst.static.toStr path;
    @[
        {[candidate]
            `ok`value`error!(1b;key hsym `$candidate;"")
        };
        p;
        {[p;e]
            .tst.static.warn "Cannot inspect ",p,": ",e;
            `ok`value`error!(0b;();e)
        }[p]]
 };

.tst.static.readableQFile:{[path]
    p:.tst.static.toStr path;
    @[{read0 hsym `$x; 1b}; p; {[p;e]
        .tst.static.warn "Cannot read q file ",p,": ",e;
        0b
    }[p]]
 };

.tst.static.MAX_DEPTH:64;
.tst.static.MAX_ENTRIES:10000;

.tst.static.traversalState:{[files;remaining;warned;problems]
    `files`remaining`warned`problems!(
        files;remaining;warned;problems)
 };

.tst.static.traversalProblem:{[remaining;warned;message]
    .tst.static.traversalState[
        `symbol$();remaining;warned;enlist .tst.static.toStr message]
 };

.tst.static.findSourceEntry:{[base;entry;depth;remaining;warned]
    full:base,$["/"=last base; ""; "/"],string entry;
    remaining-:1;
    inspected:.tst.static.keyPath full;
    if[not inspected`ok;
        :.tst.static.traversalProblem[
            remaining;warned;"Cannot inspect source entry ",full]];
    info:inspected`value;

    if[11h=type info;
        if[.tst.static.isSymlink full;
            :.tst.static.traversalState[
                `symbol$();remaining;warned;()]];
        :.tst.static.findSourcesDepth[full;depth+1;remaining;warned]
    ];

    if[-11h=type info;
        if[full like "*.q";
            if[.tst.static.readableQFile full;
                :.tst.static.traversalState[
                    enlist `$full;remaining;warned;()]];
            :.tst.static.traversalProblem[
                remaining;warned;"Cannot read source q file ",full]];
        :.tst.static.traversalState[
            `symbol$();remaining;warned;()]
    ];

    / The entry existed when its parent was read but vanished or became broken.
    problem:"Source entry vanished or became unreadable: ",full;
    .tst.static.warn problem;
    .tst.static.traversalProblem[remaining;warned;problem]
 };

.tst.static.findSourcesDepth:{[path;depth;remaining;warned]
    p:.tst.static.toStr path;
    if[depth>.tst.static.MAX_DEPTH;
        problem:"Maximum source traversal depth exceeded at ",p;
        .tst.static.warn problem;
        :.tst.static.traversalProblem[remaining;warned;problem]
    ];
    if[not count p;
        problem:"Cannot discover sources from an empty path";
        .tst.static.warn problem;
        :.tst.static.traversalProblem[remaining;warned;problem]
    ];

    inspected:.tst.static.keyPath p;
    if[not inspected`ok;
        :.tst.static.traversalProblem[
            remaining;warned;"Cannot inspect requested source path ",p]];
    info:inspected`value;

    if[-11h=type info;
        if[p like "*.q";
            if[.tst.static.readableQFile p;
                :.tst.static.traversalState[
                    enlist `$p;remaining;warned;()]];
            :.tst.static.traversalProblem[
                remaining;warned;"Cannot read requested source q file ",p]];
        :.tst.static.traversalState[
            `symbol$();remaining;warned;()]
    ];

    if[not 11h=type info;
        problem:"Requested source path is missing or broken: ",p;
        .tst.static.warn problem;
        :.tst.static.traversalProblem[remaining;warned;problem]
    ];
    if[.tst.static.isSymlink p;
        problem:"Requested source directory is a symlink and was not traversed: ",p;
        .tst.static.warn problem;
        :.tst.static.traversalProblem[remaining;warned;problem]];

    entries:asc distinct info;
    entries:entries where not (string entries) like ".*";
    if[not count entries;
        :.tst.static.traversalState[
            `symbol$();remaining;warned;()]];

    files:`symbol$();
    problems:();
    i:0;
    while[i<count entries;
        if[remaining<=0;
            if[not warned;
                problem:"Maximum source traversal entry budget exceeded at ",p;
                .tst.static.warn problem;
                problems,:enlist problem;
                warned:1b;
            ];
            i:count entries;
        ];
        if[i<count entries;
            child:.tst.static.findSourceEntry[
                p;entries i;depth;remaining;warned];
            files,:child`files;
            remaining:child`remaining;
            warned:child`warned;
            problems,:child`problems;
            i+:1;
        ];
    ];
    .tst.static.traversalState[
        files;remaining;warned;problems]
 };

/ A partial walk is useful internally for deterministic diagnostics, but it is
/ never a valid discovery result. Fail at the public boundary so coverage
/ cannot silently omit unreadable or unvisited source.
.tst.static.requireCompleteTraversal:{[state]
    problems:state`problems;
    if[count problems;
        additional:$[(count problems)>1;
            " (and ",string[(count problems)-1]," more traversal problems)";
            ""];
        / Put the failure reason before its path so q's bounded error display
        / cannot hide the important part when a source root is unusually long.
        '"Incomplete source traversal: ",first[problems],additional
    ];
    asc distinct state`files
 };

/ Accept a single q file or a directory. Results are stable across scans.
.tst.static.findSources:{[path]
    state:.tst.static.findSourcesDepth[
        path;0;.tst.static.MAX_ENTRIES;0b];
    .tst.static.requireCompleteTraversal state
 };

/ Mask strings and line comments from one ordinary source line. This is a
/ sequential lexical state machine: character order is semantic, so a loop is
/ clearer and safer than vector operations here.
.tst.static.maskCodeLine:{[line;initialInString;initialEscape]
    inString:initialInString;
    escaped:initialEscape;
    inComment:0b;
    output:"";
    i:0;
    while[i<count line;
        char:line i;
        $[inComment;
            output,:enlist " ";
          inString;
            [ output,:enlist " ";
              $[escaped;
                  escaped:0b;
                char="\\"; escaped:1b;
                char="\""; inString:0b;
                (::)] ];
          char="\"";
            [ inString:1b; output,:enlist " " ];
          (char="/") and ((i=0) or line[i-1] in " \t");
            [ inComment:1b; output,:enlist " " ];
            output,:enlist char];
        i+:1;
    ];
    (output;inString;escaped)
 };

/ Return source lines with comments, strings, block comments, and everything
/ after a q script terminator replaced by spaces. Line lengths are preserved.
.tst.static.maskLines:{[inputLines]
    lines:$[10h=type inputLines; "\n" vs inputLines;
        0h=type inputLines; .tst.static.toStr each inputLines;
        enlist .tst.static.toStr inputLines];
    output:();
    inBlock:0b;
    terminated:0b;
    inString:0b;
    escaped:0b;
    i:0;
    while[i<count lines;
        raw:lines i;
        rightTrimmed:.tst.static.rstrip raw;
        blank:(count raw)#" ";
        $[terminated;
            output,:enlist blank;
          inBlock;
            [ output,:enlist blank;
              if[rightTrimmed~enlist "\\"; inBlock:0b] ];
          (not inString) and rightTrimmed~enlist "/";
            [ inBlock:1b; output,:enlist blank ];
          (not inString) and ((count raw)>0) and
              ("\\"=first raw) and rightTrimmed~enlist "\\";
            [ terminated:1b; output,:enlist blank ];
            [ masked:.tst.static.maskCodeLine[raw;inString;escaped];
              output,:enlist masked 0;
              inString:masked 1;
              escaped:masked 2 ]];
        i+:1;
    ];
    output
 };

.tst.static.executableTokens:{[text]
    masked:"\n" sv .tst.static.maskLines text;
    allowed:.Q.a,.Q.A,.Q.n,"._";
    masked:@[masked; where not masked in allowed; :; " "];
    tokens:" " vs masked;
    distinct tokens where 0<count each tokens
 };

.tst.static.isSystemName:{[name]
    prefixes:(".q";".Q";".z";".h";".j";".kx";".m");
    any {[n;p] (n~p) or n like p,".*"}[name;] each prefixes
 };

.tst.static.findDeps:{[body;selfName]
    self:.tst.static.toStr selfName;
    tokens:.tst.static.executableTokens body;
    tokens:tokens where {
        ((count x)>2) and (("."=first x) and (1<sum x="."))
    } each tokens;
    tokens:tokens where not .tst.static.isSystemName each tokens;
    tokens:tokens except enlist self;
    `$tokens
 };

.tst.static.normalizeNamespace:{[namespace]
    ns:trim .tst.static.toStr namespace;
    if[(count ns) and "`"=first ns; ns:1_ns];
    $[(not count ns) or ns~enlist "."; ""; ns]
 };

.tst.static.validNamespace:{[namespace]
    ns:.tst.static.toStr namespace;
    if[not count ns; :1b];
    if[not "."=first ns; :0b];
    if[ns like "*..*"; :0b];
    all ns in .Q.a,.Q.A,.Q.n,"._"
 };

/ Parse the first quoted literal and return (`ok`text`end)!...
.tst.static.quotedLiteral:{[line;start]
    if[(start>=count line) or not "\""=line start;
        :`ok`text`end!(0b;"";start)];
    output:"";
    escaped:0b;
    closed:0b;
    i:start+1;
    while[(i<count line) and not closed;
        char:line i;
        $[escaped;
            [ output,:enlist char; escaped:0b ];
          char="\\"; escaped:1b;
          char="\""; closed:1b;
          output,:enlist char];
        i+:1;
    ];
    `ok`text`end!(closed;output;i-1)
 };

/ Detect the simple executable form: system "d .namespace"[;]
.tst.static.runtimeNamespace:{[raw;masked]
    code:.tst.static.lstrip masked;
    original:.tst.static.lstrip raw;
    if[not code like "system *"; :`found`namespace!(0b;"")];
    quoteAt:original?"\"";
    if[quoteAt=count original; :`found`namespace!(0b;"")];
    if[not "system"~trim quoteAt#original;
        :`found`namespace!(0b;"")];
    literal:.tst.static.quotedLiteral[original;quoteAt];
    if[not literal`ok; :`found`namespace!(0b;"")];
    tail:trim (1+literal`end)_code;
    if[(count tail) and not tail~enlist ";";
        :`found`namespace!(0b;"")];
    command:literal`text;
    if[not command like "d *"; :`found`namespace!(0b;"")];
    ns:trim 2_command;
    if[(not count ns) or " " in ns;
        :`found`namespace!(0b;"")];
    ns:.tst.static.normalizeNamespace ns;
    if[not .tst.static.validNamespace ns;
        :`found`namespace!(0b;"")];
    `found`namespace!(1b;ns)
 };

/ Detect a column-1 \d namespace directive from executable text.
.tst.static.directiveNamespace:{[raw;masked]
    if[not masked like "\\d *"; :`found`namespace!(0b;"")];
    command:.tst.static.rstrip masked;
    ns:trim 3_command;
    if[(not count ns) or " " in ns;
        :`found`namespace!(0b;"")];
    ns:.tst.static.normalizeNamespace ns;
    if[not .tst.static.validNamespace ns;
        :`found`namespace!(0b;"")];
    `found`namespace!(1b;ns)
 };

.tst.static.validFunctionName:{[name]
    n:trim .tst.static.toStr name;
    if[not count n; :0b];
    allowed:.Q.a,.Q.A,.Q.n,"._";
    if[not all n in allowed; :0b];
    if[first[n] in .Q.n,"_"; :0b];
    if[n like "*..*"; :0b];
    1b
 };

.tst.static.qualifyName:{[name;namespace]
    n:.tst.static.toStr name;
    $["."=first n; n; count namespace; namespace,".",n; n]
 };

.tst.static.definitionArgs:{[masked;braceAt]
    after:.tst.static.lstrip (braceAt+1)_masked;
    if[(not count after) or not "["=first after; :()];
    closeAt:after?"]";
    if[closeAt=count after; :()];
    args:trim each ";" vs (closeAt-1)#1_after;
    args where 0<count each args
 };

/ Find a supported top-level `name:{...}`, `name::{...}`, or
/ ``name set {...}` definition.
.tst.static.definitionStart:{[masked;namespace]
    braceAt:masked?"{";
    if[braceAt=count masked; :()];
    prefix:trim braceAt#masked;
    if[not count prefix; :()];
    name:"";

    if[":"=last prefix;
        / q's persistent/global assignment uses the exact adjacent `::`
        / token. Strip at most that token (or the ordinary single `:`), so
        / spaced/multi-colon assignment expressions remain unsupported.
        candidate:$[prefix like "*::";trim -2_prefix;trim -1_prefix];
        if[.tst.static.validFunctionName candidate; name:candidate]
    ];

    if[not count name;
        words:" " vs ssr[prefix;"\t";" "];
        words:words where 0<count each words;
        if[(count words)=2;
            if[(last words)~"set";
                candidate:first words;
                if[(count candidate) and "`"=first candidate; candidate:1_candidate];
                if[.tst.static.validFunctionName candidate; name:candidate]
            ]
        ]
    ];

    if[not count name; :()];
    `name`args!(
        .tst.static.qualifyName[name;namespace];
        .tst.static.definitionArgs[masked;braceAt])
 };

.tst.static.emptyFunctions:{[]
    ([] name:`$(); args:(); line:`int$(); srcFile:`$();
        dependencies:(); body:())
 };

.tst.static.readSource:{[file]
    handle:$[10h=type file; hsym `$file; file];
    sourceLabel:.tst.static.toStr file;
    @[
        {[sourceHandle]
            `ok`lines`error!(1b;read0 sourceHandle;"")
        };
        handle;
        {[sourceLabel;e]
            .tst.static.warn "Cannot read source ",sourceLabel,": ",e;
            `ok`lines`error!(0b;();e)
        }[sourceLabel]]
 };

.tst.static.exploreFile:{[file]
    readResult:.tst.static.readSource file;
    if[not readResult`ok;
        '"Unable to explore source file ",.tst.static.toStr[file],
            ": ",readResult`error];
    lines:readResult`lines;
    maskedLines:.tst.static.maskLines lines;
    functions:.tst.static.emptyFunctions[];
    currentNamespace:"";
    inFunction:0b;
    braceDepth:0;
    currentName:"";
    currentArgs:();
    currentLine:0i;
    currentBody:"";
    i:0;

    while[i<count lines;
        raw:lines i;
        masked:maskedLines i;

        if[not inFunction;
            directive:.tst.static.directiveNamespace[raw;masked];
            if[directive`found; currentNamespace:directive`namespace];
            runtime:.tst.static.runtimeNamespace[raw;masked];
            if[runtime`found; currentNamespace:runtime`namespace];

            start:.tst.static.definitionStart[masked;currentNamespace];
            if[99h=type start;
                currentName:start`name;
                currentArgs:start`args;
                currentLine:`int$i+1;
                currentBody:raw;
                inFunction:1b;
            ];
        ];

        if[inFunction;
            if[(i+1)>currentLine; currentBody,:enlist "\n"; currentBody,:raw];
            braceDepth+:sum[masked="{"]-sum masked="}";
            if[braceDepth<=0;
                fileSymbol:$[-11h=type file; file; `$ .tst.static.toStr file];
                dependencies:.tst.static.findDeps[currentBody;currentName];
                functions: functions upsert (
                    `$currentName;
                    currentArgs;
                    currentLine;
                    fileSymbol;
                    dependencies;
                    currentBody);
                inFunction:0b;
                braceDepth:0;
            ];
        ];
        i+:1;
    ];
    0!functions
 };
