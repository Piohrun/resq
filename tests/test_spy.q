/ Note: When spying, you must call the global function, not a local variable.
/ Using `f set {...} directly (without local assignment) ensures f[...] calls the spy.

.tst.desc["Spy Verification"]{

    should["verify spy records calls"]{
        / Set global directly - no local variable to shadow the spy
        `f set {[a;b] a+b};
        .tst.spy[`f; (::)];

        res: f[1;2];
        res musteq 3;

        .tst.callCount[`f] musteq 1;
        .tst.calledWith[`f; (1;2)] musteq 1b;
        .tst.lastCall[`f] mustmatch (1;2);

        f[10;20];
        .tst.callCount[`f] musteq 2;
    };

    should["verify spy with mock implementation"]{
        / Set global directly - no local variable to shadow the spy
        `g set {[x] x*2};

        .tst.spy[`g; {[x] x*10}];

        res: g[5];
        res musteq 50;
        .tst.callCount[`g] musteq 1;
    };
};
