/ ============================================================================
/ Tests for lib/mutate.q - mutation testing.
/ .
/ What matters most, in order:
/   - a mutant is a small, valid change to the function and nothing else;
/   - a function is mutated only when memory holds the definition in the file;
/   - "killed" is never reported without proof the mutant was in place.
/ The last group runs `resq mutate` for real on a generated project and reads
/ the JSON report. Helpers and state live under .tst.testState.mut (the
/ pollution guard skips the `tst` namespace).
/ ============================================================================

.tst.testState.mut.texts:{[text;family] (.tst.mutate.generate[text; enlist family])`text};
.tst.testState.mut.notes:{[text;family] (.tst.mutate.generate[text; enlist family])`note};
.tst.testState.mut.full:{[text] .tst.mutate.generate[text; .tst.mutate.families]};
.tst.testState.mut.has:{[strings;s] any strings~\:s};

/ Functions used as mutation input by several tests.
.tst.testState.mut.samples: (
  "{[qty;px] total: qty*px; if[total<0; '\"negative\"]; $[qty>=100; total*0.9; total]}";
  "{[x] x:0|x; x&100}";
  "{[n] i:0; s:0; while[i<n; s+:i; i+:1]; s}";
  "{[t] select from t where a>1, not b in 1 2 3}";
  "{[x;y]\n  / a comment with x+y in it\n  a: first x;   / trailing\n  if[a=y; :neg a];\n  a+y\n }";
  "{x+y}";
  "{}");

/ Write `lines` to a scratch file and return its path.
.tst.testState.mut.scratch:{[name;lines]
  dir: .utl.tempRoot[], "/resq_mut_", string[.z.i], "_", string `long$.z.p;
  system "mkdir -p ", .utl.shellQuote dir;
  path: dir, "/", name;
  (hsym `$path) 0: lines;
  path
 };
.tst.testState.mut.drop:{[path] system "rm -rf ", .utl.shellQuote .tst.static.getDir path; };

