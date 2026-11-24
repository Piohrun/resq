/ Suites that check what an earlier suite in this file did. resQ runs
/ files, suites and the tests in them in any order under -random-order, so
/ tests/test_ui.q runs this file in a child resQ of its own, where declaration
/ order holds.

.tst.testState.altlog: ();
.tst.desc["alt blocks and hooks declared after them"]{
    alt{
        before{ .tst.testState.altlog,: enlist "innerBefore" };
        after{  .tst.testState.altlog,: enlist "innerAfter" };
        should["inside alt"]{ .tst.testState.altlog,: enlist "innerTest"; 1 musteq 1; };
    };
    before{ .tst.testState.altlog,: enlist "outerBefore" };
    after{  .tst.testState.altlog,: enlist "outerAfter" };
    should["declared after the alt block"]{
        .tst.testState.altlog,: enlist "outerTest"; 1 musteq 1;
    };
};

.tst.desc["alt hook masking verification"]{
    should["run the alt's own hooks, then the outer hooks declared after it"]{
        .tst.testState.altlog musteq ("innerBefore";"innerTest";"innerAfter";
                                      "outerBefore";"outerTest";"outerAfter");
    };
    should["clean up its scratch state"]{
        @[{![`.tst.testState; (); 0b; enlist `altlog]}; (); {}];
        1 musteq 1;
    };
};
