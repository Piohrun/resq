/ The loader rewrites resQ words in test source so they reach the framework.
/ These tests pin what it must leave alone. Each case is something real qspec
/ suites contain; see docs/reviews for the audit that found them.

.tst.desc["symbols are data, whatever words they contain"]{
  should["leave file handles alone"]{
    src: enlist "  (count read0 `:data/fixture/trades.csv) musteq 2;";
    out: first .tst.preprocessScript src;
    (out like "*`:data/fixture/trades.csv*") musteq 1b;
    (out like "*.tst.dsl.fixture*") musteq 0b;
    out: first .tst.preprocessScript enlist "  `:out/after set 1 2 3;";
    out musteq "  `:out/after set 1 2 3;";
  };
  should["leave connection handles and symbol lists alone"]{
    line: "  h: `:host:5010:user:must; s: `before`after`:x/mock`skip;";
    (first .tst.preprocessScript enlist line) musteq line;
  };
  should["still qualify a call that follows a symbol"]{
    out: first .tst.preprocessScript enlist "  `.app.f mock {[x] x};";
    (out like "*.tst.dsl.mock*") musteq 1b;
  };
  should["mask symbol bodies by q's own rule"]{
    / the body is blanked; the backtick stays
    .tst.maskQLine["a:`:dir/after 1"] musteq "a:`           1";
    / without a colon the slash is an adverb, not part of the symbol
    .tst.maskQLine["`a/b"] musteq "` /b";
    .tst.maskQLine["`a`b`:c/d`e,x"] musteq "` ` `    ` ,x";
    / a backtick inside a string is not a symbol
    .tst.maskQLine["\"`x\" , y"] musteq "\"  \" , y";
  };
 };

.tst.desc["a resQ word is the framework's only where it is applied"]{
  should["leave reads, operands and qSQL columns alone"]{
    same: {[line] line ~ first .tst.preprocessScript enlist line};
    same["  n: exec max retry from orders;"] musteq 1b;
    same["  r: select from orders where pending, not skip;"] musteq 1b;
    same["  t: delete skip from orders;"] musteq 1b;
    same["  d: after-before;"] musteq 1b;
    same["  x: (count pending; it; retry);"] musteq 1b;
  };
  should["leave the left operand of an assertion alone"]{
    (first .tst.preprocessScript enlist "  retry mustne 0;") musteq "  .tst.dsl.mustne[retry;] 0;";
    (first .tst.preprocessScript enlist "  (count pending) mustgt 0;") musteq "  .tst.dsl.mustgt[(count pending);] 0;";
  };
  should["qualify every applied form"]{
    pp: {[line] first .tst.preprocessScript enlist line};
    (pp["  before{ 1 };"] like "*.tst.dsl.before{*") musteq 1b;
    (pp["  before ({ 1 });"] like "*.tst.dsl.before (*") musteq 1b;
    (pp["  fixture `trades;"] like "*.tst.dsl.fixture `trades*") musteq 1b;
    (pp["  p: tempFile \".csv\";"] like "*.tst.dsl.tempFile \"*") musteq 1b;
    (pp["  fixture each `a`b;"] like "*.tst.dsl.fixture each*") musteq 1b;
    (pp["  fixture'[`a`b];"] like "*.tst.dsl.fixture'*") musteq 1b;
  };
  should["keep assertions and mock the framework's everywhere, as in qspec"]{
    pp: {[line] first .tst.preprocessScript enlist line};
    (pp["  f: musteq;"] like "*.tst.dsl.musteq;*") musteq 1b;
    (pp["  .[mock; (`a; 1)];"] like "*.tst.dsl.mock;*") musteq 1b;
  };
 };

