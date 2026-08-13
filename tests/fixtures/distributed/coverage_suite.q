system "l tests/fixtures/distributed/coverage_source.q";

.tst.desc["Distributed coverage contract"]{
    should["negative branch"]{.distcov.classify[-1] musteq `negative};
    should["zero branch"]{.distcov.classify[0] musteq `zero};
    should["positive branch"]{.distcov.classify[1] musteq `positive};
    should["both conditional-expression edges"]{
        (.distcov.parity each 1 2) musteq `odd`even;
    };
};
