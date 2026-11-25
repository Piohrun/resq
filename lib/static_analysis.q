/ lib/static_analysis.q - Static Code Analysis Utilities
/ ============================================================================

.tst.static.toStr:{[x] $[10h=type x; x; string x] }

.tst.static.rstrip:{[x]
    s: .tst.static.toStr x;
    keep: where not s in " \t";
    $[count keep; (1+last keep)#s; ""]
 }

/ Blank out the non-executable spans of ONE line, preserving its length so
/ character offsets stay comparable with the raw text. Returns the masked line
/ plus the string/escape state to carry into the next line.
/ A "/" only opens a comment at line start or after whitespace -- that is q's
/ actual rule, and the reason `a/b` (divide) survives masking.
.tst.static.maskCodeLine:{[line;initialInString;initialEscape]
    inString: initialInString;
    escaped: initialEscape;
    inComment: 0b;
    output: "";
    i: 0;
    while[i < count line;
        char: line i;
        $[inComment;
            output,: enlist " ";
          inString;
            [ output,: enlist " ";
              $[escaped;      escaped: 0b;
                char="\\";    escaped: 1b;
                char="\"";    inString: 0b;
                (::)] ];
          char="\"";
            [ inString: 1b; output,: enlist " " ];
          (char="/") and ((i=0) or line[i-1] in " \t");
            [ inComment: 1b; output,: enlist " " ];
            output,: enlist char];
        i+: 1;
    ];
    (output; inString; escaped)
 }

/ Shared cross-line driver. Walking a q source file correctly means tracking
/ three pieces of state BETWEEN lines: how many block comments are open (a lone
/ "/" opens one, a lone "\\" closes one, and q nests them), whether the script has been terminated
/ (a line starting "\\" that is otherwise bare), and whether a string literal is
/ still open with a pending escape. That logic is subtle and was duplicated
/ verbatim in two places; a fix to one would silently miss the other.
/ blankFn: value to emit for a line that is skipped (in a block comment or past
/ the terminator). lineFn: (raw; inString; escaped) -> (value; inString; escaped).
.tst.static.scanSourceLines:{[lines; blankFn; lineFn]
    output: ();
    inBlock: 0;
    terminated: 0b;
    inString: 0b;
    escaped: 0b;
    i: 0;
    while[i < count lines;
        raw: lines i;
        rightTrimmed: .tst.static.rstrip raw;
        $[terminated;
            output,: enlist blankFn raw;
          inBlock > 0;
            [ output,: enlist blankFn raw;
              inBlock+: $[rightTrimmed ~ enlist "/"; 1; rightTrimmed ~ enlist "\\"; -1; 0] ];
          (not inString) and rightTrimmed ~ enlist "/";
            [ inBlock: 1; output,: enlist blankFn raw ];
          (not inString) and ((count raw) > 0) and
              ("\\" = first raw) and rightTrimmed ~ enlist "\\";
            [ terminated: 1b; output,: enlist blankFn raw ];
            [ step: lineFn[raw; inString; escaped];
              output,: enlist step 0;
              inString: step 1;
              escaped: step 2 ]];
        i+: 1;
    ];
    output
 }

/ Return source lines with comments, strings, block comments and everything
/ after a script terminator replaced by spaces. Line lengths are preserved, so
/ an offset into the masked text indexes the same character in the raw text.
/ A lone "/" line opens a block comment (closed by a lone "\"); a line starting
/ with "\" that is otherwise bare terminates the script.
.tst.static.maskLines:{[inputLines]
    lines: $[10h = type inputLines; "\n" vs inputLines;
             0h  = type inputLines; .tst.static.toStr each inputLines;
             enlist .tst.static.toStr inputLines];
    .tst.static.scanSourceLines[lines; {(count x)#" "}; .tst.static.maskCodeLine]
 }

.tst.static.validFunctionName:{[name]
    n: trim .tst.static.toStr name;
    if[not count n; :0b];
    allowed: .Q.a, .Q.A, .Q.n, "._";
    if[not all n in allowed; :0b];
    if[first[n] in .Q.n, "_"; :0b];
    if[n like "*..*"; :0b];
    1b
 }

/ Return the exact q identifiers present in executable source. Strings,
/ comments, block comments and text after a script terminator are masked first;
/ punctuation then becomes a separator while namespace dots remain part of the
/ token. This is deliberately lexical rather than an evaluator: discovery is
/ advisory, but a reference to .app.runAll must never count as .app.run.
.tst.static.symbolTokens:{[source]
    lines: $[10h=type source; "\n" vs source;
             0h=type source; .tst.static.toStr each source;
             enlist .tst.static.toStr source];
    s: "\n" sv .tst.static.maskLines lines;
    allowed: .Q.a, .Q.A, .Q.n, "._";
    s: @[s; where not s in allowed; :; " "];
    tokens: " " vs s;
    distinct tokens where 0 < count each tokens
 }

.tst.static.hasExactSymbol:{[source;name]
    .tst.static.toStr[name] in .tst.static.symbolTokens source
 }

.tst.static.getDir:{[x]
  x: .tst.static.toStr x; 
  if[not count x; :"" ];
  i: (count x) - (reverse x) ? "/"; 
  $[i=0; ""; i # x] 
 }

.tst.static.getBase:{[x] 
  x: .tst.static.toStr x; 
  if[not count x; :"" ];
  i: (count x) - (reverse x) ? "/"; 
  i _ x 
 }

.tst.static.normalizePath:{[f;base]
  s: .tst.static.toStr f;
  s: $[s like ":*"; 1 _ s; s];
  b: .tst.static.toStr base;
  b: $[b like ":*"; 1 _ b; b];
  if[not count b; :s];
  b: $[not "/"=last b; b, "/"; b];
  $[(count b) and s like b, "*"; (count b) _ s; s]
 }

.tst.static.findSources:{[p]
  p: .tst.static.toStr p;

  / Accept either a directory or a single q file. The previous implementation
  / appended "/" unconditionally, which made single-file discovery fail.
  if[p like "*.q";
    if[@[{read0 x; 1b}; hsym `$p; {0b}]; :enlist `$p];
  ];

  if[(count p) and not "/"=last p; p,: "/"];
  found: .tst.static.symlinksUnder p;
  .tst.static.findSourcesUnder[first found; last found; 0; p]
 }

/ "a//b" and "a/b" are one path. BSD find prints the first for a root given
/ with a trailing slash.
.tst.static.squeezeSlashes:{[s] s where not (s = "/") and "/" = prev s}

/ Symbolic links under a root, found with one subprocess: (found; paths).
/ `found` is 0b when the search could not run.
.tst.static.symlinksUnder:{[p]
  @[{[p] (1b; `$.tst.static.squeezeSlashes each system "find ", .resq.util.shellQuote[p], " -type l 2>/dev/null")};
    p; {[e] (0b; `symbol$())}]
 }

/ A linked directory is not descended into, as in test discovery. One that
/ points at an ancestor (`ln -s .. src/loop`) otherwise recurses until the OS
/ gives up, which ended `resq watch` and `resq mutate <dir>` with "Too many
/ levels of symbolic links". When the one search for links could not run, each
/ directory is checked on its own; the depth limit is the backstop for both.
.tst.static.findSourcesUnder:{[known;links;depth;p]
  if[depth > 32; :`symbol$()];
  pts: @[key; hsym `$p; {[e] ()}];
  if[() ~ pts; :`symbol$()];
  pts: pts where not (string pts) like ".*";
  if[not count pts; :`symbol$()];
  raze {[known;links;depth;p;f]
    full: p, string f;
    listing: @[key; hsym `$full; {[e] ()}];
    if[() ~ listing; :`symbol$()];
    itemType: type listing;
    if[(itemType < 0) and full like "*.q"; :enlist `$full];
    if[not itemType = 11h; :`symbol$()];
    linked: $[known; (`$.tst.static.squeezeSlashes full) in links; .tst.isSymlink full];
    $[linked; `symbol$(); .tst.static.findSourcesUnder[known; links; depth + 1; full, "/"]]
  }[known;links;depth;p] each pts
 }

.tst.static.findDeps:{[body;selfName]
  tokens: .tst.static.symbolTokens body;
  tokens: tokens where (count each tokens) > 2;
  deps: tokens where { ("."=first x) and "." in 1_x } each tokens;
  deps: deps where not deps like ".q.*";
  deps: deps where not deps like ".Q.*";
  deps: deps where not deps like ".z.*";
  deps: deps where not deps like ".h.*";
  deps: deps where not deps like ".j.*";
  deps: deps where not deps like ".kx.*";
  deps: deps where not deps like ".m.*";
  deps: deps except enlist selfName;
  `$deps
 }

/ Character constants to avoid q parser issues with braces in strings
.tst.static.LBRACE: "c"$123  / "{"
.tst.static.RBRACE: "c"$125  / "}"

.tst.static.exploreFile:{[file]
  emptyResult: ([] name:`$(); args:(); line:`int$(); srcFile:`$(); dependencies:(); body:());
  fHandle: $[10h=type file; hsym `$file; file];
  if[() ~ key fHandle; :emptyResult];
  lines: read0 fHandle;
  fns: ([name:`$()] args:(); line:`int$(); srcFile:`$(); dependencies:(); body:());
  currentNs: "";
  inFunc: 0b;
  braceDepth: 0;
  / Braces of blocks that are not a function found here: a desc block, a
  / lambda kept by index (`asserts[`m]:{...}`). A definition inside one is
  / not one of the file's, and was taken for one.
  outerDepth: 0;
  currName: "";
  currBody: "";
  currArgs: ();
  currLine: 0;
  / Strings, comments, block comments and what follows the script
  / terminator masked as everywhere else (.tst.static.maskLines). This loop
  / had a copy of its own that knew no block comments, so a function in one
  / was reported as defined.
  masked: .tst.static.maskLines lines;

  / Pattern for function definition: *:{*
  funcPat: "*:", (enlist .tst.static.LBRACE), "*";
  / Characters to exclude from function names
  badChars: " \t()[]", (enlist .tst.static.LBRACE), (enlist .tst.static.RBRACE), "/";

  i: 0;
  do[count lines;
    l: lines i;
    cleanL: trim l;
    maskedL: masked i;
    / a line q does not run: a comment, a block comment, string contents
    live: any not maskedL in " \t";
    delta: sum (maskedL=.tst.static.LBRACE) - (maskedL=.tst.static.RBRACE);
    wasInFunc: inFunc;
    / A namespace is entered with `\d .ns` or with `system "d .ns"`. Only
    / the first form was followed, so a source file written with the second
    / (resQ's own example project is) had every function recorded without its
    / namespace, matched no test, and was reported as 0% referenced.
    systemNs: $[cleanL like "system \"d *";
        [body: (count "system \"d ") _ cleanL; trim (body ? "\"") # body];
        ""];
    / Not inside a block: a `system "d .x"` in a desc block or a lambda runs
    / when that does, not as the file loads.
    if[(braceDepth=0) and (outerDepth=0) and live and (cleanL like "\\d *") or 0 < count systemNs;
      newNs: $[count systemNs; systemNs; trim 3 _ cleanL];
      / `\d .` resets to the root namespace. newNs is a 1-char string ".",
      / so compare against `enlist "."` -- comparing to the char atom "."
      / never matches and leaves a stale "." prefix on later globals.
      if[(count newNs) and not " " in newNs; currentNs: $[newNs ~ enlist "."; ""; newNs]];
    ];
    if[(not inFunc) and (braceDepth=0) and (outerDepth=0) and live;
       / Collapse whitespace around the first ":" so `name: {` (space after
       / the colon, or before it) is detected the same as `name:{`. We only
       / normalize for definition detection / name extraction below; the raw
       / cleanL is still used for body capture.
       normL: cleanL;
       if[":" in cleanL;
         ci: cleanL ? ":";
         lhs: trim ci # cleanL;
         rhs: trim (ci+1) _ cleanL;
         normL: lhs, ":", rhs;
       ];
       isColon: normL like funcPat;
       isSet: cleanL like "* set {*";  / Remove extra wildcard in middle
       
       if[isColon or isSet;
           bracePos: l ? .tst.static.LBRACE;
           
           / Verify brace is real (masked check)
           if[bracePos < count maskedL;
           if[maskedL[bracePos] = .tst.static.LBRACE;
              validStart: 0b;
              
              if[isColon;
                  parts: ":" vs cleanL;
                  namePart: trim first parts;
                  if[(count namePart) and not any namePart in badChars;
                      currName: $[namePart like ".*"; namePart; count currentNs; currentNs,".",namePart; namePart];
                      validStart: 1b;
                  ];
              ];
              
              if[isSet;
                  parts: " set " vs cleanL;
                  namePart: trim first parts;
                  / Handle symbol usage `myFunc set ...
                  if[namePart like "`*"; namePart: 1 _ namePart];
                  
                  if[(count namePart) and not any namePart in badChars;
                      currName: $[namePart like ".*"; namePart; count currentNs; currentNs,".",namePart; namePart];
                      validStart: 1b;
                  ];
              ];

              if[validStart;
                  currLine: i+1;
                  currBody: cleanL;
                  currArgs: ();
                  / A lambda has an explicit argument declaration only when
                  / the first executable character after "{" is "[". The old
                  / first-bracket search misclassified indexing such as
                  / f:{x[0]+1} as a one-argument declaration.
                  tailMasked: (bracePos+1) _ maskedL;
                  codePositions: where not tailMasked in " \t";
                  if[count codePositions;
                    openRel: first codePositions;
                    closeRel: tailMasked ? "]";
                    if[((tailMasked openRel)="[") and (openRel < closeRel);
                      tailRaw: (bracePos+1) _ l;
                      argPart: (openRel+1) _ closeRel # tailRaw;
                      currArgs: trim each ";" vs argPart;
                      / Remove empty args
                      currArgs: currArgs where 0 < count each currArgs;
                    ];
                  ];
                  inFunc: 1b;
              ];
           ];
           ];
       ];
    ];
    if[inFunc;
        if[i+1 > currLine; currBody,: " ", l];
        before: braceDepth;
        braceDepth+: delta;
        if[braceDepth <= 0;
            inFunc: 0b;
            braceDepth: 0;
            / Only a lambda that is the whole value is a function: after its
            / closing brace come at most ";", a bracket that closes around it
            / (`if[c; f:{...}]`) and a comment. `x:{...} getenv y` and
            / `x:{...}[]` are values, and were reported as functions.
            from: $[(i+1)=currLine; bracePos; 0];
            depthAt: before + sums (maskedL=.tst.static.LBRACE) - maskedL=.tst.static.RBRACE;
            closeAt: first where (depthAt<=0) and (til count maskedL) >= from;
            rest: $[null closeAt; ""; (1+closeAt) _ maskedL];
            rest: rest where not rest in " \t\r";
            plain: (0=count rest) or (first rest) in ";])";
            deps: .tst.static.findDeps[currBody; currName];
            / Ensure args is a enlisted list of strings if empty
            if[0=count currArgs; currArgs: enlist ""];
            if[currArgs ~ enlist ""; currArgs: ()]; 
            
            fileSym: $[10h=type file; `$file; -11h=type file; file; `$string file];
            row: (`$currName; currArgs; currLine; fileSym; enlist deps; enlist currBody);
            if[plain; fns: fns upsert row];
        ];
    ];
    / a line that is no function's, and starts none
    if[(not wasInFunc) and not currLine=i+1; outerDepth: 0|outerDepth+delta];
    i+: 1;
  ];
  0!fns }
