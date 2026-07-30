/ Dependency graph parsing, rebuild, and traversal authority regressions.

.tst.dependencyHardening.capture:{[]
  .tst.captureNamedLifecycle
    (`.tst.depGraph`.tst.dependencies),
    (`.tst.MAX_DEPENDENCY_FILES`.tst.MAX_DEPENDENCY_SOURCE_BYTES),
    (`.tst.MAX_DEPENDENCY_TOTAL_SOURCE_BYTES,
      `.tst.MAX_DEPENDENCY_SOURCE_LINES,
      `.tst.MAX_DEPENDENCY_DIRECTIVES),
    (`.tst.MAX_DEPENDENCY_EDGES,
      `.tst.MAX_DEPENDENCY_PATH_BYTES,
      `.tst.MAX_DEPENDENCY_MATCH_WORK),
    enlist `.tst.MAX_DEPENDENCY_WALK
 };

.tst.desc["dependency graph hardening: parsing and transactions"]{
  before{
    .tst.testState.dependencyHardeningState:
      .tst.dependencyHardening.capture[];
  };
  after{
    .tst.restoreNamedLifecycle
      .tst.testState.dependencyHardeningState;
    ![`.tst.testState;();0b;enlist `dependencyHardeningState];
  };

  should["ignore require text inside strings and inline comments"]{
    source:.tst.tempFile ".q";
    (.utl.pathToHsym source)0:(
      "text:\".utl.require \\\"string-only.q\\\"\";";
      "x:1; / .utl.require \"comment-only.q\"";
      "if[x like \"*.utl.require*\"];";
      ".utl.require \"real.q\";");

    (.tst.parseLoadDirectives source) mustmatch
      enlist `$"real.q";
  };

  should["accept simple require forms without treating data as calls"]{
    source:.tst.tempFile ".q";
    (.utl.pathToHsym source)0:(
      "data:(`.utl.require;\"symbol-data.q\");";
      ".utl.require:\"assignment.q\";";
      ".utl.require helper \"derived-call.q\";";
      ".utl.require[\"extra-arg.q\";\"ignored.q\"];";
      ".utl.require[\"bracket.q\"];";
      ".utl.require (\"parenthesized.q\");";
      ".utl.require packageRoot,\"tail.q\";";
      ".utl.require \"first.q\"; .utl.require \"second.q\";");

    records:.tst.parseDependencyRecords source;

    records[`target] mustmatch
      ("bracket.q";"parenthesized.q";"tail.q";"first.q";"second.q");
    records[`tail] mustmatch 00100b;
  };

  should["accept wrapped and multiline package require forms"]{
    source:.tst.tempFile ".q";
    (.utl.pathToHsym source)0:(
      ".utl.require[.utl.PKGLOADING,\"/wrapped-bracket.q\"];";
      ".utl.require(.utl.PKGLOADING,\"/wrapped-paren.q\");";
      ".utl.require[";
      "  .utl.PKGLOADING,";
      "  \"/multiline.q\"];");

    records:.tst.parseDependencyRecords source;

    records[`target] mustmatch
      ("/wrapped-bracket.q";
       "/wrapped-paren.q";
       "/multiline.q");
    records[`tail] mustmatch 111b;
    records[`kind] mustmatch `require`require`require;
  };

  should["respect q statement and commented continuation boundaries"]{
    source:.tst.tempFile ".q";
    (.utl.pathToHsym source)0:(
      "f:{.utl.require \"child.q\"};";
      ".utl.require";
      "\"ghost.q\";";
      ".utl.require[";
      " / an ordinary q line comment";
      " .utl.PKGLOADING,";
      " \"/real.q\"];";
      "g:{";
      "  .utl.require";
      "  \"nested-child.q\"";
      " };");

    records:.tst.parseDependencyRecords source;

    records[`target] mustmatch
      ("child.q";"/real.q";"nested-child.q");
    records[`tail] mustmatch
      010b;
    records[`kind] mustmatch
      `require`require`require;
  };

  should["reject control and unsupported dependency escapes"]{
    slash:"\\";
    quote:"\"";
    supportedSlash:
      quote,"a",slash,slash,"b.q",quote;
    supportedQuote:
      quote,"a",slash,quote,"b.q",quote;
    slashLiteral:.tst.dependencyQuotedLiteral[
      supportedSlash;
      0];
    quoteLiteral:.tst.dependencyQuotedLiteral[
      supportedQuote;
      0];

    slashLiteral[`ok] musteq 1b;
    slashLiteral[`text] mustmatch
      "a",slash,"b.q";
    quoteLiteral[`ok] musteq 1b;
    quoteLiteral[`text] mustmatch
      "a",quote,"b.q";

    badEscapes:("n";"r";"t";"060");
    outcomes:{
      raw:y,"a",x,z,"b.q",y;
      .utl.attempt[
        .tst.dependencyQuotedLiteral;
        (raw;0)]
      }[;quote;slash] each badEscapes;
    (first each outcomes) mustmatch
      (count badEscapes)#0b;

    source:.tst.tempFile ".q";
    controlLiteral:
      quote,"a",slash,"n","b.q",quote;
    (.utl.pathToHsym source)0:enlist
      ".utl.require ",controlLiteral,";";
    parseOutcome:.utl.attempt[
      .tst.parseDependencyRecords;
      enlist source];

    (first parseOutcome) musteq 0b;
  };

  should["preserve an absolute dependency target"]{
    target:"/definitely-missing/resq-absolute-dependency.q";
    resolved:.tst.resolveDepTarget[
      `$"/tmp/resq-requirer/main.q";
      `$target];

    resolved musteq `$target;
  };

  should["distinguish direct absolute paths from concatenated tails"]{
    source:.tst.tempFile ".q";
    (.utl.pathToHsym source)0:(
      "\\l /absolute/load.q";
      ".utl.require \"/absolute/direct.q\";";
      ".utl.require .utl.PKGLOADING,\"/tail.q\";");
    records:.tst.parseDependencyRecords source;
    requiring:"/project/lib/requirer.q";

    records[`target] mustmatch
      ("/absolute/load.q";
       "/absolute/direct.q";
       "/tail.q");
    records[`tail] mustmatch 001b;
    records[`kind] mustmatch `load`require`require;
    (.tst.resolveDepTargetRecord[
      requiring;
      records[0;`target];
      records[0;`tail]]) musteq
        `$"/absolute/load.q";
    (.tst.resolveDepTargetRecord[
      requiring;
      records[2;`target];
      records[2;`tail]]) musteq
        `$"/project/lib/tail.q";
  };

  should["resolve discovered relative loads from CWD before QHOME"]{
    (.tst.resolveLoadTargetWith[
      0b;
      "/cwd";
      "/qhome";
      "child.q";
      (`$"/cwd/child.q";`$"/qhome/child.q")]) musteq
        `$"/cwd/child.q";
  };

  should["fall back to a discovered QHOME load without probing CWD"]{
    cwd:"/dependency-fallback-cwd";
    qhome:"/dependency-fallback-qhome";
    target:"child.q";
    cwdCandidate:cwd,"/",target;
    qhomeCandidate:qhome,"/",target;
    fileSet:.tst.dependencyFileSet[
      enlist qhomeCandidate;
      0b];
    symbolsBefore:.Q.w[]`syms;
    registryCountBefore:count .utl.pathSymbolTexts;
    registryBytesBefore:.utl.pathSymbolBytes;

    resolvedText:.tst.resolveLoadTargetTextWith[
      fileSet;
      cwd;
      qhome;
      target];

    resolvedText mustmatch qhomeCandidate;
    .Q.w[][`syms] musteq symbolsBefore;
    (count .utl.pathSymbolTexts) musteq registryCountBefore;
    .utl.pathSymbolBytes musteq registryBytesBefore;
    must[
      not any cwdCandidate~/:.utl.pathSymbolTexts;
      "rejected CWD load candidate was interned"];
  };

  should["do not use QHOME for a load path with components"]{
    (.tst.resolveLoadTargetWith[
      0b;
      "/cwd";
      "/qhome";
      "pkg/child.q";
      enlist `$"/qhome/pkg/child.q"]) musteq
        `$"/cwd/pkg/child.q";

    (.tst.resolveLoadTargetWith[
      0b;
      "/cwd";
      "/qhome";
      "./child.q";
      enlist `$"/qhome/child.q"]) musteq
        `$"/cwd/child.q";
  };

  should["retain discovered Windows spelling and reject forged aliases"]{
    qhomeFile:"C:/QHome/Child.q";
    suffixFile:"C:/Lib/Target.q";
    fileSet:.tst.dependencyFileSet[
      (qhomeFile;suffixFile);
      1b];

    (.tst.resolveLoadTargetTextWith[
      fileSet;
      "C:/Other";
      "c:/qhome";
      "child.q"]) mustmatch
        qhomeFile;
    (.tst.resolveLoadTargetTextWith[
      fileSet;
      "C:/Other";
      "c:/qhome";
      "c:/qhome/child.q"]) mustmatch
        qhomeFile;
    (.tst.resolveDepTargetFromFileSetText[
      "C:/Other/TARGET.Q";
      "/TARGET.Q";
      1b;
      fileSet]) mustmatch
        suffixFile;

    aliasOutcome:.utl.attempt[
      .tst.dependencyFileSet;
      (("C:/Alias.q";"c:/alias.q");1b)];
    (first aliasOutcome) musteq 0b;

    forged:
      `files`index`paths`windows!(
        enlist "C:/Safe.q";
        enlist "c:/evil.q";
        enlist "C:/Safe.q";
        1b);
    forgedOutcome:.utl.attempt[
      .tst.resolveLoadTargetTextWith;
      (forged;"C:/";"";"evil.q")];
    (first forgedOutcome) musteq 0b;
  };

  should["reject an ambiguous concatenated target tail"]{
    outcome:.utl.attempt[
      .tst.resolveDepTargetRecord;
      (`$"/project/lib/requirer.q";
       `$"//ambiguous.q";
       1b)];

    (first outcome) musteq 0b;
  };

  should["reject an ambiguous discovered target suffix"]{
    outcome:.utl.attempt[
      .tst.resolveDepTargetFromFiles;
      ("/project/src/requirer.q";
       "/shared.q";
       1b;
       ("/first/shared.q";"/second/shared.q"))];

    (first outcome) musteq 0b;
  };

  should["bound discovered suffix matching before publication"]{
    seed:.tst.tempFile ".seed";
    root:.tst.static.getDir seed;
    sourceDir:.utl.normalizePath root,"/src";
    targetDir:.utl.normalizePath root,"/lib";
    .utl.ensureDir sourceDir;
    .utl.ensureDir targetDir;
    source:.utl.normalizePath sourceDir,"/requirer.q";
    target:.utl.normalizePath targetDir,"/target.q";
    (.utl.pathToHsym source)0:enlist
      ".utl.require packageRoot,\"/lib/target.q\";";
    (.utl.pathToHsym target)0:enlist "targetValue:1";
    oldGraph:(enlist `dependency)!enlist enlist `consumer;
    oldDependencies:(enlist `consumer)!enlist enlist `dependency;
    .tst.depGraph:oldGraph;
    .tst.dependencies:oldDependencies;
    .tst.MAX_DEPENDENCY_MATCH_WORK:1;

    outcome:.utl.attempt[
      .tst.rebuildGraph;
      enlist enlist root];

    (first outcome) musteq 0b;
    .tst.depGraph mustmatch oldGraph;
    .tst.dependencies mustmatch oldDependencies;
  };

  should["avoid duplicate reverse edges across repeated directory scans"]{
    seed:.tst.tempFile ".seed";
    root:.tst.static.getDir seed;
    a:.utl.normalizePath root,"/a.q";
    b:.utl.normalizePath root,"/b.q";
    (.utl.pathToHsym a)0:enlist ".utl.require \"b.q\"";
    (.utl.pathToHsym b)0:enlist "bValue:1";
    .tst.depGraph:()!();
    .tst.dependencies:()!();

    .tst.scanDirectory root;
    .tst.scanDirectory root;
    dependents:.tst.depGraph `$b;

    (count dependents) musteq 1;
    (first dependents) musteq `$a;
  };

  should["resolve a discovered package tail outside the requiring directory"]{
    coverage:`$.utl.PKGLOADING,"/coverage.q";
    runner:`$.utl.PKGLOADING,"/runner.q";
    runnerRecords:.tst.parseDependencyRecords runner;
    runnerRecords[`target] mustmatch enlist "/lib/coverage.q";
    runnerRecords[`tail] mustmatch enlist 1b;
    (.tst.resolveDepTargetFromFiles[
      runner;
      "/lib/coverage.q";
      1b;
      string each (coverage;runner)]) musteq coverage;
    .tst.rebuildGraph enlist .utl.PKGLOADING;

    (.tst.dependencies runner) mustmatch enlist coverage;
    must[runner in .tst.depGraph coverage;
      "forward and reverse dependency graphs diverged"];
  };

  should["remove stale files when a directory is rescanned"]{
    seed:.tst.tempFile ".seed";
    root:.tst.static.getDir seed;
    a:.utl.normalizePath root,"/a.q";
    b:.utl.normalizePath root,"/b.q";
    (.utl.pathToHsym a)0:enlist ".utl.require \"b.q\"";
    (.utl.pathToHsym b)0:enlist "bValue:1";
    .tst.depGraph:()!();
    .tst.dependencies:()!();
    .tst.scanDirectory root;
    hdel .utl.pathToHsym a;

    .tst.scanDirectory root;

    must[
      not (`$a) in key .tst.dependencies;
      "rescan retained a deleted source file"];
    must[
      not (`$b) in key .tst.depGraph;
      "rescan retained a stale reverse edge"];
  };

  should["merge successful scans from independent roots"]{
    firstSeed:.tst.tempFile ".seed";
    firstRoot:.tst.static.getDir firstSeed;
    firstSource:.utl.normalizePath firstRoot,"/first.q";
    (.utl.pathToHsym firstSource)0:enlist "firstValue:1";
    secondSeed:.tst.tempFile ".seed";
    secondRoot:.tst.static.getDir secondSeed;
    secondSource:.utl.normalizePath secondRoot,"/second.q";
    (.utl.pathToHsym secondSource)0:enlist "secondValue:1";
    .tst.depGraph:()!();
    .tst.dependencies:()!();

    .tst.scanDirectory firstRoot;
    .tst.scanDirectory secondRoot;

    (asc key .tst.dependencies) mustmatch
      `$asc (firstSource;secondSource);
    (.tst.getDependencies firstSource) mustmatch
      ();
    (.tst.getDependencies secondSource) mustmatch
      ();
  };

  should["preserve the previous graph when a rebuild fails"]{
    oldGraph:(enlist `dependency)!enlist enlist `consumer;
    oldDependencies:(enlist `consumer)!enlist enlist `dependency;
    .tst.depGraph:oldGraph;
    .tst.dependencies:oldDependencies;
    missing:(.tst.tempFile ".seed"),".missing";

    outcome:.utl.attempt[
      .tst.rebuildGraph;
      enlist enlist missing];

    (first outcome) musteq 0b;
    .tst.depGraph mustmatch oldGraph;
    .tst.dependencies mustmatch oldDependencies;
  };

  should["do not admit targets from a failed rebuild"]{
    seed:.tst.tempFile ".seed";
    root:.tst.static.getDir seed;
    firstSource:.utl.normalizePath root,"/a.q";
    failingSource:.utl.normalizePath root,"/z.q";
    requireName:
      "never-admit-failed-target-",
      string[.z.i],
      ".q";
    requireTarget:
      .utl.normalizePath root,"/",requireName;
    loadName:
      "never-admit-failed-load-",
      string[.z.i],
      ".q";
    loadTarget:.utl.absolutePath loadName;
    (.utl.pathToHsym firstSource)0:(
      "\\l ",loadName;
      ".utl.require \"",requireName,"\";");
    slash:"\\";
    quote:"\"";
    invalidLiteral:
      quote,"bad",slash,"n","path.q",quote;
    (.utl.pathToHsym failingSource)0:enlist
      ".utl.require ",invalidLiteral,";";
    oldGraph:(enlist `dependency)!enlist enlist `consumer;
    oldDependencies:(enlist `consumer)!enlist enlist `dependency;
    .tst.depGraph:oldGraph;
    .tst.dependencies:oldDependencies;
    rootHandle:.utl.pathToHsym root;
    warmOutcome:.utl.attempt[
      .tst.parseDependencyRecords;
      enlist failingSource];
    (first warmOutcome) musteq 0b;
    registryCountBefore:count .utl.pathSymbolTexts;
    registryBytesBefore:.utl.pathSymbolBytes;

    outcome:.utl.attempt[
      .tst.rebuildGraph;
      enlist enlist root];

    (first outcome) musteq 0b;
    .tst.depGraph mustmatch oldGraph;
    .tst.dependencies mustmatch oldDependencies;
    (count .utl.pathSymbolTexts) musteq registryCountBefore;
    .utl.pathSymbolBytes musteq registryBytesBefore;
    must[
      not any requireTarget~/:.utl.pathSymbolTexts;
      "failed rebuild admitted an unpublished dependency target"];
    must[
      not any loadTarget~/:.utl.pathSymbolTexts;
      "failed rebuild admitted an unpublished load candidate"];
  };

  should["preflight the whole publication symbol batch"]{
    seed:.tst.tempFile ".seed";
    root:.tst.static.getDir seed;
    source:.utl.normalizePath root,"/batch.q";
    firstName:
      "never-admit-batch-first-",
      string[.z.i],
      ".q";
    secondName:
      "never-admit-batch-second-",
      string[.z.i],
      ".q";
    firstTarget:.utl.normalizePath root,"/",firstName;
    secondTarget:.utl.normalizePath root,"/",secondName;
    (.utl.pathToHsym source)0:(
      ".utl.require \"",firstName,"\";";
      ".utl.require \"",secondName,"\";");
    rootHandle:.utl.pathToHsym root;
    oldLimit:.utl.MAX_PATH_SYMBOLS;
    .tst.registerCleanup[
      {[limit].utl.MAX_PATH_SYMBOLS:limit};
      enlist oldLimit];
    .utl.MAX_PATH_SYMBOLS:
      1+count .utl.pathSymbolTexts;
    oldGraph:(enlist `dependency)!enlist enlist `consumer;
    oldDependencies:(enlist `consumer)!enlist enlist `dependency;
    .tst.depGraph:oldGraph;
    .tst.dependencies:oldDependencies;
    registryCountBefore:count .utl.pathSymbolTexts;
    registryBytesBefore:.utl.pathSymbolBytes;

    outcome:.utl.attempt[
      .tst.rebuildGraph;
      enlist enlist root];

    (first outcome) musteq 0b;
    .tst.depGraph mustmatch oldGraph;
    .tst.dependencies mustmatch oldDependencies;
    (count .utl.pathSymbolTexts) musteq registryCountBefore;
    .utl.pathSymbolBytes musteq registryBytesBefore;
    must[
      not any firstTarget~/:.utl.pathSymbolTexts;
      "failed batch admitted its first unpublished target"];
    must[
      not any secondTarget~/:.utl.pathSymbolTexts;
      "failed batch admitted its second unpublished target"];
  };

  should["reject empty roots without scanning or publication"]{
    oldGraph:(enlist `dependency)!enlist enlist `consumer;
    oldDependencies:(enlist `consumer)!enlist enlist `dependency;
    .tst.depGraph:oldGraph;
    .tst.dependencies:oldDependencies;

    scanOutcome:.utl.attempt[
      .tst.scanDirectory;
      enlist ""];
    rebuildOutcome:.utl.attempt[
      .tst.rebuildGraph;
      enlist enlist ""];
    zeroRootOutcome:.utl.attempt[
      .tst.rebuildGraph;
      enlist ()];

    (first scanOutcome) musteq 0b;
    (first rebuildOutcome) musteq 0b;
    (first zeroRootOutcome) musteq 0b;
    .tst.depGraph mustmatch oldGraph;
    .tst.dependencies mustmatch oldDependencies;
  };

  should["reject oversized source before replacing the graph"]{
    seed:.tst.tempFile ".seed";
    root:.tst.static.getDir seed;
    source:.utl.normalizePath root,"/large.q";
    (.utl.pathToHsym source)0:
      enlist 1024#"x";
    oldGraph:(enlist `dependency)!enlist enlist `consumer;
    oldDependencies:(enlist `consumer)!enlist enlist `dependency;
    .tst.depGraph:oldGraph;
    .tst.dependencies:oldDependencies;
    .tst.MAX_DEPENDENCY_SOURCE_BYTES:32;

    outcome:.utl.attempt[
      .tst.rebuildGraph;
      enlist enlist root];

    (first outcome) musteq 0b;
    .tst.depGraph mustmatch oldGraph;
    .tst.dependencies mustmatch oldDependencies;
  };

  should["enforce source byte limits against an injected reader"]{
    reader:{[path;maximum]
      `path`identity`bytes!(
        path;
        path,"#fake";
        "x"$32#"a")};
    limits:.tst.dependencyLimits[];
    limits[`sourceBytes]:4;

    outcome:.utl.attempt[
      .tst.parseDependencyRecordsWith;
      (reader;"/tmp/dependency-reader.q";limits)];

    (first outcome) musteq 0b;
  };

  should["bound aggregate source bytes before replacing the graph"]{
    seed:.tst.tempFile ".seed";
    root:.tst.static.getDir seed;
    firstSource:.utl.normalizePath root,"/first.q";
    secondSource:.utl.normalizePath root,"/second.q";
    (.utl.pathToHsym firstSource)0:enlist 16#"x";
    (.utl.pathToHsym secondSource)0:enlist 16#"y";
    oldGraph:(enlist `dependency)!enlist enlist `consumer;
    oldDependencies:(enlist `consumer)!enlist enlist `dependency;
    .tst.depGraph:oldGraph;
    .tst.dependencies:oldDependencies;
    .tst.MAX_DEPENDENCY_TOTAL_SOURCE_BYTES:20;

    outcome:.utl.attempt[
      .tst.rebuildGraph;
      enlist enlist root];

    (first outcome) musteq 0b;
    .tst.depGraph mustmatch oldGraph;
    .tst.dependencies mustmatch oldDependencies;
  };

  should["reject oversized root input before invoking traversal"]{
    walker:{[suffix;roots;adapter]
      '"dependency walker must not run"};
    limits:.tst.dependencyLimits[];
    limits[`pathBytes]:1;

    outcome:.utl.attempt[
      .tst.dependencyFilesWith;
      (walker;()!();enlist "/oversized-root";limits)];

    (first outcome) musteq 0b;
    must[
      not (last outcome) like "*walker must not run*";
      "dependency roots were not bounded before traversal"];
  };

  should["honor the build's snapshotted file-set limits"]{
    limits:.tst.dependencyLimits[];
    limits[`files]:0;

    outcome:.utl.attempt[
      .tst.dependencyFileSetWith;
      (enlist "/tmp/dependency-limit-probe.q";0b;limits)];

    (first outcome) musteq 0b;
  };

  should["bound traversal failure diagnostics without cycling entries"]{
    walker:{[suffix;roots;adapter]
      `files`problems`failureCount!(
        ();
        ("first traversal problem";"second traversal problem");
        2)};
    limits:.tst.dependencyLimits[];

    outcome:.utl.attempt[
      .tst.dependencyFilesWith;
      (walker;()!();enlist "/tmp";limits)];

    (first outcome) musteq 0b;
    (count (last outcome) ss "first traversal problem") musteq 1;
    (count (last outcome) ss "second traversal problem") musteq 1;
  };

  should["reject excess directives before replacing the graph"]{
    seed:.tst.tempFile ".seed";
    root:.tst.static.getDir seed;
    source:.utl.normalizePath root,"/directives.q";
    (.utl.pathToHsym source)0:(
      ".utl.require \"a.q\";";
      ".utl.require \"b.q\";");
    oldGraph:(enlist `dependency)!enlist enlist `consumer;
    oldDependencies:(enlist `consumer)!enlist enlist `dependency;
    .tst.depGraph:oldGraph;
    .tst.dependencies:oldDependencies;
    .tst.MAX_DEPENDENCY_DIRECTIVES:1;

    outcome:.utl.attempt[
      .tst.rebuildGraph;
      enlist enlist root];

    (first outcome) musteq 0b;
    .tst.depGraph mustmatch oldGraph;
    .tst.dependencies mustmatch oldDependencies;
  };

  should["bound malformed directive candidates as parsing work"]{
    source:.tst.tempFile ".q";
    (.utl.pathToHsym source)0:enlist
      ".utl.require helper \"first.q\"; .utl.require helper \"second.q\";";
    .tst.MAX_DEPENDENCY_DIRECTIVES:1;

    outcome:.utl.attempt[
      .tst.parseDependencyRecords;
      enlist source];

    (first outcome) musteq 0b;
  };

  should["reject excess edges before replacing the graph"]{
    seed:.tst.tempFile ".seed";
    root:.tst.static.getDir seed;
    source:.utl.normalizePath root,"/edges.q";
    (.utl.pathToHsym source)0:(
      ".utl.require \"a.q\";";
      ".utl.require \"b.q\";");
    oldGraph:(enlist `dependency)!enlist enlist `consumer;
    oldDependencies:(enlist `consumer)!enlist enlist `dependency;
    .tst.depGraph:oldGraph;
    .tst.dependencies:oldDependencies;
    .tst.MAX_DEPENDENCY_EDGES:1;

    outcome:.utl.attempt[
      .tst.rebuildGraph;
      enlist enlist root];

    (first outcome) musteq 0b;
    .tst.depGraph mustmatch oldGraph;
    .tst.dependencies mustmatch oldDependencies;
  };

  should["enforce the aggregate file limit across directory scans"]{
    firstSeed:.tst.tempFile ".seed";
    firstRoot:.tst.static.getDir firstSeed;
    firstSource:.utl.normalizePath firstRoot,"/first.q";
    (.utl.pathToHsym firstSource)0:enlist "firstValue:1";
    secondSeed:.tst.tempFile ".seed";
    secondRoot:.tst.static.getDir secondSeed;
    secondSource:.utl.normalizePath secondRoot,"/second.q";
    novelTarget:.utl.normalizePath
      secondRoot,"/never-admit-aggregate-target.q";
    (.utl.pathToHsym secondSource)0:enlist
      ".utl.require \"never-admit-aggregate-target.q\";";
    .tst.depGraph:()!();
    .tst.dependencies:()!();
    .tst.MAX_DEPENDENCY_FILES:1;
    .tst.scanDirectory firstRoot;
    oldGraph:.tst.depGraph;
    oldDependencies:.tst.dependencies;
    secondRootHandle:.utl.pathToHsym secondRoot;
    registryCountBefore:count .utl.pathSymbolTexts;
    registryBytesBefore:.utl.pathSymbolBytes;

    outcome:.utl.attempt[
      .tst.scanDirectory;
      enlist secondRoot];

    (first outcome) musteq 0b;
    .tst.depGraph mustmatch oldGraph;
    .tst.dependencies mustmatch oldDependencies;
    (count .utl.pathSymbolTexts) musteq registryCountBefore;
    .utl.pathSymbolBytes musteq registryBytesBefore;
    must[
      not any novelTarget~/:.utl.pathSymbolTexts;
      "failed aggregate scan admitted an unpublished target"];
  };

  should["fail closed for a malformed dependency limit"]{
    oldGraph:(enlist `dependency)!enlist enlist `consumer;
    oldDependencies:(enlist `consumer)!enlist enlist `dependency;
    .tst.depGraph:oldGraph;
    .tst.dependencies:oldDependencies;
    .tst.MAX_DEPENDENCY_EDGES:"invalid";

    outcome:.utl.attempt[
      .tst.rebuildGraph;
      enlist enlist .utl.PKGLOADING];

    (first outcome) musteq 0b;
    .tst.depGraph mustmatch oldGraph;
    .tst.dependencies mustmatch oldDependencies;
  };
};

.tst.desc["dependency graph hardening: traversal"]{
  before{
    .tst.testState.dependencyHardeningState:
      .tst.dependencyHardening.capture[];
  };
  after{
    .tst.restoreNamedLifecycle
      .tst.testState.dependencyHardeningState;
    ![`.tst.testState;();0b;enlist `dependencyHardeningState];
  };

  should["walk a deep cycle iteratively and exactly once"]{
    nodeCount:512;
    nodes:`$"dep_node_",/:string til nodeCount;
    nextNodes:1 rotate nodes;
    .tst.depGraph:nodes!enlist each nextNodes;

    dependents:.tst.getDependents first nodes;

    (count dependents) musteq nodeCount;
    must[
      all nodes in dependents;
      "iterative traversal omitted a cycle node"];
    (count distinct dependents) musteq nodeCount;
  };

  should["preserve singleton graph and result shapes"]{
    .tst.depGraph:
      (enlist `dependency)!enlist enlist `consumer;

    (.tst.getDependents `dependency) mustmatch
      enlist `consumer;
  };

  should["preserve the seen-accumulator traversal contract"]{
    .tst.depGraph:
      `a`b!(
        enlist `b;
        enlist `c);

    (.tst.getDependentsAcc[`a;enlist `b]) mustmatch
      enlist `b;
    (.tst.getDependentsAcc[`b;enlist `b]) mustmatch
      `symbol$();
  };

  should["preserve historical depth-first dependent order"]{
    .tst.depGraph:
      `a`b`c`d!(
        `b`c;
        `c`d;
        enlist `e;
        enlist `f);

    (.tst.getDependents `a) mustmatch
      `b`c`d`e`f;
  };

  should["enforce the dependent traversal ceiling"]{
    .tst.MAX_DEPENDENCY_WALK:2;
    .tst.depGraph:
      `a`b`c`d!(
        enlist `b;
        enlist `c;
        enlist `d;
        `symbol$());

    outcome:.utl.attempt[
      .tst.getDependents;
      enlist `a];

    (first outcome) musteq 0b;
  };

  should["allow exact-limit and disconnected traversals"]{
    .tst.MAX_DEPENDENCY_WALK:3;
    .tst.depGraph:
      `a`b`c`x`y!(
        enlist `b;
        enlist `c;
        enlist `a;
        enlist `y;
        `symbol$());

    dependents:.tst.getDependents `a;

    dependents mustmatch `b`c`a;
    (count dependents) musteq 3;

    .tst.depGraph:
      `a`b`c`d`x`y!(
        enlist `b;
        enlist `c;
        enlist `d;
        `symbol$();
        enlist `y;
        `symbol$());

    (.tst.getDependents `a) mustmatch
      `b`c`d;
  };

  should["fail closed for malformed graph values"]{
    .tst.depGraph:
      (enlist `a)!enlist 42;

    outcome:.utl.attempt[
      .tst.getDependents;
      enlist `a];

    (first outcome) musteq 0b;
  };

  should["fail closed for an empty graph path"]{
    .tst.depGraph:
      (enlist `)!enlist enlist `consumer;

    outcome:.utl.attempt[
      .tst.getDependents;
      enlist `consumer];

    (first outcome) musteq 0b;
  };

  should["avoid interning unknown character-vector queries"]{
    .tst.depGraph:()!();
    .tst.dependencies:()!();
    probe:raze
      ("/dependency-query-that-does-not-exist-";
       string .z.i;
       ".q");
    symbolsBefore:.Q.w[]`syms;

    (.tst.getDependents probe) mustmatch `symbol$();
    (.tst.getDependencies probe) mustmatch ();

    .Q.w[][`syms] musteq symbolsBefore;
  };

  should["reject new dependency symbols when cumulative admission is full"]{
    oldLimit:.utl.MAX_PATH_SYMBOLS;
    .tst.registerCleanup[
      {[limit].utl.MAX_PATH_SYMBOLS:limit};
      enlist oldLimit];
    .utl.MAX_PATH_SYMBOLS:count .utl.pathSymbolTexts;
    firstProbe:raze
      ("/dependency-symbol-budget-";
       string .z.i;
       "-first.q");
    secondProbe:raze
      ("/dependency-symbol-budget-";
       string .z.i;
       "-second.q");
    firstOutcome:.utl.attempt[
      .tst.resolveDepTarget;
      ("/tmp/requirer.q";firstProbe)];
    symbolsBefore:.Q.w[]`syms;
    registryCountBefore:count .utl.pathSymbolTexts;

    outcome:.utl.attempt[
      .tst.resolveDepTarget;
      ("/tmp/requirer.q";secondProbe)];

    (first firstOutcome) musteq 0b;
    (first outcome) musteq 0b;
    .Q.w[][`syms] musteq symbolsBefore;
    (count .utl.pathSymbolTexts) musteq registryCountBefore;
    must[
      not any secondProbe~/:.utl.pathSymbolTexts;
      "rejected dependency target consumed path-symbol admission"];
  };

  should["reject an inconsistent state before publication"]{
    state:
      `forward`reverse!(
        (enlist `consumer)!enlist enlist `dependency;
        ()!());
    outcome:.utl.attempt[
      .tst.publishDependencyState;
      enlist state];

    (first outcome) musteq 0b;
  };
};
