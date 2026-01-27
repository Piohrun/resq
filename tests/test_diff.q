.tst.desc["Semantic Diff Engine"]{
    should["return empty list for identical values"]{
        result: .tst.diff[42; 42];
        0 musteq count result;

        result: .tst.diff["hello"; "hello"];
        0 musteq count result;

        result: .tst.diff[`a`b`c!1 2 3; `a`b`c!1 2 3];
        0 musteq count result;
    };

    should["detect type mismatches"]{
        result: .tst.diff[42; 42.0];
        (count result) mustgt 0;
        (first result) mustlike "*Type mismatch*";
    };

    should["detect table column mismatches"]{
        t1: ([] a:1 2 3; b:4 5 6);
        t2: ([] a:1 2 3; c:4 5 6);
        result: .tst.diff[t1; t2];
        (count result) mustgt 0;
        (first result) mustlike "*Column mismatch*";
    };

    should["detect table row count mismatches"]{
        t1: ([] a:1 2 3);
        t2: ([] a:1 2);
        result: .tst.diff[t1; t2];
        (count result) mustgt 0;
        (first result) mustlike "*Count mismatch*";
    };

    should["detect table content mismatches"]{
        t1: ([] a:1 2 3; b:4 5 6);
        t2: ([] a:1 2 3; b:4 5 99);
        result: .tst.diff[t1; t2];
        (count result) mustgt 0;
        (first result) mustlike "*Table content mismatch*";
    };

    should["detect list length mismatches"]{
        result: .tst.diff[1 2 3; 1 2];
        (count result) mustgt 0;
        (first result) mustlike "*Count mismatch*";
    };

    should["detect list content mismatches"]{
        result: .tst.diff[1 2 3; 1 2 99];
        (count result) mustgt 0;
        (first result) mustlike "*List content mismatch*";
    };

    should["show value mismatch for atoms"]{
        result: .tst.diff[42; 99];
        (count result) mustgt 0;
        (first result) mustlike "*Value mismatch*";
    };

    should["show value mismatch for dictionaries"]{
        result: .tst.diff[`a`b!1 2; `a`b!1 99];
        (count result) mustgt 0;
        (first result) mustlike "*Value mismatch*";
    };

    should["limit table row mismatches to 5"]{
        t1: ([] a: til 100);
        t2: ([] a: 100 + til 100);
        result: .tst.diff[t1; t2];
        (count result) mustgt 5;
        (count result) mustlt 20;
        (first result) mustlike "*mismatch*";
    };

    should["limit list index mismatches to 5"]{
        l1: til 100;
        l2: 100 + til 100;
        result: .tst.diff[l1; l2];
        (count result) mustgt 5;
        (count result) mustlt 20;
        (first result) mustlike "*mismatch*";
    };
};
