/ lib/mock.q - bounded, transactional mocking and spying
/ Reloading may preserve active lifecycle state and deliberately lowered seams.
.tst.mockReloadBootstrap:{[]
  emptyStore:enlist[`]!enlist(::);
  emptySymbols:`symbol$();
  emptyDict:emptySymbols!();
  hasState:`mockState in key `.tst;
  hasSpy:`spyLog in key `.tst;
  hasSeq:`seqs in key `.tst;
  fresh:not any hasState,hasSpy,hasSeq;
  legacy:0b;
  valid:0b;
  if[hasState and hasSpy and hasSeq;
    state:.tst.mockState;
    spyState:.tst.spyLog;
    seqState:.tst.seqs;
    if[(99h=type state) and (99h=type spyState) and
       (99h=type seqState);
      stateKeys:asc key state;
      spyKeys:asc key spyState;
      legacySchema:
        (stateKeys~asc (enlist `),`store`removeList) and
        (spyKeys~asc (enlist `),`calls`impls);
      if[legacySchema;
        legacy:
          ((::)~state `) and ((::)~spyState `) and
          (state[`store]~emptyStore) and
          (0h=type state`removeList) and (0=count state`removeList) and
          (spyState[`calls]~()!()) and
          (spyState[`impls]~()!()) and
          (seqState~()!())];
      validSchema:
        (stateKeys~asc (enlist `),`store`removeList`draining) and
        (spyKeys~asc
          (enlist `),`calls`impls`callCounts`retainedItems,
            `totalCalls`totalRetainedItems);
      if[validSchema;
        valid:
          ((::)~state `) and ((::)~spyState `) and
          (99h=type state`store) and
          (11h=type state`removeList) and
          (-1h=type state`draining) and
          all 99h=type each
            (spyState`calls;spyState`impls;
             spyState`callCounts;spyState`retainedItems) and
          all (type each
            (spyState`totalCalls;spyState`totalRetainedItems)) in
            -5 -6 -7h]]];
  if[not fresh or legacy or valid;
    '"Mock lifecycle state is invalid during module reload"];
  if[fresh or legacy;
    .tst.mockState:
      ((enlist `),`store`removeList`draining)!
      ((::);emptyStore;emptySymbols;0b);
    .tst.spyLog:
      ((enlist `),`calls`impls`callCounts`retainedItems,
        `totalCalls`totalRetainedItems)!
      ((::);emptyDict;emptyDict;emptyDict;emptyDict;0j;0j);
    .tst.seqs:emptyDict];
  priorSet:`mock in key `.tst;
  priorMock:$[priorSet;.tst.mock;::];
  rootName:` sv `.,`mock;
  rootSeen:@[{[name](1b;get name)};rootName;{[err](0b;::)}];
  qSeen:@[{[](1b;get `.q.mock)};();{[err](0b;::)}];
  exports:@[get;`.tst.qExports;{[err]::}];
  rootOwned:priorSet and first[rootSeen] and priorMock~last rootSeen;
  qOwned:priorSet and first[qSeen] and priorMock~last qSeen;
  exportsOwned:0b;
  if[priorSet and 99h=type exports;
    if[`mock in key exports;
      exportsOwned:priorMock~exports`mock]];
  `priorSet`priorMock`rootName`rootOwned`qOwned`exportsOwned!(
    priorSet;
    priorMock;
    rootName;
    rootOwned;
    qOwned;
    exportsOwned)
 };
.tst.mockReloadState:.Q.trp[
  .tst.mockReloadBootstrap;
  ();
  {[err;backtrace]
    ![`.tst;();0b;enlist `mockReloadBootstrap];
    '"Mock module bootstrap failed: ",err,"\n",.Q.sbt backtrace}];
![`.tst;();0b;enlist `mockReloadBootstrap];
if[not `MOCK_MAX_TARGETS in key `.tst;.tst.MOCK_MAX_TARGETS:1024];
if[not `MOCK_MAX_SPY_CALLS in key `.tst;.tst.MOCK_MAX_SPY_CALLS:10000];
if[not `MOCK_MAX_SPY_ARG_ITEMS in key `.tst;.tst.MOCK_MAX_SPY_ARG_ITEMS:100000];
if[not `MOCK_MAX_SEQUENCE_VALUES in key `.tst;.tst.MOCK_MAX_SEQUENCE_VALUES:10000];if[not `MOCK_MAX_TARGET_CHARS in key `.tst;.tst.MOCK_MAX_TARGET_CHARS:512];
if[not `MOCK_MAX_DIAGNOSTIC_CHARS in key `.tst;.tst.MOCK_MAX_DIAGNOSTIC_CHARS:2048];
if[not `context in key `.tst;.tst.context:`.];
.tst.mockLimit:{[limitName;maximum]raw:get limitName;
  if[not ((type raw) in -5 -6 -7h);:0];if[null raw;:0];
  $[(0w=abs "f"$raw) or 0>raw;0;maximum&"j"$raw]};
