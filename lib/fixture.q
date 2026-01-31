\d .tst

/ Ensure fixtures is a global in .tst
if[not `fixtures in key `.tst; fixtures:: ((),`)!(),(::)];

currentDirFixture: ` 
savedDir: `directory`vars!("";(`,())!(),(::))

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
    .tst.fixtures[name]: d
 }

/ Register a fixture with options - 3-arg version
registerFixtureWithOpts:{[name;val;opts]
    d: `val`scope`setup`teardown`instance!(val;`test;{};{};(::));
    if[(99h = type opts) and (0 < count opts); d: d, opts];
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
  if[not f[`teardown]~{}; @[f[`teardown]; val; { [name;e] -1 "ERROR cleaning fixture '", string[name], "': ", e }[name]]];
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
    if[not fixtureName ~ .tst.currentDirFixture; if[dirLoaded; .tst.removeDirVars `]; system "l ", p; .tst.currentDirFixture: fixtureName];
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
 if[not () ~ dirVars: .tst.findDirVars[];
  .tst.savedDir:`directory`vars!(system "cd";(!).(::;get each) @\:` sv' `.,'dirVars);
  .tst.removeDirVars dirVars];
 }

removeDirVars:{v:reverse x^.tst.findDirVars[]; if[0<count v; {value "delete ",string[x]," from `."} each v]}

restoreDir:{
 if[not ` ~ .tst.currentDirFixture; .tst.removeDirVars ` ; .tst.currentDirFixture: ` ];
 if[not "" ~ .tst.savedDir.directory;
  system "l ", .tst.savedDir.directory;
  (key .tst.savedDir.vars) set' value .tst.savedDir.vars;
  .tst.savedDir: `directory`vars!("";(`,())!(),(::));]
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
if[not `cleanupTasks in key `.tst; cleanupTasks:: ()];

registerCleanup:{[func;args]
    .tst.cleanupTasks,: enlist `func`args!(func;args);
 }

runCleanupTasks:{[]
    if[0 = count .tst.cleanupTasks; :()];
    tasks: .tst.cleanupTasks;
    .tst.cleanupTasks:: (); / Clear first to prevent recursion or double runs
    {[t] .[t`func; t`args; { [e] -1 "WARNING: Cleanup task failed: ", .tst.toString e }] } each tasks;
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