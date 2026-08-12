/ Native file-sharding integration contracts.

\d .tst

.tst.shardtest.base:.utl.tempRoot[],"/resq_shard_test_",string .z.i;
.tst.shardtest.counter:0;
.tst.shardtest.files:{[]
  .resq.HOME,/:(
    "/tests/fixtures/sharding/shard_a.q";
    "/tests/fixtures/sharding/shard_b.q";
    "/tests/fixtures/sharding/shard_c.q";
    "/tests/fixtures/sharding/shard_d.q";
    "/tests/fixtures/sharding/shard_e.q")
 };

.tst.shardtest.run:{[index;shardCount;isolated;strict]
  .tst.shardtest.counter+:1;
  wd:.tst.shardtest.base,"/run_",string .tst.shardtest.counter;
  .utl.ensureDir wd;
  report:wd,"/report";
  stateFile:.tst.shardtest.base,"/state/last-run.json";
  qexe:first @[system;"command -v q 2>/dev/null";{enlist (getenv[`QHOME]),"/l64/q"}];
  fileArgs:" " sv .utl.shellQuote each .tst.shardtest.files[];
  cmd:"cd ",.utl.shellQuote[.resq.HOME]," && timeout -k 5 40 ",
      .utl.shellQuote[qexe]," ",.utl.shellQuote[.resq.HOME,"/resq.q"],
      " test ",fileArgs," -shard-index ",string[index],
      " -shard-count ",string[shardCount],
      $[isolated;" -isolate";""],$[strict;" -strict";""],
      " -state-file ",.utl.shellQuote[stateFile],
      " -json -quiet -outDir ",.utl.shellQuote[report],
      " < /dev/null > ",.utl.shellQuote[wd,"/out.txt"]," 2>&1; echo $?";
  statusLines:@[system;"sh -c ",.utl.shellQuote cmd;{[err]enlist "-1"}];
  code:"J"$last statusLines;
  raw:@[read0;hsym `$report,"/test-results.json";{()}];
  doc:$[count raw;.j.k "\n" sv raw;()!()];
  rows:$[(99h=type doc) and `tests in key doc;doc`tests;()];
  labels:{.tst.toString x`description} each rows;
  shard:$[(99h=type doc) and `run in key doc;doc[`run;`shard];()!()];
  selection:$[(99h=type doc) and `run in key doc;doc[`run;`selection];()!()];
  `code`labels`shard`selection!(code;labels;shard;selection)
 };

.tst.shardtest.cleanup:{[]
  expected:.utl.tempRoot[],"/resq_shard_test_",string .z.i;
  if[not .tst.shardtest.base~expected;'"refusing unsafe shard cleanup path"];
  if[.utl.pathExists .tst.shardtest.base;
    system "rm -rf -- ",.utl.shellQuote .tst.shardtest.base];
 };

\d .

.tst.desc["Native deterministic file sharding #slow"]{
  after{.tst.shardtest.cleanup[]};

  skipIf[0=count @[system;"command -v timeout 2>/dev/null";{()}];
         "shards are disjoint, complete, replayable and isolation-safe"]{
    shard0:.tst.shardtest.run[0;3;0b;1b];
    shard1:.tst.shardtest.run[1;3;0b;1b];
    shard2:.tst.shardtest.run[2;3;0b;1b];
    shard0[`code] musteq 0;
    shard1[`code] musteq 0;
    shard2[`code] musteq 0;
    count[shard0[`labels] inter shard1`labels] musteq 0;
    count[shard0[`labels] inter shard2`labels] musteq 0;
    count[shard1[`labels] inter shard2`labels] musteq 0;
    combinedLabels:distinct shard0[`labels],shard1[`labels],shard2`labels;
    sortedLabels:asc {`$x} each combinedLabels;
    expectedLabels:`A`B`C`D`E;
    sortedLabels musteq expectedLabels;

    replay:.tst.shardtest.run[1;3;0b;1b];
    replay[`labels] musteq shard1`labels;
    isolated:.tst.shardtest.run[1;3;1b;1b];
    isolated[`code] musteq 0;
    isolated[`labels] musteq shard1`labels;

    shardInfo:shard1`shard;
    indexValue:"j"$shardInfo`index;
    countValue:"j"$shardInfo`count;
    allCount:"j"$shardInfo`allFileCount;
    selectedCount:"j"$shardInfo`selectedFileCount;
    indexValue musteq 1j;
    countValue musteq 3j;
    allCount musteq 5j;
    expectedSelected:"j"$count shard1`labels;
    selectedCount musteq expectedSelected;
    shardInfo[`algorithm] musteq "sorted-index-mod-v1";
    count[shardInfo`selectedFiles] musteq count shard1`labels;
  };

  skipIf[0=count @[system;"command -v timeout 2>/dev/null";{()}];
         "a valid empty shard passes strict mode without hiding global emptiness"]{
    empty:.tst.shardtest.run[7;8;0b;1b];
    empty[`code] musteq 0;
    count[empty`labels] musteq 0;
    selectedCount:"j"$empty[`shard;`selectedFileCount];
    allCount:"j"$empty[`shard;`allFileCount];
    selectedCount musteq 0j;
    allCount musteq 5j;
  };
 };

::
