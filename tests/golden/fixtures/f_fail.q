/ Golden fixture: one passing should + one failing musteq.
/ Default diff path is exercised (suppressAssertionDiff NOT set).
.tst.desc["fails by design"]{
  should["passes"]{ musteq[2; 2] };
  should["fails"]{ musteq[1; 2] };
 };
