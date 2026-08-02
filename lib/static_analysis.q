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
/ three pieces of state BETWEEN lines: whether a block comment is open (a lone
/ "/" opens it, a lone "\\" closes it), whether the script has been terminated
/ (a line starting "\\" that is otherwise bare), and whether a string literal is
/ still open with a pending escape. That logic is subtle and was duplicated
/ verbatim in two places; a fix to one would silently miss the other.
/ blankFn: value to emit for a line that is skipped (in a block comment or past
/ the terminator). lineFn: (raw; inString; escaped) -> (value; inString; escaped).
.tst.static.scanSourceLines:{[lines; blankFn; lineFn]
    output: ();
    inBlock: 0b;
    terminated: 0b;
    inString: 0b;
    escaped: 0b;
    i: 0;
    while[i < count lines;
        raw: lines i;
        rightTrimmed: .tst.static.rstrip raw;
        $[terminated;
            output,: enlist blankFn raw;
          inBlock;
            [ output,: enlist blankFn raw;
              if[rightTrimmed ~ enlist "\\"; inBlock: 0b] ];
          (not inString) and rightTrimmed ~ enlist "/";
            [ inBlock: 1b; output,: enlist blankFn raw ];
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
  h: hsym `$p;
  if[() ~ key h; :`symbol$()];
  pts: key h;
  pts: pts where not (string pts) like ".*";
  if[not count pts; :`symbol$()];
  raze { [p;f] 
    full: p, string f;
    h: hsym `$full;
    if[() ~ key h; :`symbol$()];
    itemType: type key h;
    $[itemType=11h; .tst.static.findSources[full]; 
      (itemType<0) and full like "*.q"; enlist `$full; 
      `symbol$()]
  }[p] each pts
 }

.tst.static.findDeps:{[body;selfName]
  s: body;
  s: @[s; where s in "()[]{};:\"\n\t"; :; " "];
  tokens: " " vs s;
  tokens: distinct tokens where (count each tokens) > 2;
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
  currName: "";
  currBody: "";
  currArgs: ();
  currLine: 0;
  pState: `inStr`inComm`esc`braceDepth!(0b;0b;0b;0);

  / Pattern for function definition: *:{*
  funcPat: "*:", (enlist .tst.static.LBRACE), "*";
  / Characters to exclude from function names
  badChars: " \t()[]", (enlist .tst.static.LBRACE), (enlist .tst.static.RBRACE), "/";

  i: 0;
  do[count lines;
    l: lines i;
    cleanL: trim l;
    inStr: pState`inStr;
    inComm: 0b;
    esc: pState`esc;
    res: "";
    j: 0;
    cnt: count l;
    do[cnt;
        c: l j;
        $[inComm; res,: " ";
          inStr; (
            $[esc; esc: 0b;
              c="\\"; esc: 1b;
              c="\""; inStr: 0b;
              (::)];
            res,: " "
          );
          $[c="\""; (inStr: 1b; res,: " ");
            (c="/") and ((j=0) or (l[j-1] in " \t")); (inComm: 1b; res,: " ");
            res,: c
          ]
        ];
        j+:1;
    ];
    delta: sum (res=.tst.static.LBRACE) - (res=.tst.static.RBRACE);
    pState[`inStr]: inStr;
    pState[`esc]: esc;
    maskedL: res;
    if[(braceDepth=0) and (not pState`inStr) and cleanL like "\\d *";
      newNs: trim 3 _ cleanL;
      / `\d .` resets to the root namespace. newNs is a 1-char string ".",
      / so compare against `enlist "."` -- comparing to the char atom "."
      / never matches and leaves a stale "." prefix on later globals.
      if[(count newNs) and not " " in newNs; currentNs: $[newNs ~ enlist "."; ""; newNs]];
    ];
    if[(not inFunc) and (braceDepth=0);
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
                  if[(cleanL?"[") < cleanL?"]";
                    argPart: (1 + cleanL?"[") _ (cleanL?"]") # cleanL;
                    currArgs: trim each ";" vs argPart;
                    / Remove empty args
                    currArgs: currArgs where 0 < count each currArgs;
                  ];
                  inFunc: 1b;
              ];
           ];
           ];
       ];
    ];
    if[inFunc;
        if[i+1 > currLine; currBody,: " ", l];
        braceDepth+: delta;
        if[braceDepth <= 0;
            inFunc: 0b;
            braceDepth: 0;
            deps: .tst.static.findDeps[currBody; currName];
            / Ensure args is a enlisted list of strings if empty
            if[0=count currArgs; currArgs: enlist ""];
            if[currArgs ~ enlist ""; currArgs: ()]; 
            
            fileSym: $[10h=type file; `$file; -11h=type file; file; `$string file];
            row: (`$currName; currArgs; currLine; fileSym; enlist deps; enlist currBody);
            fns: fns upsert row;
        ];
    ];
    i+: 1;
  ];
  0!fns }
