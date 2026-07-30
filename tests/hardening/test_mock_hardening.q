/ Focused regressions for bounded, transactional mock lifecycle behavior.

.tst.mockHardening.failSet:{[name;mockValue]
  .tst.mockHardening.setAttempts:
    .tst.mockHardening.setAttempts,enlist name;
  if[name~`.tst.mockHardening.restoreA;'"injected set failure"];
  .tst.mockHardening.savedSet[name;mockValue]
 };

.tst.mockHardening.failDelete:{[name]
  .tst.mockHardening.deleteAttempts:
    .tst.mockHardening.deleteAttempts,enlist name;
  if[name~`.tst.mockHardening.restoreC;:(0b;"injected delete failure")];
  .tst.mockHardening.savedDelete name
 };

.tst.mockHardening.registerDuringSet:{[name;mockValue]
  if[name~`.tst.mockHardening.drainTarget;
    .tst.mock[`.tst.mockHardening.drainRegistration;99]];
  .tst.mockHardening.savedSet[name;mockValue]
 };

.tst.mockHardening.invokeCapsule:{[capsule]capsule[]};
.tst.mockHardening.poisonRejected:{[capsule;target;targetValue;state;spy;seq]
  outcome:.tst.mockTry[capsule;()];
  (first outcome) musteq `error;
  .tst.mockState mustmatch state;
  .tst.spyLog mustmatch spy;
  .tst.seqs mustmatch seq;
  (get target) mustmatch targetValue;
 };
.tst.mockHardening.captureReloadState:{[]
  aliases:.tst.captureNamedLifecycle
    `mock`.q.mock;
  `mockState`spyLog`seqs`aliases`qExports!(
    .tst.mockState;
    .tst.spyLog;
    .tst.seqs;
    aliases;
    .tst.qExports)
 };
