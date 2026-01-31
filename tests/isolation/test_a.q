/ tests/isolation/test_a.q
.tst.desc["Isolation Source"]{
    should["define a global variable"]{
        leakVar:: 999;
        leakVar musteq 999;
    };
};
