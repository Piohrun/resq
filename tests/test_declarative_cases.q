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

/ Two tests with the same description in one suite have the same identity.
/ qspec runs such a suite; resQ used to refuse the whole run. The later
/ declaration now gets a name of its own while the file loads.
.tst.desc["tests declared twice in one suite"]{
  should["give each later one its own name and identity"]{
    `.tst.app.declaredTestIds mock ();
    spec: .tst.numberDuplicateTests .tst.desc["repeats"]{
      should["same name"]{ 1 musteq 1 };
      should["same name"]{ 1 musteq 1 };
      should["other"]{ 1 musteq 1 };
      should["same name"]{ 1 musteq 1 };
    };
    (spec[`expectations]`desc) musteq ("same name"; "same name (2)"; "other"; "same name (3)");
    ids: .tst.expectationTestId[spec;] each spec`expectations;
    (count distinct ids) musteq 4;
  };
  should["keep the cases of one shouldEach together and number a second shouldEach"]{
    `.tst.app.declaredTestIds mock ();
    spec: .tst.numberDuplicateTests .tst.desc["repeated cases"]{
      shouldEach["cases"; ([] a:1 2)]{[a] a musteq a };
      shouldEach["cases"; ([] a:3 4)]{[a] a musteq a };
    };
    (spec[`expectations]`desc) musteq ("cases [case 1]"; "cases [case 2]"; "cases (2) [case 1]"; "cases (2) [case 2]");
    (spec[`expectations]`parentDesc) musteq ("cases"; "cases"; "cases (2)"; "cases (2)");
    ids: .tst.expectationCaseId[spec;] each spec`expectations;
    (count distinct ids) musteq 4;
  };
  should["leave a suite without repeats exactly as it was"]{
    `.tst.app.declaredTestIds mock ();
    spec: .tst.desc["no repeats"]{
      should["first"]{ 1 musteq 1 };
      should["second"]{ 1 musteq 1 };
    };
    numbered: .tst.numberDuplicateTests spec;
    (numbered[`expectations]`desc) musteq ("first"; "second");
  };
 };
