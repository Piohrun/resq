/ lib/mock.q - Mocking and spying framework

.tst.mockState.store: enlist[`]!enlist(::)
.tst.mockState.removeList:()
.tst.spyLog.calls:()!()
.tst.spyLog.impls:()!()
.tst.seqs:()!()

/ Mocks installed by a suite's beforeAll, for the whole suite. () when the
/ suite has none. Suites nest (a test may run a suite), so the enclosing
/ suite's entry waits on a stack, with the names that were already mocked
/ when this suite began.
.tst.mockState.suite: ();
.tst.mockState.suiteStack: ();
.tst.mockState.mockedBeforeSuite: `symbol$();

.tst.mockedNames:{[] (key[.tst.mockState.store] except `), .tst.mockState.removeList};

/ A suite starts: set aside the enclosing suite's mocks and note what is
/ mocked already, so beforeAll's additions can be told apart.
.tst.beginSuiteMocks:{[]
    .tst.mockState.suiteStack,: enlist (.tst.mockState.suite; .tst.mockState.mockedBeforeSuite);
    .tst.mockState.suite: ();
    .tst.mockState.mockedBeforeSuite: .tst.mockedNames[];
 };

/ Remember the mocks beforeAll installed. After each test every mock is
/ undone, which is right for the test's own; without this it also undid the
/ suite's after the first test, and from the second test on the real
/ dependency ran.
.tst.captureSuiteMocks:{[]
    names: .tst.mockedNames[] except .tst.mockState.mockedBeforeSuite;
    if[0 = count names; .tst.mockState.suite: (); :()];
    inStore: names inter key .tst.mockState.store;
    .tst.mockState.suite: `originals`removeList`names`values`impls`seqs!(
        inStore!.tst.mockState.store inStore; names inter .tst.mockState.removeList; names;
        {@[get; x; {[e] ::}]} each names; .tst.spyLog.impls; .tst.seqs);
 };

/ End of the suite, after afterAll: undo the suite's own mocks, and only
/ those. A suite run from inside a test must leave that test's mocks alone.
.tst.releaseSuiteMocks:{[]
    suite: .tst.mockState.suite;
    if[99h = type suite;
        mockSet: {[n;v] $[not (string n) like ".*"; @[`.;n;:;v]; n set v]};
        originals: suite`originals;
        {[mockSet;n;v] @[{[f;p] f . p}[mockSet]; (n;v); {[e] ::}]}[mockSet]'[key originals; value originals];
        .tst.deleteVar each suite`removeList;
        .tst.mockState.store: (key[originals]) _ .tst.mockState.store;
        .tst.mockState.removeList: .tst.mockState.removeList except suite`removeList];
    if[count .tst.mockState.suiteStack;
        enclosing: last .tst.mockState.suiteStack;
        .tst.mockState.suiteStack: -1 _ .tst.mockState.suiteStack;
        .tst.mockState.suite: enclosing 0;
        .tst.mockState.mockedBeforeSuite: enclosing 1];
 };

/ After a test: undo its mocks, and put the suite's back as beforeAll left
/ them (a test may have mocked the same name again). Spy logs start empty.
.tst.restoreAfterTest:{[]
    suite: .tst.mockState.suite;
    .tst.restore[];
    if[not 99h = type suite; :()];
    mockSet: {[n;v] $[not (string n) like ".*"; @[`.;n;:;v]; n set v]};
    mockSet'[suite`names; suite`values];
    .tst.mockState.store: .tst.mockState.store, suite`originals;
    .tst.mockState.removeList: distinct .tst.mockState.removeList, suite`removeList;
    .tst.spyLog.impls: suite`impls;
    spied: key suite`impls;
    .tst.spyLog.calls: $[count spied; spied!(count spied)#enlist (); ()!()];
    .tst.seqs: suite`seqs;
 };

/ Is this name a view (`name::expression`)? q keeps views in the root
/ namespace, by bare name.
.tst.isView:{[fqn]
    if[(string fqn) like ".*"; :0b];
    fqn in views `.
 };

