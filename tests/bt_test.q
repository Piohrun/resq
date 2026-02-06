if[not `FILELOADING in key `.utl;
    f1:{[x] f2[x+1]};
    f2:{[x] f3[x+1]};
    f3:{[x] 'nested_error};

    / Trap (capture backtrace via .Q.trp)
    res: .Q.trp[{[x] f1[x]}; 10; {[err; bt]
        "Error: ", err, "\nStack Trace:\n", .Q.sbt bt
    }];

    -1 res;
    exit 0;
];
