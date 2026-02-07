/ tests/hardening/test_dev_experience.q
/ Phase 4: Developer experience features

.tst.desc["Developer Experience Features"]{

    should["have beforeAll hook available"]{
        `beforeAll mustin key `.tst;
        `currentBeforeAll mustin key `.tst;
    };

    should["have afterAll hook available"]{
        `afterAll mustin key `.tst;
        `currentAfterAll mustin key `.tst;
    };

    should["have config validation function"]{
        `validateConfig mustin key `.tst;
    };

    should["validate config with unknown keys"]{
        / Test validation catches unknown keys
        cfg: `unknownKey`fmt!("bad"; `junit);
        warnings: .tst.validateConfig cfg;
        0 mustlt count warnings;
    };

    should["pass validation for known keys"]{
        cfg: `fmt`maxTestTime!(`junit; 30);
        warnings: .tst.validateConfig cfg;
        0 musteq count warnings;
    };

    should["have watch mode debounce config"]{
        `debounceMs mustin key `.tst.watch;
        .tst.watch.debounceMs musteq 200;
    };

};
