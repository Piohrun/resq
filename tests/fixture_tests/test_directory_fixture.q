.tst.testState.dirfix.start: system "cd";
.tst.desc["Loading Directory Fixtures"]{
 before{
  `notAFixture mock 1 _ string ` sv (-1 _ ` vs .tst.tstPath),`fixtures`not_a_fixture;
  `emptyDir mock 1 _ string ` sv (-1 _ ` vs .tst.tstPath),`fixtures`emptyDir;
  };
 / Several tests load a database with \l themselves. That leaves its tables,
 / and q's working directory inside it, for the next test, so each test saw
 / what the one before it had loaded; under -random-order they failed. Each
 / test now ends with no database loaded.
 after{
  .tst.restoreDir[];
  system "cd ", .tst.testState.dirfix.start;
  {[ns] loaded: (tables ns) inter `mytable`sometable`othertable;
        if[count loaded; ![ns; (); 0b; loaded]]} each distinct (`.; .tst.context);
  };
 should["clear any loaded partition"]{
  system "l ",notAFixture; 
  `mytable mustin tables `;
  fixture `a_fixture;
  `mytable mustnin tables `;
  };
 should["only load one directory fixture at a time"]{
  fixture `a_fixture;
  `sometable mustin tables `;
  fixture `other_fixture;
  `sometable mustnin tables `;
  `othertable mustin tables `;
  .tst.restoreDir[];         / This is a limitation of the fixture system: If a directory is loaded through the normal manner without first restoring (IE: Cleaningup the fixture) the fixture that was loaded will left hanging around.  Moral of the story: Don't load directories in Specification objects that use fixtures
  };
 should["allow you to restore to the previously loaded partition"]{
  system "l ", notAFixture;
  fixture `a_fixture;
  .tst.restoreDir[];
  `mytable mustin tables `;
  };
 should["leave loaded partitions untouched if restore is called twice after loading a directory fixture"]{
  system "l ", notAFixture;
  fixture `a_fixture;
  .tst.restoreDir[];
  .tst.restoreDir[];
  `mytable mustin tables `;
  `othertable mustnin tables `;
  };
 should["load directory fixtures not containing partitions"]{
  origQ: .Q;
  // Newer Q versions will load hidden files
  ep:` sv (hsym `$emptyDir;`.empty);
  / Ensure the sentinel exists before deleting it
  if[() ~ key ep; ep 0: enlist ""];
  hdel ep;
  / Remove any stray coverage artifacts from prior runs
  covHtml:` sv (hsym `$emptyDir;`coverage.html);
  covLcov:` sv (hsym `$emptyDir;`coverage.lcov);
  covState:` sv (hsym `$emptyDir;`coverage_state.txt);
  if[not () ~ key covHtml; hdel covHtml];
  if[not () ~ key covLcov; hdel covLcov];
  if[not () ~ key covState; hdel covState];
  // Q doesn't clean up all internal variables between each file load. Simulate no previous db's having been loaded
  system "l ", emptyDir;
  .Q:`pv`pt`pf _ .Q;
  mustnotthrow[();{fixture `no_part_fixture}];
  @[`.Q; `pv`pt`pf; :; origQ[`pv`pt`pf]];
  ep set ()
  };
};

/ restoreDir reloads the database a directory fixture displaced, when there
/ was one. The check joined the directory and its table names right to left:
/ "/" became one of the paths it looked at, and it always said yes. With a
/ table in the test's namespace, the project directory was loaded as a
/ database, which runs the q scripts it finds there.
.tst.desc["what counts as a database to put back after a directory fixture"]{
 before{
  `dbRoot mock .utl.tempRoot[], "/resq_dirfix_db_", string[.z.i], "_", string `long$.z.p;
  .utl.ensureDir dbRoot, "/src";
  .tst.registerCleanup[{[d] @[system; "rm -rf -- ", .utl.shellQuote d; {}]}; enlist dbRoot];
  `.tst.savedDir mock `directory`vars`context`tables!(dbRoot;(`,())!(),(::);`.;`trade`quote);
  };
 should["not take a project directory for one because a test holds a table"]{
  .tst.savedDirHasDiskTables[] musteq 0b;
  };
 should["take a directory with a splayed table of that name"]{
  .utl.ensureDir dbRoot, "/quote";
  .tst.savedDirHasDiskTables[] musteq 1b;
  };
 should["take a partitioned database"]{
  .utl.ensureDir dbRoot, "/2024.01.02/trade";
  .tst.savedDirHasDiskTables[] musteq 1b;
  };
 should["take a database with a par.txt"]{
  (hsym `$dbRoot, "/par.txt") 0: enlist "/somewhere";
  .tst.savedDirHasDiskTables[] musteq 1b;
  };
 should["not take a partition-like directory without the table"]{
  .utl.ensureDir dbRoot, "/2024.01.02/other";
  .tst.savedDirHasDiskTables[] musteq 0b;
  (.tst.isPartitionName each ("2024.01.02"; "2024.01"; "2024"; "src"; "")) musteq 11100b;
  };
};