.tst.mockHardening.restoreReloadState:{[]
  if[not `mockHardeningReloadRecovery in key `.tst.testState;:()];
  saved:.tst.testState.mockHardeningReloadRecovery;
  .tst.mockState:saved`mockState;
  .tst.spyLog:saved`spyLog;
  .tst.seqs:saved`seqs;
  .tst.qExports:saved`qExports;
  .tst.restoreNamedLifecycle saved`aliases;
  ![`.tst.testState;();0b;enlist `mockHardeningReloadRecovery];
  ::
 };

.tst.desc["Mock hardening: resolution and bounds"]{
  should["restore an original value equal to the former dne sentinel"]{
    .tst.mockHardening.dneValue:`dne;
    .tst.mock[`.tst.mockHardening.dneValue;42];
    .tst.restore[];
    .tst.mockHardening.dneValue musteq `dne;
  };

  should["use one context-qualified FQN for partial mocks spies and sequences"]{
    .mockHardeningContext.config:`a`b!1 2;
    .mockHardeningContext.fn:{[x]2*x};
    .mockHardeningContext.seq:{[x]x};
    .tst.context:`.mockHardeningContext;
    .tst.partialMock[`config;enlist[`b]!enlist 9];
    .tst.spy[`fn;::];
    .tst.mockSequence[`seq;10 20];
    .mockHardeningContext.fn 3;
    .mockHardeningContext.seq 0;
    .mockHardeningContext.config[`b] musteq 9;
    .tst.callCount[`fn] musteq 1;
    `.mockHardeningContext.fn mustin key .tst.spyLog.calls;
    `.mockHardeningContext.seq mustin key .tst.seqs;
    `.mockHardeningContext.config mustin .tst.mockRegistryNames[];
  };

  should["reject wrong null malformed and overlong names before registration"]{
    mustthrow["*symbol*";{.tst.mock["not-a-symbol";1]}];
    mustthrow["*null*";{.tst.mock[`;1]}];
    mustthrow["*malformed*";{.tst.mock[`$"bad name";1]}];
    hugeName:`$600#"a";
    .tst.mockHardening.hugeName:hugeName;
    mustthrow["*length*";{
      .tst.mock[.tst.mockHardening.hugeName;1]
    }];
    .tst.asserts[`must][
      not (hugeName in .tst.mockRegistryNames[]);
      "overlong target entered mock state"];
  };

  should["validate context before qualification"]{
    saved:.tst.context;
    .tst.registerCleanup[{[context].tst.context:context};enlist saved];
    .tst.context:42;
    mustthrow["*context must be a symbol*";{.tst.mock[`x;1]}];
  };

  should["protect lifecycle state and true system subtrees before registration"]{
    beforeNames:.tst.mockRegistryNames[];
    beforeStoreKeys:key .tst.mockState.store;
    beforeRemove:.tst.mockState.removeList;
    beforeSpyKeys:key .tst.spyLog.calls;
    beforeSeqKeys:key .tst.seqs;
    mustthrow["*lifecycle state*";{.tst.mock[`.tst.mockState;1]}];
    mustthrow["*lifecycle state*";{.tst.mock[`.tst.mockState.store;1]}];
    mustthrow["*lifecycle state*";{.tst.mock[`.tst.spyLog;1]}];
    mustthrow["*lifecycle state*";{.tst.mock[`.tst.spyLog.calls;1]}];
    mustthrow["*lifecycle state*";{.tst.mock[`.tst.spyLog.impls;1]}];
    mustthrow["*lifecycle state*";{.tst.mock[`.tst.seqs;1]}];
    mustthrow["*lifecycle state*";{.tst.mock[`..tst.mockState;1]}];
    mustthrow["*system namespace member*";{.tst.mock[`.z.ts;1]}];
    mustthrow["*system namespace member*";{.tst.mock[`.Q.s;1]}];
    mustthrow["*system namespace member*";{
      .tst.mock[`..q.mockHardeningReserved;1]
    }];
    .tst.mockRegistryNames[] mustmatch beforeNames;
    key[.tst.mockState.store] mustmatch beforeStoreKeys;
    .tst.mockState.removeList mustmatch beforeRemove;
    key[.tst.spyLog.calls] mustmatch beforeSpyKeys;
    key[.tst.seqs] mustmatch beforeSeqKeys;
    .zebra.mockAllowed:0;
    .tst.mock[`.zebra.mockAllowed;1];
    .zebra.mockAllowed musteq 1;
  };

  should["reject KX namespace subtrees before relative qualification interns them"]{
    savedContext:.tst.context;
    .tst.registerCleanup[
      {[context].tst.context:context};
      enlist savedContext];
    reserved:
      `$(".m.mockHardeningReserved";".q.mockHardeningReserved";
        ".Q.mockHardeningReserved";".z.mockHardeningReserved";
        ".h.mockHardeningReserved";".j.mockHardeningReserved";
        ".kx.mockHardeningReserved");
    outcomes:{.tst.mockTry[.tst.mock;(x;1)]} each reserved;
    (first each outcomes) musteq count[reserved]#`error;
    beforeSymbols:.Q.w[]`syms;
    .tst.context:`.q;
    relativeOutcome:.tst.mockTry[
      .tst.mock;
      (`mockHardeningRelativeInternProbe;1)];
    afterSymbols:.Q.w[]`syms;
    (first relativeOutcome) musteq `error;
    afterSymbols musteq beforeSymbols;
    .zebra.mockHardeningReserved:0;
    .tst.mock[`.zebra.mockHardeningReserved;1];
    .zebra.mockHardeningReserved musteq 1;
  };

  should["clamp raised seams and fail closed on poisoned seams"]{
    `.tst.MOCK_MAX_TARGETS mock 1000000000;
    .tst.mockLimit[`.tst.MOCK_MAX_TARGETS;1024] musteq 1024;
    `.tst.MOCK_MAX_TARGETS mock "poison";
    .tst.mockLimit[`.tst.MOCK_MAX_TARGETS;1024] musteq 0;
    mustthrow["*capacity*";{
      .tst.mock[`.tst.mockHardening.poisonedTarget;1]
    }];
  };

  should["enforce target and sequence state caps before growth"]{
    `.tst.MOCK_MAX_SEQUENCE_VALUES mock 2;
    `.tst.MOCK_MAX_TARGETS mock 0;
    mustthrow["*capacity*";{
      .tst.mock[`.tst.mockHardening.cappedTarget;1]
    }];
    .tst.mockHardening.sequenceCapFn:{[x]x};
    mustthrow["*capacity*";{
      .tst.mockSequence[`.tst.mockHardening.sequenceCapFn;1 2 3]
    }];
    .tst.asserts[`must][
      not `.tst.mockHardening.sequenceCapFn in key .tst.seqs;
      "oversized sequence entered state"];
  };

  should["require a callable sequence target"]{
    .tst.mockHardening.notCallable:42;
    mustthrow["*callable*";{
      .tst.mockSequence[`.tst.mockHardening.notCallable;1 2]
    }];
  };

  should["preserve zero and eight argument sequence arity"]{
    .tst.mockHardening.seq0:{[]0};
    .tst.mockHardening.seq8:{[a;b;c;d;e;f;g;h]a+b+c+d+e+f+g+h};
    .tst.mockHardening.seqTable:{[x]x};
    (.tst.mockCallableArity .tst.mockHardening.seq0) musteq 0;
    .tst.mockSequence[`.tst.mockHardening.seq0;enlist 11];
    .tst.mockSequence[`.tst.mockHardening.seq8;enlist 22];
    .tst.mockSequence[
      `.tst.mockHardening.seqTable;
      ([] avg_us:0 1f)];
    .tst.mockHardening.seq0[] musteq 11;
    .tst.mockHardening.seq8[0;1;2;3;4;5;6;7] musteq 22;
    .tst.mockHardening.seqTable[0] mustmatch
      (enlist `avg_us)!enlist 0f;
    .tst.mockHardening.seqTable[0] mustmatch
      (enlist `avg_us)!enlist 1f;
    mustthrow["*exhausted*";{.tst.mockHardening.seq0[]}];
  };
};

.tst.desc["Mock hardening: transactional state and restore"]{
  should["reject ancestor and descendant ownership in either order without mutation"]{
    parent:`.tst.mockHardening.overlapParent;
    child:`.tst.mockHardening.overlapParent.child;
    child set 1;
    original:get parent;
    parentReplacement:original;
    parentReplacement[`child]:20;
    .tst.mock[parent;parentReplacement];
    beforeState:.tst.mockState;
    beforeSpy:.tst.spyLog;
    beforeSeq:.tst.seqs;
    outcome:.tst.mockTry[.tst.mock;(child;30)];
    (first outcome) musteq `error;
    .tst.asserts[`must][
      (first last outcome) like "*overlap*";
      "descendant rejection did not identify overlapping ownership"];
    .tst.mockState mustmatch beforeState;
    .tst.spyLog mustmatch beforeSpy;
    .tst.seqs mustmatch beforeSeq;
    (get parent) mustmatch parentReplacement;
    .tst.restore[];
    (get parent) mustmatch original;

    child set 1;
    original:get parent;
    .tst.mock[child;10];
    beforeState:.tst.mockState;
    beforeSpy:.tst.spyLog;
    beforeSeq:.tst.seqs;
    childReplacement:get child;
    outcome:.tst.mockTry[
      .tst.mock;
      (parent;enlist[`child]!enlist 40)];
    (first outcome) musteq `error;
    .tst.asserts[`must][
      (first last outcome) like "*overlap*";
      "ancestor rejection did not identify overlapping ownership"];
    .tst.mockState mustmatch beforeState;
    .tst.spyLog mustmatch beforeSpy;
    .tst.seqs mustmatch beforeSeq;
    (get child) musteq childReplacement;
    .tst.restore[];
    (get parent) mustmatch original;
  };

  should["allow repeated ownership of the exact same target"]{
    target:`.tst.mockHardening.sameTarget;
    target set 1;
    .tst.mock[target;2];
    ownership:.tst.mockRegistryNames[];
    .tst.mock[target;3];
    (get target) musteq 3;
    .tst.mockRegistryNames[] mustmatch ownership;
    .tst.restore[];
    (get target) musteq 1;
  };

  should["use captured primitives and publish only observed installations"]{
    .tst.mockHardening.installTarget:7;
    savedSet:.tst.setMockValue;
    .tst.registerCleanup[
      {[fn].tst.setMockValue:fn};
      enlist savedSet];
    .tst.setMockValue:{[name;mockValue]::};
    .tst.mock[`.tst.mockHardening.installTarget;9];
    .tst.mockHardening.installTarget musteq 9;
    `.tst.mockHardening.installTarget mustin .tst.mockRegistryNames[];
    .tst.deleteVar `.tst.mockHardening.installNewTarget;
    .tst.mock[`.tst.mockHardening.installNewTarget;11];
    .tst.mockHardening.installNewTarget musteq 11;
    `.tst.mockHardening.installNewTarget mustin .tst.mockRegistryNames[];
    .tst.setMockValue:savedSet;
    .tst.restore[];
    .tst.mockHardening.installTarget musteq 7;
    mustthrow["*installNewTarget*";{
      get `.tst.mockHardening.installNewTarget
    }];
  };

  should["install spies through captured primitives despite a throwing public setter"]{
    .tst.mockHardening.spyInstall:{[x]x};
    savedSet:.tst.setMockValue;
    .tst.registerCleanup[
      {[fn].tst.setMockValue:fn};
      enlist savedSet];
    .tst.setMockValue:{[name;mockValue]'"injected spy install failure"};
    .tst.spy[`.tst.mockHardening.spyInstall;::];
    .tst.mockHardening.spyInstall 4 musteq 4;
    .tst.callCount[`.tst.mockHardening.spyInstall] musteq 1;
    `.tst.mockHardening.spyInstall mustin key .tst.spyLog.calls;
    `.tst.mockHardening.spyInstall mustin key .tst.spyLog.impls;
    .tst.setMockValue:savedSet;
  };

  should["attempt every restore entry retain failures and support retry"]{
    .tst.mockHardening.restoreA:1;
    .tst.mockHardening.restoreB:2;
    .tst.deleteVar `.tst.mockHardening.restoreC;
    .tst.deleteVar `.tst.mockHardening.restoreD;
    .tst.mock[`.tst.mockHardening.restoreA;101];
    .tst.mock[`.tst.mockHardening.restoreB;202];
    .tst.mock[`.tst.mockHardening.restoreC;303];
    .tst.mock[`.tst.mockHardening.restoreD;404];
    .tst.mockHardening.savedSet:.tst.mockPrimitives`set;
    .tst.mockHardening.savedDelete:.tst.mockPrimitives`delete;
    .tst.mockHardening.setAttempts:`symbol$();
    .tst.mockHardening.deleteAttempts:`symbol$();
    restoreCapsule:.tst.makeMockRestoreCapsuleWith[
      .tst.mockHardening.failSet;
      .tst.mockHardening.failDelete];
    mustthrow[
      "*2 target*";
      (.tst.mockHardening.invokeCapsule;restoreCapsule)];
    expectedSet:
      `.tst.mockHardening.restoreA`.tst.mockHardening.restoreB;
    expectedDelete:
      `.tst.mockHardening.restoreC`.tst.mockHardening.restoreD;
    filteredSet:.tst.mockHardening.setAttempts inter expectedSet;
    filteredDelete:.tst.mockHardening.deleteAttempts inter expectedDelete;
    filteredSet mustmatch expectedSet;
    filteredDelete mustmatch expectedDelete;
    .tst.mockHardening.restoreB musteq 2;
    mustthrow["*restoreD*";{get `.tst.mockHardening.restoreD}];
    `.tst.mockHardening.restoreA mustin .tst.mockRegistryNames[];
    `.tst.mockHardening.restoreC mustin .tst.mockRegistryNames[];
    .tst.restore[];
    .tst.mockHardening.restoreA musteq 1;
    mustthrow["*restoreC*";{get `.tst.mockHardening.restoreC}];
  };

  should["retain ownership when restore primitives silently no-op"]{
    .tst.mockHardening.noOpSetTarget:7;
    .tst.deleteVar `.tst.mockHardening.noOpDeleteTarget;
    .tst.mock[`.tst.mockHardening.noOpSetTarget;70];
    .tst.mock[`.tst.mockHardening.noOpDeleteTarget;80];
    restoreCapsule:.tst.makeMockRestoreCapsuleWith[
      {[name;replacement]::};
      {[name](1b;"")}];
    mustthrow[
      "*target*";
      (.tst.mockHardening.invokeCapsule;restoreCapsule)];
    .tst.mockHardening.noOpSetTarget musteq 70;
    .tst.mockHardening.noOpDeleteTarget musteq 80;
    `.tst.mockHardening.noOpSetTarget mustin .tst.mockRegistryNames[];
    `.tst.mockHardening.noOpDeleteTarget mustin .tst.mockRegistryNames[];
    .tst.mockState.draining musteq 0b;
    .tst.restore[];
    .tst.mockHardening.noOpSetTarget musteq 7;
    mustthrow["*noOpDeleteTarget*";{
      get `.tst.mockHardening.noOpDeleteTarget
    }];
  };

  should["verify named lifecycle set and delete postconditions"]{
    existing:`.tst.mockHardening.namedExisting;
    absent:`.tst.mockHardening.namedAbsent;
    existing set 7;
    .tst.deleteVar absent;
    state:.tst.captureNamedLifecycle existing,absent;
    existing set 70;
    absent set 80;
    outcome:.tst.mockTry[
      .tst.restoreNamedLifecycleWith;
      (state;
       {[name;replacement]::};
       {[name](1b;"")};
       .tst.mockTargetMatches;
       .tst.mockTarget;
       ::)];
    (first outcome) musteq `error;
    (get existing) musteq 70;
    (get absent) musteq 80;
    .tst.restoreNamedLifecycle state;
    (get existing) musteq 7;
    mustthrow["*namedAbsent*";{get `.tst.mockHardening.namedAbsent}];
  };

  should["reset the restore guard and retain work after commit signals"]{
    target:`.tst.mockHardening.commitFailureTarget;
    target set 7;
    .tst.mock[target;70];
    mustthrow["*target*";{
      .tst.restoreWork[
        .tst.mockPrimitives`set;
        .tst.mockPrimitives`delete;
        .tst.validateMockState;
        .tst.mockCallableArity;
        .tst.mockTargetMatches;
        .tst.mockTry;
        {[dictionary;name]'"injected state update failure"};
        `mockRestoreV1]
    }];
    .tst.mockState.draining musteq 0b;
    (get target) musteq 7;
    target mustin .tst.mockRegistryNames[];
    .tst.restore[];
    (get target) musteq 7;
    .tst.asserts[`must][
      not target in .tst.mockRegistryNames[];
      "retry left commit-failure ownership behind"];
  };

  should["reject registration attempted during restore and retain retry state"]{
    .tst.mockHardening.drainTarget:5;
    .tst.deleteVar `.tst.mockHardening.drainRegistration;
    .tst.mock[`.tst.mockHardening.drainTarget;50];
    .tst.mockHardening.savedSet:.tst.mockPrimitives`set;
    restoreCapsule:.tst.makeMockRestoreCapsuleWith[
      .tst.mockHardening.registerDuringSet;
      .tst.mockPrimitives`delete];
    mustthrow[
      "*1 target*";
      (.tst.mockHardening.invokeCapsule;restoreCapsule)];
    `.tst.mockHardening.drainTarget mustin .tst.mockRegistryNames[];
    .tst.asserts[`must][
      not `.tst.mockHardening.drainRegistration in .tst.mockRegistryNames[];
      "registration during restore entered state"];
    .tst.restore[];
    .tst.mockHardening.drainTarget musteq 5;
  };

  should["preserve active originals when the mock module is reloaded"]{
    .tst.mockHardening.reloadTarget:7;
    .tst.mock[`.tst.mockHardening.reloadTarget;70];
    system "l ",.resq.HOME,"/lib/mock.q";
    .tst.mockHardening.reloadTarget musteq 70;
    `.tst.mockHardening.reloadTarget mustin .tst.mockRegistryNames[];
    .tst.restore[];
    .tst.mockHardening.reloadTarget musteq 7;
  };

  should["migrate only the exact idle legacy empty lifecycle on reload"]{
    .tst.testState.mockHardeningReloadRecovery:
      .tst.mockHardening.captureReloadState[];
    .tst.registerCleanup[
      .tst.mockHardening.restoreReloadState;
      enlist(::)];
    .tst.mockState:
      ((enlist `),`store`removeList)!
      ((::);enlist[`]!enlist(::);());
    .tst.spyLog:
      ((enlist `),`calls`impls)!
      ((::);()!();()!());
    .tst.seqs:()!();
    outcome:.tst.mockTry[
      system;
      enlist "l ",.resq.HOME,"/lib/mock.q"];
    (first outcome) musteq `ok;
    mustnotthrow[();{.tst.validateMockState 0b}];
    .tst.mockRegistryNames[] mustmatch `symbol$();
    .tst.mockHardening.restoreReloadState[];
  };

  should["reject malformed hot-load state without changing lifecycle ownership"]{
    .tst.testState.mockHardeningReloadRecovery:
      .tst.mockHardening.captureReloadState[];
    .tst.registerCleanup[
      .tst.mockHardening.restoreReloadState;
      enlist(::)];
    .tst.mockState.removeList:42;
    malformedState:.tst.mockState;
    malformedSpy:.tst.spyLog;
    malformedSeq:.tst.seqs;
    outcome:.tst.mockTry[
      system;
      enlist "l ",.resq.HOME,"/lib/mock.q"];
    (first outcome) musteq `error;
    .tst.mockState mustmatch malformedState;
    .tst.spyLog mustmatch malformedSpy;
    .tst.seqs mustmatch malformedSeq;
    .tst.asserts[`must][
      not `mockReloadBootstrap in key `.tst;
      "failed reload left its bootstrap helper installed"];
    .tst.mockHardening.restoreReloadState[];
  };

  should["refresh framework-owned reload aliases while preserving a caller conflict"]{
    .tst.testState.mockHardeningReloadRecovery:
      .tst.mockHardening.captureReloadState[];
    .tst.registerCleanup[
      .tst.mockHardening.restoreReloadState;
      enlist(::)];
    staleMock:{[name;mockValue]`staleMock};
    .tst.mock:staleMock;
    (` sv `.,`mock) set staleMock;
    `.q.mock set staleMock;
    .tst.qExports[`mock]:staleMock;
    system "l ",.resq.HOME,"/lib/mock.q";
    newMock:.tst.mock;
    .tst.deleteVar `.tst.mockHardening.rootReloadTarget;
    (get `..mock)[`.tst.mockHardening.rootReloadTarget;11];
    .tst.mockHardening.rootReloadTarget musteq 11;
    .tst.deleteVar `.tst.mockHardening.qReloadTarget;
    (get `.q.mock)[`.tst.mockHardening.qReloadTarget;12];
    .tst.mockHardening.qReloadTarget musteq 12;
    .tst.deleteVar `.tst.mockHardening.exportReloadTarget;
    (.tst.qExports `mock)[`.tst.mockHardening.exportReloadTarget;13];
    .tst.mockHardening.exportReloadTarget musteq 13;

    callerMock:{[name;mockValue]`callerMock};
    `.q.mock set callerMock;
    system "l ",.resq.HOME,"/lib/mock.q";
    refreshed:.tst.mock;
    (get `.q.mock)[`ignored;0] musteq `callerMock;
    .tst.deleteVar `.tst.mockHardening.rootReloadTarget2;
    (get `..mock)[`.tst.mockHardening.rootReloadTarget2;21];
    .tst.mockHardening.rootReloadTarget2 musteq 21;
    .tst.deleteVar `.tst.mockHardening.exportReloadTarget2;
    (.tst.qExports `mock)[`.tst.mockHardening.exportReloadTarget2;22];
    .tst.mockHardening.exportReloadTarget2 musteq 22;
    .tst.mockHardening.restoreReloadState[];
  };

  should["delete root and child targets functionally and verify absence"]{
    @[`.;`mockHardeningRootDelete;:;1];
    .mockHardeningDelete.child:2;
    rootResult:.tst.deleteVar `mockHardeningRootDelete;
    childResult:.tst.deleteVar `.mockHardeningDelete.child;
    (first rootResult) musteq 1b;
    (first childResult) musteq 1b;
    mustthrow["*mockHardeningRootDelete*";{
      get `mockHardeningRootDelete
    }];
    mustthrow["*child*";{get `.mockHardeningDelete.child}];
  };

  should["reject poisoned registry forms before any restore mutation"]{
    target:`.tst.mockHardening.poisonTarget;
    target set 7;
    .tst.mock[target;70];
    capsule:.tst.makeMockRestoreCapsule[];
    validState:.tst.mockState;
    validSpy:.tst.spyLog;
    validSeq:.tst.seqs;

    .tst.mockState.extra:1;
    poisonState:.tst.mockState;
    .tst.mockHardening.poisonRejected[
      capsule;target;70;poisonState;.tst.spyLog;.tst.seqs];
    .tst.mockState:validState;

    .tst.mockState.removeList:target,target;
    poisonState:.tst.mockState;
    .tst.mockHardening.poisonRejected[
      capsule;target;70;poisonState;.tst.spyLog;.tst.seqs];
    .tst.mockState:validState;

    .tst.mockState.removeList:enlist target;
    poisonState:.tst.mockState;
    .tst.mockHardening.poisonRejected[
      capsule;target;70;poisonState;.tst.spyLog;.tst.seqs];
    .tst.mockState:validState;

    .tst.mockState.store:enlist[`]!enlist(::);
    .tst.mockState.removeList:
      `$".tst.mockHardening.poison",/:string til 1025;
    poisonState:.tst.mockState;
    .tst.mockHardening.poisonRejected[
      capsule;target;70;poisonState;.tst.spyLog;.tst.seqs];
    .tst.mockState:validState;

    .tst.mockState.store:enlist[`]!enlist(::);
    .tst.mockState.removeList:enlist `$"bad target";
    poisonState:.tst.mockState;
    .tst.mockHardening.poisonRejected[
      capsule;target;70;poisonState;.tst.spyLog;.tst.seqs];
    .tst.mockState:validState;
    .tst.spyLog:validSpy;
    .tst.seqs:validSeq;
    capsule[];
    (get target) musteq 7;
  };

  should["reject poisoned spy and sequence payloads without partial restore"]{
    target:`.tst.mockHardening.poisonCallable;
    target set {[x]x};
    .tst.spy[target;{[x]x+1}];
    capsule:.tst.makeMockRestoreCapsule[];
    validState:.tst.mockState;
    validSpy:.tst.spyLog;
    validSeq:.tst.seqs;
    wrapped:get target;

    .tst.spyLog.extra:1;
    .tst.mockHardening.poisonRejected[
      capsule;target;wrapped;.tst.mockState;.tst.spyLog;.tst.seqs];
    .tst.spyLog:validSpy;

    .tst.spyLog.impls[target]:(::);
    poisonSpy:.tst.spyLog;
    .tst.mockHardening.poisonRejected[
      capsule;target;wrapped;.tst.mockState;poisonSpy;.tst.seqs];
    .tst.spyLog:validSpy;

    .tst.spyLog.impls[target]:+;
    poisonSpy:.tst.spyLog;
    .tst.mockHardening.poisonRejected[
      capsule;target;wrapped;.tst.mockState;poisonSpy;.tst.seqs];
    .tst.spyLog:validSpy;

    hugeArgs:enlist til 100001;
    .tst.spyLog.calls[target]:enlist hugeArgs;
    outcome:.tst.mockTry[capsule;()];
    (first outcome) musteq `error;
    count[.tst.spyLog.calls target] musteq 1;
    count[first first .tst.spyLog.calls target] musteq 100001;
    (get target) mustmatch wrapped;
    .tst.spyLog:validSpy;

    .tst.seqs[target]:`a`b!1 2;
    poisonSeq:.tst.seqs;
    .tst.mockHardening.poisonRejected[
      capsule;target;wrapped;.tst.mockState;.tst.spyLog;poisonSeq];
    .tst.mockState:validState;
    .tst.spyLog:validSpy;
    .tst.seqs:validSeq;
    capsule[];
    ((get target) 3) musteq 3;
  };
};

.tst.desc["Mock hardening: spies"]{
  should["keep a spy callable after clearing its logs"]{
    .tst.mockHardening.zeroSpy:{[]7};
    .tst.spy[`.tst.mockHardening.zeroSpy;::];
    .tst.mockHardening.zeroSpy[] musteq 7;
    .tst.callCount[`.tst.mockHardening.zeroSpy] musteq 1;
    .tst.mockHardening.clearSpy:{[x]2*x};
    .tst.spy[`.tst.mockHardening.clearSpy;::];
    .tst.mockHardening.clearSpy 2;
    .tst.clearSpyLogs[];
    (.tst.mockHardening.clearSpy 3) musteq 6;
    .tst.callCount[`.tst.mockHardening.clearSpy] musteq 1;
    .tst.lastCall[`.tst.mockHardening.clearSpy] mustmatch enlist 3;
  };

  should["replace an existing spy without recursively wrapping it"]{
    .tst.mockHardening.repeatedSpy:{[x]2*x};
    .tst.spy[`.tst.mockHardening.repeatedSpy;::];
    .tst.mockHardening.repeatedSpy 2;
    .tst.spy[`.tst.mockHardening.repeatedSpy;::];
    (.tst.mockHardening.repeatedSpy 3) musteq 6;
    .tst.callCount[`.tst.mockHardening.repeatedSpy] musteq 1;
    .tst.lastCall[`.tst.mockHardening.repeatedSpy] mustmatch enlist 3;
  };

  should["signal before log cap overflow without calling the implementation"]{
    .tst.mockHardening.spyEffects:0;
    .tst.mockHardening.cappedSpy:{[x]
      .tst.mockHardening.spyEffects+:1;
      x};
    .tst.spy[`.tst.mockHardening.cappedSpy;::];
    `.tst.MOCK_MAX_SPY_CALLS mock 1;
    .tst.mockHardening.cappedSpy 1;
    mustthrow["*capacity*";{.tst.mockHardening.cappedSpy 2}];
    .tst.callCount[`.tst.mockHardening.cappedSpy] musteq 1;
    .tst.mockHardening.spyEffects musteq 1;
  };

  should["bound nested retained argument graphs before calling implementation"]{
    .tst.mockHardening.argEffects:0;
    .tst.mockHardening.argSpy:{[x]
      .tst.mockHardening.argEffects+:1;
      count x};
    .tst.spy[`.tst.mockHardening.argSpy;::];
    small:(enlist `payload)!enlist 1 2 3;
    .tst.mockHardening.argSpy[small] musteq 1;
    .tst.lastCall[`.tst.mockHardening.argSpy] mustmatch enlist small;
    `.tst.MOCK_MAX_SPY_ARG_ITEMS mock 20;
    mustthrow["*retention*";{
      .tst.mockHardening.argSpy enlist[`payload]!enlist til 30
    }];
    mustthrow["*retention*";{
      .tst.mockHardening.argSpy enlist enlist til 30
    }];
    .tst.callCount[`.tst.mockHardening.argSpy] musteq 1;
    .tst.mockHardening.argEffects musteq 1;
  };

  should["account table column payload once plus structural references"]{
    table:([]a:1 2 3;b:4 5 6);
    .tst.spyRetainedItems[table] musteq 10;
    nested:(enlist `payload)!enlist table;
    .tst.spyRetainedItems[nested] musteq 13;
  };

  should["scale spy logging linearly with retained call count"]{
    .tst.mockHardening.scalingSpy:{[x]x};
    .tst.spy[`.tst.mockHardening.scalingSpy;::];
    measure:{[n]
      .tst.clearSpyLogs[];
      started:.z.p;
      do[n;.tst.mockHardening.scalingSpy 1];
      .z.p-started};
    small:med measure each 3#500;
    large:med measure each 3#1000;
    .tst.asserts[`must][
      large<3*small;
      "spy logging growth exceeded a linear scaling envelope"];
    .tst.callCount[`.tst.mockHardening.scalingSpy] musteq 1000;
  };

  should["define missing spy query results without state growth"]{
    beforeNames:key .tst.spyLog.calls;
    .tst.calledWith[`.tst.mockHardening.missingSpy;enlist 1] musteq 0b;
    .tst.callCount[`.tst.mockHardening.missingSpy] musteq 0;
    .tst.lastCall[`.tst.mockHardening.missingSpy] mustmatch (::);
    key[.tst.spyLog.calls] mustmatch beforeNames;
  };

  should["reject null non-callable and mismatched spy implementations"]{
    .tst.mockHardening.implTarget:{[x]x};
    mustthrow["*callable*";{
      .tst.spy[`.tst.mockHardening.implTarget;0N]
    }];
    mustthrow["*arity must match*";{
      .tst.spy[`.tst.mockHardening.implTarget;{[x;y]x+y}]
    }];
    .tst.mockHardening.projectionBase:{[x;y]x+y};
    .tst.mockHardening.projectionSpy:
      .tst.mockHardening.projectionBase[10;];
    .tst.spy[`.tst.mockHardening.projectionSpy;::];
    (.tst.mockHardening.projectionSpy 5) musteq 15;
  };
};

.tst.desc["Mock hardening: derived callable contracts"]{
  should["preserve fixed ranks for derived types 106 through 111"]{
    .tst.mockHardening.rank1:{[x]x};
    .tst.mockHardening.rank2:{[x;y]x+y};
    .tst.mockHardening.rank3:{[x;y;z]x+y+z};
    .tst.mockHardening.derived106:.tst.mockHardening.rank3';
    .tst.mockHardening.derived107:.tst.mockHardening.rank3/;
    .tst.mockHardening.derived108:.tst.mockHardening.rank3\;
    .tst.mockHardening.derived109:.tst.mockHardening.rank1':;
    .tst.mockHardening.derived110:.tst.mockHardening.rank2/:;
    .tst.mockHardening.derived111:.tst.mockHardening.rank2\:;
    derived:(.tst.mockHardening.derived106;
      .tst.mockHardening.derived107;
      .tst.mockHardening.derived108;
      .tst.mockHardening.derived109;
      .tst.mockHardening.derived110;
      .tst.mockHardening.derived111);
    (.tst.mockCallableArity each derived) musteq 3 3 3 1 2 2;
    .tst.spy[`.tst.mockHardening.derived106;{[a;b;c]a+b+c}];
    .tst.spy[`.tst.mockHardening.derived107;{[a;b;c]a*b*c}];
    .tst.spy[`.tst.mockHardening.derived108;{[a;b;c]a-b-c}];
    .tst.spy[`.tst.mockHardening.derived109;{[a]10+a}];
    .tst.spy[`.tst.mockHardening.derived110;{[a;b]a,b}];
    .tst.spy[`.tst.mockHardening.derived111;{[a;b]b,a}];
    .tst.mockHardening.derived106[1;2;3] musteq 6;
    .tst.mockHardening.derived107[2;3;4] musteq 24;
    .tst.mockHardening.derived108[9;2;1] musteq 8;
    (.tst.mockHardening.derived109 5) musteq 15;
    .tst.mockHardening.derived110[1;2] musteq 1 2;
    .tst.mockHardening.derived111[1;2] musteq 2 1;
  };

  should["preserve a fixed derived rank for sequence wrappers"]{
    .tst.mockHardening.sequenceDerivedBase:{[x;y;z]x+y+z};
    .tst.mockHardening.sequenceDerived:
      .tst.mockHardening.sequenceDerivedBase\;
    .tst.mockSequence[
      `.tst.mockHardening.sequenceDerived;
      enlist 99];
    .tst.mockHardening.sequenceDerived[1;2;3] musteq 99;
  };

  should["reject genuinely ambivalent 102 107 108 and 109 forms"]{
    .tst.mockHardening.ambivalent102:+;
    .tst.mockHardening.ambivalent107:+/;
    .tst.mockHardening.ambivalent108:+\;
    .tst.mockHardening.ambivalent109:+':;
    names:`.tst.mockHardening.ambivalent102,
      `.tst.mockHardening.ambivalent107,
      `.tst.mockHardening.ambivalent108,
      `.tst.mockHardening.ambivalent109;
    (.tst.mockCallableArity each get each names) musteq -2 -2 -2 -2;
    mustthrow["*ambivalent*";{
      .tst.spy[`.tst.mockHardening.ambivalent102;::]
    }];
    mustthrow["*ambivalent*";{
      .tst.spy[`.tst.mockHardening.ambivalent107;::]
    }];
    mustthrow["*ambivalent*";{
      .tst.spy[`.tst.mockHardening.ambivalent108;::]
    }];
    mustthrow["*ambivalent*";{
      .tst.spy[`.tst.mockHardening.ambivalent109;::]
    }];
    .tst.asserts[`must][
      not any names in key .tst.spyLog.calls;
      "ambivalent callable entered spy state"];
  };

  should["accept q lists and tables as sequence containers"]{
    .tst.mockHardening.sequenceListTarget:{[x]x};
    .tst.mockSequence[
      `.tst.mockHardening.sequenceListTarget;
      ([] a:1 2)];
    .tst.mockHardening.sequenceListTarget[0] mustmatch
      (enlist `a)!enlist 1;
    .tst.mockHardening.sequenceListTarget[0] mustmatch
      (enlist `a)!enlist 2;
    mustthrow["*must be a list*";{
      .tst.mockSequence[
        `.tst.mockHardening.sequenceListTarget;
        {[x]x}]
    }];
    mustthrow["*must be a list*";{
      .tst.mockSequence[
        `.tst.mockHardening.sequenceListTarget;
        42]
    }];
  };
};

/ These paired expectations prove that teardown uses its captured capsule, not
/ a replacement installed by the preceding expectation body.
.tst.desc["Mock hardening: authoritative cleanup"]{
  should["allow restore and its public helpers to be mocked in the body"]{
    .tst.deleteVar `.tst.mockHardening.capsuleLeak;
    .tst.mockHardening.cleanupEvents:`symbol$();
    .tst.registerCleanup[{[]
      .tst.mockHardening.cleanupEvents,:enlist `noOpCleanup
      };enlist(::)];
    .tst.mock[`.tst.restore;{[] ::}];
    .tst.mock[`.tst.restoreWork;{[a;b;c] ::}];
    .tst.mock[`.tst.teardownExpec;{[s;e]e}];
    .tst.mock[`.tst.finalizeExpecWith;{[a;s;e]e}];
    .tst.mock[`.tst.makeExpectationCleanup;{[]{[]::}}];
    .tst.mock[`.tst.restoreRuntimeContext;{[ctx]::}];
    .tst.mock[`..must;{[condition;message]'"mocked must"}];
    .tst.mock[`.tst.deleteVar;{[name](1b;"")}];
    .tst.mock[`.tst.mockHardening.capsuleLeak;42];
    / Install this last because mock installation itself uses the public setter.
    .tst.mock[`.tst.setMockValue;{[name;replacement] ::}];
  };

  should["unwind all mocks despite no-op cleanup replacements"]{
    .tst.mockHardening.cleanupEvents musteq enlist `noOpCleanup;
    mustthrow["*capsuleLeak*";{
      get `.tst.mockHardening.capsuleLeak
    }];
    .tst.asserts[`must][
      not `.tst.restore in .tst.mockRegistryNames[];
      "restore replacement survived expectation cleanup"];
    .tst.asserts[`must][
      not `.tst.restoreWork in .tst.mockRegistryNames[];
      "restore helper replacement survived expectation cleanup"];
    .tst.asserts[`must][
      not `.tst.finalizeExpecWith in .tst.mockRegistryNames[];
      "expectation finalizer replacement survived cleanup"];
    .tst.asserts[`must][
      not `.tst.makeExpectationCleanup in .tst.mockRegistryNames[];
      "cleanup capsule builder replacement survived cleanup"];
    .tst.asserts[`must][
      not `.tst.setMockValue in .tst.mockRegistryNames[];
      "set helper replacement survived expectation cleanup"];
    .tst.asserts[`must][
      not `.tst.deleteVar in .tst.mockRegistryNames[];
      "delete helper replacement survived expectation cleanup"];
    .tst.asserts[`must][
      not `..must in .tst.mockRegistryNames[];
      "root must replacement survived expectation cleanup"];
    mustnotthrow[();{(get `..must)[1b;"restored"]}];
  };

  should["allow a throwing restore replacement in the body"]{
    .tst.deleteVar `.tst.mockHardening.throwLeak;
    .tst.registerCleanup[{[]
      .tst.mockHardening.cleanupEvents,:enlist `throwReplacementCleanup
      };enlist(::)];
    .tst.mock[`.tst.restore;{[]'"mocked restore throw"}];
    .tst.mock[`.tst.teardownExpec;{[s;e]'"mocked teardown throw"}];
    .tst.mock[`.tst.finalizeExpecWith;{[a;s;e]'"mocked finalizer throw"}];
    .tst.mock[`.tst.makeExpectationCleanup;{[]
      '"mocked cleanup capsule builder throw"}];
    .tst.mock[`.tst.mockHardening.throwLeak;84];
  };

  should["unwind all mocks despite a throwing cleanup replacement"]{
    .tst.mockHardening.cleanupEvents musteq
      `noOpCleanup`throwReplacementCleanup;
    mustthrow["*throwLeak*";{
      get `.tst.mockHardening.throwLeak
    }];
    .tst.asserts[`must][
      not `.tst.restore in .tst.mockRegistryNames[];
      "throwing restore replacement survived expectation cleanup"];
    .tst.asserts[`must][
      not `.tst.teardownExpec in .tst.mockRegistryNames[];
      "throwing teardown replacement survived expectation cleanup"];
    .tst.asserts[`must][
      not `.tst.finalizeExpecWith in .tst.mockRegistryNames[];
      "throwing finalizer replacement survived expectation cleanup"];
  };

  should["leave no hardening target in mock lifecycle state"]{
    names:string .tst.mockRegistryNames[];
    leaked:names where names like "*.tst.mockHardening.*";
    count[leaked] musteq 0;
  };
};

::