/ Run `body` against a child state of the test's own, loaded from a plan file
/ as a real child loads its plan. The state is named .tst.testState.mut.state,
/ so the process's own (it may itself be a mutation child) is left alone.
/ Returns what body returned and the status lines the plan produced.
.tst.testState.mut.withPlan:{[plan;body]
  path: .tst.testState.mut.scratch["plan"; enlist ""];
  status: path, ".status";
  plan[`status]: status;
  (hsym `$path) set plan;
  loaded: .tst.mutate.loadPlan[`.tst.testState.mut.state; path];
  r: @[{[f] (1b; f[])}; body; {[e] (0b; e)}];
  lines: @[read0; hsym `$status; {[e] ()}];
  .tst.testState.mut.drop path;
  if[not loaded; '"the plan could not be loaded"];
  if[not first r; '"plan body failed: ", last r];
  `result`status!(last r; lines)
 };

/ ---------------------------------------------------------------------------
.tst.desc["mutation: operators are exchanged"]{
  should["swap arithmetic operators and their assignment forms"]{
    .tst.testState.mut.texts["{x+y}"; `arithmetic] mustmatch enlist "{x-y}";
    .tst.testState.mut.texts["{x-y}"; `arithmetic] mustmatch enlist "{x+y}";
    .tst.testState.mut.texts["{x*y}"; `arithmetic] mustmatch enlist "{x%y}";
    .tst.testState.mut.texts["{x%y}"; `arithmetic] mustmatch enlist "{x*y}";
    .tst.testState.mut.texts["{[x] x+:1; x}"; `arithmetic] mustmatch enlist "{[x] x-:1; x}";
  };

  should["move comparison boundaries and flip equality"]{
    .tst.testState.mut.texts["{x<y}"; `comparison] mustmatch enlist "{x<=y}";
    .tst.testState.mut.texts["{x<=y}"; `comparison] mustmatch enlist "{x<y}";
    .tst.testState.mut.texts["{x>y}"; `comparison] mustmatch enlist "{x>=y}";
    .tst.testState.mut.texts["{x>=y}"; `comparison] mustmatch enlist "{x>y}";
    .tst.testState.mut.texts["{x=y}"; `comparison] mustmatch enlist "{x<>y}";
    .tst.testState.mut.texts["{x<>y}"; `comparison] mustmatch enlist "{x=y}";
  };

  should["swap logical operators and words"]{
    .tst.testState.mut.texts["{x&y}"; `logical] mustmatch enlist "{x|y}";
    .tst.testState.mut.texts["{x|y}"; `logical] mustmatch enlist "{x&y}";
    .tst.testState.mut.texts["{x and y}"; `logical] mustmatch enlist "{x or y}";
    .tst.testState.mut.texts["{all x}"; `logical] mustmatch enlist "{any x}";
  };

  should["swap paired keywords and remove unary ones"]{
    .tst.testState.mut.texts["{first x}"; `keyword] mustmatch enlist "{last x}";
    .tst.testState.mut.texts["{max x}"; `keyword] mustmatch enlist "{min x}";
    .tst.testState.mut.texts["{x lj y}"; `keyword] mustmatch enlist "{x ij y}";
    .tst.testState.mut.texts["{not x}"; `keyword] mustmatch enlist "{ x}";
    .tst.testState.mut.texts["{distinct x}"; `keyword] mustmatch enlist "{ x}";
    / A keyword used as a value cannot simply be dropped: `neg each x` would
    / leave `each x`, which is not q. Such a mutant is discarded.
    .tst.testState.mut.texts["{neg each x}"; `keyword] mustmatch ();
  };

  should["tell a negative literal from a subtraction"]{
    .tst.testState.mut.texts["{-1+x}"; `arithmetic] mustmatch enlist "{-1-x}";
    .tst.testState.mut.texts["{x-1}"; `arithmetic] mustmatch enlist "{x+1}";
    .tst.testState.mut.texts["{x -1}"; `arithmetic] mustmatch ();
  };

  should["leave strings and comments alone"]{
    .tst.testState.mut.texts["{\"a+b<c\"}"; `arithmetic] mustmatch ();
    .tst.testState.mut.texts["{\"a+b<c\"}"; `comparison] mustmatch ();
    .tst.testState.mut.texts["{x / a+b\n }"; `arithmetic] mustmatch ();
    .tst.testState.mut.texts["{x\n/ a+b at column one\n }"; `arithmetic] mustmatch ();
  };

  should["tell an adverb from a comment"]{
    / "/" is also over, and "/:" each-right: neither starts a comment here.
    .tst.testState.mut.texts["{+/[x]}"; `arithmetic] mustmatch enlist "{-/[x]}";
    .tst.testState.mut.texts["{x+/:y}"; `arithmetic] mustmatch enlist "{x-/:y}";
    kinds: .tst.mutate.tokenKind each (enlist " "; "\n  "; " / note"; "/ note"; "/x"; enlist "/"; "/:"; enlist "x"; "+:");
    kinds mustmatch `blank`blank`comment`comment`comment`code`code`code`code;
  };

  should["mutate inside a qSQL expression"]{
    t: .tst.testState.mut.texts["{[t] select from t where a>1}"; `comparison];
    t mustmatch enlist "{[t] select from t where a>=1}";
  };
 };

/ ---------------------------------------------------------------------------
.tst.desc["mutation: constants"]{
  should["nudge an integer literal and flip a boolean"]{
    .tst.testState.mut.texts["{x+0}"; `constant] mustmatch enlist "{x+1}";
    .tst.testState.mut.texts["{x+1}"; `constant] mustmatch enlist "{x+0}";
    .tst.testState.mut.texts["{x+7}"; `constant] mustmatch enlist "{x+8}";
    .tst.testState.mut.texts["{x+5i}"; `constant] mustmatch enlist "{x+6i}";
    .tst.testState.mut.texts["{x&-3}"; `constant] mustmatch enlist "{x&-2}";
    .tst.testState.mut.texts["{0b}"; `constant] mustmatch enlist "{1b}";
    .tst.testState.mut.texts["{1b}"; `constant] mustmatch enlist "{0b}";
    / A number before a minus sign that stands alone is an operand.
    .tst.testState.mut.texts["{5 - x}"; `constant] mustmatch enlist "{6 - x}";
  };

  should["not take an operator or a name for a number"]{
    .tst.testState.mut.texts["{[x;y] x-y}"; `constant] mustmatch ();
    .tst.testState.mut.texts["{[x] x-}"; `constant] mustmatch ();
    / i, j and h are type suffixes only after digits.
    .tst.testState.mut.texts["{[i;j;h] i,j,h}"; `constant] mustmatch ();
  };

  should["keep a number that is the left argument of a keyword"]{
    .tst.testState.mut.texts["{3 sublist x}"; `constant] mustmatch enlist "{4 sublist x}";
    .tst.testState.mut.texts["{2 xbar x}"; `constant] mustmatch enlist "{3 xbar x}";
  };

  should["not touch a handle that is written to"]{
    / `-1 "text"` prints. Changing the handle would send the text somewhere
    / else, or evaluate it: that is not a mutation of the program's logic.
    .tst.testState.mut.texts["{-1 \"log\"; x}"; `constant] mustmatch ();
    .tst.testState.mut.texts["{[msg] -2 msg; msg}"; `constant] mustmatch ();
    .tst.testState.mut.texts["{[h;x] 1 (x;h); x}"; `constant] mustmatch ();
  };

  should["not touch a vector literal, an internal function, a null or a float"]{
    .tst.testState.mut.texts["{x in 1 2 3}"; `constant] mustmatch ();
    .tst.testState.mut.texts["{-4!x}"; `constant] mustmatch ();
    .tst.testState.mut.texts["{x^0N}"; `constant] mustmatch ();
    .tst.testState.mut.texts["{x*1.5}"; `constant] mustmatch ();
    .tst.testState.mut.texts["{x within 2000.01.01 2000.12.31}"; `constant] mustmatch ();
    .tst.testState.mut.texts["{`:f 0: x}"; `constant] mustmatch ();
    / A negative or null neighbour is still part of the same vector literal.
    .tst.testState.mut.texts["{x in 1 -2}"; `constant] mustmatch ();
    .tst.testState.mut.texts["{x^0N 5}"; `constant] mustmatch ();
    / Too long to be read back as a long: left alone rather than corrupted.
    .tst.testState.mut.texts["{x+1234567890123456}"; `constant] mustmatch ();
    .tst.testState.mut.texts["{x+123456789012345}"; `constant] mustmatch enlist "{x+123456789012346}";
  };
 };

/ ---------------------------------------------------------------------------
.tst.desc["mutation: conditions are negated"]{
  should["negate the condition of if"]{
    .tst.testState.mut.texts["{if[x>0; :1]; 0}"; `condition] mustmatch enlist "{if[not x>0; :1]; 0}";
    .tst.testState.mut.notes["{if[x>0; :1]; 0}"; `condition] mustmatch enlist "condition negated: x>0";
  };

  should["negate the condition of a plain three-part conditional"]{
    .tst.testState.mut.texts["{$[x>0; 1; 2]}"; `condition] mustmatch enlist "{$[not x>0; 1; 2]}";
    / if with nothing to run has no condition worth negating.
    .tst.testState.mut.texts["{if[x>0]; 1}"; `condition] mustmatch ();
  };

  should["negate each condition of a multi-branch conditional, one at a time"]{
    t: .tst.testState.mut.texts["{$[x=1; `a; x=2; `b; `c]}"; `condition];
    t mustmatch ("{$[not x=1; `a; x=2; `b; `c]}"; "{$[x=1; `a; not x=2; `b; `c]}");
  };

  should["negate a vector conditional but not a functional select or a cast"]{
    .tst.testState.mut.texts["{?[x>0; x; 0]}"; `condition] mustmatch enlist "{?[not x>0; x; 0]}";
    .tst.testState.mut.texts["{[t] ?[t; (); 0b; ()]}"; `condition] mustmatch ();
    .tst.testState.mut.texts["{$[`int; x]}"; `condition] mustmatch ();
    / Three arguments in brackets are a condition only after ?.
    .tst.testState.mut.texts["{f[x;y;z]}"; `condition] mustmatch ();
    / A condition may be a single name.
    .tst.testState.mut.texts["{if[x; :1]; 0}"; `condition] mustmatch enlist "{if[not x; :1]; 0}";
  };

  should["leave while alone and skip a condition that already starts with not"]{
    / Negating a loop condition mostly makes loops that never end, and a
    / leading `not` is already covered by removing it.
    .tst.testState.mut.texts["{[n] i:0; while[i<n; i+:1]; i}"; `condition] mustmatch ();
    .tst.testState.mut.texts["{if[not x; :1]; 0}"; `condition] mustmatch ();
    .tst.testState.mut.texts["{if[not x; :1]; 0}"; `keyword] mustmatch enlist "{if[ x; :1]; 0}";
  };
 };

/ ---------------------------------------------------------------------------
.tst.desc["mutation: statements are removed"]{
  should["remove each statement of the body in turn, keeping the parameters"]{
    t: .tst.testState.mut.texts["{[x] a:x+1; b:a*2; b}"; `statement];
    t mustmatch ("{[x] ; b:a*2; b}"; "{[x] a:x+1; ; b}"; "{[x] a:x+1; b:a*2; }");
  };

  should["remove the only statement of a one-line function"]{
    .tst.testState.mut.texts["{[x;y] x+y}"; `statement] mustmatch enlist "{[x;y] }";
    .tst.testState.mut.texts["{}"; `statement] mustmatch ();
    / With implicit parameters the body is what declares them: emptying it
    / would change how many arguments the function takes, so it is not done.
    .tst.testState.mut.texts["{x+y}"; `statement] mustmatch ();
  };

  should["remove the statements of a block that has several"]{
    n: .tst.testState.mut.notes["{[x] if[x>0; a:1; b:2]; x}"; `statement];
    must[.tst.testState.mut.has[n; "statement removed: a:1"]; "first block statement: ", .Q.s1 n];
    must[.tst.testState.mut.has[n; "statement removed: b:2"]; "second block statement: ", .Q.s1 n];
    must[.tst.testState.mut.has[n; "statement removed: if[x>0; a:1; b:2]"]; "the block itself: ", .Q.s1 n];
    4 musteq count n;
  };

  should["not take the arguments of an ordinary call for statements"]{
    n: .tst.testState.mut.notes["{[x] f[x;1;2]; x}"; `statement];
    n mustmatch ("statement removed: f[x;1;2]"; "statement removed: x");
  };

  should["not repeat the removal of a block that has one statement"]{
    n: .tst.testState.mut.notes["{[x] if[x<0; '\"negative\"]; x}"; `statement];
    n mustmatch ("statement removed: if[x<0; '\"negative\"]"; "statement removed: x");
  };

  should["shorten a long statement to sixty characters"]{
    / 62 characters is cut to 57 and an ellipsis; exactly 60 is shown whole.
    long: "total: ", (54#"x+"), "x";
    n: .tst.testState.mut.notes["{[x] ", long, "; total}"; `statement];
    first[n] mustmatch "statement removed: ", (57#long), "...";
    / One character too many is cut as well.
    longer: "total: ", (53#"x+x"), "x";
    61 musteq count longer;
    n: .tst.testState.mut.notes["{[x] ", longer, "; total}"; `statement];
    first[n] mustmatch "statement removed: ", (57#longer), "...";
    exact: "total: ", (52#"x+"), "x";
    60 musteq count exact;
    n: .tst.testState.mut.notes["{[x] ", exact, "; total}"; `statement];
    first[n] mustmatch "statement removed: ", exact;
  };

  should["describe a statement spread over lines on one line"]{
    n: .tst.testState.mut.notes["{[x]\n  a: x +\n     1;   / note\n  a}"; `statement];
    n mustmatch ("statement removed: a: x + 1"; "statement removed: a");
  };
 };

/ ---------------------------------------------------------------------------
.tst.desc["mutation: every mutant is a different, valid function"]{
  should["parse, keep the parameters, differ from the original and from each other"]{
    {[text]
      m: .tst.testState.mut.full text;
      params: (value value text) 1;
      fns: {[t] @[value; t; {[e] ::}]} each m`text;
      must[all 100h=type each fns; "every mutant parses: ", text];
      must[all {[p;f] p~(value f) 1}[params] each fns; "parameters are unchanged: ", text];
      must[not any (m`text)~\:text; "no mutant equals the original: ", text];
      must[(count m)=count distinct m`text; "mutants are distinct: ", text];
    } each .tst.testState.mut.samples;
  };

  should["produce mutants for real code and none for an empty function"]{
    counts: {[text] count .tst.testState.mut.full text} each .tst.testState.mut.samples;
    must[all 0<-1 _ counts; "each non-empty sample has mutants: ", .Q.s1 counts];
    0 musteq last counts;
  };

  should["record where the change is"]{
    text: "{[x]\n  x+1}";
    m: .tst.mutate.generate[text; enlist `arithmetic];
    1 musteq count m;
    text[first m`at] musteq "+";
    (first[m`upto]-first m`at) musteq 1;
    / The function opens at line 10, column 5 of its file.
    f: `name`file`line`col`text!(`f; "x.q"; 10; 5; text);
    .tst.mutate.position[f; first m`at] mustmatch 11 4;
    .tst.mutate.position[f; 0] mustmatch 10 5;
    / On the opening line the column counts from where the function starts;
    / after a line break, from the start of that line.
    .tst.mutate.position[f; 2] mustmatch 10 7;
    g: `name`file`line`col`text!(`g; "x.q"; 3; 9; "{[x]\n  a:1;\n  a+x}");
    .tst.mutate.position[g; 15] mustmatch 5 4;
  };

  should["list mutants in source order"]{
    m: .tst.testState.mut.full first .tst.testState.mut.samples;
    must[(m`at)~asc m`at; "ordered by position"];
  };

  should["honour the chosen families"]{
    text: first .tst.testState.mut.samples;
    m: .tst.mutate.generate[text; `comparison`constant];
    must[all (m`family) in `comparison`constant; "only the chosen families: ", .Q.s1 distinct m`family];
    must[all `comparison`constant in m`family; "and both of them"];
    0 musteq count .tst.mutate.generate[text; `symbol$()];
  };

  should["give nothing for text that is not one lambda"]{
    none: .tst.mutate.emptyMutants[];
    .tst.testState.mut.full["{x+"] mustmatch none;
    .tst.testState.mut.full["1+1"] mustmatch none;
    .tst.testState.mut.full[""] mustmatch none;
    / A lambda that is applied is a value, and one after a blank is not bare.
    .tst.testState.mut.full["{x}[1]"] mustmatch none;
    .tst.testState.mut.full[" {x+y}"] mustmatch none;
    / Nothing to change, and nothing left once the invalid changes are dropped.
    .tst.testState.mut.full["{}"] mustmatch none;
    .tst.mutate.generate["{neg each x}"; enlist `keyword] mustmatch none;
  };

  should["give nothing when the tokens do not add up to the text"]{
    / These tokens make a function, and changing one would make another, but
    / they are not the text that was given.
    `.tst.mutate.tokens mock {[text] (enlist "{"; "[x;y]"; enlist "x"; enlist "-"; enlist "y"; enlist "}")};
    0 musteq count .tst.testState.mut.full "{[x;y] x+y}";
    / The same tokens for the text they do add up to are mutated as usual.
    (.tst.mutate.generate["{[x;y]x-y}"; enlist `arithmetic]`text) mustmatch enlist "{[x;y]x+y}";
    `.tst.mutate.tokens mock {[text] '"tokenizer"};
    0 musteq count .tst.testState.mut.full "{x+y}";
  };

  should["drop a change that changes nothing, and one that repeats another"]{
    / A stand-in mutator that proposes the text itself and the same change twice.
    `.tst.mutate.genRemovals mock {[cx] (
      (`keyword; 1; 1; "same text"; raze cx`toks);
      (`keyword; 1; 1; "first"; "{y+y}");
      (`keyword; 2; 2; "again"; "{y+y}"))};
    m: .tst.mutate.generate["{x+y}"; enlist `keyword];
    (m`note) mustmatch enlist "first";
  };
 };

/ ---------------------------------------------------------------------------
.tst.desc["mutation: functions are found where a file defines them"]{
  should["qualify names by namespace and hold the text q itself keeps"]{
    path: .tst.testState.mut.scratch["src.q"; (
      "\\d .tst";
      "mutFixScale: 3;";
      "mutFixPrice:{[qty;px]";
      "    / a comment inside";
      "    total: qty*px;   / trailing";
      "    total*mutFixScale";
      " };";
      "\\d .";
      ".tst.mutFixClip:{[x] 0|x};";
      "system \"d .tst\";";
      "mutFixLast:{last x}";
      "system \"d .\";")];
    fns: .tst.mutate.functionsIn path;
    system "l ", path;
    live: {[n] last value get n} each fns`name;
    names: fns`name;
    ok: live~fns`text;
    positions: flip (fns`line; fns`col);
    { ![`.tst; (); 0b; enlist x] } each `mutFixScale`mutFixPrice`mutFixClip`mutFixLast;
    .tst.testState.mut.drop path;
    names mustmatch `.tst.mutFixPrice`.tst.mutFixClip`.tst.mutFixLast;
    must[ok; "the text found in the file is the text q holds for the function"];
    positions mustmatch (3 13; 9 17; 11 12);
  };

  should["skip a definition whose value is not the lambda itself"]{
    path: .tst.testState.mut.scratch["src.q"; (
      ".mf.plain:{x+1};";
      ".mf.projected:{x+y}[1;];";
      ".mf.applied:{x+1} 2;";
      ".mf.each:{x+1}';";
      ".mf.table:`a`b!({x+1};{x+2});";
      ".mf.nested:{ {x+1} x };";
      "if[1b; .mf.guarded:{x+1}];";
      ".mf.withComment:{x+2}   / a comment after it")];
    names: (.tst.mutate.functionsIn path)`name;
    .tst.testState.mut.drop path;
    names mustmatch `.mf.plain`.mf.nested`.mf.withComment;
  };

  should["ignore text that is not code"]{
    path: .tst.testState.mut.scratch["src.q"; (
      enlist "/";
      ".mf.inBlockComment:{x+1};";
      enlist "\\";
      "/ .mf.inComment:{x+1};";
      "note: \".mf.inString:{x+1};\";";
      ".mf.real:{x+1};";
      enlist "\\";
      ".mf.afterTerminator:{x+1};")];
    names: (.tst.mutate.functionsIn path)`name;
    .tst.testState.mut.drop path;
    names mustmatch enlist `.mf.real;
  };

  should["survive a brace that is never closed"]{
    path: .tst.testState.mut.scratch["src.q"; (".mf.ok:{x+1};"; ".mf.open:{x+1")];
    names: (.tst.mutate.functionsIn path)`name;
    .tst.testState.mut.drop path;
    names mustmatch enlist `.mf.ok;
  };

  should["give an empty table for a missing or empty file"]{
    none: .tst.mutate.emptyFunctions[];
    .tst.mutate.functionsIn["/nonexistent/resq/mutation/file.q"] mustmatch none;
    path: .tst.testState.mut.scratch["src.q"; ()];
    zeroBytes: .tst.mutate.functionsIn path;
    (hsym `$path) 0: enlist "";
    oneEmptyLine: .tst.mutate.functionsIn path;
    (hsym `$path) 0: ("x: 1"; "/ no function here");
    noFunction: .tst.mutate.functionsIn path;
    .tst.testState.mut.drop path;
    zeroBytes mustmatch none;
    oneEmptyLine mustmatch none;
    noFunction mustmatch none;
  };

  should["take a one-letter name, and skip a lambda that has none"]{
    path: .tst.testState.mut.scratch["src.q"; ("f:{x+1};"; "{x+2};"; "g:{x+3}")];
    names: (.tst.mutate.functionsIn path)`name;
    .tst.testState.mut.drop path;
    names mustmatch `f`g;
  };
 };

/ ---------------------------------------------------------------------------
.tst.desc["mutation: targets and options"]{
  should["read a path, a line and a line range"]{
    .tst.mutate.parseTarget["src/a.q"] mustmatch `path`lo`hi!("src/a.q"; 0N; 0N);
    .tst.mutate.parseTarget["src/a.q:12"] mustmatch `path`lo`hi!("src/a.q"; 12; 12);
    .tst.mutate.parseTarget["src/a.q:7"] mustmatch `path`lo`hi!("src/a.q"; 7; 7);
    .tst.mutate.parseTarget["src/a.q:5-9"] mustmatch `path`lo`hi!("src/a.q"; 5; 9);
    .tst.mutate.parseTarget["src/a.q:10-40"] mustmatch `path`lo`hi!("src/a.q"; 10; 40);
    / A colon that is not a line range belongs to the path.
    .tst.mutate.parseTarget["c:/src/a.q"] mustmatch `path`lo`hi!("c:/src/a.q"; 0N; 0N);
    .tst.mutate.parseTarget["src/a.q:x-y"] mustmatch `path`lo`hi!("src/a.q:x-y"; 0N; 0N);
    .tst.mutate.parseTarget["c:/src/a.q:10-20"] mustmatch `path`lo`hi!("c:/src/a.q"; 10; 20);
    .tst.mutate.parseTarget["src/a.q:1x-2"] mustmatch `path`lo`hi!("src/a.q:1x-2"; 0N; 0N);
    .tst.mutate.parseTarget["src/a.q:-5"] mustmatch `path`lo`hi!("src/a.q:-5"; 0N; 0N);
    .tst.mutate.parseTarget["src/a.q:5-"] mustmatch `path`lo`hi!("src/a.q:5-"; 0N; 0N);
  };

  should["expand a directory to its source files, in one spelling, without the tests"]{
    path: .tst.testState.mut.scratch["a.q"; enlist ".mf.a:{x+1};"];
    dir: .tst.static.getDir path;
    (hsym `$dir, "/test_a.q") 0: enlist "/ a test file";
    (hsym `$dir, "/b.q") 0: enlist ".mf.b:{x+1};";
    whole: `path`lo`hi!(dir; 0N; 0N);
    fromDir: .tst.mutate.expandTarget[(); whole];
    asTest: .tst.mutate.expandTarget[enlist .tst.canonicalPath dir, "/b.q"; whole];
    odd: .tst.mutate.expandTarget[(); `path`lo`hi!(dir, "/./a.q"; 3; 4)];
    missing: @[.tst.mutate.expandTarget[()]; `path`lo`hi!(dir, "/nope.q"; 0N; 0N); {[e] e}];
    ranged: @[.tst.mutate.expandTarget[()]; `path`lo`hi!(dir; 1; 2); {[e] e}];
    .tst.testState.mut.drop path;
    want: .tst.mutate.display each .tst.canonicalPath each (dir, "/a.q"; dir, "/b.q");
    (asc fromDir`path) mustmatch asc want;
    (asTest`path) mustmatch enlist first want;
    (odd`path) mustmatch enlist first want;
    (odd`lo`hi) mustmatch (enlist 3; enlist 4);
    must[missing like "no such file or directory*"; "a missing path is an error: ", .Q.s1 missing];
    must[ranged like "a line range needs a file*"; "a line range on a directory is an error: ", .Q.s1 ranged];
  };

  should["accept known mutators and name an unknown one"]{
    .tst.mutate.chosenFamilies[""] mustmatch .tst.mutate.families;
    .tst.mutate.chosenFamilies["comparison, statement"] mustmatch `comparison`statement;
    e: @[.tst.mutate.chosenFamilies; "comparison,bogus"; {[e] e}];
    must[e like "unknown mutator: bogus*"; "names the unknown mutator: ", .Q.s1 e];
  };

  should["read the new-side line ranges of a diff"]{
    diff: ("diff --git a/src/a.q b/src/a.q"; "--- a/src/a.q"; "+++ b/src/a.q";
      "@@ -2 +2 @@"; "-old"; "+new";
      "@@ -10,0 +11,3 @@ total: a +b"; "+a"; "+b"; "+c";
      "@@ -20,2 +22,0 @@"; "-gone"; "-gone");
    .tst.mutate.hunkRanges[diff] mustmatch (2 2; 11 13; 22 21);
    .tst.mutate.hunkRanges[()] mustmatch ();
  };

  should["keep only mutants on the requested lines"]{
    path: .tst.testState.mut.scratch["src.q"; (".mf.a:{x+1};"; ".mf.b:{x-1};"; ".mf.c:{"; "  x*2"; " };")];
    sources: {[path;lo;hi] ([] path:enlist path; lo:enlist lo; hi:enlist hi)}[path];
    fam: enlist `arithmetic;
    whole: .tst.mutate.gather[sources[0N;0N]; fam; ()];
    line2: .tst.mutate.gather[sources[2;2]; fam; ()];
    line4: .tst.mutate.gather[sources[4;4]; fam; ()];
    changed: .tst.mutate.gather[sources[0N;0N]; fam; (enlist `$path)!enlist enlist 1 1];
    none: .tst.mutate.gather[sources[0N;0N]; fam; (enlist `$path)!enlist ()];
    .tst.testState.mut.drop path;
    (whole[`mutants]`line) mustmatch 1 2 4;
    (whole[`mutants]`col) mustmatch 9 9 4;
    (line2[`mutants]`line) mustmatch enlist 2;
    (line4[`mutants]`line) mustmatch enlist 4;
    (changed[`mutants]`line) mustmatch enlist 1;
    0 musteq count none`mutants;
    / A mutant keeps the index of its function in the functions table.
    (whole[`functions]`name) mustmatch `.mf.a`.mf.b`.mf.c;
    (whole[`mutants]`fnIdx) mustmatch 0 1 2;
  };

  should["not repeat a file that is named twice"]{
    path: .tst.testState.mut.scratch["src.q"; (".mf.a:{x+1};"; ".mf.b:{x-1};")];
    sources: ([] path:(path;path); lo:1 2; hi:1 2);
    found: .tst.mutate.gather[sources; enlist `arithmetic; ()];
    .tst.testState.mut.drop path;
    (found[`functions]`name) mustmatch `.mf.a`.mf.b;
    (found[`mutants]`line) mustmatch 1 2;
  };

  should["keep a mutant whose change reaches into the requested lines"]{
    / The statement starts on line 2 and ends on line 3.
    path: .tst.testState.mut.scratch["src.q"; (".mf.a:{[x]"; "  b: x +"; "     1;"; "  b};")];
    one: {[path;line] ([] path:enlist path; lo:enlist line; hi:enlist line)}[path];
    fam: enlist `statement;
    line3: .tst.mutate.gather[one 3; fam; ()];
    line1: .tst.mutate.gather[one 1; fam; ()];
    .tst.testState.mut.drop path;
    (line3[`mutants]`note) mustmatch enlist "statement removed: b: x + 1";
    0 musteq count line1`mutants;
  };
 };

