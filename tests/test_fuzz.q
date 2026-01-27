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
  / 20 runs, maxFailRate 0.5. We fail if more than 10 fail.
  holds["run this"; `runs`maxFailRate!(20;0.5)]{[x]
   ran+:1;
   if[ran > 10; 1 musteq 2]; 
   };
  e:getExpec[];
  e: .tst.runners[`fuzz][e];
  e[`result] musteq `fuzzFail;
  e[`failRate] mustgt 0.49; / Should be 10/20 = 0.5 exactly
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
  all res in l;
  };

 should["return a list of elements from a typed list"]{
  l: 10 30 33 22 80 4;
  res: .tst.pickFuzz[l;40];
  all res in l;
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
 };