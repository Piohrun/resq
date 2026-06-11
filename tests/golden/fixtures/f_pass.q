/ Golden fixture: one desc, two passing shoulds.
.tst.desc["passing suite"]{
  should["adds"]{ musteq[1+1; 2] };
  should["matches"]{ must[1b; "true"] };
 };
