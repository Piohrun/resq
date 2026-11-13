/ tests/hardening/test_large_output.q
/ Phase 2: Verify truncation prevents memory issues with large values

.tst.desc["Large Output Safety"]{

    should["have truncate function available"]{
        `truncate mustin key `.tst;
    };

    should["truncate long serialized values"]{
        / Create a large dictionary - serializes to long string
        bigDict: (til 200)!(til 200);
        
        / Truncate with 100 char limit
        truncated: .tst.truncate[bigDict; 100];
        
        / Should be shorter than or equal to limit (including truncation message)
        / The limit + message overhead is approximately limit + 40
        (count truncated) mustlt 150;
    };

    should["include truncation indicator"]{
        / Create large value and truncate
        bigList: til 100;
        truncated: .tst.truncate[bigList; 50];
        
        / Output should contain "truncated"
        0 mustlt count truncated ss "truncated";
        / And be roughly around the limit (allowing for message overhead)
        (count truncated) mustlt 100;
    };

    should["preserve small values unchanged"]{
        / Small values should not be modified  
        result: .tst.truncate[42; 10000];
        result musteq "42";
    };

    should["preserve reportLimit configuration"]{
        `reportLimit mustin key `.tst.output;
        .tst.output.reportLimit musteq 50000;
    };

    should["preserve reportListLimit configuration"]{
        `reportListLimit mustin key `.tst.output;
        .tst.output.reportListLimit musteq 1000;
    };

    should["bound and localize a mismatch in a 100k-row table"]{
        n: 100000;
        expected: ([] id:til n; v:n#0j);
        actual: expected;
        actual[n - 1;`v]: 1j;
        rendered: "\n" sv .tst.diff[expected;actual];
        must[(count rendered) < 5000;
             "large-table diagnostics must stay below 5KB, got ",string count rendered];
        must[0 < count ss[rendered;"Row 99999"];
             "the bounded diagnostic must retain the mismatch location"];
    };

    should["bound and localize a mismatch in a million-element vector"]{
        n: 1000000;
        expected: til n;
        actual: expected;
        actual[n - 1]: -1;
        rendered: "\n" sv .tst.diff[expected;actual];
        must[(count rendered) < 5000;
             "million-vector diagnostics must stay below 5KB, got ",string count rendered];
        must[0 < count ss[rendered;"Idx 999999"];
             "the bounded diagnostic must retain the mismatch index"];
    };

    / A failing assertion renders its operands. Rendering used to walk the whole
    / value before cutting it to the limit: 79 s for a 2M-row table. The time
    / limits below are loose on purpose; the old cost was 20x beyond them.
    should["render a bounded prefix of a large table without walking all of it"]{
        n: 2000000;
        big: ([] id:til n; px:n?1f; sym:n?`3);
        small: 2000 # big;
        started: .z.p;
        bounded: .tst.truncate[big; 5000];
        elapsed: .z.p - started;
        must[elapsed < 0D00:00:05;
             "bounded rendering of a 2M-row table took ",string elapsed];
        (count bounded) musteq 5000;
        marker: .tst.truncationMarker big;
        kept: 5000 - count marker;
        musteq[kept # bounded; kept # .tst.renderValueHuman small];
        musteq[(neg count marker) # bounded; marker];
    };

    should["keep real counts in a bounded canonical rendering"]{
        bounded: .tst.renderValueBounded[til 100000; 200];
        must[bounded like "0 1 2 3*"; "prefix must be the leading items"];
        bounded: .tst.renderValueBounded[100000#enlist 1 2; 200];
        must[bounded like "list[[]100000](*"; "header must state the real count, got ",40 sublist bounded];
    };

    should["return short renderings complete and unmarked at the exact limit"]{
        raw: til 10;
        full: .tst.renderValueFull raw;
        musteq[.tst.renderValueBounded[raw; count full]; full];
        must[0 < count ss[.tst.renderValueBounded[raw; -1 + count full]; "truncated"];
             "one character under the full length must truncate"];
    };

    should["render a large value identically to the unbounded form when it fits"]{
        raw: ([] a:til 50; b:50#`x; c:50#enlist "ab");
        musteq[.tst.renderValueHumanBounded[raw; 100000]; .tst.renderValueHuman raw];
        musteq[.tst.renderValueBounded[raw; 100000]; .tst.renderValueFull raw];
    };

    should["describe only the first differing keys of a large dictionary"]{
        n: 200000;
        expected: (til n)!n#0j;
        actual: @[expected; 100 + til 50; :; 1j];
        started: .z.p;
        rendered: .tst.diff[expected; actual];
        elapsed: .z.p - started;
        must[elapsed < 0D00:00:05; "dictionary diff took ",string elapsed];
        text: "\n" sv rendered;
        must[0 < count ss[text; "100: Value mismatch"]; "first differing key must be shown"];
        must[0 < count ss[text; "30 more differing keys not shown"];
             "the remainder must be counted, got: ",(-200) sublist text];
        must[(count text) < 5000; "dictionary diagnostics must stay bounded"];
    };

    should["still describe every differing key of a small dictionary"]{
        rendered: "\n" sv .tst.diff[`a`b`c!1 2 3; `a`b`c!1 9 8];
        must[(0 < count ss[rendered; "b: Value mismatch"]) and 0 < count ss[rendered; "c: Value mismatch"];
             "both differing keys must be described"];
        must[0 = count ss[rendered; "a: "]; "an equal key must not be described"];
    };

};
