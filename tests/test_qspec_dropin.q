/ ============================================================================
/ qspec drop-in behaviours found by running real third-party qspec suites
/ (asatirahul/cryptoq, nugend/qutil, exxeleron/enterprise-components) through
/ bin/qspec next to upstream qspec:
/ .
/ - qspec's loader takes every .q file under a directory;
/ - `qspec --junit tests > results.xml` captures the XML report from stdout;
/ - qutil (which qspec requires) owns .utl.require and its loader state;
/ - suites keep helpers in .tst, whose resQ namesake must not be clobbered.
/ .
/ Subprocess-based where the behaviour is a launcher or process contract.
/ ============================================================================
.tst.testState.dropin.canQ: 0 < count @[system; "which q 2>/dev/null"; {()}];

.tst.testState.dropin.stateFlags:{[wd]
  " -state-file ",.utl.shellQuote[wd,"/state.json"],
  " -flake-history ",.utl.shellQuote[wd,"/flake.json"],
  " -quarantine-file ",.utl.shellQuote[wd,"/quarantine.json"],
  " -flake-proposal-file ",.utl.shellQuote[wd,"/proposals.json"]
 };

/ Write files (name!lines) into a fresh directory, run `command` from it with
/ stdout and stderr captured separately, and return code/out/err.
.tst.testState.dropin.run:{[files;command]
  wd: .utl.tempRoot[], "/resq_dropin_", string[.z.i], "_", string `long$.z.p;
  .utl.ensureDir wd, "/tests";
  {[wd;name;lines] (hsym `$wd,"/",name) 0: lines}[wd]'[key files; value files];
  cmd: "cd ", (.utl.shellQuote wd), " && ", command[wd],
       " > out.txt 2> err.txt; echo $?";
  code: "J"$ last @[system; "sh -c ", .utl.shellQuote cmd; {[e] enlist "-1"}];
  out: @[read0; hsym `$wd, "/out.txt"; {()}];
  err: @[read0; hsym `$wd, "/err.txt"; {()}];
  system "rm -rf -- ", .utl.shellQuote wd;
  `code`out`err!(code; out; err)
 };

.tst.testState.dropin.passingSpec: (
  ".tst.desc[\"pricing\"]{";
  "  should[\"price\"]{ 3 musteq 1+2 };";
  "  };");

.tst.desc["qspec drop-in launcher behaviours"]{
  skipIf[not .tst.testState.dropin.canQ;
         "bin/qspec loads a directory's .q files whatever their names"]{
    launcher: .utl.shellQuote .resq.HOME, "/bin/qspec";
    r: .tst.testState.dropin.run[(enlist "tests/pricing.q")!enlist .tst.testState.dropin.passingSpec;
      {[l;wd] "timeout 60 ", l, " tests -strict", .tst.testState.dropin.stateFlags wd}[launcher]];
    must[0 = r`code; "an unprefixed qspec file must be found, got exit ", string[r`code], "\n", "\n" sv r`out];
  };

  skipIf[not .tst.testState.dropin.canQ;
         "bin/qspec shares a helper file's root definitions with later files"]{
    / qspec loads every file into the root namespace and does not treat a
    / spec-free helper as an error; -strict keeps judging the specs.
    launcher: .utl.shellQuote .resq.HOME, "/bin/qspec";
    helper: ("mkx:{x*10};"; ".app.cfg:`ok;");
    spec: (
      ".tst.desc[\"uses helper\"]{";
      "  should[\"see a root helper\"]{ 20 musteq mkx 2 };";
      "  should[\"see a namespaced helper\"]{ `ok musteq .app.cfg };";
      "  };");
    r: .tst.testState.dropin.run[("tests/aa_helpers.q";"tests/bb_spec.q")!(helper;spec);
      {[l;wd] "timeout 60 ", l, " tests -strict", .tst.testState.dropin.stateFlags wd}[launcher]];
    must[0 = r`code; "helper definitions must reach later files, got exit ", string[r`code], "\n", "\n" sv r`out];
    must[not any r[`out] like "*added no tests*"; "a helper file is not a warning on the qspec path"];
  };

  skipIf[not .tst.testState.dropin.canQ;
         "resq test explains why an unprefixed tree found nothing"]{
    resq: .utl.shellQuote .resq.HOME, "/bin/resq";
    r: .tst.testState.dropin.run[(enlist "tests/pricing.q")!enlist .tst.testState.dropin.passingSpec;
      {[l;wd] "timeout 60 ", l, " test tests", .tst.testState.dropin.stateFlags wd}[resq]];
    r[`code] musteq 3;
    must[any r[`out] like "*did not match the test file patterns*"; "the warning must say why"];
    must[any r[`out] like "*bin/qspec*"; "the warning must name the qspec launcher"];
  };

  skipIf[not .tst.testState.dropin.canQ;
         "qspec --junit prints the XML report on stdout and the console on stderr"]{
    launcher: .utl.shellQuote .resq.HOME, "/bin/qspec";
    r: .tst.testState.dropin.run[(enlist "tests/pricing.q")!enlist .tst.testState.dropin.passingSpec;
      {[l;wd] "timeout 60 ", l, " --junit tests", .tst.testState.dropin.stateFlags wd}[launcher]];
    r[`code] musteq 0;
    must[(first r`out) like "<?xml*"; "stdout must be the XML report, got: ", first r`out];
    must[any (r[`out] like "*<testcase*") and r[`out] like "*price*"; "the report must contain the test"];
    / qspec's testcase naming, so CI test history continues across the switch.
    must[any r[`out] like "*<testcase name=\"should price\"*"; "testcases must carry qspec's names"];
    must[not any r[`out] like "*classname=*"; "qspec writes no classname"];
    must[not any r[`out] like "*SUMMARY*"; "console output must not pollute the XML"];
    must[any r[`err] like "*SUMMARY*"; "console output moves to stderr"];
  };

  skipIf[not .tst.testState.dropin.canQ;
         "qutil loaded before resQ keeps .utl.require for packages and its loader state"]{
    / A minimal stand-in for qutil's bootstrap, installed the way qutil's README
    / says: from q's startup file (QINIT here, q.q in a real install).
    fakeQutil: (
      ".utl.requireVH:(enlist `)!enlist (::);";
      ".utl.PKGLOADING:\"\";";
      ".utl.FILELOADING:`;";
      ".utl.DEBUG:0b;";
      ".fakeQutil.required:();";
      ".utl.require:{[x] .fakeQutil.required,:enlist x; if[x~\"mypkg\"; `.mypkg.add set {x+y}];";
      "  if[x~\"qutil/opts.q\"; `.utl.addOpt set {[f;t;h] 1b}]; 1b};");
    spec: (
      ".utl.require \"mypkg\";";
      ".tst.desc[\"qutil package\"]{";
      "  should[\"load through qutil\"]{";
      "    3 musteq .mypkg.add[1;2];";
      "    must[.utl.PKGLOADING~\"\"; \"qutil's PKGLOADING must be untouched\"];";
      "    must[.fakeQutil.required~(\"qutil/opts.q\";\"mypkg\"); \"qutil must receive the package names\"];";
      "    };";
      "  should[\"see qutil's option parser preloaded, as qspec's spec.q does\"]{";
      "    must[100h=type .utl.addOpt; \".utl.addOpt must be defined\"];";
      "    };";
      "  };");
    launcher: .utl.shellQuote .resq.HOME, "/bin/qspec";
    r: .tst.testState.dropin.run[("qutil.q";"tests/test_pkg.q")!(fakeQutil;spec);
      {[l;wd] "QINIT=", (.utl.shellQuote wd, "/qutil.q"), " timeout 60 ", l, " tests -strict",
        .tst.testState.dropin.stateFlags wd}[launcher]];
    must[0 = r`code; "qutil coexistence failed, exit ", string[r`code], "\n", "\n" sv r`out];
  };
 };

.tst.desc["framework override guard"]{
  should["restore a clobbered framework function and fail the file by name"]{
    `.tst.app.loadErrors mock flip `file`error`type!(`symbol$(); (); `symbol$());
    `.tst.dropinProbeFn mock {[x] `framework};
    `.tst.frameworkFunctionSnapshot mock (enlist `.tst.dropinProbeFn)!enlist .tst.dropinProbeFn;
    .tst.dropinProbeFn: {[x] `userHelper};
    .tst.restoreFrameworkOverrides["tests/helpers.q";enlist ".tst.dropinProbeFn:{[x] `userHelper};"];
    (.tst.dropinProbeFn 0) musteq `framework;
    (count .tst.app.loadErrors) musteq 1;
    (first .tst.app.loadErrors`type) musteq `frameworkOverride;
    message: first .tst.app.loadErrors`error;
    message mustlike "*.tst.dropinProbeFn*";
    message mustlike "*rename the helper*";
  };

  should["leave an untouched framework alone"]{
    `.tst.app.loadErrors mock flip `file`error`type!(`symbol$(); (); `symbol$());
    `.tst.dropinProbeFn mock {[x] `framework};
    `.tst.frameworkFunctionSnapshot mock (enlist `.tst.dropinProbeFn)!enlist .tst.dropinProbeFn;
    .tst.restoreFrameworkOverrides["tests/plain.q";enlist "x:1;"];
    (count .tst.app.loadErrors) musteq 0;
  };

  should["ignore framework changes the file did not assign itself"]{
    `.tst.app.loadErrors mock flip `file`error`type!(`symbol$(); (); `symbol$());
    `.tst.dropinProbeFn mock {[x] `framework};
    `.tst.frameworkFunctionSnapshot mock (enlist `.tst.dropinProbeFn)!enlist .tst.dropinProbeFn;
    .tst.dropinProbeFn: {[x] `swappedByFramework};
    .tst.restoreFrameworkOverrides["tests/plain.q";("beforeAll{ 1 };";"s:\".tst.dropinProbeFn:1\";")];
    (count .tst.app.loadErrors) musteq 0;
    (.tst.dropinProbeFn 0) musteq `swappedByFramework;
  };

  should["find .tst assignments in code only"]{
    src: (".tst.helper:{x};";"/ .tst.inComment:1";"s:\".tst.inString:1\";";"  .tst.amended::2;";".tst.called[1];";"x..tst.no:1");
    (asc .tst.sourceAssignedTstNames src) musteq `.tst.amended`.tst.helper;
  };
 };

.tst.desc["qspec helper surface"]{
  should["resolve .tst.testFilePath next to the running test file"]{
    / qutil's own suite reads its config fixtures this way.
    (.tst.testFilePath `configs`normal) musteq hsym `$.resq.HOME,"/tests/configs/normal";
    (.tst.testFilePath enlist `x.q) musteq hsym `$.resq.HOME,"/tests/x.q";
  };
 };

/ Directory fixtures load into root context on the qspec path, which exposed
/ removeDirVars' old x^findDirVars[] fill ('length on unequal lists).
.tst.desc["directory fixture variable cleanup"]{
  should["treat ` as the loaded vars and never clear the root namespace"]{
    `..resqDirVarSentinel set 42;
    `.tst.findDirVars mock {`symbol$()};
    .tst.removeDirVars `;
    (get `..resqDirVarSentinel) musteq 42;
    .tst.removeDirVars `resqDirVarSentinel`resqDirVarAbsent;
    `resqDirVarSentinel mustnin key `.;
  };
 };