/ ---------------------------------------------------------------------------
.tst.testState.mut.child:{[code;valid;failed;timedOut;licence;status]
  `code`valid`ran`failed`firstFailure`timedOut`licence`status`tail!(
    code; valid; 3; failed; ""; timedOut; licence; status; "")
 };

.tst.desc["mutation: a verdict needs proof the mutant was in place"]{
  should["call a failing run a kill only when the mutant was applied"]{
    applied: enlist "applied";
    .tst.mutate.verdict[.tst.testState.mut.child[1; 1b; 1; 0b; 0b; applied]] musteq `killed;
    .tst.mutate.verdict[.tst.testState.mut.child[1; 1b; 1; 0b; 0b; ()]] musteq `retry;
  };

  should["call a passing run survived, or unapplied when the mutant never went in"]{
    .tst.mutate.verdict[.tst.testState.mut.child[0; 1b; 0; 0b; 0b; enlist "applied"]] musteq `survived;
    .tst.mutate.verdict[.tst.testState.mut.child[0; 1b; 0; 0b; 0b; ()]] musteq `unapplied;
  };

  should["treat a process that died with the mutant in place as a kill"]{
    .tst.mutate.verdict[.tst.testState.mut.child[1; 0b; 0; 0b; 0b; enlist "applied"]] musteq `killed;
    / A non-zero exit with every test passing is still a change the suite saw.
    .tst.mutate.verdict[.tst.testState.mut.child[4; 1b; 0; 0b; 0b; enlist "applied"]] musteq `killed;
    / So is a failed test, whatever the exit code says.
    .tst.mutate.verdict[.tst.testState.mut.child[0; 1b; 1; 0b; 0b; enlist "applied"]] musteq `killed;
    / A process that left no report did not pass, even if it exited 0.
    .tst.mutate.verdict[.tst.testState.mut.child[0; 0b; 0; 0b; 0b; enlist "applied"]] musteq `killed;
    .tst.mutate.verdict[.tst.testState.mut.child[0; 0b; 0; 0b; 0b; ()]] musteq `retry;
  };

  should["never count a startup or licence failure as a kill"]{
    .tst.mutate.verdict[.tst.testState.mut.child[1; 0b; 0; 0b; 0b; ()]] musteq `retry;
    .tst.mutate.verdict[.tst.testState.mut.child[1; 0b; 0; 0b; 1b; ()]] musteq `retry;
    .tst.mutate.verdict[.tst.testState.mut.child[1; 0b; 0; 0b; 1b; enlist "applied"]] musteq `retry;
  };

  should["report a timeout only with the mutant in place"]{
    .tst.mutate.verdict[.tst.testState.mut.child[124; 0b; 0; 1b; 0b; enlist "applied"]] musteq `timeout;
    .tst.mutate.verdict[.tst.testState.mut.child[124; 0b; 0; 1b; 0b; ()]] musteq `retry;
  };

  should["not trust a passing run when the child recorded an error"]{
    failedToCompile: enlist "error could not compile the mutant: x";
    lateError: ("applied"; "error type");
    / Never in place: an error, not a survivor and not worth retrying.
    .tst.mutate.verdict[.tst.testState.mut.child[0; 1b; 0; 0b; 0b; failedToCompile]] musteq `error;
    .tst.mutate.verdict[.tst.testState.mut.child[1; 1b; 1; 0b; 0b; failedToCompile]] musteq `error;
    .tst.mutate.verdict[.tst.testState.mut.child[124; 0b; 0; 1b; 0b; failedToCompile]] musteq `error;
    / In place, then something went wrong: it may not have stayed in place, so
    / a pass proves nothing.
    .tst.mutate.verdict[.tst.testState.mut.child[0; 1b; 0; 0b; 0b; lateError]] musteq `error;
    / But it was in place and the tests failed: that is a kill.
    .tst.mutate.verdict[.tst.testState.mut.child[1; 1b; 1; 0b; 0b; lateError]] musteq `killed;
    .tst.mutate.verdict[.tst.testState.mut.child[124; 0b; 0; 1b; 0b; lateError]] musteq `timeout;
  };

  should["explain why a test file cannot be used as a baseline"]{
    done: enlist "done";
    ok: .tst.testState.mut.child[0; 1b; 0; 0b; 0b; done];
    .tst.mutate.baselineReason[ok] mustmatch "";
    r: .tst.mutate.baselineReason .tst.testState.mut.child[1; 1b; 1; 0b; 0b; done];
    must[r like "fails on its own*"; "a failing file: ", r];
    r: .tst.mutate.baselineReason .tst.testState.mut.child[3; 1b; 0; 0b; 0b; done];
    r mustmatch "exit code 3";
    r: .tst.mutate.baselineReason .tst.testState.mut.child[124; 0b; 0; 1b; 0b; ()];
    r mustmatch "timed out";
    r: .tst.mutate.baselineReason .tst.testState.mut.child[1; 0b; 0; 0b; 0b; ()];
    must[r like "left no report*"; "a dead process: ", r];
    r: .tst.mutate.baselineReason @[ok; `ran; :; 0];
    r mustmatch "ran no tests";
    r: .tst.mutate.baselineReason @[ok; `status; :; ()];
    r mustmatch "did not finish the run";
  };

  should["read function indexes from status lines"]{
    lines: ("matched 0"; "matched 12"; "differs 3"; "hit 12"; "done");
    .tst.mutate.statusIndexes[lines; "matched"] mustmatch 0 12;
    .tst.mutate.statusIndexes[lines; "hit"] mustmatch enlist 12;
    0 musteq count .tst.mutate.statusIndexes[lines; "missing"];
  };
 };

/ ---------------------------------------------------------------------------
.tst.desc["mutation: the score counts what the tests failed to notice"]{
  should["count an uncovered mutant against the score and leave out the unassessed"]{
    st: `killed`killed`killed`timeout`survived`survived`uncovered`unloaded`unmatched`unapplied`error;
    s: .tst.mutate.summary ([] status: st);
    s[`mutants`killed`timedOut`survived`notCovered`notAssessed] mustmatch 11 3 1 2 2 3;
    / 4 detected of 8 that count; 4 of 6 in functions the tests call.
    s[`score] musteq 50f;
    s[`coveredScore] musteq 66.7;
  };

  should["have no score when nothing could be assessed"]{
    s: .tst.mutate.summary ([] status: `unmatched`error);
    must[null s`score; "no score"];
    .tst.mutate.showPercent[s`score] mustmatch "n/a";
    .tst.mutate.showPercent[66.7] mustmatch "66.7%";
    .tst.mutate.percent[1; 1] musteq 100f;
    must[null .tst.mutate.percent[0; 0]; "nothing out of nothing is not a score"];
  };
 };

