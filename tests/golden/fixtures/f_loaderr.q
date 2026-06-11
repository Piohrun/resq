/ Golden fixture: top-level reference to an undefined name so the file
/ fails to load.
thisFunctionDoesNotExist[42];
.tst.desc["never reached"]{
  should["unreachable"]{ musteq[1; 1] };
 };
