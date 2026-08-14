.tst.desc["Fuzz expectations"]{
 before{
  / Mock state to test the runner itself
  `.tst.origExpecList mock .tst.expecList;
  .tst.expecList: ();
  `getExpec mock {last .tst.expecList};
  };
 after{
  .tst.expecList: .tst.origExpecList;
  };

 should["run the fuzz test the number of times specified"]{
  `ran mock 0;
  holds["run this"; `runs!20]{[x] ran+:1};
  e:getExpec[];
  .tst.runners[`fuzz][e];
  ran musteq 20;
  
  `ran mock 0;
  holds["run this"; `runs!40]{[x] ran+:1};
  e:getExpec[];
  .tst.runners[`fuzz][e];
  ran musteq 40;
  };

 should["fail when the percentage of failures exceeds the maximum percentage of failures"]{
  `ran mock 0;
  / 20 runs, maxFailRate 0.5. The comparison is strict (>), so we must EXCEED
  / 0.5: fail 11 of 20 (failRate 0.55 > 0.5).
  holds["run this"; `runs`maxFailRate!(20;0.5)]{[x]
   ran+:1;
   if[ran > 9; 1 musteq 2];
   };
  e:getExpec[];
  e: .tst.runners[`fuzz][e];
  e[`result] musteq `fuzzFail;
  e[`failRate] mustgt 0.5; / 11/20 = 0.55 exceeds the 0.5 cap
  };

 should["pass at exactly the max failure rate (strict comparison)"]{
  `ran mock 0;
  / 20 runs, maxFailRate 0.5, exactly 10 failures (failRate 0.5). 0.5 does NOT
  / exceed 0.5, so the block passes - the boundary is inclusive of the cap.
  holds["run this"; `runs`maxFailRate!(20;0.5)]{[x]
   ran+:1;
   if[ran > 10; 1 musteq 2];
   };
  e:getExpec[];
  e: .tst.runners[`fuzz][e];
  e[`result] musteq `pass;
  e[`failRate] musteq 0.5;
  };

 should["pass with default props when every iteration passes (maxFailRate 0)"]{
  `ran mock 0;
  / Default maxFailRate is 0f; failRate 0 must NOT exceed it under strict '>'.
  holds["always passes"; (enlist `runs)!enlist 5]{[x] ran+:1; must[x~x;"ok"] };
  e:getExpec[];
  e: .tst.runners[`fuzz][e];
  e[`result] musteq `pass;
  ran musteq 5;
  };

 should["sum assertions across generated cases without counting shrink probes"]{
  / Keep both declarations' generator shape compatible: q stores every holds
  / row in one expectation table for the surrounding desc block.
  holds["five executions"; `runs`vars!(5;{til 8})]{[x]
   x musteq x;
   };
  passing:getExpec[];
  passing:.tst.runners[`fuzz][passing];
  passing[`assertsRun] musteq 5;

  / The failing vector is shrunk by re-running the property several times.
  / Those minimization probes are diagnostics, not part of the five declared
  / property executions, so the public assertion count must remain five.
  holds["five failing executions"; `runs`vars!(5;{til 8})]{[x]
   count[x] musteq 0;
   };
  failing:getExpec[];
  failing:.tst.runners[`fuzz][failing];
  failing[`assertsRun] musteq 5;

  row:.tst.oneResultTable `suite`description`status`file`assertsRun!(
   `property;"five executions";`pass;"tests/test_fuzz.q";passing`assertsRun);
  model:.tst.withIsolatedRunState[{[payload]
   .tst.beginRunMetadata[];
   .tst.canonicalRunModel payload};enlist row];
  model[`summary;`assertionCount] musteq 5;
  };

 should["provide fuzz variables to the function"]{
  `capturedX mock (::);
  holds["run this"; `runs`vars!(1; `a`b`c!(`symbol; 1 2 3; 20#0Nd))]{[x]
   capturedX:: x;
  };
  e:getExpec[];
  .tst.runners[`fuzz][e];
  `a`b`c mustin key capturedX;
  type[capturedX`a] musteq -11h;
  capturedX[`b] mustin 1 2 3;
  count[capturedX`c] mustlt 20;
  type[capturedX`c] musteq 14h;
  };
 };

.tst.desc["The Fuzz Generator"]{
 should["return a list of fuzz values of the given type provided a symbol"]{
  res: .tst.pickFuzz[`symbol;10];
  (type res) musteq 11h;
  (count res) musteq 10;
  
  res: .tst.pickFuzz[`long;100];
  (type res) musteq 7h;
  (count res) musteq 100;
  };

 should["run a generator function once for every run requested"]{
  `runsDone mock 0;
   .tst.pickFuzz[{runsDone+:1};100];
   runsDone musteq 100;
  };

 should["return a table of distinct fuzz values given a dictionary"]{
  r: .tst.pickFuzz[`a`b`c`d!`long`float`symbol`timespan;20];
  type[r] musteq 98h;
  (count r) musteq 20;
  type[r`a] musteq 7h;
  type[r`b] musteq 9h;
  type[r`c] musteq 11h;
  type[r`d] musteq 16h;
  };

 should["return a list of elements from a general list"]{
  l: (10;`a;"foo";`a`b`c!1 2 3);
  res: .tst.pickFuzz[l;20];
  (count res) musteq 20;
  / `in` is not usable here: when the picked element is the DICT, `res in l`
  / returns a dict of booleans, not a boolean. Match each element structurally.
  must[all {[src; x] any src ~\: x}[l] each res;
       "every picked element must come from the source list"];
  };

 should["return a list of elements from a typed list"]{
  l: 10 30 33 22 80 4;
  res: .tst.pickFuzz[l;40];
  (count res) musteq 40;
  must[all res in l; "every picked element must come from the source list"];
  };

 should["return lists of fuzz values given an empty typed list"]{
  l:.tst.pickFuzz[`float$();100];
  (count l) musteq 100;
  all 9h = type each l;
  all (count each l) < .tst.fuzzListMaxLength;
  };

 should["return lists of fuzz values given a list of null values"]{
  l:.tst.pickFuzz[20#0Nd;100];
  (count l) musteq 100;
  all 14h = type each l;
  all (count each l) <= 20;
  };

 should["preserve the element type when a generated list is empty"]{
  type[.tst.privateVector[0Nd;0;42j;0j;"typed-empty"]] musteq 14h;
  type[.tst.privateVector[`symbol;0;42j;0j;"typed-empty"]] musteq 11h;
  };
 };