/ ---------------------------------------------------------------------------
.tst.desc["mutation: inside a child process"]{
  should["replace a matching function, compiled in the namespace it came from"]{
    / The original lives in .tst and reads a .tst global by its bare name; the
    / mutant must resolve that name the same way.
    .tst.mutFixScale: 3;
    `.tst.mutFixTimes set last .tst.mutate.compile[`tst; "{[x] x*mutFixScale}"];
    before: .tst.mutFixTimes 6;
    plan: `mode`names`texts`mutated`status!(`mutant; enlist `.tst.mutFixTimes;
      enlist "{[x] x*mutFixScale}"; "{[x] x%mutFixScale}"; "");
    out: .tst.testState.mut.withPlan[plan; {.tst.mutate.install `.tst.testState.mut.state; .tst.mutate.install `.tst.testState.mut.state; .tst.mutFixTimes 6}];
    { ![`.tst; (); 0b; enlist x] } each `mutFixScale`mutFixTimes;
    before musteq 18;
    out[`result] musteq 2f;
    out[`status] mustmatch enlist "applied";
  };

  should["put the mutant back after the source is reloaded"]{
    .tst.testState.mut.fix: value "{[x] x+1}";
    plan: `mode`names`texts`mutated`status!(`mutant; enlist `.tst.testState.mut.fix;
      enlist "{[x] x+1}"; "{[x] x-1}"; "");
    out: .tst.testState.mut.withPlan[plan; {
      .tst.mutate.install `.tst.testState.mut.state;
      first1: .tst.testState.mut.fix 10;
      .tst.testState.mut.fix:: value "{[x] x+1}";
      reloaded: .tst.testState.mut.fix 10;
      .tst.mutate.install `.tst.testState.mut.state;
      (first1; reloaded; .tst.testState.mut.fix 10)}];
    out[`result] mustmatch 9 11 9;
    out[`status] mustmatch enlist "applied";
  };

  should["leave alone a function that is not the one in the file"]{
    .tst.testState.mut.fix: value "{[x] x+2}";
    plan: `mode`names`texts`mutated`status!(`mutant; enlist `.tst.testState.mut.fix;
      enlist "{[x] x+1}"; "{[x] x-1}"; "");
    out: .tst.testState.mut.withPlan[plan; {.tst.mutate.install `.tst.testState.mut.state; .tst.testState.mut.fix 10}];
    out[`result] musteq 12;
    0 musteq count out`status;
  };

  should["leave alone a name that is undefined or not a function"]{
    .tst.testState.mut.fix: 42;
    plan: `mode`names`texts`mutated`status!(`mutant; enlist `.tst.testState.mut.fix;
      enlist "{[x] x+1}"; "{[x] x-1}"; "");
    out: .tst.testState.mut.withPlan[plan; {.tst.mutate.install `.tst.testState.mut.state; .tst.testState.mut.fix}];
    out[`result] musteq 42;
    plan[`names]: enlist `.tst.testState.mut.neverDefined;
    out: .tst.testState.mut.withPlan[plan; {.tst.mutate.install `.tst.testState.mut.state; 1b}];
    0 musteq count out`status;
  };

  should["record an error instead of signalling when the mutant does not compile"]{
    .tst.testState.mut.fix: value "{[x] x+1}";
    plan: `mode`names`texts`mutated`status!(`mutant; enlist `.tst.testState.mut.fix;
      enlist "{[x] x+1}"; "{[x] x+"; "");
    out: .tst.testState.mut.withPlan[plan; {.tst.mutate.install `.tst.testState.mut.state; .tst.testState.mut.fix 10}];
    out[`result] musteq 11;
    must[all out[`status] like "error*"; "an error line and no applied line: ", .Q.s1 out`status];
    1 musteq count out`status;
  };

  should["probe which functions are called without changing what they return"]{
    / In order: called; undefined; never called; called, no arguments; a
    / function with other text; not a function at all.
    .tst.testState.mut.pa: value "{[x;y] x+y}";
    .tst.testState.mut.pb: value "{x*2}";
    .tst.testState.mut.pc: value "{[] 7}";
    .tst.testState.mut.pd: value "{[x] x+2}";
    .tst.testState.mut.pf: 42;
    names: `.tst.testState.mut.pa`.tst.testState.mut.pe`.tst.testState.mut.pb`.tst.testState.mut.pc`.tst.testState.mut.pd`.tst.testState.mut.pf;
    texts: ("{[x;y] x+y}"; "{x}"; "{x*2}"; "{[] 7}"; "{[x] x+1}"; "{x}");
    plan: `mode`names`texts`mutated`status!(`probe; names; texts; ""; "");
    out: .tst.testState.mut.withPlan[plan; {
      .tst.mutate.install `.tst.testState.mut.state;
      .tst.mutate.install `.tst.testState.mut.state;
      r: (.tst.testState.mut.pa[2;3]; .tst.testState.mut.pc[]; .tst.testState.mut.pd 1);
      .tst.mutate.finish `.tst.testState.mut.state;
      r}];
    out[`result] mustmatch 5 7 3;
    (out`status) mustmatch ("matched 0"; "matched 2"; "matched 3"; "differs 4"; "hit 0"; "hit 3"; "done");
    / A second visit leaves a function it has already wrapped alone: the
    / wrapper is not mistaken for a different definition.
    st: .tst.testState.mut.state;
    (st`matched) mustmatch 101100b;
    (st`differs) mustmatch 000010b;
    .tst.testState.mut.pf musteq 42;
  };

  should["leave a function alone when its stand-in cannot be built"]{
    .tst.testState.mut.fix: value "{[x] x+1}";
    `.tst.mutate.wrapperText mock {[st;i;args] "{[x"};
    plan: `mode`names`texts`mutated`status!(`probe; enlist `.tst.testState.mut.fix; enlist "{[x] x+1}"; ""; "");
    out: .tst.testState.mut.withPlan[plan; {
      .tst.mutate.install `.tst.testState.mut.state;
      .tst.mutate.finish `.tst.testState.mut.state;
      .tst.testState.mut.fix 10}];
    out[`result] musteq 11;
    (last value .tst.testState.mut.fix) mustmatch "{[x] x+1}";
    (out`status) mustmatch enlist "done";
  };

  should["add the probe's report to what is already in the status file"]{
    .tst.testState.mut.fix: value "{[x] x+1}";
    plan: `mode`names`texts`mutated`status!(`probe; enlist `.tst.testState.mut.fix; enlist "{[x] x+1}"; ""; "");
    out: .tst.testState.mut.withPlan[plan; {
      .tst.mutate.note[`.tst.testState.mut.state; "earlier"];
      .tst.mutate.install `.tst.testState.mut.state;
      .tst.testState.mut.fix 1;
      .tst.mutate.finish `.tst.testState.mut.state}];
    (out`status) mustmatch ("earlier"; "matched 0"; "hit 0"; "done");
  };

  should["write each note on a line of its own"]{
    plan: `mode`names`texts`mutated`status!(`mutant; enlist `.tst.testState.mut.neverDefined; enlist "{x}"; "{y}"; "");
    out: .tst.testState.mut.withPlan[plan; {
      .tst.mutate.note[`.tst.testState.mut.state; "one"];
      .tst.mutate.note[`.tst.testState.mut.state; "two"]}];
    (out`status) mustmatch ("one"; "two");
  };

  should["report nothing at the end of a mutant run"]{
    / Only a probe reports when the run is over. A mutant run that did would
    / overwrite the record that the mutant was applied.
    .tst.testState.mut.fix: value "{[x] x+1}";
    plan: `mode`names`texts`mutated`status!(`mutant; enlist `.tst.testState.mut.fix;
      enlist "{[x] x+1}"; "{[x] x-1}"; "");
    out: .tst.testState.mut.withPlan[plan; {
      .tst.mutate.install `.tst.testState.mut.state;
      .tst.mutate.finish `.tst.testState.mut.state;
      .tst.testState.mut.fix 10}];
    out[`result] musteq 9;
    (out`status) mustmatch enlist "applied";
  };

  should["compile in the given namespace and come back to the one it started in"]{
    here: system "d";
    good: .tst.mutate.compile[`tst; "{[x] x+1}"];
    afterGood: system "d";
    bad: .tst.mutate.compile[`tst; "{[x] x+"];
    afterBad: system "d";
    root: .tst.mutate.compile[`; "{[x] x+2}"];
    afterGood musteq here;
    afterBad musteq here;
    must[first good; "valid text compiles"];
    (first (value last good) 3) musteq `tst;
    must[not first bad; "invalid text does not"];
    must[10h=type last bad; "and says why: ", .Q.s1 last bad];
    (first (value last root) 3) musteq `;
  };
 };

.tst.testState.mut.canRun: (0 < count .tst.isolate.qExe) and
  0 < count @[system; "which timeout 2>/dev/null"; {[e] ()}];

/ ---------------------------------------------------------------------------
/ The parent side. What the command prints is collected instead of shown, and
/ the function that starts child processes is replaced by one that answers
/ from a script, so the scheduling can be tested without starting anything.
/ ---------------------------------------------------------------------------

.tst.testState.mut.capture:{[]
  .tst.testState.mut.printed: ();
  .tst.testState.mut.marks: "";
  / Progress marks are shown unless the enclosing run was started with -quiet.
  `.tst.app.quiet mock 0b;
  `.tst.mutate.out mock {[line] .tst.testState.mut.printed,: enlist line;};
  `.tst.mutate.err mock {[line] .tst.testState.mut.printed,: enlist "ERR ", line;};
  `.tst.mutate.mark mock {[text] .tst.testState.mut.marks,: text;};
 };

/ Stand-in for .tst.mutate.runBatch: records each call and answers every
/ (test file; plan) from .tst.testState.mut.respond.
.tst.testState.mut.script:{[respond]
  .tst.testState.mut.calls: ();
  .tst.testState.mut.respond: respond;
  `.tst.mutate.runBatch mock {[files;plans;timeouts]
    .tst.testState.mut.calls,: enlist `files`plans`timeouts!(files; plans; timeouts);
    .tst.testState.mut.respond'[files; plans]};
 };

/ Child results by name.
.tst.testState.mut.outcome:{[kind]
  applied: enlist "applied";
  $[kind~`killed;    .tst.testState.mut.child[1; 1b; 1; 0b; 0b; applied];
    kind~`survived;  .tst.testState.mut.child[0; 1b; 0; 0b; 0b; applied];
    kind~`unapplied; .tst.testState.mut.child[0; 1b; 0; 0b; 0b; ()];
    kind~`timeout;   .tst.testState.mut.child[124; 0b; 0; 1b; 0b; applied];
    kind~`error;     .tst.testState.mut.child[0; 1b; 0; 0b; 0b; ("applied"; "error boom")];
    .tst.testState.mut.child[1; 0b; 0; 0b; 0b; ()]]
 };

.tst.desc["mutation: what a child leaves behind"]{
  should["keep the plan and the status in the child's scratch directory"]{
    .tst.mutate.planPath["/tmp/x"] mustmatch "/tmp/x/mutation.plan";
    .tst.mutate.statusPath["/tmp/x"] mustmatch "/tmp/x/mutation.status";
  };

  should["read the exit code, the report, the status and the output"]{
    rc: .tst.testState.mut.scratch["rc.txt"; enlist enlist "0"];
    wd: .tst.static.getDir rc;
    (hsym `$wd, "/test-results.json") 0: enlist "{\"tests\":[{\"suite\":\"s\",\"description\":\"a\",\"status\":\"pass\"},{\"suite\":\"s\",\"description\":\"b\",\"status\":\"fail\"},{\"suite\":\"s\",\"description\":\"c\",\"status\":\"skip\"},{\"suite\":\"s\",\"description\":\"d\",\"status\":\"Error\"},{\"suite\":\"s\",\"description\":\"e\",\"status\":\"pending\"}]}";
    (hsym `$wd, "/out.txt") 0: ("line one"; "line two");
    (hsym `$.tst.mutate.statusPath wd) 0: enlist "applied";
    r: .tst.mutate.readChild wd;
    .tst.testState.mut.drop rc;
    r[`code] musteq 0;
    r[`valid] musteq 1b;
    r[`ran] musteq 5;
    / skip and pending are not failures; anything else that is not a pass is.
    r[`failed] musteq 2;
    r[`firstFailure] mustmatch "s / b";
    r[`timedOut] musteq 0b;
    r[`licence] musteq 0b;
    r[`status] mustmatch enlist "applied";
    r[`tail] mustmatch "line one\nline two\n";
  };

  should["see a timeout in the exit code or in what timeout printed"]{
    rc: .tst.testState.mut.scratch["rc.txt"; enlist "124"];
    wd: .tst.static.getDir rc;
    byCode: .tst.mutate.readChild wd;
    (hsym `$rc) 0: enlist "137";
    byKill: .tst.mutate.readChild wd;
    (hsym `$rc) 0: enlist enlist "1";
    plain: .tst.mutate.readChild wd;
    (hsym `$wd, "/out.txt") 0: ("some output"; "timeout: sending signal TERM to command 'q'");
    byText: .tst.mutate.readChild wd;
    .tst.testState.mut.drop rc;
    byCode[`timedOut] musteq 1b;
    byKill[`timedOut] musteq 1b;
    plain[`timedOut] musteq 0b;
    byText[`timedOut] musteq 1b;
    / No report was written in any of these.
    byCode[`valid`ran`failed] mustmatch (0b; 0; 0);
    byCode[`firstFailure] mustmatch "";
    (count byCode`status) musteq 0;
  };

  should["keep the last twelve lines of what the child printed"]{
    rc: .tst.testState.mut.scratch["rc.txt"; enlist enlist "1"];
    wd: .tst.static.getDir rc;
    (hsym `$wd, "/out.txt") 0: "line ",/: string 1+til 20;
    r: .tst.mutate.readChild wd;
    .tst.testState.mut.drop rc;
    / The file ends with a line break, so the last of the twelve is empty.
    r[`tail] mustmatch "\n" sv ("line ",/: string 10+til 11), enlist "";
  };

  should["notice a licence failure, and a child that left nothing at all"]{
    rc: .tst.testState.mut.scratch["rc.txt"; enlist enlist "1"];
    wd: .tst.static.getDir rc;
    / Written in two parts: a failing test prints its own source, and the
    / whole phrase in that output would look like a licence failure.
    (hsym `$wd, "/out.txt") 0: enlist "'2026.01.01 Couldn't connect to ", "license daemon";
    refused: .tst.mutate.readChild wd;
    / The same words inside other output are not q refusing to start.
    (hsym `$wd, "/out.txt") 0: enlist "    says: 'couldn't connect to ", "license daemon";
    mentioned: .tst.mutate.readChild wd;
    / Nor is any other q error, though it too starts its line with a quote.
    (hsym `$wd, "/out.txt") 0: ("'type"; "  [0]  f 1");
    otherError: .tst.mutate.readChild wd;
    hdel hsym `$rc;
    hdel hsym `$wd, "/out.txt";
    nothing: .tst.mutate.readChild wd;
    .tst.testState.mut.drop rc;
    refused[`licence] musteq 1b;
    mentioned[`licence] musteq 0b;
    otherError[`licence] musteq 0b;
    nothing[`licence] musteq 0b;
    .tst.mutate.verdict[refused] musteq `retry;
    nothing[`code] musteq -1;
    nothing[`licence`timedOut`valid] mustmatch 000b;
    nothing[`tail] mustmatch "";
  };

  should["stand in for a child that could not be started"]{
    r: .tst.mutate.noChild[];
    (key r) mustmatch key .tst.testState.mut.outcome `killed;
    r[`code`valid`ran`failed`timedOut`licence] mustmatch (-1; 0b; 0; 0; 0b; 0b);
    .tst.mutate.verdict[r] musteq `retry;
    must[.tst.mutate.baselineReason[r] like "left no report*"; .tst.mutate.baselineReason r];
  };
 };

/ ---------------------------------------------------------------------------
.tst.testState.mut.batchProject:{[]
  root: .utl.tempRoot[], "/resq_mut_batch_", string[.z.i], "_", string `long$.z.p;
  system "mkdir -p ", .utl.shellQuote root;
  (hsym `$root, "/calc.q") 0: enlist ".rb.add:{[x;y] x+y};";
  source: "system \"l ", root, "/calc.q\";";
  (hsym `$root, "/test_pass.q") 0: (source; ".tst.desc[\"rb\"]{ should[\"add\"]{ .rb.add[1;2] musteq 3 } };");
  (hsym `$root, "/test_fail.q") 0: (source; ".tst.desc[\"rb\"]{ should[\"be wrong\"]{ .rb.add[1;2] musteq 4 } };");
  root
 };

