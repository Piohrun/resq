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
    orig: get name;
    if[not 99h=type orig; '"partialMock only supports dictionaries"];
    if[not 99h=type partialVal; '"Partial value must be a dictionary"];
    .tst.mock[name; orig, partialVal];
 }

.tst.spy:{[name;impl]
    orig: @[get; name; {[n;e] '"Spy on undefined function: ", string n}[name]];
    if[not 100h=type orig; '"Not a func"];
    if[impl~(::); impl:orig];
    r: count (value orig) 1;
    if[r>8; r:8];
    if[r<1; r:1];
    args: ";" sv string r#`a`b`c`d`e`f`g`h;
    / For arity 1, (a) is just an atom. Use "enlist a" to make a list
    argsAsList: $[r=1; "enlist ", args; "(", args, ")"];
    wrapper: "{[",args,"] .tst.spyLogCallback[",(.Q.s1 name),";",argsAsList,"]; .tst.spyLog.impls[",(.Q.s1 name),"][",args,"]}";
    compiled: value wrapper;
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
        { [mockSet;k;v] if[not null k; .[mockSet; (k;v); {}]] }[mockSet]' [key .tst.mockState.store; value .tst.mockState.store]];
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
        @[{![x;();0b;enlist y]}; (ns;vn); {}];
        :()
    ];
    / Handle root-level variables (e.g. foo)
    @[{![`.;();0b;enlist x]}; sym; {}];
 }

.tst.mockSequence:{[name;vals]
    .tst.seqs[name]: vals;
    orig: get name;
    r: count (value orig) 1;
    if[r>8; r:8];
    args: ";" sv string r#`a`b`c`d`e`f`g`h;
    wrapper: "{[",args,"] .tst.nextSeq[",(.Q.s1 name),"]}";
    .tst.mock[name; value wrapper];
 }

.tst.nextSeq:{[name]
    if[not count .tst.seqs[name]; '"Mock sequence exhausted"];
    v: first .tst.seqs[name];
    .tst.seqs[name]: 1 _ .tst.seqs[name];
    v
 }
