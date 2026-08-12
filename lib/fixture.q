\d .tst

/ Ensure fixtures is a global in .tst
if[not `fixtures in key `.tst; fixtures:: ((),`)!(),(::)];

/ The registry legitimately stores mixed value shapes: definition dicts AND
/ bare symbol references (see cleanupAllFixtures). The null-key (::) sentinel
/ keeps the value list generic; if it is ever lost, q collapses the values to
/ a typed vector (or a table, for uniform dicts) and every later registration
/ of a different shape dies with 'type. Rebuild the sentinel before amending.
ensureFixtureRegistry:{[]
    reg: @[get; `.tst.fixtures; {[e] ()!()}];
    if[not 99h = type reg; reg: ()!()];
    vals: value reg;
    / uniform definition dicts collapse to a table; recover the rows as dicts
    if[98h = type vals; vals: {x} each vals];
    reg: key[reg]!vals;
    / dict join re-materializes the value list; the (::) cannot conform to any
    / typed vector, so the result is guaranteed generic again
    .tst.fixtures:: (((),`)!(),(::)) , ((),`) _ reg;
 }

currentDirFixture: ` 
savedDir: `directory`vars`context`tables!("";(`,())!(),(::);`.;`symbol$())

fixtureAs:{[fixtureName;name]
    / Get directory of current test file (tstPath should be absolute from loader)
    tstPath: .utl.pathToString .tst.tstPath;
    dirPath: $[0 = count tstPath; "."; "/" sv -1 _ "/" vs tstPath];
    if[0 = count dirPath; dirPath: "."];

    / Look for fixture in test directory first
    fp: .tst.fixtureInDir[fixtureName; dirPath];

    / If not found, try fixtures subdirectory
    fixturesDir: dirPath, "/fixtures";
    if[(fp ~ `) and .utl.isDir fixturesDir; fp: .tst.fixtureInDir[fixtureName; fixturesDir]];

    / Error if still not found
    if[fp ~ `; '"Error loading fixture '", (.tst.toString fixtureName), "', not found in ", dirPath];

    / Load and register
    fixture: .tst.loadFixture[fp; name];
    .tst.ensureFixtureRegistry[];
    .tst.fixtures[name]: fixture;
    fixture ^ name
 }

fixtureInDir:{[fname;dir]
    / Normalize inputs
    fnameStr: .tst.toString fname;
    dirPath: .utl.pathToString dir;

    / Check directory exists
    if[not .utl.isDir dirPath; :` ];

    / Get directory contents
    h: .utl.pathToHsym dirPath;
    contents: key h;
    if[() ~ contents; :` ];

    / Look for fixture by name (with or without extension)
    matches: contents where {[target;name] n: string name; base: first "." vs n; (base ~ target) or (n ~ target)}[fnameStr] each contents;

    if[0 = count matches; :` ];

    / Return full path as symbol for compatibility
    `$":", dirPath, "/", string first matches
 }

/ Register a fixture - 2-arg version (simple case)
registerFixture:{[name;val]
    d: `val`scope`setup`teardown`instance!(val;`test;{};{};(::));
    .tst.ensureFixtureRegistry[];
    .tst.fixtures[name]: d
 }

/ Register a fixture with options - 3-arg version
registerFixtureWithOpts:{[name;val;opts]
    d: `val`scope`setup`teardown`instance!(val;`test;{};{};(::));
    if[(99h = type opts) and (0 < count opts); d: d, opts];
    .tst.ensureFixtureRegistry[];
    .tst.fixtures[name]: d
 }

getFixture:{[name]
    if[not name in key .tst.fixtures; '"Fixture not found: ", string[name]];
    f: .tst.fixtures[name];
    if[(f[`scope]~`session) and not (::)~f`instance; :f`instance];
    v: f`val;
    if[not f[`setup]~{}; v: @[f[`setup]; v; {[name;e] '"Setup failed for '", string[name], "': ", e}[name]]];
    if[f[`scope]~`session; .tst.fixtures[name;`instance]: v];
    v
 }

teardownFixture:{[name;val]
  if[not name in key .tst.fixtures; :()];
  f: .tst.fixtures name;
  if[not f[`teardown]~{};
    @[f[`teardown]; val; {[fixtureName;err]
        .tst.recordCleanupError[`sessionFixture;
            "Fixture '",string[fixtureName],"' teardown failed: ",err]
      }[name]]];
 }

cleanupAllFixtures:{[]
    if[not count .tst.fixtures; :()];
    fks: key .tst.fixtures;
    / Filter to session fixtures with instances, safely handling missing/invalid entries
    sFixtures: fks where {
        f: @[{.tst.fixtures x}; x; {`invalid}];
        if[f ~ `invalid; :0b];
        if[-11h = type f; :0b];  / Just a symbol reference, not a dict
        if[not 99h = type f; :0b];  / Not a dictionary
        (f[`scope] ~ `session) and not (::) ~ f`instance
    } each fks;
    if[0 < count sFixtures;
        {[fname]
            f: @[{.tst.fixtures x}; fname; {(::)}];
            if[(::) ~ f; :()];
            if[99h = type f; .tst.teardownFixture[fname; f`instance]; .tst.fixtures[fname;`instance]: (::)];
        } each sFixtures;
    ];
 }

loadFixture:{[path;name]
    / Get file extension from path
    p: .utl.pathToString path;
    base: last "/" vs p;
    parts: "." vs base;
    fext: `$$[1 < count parts; last parts; ""];

    / Handle based on extension or type (single line for q parser)
    $[fext in `txt`csv`psv`tsv; .tst.loadFixtureTxt[path;name]; .utl.isFile p; .tst.loadFixtureFile[path;name]; .tst.loadFixtureDir[path;name]]
 }

fixture: .tst.fixtureAs[;` ]

loadFixtureDir:{[f;name]
    / Extract fixture/directory name
    p: .utl.pathToString f;
    fixtureName: `$last "/" vs p;

    dirLoaded: not ` ~ .tst.currentDirFixture;
    if[not dirLoaded; .tst.saveDir[]];
    / Note: q doesn't support multiline if blocks, so consolidate
    if[not fixtureName ~ .tst.currentDirFixture;
        if[dirLoaded; .tst.removeDirVars `];
        / Clear any previously loaded tables before switching fixtures
        origCtx: system "d";
        ctx: $[`context in key `.tst; .tst.context; origCtx];
        system "d ", string ctx;
        tbls: tables[];
        if[count tbls; ![ctx; (); 0b; tbls]];
        / Load fixture data in the current test context (protected)
        res: @[.utl.loadQFile; p; {[p;e] '("Fixture load failed for '", p, "': ", e)}[p]];
        system "d ", string origCtx;
        .tst.currentDirFixture: fixtureName
    ];
    / Return the fixture name (like other load functions)
    fixtureName ^ name
 }

loadFixtureTxt:{[f;name]
    / Extract fixture name from path (filename without extension)
    p: .utl.pathToString f;
    base: last "/" vs p;
    parts: "." vs base;
    fnameDefault: `$$[1 < count parts; "." sv -1 _ parts; base];
    fname: fnameDefault ^ name;

    / Read and parse content
    h: .utl.pathToHsym f;
    content: (raze l[0;1] vs l[0];enlist l[0;1]) 0: 1 _ l: read0 h;
    .tst.mock[fname; content];
    fname
 }

loadFixtureFile:{[f;name]
    / Extract fixture name from path
    p: .utl.pathToString f;
    base: last "/" vs p;
    fnameDefault: `$base;
    fname: fnameDefault ^ name;

    / Load file content
    h: .utl.pathToHsym f;
    .tst.mock[fname; get h];
    fname
 }

saveDir:{
  origCtx: system "d";
  ctx: $[`context in key `.tst; .tst.context; origCtx];
  system "d ", string ctx;
  dirVars: .tst.findDirVars[];
  tbls: tables[];
  if[(not () ~ dirVars) or (0 < count tbls);
    .tst.savedDir:`directory`vars`context`tables!(
      system "cd";(!).(::;get each) @\:` sv' `.,'dirVars;ctx;tbls);
    if[0 < count tbls; ![ctx; (); 0b; tbls]];
    if[not () ~ dirVars; .tst.removeDirVars dirVars];
  ];
  system "d ", string origCtx;
 }

removeDirVars:{v:reverse x^.tst.findDirVars[]; if[0<count v; {value "delete ",string[x]," from `."} each v]}

/ A saved in-memory table does not imply the process cwd is a q database. Reload
/ only when at least one captured table has a corresponding on-disk directory;
/ this distinguishes a loaded partition/splay from an ordinary project checkout.
savedDirHasDiskTables:{[]
 if["" ~ .tst.savedDir.directory;:0b];
 names:string .tst.savedDir.tables;
 if[0=count names;:0b];
 any .utl.isDir each .tst.savedDir.directory,"/",/:names
 }

restoreDir:{
 origCtx: system "d";
 if[not ` ~ .tst.currentDirFixture; .tst.removeDirVars ` ; .tst.currentDirFixture: ` ];
 if[not "" ~ .tst.savedDir.directory;
  ctx: .tst.savedDir.context;
  system "d ", string ctx;
  tbls: tables[];
  if[count tbls; ![ctx; (); 0b; tbls]];
  loadOutcome:(0b;"");
  if[.tst.savedDirHasDiskTables[];
   loadOutcome:@[{system "l ",x;(0b;"")};.tst.savedDir.directory;{[e](1b;e)}]];
  (key .tst.savedDir.vars) set' value .tst.savedDir.vars;
  system "d ", string origCtx;
  .tst.savedDir: `directory`vars`context`tables!("";(`,())!(),(::);`.;`symbol$());
  if[first loadOutcome;'last loadOutcome]]
 }

findDirVars:{
 $[0<count where -1h = (type .Q.qp get @) each ` sv' `.,'tables `.;
  [
      c: distinct @[get;`.Q.pf;()], @[get;`.Q.pt;()], pvals where not any (pvals:key `:.) like/:(string @[get;`.Q.pv;()]),enlist "par.txt";
      c where c in key `.
  ];
  ()]
 }

/ Cleanup Registry
/ Two queues: expec-scope (runs after each expectation) and spec-scope
/ (runs at end of spec, AFTER resource teardown). Spec scope is the right
/ choice for cleanups that depend on resources the runner closes for you,
/ e.g. unlinking a file whose handle the test deliberately leaks.
if[not `cleanupTasks in key `.tst; cleanupTasks:: ()];
if[not `specCleanupTasks in key `.tst; specCleanupTasks:: ()];
if[not `cleanupErrors in key `.tst.app; .tst.app.cleanupErrors: ()];

/ Record cleanup failures as structured run state. They are injected into the
/ final result set after all cleanup attempts finish, so CI cannot go green when
/ teardown failed and later cleanup steps still get a chance to run.
recordCleanupError:{[scope;err]
    ctx: @[get; `.tst.currentContext; {()!()}];
    sourcePath: $[(99h = type ctx) and `file in key ctx; .tst.toString ctx`file; ""];
    suiteName: $[(99h = type ctx) and `suite in key ctx; .tst.toString ctx`suite; ""];
    testName: $[(99h = type ctx) and `test in key ctx; .tst.toString ctx`test; ""];
    messageText: .tst.toString err;
    .tst.app.cleanupErrors,: enlist `scope`file`suite`test`message!(
        scope;sourcePath;suiteName;testName;messageText);
    -1 "ERROR: Cleanup failure [", .tst.toString[scope], "]",
        $[count suiteName; " in ",suiteName; ""],
        $[count testName; " :: ",testName; ""], ": ", messageText;
    messageText
 };

registerCleanup:{[func;args]
    .tst.cleanupTasks,: enlist `func`args!(func;args);
 }

registerSpecCleanup:{[func;args]
    .tst.specCleanupTasks,: enlist `func`args!(func;args);
 }

drainQueue:{[q]
    if[0 = count q; :()];
    outcomes: {[t]
        $[0 = count t`args;
          @[{[fn] (0b;fn[])};t`func;{[err] (1b;err)}];
          @[{[task] (0b;.[task`func;task`args])};t;{[err] (1b;err)}]]
      } each q;
    failed: outcomes where 1b ~/: first each outcomes;
    if[count failed; .tst.recordCleanupError[`cleanupTask;] each last each failed];
    last each failed
 }

runCleanupTasks:{[]
    tasks: .tst.cleanupTasks;
    .tst.cleanupTasks:: (); / Clear first to prevent recursion or double runs
    .tst.drainQueue tasks;
 }

runSpecCleanupTasks:{[]
    tasks: .tst.specCleanupTasks;
    .tst.specCleanupTasks:: ();
    .tst.drainQueue tasks;
 }

tempFile:{[suffix]
    / Generate unique name
    fn: "resq_", .tst.toString[.z.p], "_", string[first 1?1000], suffix;
    path: .utl.normalizePath (system "cd"), "/", fn;
    
    / Register for cleanup
    .tst.registerCleanup[{[p] @[hdel; hsym `$p; {}]}; enlist path];
    
    path
 }

\d .
