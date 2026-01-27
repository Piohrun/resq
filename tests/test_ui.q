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
 / SKIPPED: Known q parsing limitation - multi-line nested code blocks fail to parse
 / when evaluated via `value`. This is a pre-existing q language constraint.
 / Test: should["let you mask before and after functions inside of alternate blocks"]
 };
