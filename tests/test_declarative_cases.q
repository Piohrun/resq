.tst.declarativeFixtureValue:41;

.tst.desc["Declarative parameter cases"]{
    before{.tst.registerFixture[`declaredFixture;.tst.declarativeFixtureValue]};

    shouldEach["execute as independently declared cases";
        ([] left:1 2 3;right:10 20 30;expected:11 22 33)]{
        [left;right;expected]
        (left+right) musteq expected;
    };

    shouldEach["inject fixtures after case parameters";
        ([] input:enlist 1;expected:enlist 42)]{
        [input;expected;declaredFixture]
        (input+declaredFixture) musteq expected;
    };

    should["inventory cases without executing their bodies"]{
        old:.tst.expecList;
        .tst.expecList:();
        touched:0b;
        .tst.shouldEach["inventory";([] a:7 8)]{[a] touched::1b};
        rows:{[table;i]table i}[.tst.expecList] each til count .tst.expecList;
        .tst.expecList:old;
        2 musteq count rows;
        0b musteq touched;
        `case`case musteq rows[;`type];
        0 1j musteq rows[;`caseIndex];
        7 8 musteq {first value x} each rows[;`parameters];
    };

    should["reject non-table data and mismatched body parameters"]{
        mustthrow["*expects a table*";(.tst.shouldEach;"bad";1 2;{[x]x})];
        mustthrow["*at least one*";
            (.tst.shouldEach;"bad";([] a:`int$());{[a]a})];
        mustthrow["*leading parameter names*";
            (.tst.shouldEach;"bad";([] a:enlist 1);{[wrong]wrong})];
    };
};
