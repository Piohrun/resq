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

/ File-level setup/teardown hooks (run once per describe block).
currentBeforeAll:{}
currentAfterAll:{}
/ Flags track whether beforeAll/afterAll was set by a setter since the last
/ desc consumed (and reset) them. Robust against lambda-identity pitfalls:
/ comparing two empty lambdas from different definition sites with ~ is not
/ reliable, so we never compare lambdas to detect "was it set" -- a flag is.
currentBeforeAllSet:0b
currentAfterAllSet:0b

beforeAll:{[code]
 .tst.currentBeforeAll: code;
 .tst.currentBeforeAllSet: 1b
 }

afterAll:{[code]
 .tst.currentAfterAll: code;
 .tst.currentAfterAllSet: 1b
 }

/ A hook is "already set" only if the key is present AND carries a real value.
/ Joining expectations that HAVE before/after (e.g. those returned by an alt
/ block, which fills them on the way out) with ones that do not coerces the list
/ to a table, and q fills the new rows' before/after with a `::` placeholder.
/ Treating that placeholder as a real hook meant a `before`/`after` declared
/ AFTER an alt block silently never ran -- qspec explicitly allows hooks to be
/ declared after the expectations they apply to.
hookUnset:{[ex;k]
  if[not k in key ex; :1b];
  v: ex k;
  ((::) ~ v) or (() ~ v)
 }

fillExpecBA:{[x]
  { [ex]
    if[.tst.hookUnset[ex; `before]; ex[`before]: .tst.currentBefore];
    if[.tst.hookUnset[ex; `after];  ex[`after]:  .tst.currentAfter];
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
  / The fuzz runner reads runs/vars/maxFailRate as top-level keys (all in the
  / base), so override those directly; stash everything under `props too so the
  / column set stays uniform and any other consumer can read it back.
  if[0 < count propsDict;
    known: (key propsDict) inter `runs`vars`maxFailRate;
    if[0 < count known; d: d, known#propsDict];
    d[`props]: propsDict];
  .tst.expecList,: enlist d
 }

perf:{[des;props;code]
  desStr: .tst.toString des;
  d: .tst.internals.perfObj, (`desc`code!(desStr;code));
  / Handle single-key dict (type -20 enumeration) and regular dict (type 99)
  propsDict: $[99h = type props; props;
               (type props) in -20 20h; (enlist key props)!(enlist value props);
               ()!()];
  / The perf runner reads opts from expec`props, so stash props there.
  if[0 < count propsDict; d[`props]: propsDict];
  .tst.expecList,: enlist d
 }

/ Register a skipped expectation under an explicit description.
skipNamed:{[desStr;reason;code]
  d: .tst.internals.testObj, (`desc`code`result`skipReason!(.tst.toString desStr; {}; `skip; reason));
  .tst.expecList,: enlist d
 }

/ Skip a test with a reason
skip:{[reason;code]
  .tst.skipNamed["SKIP: ", .tst.toString reason; reason; code]
 }

/ Mark a test as pending (placeholder)
pending:{[reason]
  desStr: "PENDING: ", .tst.toString reason;
  d: .tst.internals.testObj, (`desc`code`result`skipReason!(desStr; {}; `pending; reason));
  .tst.expecList,: enlist d
 }

/ Conditionally skip based on a condition.
/ The description stays the SAME whether or not it skips. Reporters key test
/ identity on the description, and this test previously reported as "reason"
/ where it ran and "SKIP: reason" where it did not — so every environment-gated
/ test (a platform check, a `which q` probe) looked like a different test
/ between environments, breaking CI history and flaky-test tracking. An
/ explicit skip[] keeps its prefix: it is always skipped, so its name is stable.
skipIf:{[condition;reason;code]
  $[condition; .tst.skipNamed[reason; reason; code]; should[reason; code]]
 }

/ Retry a flaky test up to N times before failing the suite.
retry:{[retries;des;code]
  desStr: .tst.toString des;
  d: .tst.internals.testObj, (`desc`code`retries`namespace!(desStr;code;retries;.tst.currentNs));
  .tst.expecList,: enlist d
 }

/ testOnly: focus the suite on specific tests. When any testOnly test is
/ defined in a suite, only the testOnly tests run for that suite; the
/ remaining tests are reported as skipped (see .tst.applyTestOnlyFocus).
/ The `only:1b flag and `only tag are what the focus pre-step consumes.
testOnly:{[des;code]
  desStr: .tst.toString des;
  tags: (`$"only"), `$ {x where x like "#*"} " " vs desStr;
  .tst.expecList,: enlist .tst.internals.testObj, (`desc`code`tags`namespace`only!(desStr;code;tags;.tst.currentNs;1b))
 }

uiRuntimeNames:`fixture`fixtureAs`mock
uiRuntimeCode: (.tst.fixture;.tst.fixtureAs;.tst.mock)

.tst.desc:{[title;expectations]
 oldBefore: .tst.currentBefore;
 oldAfter: .tst.currentAfter;
 oldBeforeAll: .tst.currentBeforeAll;
 oldAfterAll: .tst.currentAfterAll;
 / A beforeAll/afterAll defined OUTSIDE a describe block is a silent footgun:
 / the reset below wipes it before the block's hooks are captured. If the
 / corresponding flag is already set at entry (i.e. a setter ran before this
 / desc body executes), warn once -- that hook will be ignored. We rely on the
 / flag rather than comparing lambdas (empty lambdas from different sites are
 / not guaranteed ~-equal).
 if[.tst.currentBeforeAllSet;
   -1 "WARNING: beforeAll defined outside a describe block is ignored (call it inside the block)";
 ];
 if[.tst.currentAfterAllSet;
   -1 "WARNING: afterAll defined outside a describe block is ignored (call it inside the block)";
 ];
 .tst.currentBeforeAll: {};
 .tst.currentAfterAll: {};
 .tst.currentBeforeAllSet: 0b;
 .tst.currentAfterAllSet: 0b;
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
  / Attach suite-level hooks unconditionally ({} when never set) so every spec
  / dict carries identical keys (enlist-dict-becomes-table requires this).
  specObj[`beforeAll]: .tst.currentBeforeAll;
  specObj[`afterAll]: .tst.currentAfterAll;
  .tst.currentBefore: oldBefore;
  .tst.currentAfter: oldAfter;
  .tst.currentBeforeAll: oldBeforeAll;
  .tst.currentAfterAll: oldAfterAll;
  / The in-block hooks have been captured into specObj; clear the set-flags so
  / a later top-level desc does not inherit this block's "was set" state.
  .tst.currentBeforeAllSet: 0b;
  .tst.currentAfterAllSet: 0b;
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
beforeAll: .tst.beforeAll; afterAll: .tst.afterAll;
holds: .tst.holds; perf: .tst.perf; alt: .tst.alt;
skip: .tst.skip; pending: .tst.pending; skipIf: .tst.skipIf;
retry: .tst.retry; testOnly: .tst.testOnly;

.tst.uiQExports: `describe`should`it`before`after`beforeAll`afterAll`holds`perf`alt`skip`pending`skipIf`retry`testOnly!(
    .tst.desc;
    .tst.should;
    .tst.should;
    .tst.before;
    .tst.after;
    .tst.beforeAll;
    .tst.afterAll;
    .tst.holds;
    .tst.perf;
    .tst.alt;
    .tst.skip;
    .tst.pending;
    .tst.skipIf;
    .tst.retry;
    .tst.testOnly);

\d .tst
::
