/ tests/hardening/test_testing_patterns.q
/ Phase 5: Testing patterns - retry, testOnly, focus

.tst.desc["Testing Pattern Features"]{

    should["have retry DSL available"]{
        `retry mustin key `.tst;
    };

    should["have testOnly DSL available"]{
        `testOnly mustin key `.tst;
    };

    should["have skip DSL available"]{
        `skip mustin key `.tst;
    };

    should["have pending DSL available"]{
        `pending mustin key `.tst;
    };

    should["have skipIf DSL available"]{
        `skipIf mustin key `.tst;
    };

    / Note: skip and pending create special test entries
    / They are verified by checking the DSL functions exist

};
