if[not `FILELOADING in key `.utl;
system "l lib/bootstrap.q";
system "l lib/init.q";

.tst.desc["ST"] {[x]
  it["fails"; {
    f1:{[x] f2[x+1]};
    f2:{[x] f3[x+1]};
    f3:{[x] 'nested_error};
    f1[10];
  }];
};

-1 "Running tests...";
.tst.runAll[];

m: exec first message from .resq.state.results;
-1 "--- CAPTURED MESSAGE ---";
-1 $[10h=abs type m; m; .Q.s1 m];
-1 "--- END MESSAGE ---";

exit 0;
];
