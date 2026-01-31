\l lib/bootstrap.q
\l lib/init.q

.tst.desc["Deep Diff Verification"; {
    it["should diff nested dictionaries"; {
        exp: `a`b`c!(1; `x`y!(10;20); 3);
        act: `a`b`c!(1; `x`y!(11;20); 3);
        res: .tst.diff[exp; act];
        -1 "Dict Diff Output:";
        -1 "\n" sv res;
        (count res) mustgt 0;
        any res like "*b.x:*" musteq 1b;
    }];

    it["should diff tables with column deltas"; {
        exp: ([] a:1 2 3; b:`x`y`z);
        act: ([] a:1 25 3; b:`x`y`w);
        res: .tst.diff[exp; act];
        -1 "Table Diff Output:";
        -1 "\n" sv res;
        (count res) mustgt 0;
        any res like "*Row 1:*" musteq 1b;
        any res like "*Col a:*" musteq 1b;
        any res like "*Row 2:*" musteq 1b;
        any res like "*Col b:*" musteq 1b;
    }];
    
    it["should detect missing/extra keys in dicts"; {
        exp: `a`b!1 2;
        act: `a`c!1 3;
        res: .tst.diff[exp; act];
        -1 "Dict Key Mismatch Output:";
        -1 "\n" sv res;
        any res like "*Missing keys: *" musteq 1b;
        any res like "*Extra keys: *" musteq 1b;
    }];
}];

.tst.runAll[];
exit `int$not .tst.app.passed;
