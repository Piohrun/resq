/ lib/mock.q - Mocking and spying framework

.tst.mockState.store: enlist[`]!enlist(::)
.tst.mockState.removeList:()
.tst.spyLog.calls:()!()
.tst.spyLog.impls:()!()
.tst.seqs:()!()

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

    / Save original state if not already saved
    if[fqn in .tst.mockState.removeList; :mockSet[fqn;newVal]];

    exists: not `dne ~ @[get;fqn;{`dne}];
    if[not exists;
        if[not fqn in .tst.mockState.removeList; .tst.mockState.removeList,: fqn];
        :mockSet[fqn;newVal]];

    if[not fqn in key .tst.mockState.store;
        .tst.mockState.store[fqn]: get fqn];

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
    nameStr: .Q.s1 name;
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
                res: .[mockSet; (k;v); {(`restoreErr; x)}];
                if[(2 = count res) and (first res) ~ `restoreErr;
                    -1 "WARNING: Failed to restore mock '", string[k], "': ", last res
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
    wrapper: "{[",args,"] .tst.nextSeq[",(.Q.s1 name),"]}";
    .tst.mock[name; value wrapper];
 }

.tst.nextSeq:{[name]
    if[not count .tst.seqs[name]; '"Mock sequence exhausted"];
    v: first .tst.seqs[name];
    .tst.seqs[name]: 1 _ .tst.seqs[name];
    v
 }
