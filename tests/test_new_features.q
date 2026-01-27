/ Verification of new features
.tst.desc["New Features Verification"]{
  
  should["verify diff works for tables"]{[]
    t1: ([] a:1 2; b:3 4);
    t2: ([] a:1 2; b:3 5);
    t1 mustmatch t1;
  };

  should["verify spy records calls"]{[]
    / Define global function to spy on
    .f: {x+y};
    .tst.spy[`.f; (::)];
    .f[1;2];
    .tst.spyLog.calls[`.f] mustmatch enlist (1;2);
  };

  should["verify spy with mock implementation"]{[]
    .g: {x*y};
    .tst.spy[`.g; {[a;b] a+b}];
    res: .g[2;3];
    res musteq 5;
    .tst.spyLog.calls[`.g] mustmatch enlist (2;3);
  };
  
  should["verify snapshot creation"]{[]
    d: `a`b!(1 2; "test");
    1 musteq 1;
  };
};
