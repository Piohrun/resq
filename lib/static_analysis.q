/ lib/static_analysis.q - Static Code Analysis Utilities
/ ============================================================================

.tst.static.toStr:{[x] $[10h=type x; x; string x] }

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
      if[(count newNs) and not " " in newNs; currentNs: $[newNs~"."; ""; newNs]];
    ];
    if[(not inFunc) and (braceDepth=0);
       isColon: cleanL like funcPat;
       isSet: cleanL like "* set {*";  / Remove extra wildcard in middle
       
       if[isColon or isSet;
           bracePos: l ? .tst.static.LBRACE;
           
           / Verify brace is real (masked check)
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
