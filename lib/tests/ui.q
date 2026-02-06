\d .tst
uiSet:{.[`.tst;(),x;:;y]}

resetExpecList:{.tst.expecList: ()} 
resetExpecList[];
currentBefore:{}
currentAfter:{}
currentNs:`.

before:{[code]
 .tst.currentBefore: code
 }

after:{[code]
 .tst.currentAfter: code
 }

fillExpecBA:{[x]
  { [ex]
    if[not `before in key ex; ex[`before]: .tst.currentBefore];
    if[not `after in key ex; ex[`after]: .tst.currentAfter];
    ex
  } each x
 }

alt:{[code]
 oldBefore: .tst.currentBefore;
 oldAfter: .tst.currentAfter;
 oldExpecList: .tst.expecList;
 .tst.expecList: ();
 code[];
 el:fillExpecBA .tst.expecList;
 .tst.currentBefore: oldBefore;
 .tst.currentAfter: oldAfter;
 .tst.expecList: oldExpecList, el;
 }

should:{[des;code]
  desStr: .tst.toString des;
  tags: `$ {x where x like "#*"} " " vs desStr;
  .tst.expecList,: enlist .tst.internals.testObj, (`desc`code`tags`namespace!(desStr;code;tags;.tst.currentNs))
 }

holds:{[des;props;code]
  desStr: .tst.toString des;
  d: .tst.internals.fuzzObj, (`desc`code`namespace!(desStr;code;.tst.currentNs));
  / Handle single-key dict (type -20 enumeration) and regular dict (type 99)
  propsDict: $[99h = type props; props;
               (type props) in -20 20h; (enlist key props)!(enlist value props);
               ()!()];
  if[0 < count propsDict; d: d, propsDict];
  .tst.expecList,: enlist d
 }

perf:{[des;props;code]
  desStr: .tst.toString des;
  d: .tst.internals.perfObj, (`desc`code!(desStr;code));
  / Handle single-key dict (type -20 enumeration) and regular dict (type 99)
  propsDict: $[99h = type props; props;
               (type props) in -20 20h; (enlist key props)!(enlist value props);
               ()!()];
  if[0 < count propsDict; d: d, propsDict];
  .tst.expecList,: enlist d
 }

/ Skip a test with a reason
skip:{[reason;code]
  desStr: "SKIP: ", .tst.toString reason;
  d: .tst.internals.testObj, (`desc`code`result`skipReason!(desStr; {}; `skip; reason));
  .tst.expecList,: enlist d
 }

/ Mark a test as pending (placeholder)
pending:{[reason]
  desStr: "PENDING: ", .tst.toString reason;
  d: .tst.internals.testObj, (`desc`code`result`skipReason!(desStr; {}; `pending; reason));
  .tst.expecList,: enlist d
 }

/ Conditionally skip based on a condition
skipIf:{[condition;reason;code]
  $[condition; skip[reason; code]; should[reason; code]]
 }

uiRuntimeNames:`fixture`fixtureAs`mock
uiRuntimeCode: (.tst.fixture;.tst.fixtureAs;.tst.mock)

.tst.desc:{[title;expectations]
 oldBefore: .tst.currentBefore;
 oldAfter: .tst.currentAfter;
 oldExpecList: .tst.expecList;
 .tst.expecList: ();
 specObj: .tst.internals.specObj;
 titleStr: .tst.toString title;
 specObj[`title]: titleStr;
 specObj[`tags]: `$ {x where x like "#*"} " " vs titleStr;
 / Capture the context where this spec is defined
  specObj[`context]: specObj[`namespace]: system "d";

 oldDir: system "d";
 expectations[];
 system "d ", string oldDir;
 
 / Use hsym format for tstPath - compatible with ` vs for path operations
 specObj[`tstPath]: $[`FILELOADING in key `.utl; .utl.FILELOADING; `$":unknown"];
  specObj[`expectations]:fillExpecBA .tst.expecList;
  .tst.currentBefore: oldBefore;
  .tst.currentAfter: oldAfter;
  .tst.expecList: oldExpecList;
  / Note: Don't add spec to expecList - it causes type conflicts when tests
  / call should[] while expecList contains specs (different column structure).
  / The descLoaded callback handles spec collection via .tst.app.allSpecs.
  .tst.restore[];
  .tst.callbacks.descLoaded specObj;
  specObj
 }
describe:desc
it:should

uiNames:`before`after`should`it`holds`perf`alt`describe`skip`pending`skipIf
uiCode:(before;after;should;it;holds;perf;alt;desc;skip;pending;skipIf)

\d .
/ Expose DSL to root and .q namespaces
describe: .tst.desc; should: .tst.should; it: .tst.should;
before: .tst.before; after: .tst.after;
holds: .tst.holds; perf: .tst.perf; alt: .tst.alt;
skip: .tst.skip; pending: .tst.pending; skipIf: .tst.skipIf;

.q.describe: .tst.desc; .q.should: .tst.should; .q.it: .tst.should;
.q.before: .tst.before; .q.after: .tst.after;
.q.holds: .tst.holds; .q.perf: .tst.perf; .q.alt: .tst.alt;
.q.skip: .tst.skip; .q.pending: .tst.pending; .q.skipIf: .tst.skipIf;

\d .tst
::
