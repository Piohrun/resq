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
