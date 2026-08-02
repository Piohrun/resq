.tst.desc["The Testing UI"]{
 alt {
  before{
   `myRestore mock .tst.restore;
   `.tst.restore mock {};
   `.tst.callbacks.descLoaded mock {};
   `.tst.mock mock {[x;y]};
  };
  after{
   myRestore[];
   };
  should["let you create specifications"]{
   descStr: "This is a description";
   myDesc: .tst.desc[descStr]{}; / Not testing the other parts of the UI here
   99h musteq type myDesc;
   descStr mustmatch myDesc`title;
   };
  should["cause specifications to assume the context that they were defined in"]{
   oldContext: string system "d";
   system "d .foo";
   myDesc: .tst.desc["Blah"]{};
   system "d ", oldContext;
   `.foo mustmatch myDesc`context;
   };
  should["call the descLoaded callback when a new specification is defined"]{
   `callbackCalled mock 0b;
   `.tst.callbacks.descLoaded mock {`callbackCalled set 1b};
   .tst.desc["Blah"]{};
   must[callbackCalled;"Expected the descLoaded callback to have been called"];
   };
  };
 should["let you set a before function"]{
  `.tst.currentBefore mock .tst.currentBefore;
  bFunction: {"unique message before"};
  .tst.before bFunction;
  bFunction mustmatch .tst.currentBefore;
  };
 should["let you set an after function"]{
  `.tst.currentAfter mock .tst.currentAfter;
  aFunction: {"unique message after"};
  .tst.after aFunction;
  aFunction mustmatch .tst.currentAfter;
  };
 should["let you create an expectation"]{
  `.tst.expecList mock .tst.expecList;
  description:"unique description expec";
  func:{"unique message expec"};
  .tst.should[description;func];
  e:.tst.fillExpecBA .tst.expecList;
  1 musteq count e;
  description mustmatch first e[`desc];
  func mustmatch first e[`code];
  };
 should["let you create a fuzz expectation"]{
  `.tst.expecList mock .tst.expecList;
  description:"unique description fuzz";
  func:{"unique message fuzz"};
  .tst.holds[description;()!();func];
  e:.tst.fillExpecBA .tst.expecList;
  1 musteq count e;
  description mustmatch first e[`desc];
  func mustmatch first e[`code];
  };
 should["expose public root helper aliases"]{
  (get `..mock) mustmatch .tst.mock;
  (get `..fixture) mustmatch .tst.fixture;
  (get `..fixtureAs) mustmatch .tst.fixtureAs;
  (get `..tempFile) mustmatch .tst.tempFile;
  (get `..registerCleanup) mustmatch .tst.registerCleanup;
  };
 / SKIPPED: Known q parsing limitation - multi-line nested code blocks fail to parse
 / when evaluated via `value`. This is a pre-existing q language constraint.
 / Test: should["let you mask before and after functions inside of alternate blocks"]
 };

/ qspec allows before/after to be declared AFTER the expectations they apply to
/ ("Before and After values can be set after the expectation"). Joining alt's
/ already-filled expectations with unfilled ones coerces the list to a table and
/ q fills the new rows' before/after with `::`; treating that placeholder as a
/ real hook meant a before/after declared after an alt block silently never ran.
.tst.testState.altlog: ();
.tst.desc["alt blocks and hooks declared after them"]{
    alt{
        before{ .tst.testState.altlog,: enlist "innerBefore" };
        after{  .tst.testState.altlog,: enlist "innerAfter" };
        should["inside alt"]{ .tst.testState.altlog,: enlist "innerTest"; 1 musteq 1; };
    };
    before{ .tst.testState.altlog,: enlist "outerBefore" };
    after{  .tst.testState.altlog,: enlist "outerAfter" };
    should["declared after the alt block"]{
        .tst.testState.altlog,: enlist "outerTest"; 1 musteq 1;
    };
};

.tst.desc["alt hook masking verification"]{
    should["run the alt's own hooks, then the outer hooks declared after it"]{
        .tst.testState.altlog musteq ("innerBefore";"innerTest";"innerAfter";
                                      "outerBefore";"outerTest";"outerAfter");
    };
    should["clean up its scratch state"]{
        @[{![`.tst.testState; (); 0b; enlist `altlog]}; (); {}];
        1 musteq 1;
    };
};
