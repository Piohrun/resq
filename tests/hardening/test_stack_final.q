\l lib/bootstrap.q
\l lib/init.q

/ Use explicit namespace to avoid any collisions
.tst.desc["ST"] {
  .tst.should["fails"] {
    f1:{[x] f2[x+1]};
    f2:{[x] f3[x+1]};
    f3:{[x] 'nested_error};
    f1[10];
  };
};

-1 "Running tests...";
.tst.runAll[];

results: .resq.state.results;
fail: select from results where not status=`pass;

if[count fail;
    m: first exec message from fail;
    -1 "--- CAPTURED STACK TRACE ---";
    -1 $[10h=abs type m; m; .Q.s1 m];
    -1 "----------------------------";
    / Content check
    if[all ("nested_error" in m; "f3" in m; "f2" in m; "f1" in m);
        -1 "SUCCESS: Stack trace captured correctly.";
        exit 0;
    ];
];

-1 "FAIL: Stack trace missing or incomplete.";
show results;
exit 1;
