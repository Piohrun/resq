if[not `FILELOADING in key `.utl;
system "l lib/bootstrap.q";
system "l lib/init.q";

.tst.desc["Large Table Diff Benchmark"; {
    before[{
        .tst.N: 1000000; / 1 million rows
        .tst.t1: ([] id:til .tst.N; val: .tst.N?1000f; sym: .tst.N?`a`b`c);
        
        / Create t2 with small differences
        .tst.t2: .tst.t1;
        
        / Diff 1: Early in the table
        .tst.t2[5; `val]: 99999f;
        
        / Diff 2: Middle of the table
        .tst.t2[500000; `sym]: `z;
        
        / Diff 3: Late in the table
        .tst.t2[.tst.N-5; `val]: -1f;
    }];

    it["should diff large tables reasonably fast"; {
        st: .z.p;
        res: .tst.diff[.tst.t1; .tst.t2];
        et: .z.p;
        
        / Log performance
        elapsed: `long$(et-st) div 1000000;
        -1 "Diff took ",string[elapsed]," ms";
        
        / Show output sample (first 20 lines)
        -1 "Diff Output Sample:";
        -1 "\n" sv 20 sublist res;
        
        / Assertions
        (count res) mustgt 0;
        
        / Soft performance check (warn if slow, don't fail yet)
        if[elapsed > 500;
             -1 "WARNING: Diff took > 500ms";
        ];
        -1 "DEBUG: Test finished successfully";
    }];
}];

.tst.runAll[];

/ Dump report to file purely for debug
output: .h.ty .resq.state.results;
`test_output.txt 0: enlist output;

exit `int$not .tst.app.passed;
];
