/ tests/isolation/test_b.q
.tst.desc["Isolation Target"]{
    should["not see global from other file"]{
        / Should throw 'leakVar error because it shouldn't exist
        mustthrow["leakVar"; { leakVar }];
    };
};
