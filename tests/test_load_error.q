.tst.desc["Load Error Test"]{
    should["record syntax errors when loading tests"]{
        code: "1+`a";
        res: @[value; code; {(`err0x; x)}];
        must[(2 = count res) and (first res) ~ `err0x; "Expected error trap to return err0x tuple"];
    };
};