.tst.desc["a table whose columns are named like resQ words"]{
  should["is queried as q queries it"]{
    orders: flip `id`pending`retry`skip`it!(1 2 3; 101b; 0 2 5; 010b; 10 20 30);
    (exec count i from orders where pending) musteq 2;
    (exec max retry from orders) musteq 5;
    (cols delete skip from orders) musteq `id`pending`retry`it;
    (exec sum it from orders where not skip) musteq 40;
  };
 };

.tst.desc["loading the code under test, as \\l does"]{
  should["keep the working directory while a file loads"]{
    / An application whose entry file loads its own files by paths relative
    / to the project root, which is how it is started in production.
    root: .utl.tempRoot[], "/resq_load_", string[.z.i], "_", string `long$.z.p;
    system "mkdir -p ", .utl.shellQuote root, "/src";
    (hsym `$root, "/src/util.q") 0: enlist ".loadprobe.util: 1b;";
    (hsym `$root, "/src/app.q") 0: (
        "\\l src/util.q";
        ".loadprobe.cwd: system \"cd\";");
    .tst.registerCleanup[{[d] @[system; "rm -rf ", .utl.shellQuote d; {}]; @[system; "x .loadprobe"; {}]}; enlist root];
    system "cd ", root;
    .tst.sysl "src/app.q";
    .loadprobe.util musteq 1b;
    .loadprobe.cwd musteq root;
    (system "cd") musteq root;
  };
  should["accept a comment after the path"]{
    (first .tst.preprocessScript enlist "\\l dep.q / code under test") musteq ".tst.sysl \"dep.q\";";
    (first .tst.preprocessScript enlist "\\l /abs/dir/dep.q") musteq ".tst.sysl \"/abs/dir/dep.q\";";
    / q rejects anything else after the path; resQ keeps it, for paths with spaces
    (first .tst.preprocessScript enlist "\\l my dir/dep.q") musteq ".tst.sysl \"my dir/dep.q\";";
  };
  should["see a load written as one string literal, so coverage instruments it"]{
    .tst.rewriteSystemLoad["system \"l src/p.q\";"] musteq ".tst.sysl \"src/p.q\";";
    .tst.rewriteSystemLoad["  system \"l src/p.q\""] musteq "  .tst.sysl \"src/p.q\"";
    .tst.rewriteSystemLoad["system \"l dep.q / code under test\";"] musteq ".tst.sysl \"dep.q\";";
    / not a load statement on its own: left exactly as written
    same: {[line] line ~ .tst.rewriteSystemLoad line};
    same["system \"l src/p.q\"; loaded: 1b;"] musteq 1b;
    same["r: system \"l src/p.q\";"] musteq 1b;
    same["system \"ls -l\";"] musteq 1b;
  };
  should["wrap a computed load only when it is the whole statement"]{
    .tst.rewriteSystemLoad["  system \"l \", root, \"/src/x.q\";"] musteq "  .tst.sysl (root, \"/src/x.q\");";
    .tst.rewriteSystemLoad["  system \"l \", path[`src;\"x.q\"];"] musteq "  .tst.sysl (path[`src;\"x.q\"]);";
    line: "  system \"l \", f; loaded: 1b;";
    .tst.rewriteSystemLoad[line] musteq line;
  };
 };

/ Source lines went through .resq.util.pathToString, which takes a leading
/ ":" for a file handle's and drops it: "::" became ":", and every offset
/ after such a line in the masked source was one off.
.tst.desc["a line that starts with a colon"]{
  should["keep it as written when the file is read"]{
    lines: ("a:1"; "::"; ":x"; "b:2");
    pp: .tst.preprocessScript lines;
    (pp where not pp like "/*") mustmatch lines;
    (.tst.groupStatements lines)[;1] mustmatch enlist each lines;
    .tst.bracketDelta[":["] musteq 1;
  };
  should["keep every offset of the masked source"]{
    lines: ("a:1"; "::"; "b:\"str\"");
    masked: .tst.dslMaskedSource lines;
    (count masked) musteq count "\n" sv lines;
    masked mustmatch "a:1\n::\nb:\"   \"";
  };
 };

/ q joins the lines that continue a system command to it, as KX's TAQ
/ scripts rely on (\t a:select ... / ` where ...`). The loader ended the
/ command at its first line and ran the continuation on its own.
.tst.desc["a system command continued on the next line"]{
  should["be one command, as q reads it"]{
    pp: .tst.preprocessScript ("\\t .tst.testState.cont.a:til"; ""; "/ a comment"; " 10"; "r:1");
    pp mustmatch ("system \"t .tst.testState.cont.a:til\\n 10\";"; "r:1");
    .tst.preprocessScript[("\\d .x"; "y:1")] mustmatch ("system \"d .x\";"; "y:1");
  };
  should["run as q runs it"]{
    .tst.testState.cont.b: ();
    .tst.evalPreprocessed .tst.preprocessScript ("\\t .tst.testState.cont.b:til"; "  5");
    .tst.testState.cont.b mustmatch til 5;
  };
 };
