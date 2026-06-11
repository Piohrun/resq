/ Golden fixture: should + retry + testOnly + holds in one desc block.
/ holds body carries a real assertion so the fuzz runner records assertsRun and
/ the body passes. Default maxFailRate (0f) with strict '>' means failRate 0
/ passes, so no maxFailRate override is needed here.
.tst.desc["dsl mix"]{
  should["plain"]{ musteq[1; 1] };
  retry[2; "retried"]{ musteq[2; 2] };
  testOnly["focused"]{ musteq[3; 3] };
  holds["h"; (enlist `runs)!enlist 5]{[x] must[x~x; "ok"] };
 };