.tst.desc["mutation: starting child processes"]{
  skipIf[not .tst.testState.mut.canRun; "need q, timeout and the other tools, and say so when one is missing"]{
    .tst.mutate.requireTools[] mustmatch (::);
    / QBIN may be as short as "q".
    `.tst.isolate.qExe mock enlist "q";
    .tst.mutate.requireTools[] mustmatch (::);
    `.tst.isolate.qExe mock "";
    e: @[.tst.mutate.requireTools; ::; {[e] e}];
    must[e like "mutation testing needs*"; "names what is missing: ", .Q.s1 e];
  };

  skipIf[not .tst.testState.mut.canRun; "refuse a timeout command that cannot stop a busy process"]{
    `.tst.isolate.timeoutExe mock "";
    e: @[.tst.mutate.requireTools; ::; {[e] e}];
    must[e like "mutation testing needs*"; .Q.s1 e];
  };

  skipIf[not .tst.testState.mut.canRun; "run real children: a probe that passes, one that fails, and a mutant"]{
    root: .tst.testState.mut.batchProject[];
    allocated: count .tst.isolate.allocated;
    probe: `mode`names`texts`mutated`status!(`probe; enlist `.rb.add; enlist "{[x;y] x+y}"; ""; "");
    mutant: `mode`names`texts`mutated`status!(`mutant; enlist `.rb.add; enlist "{[x;y] x+y}"; "{[x;y] x-y}"; "");
    `.tst.mutate.parent mock 1b;
    res: .tst.mutate.runBatch[root ,/: ("/test_pass.q"; "/test_fail.q"; "/test_pass.q"); (probe; probe; mutant); 60 60 60];
    left: count .tst.isolate.allocated;
    system "rm -rf ", .utl.shellQuote root;
    (res`valid) mustmatch 111b;
    (res`ran) mustmatch 1 1 1;
    (res`failed) mustmatch 0 1 1;
    (0=res`code) mustmatch 100b;
    (res`timedOut) mustmatch 000b;
    / The passing probe matched the function, saw it called, and finished.
    (res[`status] 0) mustmatch ("matched 0"; "hit 0"; "done");
    .tst.mutate.baselineReason[res 0] mustmatch "";
    must[.tst.mutate.baselineReason[res 1] like "fails on its own: rb / be wrong"; .tst.mutate.baselineReason res 1];
    / The mutant was put in place, and the test that passes without it failed.
    (res[`status] 2) mustmatch enlist "applied";
    .tst.mutate.verdict[res 2] musteq `killed;
    left musteq allocated;
  };

  should["report a child whose scratch directory could not be made, and start nothing"]{
    `.tst.isolate.createScratch mock {[] '"no room"};
    `.tst.isolate.launchGroup mock {[indexes;cmds;wds] .tst.testState.mut.launched: count indexes;};
    `.tst.isolate.resetScratch mock {[wd] .tst.testState.mut.touched+: 1;};
    .tst.testState.mut.launched: -1;
    .tst.testState.mut.touched: 0;
    plan: `mode`names`texts`mutated`status!(`probe; `symbol$(); (); ""; "");
    res: .tst.mutate.runBatch[("a.q"; "b.q"); (plan; plan); 5 5];
    (count res) musteq 2;
    (res`code) mustmatch -1 -1;
    (res`valid) mustmatch 00b;
    .tst.testState.mut.launched musteq 0;
    / Nothing is done with a directory that does not exist.
    .tst.testState.mut.touched musteq 0;
  };

  should["start only the children whose scratch and plan are ready"]{
    marker: .tst.testState.mut.scratch["marker"; enlist ""];
    .tst.testState.mut.wd: -1 _ .tst.static.getDir marker;
    .tst.testState.mut.started: ();
    `.tst.isolate.createScratch mock {[] .tst.testState.mut.wd};
    `.tst.isolate.cleanupScratch mock {[wd] 1b};
    `.tst.isolate.launchGroup mock {[indexes;cmds;wds] .tst.testState.mut.started,: enlist (indexes; count each cmds; wds);};
    `.tst.mutate.readChild mock {[wd] .tst.testState.mut.outcome `survived};
    plan: `mode`names`texts`mutated`status!(`mutant; enlist `.x.f; enlist "{x}"; "{y}"; "");
    files: ("a.q"; "b.q");

    `.tst.isolate.preparePrivateRerunState mock {[wd] 0b};
    refused: .tst.mutate.runBatch[files; (plan; plan); 5 5];
    `.tst.isolate.preparePrivateRerunState mock {[wd] '"disk full"};
    failed: .tst.mutate.runBatch[files; (plan; plan); 5 5];
    `.tst.isolate.preparePrivateRerunState mock {[wd] 1b};
    / A plan path under a regular file cannot be written.
    `.tst.mutate.planPath mock {[wd] wd, "/marker/plan"};
    unwritable: .tst.mutate.runBatch[files; (plan; plan); 5 5];
    notStarted: .tst.testState.mut.started;
    `.tst.mutate.planPath mock {[wd] wd, "/the.plan"};
    ready: .tst.mutate.runBatch[files; (plan; plan); 5 5];
    written: get hsym `$.tst.testState.mut.wd, "/the.plan";
    .tst.testState.mut.drop marker;

    (refused`code) mustmatch -1 -1;
    (failed`code) mustmatch -1 -1;
    (unwritable`code) mustmatch -1 -1;
    / Each time the group was started with no children in it.
    (notStarted[;0]) mustmatch 3#enlist `long$();
    (ready`code) mustmatch 0 0;
    started: last .tst.testState.mut.started;
    (started 0) mustmatch 0 1;
    must[all 0<started 1; "each child has a command"];
    (started 2) mustmatch 2#enlist .tst.testState.mut.wd;
    / The plan each child reads says where to leave its status.
    written[`status] mustmatch .tst.mutate.statusPath .tst.testState.mut.wd;
    written[`mutated] mustmatch "{y}";
  };
 };

/ ---------------------------------------------------------------------------
.tst.testState.mut.fns4: ([] name:`.m.called`.m.idle`.m.changed`.m.absent`.m.once;
  file:5#enlist "src/m.q"; line:1 2 3 4 5; col:5#9; text:("{a}"; "{b}"; "{c}"; "{d}"; "{e}"));

.tst.desc["mutation: the baseline run"]{
  should["probe every file, in groups, and read what each saw"]{
    .tst.testState.mut.capture[];
    .tst.testState.mut.script {[file;plan]
      st: $[file~"a.q"; ("matched 0"; "matched 1"; "hit 1"; "done");
            file~"b.q"; enlist "done";
            ("matched 0"; "differs 2"; "done")];
      $[file~"b.q"; .tst.testState.mut.child[1; 1b; 1; 0b; 0b; st]; .tst.testState.mut.child[0; 1b; 0; 0b; 0b; st]]};
    fns: .tst.testState.mut.fns4;
    base: .tst.mutate.baseline[("a.q"; "b.q"; "c.q"); fns; 2; 77];
    (base`file) mustmatch ("a.q"; "b.q"; "c.q");
    (base`usable) mustmatch 101b;
    (base[`why] 0) mustmatch "";
    must[(base[`why] 1) like "fails on its own*"; base[`why] 1];
    (base[`matched] 0) mustmatch 0 1;
    (base[`hits] 0) mustmatch enlist 1;
    (count base[`hits] 2) musteq 0;
    (base[`differs] 2) mustmatch enlist 2;
    must[all (base`secs) within 0 60; "a time in seconds for every file: ", .Q.s1 base`secs];
    (base[`secs] 0) musteq base[`secs] 1;
    / Two at a time: (a;b) then (c). Every child is given the same limit.
    calls: .tst.testState.mut.calls;
    (calls`files) mustmatch (("a.q"; "b.q"); enlist "c.q");
    (calls`timeouts) mustmatch (77 77; enlist 77);
    plans: raze calls`plans;
    must[all `probe=plans`mode; "every child gets a probe plan"];
    (first plans`names) mustmatch fns`name;
    (first plans`texts) mustmatch fns`text;
    / One mark per file: "." usable, "x" left out.
    .tst.testState.mut.marks mustmatch ".x.";
  };
 };

/ ---------------------------------------------------------------------------
/ a.q is slow and b.q quick; both call .m.called, and only b.q calls .m.once.
/ .m.idle is in memory in a.q alone and never called. c.q fails on its own,
/ so what it saw must not count.
.tst.testState.mut.base3: ([] file:("a.q"; "b.q"; "c.q"); usable:110b; why:(""; ""; "fails on its own: x");
  secs:2 0.1 0.05; matched:(0 1; 0 4; 0 1 3); differs:(enlist 2; `long$(); `long$());
  hits:(enlist 0; 0 4; 0 1 3); tail:3#enlist "");

/ Mutants of .m.called named by what the script does with them.
.tst.testState.mut.mutantsOf:{[texts;fnIdx]
  n: count texts;
  ([] family:n#`arithmetic; at:n#1; upto:n#2; note:texts; text:texts; fnIdx:fnIdx; line:n#1; col:n#10)
 };

/ Answer from a table of what each mutant does on each file, in call order.
.tst.testState.mut.byScript:{[plays]
  .tst.testState.mut.plays: plays;
  .tst.testState.mut.seen: (`symbol$())!`long$();
  .tst.testState.mut.script {[file;plan]
    k: `$plan[`mutated], "@", file;
    n: 0^.tst.testState.mut.seen k;
    .tst.testState.mut.seen[k]: n+1;
    kinds: .tst.testState.mut.plays k;
    .tst.testState.mut.outcome kinds n&-1+count kinds};
 };

.tst.desc["mutation: running the mutants"]{
  should["not run a mutant whose function no usable test file calls"]{
    .tst.testState.mut.capture[];
    .tst.testState.mut.script {[file;plan] .tst.testState.mut.outcome `killed};
    m: .tst.testState.mut.mutantsOf[("idle"; "changed"; "absent"); 1 2 3];
    r: .tst.mutate.execute[m; .tst.testState.mut.fns4; .tst.testState.mut.base3; 2; 300];
    / Matched but never called; found different; never seen. c.q called all
    / three, but it fails on its own.
    (r`status) mustmatch `uncovered`unmatched`unloaded;
    (r`killedBy) mustmatch 3#enlist "";
    (count .tst.testState.mut.calls) musteq 0;
    .tst.testState.mut.marks mustmatch "";
  };

  should["run a mutant whose function a single test file calls"]{
    .tst.testState.mut.capture[];
    .tst.testState.mut.byScript (enlist `$"lone@b.q")!enlist enlist `killed;
    r: .tst.mutate.execute[.tst.testState.mut.mutantsOf[enlist "lone"; enlist 4]; .tst.testState.mut.fns4; .tst.testState.mut.base3; 1; 300];
    (r`status) mustmatch enlist `killed;
    (r`killedBy) mustmatch enlist "b.q";
    (raze .tst.testState.mut.calls`files) mustmatch enlist "b.q";
  };

  should["try the quickest test file first and stop at the first kill"]{
    .tst.testState.mut.capture[];
    .tst.testState.mut.byScript (`$("first@b.q"; "second@b.q"; "second@a.q"))!(enlist `killed; enlist `survived; enlist `killed);
    m: .tst.testState.mut.mutantsOf[("first"; "second"); 0 0];
    r: .tst.mutate.execute[m; .tst.testState.mut.fns4; .tst.testState.mut.base3; 1; 300];
    (r`status) mustmatch `killed`killed;
    (r`killedBy) mustmatch ("b.q"; "a.q");
    calls: .tst.testState.mut.calls;
    (raze calls`files) mustmatch ("b.q"; "b.q"; "a.q");
    / Five seconds and three times the unmutated run, rounded up.
    (raze calls`timeouts) mustmatch 6 6 11;
    plans: raze calls`plans;
    (plans`mode) mustmatch 3#`mutant;
    (plans`mutated) mustmatch ("first"; "second"; "second");
    (first plans`names) mustmatch enlist `.m.called;
    (first plans`texts) mustmatch enlist "{a}";
    .tst.testState.mut.marks mustmatch "..";
  };

  should["never wait longer than the limit given"]{
    .tst.testState.mut.capture[];
    .tst.testState.mut.byScript (`$("m@b.q"; "m@a.q"))!(enlist `survived; enlist `survived);
    r: .tst.mutate.execute[.tst.testState.mut.mutantsOf[enlist enlist "m"; enlist 0]; .tst.testState.mut.fns4; .tst.testState.mut.base3; 1; 4];
    (raze .tst.testState.mut.calls`timeouts) mustmatch 4 4;
  };

  should["tell survived, never applied, timed out and error apart"]{
    .tst.testState.mut.capture[];
    names: ("lives"; "half"; "never"; "hangs"; "broken");
    .tst.testState.mut.byScript (`$("lives@b.q"; "lives@a.q"; "half@b.q"; "half@a.q"; "never@b.q"; "never@a.q"; "hangs@b.q"; "broken@b.q"))!(
      enlist `survived; enlist `survived;
      enlist `unapplied; enlist `survived;
      enlist `unapplied; enlist `unapplied;
      enlist `timeout;
      enlist `error);
    r: .tst.mutate.execute[.tst.testState.mut.mutantsOf[names; 5#0]; .tst.testState.mut.fns4; .tst.testState.mut.base3; 5; 300];
    / Applied in one file is enough to call it survived.
    (r`status) mustmatch `survived`survived`unapplied`timeout`error;
    (r`killedBy) mustmatch (""; ""; ""; "b.q"; "");
    (asc .tst.testState.mut.marks) mustmatch asc "SS-TE";
  };

  should["retry a run that proves nothing, twice, then give up on the mutant"]{
    .tst.testState.mut.capture[];
    .tst.testState.mut.byScript (`$("blip@b.q"; "blip@a.q"; "dead@b.q"; "late@b.q"; "late@a.q"))!(
      `retry`retry`survived; `retry`killed;
      enlist `retry;
      enlist `survived; `retry`retry`retry);
    r: .tst.mutate.execute[.tst.testState.mut.mutantsOf[("blip"; "dead"; "late"); 3#0]; .tst.testState.mut.fns4; .tst.testState.mut.base3; 1; 300];
    / blip: two blips then a pass on b.q; the count starts again on a.q.
    (r`status) mustmatch `killed`error`error;
    (r`killedBy) mustmatch ("a.q"; ""; "");
    seen: .tst.testState.mut.seen;
    seen[`$"blip@b.q"] musteq 3;
    seen[`$"blip@a.q"] musteq 2;
    seen[`$"dead@b.q"] musteq 3;
    seen[`$"late@a.q"] musteq 3;
  };

  should["run as many at once as it is told, and break the line of marks at sixty"]{
    .tst.testState.mut.capture[];
    .tst.testState.mut.script {[file;plan] .tst.testState.mut.outcome `killed};
    names: string each til 61;
    r: .tst.mutate.execute[.tst.testState.mut.mutantsOf[names; 61#0]; .tst.testState.mut.fns4; .tst.testState.mut.base3; 25; 300];
    must[all `killed=r`status; "all killed"];
    (count each .tst.testState.mut.calls`files) mustmatch 25 25 11;
    .tst.testState.mut.marks mustmatch (60#"."), "\n", ".";
  };
 };

/ ---------------------------------------------------------------------------
/ One mutant of every status, in two files, for the report.
.tst.testState.mut.reportFns: ([] name:`.a.price`.a.clip`.b.unused`.b.swapped`.b.gone`.b.kept;
  file:("src/a.q"; "src/a.q"; "src/b.q"; "src/b.q"; "src/b.q"; "src/b.q"); line:3 10 2 7 9 20; col:6#9; text:6#enlist "{x}");
.tst.testState.mut.reportMutants:{[]
  st: `survived`killed`survived`timeout`survived`uncovered`uncovered`unloaded`unmatched`unapplied`error`survived;
  notes: ("`>=` replaced with `>`"; "`*` replaced with `%`"; "statement removed: if[x<0; 'neg]";
    "`+:` replaced with `-:`"; "`100` replaced with `101`"; "u1"; "u2"; "g1"; "w1"; "n1"; "e1";
    "`first` replaced with `last`");
  n: count st;
  killers: @[n#enlist ""; 1; :; (system "cd"), "/tests/t.q"];
  ([] family:n#`comparison; at:n#0; upto:n#1; note:notes; text:notes; fnIdx:0 0 0 1 1 2 2 4 3 1 0 5;
    line:12 5 5 10 11 2 2 9 7 10 6 21; col:3 20 8 14 2 10 12 10 10 30 4 7; status:st; killedBy:killers)
 };
.tst.testState.mut.reportBase: ([] file:("tests/t.q"; "tests/u.q"); usable:10b; why:(""; "ran no tests"));

.tst.desc["mutation: the report"]{
  should["print the counts, the score, and each group that needs attention"]{
    .tst.testState.mut.capture[];
    s: .tst.mutate.report[.tst.testState.mut.reportMutants[]; .tst.testState.mut.reportFns; .tst.testState.mut.reportBase];
    .tst.testState.mut.printed mustmatch (
      "";
      "RESULT";
      "  killed        1";
      "  timed out     1";
      "  survived      4";
      "  not covered   3";
      "  not assessed  3";
      "";
      "  Mutation score: 22.2% (2 of 9 mutants detected)";
      "  In functions the tests call: 33.3%";
      "";
      "SURVIVED (4): the tests pass with this change in place";
      "  src/a.q";
      "    5:8   .a.price  statement removed: if[x<0; 'neg]";
      "    11:2  .a.clip   `100` replaced with `101`";
      "    12:3  .a.price  `>=` replaced with `>`";
      "  src/b.q";
      "    21:7  .b.kept  `first` replaced with `last`";
      "";
      "TIMED OUT (1): counted as detected; the change made a test run far longer";
      "  src/a.q";
      "    10:14  .a.clip  `+:` replaced with `-:`";
      "";
      "NOT COVERED (3): no usable test file calls these functions by name";
      "    src/b.q:2  .b.unused  (2 mutant(s))";
      "    src/b.q:9  .b.gone  (1 mutant(s))";
      "";
      "NOT ASSESSED (1): the function in memory is not the definition in the file";
      "    src/b.q:7  .b.swapped  (1 mutant(s))";
      "";
      "NOT ASSESSED (1): the function was not in place when the tests ran";
      "    src/a.q:10  .a.clip  (1 mutant(s))";
      "";
      "NOT ASSESSED (1): the run failed without the mutant in place (unstable test or environment)";
      "  src/a.q";
      "    6:4  .a.price  e1");
    s[`mutants`killed`timedOut`survived`notCovered`notAssessed] mustmatch 12 1 1 4 3 3;
    s[`score] musteq 22.2;
  };

  should["print nothing but the result when every mutant was killed"]{
    .tst.testState.mut.capture[];
    m: update status:`killed from .tst.testState.mut.reportMutants[];
    .tst.mutate.report[m; .tst.testState.mut.reportFns; .tst.testState.mut.reportBase];
    .tst.testState.mut.printed mustmatch (
      "";
      "RESULT";
      "  killed        12";
      "  timed out     0";
      "  survived      0";
      "  not covered   0";
      "  not assessed  0";
      "";
      "  Mutation score: 100.0% (12 of 12 mutants detected)");
  };

  should["give the second score as soon as one mutant is not covered"]{
    .tst.testState.mut.capture[];
    m: update status:`killed from .tst.testState.mut.reportMutants[];
    m: update status:`uncovered from m where i=5;
    .tst.mutate.report[m; .tst.testState.mut.reportFns; .tst.testState.mut.reportBase];
    p: .tst.testState.mut.printed;
    must[.tst.testState.mut.has[p; "  Mutation score: 91.7% (11 of 12 mutants detected)"]; .Q.s1 p];
    must[.tst.testState.mut.has[p; "  In functions the tests call: 100.0%"]; .Q.s1 p];
  };

  should["pad a column, and never cut it"]{
    .tst.mutate.pad[5; "ab"] mustmatch "ab   ";
    .tst.mutate.pad[3; "abc"] mustmatch "abc";
    .tst.mutate.pad[2; "abc"] mustmatch "abc";
  };

  should["show a path as it would be typed from the working directory"]{
    cwd: system "cd";
    .tst.mutate.display[cwd, "/src/a.q"] mustmatch "src/a.q";
    .tst.mutate.display["src/a.q"] mustmatch "src/a.q";
    .tst.mutate.display["/elsewhere/a.q"] mustmatch "/elsewhere/a.q";
    / Another directory whose name merely starts the same way is not inside.
    .tst.mutate.display[cwd, "x/a.q"] mustmatch cwd, "x/a.q";
    .tst.mutate.display[`$cwd, "/src/a.q"] mustmatch "src/a.q";
  };

  should["write every mutant to mutation-report.json"]{
    .tst.testState.mut.capture[];
    marker: .tst.testState.mut.scratch["marker"; enlist ""];
    dir: .utl.normalizePath .tst.static.getDir[marker], "/reports";
    `.resq.config.outDir mock dir;
    m: .tst.testState.mut.reportMutants[];
    summary: .tst.mutate.summary m;
    .tst.mutate.writeJson[m; .tst.testState.mut.reportFns; .tst.testState.mut.reportBase; summary];
    doc: .j.k raze read0 hsym `$dir, "/mutation-report.json";
    .tst.testState.mut.drop marker;
    .tst.testState.mut.printed mustmatch enlist "Mutation report written to: ", dir, "/mutation-report.json";
    doc[`kind] mustmatch "resq-mutation-report";
    must[1 = doc`schemaVersion; "schema version one"];
    doc[`framework] mustmatch "resQ";
    doc[`frameworkVersion] mustmatch .tst.toString .resq.VERSION;
    must[(doc[`summary]`mutants) = 12; "the summary is included"];
    must[(doc[`summary]`score) = 22.2; "with the score"];
    (doc[`testFiles]`file) mustmatch ("tests/t.q"; "tests/u.q");
    (doc[`testFiles]`usable) mustmatch 10b;
    (doc[`testFiles]`reason) mustmatch (""; "ran no tests");
    one: doc[`mutants] 1;
    must[1 = one`id; "ids count from zero in order"];
    one[`file] mustmatch "src/a.q";
    must[(5 = one`line) and 20 = one`column; "where the change is"];
    one[`function] mustmatch ".a.price";
    one[`mutator] mustmatch "comparison";
    one[`description] mustmatch "`*` replaced with `%`";
    one[`status] mustmatch "killed";
    one[`killedBy] mustmatch "tests/t.q";
    (doc[`mutants]`status) mustmatch string .tst.testState.mut.reportMutants[]`status;
  };

  should["show progress marks unless asked to be quiet"]{
    .tst.testState.mut.capture[];
    `.tst.app.quiet mock 0b;
    .tst.mutate.tick "ab";
    .tst.mutate.tick ".";
    shown: .tst.testState.mut.marks;
    `.tst.app.quiet mock 1b;
    .tst.mutate.tick "zz";
    shown mustmatch "ab.";
    .tst.testState.mut.marks mustmatch "ab.";
  };
 };

/ ---------------------------------------------------------------------------
/ A project to select from: three functions on three lines, one test file,
/ and a directory that holds nothing but a test.
.tst.testState.mut.selectProject:{[]
  root: .utl.tempRoot[], "/resq_mut_sel_", string[.z.i], "_", string `long$.z.p;
  system "mkdir -p ", " " sv .utl.shellQuote each root ,/: ("/src"; "/tests"; "/other"; "/empty");
  (hsym `$root, "/src/calc.q") 0: (".sel.add:{[x;y] x+y};"; ".sel.big:{[x] x>10};"; ".sel.flip:{[x] neg x};");
  (hsym `$root, "/tests/test_calc.q") 0: enlist "/ a test file";
  (hsym `$root, "/tests/helper.q") 0: enlist "/ not a test file";
  (hsym `$root, "/other/test_b.q") 0: enlist "/ another test file";
  / findTests records what it skipped for the enclosing run; keep that ours.
  `.tst.app.unmatchedQFiles mock ();
  `.tst.app.testFilePatternsUsed mock ();
  `.tst.app.mutationTests mock enlist root, "/tests";
  `.tst.app.mutators mock "";
  `.tst.app.mutationSince mock "";
  `.tst.app.maxMutants mock 0;
  root
 };
.tst.testState.mut.try:{[f;x] @[{[f;x] (1b; f x)}[f]; x; {[e] (0b; e)}]};
/ 1b when a call run through .try failed with a message like `pattern`. A
/ plain boolean whatever the call returned: `() like "x"` is an empty list,
/ and an empty list passes `must`.
.tst.testState.mut.failed:{[r;pattern] $[first r; 0b; 10h=type last r; (last r) like pattern; 0b]};

.tst.desc["mutation: choosing what to run"]{
  should["find the test files, under tests/ when none are named"]{
    root: .tst.testState.mut.selectProject[];
    here: system "cd";
    system "cd ", root;
    byDefault: .tst.testState.mut.try[.tst.mutate.testFiles; ()];
    system "cd ", root, "/src";
    noTestsDir: .tst.testState.mut.try[.tst.mutate.testFiles; ()];
    system "cd ", here;
    named: .tst.mutate.testFiles (root, "/tests"; root, "/other");
    oneFile: .tst.mutate.testFiles enlist root, "/tests/helper.q";
    missing: .tst.testState.mut.try[.tst.mutate.testFiles; (root, "/tests"; root, "/nope")];
    none: .tst.testState.mut.try[.tst.mutate.testFiles; enlist root, "/empty"];
    system "rm -rf ", .utl.shellQuote root;
    canon: .tst.canonicalPath each root ,/: ("/other/test_b.q"; "/tests/test_calc.q"; "/tests/helper.q");
    byDefault mustmatch (1b; enlist canon 1);
    must[.tst.testState.mut.failed[noTestsDir; "there is no tests/ directory here*"]; .Q.s1 noTestsDir];
    / Sorted, and only files that look like tests, unless one is named outright.
    named mustmatch canon 0 1;
    oneFile mustmatch enlist canon 2;
    must[.tst.testState.mut.failed[missing; "test path not found: *nope"]; .Q.s1 missing];
    must[.tst.testState.mut.failed[none; "no test files found under: *empty"]; .Q.s1 none];
  };

  should["select every mutant of the named source"]{
    root: .tst.testState.mut.selectProject[];
    sel: .tst.mutate.select enlist root, "/src/calc.q";
    noArgs: .tst.testState.mut.try[.tst.mutate.select; ()];
    onlyTests: .tst.testState.mut.try[.tst.mutate.select; enlist root, "/other"];
    `.tst.app.mutators mock "bogus";
    badMutator: .tst.testState.mut.try[.tst.mutate.select; enlist root, "/src"];
    `.tst.app.mutators mock "arithmetic";
    arithmetic: .tst.mutate.select enlist root, "/src";
    system "rm -rf ", .utl.shellQuote root;
    (sel[`functions]`name) mustmatch `.sel.add`.sel.big`.sel.flip;
    (sel[`mutants]`line) mustmatch 1 1 2 2 2 3 3;
    (sel[`mutants]`fnIdx) mustmatch 0 0 1 1 1 2 2;
    sel[`total] musteq 7;
    sel[`testFiles] mustmatch enlist .tst.canonicalPath root, "/tests/test_calc.q";
    must[.tst.testState.mut.failed[noArgs; "name the source to mutate*"]; .Q.s1 noArgs];
    must[.tst.testState.mut.failed[onlyTests; "no source files to mutate under: *other"]; .Q.s1 onlyTests];
    must[.tst.testState.mut.failed[badMutator; "unknown mutator: bogus*"]; .Q.s1 badMutator];
    (arithmetic[`mutants]`family) mustmatch enlist `arithmetic;
    (arithmetic[`functions]`name) mustmatch enlist `.sel.add;
  };

  should["take an even sample, and keep only the functions it touches"]{
    root: .tst.testState.mut.selectProject[];
    `.tst.app.maxMutants mock 2;
    two: .tst.mutate.select enlist root, "/src/calc.q";
    `.tst.app.maxMutants mock 1;
    single: .tst.mutate.select enlist root, "/src/calc.q";
    `.tst.app.maxMutants mock 7;
    all7: .tst.mutate.select enlist root, "/src/calc.q";
    `.tst.app.maxMutants mock 50;
    more: .tst.mutate.select enlist root, "/src/calc.q";
    system "rm -rf ", .utl.shellQuote root;
    / The first of seven and the one half way, counting down from 3.5.
    (two[`mutants]`note) mustmatch ("statement removed: x+y"; "`>` replaced with `>=`");
    (two[`mutants]`line) mustmatch 1 2;
    two[`total] musteq 7;
    (two[`functions]`name) mustmatch `.sel.add`.sel.big;
    (two[`mutants]`fnIdx) mustmatch 0 1;
    (single[`mutants]`note) mustmatch enlist "statement removed: x+y";
    (count all7`mutants) musteq 7;
    (count more`mutants) musteq 7;
    (more[`mutants]`line) mustmatch 1 1 2 2 2 3 3;
  };

  should["keep only changed lines when a revision is given"]{
    root: .tst.testState.mut.selectProject[];
    .tst.testState.mut.asked: ();
    `.tst.mutate.requireRevision mock {[ref] .tst.testState.mut.asked,: enlist ref;};
    `.tst.mutate.changedLines mock {[ref;path] .tst.testState.mut.asked,: enlist ref, " ", path; enlist 3 3};
    `.tst.app.mutationSince mock "main";
    sel: .tst.mutate.select enlist root, "/src/calc.q";
    system "rm -rf ", .utl.shellQuote root;
    (sel[`mutants]`line) mustmatch 3 3;
    / The function left is the third in the file and the first in the result.
    (sel[`functions]`name) mustmatch enlist `.sel.flip;
    (sel[`mutants]`fnIdx) mustmatch 0 0;
    sel[`total] musteq 2;
    (first .tst.testState.mut.asked) mustmatch "main";
    must[(last .tst.testState.mut.asked) like "main *src/calc.q"; .Q.s1 .tst.testState.mut.asked];
  };
 };

/ ---------------------------------------------------------------------------
.tst.testState.mut.gitProject:{[]
  root: .utl.tempRoot[], "/resq_mut_git_", string[.z.i], "_", string `long$.z.p;
  system "mkdir -p ", .utl.shellQuote root;
  (hsym `$root, "/a.q") 0: ("one"; "two"; "three");
  git: "git -C ", .utl.shellQuote[root], " -c user.email=t@example.invalid -c user.name=t ";
  system git, "init -q .";
  system git, "add -A";
  system git, "commit -q -m base";
  (hsym `$root, "/a.q") 0: ("one"; "TWO"; "three"; "four");
  (hsym `$root, "/b.q") 0: enlist "new";
  root
 };
.tst.testState.mut.hasGit: 0 < count @[system; "which git 2>/dev/null"; {[e] ()}];

.tst.desc["mutation: lines changed since a revision"]{
  skipIf[not .tst.testState.mut.hasGit; "read the changed lines of a tracked file, and count a new file as all new"]{
    root: .tst.testState.mut.gitProject[];
    here: system "cd";
    system "cd ", root;
    changed: .tst.testState.mut.try[.tst.mutate.changedLines["HEAD"]; "a.q"];
    fresh: .tst.testState.mut.try[.tst.mutate.changedLines["HEAD"]; "b.q"];
    known: .tst.testState.mut.try[.tst.mutate.requireRevision; "HEAD"];
    unknown: .tst.testState.mut.try[.tst.mutate.requireRevision; "no-such-revision"];
    system "cd ", here;
    system "rm -rf ", .utl.shellQuote root;
    changed mustmatch (1b; (2 2; 4 4));
    fresh mustmatch (1b; enlist 1 0W);
    must[first known; "HEAD is a revision: ", .Q.s1 known];
    must[.tst.testState.mut.failed[unknown; "-since needs a git revision*no-such-revision"]; .Q.s1 unknown];
  };
 };

/ ---------------------------------------------------------------------------
/ run with the process-starting steps replaced: what it prints, what it hands
/ on, and what it returns.
.tst.testState.mut.runSetup:{[statuses]
  root: .tst.testState.mut.selectProject[];
  .tst.testState.mut.capture[];
  .tst.testState.mut.handed: (enlist `)!enlist (::);
  .tst.testState.mut.statuses: statuses;
  .tst.testState.mut.baseRows: ([] file:enlist root, "/tests/test_calc.q"; usable:enlist 1b; why:enlist "";
    secs:enlist 0.1; matched:enlist 0 1 2; differs:enlist `long$(); hits:enlist 0 1 2; tail:enlist "");
  `.tst.mutate.requireTools mock {[] .tst.testState.mut.handed[`tools]: 1b;};
  `.tst.mutate.baseline mock {[testFiles;fns;workers;cap]
    .tst.testState.mut.handed[`baseline]: (testFiles; fns`name; workers; cap);
    .tst.testState.mut.baseRows};
  `.tst.mutate.execute mock {[mutants;fns;base;workers;cap]
    .tst.testState.mut.handed[`execute]: (count mutants; fns`name; base`file; workers; cap);
    n: count mutants;
    update status:n#.tst.testState.mut.statuses, killedBy:n#enlist "" from mutants};
  `.tst.mutate.parent mock 0b;
  `.tst.app.failFast mock 0b;
  `.tst.isolate.killAfter mock 5;
  `.tst.app.reportFormats mock `symbol$();
  `.tst.app.mutationMin mock 0N;
  `.tst.app.isolateWorkers mock 3;
  `.tst.app.isolateTimeout mock 44;
  root
 };

.tst.desc["mutation: the run as a whole"]{
  should["say what it will do, probe, run the mutants and report"]{
    root: .tst.testState.mut.runSetup `killed`survived;
    code: .tst.mutate.run enlist root, "/src/calc.q";
    state: (.tst.mutate.parent; .tst.app.failFast; .tst.isolate.killAfter);
    system "rm -rf ", .utl.shellQuote root;
    code musteq 0;
    p: .tst.testState.mut.printed;
    (4#p) mustmatch (
      "Mutation testing";
      "  Source: 1 file(s), 3 function(s), 7 mutant(s)";
      "  Tests:  1 file(s), each first run on its own without a mutant";
      "  Running mutants (. killed, S survived, T timed out, - not applied, E error)");
    must[.tst.testState.mut.has[p; "RESULT"]; "the report follows"];
    must[.tst.testState.mut.has[p; "  killed        4"]; "with the outcome of the run: ", .Q.s1 p];
    / A gap before each row of marks and a line end after it.
    .tst.testState.mut.marks mustmatch "  \n  \n";
    h: .tst.testState.mut.handed;
    must[h`tools; "the tools are checked before anything is started"];
    file: .tst.canonicalPath root, "/tests/test_calc.q";
    / One test file, so one at a time; seven mutants, so the three allowed.
    h[`baseline] mustmatch (enlist file; `.sel.add`.sel.big`.sel.flip; 1; 44);
    h[`execute] mustmatch (7; `.sel.add`.sel.big`.sel.flip; enlist root, "/tests/test_calc.q"; 3; 44);
    / Children are handed a plan, stop at the first failure, and are killed
    / soon after they overrun.
    state mustmatch (1b; 1b; 1);
  };

  should["say so when it samples, and when it looks only at changed lines"]{
    root: .tst.testState.mut.runSetup enlist `killed;
    `.tst.app.maxMutants mock 2;
    .tst.mutate.run enlist root, "/src/calc.q";
    sampled: .tst.testState.mut.printed 1;
    .tst.testState.mut.capture[];
    `.tst.app.maxMutants mock 0;
    `.tst.mutate.requireRevision mock {[ref] ::};
    `.tst.mutate.changedLines mock {[ref;path] enlist 1 1};
    `.tst.app.mutationSince mock "main";
    .tst.mutate.run enlist root, "/src/calc.q";
    since: .tst.testState.mut.printed 1;
    system "rm -rf ", .utl.shellQuote root;
    sampled mustmatch "  Source: 1 file(s), 2 function(s), 2 mutant(s), an even sample of 7 (-max-mutants)";
    since mustmatch "  Source: 1 file(s), 1 function(s), 2 mutant(s) on lines changed since main";
  };

  should["stop early, successfully, when there is nothing to mutate"]{
    root: .tst.testState.mut.runSetup enlist `killed;
    `.tst.app.mutators mock "logical";
    code: .tst.mutate.run enlist root, "/src/calc.q";
    plain: .tst.testState.mut.printed;
    .tst.testState.mut.capture[];
    `.tst.mutate.requireRevision mock {[ref] ::};
    `.tst.mutate.changedLines mock {[ref;path] ()};
    `.tst.app.mutators mock "";
    `.tst.app.mutationSince mock "v1";
    code2: .tst.mutate.run enlist root, "/src/calc.q";
    since: .tst.testState.mut.printed;
    system "rm -rf ", .utl.shellQuote root;
    code musteq 0;
    code2 musteq 0;
    plain mustmatch ("Mutation testing";
      "  Nothing to mutate: no named function with a mutable construct in the selected source.");
    since mustmatch ("Mutation testing";
      "  Nothing to mutate: no named function with a mutable construct in the lines changed since v1.");
    must[not `baseline in key .tst.testState.mut.handed; "nothing is started"];
    must[not `tools in key .tst.testState.mut.handed; "and nothing is required"];
  };

  should["name a test file that is left out, and stop when none can be used"]{
    root: .tst.testState.mut.runSetup enlist `killed;
    good: .tst.testState.mut.baseRows;
    bad: update file:enlist "tests/test_bad.q", usable:0b, why:enlist "fails on its own: s / t", tail:enlist "the output" from good;
    .tst.testState.mut.baseRows: good, bad;
    code: .tst.mutate.run enlist root, "/src/calc.q";
    some: .tst.testState.mut.printed;
    .tst.testState.mut.capture[];
    .tst.testState.mut.handed: (enlist `)!enlist (::);
    worse: update file:enlist "tests/test_worse.q", tail:enlist "the last output" from bad;
    .tst.testState.mut.baseRows: bad, worse;
    outcome: .tst.testState.mut.try[.tst.mutate.run; enlist root, "/src/calc.q"];
    none: .tst.testState.mut.printed;
    system "rm -rf ", .utl.shellQuote root;
    code musteq 0;
    some[3 4] mustmatch (
      "  1 test file(s) left out, because a failure there would not be the mutant's doing:";
      "    tests/test_bad.q: fails on its own: s / t");
    must[.tst.testState.mut.failed[outcome; "no test file passes on its own*"]; .Q.s1 outcome];
    / The output of the last file that failed is shown, to say why.
    (-2#none) mustmatch (""; "the last output");
    must[not `execute in key .tst.testState.mut.handed; "no mutant is run"];
  };

  should["write the JSON report only when asked"]{
    root: .tst.testState.mut.runSetup enlist `killed;
    dir: root, "/reports";
    `.resq.config.outDir mock dir;
    .tst.mutate.run enlist root, "/src/calc.q";
    without: .utl.pathExists dir, "/mutation-report.json";
    `.tst.app.reportFormats mock `junit`json;
    .tst.mutate.run enlist root, "/src/calc.q";
    with: .utl.pathExists dir, "/mutation-report.json";
    system "rm -rf ", .utl.shellQuote root;
    without musteq 0b;
    with musteq 1b;
  };

  should["fail the run when the score is below the minimum, or there is none"]{
    / One killed of seven: 14.3%.
    root: .tst.testState.mut.runSetup `killed`survived`survived`survived`survived`survived`survived;
    `.tst.app.mutationMin mock 15;
    below: .tst.mutate.run enlist root, "/src/calc.q";
    said: -2#.tst.testState.mut.printed;
    `.tst.app.mutationMin mock 14;
    above: .tst.mutate.run enlist root, "/src/calc.q";
    / One of two is 50.0%: exactly the minimum is enough.
    `.tst.app.maxMutants mock 2;
    `.tst.app.mutationMin mock 50;
    .tst.testState.mut.statuses: `killed`survived;
    equal: .tst.mutate.run enlist root, "/src/calc.q";
    `.tst.app.maxMutants mock 0;
    .tst.testState.mut.statuses: enlist `unmatched;
    .tst.testState.mut.capture[];
    `.tst.app.mutationMin mock 0;
    noScore: .tst.mutate.run enlist root, "/src/calc.q";
    saidNone: last .tst.testState.mut.printed;
    system "rm -rf ", .utl.shellQuote root;
    below musteq 1;
    said mustmatch (""; "Mutation score 14.3% is below the required 15%.");
    above musteq 0;
    equal musteq 0;
    / Nothing could be assessed: a gate cannot pass on no evidence.
    noScore musteq 1;
    saidNone mustmatch "Mutation score n/a is below the required 0%.";
  };

  should["turn an error into a message and a failing exit code"]{
    .tst.testState.mut.capture[];
    `.tst.mutate.run mock {[args] count args};
    .tst.mutate.main[("a"; "b"; "c")] musteq 3;
    (count .tst.testState.mut.printed) musteq 0;
    `.tst.mutate.run mock {[args] '"no such file or directory: x.q"};
    .tst.mutate.main[enlist "x.q"] musteq 1;
    .tst.testState.mut.printed mustmatch enlist "ERR MUTATION ERROR: no such file or directory: x.q";
  };

  should["become a child only when the plan can be read"]{
    `.tst.mutate.active mock 0b;
    path: .tst.testState.mut.scratch["plan"; enlist ""];
    (hsym `$path) set `mode`names`texts`mutated`status!(`probe; `.x.f`.x.g; ("{x}"; "{y}"); ""; path, ".status");
    bad: .tst.mutate.startChild[`.tst.testState.mut.state; path, ".nothere"];
    stillOff: .tst.mutate.active;
    ok: .tst.mutate.startChild[`.tst.testState.mut.state; path];
    on: .tst.mutate.active;
    st: .tst.testState.mut.state;
    .tst.testState.mut.drop path;
    bad musteq 0b;
    stillOff musteq 0b;
    ok musteq 1b;
    on musteq 1b;
    st[`plan; `mode] musteq `probe;
    st[`hits`matched`differs] mustmatch (00b; 00b; 00b);
    st[`applied] musteq 0b;
  };
 };

/ ---------------------------------------------------------------------------
/ End to end: a generated project, the real command, the JSON report.
/ ---------------------------------------------------------------------------

/ Write `files` (relative path -> lines) under a fresh root, run `resq mutate`
/ there with `args`, and return the exit code, the console output, the parsed
/ report and whether every file is byte-for-byte what was written.
.tst.testState.mut.run:{[files;args]
  root: .utl.tempRoot[], "/resq_mut_e2e_", string[.z.i], "_", string `long$.z.p;
  full: (root, "/") ,/: key files;
  system "mkdir -p ", " " sv .utl.shellQuote each distinct .tst.static.getDir each full;
  {[path;lines] (hsym `$path) 0: lines}'[full; value files];
  digest: {[paths] {md5 "c"$read1 hsym `$x} each paths};
  before: digest full;
  command: "cd ", .utl.shellQuote[root], " && MUT_ROOT=", .utl.shellQuote[root], " ",
    .utl.shellQuote[.tst.isolate.qExe], " ", .utl.shellQuote[.resq.HOME, "/resq.q"],
    " mutate ", args, " -json -outDir out < /dev/null > out.txt 2>&1; echo $? > rc.txt; true";
  / Through sh: q's own `system` reads a leading "cd" as its \cd command.
  @[system; "sh -c ", .utl.shellQuote command; {[e] e}];
  code: "J"$first @[read0; hsym `$root, "/rc.txt"; {[e] enlist "-1"}];
  output: @[read0; hsym `$root, "/out.txt"; {[e] ()}];
  report: @[{.j.k raze read0 hsym `$x}; root, "/out/mutation-report.json"; {[e] ()!()}];
  untouched: before~digest full;
  system "rm -rf ", .utl.shellQuote root;
  `code`output`report`untouched!(code; output; report; untouched)
 };

.tst.testState.mut.project: ("src/calc.q"; "lib/loader.q"; "tests/test_calc.q"; "tests/test_broken.q")!(
  (".mx.add:{[x;y] x+y};";
   ".mx.grade:{[x] $[x>=50; `pass; `fail]};";
   ".mx.unused:{[x] x*2};";
   ".mx.over:{[x] x+1};";
   ".mx.spin:{[n] i:0; while[i<n; i+:1]; i};");
  / A project loader: a module name, a root from the environment, a computed
  / path and a load-once cache. Nothing in the text names src/calc.q.
  (".ld.loaded: ();";
   ".ld.load:{[module]";
   "    if[module in .ld.loaded; :()];";
   "    .ld.loaded,: module;";
   "    system \"l \", getenv[`MUT_ROOT], \"/src/\", string[module], \".q\";";
   " };");
  ("\\l lib/loader.q";
   ".ld.load `calc;";
   "/ replaced after loading: memory no longer holds the file's definition";
   ".mx.over:{[x] x+2};";
   ".tst.desc[\"calc\"]{";
   "  should[\"add\"]{ .mx.add[1;2] musteq 3 };";
   "  should[\"grade\"]{ .mx.grade[80] musteq `pass; .mx.grade[10] musteq `fail };";
   "  should[\"spin\"]{ .mx.spin[3] musteq 3 };";
   " };");
  ("\\l lib/loader.q";
   ".ld.load `calc;";
   ".tst.desc[\"fails on its own\"]{";
   "  should[\"be wrong\"]{ .mx.add[1;2] musteq 4 };";
   " };"));

/ Status of the mutants of one function, keyed by description.
.tst.testState.mut.statusOf:{[report;fn]
  m: report`mutants;
  m: m where (m`function)~\:fn;
  (`$m`description)!`$m`status
 };

.tst.desc["mutation: the real command on a generated project (#slow)"]{
  skipIf[not .tst.testState.mut.canRun;
         "kills, survivors, timeouts, uncovered and unmatched functions are told apart"]{
    r: .tst.testState.mut.run[.tst.testState.mut.project; "src -isolateWorkers 4"];
    shown: "\n" sv r`output;
    must[0 = r`code; "the run succeeds: ", shown];
    rep: r`report;
    must[99h = type rep; "a JSON report is written: ", shown];

    add: .tst.testState.mut.statusOf[rep; ".mx.add"];
    must[all `killed = value add; "a fully tested function has no survivor: ", .Q.s1 add];
    2 musteq count add;

    grade: .tst.testState.mut.statusOf[rep; ".mx.grade"];
    grade[`$"`>=` replaced with `>`"] musteq `survived;
    grade[`$"`50` replaced with `51`"] musteq `survived;
    grade[`$"condition negated: x>=50"] musteq `killed;

    unused: .tst.testState.mut.statusOf[rep; ".mx.unused"];
    must[all `uncovered = value unused; "a function no test calls: ", .Q.s1 unused];
    replaced: .tst.testState.mut.statusOf[rep; ".mx.over"];
    must[all `unmatched = value replaced; "a function replaced in memory is not mutated: ", .Q.s1 replaced];

    spin: .tst.testState.mut.statusOf[rep; ".mx.spin"];
    / A mutant that never returns is stopped and counted as detected.
    spin[`$"`+:` replaced with `-:`"] musteq `timeout;
    spin[`$"`<` replaced with `<=`"] musteq `killed;

    / The failing file is left out, and named with the reason.
    files: rep`testFiles;
    usable: (`$files`file)!files`usable;
    usable[`$"tests/test_calc.q"] musteq 1b;
    usable[`$"tests/test_broken.q"] musteq 0b;
    must[any (r`output) like "*test_broken.q: fails on its own*"; "the excluded file is explained: ", shown];
    killers: distinct (rep[`mutants]`killedBy) except enlist "";
    killers mustmatch enlist "tests/test_calc.q";

    / The summary adds up and the console agrees with the report.
    s: rep`summary;
    must[(s`mutants) = count rep`mutants; "the summary counts every mutant"];
    must[(s`mutants) = sum s`killed`timedOut`survived`notCovered`notAssessed; "and its parts add up: ", .Q.s1 s];
    must[any (r`output) like "*Mutation score: *"; "the score is printed: ", shown];

    must[r`untouched; "no file of the project was changed"];
  };

  skipIf[not .tst.testState.mut.canRun;
         "the score gate, a line range and a clean function"]{
    files: .tst.testState.mut.project;
    r: .tst.testState.mut.run[files; "src/calc.q:1 -tests tests/test_calc.q -mutation-min 100"];
    must[0 = r`code; "a function with no survivor passes a 100% gate: ", "\n" sv r`output];
    (`$r[`report][`mutants]`function) mustmatch 2#`.mx.add;

    r: .tst.testState.mut.run[files; "src/calc.q:2 -tests tests/test_calc.q -mutation-min 100"];
    must[1 = r`code; "a survivor fails the gate: ", "\n" sv r`output];
    must[any (r`output) like "*is below the required 100%*"; "and says so: ", "\n" sv r`output];
  };

  skipIf[not .tst.testState.mut.canRun;
         "nothing is assessed when no test file passes on its own"]{
    files: ("src/calc.q"; "lib/loader.q"; "tests/test_broken.q")#.tst.testState.mut.project;
    r: .tst.testState.mut.run[files; "src/calc.q:1"];
    must[1 = r`code; "the run fails: ", "\n" sv r`output];
    must[any (r`output) like "*no test file passes on its own*"; "and says why: ", "\n" sv r`output];
    must[r`untouched; "no file of the project was changed"];
  };

  skipIf[not .tst.testState.mut.canRun;
         "a wrong path or option is an error, not an empty success"]{
    files: .tst.testState.mut.project;
    r: .tst.testState.mut.run[files; "src/missing.q"];
    must[1 = r`code; "a missing source fails: ", "\n" sv r`output];
    must[any (r`output) like "*no such file or directory: src/missing.q*"; "\n" sv r`output];
    r: .tst.testState.mut.run[files; "src -tests nowhere"];
    must[1 = r`code; "a missing test path fails: ", "\n" sv r`output];
    r: .tst.testState.mut.run[files; "src -mutators nonsense"];
    must[1 = r`code; "an unknown mutator fails: ", "\n" sv r`output];
  };
 };
