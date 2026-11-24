.tst.desc["Test Loading"]{
 before{
  / Build base path as string from tstPath
  tstPathStr: .utl.pathToString .tst.tstPath;
  parts: "/" vs tstPathStr;
  `basePath mock "/" sv (-1 _ parts),enlist "nestedFiles";
  `pathList mock `foo`bar`baz! (basePath,"/foo"; basePath,"/bar"; basePath,"/baz");
  / Helper to get filename from a path string
  `getFilename mock {last "/" vs x};
 };
 should["recursively find all files matching an extension in a path"]{
  / suffixMatch returns list of string paths - extract filenames
  files: .tst.suffixMatch[".q";pathList[`foo]];
  filenames: asc getFilename each files;
  (asc ("a.q";"b.q";"c.q";"d.q";"d.q")) mustmatch filenames;

  filesK: .tst.suffixMatch[".k";pathList[`foo]];
  filenamesK: asc getFilename each filesK;
  (enlist "e.k") mustmatch filenamesK;
  };
 should["filter directory discovery to named test files"]{
  files: .tst.findTests[value pathList];
  0 musteq count files;
  };
 should["return a q file given a q file"]{
  path: pathList[`foo],"/one/a.q"; / String path to known file
  result: .tst.findTests[path];
  / findTests should return a list with the single file
  (enlist path) mustmatch result;
  };
 should["honour a custom testFilePatterns configuration"]{
  / Make two files in a temp dir: one matches the new pattern, one doesn't.
  d: .tst.tempFile "";
  .utl.ensureDir d;
  goodPath: d, "/widget_spec.q";
  badPath:  d, "/helper.q";
  (hsym `$goodPath) 0: enlist ".tst.desc[\"x\"]{should[\"y\"]{1 musteq 1}}";
  (hsym `$badPath)  0: enlist "/ not a spec file";
  / Spec-scope cleanup so the dir is removed even though hdel on a non-empty
  / directory would fail. Delete the files first, then the directory.
  .tst.registerSpecCleanup[{[paths]
      @[hdel; hsym `$paths 0; {}];
      @[hdel; hsym `$paths 1; {}];
      @[hdel; hsym `$paths 2; {}];
    }; enlist (goodPath; badPath; d)];

  / Default patterns: neither file matches "test_*" or "*_test", expect 0.
  prevPatterns: @[get; `.resq.config.testFilePatterns; {()}];
  (count .tst.findTests d) musteq 0;

  / Custom pattern picks up the spec file.
  .resq.config.testFilePatterns: enlist "*_spec.q";
  discovered: .tst.findTests d;
  (count discovered) musteq 1;
  must[any discovered like "*widget_spec.q"; "should discover *_spec.q"];

  / Restore.
  $[(::) ~ prevPatterns; ![`.resq.config; (); 0b; enlist `testFilePatterns]; .resq.config.testFilePatterns: prevPatterns];
  };
 };

.tst.desc["require fails when the file cannot be loaded"]{
  before{
    root: .utl.tempRoot[], "/resq_require_", string[.z.i], "_", string `long$.z.p;
    system "mkdir -p ", .utl.shellQuote root, "/src";
    (hsym `$root, "/src/ok.q") 0: enlist ".reqprobe.ok: 1 + @[get; `.reqprobe.ok; 0];";
    (hsym `$root, "/src/throws.q") 0: (".reqprobe.partial: 1b;"; "'\"licence check failed\";"; ".reqprobe.late: 1b;");
    `.tst.testState.reqRoot set root;
    .tst.registerCleanup[{[d] @[system; "rm -rf ", .utl.shellQuote d; {}]; @[system; "x .reqprobe"; {}]}; enlist root];
  };
  should["signal, naming the file and the error it raised"]{
    target: .tst.testState.reqRoot, "/src/throws.q";
    err: @[{.utl.require x; ""}; target; {x}];
    (0 < count err ss "failed to load ") musteq 1b;
    (0 < count err ss "throws.q") musteq 1b;
    (0 < count err ss "licence check failed") musteq 1b;
  };
  should["signal for a file that does not exist"]{
    err: @[{.utl.require x; ""}; .tst.testState.reqRoot, "/src/missing.q"; {x}];
    (0 < count err ss "failed to load ") musteq 1b;
  };
  should["load a path that starts with ./ or ../"]{
    system "cd ", .tst.testState.reqRoot;
    .utl.require "./src/ok.q";
    .reqprobe.ok musteq 1;
    system "cd src";
    .utl.require "../src/../src/ok.q";
    .reqprobe.ok musteq 2;
  };
  should["still ignore a namespace-like name"]{
    (@[{.utl.require x; `ignored}; ".app.module"; {`signalled}]) musteq `ignored;
  };
 };
