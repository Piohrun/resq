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

};
