.tst.desc["Advanced Mocking Features"]{
 before{
  .tst.dummyFunc: {[x] x*2};
  .tst.dummyDict: `a`b`c!1 2 3;
  .tst.dummySeqFunc: {[x] x};
  };
 should["support mockSequence for sequential returns"]{
  .tst.mockSequence[`.tst.dummySeqFunc; (10; 20)];
  r1: .tst.dummySeqFunc[1];
  r1 musteq 10;
  r2: .tst.dummySeqFunc[2];
  r2 musteq 20;
  mustthrow["*exhausted*"; { .tst.dummySeqFunc[3] }];
  };
 should["support partialMock for dictionaries"]{
  .tst.partialMock[`.tst.dummyDict; enlist[`b]!enlist 99];
  d: .tst.dummyDict;
  d[`a] musteq 1;
  d[`b] musteq 99;
  d[`c] musteq 3;
  };
 should["support mustHaveBeenCalledWith spy assertion"]{
  .tst.spy[`.tst.dummyFunc; (::)];
  .tst.dummyFunc[5];
  `.tst.dummyFunc mustHaveBeenCalledWith (enlist 5);
  };
 should["handle multi-arg spies with mustHaveBeenCalledWith"]{
  .tst.multiArgFunc: {[a;b] a+b};
  .tst.spy[`.tst.multiArgFunc; (::)];
  .tst.multiArgFunc[10; 20];
  `.tst.multiArgFunc mustHaveBeenCalledWith (10; 20);
  };
 };

::
