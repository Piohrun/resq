\l lib/bootstrap.q
\l lib/init.q

.tst.desc["Manual Stack Trace Check"]{
    should["show stack trace"]{
        f1:{[x] f2[x]};
        f2:{[x] f3[x]};
        f3:{[x] 'nested_error};
        f1[10];
    };
};

/ Run it manually
-1 "Running test...";
.tst.runAll[];

/ Check results
r: .resq.state.results;
show r;

exit 0;
