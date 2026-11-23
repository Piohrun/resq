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

/ Run `body` as a mutation child would see things: the plan is loaded from a
/ file, but the runner's own hooks stay off so only the calls in `body` act.
/ Returns what body returned and the status lines the plan produced.
.tst.testState.mut.withPlan:{[plan;body]
  path: .tst.testState.mut.scratch["plan"; enlist ""];
  status: path, ".status";
  plan[`status]: status;
  (hsym `$path) set plan;
  .tst.mutate.loadPlan path;
  .tst.mutate.active: 0b;
  r: @[{[f] (1b; f[])}; body; {[e] (0b; e)}];
  lines: @[read0; hsym `$status; {[e] ()}];
  .tst.mutate.plan: ()!();
  .tst.testState.mut.drop path;
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

  should["not repeat the removal of a block that has one statement"]{
    n: .tst.testState.mut.notes["{[x] if[x<0; '\"negative\"]; x}"; `statement];
    n mustmatch ("statement removed: if[x<0; '\"negative\"]"; "statement removed: x");
  };

  should["shorten a long statement to sixty characters"]{
    / 62 characters is cut to 57 and an ellipsis; exactly 60 is shown whole.
    long: "total: ", (54#"x+"), "x";
    n: .tst.testState.mut.notes["{[x] ", long, "; total}"; `statement];
    first[n] mustmatch "statement removed: ", (57#long), "...";
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
    0 musteq count .tst.testState.mut.full "{x+";
    0 musteq count .tst.testState.mut.full "1+1";
    0 musteq count .tst.testState.mut.full "";
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
    0 musteq count .tst.mutate.functionsIn "/nonexistent/resq/mutation/file.q";
    path: .tst.testState.mut.scratch["src.q"; ()];
    n: count .tst.mutate.functionsIn path;
    .tst.testState.mut.drop path;
    0 musteq n;
  };
 };

/ ---------------------------------------------------------------------------
.tst.desc["mutation: targets and options"]{
  should["read a path, a line and a line range"]{
    .tst.mutate.parseTarget["src/a.q"] mustmatch `path`lo`hi!("src/a.q"; 0N; 0N);
    .tst.mutate.parseTarget["src/a.q:12"] mustmatch `path`lo`hi!("src/a.q"; 12; 12);
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
      "@@ -10,0 +11,3 @@ context"; "+a"; "+b"; "+c";
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

  should["report an error the child recorded while installing"]{
    st: ("applied"; "error could not compile the mutant: x");
    .tst.mutate.verdict[.tst.testState.mut.child[1; 1b; 1; 0b; 0b; st]] musteq `error;
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
    out: .tst.testState.mut.withPlan[plan; {.tst.mutate.install[]; .tst.mutate.install[]; .tst.mutFixTimes 6}];
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
      .tst.mutate.install[];
      first1: .tst.testState.mut.fix 10;
      .tst.testState.mut.fix:: value "{[x] x+1}";
      reloaded: .tst.testState.mut.fix 10;
      .tst.mutate.install[];
      (first1; reloaded; .tst.testState.mut.fix 10)}];
    out[`result] mustmatch 9 11 9;
    out[`status] mustmatch enlist "applied";
  };

  should["leave alone a function that is not the one in the file"]{
    .tst.testState.mut.fix: value "{[x] x+2}";
    plan: `mode`names`texts`mutated`status!(`mutant; enlist `.tst.testState.mut.fix;
      enlist "{[x] x+1}"; "{[x] x-1}"; "");
    out: .tst.testState.mut.withPlan[plan; {.tst.mutate.install[]; .tst.testState.mut.fix 10}];
    out[`result] musteq 12;
    0 musteq count out`status;
  };

  should["leave alone a name that is undefined or not a function"]{
    .tst.testState.mut.fix: 42;
    plan: `mode`names`texts`mutated`status!(`mutant; enlist `.tst.testState.mut.fix;
      enlist "{[x] x+1}"; "{[x] x-1}"; "");
    out: .tst.testState.mut.withPlan[plan; {.tst.mutate.install[]; .tst.testState.mut.fix}];
    out[`result] musteq 42;
    plan[`names]: enlist `.tst.testState.mut.neverDefined;
    out: .tst.testState.mut.withPlan[plan; {.tst.mutate.install[]; 1b}];
    0 musteq count out`status;
  };

  should["record an error instead of signalling when the mutant does not compile"]{
    .tst.testState.mut.fix: value "{[x] x+1}";
    plan: `mode`names`texts`mutated`status!(`mutant; enlist `.tst.testState.mut.fix;
      enlist "{[x] x+1}"; "{[x] x+"; "");
    out: .tst.testState.mut.withPlan[plan; {.tst.mutate.install[]; .tst.testState.mut.fix 10}];
    out[`result] musteq 11;
    must[all out[`status] like "error*"; "an error line and no applied line: ", .Q.s1 out`status];
    1 musteq count out`status;
  };

  should["probe which functions are called without changing what they return"]{
    .tst.testState.mut.pa: value "{[x;y] x+y}";
    .tst.testState.mut.pb: value "{x*2}";
    .tst.testState.mut.pc: value "{[] 7}";
    .tst.testState.mut.pd: value "{[x] x+2}";
    names: `.tst.testState.mut.pa`.tst.testState.mut.pb`.tst.testState.mut.pc`.tst.testState.mut.pd`.tst.testState.mut.pe;
    texts: ("{[x;y] x+y}"; "{x*2}"; "{[] 7}"; "{[x] x+1}"; "{x}");
    plan: `mode`names`texts`mutated`status!(`probe; names; texts; ""; "");
    out: .tst.testState.mut.withPlan[plan; {
      .tst.mutate.install[];
      .tst.mutate.install[];
      r: (.tst.testState.mut.pa[2;3]; .tst.testState.mut.pc[]; .tst.testState.mut.pd 1);
      .tst.mutate.finish[];
      r}];
    out[`result] mustmatch 5 7 3;
    st: out`status;
    .tst.mutate.statusIndexes[st; "matched"] mustmatch 0 1 2;
    .tst.mutate.statusIndexes[st; "differs"] mustmatch enlist 3;
    .tst.mutate.statusIndexes[st; "hit"] mustmatch 0 2;
    must[.tst.testState.mut.has[st; "done"]; "the probe reports that it finished: ", .Q.s1 st];
  };
 };

/ ---------------------------------------------------------------------------
/ End to end: a generated project, the real command, the JSON report.
/ ---------------------------------------------------------------------------

.tst.testState.mut.canRun: (0 < count .tst.isolate.qExe) and
  0 < count @[system; "which timeout 2>/dev/null"; {[e] ()}];

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
