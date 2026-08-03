/ ============================================================================
/ qspec source-compatibility surface.
/ .
/ resQ exists to be a drop-in replacement for qspec (nugend/qspec), so the
/ qspec-facing DSL and assertion surface is a CONTRACT, not an implementation
/ detail. This file is written the way a qspec suite is written and must keep
/ passing unchanged. It exists because compatibility was twice broken by
/ well-intentioned correctness fixes (must's condition contract, mustne's
/ comparison) and nothing caught it -- the regressions were found only by
/ diffing against a clone of qspec by hand.
/ .
/ Everything here must hold in BOTH default and -qspec-compat mode; the
/ mode-SPECIFIC semantics are pinned separately in test_qspec_compat.q.
/ ============================================================================

.tst.desc["qspec surface: suite and test verbs"]{
  before{ .tst.testState.qsurface.beforeRan: 1b };
  after{  .tst.testState.qsurface.afterRan:  1b };

  should["run a should block"]{ 1 musteq 1 };
  it["expose `it` as an alias for should"]{ 1 musteq 1 };

  should["have run the before hook"]{
    must[.tst.testState.qsurface.beforeRan; "before must have run"];
  };
 };

.tst.desc["qspec surface: alt blocks mask hooks"]{
  alt{
    before{ .tst.testState.qsurface.altBefore: 1b };
    should["use the alt's own before"]{
      must[.tst.testState.qsurface.altBefore; "alt before must have run"];
    };
  };
  before{ .tst.testState.qsurface.outerBefore: 1b };
  should["use a before declared after the alt block"]{
    must[.tst.testState.qsurface.outerBefore; "outer before must have run"];
  };
 };

.tst.desc["qspec surface: every qspec assertion"]{
  should["compare and match"]{
    1 musteq 1;
    "abc" musteq "abc";
    mustne[1; 2];
    (1 2 3) mustmatch 1 2 3;
    mustnmatch[1 2 3; 1 2 4];
  };
  should["order, membership and range"]{
    1 mustlt 2;
    2 mustgt 1;
    "hello" mustlike "he*";
    mustin[2; 1 2 3];
    mustnin[9; 1 2 3];
    mustwithin[5; 1 10];
    mustdelta[0.01; 1.001; 1.0];
  };
  should["truth values, including q truthiness"]{
    must[1b; "boolean"];
    must[count 1 2 3; "a non-zero count is true, as in qspec"];
  };
  should["errors"]{
    mustthrow["*boom*"; {'"boom"}];
    mustthrow[(); {'"anything"}];
    mustthrow[("*nope*"; "*boom*"); {'"boom"}];   / list of patterns
    mustnotthrow[(); {1 + 1}];
  };
 };

.tst.desc["qspec surface: mocking"]{
  should["mock a value and see it"]{
    `.tst.testState.qsurface.target mock 42;
    .tst.testState.qsurface.target musteq 42;
  };
  should["have restored the mock automatically"]{
    must[not `target in key `.tst.testState.qsurface;
         "a mock must be restored after the should block that set it"];
  };
 };

.tst.desc["qspec surface: file fixtures"]{
  before{ fixture `qspecSurface };

  should["load a fixture into its default name"]{
    ([]whole:20 40i; word:`foo`bar) mustmatch qspecSurface;
  };

  should["load the same fixture under an explicit name"]{
    fixtureAs[`qspecSurface; `qspecSurfaceAlias];
    qspecSurface mustmatch qspecSurfaceAlias;
  };
 };

.tst.desc["qspec surface: legacy runner options"]{
  should["accept qspec's original option names"]{
    parsed:.tst.parseCLI ("-performance"; "-pass"; "-fuzz-display-limt"; "17"; "suite.q");
    parsed[`ok] musteq 1b;
    parsed[`options; `perf] musteq 1b;
    parsed[`options; `passOnly] musteq 1b;
    parsed[`options; `fuzzLimit] musteq 17;
    parsed[`args] mustmatch enlist "suite.q";
  };

  should["accept qspec's short fuzz display alias"]{
    parsed:.tst.parseCLI ("-fdl"; "9"; "suite.q");
    parsed[`ok] musteq 1b;
    parsed[`options; `fuzzLimit] musteq 9;
  };
 };

.tst.desc["qspec surface: property-based holds"]{
  holds["addition is commutative"; `runs`vars!(20; `a`b!(`int;`int))]{[x]
    (x[`a] + x[`b]) musteq (x[`b] + x[`a])
  };
 };

/ qspec's perf verb is registered at load time but executes only when the
/ runner receives -perf/-performance, exactly like the original framework.
.tst.desc["qspec surface: performance"]{
  perf["run a qspec-style performance expectation"; enlist[`runs]!enlist 2]{
    1 musteq 1
  };
 };

.tst.desc["qspec surface: cleanup"]{
  should["drop the scratch state this file used"]{
    @[{![`.tst.testState; (); 0b; enlist `qsurface]}; (); {}];
    1 musteq 1;
  };
 };
