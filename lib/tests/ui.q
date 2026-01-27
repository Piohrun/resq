\d .tst
uiSet:{.[`.tst;(),x;:;y]}

resetExpecList:{.tst.expecList: ()} 
resetExpecList[];
currentBefore:{}
currentAfter:{}

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
  .tst.expecList,: enlist .tst.internals.testObj, (`desc`code`tags!(desStr;code;tags))
 }

holds:{[des;props;code]
  desStr: .tst.toString des;
  d: .tst.internals.fuzzObj, (`desc`code!(desStr;code));
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

uiRuntimeNames:`fixture`fixtureAs`mock
uiRuntimeCode: (.tst.fixture;.tst.fixtureAs;.tst.mock)
uiNames:`before`after`should`holds`perf`alt
uiCode:(before;after;should;holds;perf;alt)

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
 specObj[`context]: system "d";

 expectations[];
 
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

\d .
describe: .tst.desc
should: .tst.should
holds: .tst.holds
perf: .tst.perf
alt: .tst.alt
before: .tst.before
after: .tst.after
\d .tst
::
