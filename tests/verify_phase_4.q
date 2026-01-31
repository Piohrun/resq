/ Verify Max Arity (8 in this env)
.tst.desc["Mocking Arity Test"]{
    should["spy on an 8-argument function"]{
        .tst.f8: {[a0;a1;a2;a3;a4;a5;a6;a7] (a0;a1;a2;a3;a4;a5;a6;a7)};
        .tst.spy[`.tst.f8; (::)];
        
        args: til 8;
        res: .tst.f8 . args;
        
        res mustmatch args;
        `.tst.f8 mustHaveBeenCalledWith args;
    };
};

/ Verify Wall of Fame
.tst.desc["Performance Wall Test"]{
    should["be slow to show up in report"]{
        x:0; do[100000000; x+:1]; 
        1 musteq 1;
    };
    should["be medium slow"]{
        x:0; do[50000000; x+:1];
        1 musteq 1;
    };
    should["be fast"]{
        1 musteq 1;
    };
};