.tst.mockTry:{[fn;args]
  .[{[f;a](`ok;enlist f . a)};(fn;args);{[err](`error;enlist err)}]};
/ Fixed callable rank, -1 opaque, -2 genuinely unary/binary ambivalent.
.tst.mockCallableArity:{[fn]@[{[callable]
  current:callable;wrappers:`long$();arity:-1;depth:0;done:0b;
  while[not done;
    if[16<=depth;:-1];t:type current;
    if[(101h=t) and (::)~current;:-1];
    if[100h=t;arity:"j"$sum not null (value current)1;done:1b];
    if[(not done) and t in 101 103h;arity:1;done:1b];
    if[(not done) and 102h=t;arity:-2;done:1b];
    if[(not done) and 104h=t;
      arity:sum {(::)~x} each 1_value current;done:1b];
    if[(not done) and t in 105 106 107 108 109h;
      parts:value current;
      if[105h=t;
        if[(0h<>type parts) or not count parts;:-1];current:last parts];
      if[105h<>t;current:parts];
      wrappers,:enlist "j"$t;depth+:1];
    if[(not done) and t in 110 111h;arity:2;done:1b];
    if[(not done) and 112h=t;
      metadata:value current;
      if[(0h<>type metadata) or not count metadata;:-1];raw:first metadata;
      if[not ((type raw) in -5 -6 -7h);:-1];if[null raw;:-1];
      if[0w=abs "f"$raw;:-1];
      arity:"j"$raw;if[not arity within 0 8;arity:-1];done:1b];
    if[(not done) and not t in 105 106 107 108 109 110 111 112h;done:1b]];
  wrappers:reverse wrappers;i:0;
  while[i<count wrappers;
    wrapper:wrappers i;
    if[wrapper in 107 108;
      arity:$[-2=arity;-2;2<arity;arity;$[arity in 1 2;-2;-1]]];
    if[109=wrapper;arity:$[-2=arity;-2;1=arity;1;$[2=arity;-2;-1]]];
    i+:1];
  arity};fn;{[err] -1}]};
.tst.requireMockArity:{[fn;label]
  arity:.tst.mockCallableArity fn;
  if[-2=arity;'label," uses an ambivalent callable that cannot be mocked exactly"];
  if[0>arity;'label," must be a callable function with determinable arity"];
  if[8<arity;'label," arity must be between 0 and 8"];
  arity};
/ Sole resolver: mode 0 is literal/immutable; mode 1 qualifies and protects.
.tst.mockTarget:{[validPath;under;name;qualify]
  if[-11h<>type name;'"Mock name must be a symbol"];if[null name;'"Mock name must not be null"];
  limit:$[qualify;.tst.mockLimit[`.tst.MOCK_MAX_TARGET_CHARS;512];512];
  text:(),string name;fqn:name;fqnText:text;
  if[not validPath[text;limit];'"Mock name is malformed or exceeds length limit"];
  if[qualify;
    context:@[get;`.tst.context;{[err]`.}];
    if[-11h<>type context;'"Mock context must be a symbol"];
    if[null context;'"Mock context must not be null"];
    contextText:(),string context;
    contextValid:$[
      (1=count contextText) and "."=first contextText;1b;
      (1<count contextText) and ("."=first contextText) and
        ("."<>contextText 1) and validPath[contextText;limit]];
    if[not contextValid;'"Mock context is malformed"];
    absolute:"."=first text;
    if[(not absolute) and context<>`.;
      fqnText:contextText,".",text;
      if[count[fqnText]>limit;'"Qualified mock name exceeds length limit"]];
    guardText:$[
      ".."~2#fqnText;".",2_fqnText;
      "."=first fqnText;fqnText;
      ""];
    if[count guardText;
      if[any under[guardText;] each
          (".q";".Q";".z";".h";".j";".kx";".m");
        '"Cannot mock a KX system namespace member"]];
    if[(not absolute) and context<>`.;fqn:`$fqnText];
    if[guardText in (".q";".Q";".z";".h";".j";".tst";".resq";".utl");
      '"Cannot mock a system namespace"];
    if[any under[guardText;] each
        (".tst.mockState";".tst.spyLog";".tst.seqs";".tst.mockPrimitives");
      '"Cannot mock internal lifecycle state"]];
  if["."<>first fqnText;
    root:value `.;exists:fqn in key root;
    :`name`text`exists`value!(fqn;fqnText;exists;
      enlist $[exists;root fqn;::])];
  captured:.tst.mockTry[get;enlist fqn];
  `name`text`exists`value!(fqn;fqnText;`ok~first captured;
    enlist $[`ok~first captured;first last captured;::])}[
  {[candidate;maximum]
    if[(not count candidate) or maximum<count candidate;:0b];
    if[not all candidate in
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.";:0b];
    if[(1=count candidate) and ("."=first candidate);:0b];
    offset:$[(1<count candidate) and (".."~2#candidate);2;
      "."=first candidate;1;0];
    parts:"." vs offset _ candidate;
    if[(not count parts) or any 0=count each parts;:0b];
    not any (first each parts) in "0123456789"};
  {[candidate;prefix](candidate~prefix) or
    (((count candidate)>count prefix) and
     (prefix~count[prefix]#candidate) and
     ("."=candidate count prefix))};;];
.tst.setMockValue:{[resolver;name;mockValue]
  target:resolver[name;0b];
  $["."=first target`text;(target`name) set mockValue;
    @[`.;target`name;:;mockValue]]}[.tst.mockTarget;;];
.tst.deleteVar:{[resolver;name]
  target:resolver[name;0b];if[not target`exists;:(1b;"")];
  text:target`text;
  if["."<>first text;
    ![`.;();0b;enlist (target`name)];
    :$[(target`name) in key value `.;(0b;"target remained defined");(1b;"")]];
  body:1_text;if["."=first body;body:1_body];
  parts:"." vs body;member:`$last parts;
  if[1=count parts;
    ![`.;();0b;enlist member];
    remains:.tst.mockTry[get;enlist (target`name)];
    :$[`ok~first remains;(0b;"target remained defined");(1b;"")]];
  namespace:`$".","." sv -1_parts;
  namespace set ![value namespace;();0b;enlist member];
  remains:.tst.mockTry[get;enlist (target`name)];
  $[`ok~first remains;(0b;"target remained defined");(1b;"")]}[.tst.mockTarget;];
.tst.mockPrimitives:`set`delete!(.tst.setMockValue;.tst.deleteVar);
.tst.mockTargetMatches:{[resolver;attempt;name;didExist;expected]
  seen:attempt[resolver;(name;0b)];if[not `ok~first seen;:0b];
  actual:first last seen;
  if[not didExist;:not actual`exists];
  if[not actual`exists;:0b];
  expected~first actual`value
 }[.tst.mockTarget;.tst.mockTry;;;];
/ Typed vectors are weighted O(1); only general lists/dicts/tables recurse.
.tst.spyRetainedItems:{[root]
  walk:{[self;node;depth;state]
    if[64<depth;'"Spy arguments exceed retention depth"];state[`nodes]+:1;
    if[100000<state`nodes;'"Spy arguments exceed retention node capacity"];
    t:type node;state[`weight]+:$[
      t<0;1;t within 1 97h;count node;98h=t;0;t in 0 99h;count node;1];
    if[100000<state`weight;'"Spy arguments exceed retention capacity"];
    if[0h=t;
      i:0;while[i<count node;state:self[self;node i;depth+1;state];i+:1]];
    if[t in 98 99h;
      container:$[98h=t;flip node;node];
      state:self[self;key container;depth+1;state];
      state:self[self;value container;depth+1;state]];
    state};
  (walk[walk;root;0;`nodes`weight!0 0])`weight};
.tst.mockLifecycleBad:{[detail]
  '"Mock lifecycle state is invalid: ",(256&count detail)#detail};
.tst.mockPathText:{[name]
  text:(),string name;
  $[".."~2#text;2_text;"."=first text;1_text;text]};
.tst.mockPathsOverlap:{[left;right]
  a:.tst.mockPathText left;b:.tst.mockPathText right;
  if[a~b;:0b];
  ((count[b]>count a) and (a~count[a]#b) and ("."=b count a)) or
    ((count[a]>count b) and (b~count[b]#a) and ("."=a count b))};
.tst.validateMockOwnership:{[resolver;state;guard]
  bad:.tst.mockLifecycleBad;
  if[99h<>type state;bad "state schema"];
  stateKeys:key state;
  if[(11h<>type stateKeys) or
     not ((asc stateKeys)~asc (enlist `),`store`removeList`draining) or
     not (::)~state `;bad "state schema"];
  if[(-1h<>type state`draining) or not (guard~state`draining);
    bad "restore guard"];
  store:state`store;removals:state`removeList;
  if[99h<>type store;bad "original store"];
  storeKeys:key store;
  if[11h<>type storeKeys;bad "original store keys"];
  if[count[storeKeys]<>count distinct storeKeys;bad "duplicate store keys"];
  if[(1<>sum null storeKeys) or not ((::)~store `);
    bad "original store sentinel"];
  originals:storeKeys where not null storeKeys;
  if[11h<>type removals;bad "remove list"];
  if[(any null removals) or count[removals]<>count distinct removals;
    bad "remove list"];
  if[count originals inter removals;bad "store/remove overlap"];
  tracked:originals,removals;
  if[1024<count tracked;bad "tracked target capacity"];
  i:0;
  while[i<count tracked;
    if[any .tst.mockPathsOverlap[tracked i;] each (i+1)_tracked;
      bad "overlapping tracked targets"];
    checked:.[{[r;n]r[n;0b];1b};(resolver;tracked i);{[err]0b}];
    if[not checked;bad "target form"];
    i+:1];
  `store`originals`removals`tracked!(store;originals;removals;tracked)};
.tst.validateSpyLifecycle:{[rankValue;itemCount;spyState;tracked]
  bad:.tst.mockLifecycleBad;
  if[99h<>type spyState;bad "spy schema"];
  outer:key spyState;
  expected:(enlist `),`calls`impls`callCounts`retainedItems,
    `totalCalls`totalRetainedItems;
  if[(11h<>type outer) or not ((asc outer)~asc expected) or
     not (::)~spyState `;bad "spy schema"];
  dictionaries:
    (spyState`calls;spyState`impls;
     spyState`callCounts;spyState`retainedItems);
  if[not all 99h=type each dictionaries;bad "spy dictionaries"];
  dictionaryKeys:key each dictionaries;
  if[not all 11h=type each dictionaryKeys;bad "spy keys"];
  if[any {count[x]<>count distinct x} each dictionaryKeys;
    bad "duplicate spy keys"];
  if[any {any null x} each dictionaryKeys;bad "null spy keys"];
  if[any 1024<count each dictionaryKeys;bad "spy capacity"];
  callKeys:first dictionaryKeys;
  if[not all {[expected;actual](asc expected)~asc actual}[callKeys;]
      each 1_dictionaryKeys;
    bad "spy key coherence"];
  if[count callKeys except tracked;bad "untracked spy state"];
  logs:value spyState`calls;
  counts:value spyState`callCounts;
  retained:value spyState`retainedItems;
  if[count logs;
    if[any not (type each logs) within 0 97h;bad "spy log shape"];
    if[not (count each logs)~"j"$counts;bad "spy call counters"];
    i:0;calculated:`long$();
    while[i<count logs;
      history:logs i;
      if[any not (type each history) within 0 98h;bad "spy argument shape"];
      calculated,:sum 0,itemCount each history;
      i+:1];
    if[not calculated~"j"$retained;bad "spy retention counters"]];
  if[not all {(type x) in -5 -6 -7h} each
      (spyState`totalCalls;spyState`totalRetainedItems);
    bad "spy aggregate counters"];
  if[(null spyState`totalCalls) or (null spyState`totalRetainedItems) or
     (0>spyState`totalCalls) or (0>spyState`totalRetainedItems);
    bad "spy aggregate counters"];
  if[("j"$spyState`totalCalls)<>sum "j"$counts;
    bad "spy total call counter"];
  if[("j"$spyState`totalRetainedItems)<>sum "j"$retained;
    bad "spy total retention counter"];
  if[10000<spyState`totalCalls;bad "spy call capacity"];
  if[100000<spyState`totalRetainedItems;bad "spy argument capacity"];
  implementations:value spyState`impls;
  if[count implementations;
    arities:rankValue each implementations;
    if[any (0>arities) or 8<arities;bad "spy implementation rank"]];
  ::};
.tst.validateSequenceLifecycle:{[seqState;tracked]
  bad:.tst.mockLifecycleBad;
  if[99h<>type seqState;bad "sequence schema"];
  seqKeys:key seqState;
  if[11h<>type seqKeys;bad "sequence keys"];
  if[(any null seqKeys) or count[seqKeys]<>count distinct seqKeys;
    bad "sequence keys"];
  if[1024<count seqKeys;bad "sequence capacity"];
  if[count seqKeys except tracked;bad "untracked sequence state"];
  sequences:value seqState;
  if[count sequences;
    if[any not (type each sequences) within 0 98h;bad "sequence shape"];
    if[any 10000<count each sequences;bad "sequence capacity"]];
  ::};
.tst.validateMockState:{[rankValue;resolver;itemCount;guard]
  ownership:.tst.validateMockOwnership[resolver;.tst.mockState;guard];
  tracked:ownership`tracked;
  .tst.validateSpyLifecycle[rankValue;itemCount;.tst.spyLog;tracked];
  .tst.validateSequenceLifecycle[.tst.seqs;tracked];
  ownership}[
    .tst.mockCallableArity;.tst.mockTarget;.tst.spyRetainedItems;];
.tst.mockRegistryNames:{[](.tst.validateMockState .tst.mockState.draining)`tracked};
.tst.ensureMockRegistrationAllowed:{[]
  .tst.validateMockState .tst.mockState.draining;
  if[.tst.mockState.draining;'"Mock registration is unavailable during restore"];
  ::};
.tst.ensureMockTargetAvailable:{[target]
  tracked:(.tst.validateMockState .tst.mockState.draining)`tracked;
  name:target`name;
  others:tracked except enlist name;
  if[any .tst.mockPathsOverlap[name;] each others;
    '"Mock target overlaps existing lifecycle ownership: ",target`text];
  ::};
.tst.installResolvedMock:{[setValue;deleteValue;matches;attempt;validator;target;newValue]
  .tst.ensureMockTargetAvailable target;
  name:target`name;storeKeys:key .tst.mockState.store;
  tracked:(storeKeys where not null storeKeys),.tst.mockState.removeList;
  newlyTracked:not name in tracked;
  if[newlyTracked;
    if[count[tracked]>=.tst.mockLimit[`.tst.MOCK_MAX_TARGETS;1024];
      '"Mock target capacity exceeded"]];
  outcome:attempt[setValue;(name;newValue)];
  installed:`ok~first outcome;
  if[installed;installed:matches[name;1b;newValue]];
  if[installed;
    if[newlyTracked;
      $[target`exists;.tst.mockState.store[name]:first target`value;
        .tst.mockState.removeList,:enlist name]];
    published:attempt[validator;enlist 0b];
    if[`ok~first published;:newValue];
    outcome:(`error;last published)];
  installError:$[`error~first outcome;first last outcome;
    "mock target postcondition failed"];
  if[10h<>type installError;installError:"mock operation failed"];
  installError:(.tst.mockLimit[`.tst.MOCK_MAX_DIAGNOSTIC_CHARS;2048]&
    count installError)#installError;
  rollback:$[target`exists;
    attempt[setValue;(name;first target`value)];
    attempt[deleteValue;enlist name]];
  rollbackOk:`ok~first rollback;
  if[rollbackOk;rollbackOk:matches[name;target`exists;
    $[target`exists;first target`value;::]]];
  if[rollbackOk and newlyTracked;
    $[target`exists;
      .tst.mockState.store:![.tst.mockState.store;();0b;enlist name];
      .tst.mockState.removeList:.tst.mockState.removeList except enlist name]];
  if[not rollbackOk;
    '"Mock installation failed and rollback could not complete: ",installError];
  '"Mock installation failed: ",installError
 }[.tst.mockPrimitives`set;.tst.mockPrimitives`delete;
   .tst.mockTargetMatches;.tst.mockTry;.tst.validateMockState;;];
.tst.mock:{[name;newValue].tst.ensureMockRegistrationAllowed[];
  .tst.installResolvedMock[.tst.mockTarget[name;1b];newValue]};
.tst.mockFrameworkQExport:{[name;newValue]
  .tst.ensureMockRegistrationAllowed[];
  target:.tst.mockTarget[name;0b];
  text:target`text;
  if[(not text like ".q.*") or 3>=count text;
    '"Framework q export target is invalid"];
  exports:@[get;`.tst.qExports;{[err]::}];
  if[99h<>type exports;'"Framework q exports are unavailable"];
  memberText:3_text;
  if[not any memberText~/:string each key exports;
    '"Framework q export target is not registered"];
  .tst.installResolvedMock[target;newValue]};
.tst.partialMock:{[name;partialValue]
  .tst.ensureMockRegistrationAllowed[];target:.tst.mockTarget[name;1b];
  if[not target`exists;'"partialMock target not defined: ",target`text];
  original:first target`value;
  if[99h<>type original;'"partialMock only supports dictionaries"];
  if[99h<>type partialValue;'"Partial value must be a dictionary"];
  .tst.installResolvedMock[target;original,partialValue]};
/ Static packers preserve exact ranks without source construction/evaluation.
.tst.mockArgPacks:enlist[1]!enlist {[a0]enlist a0};
.tst.mockArgPacks[2]:{[a0;a1](a0;a1)};.tst.mockArgPacks[3]:{[a0;a1;a2](a0;a1;a2)};
.tst.mockArgPacks[4]:{[a0;a1;a2;a3](a0;a1;a2;a3)};.tst.mockArgPacks[5]:{[a0;a1;a2;a3;a4](a0;a1;a2;a3;a4)};
.tst.mockArgPacks[6]:{[a0;a1;a2;a3;a4;a5](a0;a1;a2;a3;a4;a5)};.tst.mockArgPacks[7]:{[a0;a1;a2;a3;a4;a5;a6](a0;a1;a2;a3;a4;a5;a6)};
.tst.mockArgPacks[8]:{[a0;a1;a2;a3;a4;a5;a6;a7](a0;a1;a2;a3;a4;a5;a6;a7)};

.tst.mockDispatchWrapper:{[dispatcher;zeroDispatcher;name;arity]
  if[0=arity;:('[zeroDispatcher[name;];{[]::}])];
  if[arity in key .tst.mockArgPacks;
    :('[dispatcher[name;];.tst.mockArgPacks arity])];
  '"Mock callable arity must be between 0 and 8"};
.tst.rollbackMockPublication:{[target;previousState;previousSpy;previousSeq;err]
  .tst.spyLog:previousSpy;
  .tst.seqs:previousSeq;
  rollback:.tst.mockTry[
    .tst.mockPrimitives`set;
    (target`name;first target`value)];
  rollbackOk:`ok~first rollback;
  if[rollbackOk;
    rollbackOk:.tst.mockTargetMatches[
      target`name;
      1b;
      first target`value]];
  if[rollbackOk;.tst.mockState:previousState];
  if[not rollbackOk;
    '"Mock state publication failed and target rollback could not complete"];
  detail:$[10h=type err;err;"mock state publication failed"];
  '"Mock state publication failed: ",
    (.tst.mockLimit[`.tst.MOCK_MAX_DIAGNOSTIC_CHARS;2048]&
      count detail)#detail};
.tst.spy:{[name;impl]
  .tst.ensureMockRegistrationAllowed[];target:.tst.mockTarget[name;1b];
  .tst.ensureMockTargetAvailable target;
  if[not target`exists;'"Spy on undefined function: ",target`text];
  original:first target`value;arity:.tst.requireMockArity[original;"Spy target"];
  targetName:target`name;keepOriginal:(::)~impl;
  if[not keepOriginal;
    implArity:.tst.requireMockArity[impl;"Spy implementation"];
    if[implArity<>arity;'"Spy implementation arity must match target"]];
  if[(not targetName in key .tst.spyLog.impls) and
     count[.tst.spyLog.impls]>=.tst.mockLimit[`.tst.MOCK_MAX_TARGETS;1024];
    '"Spy implementation capacity exceeded"];
  previousState:.tst.mockState;
  previousSpy:.tst.spyLog;
  previousSeq:.tst.seqs;
  implementation:$[
    keepOriginal;
    $[targetName in key .tst.spyLog.impls;
      .tst.spyLog.impls targetName;
      original];
    impl];
  wrapper:.tst.mockDispatchWrapper[
    {[n;a].tst.spyLogCallback[n;a];(.tst.spyLog.impls n). a};
    {[n;ignored].tst.spyLogCallback[n;()];(.tst.spyLog.impls n)[]};
    targetName;arity];
  outcome:.tst.mockTry[.tst.installResolvedMock;(target;wrapper)];
  if[`error~first outcome;'first last outcome];
  publication:.tst.mockTry[
    {[targetName;implementation]
      existed:targetName in key .tst.spyLog.calls;
      priorCalls:$[existed;.tst.spyLog.callCounts targetName;0];
      priorRetained:$[existed;.tst.spyLog.retainedItems targetName;0];
      .tst.spyLog.impls[targetName]:implementation;
      .tst.spyLog.calls[targetName]:();
      .tst.spyLog.callCounts[targetName]:0;
      .tst.spyLog.retainedItems[targetName]:0;
      .tst.spyLog.totalCalls-:priorCalls;
      .tst.spyLog.totalRetainedItems-:priorRetained;
      .tst.validateMockState 0b;
      ::};
    (targetName;implementation)];
  if[`ok~first publication;:first last outcome];
  .tst.rollbackMockPublication[
    target;
    previousState;
    previousSpy;
    previousSeq;
    first last publication]};
.tst.validateSpyAppend:{[name;args]
  expected:(enlist `),`calls`impls`callCounts`retainedItems,
    `totalCalls`totalRetainedItems;
  if[(99h<>type .tst.spyLog) or
     not ((asc key .tst.spyLog)~asc expected) or
     not (::)~.tst.spyLog `;
    '"Spy call state is invalid"];
  dictionaries:
    (.tst.spyLog.calls;.tst.spyLog.impls;
     .tst.spyLog.callCounts;.tst.spyLog.retainedItems);
  if[not all 99h=type each dictionaries;'"Spy call state is invalid"];
  dictionaryKeys:key each dictionaries;
  if[not all {[expected;actual](asc expected)~asc actual}[
      first dictionaryKeys;] each 1_dictionaryKeys;
    '"Spy call state is invalid"];
  if[not name in first dictionaryKeys;'"Spy call state is missing"];
  countValue:.tst.spyLog.callCounts name;
  retainedValue:.tst.spyLog.retainedItems name;
  aggregates:
    (countValue;retainedValue;
     .tst.spyLog.totalCalls;.tst.spyLog.totalRetainedItems);
  if[not all {(type x) in -5 -6 -7h} each aggregates;
    '"Spy call counters are invalid"];
  if[any null aggregates;'"Spy call counters are invalid"];
  if[any 0>aggregates;'"Spy call counters are invalid"];
  history:.tst.spyLog.calls name;
  if[not type[history] within 0 97h;'"Spy call history is invalid"];
  if[count[history]<>"j"$countValue;'"Spy call counters are invalid"];
  if[not .tst.spyLog.totalCalls~sum value .tst.spyLog.callCounts;
    '"Spy call counters are invalid"];
  if[not .tst.spyLog.totalRetainedItems~
      sum value .tst.spyLog.retainedItems;
    '"Spy retention counters are invalid"];
  if[0>.tst.mockCallableArity .tst.spyLog.impls name;
    '"Spy implementation is invalid"];
  payload:.tst.spyRetainedItems args;
  if[.tst.spyLog.totalCalls>=
      .tst.mockLimit[`.tst.MOCK_MAX_SPY_CALLS;10000];
    '"Spy call log capacity exceeded"];
  if[(payload+.tst.spyLog.totalRetainedItems)>
      .tst.mockLimit[`.tst.MOCK_MAX_SPY_ARG_ITEMS;100000];
    '"Spy arguments exceed retention capacity"];
  payload};
.tst.spyLogCallback:{[name;args]
  if[.tst.mockState.draining;'"Spy logging is unavailable during restore"];
  payload:.tst.validateSpyAppend[name;args];
  .tst.spyLog.calls[name],:enlist args;
  .tst.spyLog.callCounts[name]+:1;
  .tst.spyLog.retainedItems[name]+:payload;
  .tst.spyLog.totalCalls+:1;
  .tst.spyLog.totalRetainedItems+:payload;
  ::};
.tst.calledWith:{[name;args]
  .tst.validateMockState .tst.mockState.draining;
  targetName:(.tst.mockTarget[name;1b])`name;
  if[not targetName in key .tst.spyLog.calls;:0b];
  args in .tst.spyLog.calls targetName};
.tst.callCount:{[name]
  .tst.validateMockState .tst.mockState.draining;
  targetName:(.tst.mockTarget[name;1b])`name;
  if[not targetName in key .tst.spyLog.calls;:0];
  .tst.spyLog.callCounts targetName};
.tst.lastCall:{[name]
  .tst.validateMockState .tst.mockState.draining;
  targetName:(.tst.mockTarget[name;1b])`name;
  if[not targetName in key .tst.spyLog.calls;:(::)];
  calls:.tst.spyLog.calls targetName;if[not count calls;:(::)];last calls};
.tst.clearSpyLogs:{[]
  .tst.validateMockState .tst.mockState.draining;
  names:key .tst.spyLog.calls;
  .tst.spyLog.calls:names!(count names)#enlist ();
  .tst.spyLog.callCounts:names!count[names]#0;
  .tst.spyLog.retainedItems:names!count[names]#0;
  .tst.spyLog.totalCalls:0;
  .tst.spyLog.totalRetainedItems:0;
  ::};
.tst.mockSequence:{[name;values]
  .tst.ensureMockRegistrationAllowed[];target:.tst.mockTarget[name;1b];
  .tst.ensureMockTargetAvailable target;
  if[not target`exists;'"mockSequence target not defined: ",target`text];
  if[not type[values] within 0 98h;'"Mock sequence values must be a list"];
  if[count[values]>.tst.mockLimit[`.tst.MOCK_MAX_SEQUENCE_VALUES;10000];
    '"Mock sequence value capacity exceeded"];
  arity:.tst.requireMockArity[first target`value;"Mock sequence target"];
  targetName:target`name;
  if[(not targetName in key .tst.seqs) and
     count[.tst.seqs]>=.tst.mockLimit[`.tst.MOCK_MAX_TARGETS;1024];
    '"Mock sequence capacity exceeded"];
  previousState:.tst.mockState;
  previousSpy:.tst.spyLog;
  previousSeq:.tst.seqs;
  wrapper:.tst.mockDispatchWrapper[
    {[n;a].tst.nextSeq n};{[n;ignored].tst.nextSeq n};targetName;arity];
  outcome:.tst.mockTry[.tst.installResolvedMock;(target;wrapper)];
  if[`error~first outcome;'first last outcome];
  publication:.tst.mockTry[
    {[targetName;values]
      .tst.seqs[targetName]:values;
      .tst.validateMockState 0b;
      ::};
    (targetName;values)];
  if[`ok~first publication;:first last outcome];
  .tst.rollbackMockPublication[
    target;
    previousState;
    previousSpy;
    previousSeq;
    first last publication]};
.tst.nextSeq:{[name]
  .tst.validateMockState .tst.mockState.draining;
  if[not name in key .tst.seqs;'"Mock sequence state is missing"];
  values:.tst.seqs name;if[not count values;'"Mock sequence exhausted"];
  .tst.seqs[name]:1_values;first values};
/ Validate before guard mutation; attempt all targets and retain failed work.
.tst.restoreWork:{[setValue;deleteValue;validator;rankValue;matches;attempt;drop;tag]
  if[not `mockRestoreV1~tag;'"Mock restore capsule is invalid"];
  if[2<>rankValue setValue;'"Mock restore setter arity is invalid"];
  if[1<>rankValue deleteValue;'"Mock restore deleter arity is invalid"];
  if[(-1h<>type .tst.mockState.draining) or .tst.mockState.draining;
    '"Mock restore guard is invalid or already active"];
  snapshot:validator 0b;store:snapshot`store;
  drain:{[setValue;deleteValue;matches;attempt;drop;snapshot]
    store:snapshot`store;originals:snapshot`originals;
    removals:snapshot`removals;failures:0;i:0;
    commit:{[drop;name;original]
      primary:$[original;drop[.tst.mockState.store;name];
        .tst.mockState.removeList except enlist name];
      calls:drop[.tst.spyLog.calls;name];impls:drop[.tst.spyLog.impls;name];
      callValue:$[name in key .tst.spyLog.callCounts;
        .tst.spyLog.callCounts name;0];
      retainedValue:$[name in key .tst.spyLog.retainedItems;
        .tst.spyLog.retainedItems name;0];
      callCounts:drop[.tst.spyLog.callCounts;name];
      retainedItems:drop[.tst.spyLog.retainedItems;name];
      seqs:drop[.tst.seqs;name];
      $[original;.tst.mockState.store:primary;
        .tst.mockState.removeList:primary];
      .tst.spyLog.calls:calls;.tst.spyLog.impls:impls;
      .tst.spyLog.callCounts:callCounts;
      .tst.spyLog.retainedItems:retainedItems;
      .tst.spyLog.totalCalls-:callValue;
      .tst.spyLog.totalRetainedItems-:retainedValue;
      .tst.seqs:seqs;1b};
    while[i<count originals;
      name:originals i;result:attempt[setValue;(name;store name)];
      restored:`ok~first result;
      if[restored;restored:matches[name;1b;store name]];
      if[restored;
        committed:attempt[commit;(drop;name;1b)];
        restored:`ok~first committed];
      if[not restored;failures+:1];i+:1];
    i:0;
    while[i<count removals;
      name:removals i;result:attempt[deleteValue;enlist name];
      deleted:`ok~first result;
      if[deleted;deleted:matches[name;0b;::]];
      if[deleted;
        committed:attempt[commit;(drop;name;0b)];
        deleted:`ok~first committed];
      if[not deleted;failures+:1];i+:1];
    failures};
  .tst.mockState.draining:1b;
  drained:attempt[drain;(setValue;deleteValue;matches;attempt;drop;snapshot)];
  .tst.mockState.draining:0b;
  if[`error~first drained;'first last drained];
  failures:first last drained;
  if[failures;'"Mock restore failed for ",string[failures]," target(s)"];
  ::};
.tst.makeMockRestoreCapsuleWith:{[setValue;deleteValue]
  rankValue:.tst.mockCallableArity;
  if[2<>rankValue setValue;'"Mock restore setter arity is invalid"];
  if[1<>rankValue deleteValue;'"Mock restore deleter arity is invalid"];
  validator:.tst.validateMockState;validator 0b;
  work:.tst.restoreWork;attempt:.tst.mockTry;matches:.tst.mockTargetMatches;
  drop:{[dictionary;name]![dictionary;();0b;enlist name]};
  ('[work[setValue;deleteValue;validator;rankValue;matches;attempt;drop;];
    {[]`mockRestoreV1}])};
.tst.makeMockRestoreCapsule:{[]
  .tst.makeMockRestoreCapsuleWith[
    .tst.mockPrimitives`set;
    .tst.mockPrimitives`delete]};
.tst.restore:{[]capsule:.tst.makeMockRestoreCapsule[];capsule[]};

.tst.publishMockReloadAliases:{[reloadState]
  if[not reloadState`priorSet;:()];
  priorMock:reloadState`priorMock;
  rootName:reloadState`rootName;
  rootOwned:reloadState`rootOwned;
  qOwned:reloadState`qOwned;
  exportsOwned:reloadState`exportsOwned;
  if[rootOwned;
    current:@[get;rootName;{[err]::}];
    if[not current~priorMock;'"Root mock alias changed during reload"]];
  if[qOwned;
    current:@[get;`.q.mock;{[err]::}];
    if[not current~priorMock;'".q mock alias changed during reload"]];
  if[exportsOwned;
    exports:@[get;`.tst.qExports;{[err]::}];
    if[99h<>type exports;
      '"qExports mock alias changed during reload"];
    if[not `mock in key exports;
      '"qExports mock alias changed during reload"];
    if[not exports[`mock]~priorMock;
      '"qExports mock alias changed during reload"]];
  outcome:.tst.mockTry[
    {[state;newMock]
      if[state`rootOwned;(state`rootName) set newMock];
      if[state`qOwned;`.q.mock set newMock];
      if[state`exportsOwned;.tst.qExports[`mock]:newMock];
      ::};
    (reloadState;.tst.mock)];
  if[`ok~first outcome;:()];
  if[rootOwned;rootName set priorMock];
  if[qOwned;`.q.mock set priorMock];
  if[exportsOwned;.tst.qExports[`mock]:priorMock];
  '"Mock alias refresh failed: ",first last outcome};

.tst.validateMockState 0b;
.tst.publishMockReloadAliases .tst.mockReloadState;
![`.tst;();0b;`mockReloadState`publishMockReloadAliases];