.tst.mock:{[name;newVal]
    if[not -11h=type name; '"Mock name must be symbol"];
    if[null name; '"Mock name null"];
    fctx: @[get;`.tst.context;{` }];
    / Build fully qualified name
    / Original logic: if name starts with . OR context is not root/null, qualify it
    / Otherwise use unqualified name (for root context compatibility)
    fqn: $[(string[name] like ".*") or (not fctx in ``.); $[(string[name] like ".*"); name; ` sv fctx, name]; name];

    / Validate - cannot mock system namespaces
    fqnStr: string fqn;
    systemNs: `.q`.Q`.z`.h`.j`.tst`.resq`.utl;
    if[fqn in systemNs; '"Cannot mock a system namespace"];

    / Helper to set a value regardless of current q namespace
    / For global vars (no dot), use functional update to root namespace
    / For namespaced vars, use regular set
    mockSet: {[n;v] $[not (string n) like ".*"; @[`.;n;:;v]; n set v] };

    / A view cannot be mocked and put back. What q hands over for it is its
    / last value (or nothing, before first use), not its definition, so the
    / "restored" name was a plain variable that no longer followed what it
    / was defined on, for the rest of the run.
    if[.tst.isView fqn;
        '"cannot mock the view ", fqnStr, ": after the test it would be a plain value, no longer a view. Mock the variables it is defined on instead."];
    / Save original state if not already saved
    if[fqn in .tst.mockState.removeList; :mockSet[fqn;newVal]];

    / Tag the lookup outside its value. A legitimate original value of `dne (or
    / any other q value) must never be confused with "name does not exist".
    lookup: @[{[n] (1b; get n)}; fqn; {[err] (0b; err)}];
    exists: 1b ~ first lookup;
    if[not exists;
        if[not fqn in .tst.mockState.removeList; .tst.mockState.removeList,: fqn];
        :mockSet[fqn;newVal]];

    if[not fqn in key .tst.mockState.store;
        .tst.mockState.store[fqn]: last lookup];

    mockSet[fqn;newVal]
 }

.tst.partialMock:{[name;partialVal]
    orig: @[get; name; {[n;e] '"partialMock target not defined: ", string n}[name]];
    if[not 99h=type orig; '"partialMock only supports dictionaries"];
    if[not 99h=type partialVal; '"Partial value must be a dictionary"];
    .tst.mock[name; orig, partialVal];
 }

/ Arity-indexed spy wrappers. Each template takes `name` as its first
/ parameter and is projected with the target name when a spy is installed,
/ giving back a function whose remaining arity matches the original. This
/ replaces an earlier value-eval of a constructed q source string, which was
/ correct but a generic injection surface.
.tst.spyTemplates: enlist[0]!enlist {[name] .tst.spyLogCallback[name; ()]; (.tst.spyLog.impls name)[]};
.tst.spyTemplates[1]: {[name; a0] .tst.spyLogCallback[name; enlist a0]; (.tst.spyLog.impls name) . enlist a0};
.tst.spyTemplates[2]: {[name; a0; a1] .tst.spyLogCallback[name; (a0; a1)]; (.tst.spyLog.impls name) . (a0; a1)};
.tst.spyTemplates[3]: {[name; a0; a1; a2] .tst.spyLogCallback[name; (a0; a1; a2)]; (.tst.spyLog.impls name) . (a0; a1; a2)};
.tst.spyTemplates[4]: {[name; a0; a1; a2; a3] .tst.spyLogCallback[name; (a0; a1; a2; a3)]; (.tst.spyLog.impls name) . (a0; a1; a2; a3)};
.tst.spyTemplates[5]: {[name; a0; a1; a2; a3; a4] .tst.spyLogCallback[name; (a0; a1; a2; a3; a4)]; (.tst.spyLog.impls name) . (a0; a1; a2; a3; a4)};
.tst.spyTemplates[6]: {[name; a0; a1; a2; a3; a4; a5] .tst.spyLogCallback[name; (a0; a1; a2; a3; a4; a5)]; (.tst.spyLog.impls name) . (a0; a1; a2; a3; a4; a5)};
.tst.spyTemplates[7]: {[name; a0; a1; a2; a3; a4; a5; a6] .tst.spyLogCallback[name; (a0; a1; a2; a3; a4; a5; a6)]; (.tst.spyLog.impls name) . (a0; a1; a2; a3; a4; a5; a6)};

/ Arity-8 fallback: q's hard lambda-arity ceiling (8) means the templated
/ approach cannot cover it (8 user args + `name` would need 9 params).
/ Construct via `value` on a fixed source string. Inputs to the format are
/ all internally generated, so this re-introduces no user-controlled eval.
.tst.spy8Wrapper:{[name]
    nameStr: .tst.renderValueFull name;
    value "{[a0;a1;a2;a3;a4;a5;a6;a7] .tst.spyLogCallback[",nameStr,"; (a0;a1;a2;a3;a4;a5;a6;a7)]; .tst.spyLog.impls[",nameStr,"] . (a0;a1;a2;a3;a4;a5;a6;a7)}"
 };

.tst.spy:{[name;impl]
    orig: @[get; name; {[n;e] '"Spy on undefined function: ", string n}[name]];
    if[not 100h=type orig; '"Not a func"];
    if[impl~(::); impl:orig];
    arity: count (value orig) 1;
    compiled: $[arity in key .tst.spyTemplates;
                .tst.spyTemplates[arity] name;
                arity = 8;
                .tst.spy8Wrapper name;
                '"Cannot spy on arity-", string[arity], " functions"
              ];
    .tst.spyLog.impls[name]: impl;
    .tst.spyLog.calls[name]: ();
    .tst.mock[name; compiled];
 }

.tst.spyLogCallback:{[name;args] .tst.spyLog.calls[name],: enlist args }
.tst.calledWith:{[name;args] args in .tst.spyLog.calls[name]}
.tst.callCount:{[name] count .tst.spyLog.calls[name]}
.tst.lastCall:{[name] last .tst.spyLog.calls[name]}
.tst.clearSpyLogs:{[] .tst.spyLog.calls: ()!()}

.tst.restore:{[]
    / Helper to set a value regardless of current q namespace
    mockSet: {[n;v] $[not (string n) like ".*"; @[`.;n;:;v]; n set v] };
    if[0<count .tst.mockState.store;
        { [mockSet;k;v] 
            if[not null k; 
                / Discard the setter's return value and add our own status tag;
                / otherwise an original (`restoreErr;...) value impersonates an
                / error even though restoration succeeded.
                res: .[{[setFn;n;original] setFn[n;original]; (0b; "")};
                         (mockSet;k;v);
                         {[err] (1b; err)}];
                if[1b ~ first res;
                    if[`recordCleanupError in key `.tst;
                        .tst.recordCleanupError[`mockRestore;
                            "Failed to restore mock '", string[k], "': ", last res]
                    ];
                    if[not `recordCleanupError in key `.tst;
                        -1 "ERROR: Failed to restore mock '", string[k], "': ", last res
                    ];
                ]
            ]
        }[mockSet]' [key .tst.mockState.store; value .tst.mockState.store]];
    if[0<count .tst.mockState.removeList;
        .tst.deleteVar each .tst.mockState.removeList];
    .tst.mockState.store: enlist[`]!enlist(::);
    .tst.mockState.removeList: ();
    .tst.spyLog.calls: ()!();
    .tst.spyLog.impls: ()!();
    .tst.seqs: ()!();
 }

/ Helper to properly delete a variable by symbol
.tst.deleteVar:{[sym]
    s: string sym;
    / Handle namespaced variables (e.g. .foo.bar)
    / .z callbacks (.z.pg, .z.ps, .z.ts, ...) are not dictionary entries; q
    / unsets one with \x. Without this a handler mocked while unset stayed
    / installed for every later test.
    if[s like ".z.*";
        @[system; "x ", s; {[s;e] -1 "WARN: deleteVar failed for ", s, ": ", e}[s]];
        :()];
    if[s like ".*";
        parts: "." vs s;
        ns: `$ "." sv -1 _ parts;  / namespace (e.g. .foo)
        vn: `$ last parts;          / variable name (e.g. bar)
        .[{x set ![value x;();0b;enlist y]}; (ns;vn); {[n;v;e] -1 "WARN: deleteVar failed for ",string[n],".",string[v],": ",e}[ns;vn]];
        :()
    ];
    / Handle root-level variables (e.g. foo)
    @[{![`.;();0b;enlist x]}; sym; {}];
 }

.tst.mockSequence:{[name;vals]
    .tst.seqs[name]: vals;
    orig: @[get; name; {[n;e] '"mockSequence target not defined: ", string n}[name]];
    r: count (value orig) 1;
    argNames: `$"a",/:string til r;
    args: ";" sv string argNames;
    wrapper: "{[",args,"] .tst.nextSeq[",(.tst.renderValueFull name),"]}";
    .tst.mock[name; value wrapper];
 }

.tst.nextSeq:{[name]
    if[not count .tst.seqs[name]; '"Mock sequence exhausted"];
    v: first .tst.seqs[name];
    .tst.seqs[name]: 1 _ .tst.seqs[name];
    v
 }
