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
