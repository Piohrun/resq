.repro.globalA: 10;

.tst.desc["Isolation Testing 1"]{
    .tst.should["Pollute Global A";{
        .repro.globalA: 999; 
        .repro.newVar: 1;
    }];
};

.tst.desc["Isolation Testing 2"]{
    .tst.should["See clean Global A";{
         / This should PASS if deep snapshotting works between suites
         mustmatch[10; .repro.globalA];
         mustmatch[1b; not `newVar in key `.repro]; 
    }];
};
