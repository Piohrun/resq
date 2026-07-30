.tst.desc["Loader path policy v2"]{
  should["normalize POSIX roots without reinterpreting Windows-looking bytes"]{
    .utl.normalizePathForHost["//server//a/../b";0b] musteq "//server/b";
    .utl.normalizePathForHost["///server/a";0b] musteq "/server/a";
    .utl.normalizePathForHost["C:\\literal\\name";0b] musteq "C:\\literal\\name";
    .utl.isAbsolutePathForHost["C:\\literal";0b] musteq 0b;
    .utl.isAbsolutePathForHost["//root";0b] musteq 1b;
  };

  should["keep absolute and normalization decisions on one grammar"]{
    posix:.utl.absolutePathForHost[first "a";0b;"/cwd"];
    posix musteq "/cwd/a";
    .utl.isAbsolutePathForHost[posix;0b] musteq 1b;
    .utl.absolutePathForHost["//host/x";0b;"/cwd"]
      musteq "//host/x";
    win:.utl.absolutePathForHost[first "a";1b;"C:/cwd"];
    win musteq "C:/cwd/a";
    .utl.isAbsolutePathForHost[win;1b] musteq 1b;
    .utl.absolutePathForHost["D:/x/../y";1b;"C:/cwd"]
      musteq "D:/y";
    .utl.absolutePathForHost["//server/share/a";1b;"C:/cwd"]
      musteq "//server/share/a";
  };

  should["accept scalar and short path inputs deliberately"]{
    .utl.normalizePathForHost[first "a";0b] musteq enlist "a";
    .utl.normalizePathForHost["";0b] musteq enlist ".";
    .utl.normalizePathForHost[".";0b] musteq enlist ".";
    .utl.normalizePathForHost["..";0b] musteq "..";
    .utl.normalizePathForHost["/";0b] musteq enlist "/";
    .utl.normalizePathForHost["C:/";1b] musteq "C:/";
  };

  should["reject ambiguous and aliased Windows names"]{
    invalid:(
      "C:relative";
      "\\root-relative";
      "foo:stream";
      "a:b:c";
      "C:/a:stream";
      "\\\\?\\C:\\x";
      "\\\\.\\PIPE\\x";
      "/??/C:/x";
      "///server/share/x";
      "////server/share/x";
      "/////server/share/x";
      "C:/bad*name";
      "C:/bad?name";
      "C:/bad<name";
      "C:/trail.";
      "C:/trail ";
      "C:/ lead";
      "C:/CON";
      "C:/con.txt";
      "C:/aux.data";
      "C:/COM1.q";
      "C:/LPT9";
      "C:/COM¹.txt";
      "C:/LPT².log";
      "//server";
      "//server/";
      "//./share/x";
      "//server/../leaf";
      "//server/./leaf");
    {mustthrow["*Invalid*";(.utl.pathPolicy;x;"test path";1b)]}
      each invalid;
  };

  should["accept ordinary rooted Windows paths and UNC paths"]{
    .utl.normalizePathForHost["c:\\dir\\file.q";1b]
      musteq "c:/dir/file.q";
    .utl.normalizePathForHost["//server/share/a/../b";1b]
      musteq "//server/share/b";
    .utl.isAbsolutePathForHost["//server/share";1b] musteq 1b;
  };

  should["reject corrupted path-symbol state before admission"]{
    oldTexts:.utl.pathSymbolTexts;
    oldBytes:.utl.pathSymbolBytes;
    .utl.pathSymbolBytes+:1;
    mismatch:@[.utl.pathToHsym;"/never-admitted-mismatch";{[e]e}];
    mismatchState:(.utl.pathSymbolTexts;.utl.pathSymbolBytes);
    .utl.pathSymbolTexts:8193#enlist "x";
    .utl.pathSymbolBytes:8193j;
    oversized:@[.utl.pathToHsym;"/never-admitted-oversized";{[e]e}];
    oversizedState:(count .utl.pathSymbolTexts;.utl.pathSymbolBytes);
    .utl.pathSymbolTexts:oldTexts;
    .utl.pathSymbolBytes:oldBytes;
    must[not (::)~mismatch;"byte-count mismatch must signal"];
    must[mismatchState~(oldTexts;oldBytes+1);
      "rejected admission must leave corrupted state untouched"];
    must[not (::)~oversized;"hard registry limit must signal"];
    oversizedState musteq (8193;8193j);
  };

  should["honor existing path ownership after soft limits are lowered"]{
    oldTexts:.utl.pathSymbolTexts;
    oldBytes:.utl.pathSymbolBytes;
    oldCountLimit:.utl.MAX_PATH_SYMBOLS;
    oldByteLimit:.utl.MAX_PATH_SYMBOL_BYTES;
    oldCharacterLimit:.utl.MAX_PATH_CHARACTERS;
    ownedPath:(system "cd"),"/.loader-v2-owned-",string .z.p;
    expected:.utl.pathToHsym ownedPath;
    ownedState:(.utl.pathSymbolTexts;.utl.pathSymbolBytes);
    .utl.MAX_PATH_SYMBOLS:0;
    .utl.MAX_PATH_SYMBOL_BYTES:0;
    .utl.MAX_PATH_CHARACTERS:1;
    resolved:@[.utl.pathToHsym;ownedPath;{[e]e}];
    rejected:@[.utl.pathToHsym;ownedPath,"-new";{[e]e}];
    finalState:(.utl.pathSymbolTexts;.utl.pathSymbolBytes);
    .utl.MAX_PATH_SYMBOLS:oldCountLimit;
    .utl.MAX_PATH_SYMBOL_BYTES:oldByteLimit;
    .utl.MAX_PATH_CHARACTERS:oldCharacterLimit;
    .utl.pathSymbolTexts:oldTexts;
    .utl.pathSymbolBytes:oldBytes;
    resolved musteq expected;
    must[not (::)~rejected;"soft limits must reject only new ownership"];
    must[finalState~ownedState;
      "rejected new ownership must leave the registry unchanged"];
  };

};

.tst.desc["Owned cleanup and fixture lifecycle v2"]{
  should["preserve heterogeneous fixtures in both insertion orders"]{
    oldFixtures:.tst.fixtures;
    seed:.tst.fixtureDefinition[0;()!()];
    .tst.fixtures:(enlist `seed)!enlist seed;
    ![`.tst.fixtures;();0b;enlist `seed];
    nested:`name`id!(`Alice;1001);
    .tst.registerFixture[`nested;nested];
    .tst.registerFixture[`scalar;10];
    .tst.registerFixture[`nested;nested];
    .tst.validateFixtureRegistry[];
    .tst.cleanupAllFixtures[];
    dictionaryFirst:(key .tst.fixtures;
      .tst.getFixture `nested;.tst.getFixture `scalar);
    .tst.fixtures:(`symbol$())!();
    .tst.registerFixture[`scalar;10];
    .tst.registerFixture[`nested;nested];
    .tst.validateFixtureRegistry[];
    .tst.cleanupAllFixtures[];
    scalarFirst:(key .tst.fixtures;
      .tst.getFixture `nested;.tst.getFixture `scalar);
    .tst.fixtures:oldFixtures;
    dictionaryFirst musteq (`nested`scalar;nested;10);
    scalarFirst musteq (`scalar`nested;nested;10);
  };

  should["attempt malformed and valid cleanup tasks and retain only failures"]{
    oldQueue:.tst.cleanupTasks;
    oldGuard:.tst.cleanupDrainActive;
    .tst.testState.loaderV2Events:();
    valid:`func`args!(
      {[x].tst.testState.loaderV2Events,:enlist x};
      enlist `valid);
    .tst.cleanupTasks:(42;valid);
    capsule:.tst.makeExpectationCleanup[];
    err:@[capsule;();{x}];
    remaining:.tst.cleanupTasks;
    events:.tst.testState.loaderV2Events;
    .tst.cleanupTasks:oldQueue;
    .tst.cleanupDrainActive:oldGuard;
    must[not (::)~err;"malformed cleanup must signal"];
    events musteq enlist `valid;
    count[remaining] musteq 1;
    first[remaining] musteq 42;
  };

  should["retain a failed cleanup for retry and remove it after success"]{
    oldQueue:.tst.cleanupTasks;
    .tst.testState.loaderV2Attempts:0;
    retryTask:`func`args!(
      {[]
        .tst.testState.loaderV2Attempts+:1;
        if[1=.tst.testState.loaderV2Attempts;'"retry me"]};
      ());
    .tst.cleanupTasks:enlist retryTask;
    capsule:.tst.makeExpectationCleanup[];
    firstErr:@[capsule;();{x}];
    afterFirst:count .tst.cleanupTasks;
    secondErr:@[capsule;();{x}];
    afterSecond:count .tst.cleanupTasks;
    attempts:.tst.testState.loaderV2Attempts;
    .tst.cleanupTasks:oldQueue;
    must[not (::)~firstErr;"first cleanup failure must signal"];
    afterFirst musteq 1;
    secondErr musteq (::);
    afterSecond musteq 0;
    attempts musteq 2;
  };

  should["restore guard and failed ownership when a callback deletes both"]{
    oldQueue:.tst.cleanupTasks;
    oldGuard:.tst.cleanupDrainActive;
    destructive:`func`args!(
      {[]
        delete cleanupTasks from `.tst;
        delete cleanupDrainActive from `.tst;
        '"guard deletion"};
      ());
    .tst.cleanupTasks:enlist destructive;
    capsule:.tst.makeExpectationCleanup[];
    err:@[capsule;();{x}];
    guard:@[get;`.tst.cleanupDrainActive;{::}];
    retained:@[get;`.tst.cleanupTasks;{()}];
    .tst.cleanupTasks:oldQueue;
    .tst.cleanupDrainActive:oldGuard;
    must[not (::)~err;"destructive cleanup must signal"];
    guard musteq 0b;
    count[retained] musteq 1;
  };

  should["clear only successful session instances and keep failed ownership"]{
    oldFixtures:.tst.fixtures;
    .tst.testState.loaderV2FixtureEvents:();
    good:.tst.fixtureDefinition[
      1;
      `scope`teardown!(
        `session;
        {[x].tst.testState.loaderV2FixtureEvents,:enlist `good})];
    bad:.tst.fixtureDefinition[
      2;
      `scope`teardown!(
        `session;
        {[x]
          .tst.testState.loaderV2FixtureEvents,:enlist `bad;
          '"teardown failed"})];
    good[`instance]:10;
    bad[`instance]:20;
    .tst.fixtures:`good`malformed`bad!(good;`invalid;bad);
    capsule:.tst.makeFixtureCleanup[];
    err:@[capsule;();{x}];
    fixtureRegistryAfter:.tst.fixtures;
    events:.tst.testState.loaderV2FixtureEvents;
    .tst.fixtures:oldFixtures;
    must[not (::)~err;"aggregate fixture teardown must signal"];
    events musteq `good`bad;
    fixtureRegistryAfter[`good;`instance] musteq (::);
    fixtureRegistryAfter[`bad;`instance] musteq 20;
    must[not 99h=type fixtureRegistryAfter`malformed;
      "malformed fixture record must remain owned"];
  };

  should["restore registry shape when teardown mutates its ownership record"]{
    oldFixtures:.tst.fixtures;
    deleting:.tst.fixtureDefinition[
      1;
      `scope`teardown!(
        `session;
        {[x]delete fixtures from `.tst})];
    deleting[`instance]:99;
    .tst.fixtures:(enlist `deleting)!enlist deleting;
    capsule:.tst.makeFixtureCleanup[];
    err:@[capsule;();{x}];
    fixtureRegistryAfter:.tst.fixtures;
    .tst.fixtures:oldFixtures;
    must[not (::)~err;"registry mutation during teardown must signal"];
    key[fixtureRegistryAfter] musteq enlist `deleting;
    fixtureRegistryAfter[`deleting;`instance] musteq (::);
  };

  should["run and retain through a captured capsule after helper replacement"]{
    oldQueue:.tst.cleanupTasks;
    oldGuard:.tst.cleanupDrainActive;
    oldWorker:.tst.drainOwnedCleanupWith;
    oldAttemptAll:.tst.attemptAll;
    oldValidate:.tst.validateCleanupTask;
    oldNote:.tst.noteFailure;
    oldFinish:.tst.raiseAttemptFailures;
    oldBuilder:.tst.makeCleanupQueueDrain;
    .tst.testState.loaderV2CapsuleEvents:();
    good:`func`args!(
      {[x].tst.testState.loaderV2CapsuleEvents,:enlist x};
      enlist `captured);
    bad:`func`args!(
      {[x]
        .tst.testState.loaderV2CapsuleEvents,:enlist x;
        '"capsule retry"};
      enlist `failed);
    .tst.cleanupTasks:(good;bad);
    capsule:.tst.makeExpectationCleanup[];
    .tst.drainOwnedCleanupWith:{[a;b;c;d](::)};
    .tst.attemptAll:{[a;b;c]'"replaced attempt-all"};
    .tst.validateCleanupTask:{[x]'"replaced validator"};
    .tst.noteFailure:{[a;b]'"replaced note"};
    .tst.raiseAttemptFailures:{[a;b]'"replaced finish"};
    .tst.makeCleanupQueueDrain:{[a;b]'"replaced builder"};
    outcome:@[capsule;();{[e]e}];
    remaining:.tst.cleanupTasks;
    guard:.tst.cleanupDrainActive;
    events:.tst.testState.loaderV2CapsuleEvents;
    `.tst.drainOwnedCleanupWith set oldWorker;
    `.tst.attemptAll set oldAttemptAll;
    `.tst.validateCleanupTask set oldValidate;
    `.tst.noteFailure set oldNote;
    `.tst.raiseAttemptFailures set oldFinish;
    `.tst.makeCleanupQueueDrain set oldBuilder;
    .tst.cleanupTasks:oldQueue;
    .tst.cleanupDrainActive:oldGuard;
    must[not (::)~outcome;"captured failure must signal"];
    count[remaining] musteq 1;
    must[(remaining 0)~bad;"failed task must remain owned for retry"];
    guard musteq oldGuard;
    events musteq `captured`failed;
  };

  should["keep cleanup authority when an earlier callback poisons helpers"]{
    oldQueue:.tst.cleanupTasks;
    oldGuard:.tst.cleanupDrainActive;
    oldAttempt:.utl.attempt;
    oldDiagnostic:.utl.boundedDiagnostic;
    .tst.testState.loaderV2PoisonEvents:();
    poison:`func`args!(
      {[]
        .tst.testState.loaderV2PoisonEvents,:enlist `first;
        .utl.attempt:{[a;b]'"poisoned attempt"};
        .utl.boundedDiagnostic:{[a;b]'"poisoned diagnostic"}};
      ());
    failing:`func`args!(
      {[]
        .tst.testState.loaderV2PoisonEvents,:enlist `second;
        '"retained cleanup"};
      ());
    .tst.cleanupTasks:(poison;failing);
    capsule:.tst.makeExpectationCleanup[];
    outcome:@[capsule;();{[e]e}];
    remaining:.tst.cleanupTasks;
    guard:.tst.cleanupDrainActive;
    events:.tst.testState.loaderV2PoisonEvents;
    `.utl.attempt set oldAttempt;
    `.utl.boundedDiagnostic set oldDiagnostic;
    .tst.cleanupTasks:oldQueue;
    .tst.cleanupDrainActive:oldGuard;
    must[not (::)~outcome;"captured failure must signal"];
    events musteq `first`second;
    count[remaining] musteq 1;
    first[remaining] musteq failing;
    guard musteq oldGuard;
  };

  should["run a captured fixture-cleanup capsule after helper replacement"]{
    oldFixtures:.tst.fixtures;
    oldWorker:.tst.cleanupAllFixturesWith;
    oldAttemptAll:.tst.attemptAll;
    oldValidateName:.tst.validateFixtureName;
    oldValidateRecord:.tst.validateFixtureRecord;
    oldNote:.tst.noteFailure;
    oldFinish:.tst.raiseAttemptFailures;
    .tst.testState.loaderV2FixtureCapsuleEvents:();
    record:.tst.fixtureDefinition[
      1;
      `scope`teardown!(
        `session;
        {[x].tst.testState.loaderV2FixtureCapsuleEvents,:enlist x})];
    record[`instance]:99;
    .tst.fixtures:(enlist `captured)!enlist record;
    capsule:.tst.makeFixtureCleanup[];
    .tst.cleanupAllFixturesWith:{[a;b](::)};
    .tst.attemptAll:{[a;b;c]'"replaced attempt-all"};
    .tst.validateFixtureName:{[x]'"replaced name validator"};
    .tst.validateFixtureRecord:{[x]'"replaced record validator"};
    .tst.noteFailure:{[a;b]'"replaced note"};
    .tst.raiseAttemptFailures:{[a;b]'"replaced finish"};
    outcome:@[capsule;();{[e]e}];
    registry:.tst.fixtures;
    events:.tst.testState.loaderV2FixtureCapsuleEvents;
    `.tst.cleanupAllFixturesWith set oldWorker;
    `.tst.attemptAll set oldAttemptAll;
    `.tst.validateFixtureName set oldValidateName;
    `.tst.validateFixtureRecord set oldValidateRecord;
    `.tst.noteFailure set oldNote;
    `.tst.raiseAttemptFailures set oldFinish;
    .tst.fixtures:oldFixtures;
    outcome musteq (::);
    events musteq enlist 99;
    registry[`captured;`instance] musteq (::);
  };

  should["preserve the public fixture teardown API and trap failures"]{
    oldFixtures:.tst.fixtures;
    .tst.testState.loaderV2TeardownEvents:();
    good:.tst.fixtureDefinition[
      1;
      (enlist `teardown)!enlist {[x]
        .tst.testState.loaderV2TeardownEvents,:enlist x}];
    bad:.tst.fixtureDefinition[
      2;
      (enlist `teardown)!enlist {[x]
        .tst.testState.loaderV2TeardownEvents,:enlist x;
        '"public teardown failure"}];
    .tst.fixtures:`good`bad!(good;bad);
    goodOutcome:.[.tst.teardownFixture;(`good;10);{[e]e}];
    badOutcome:.[.tst.teardownFixture;(`bad;20);{[e]e}];
    missingOutcome:.[.tst.teardownFixture;(`missing;30);{[e]e}];
    events:.tst.testState.loaderV2TeardownEvents;
    .tst.fixtures:oldFixtures;
    goodOutcome musteq (::);
    badOutcome musteq (::);
    missingOutcome musteq (::);
    events musteq 10 20;
  };

  should["trap public queue cleanup while internal capsules retain failures"]{
    oldExpectation:.tst.cleanupTasks;
    oldSpec:.tst.specCleanupTasks;
    oldGuard:.tst.cleanupDrainActive;
    .tst.testState.loaderV2PublicCleanupEvents:();
    bad:`func`args!(
      {[x]
        .tst.testState.loaderV2PublicCleanupEvents,:enlist x;
        '"public cleanup failure"};
      enlist `bad);
    good:`func`args!(
      {[x].tst.testState.loaderV2PublicCleanupEvents,:enlist x};
      enlist `good);
    .tst.cleanupTasks:(bad;good);
    expectationOutcome:@[.tst.runCleanupTasks;();{[e]e}];
    expectationRemaining:.tst.cleanupTasks;
    .tst.specCleanupTasks:(bad;good);
    specOutcome:@[.tst.runSpecCleanupTasks;();{[e]e}];
    specRemaining:.tst.specCleanupTasks;
    events:.tst.testState.loaderV2PublicCleanupEvents;
    .tst.cleanupTasks:oldExpectation;
    .tst.specCleanupTasks:oldSpec;
    .tst.cleanupDrainActive:oldGuard;
    expectationOutcome musteq (::);
    specOutcome musteq (::);
    count[expectationRemaining] musteq 1;
    count[specRemaining] musteq 1;
    events musteq `bad`good`bad`good;
  };

  should["trap public fixture cleanup while retaining failed instances"]{
    oldFixtures:.tst.fixtures;
    .tst.testState.loaderV2PublicFixtureEvents:();
    good:.tst.fixtureDefinition[
      1;
      `scope`teardown!(
        `session;
        {[x].tst.testState.loaderV2PublicFixtureEvents,:enlist `good})];
    bad:.tst.fixtureDefinition[
      2;
      `scope`teardown!(
        `session;
        {[x]
          .tst.testState.loaderV2PublicFixtureEvents,:enlist `bad;
          '"public fixture failure"})];
    good[`instance]:10;
    bad[`instance]:20;
    .tst.fixtures:`good`bad!(good;bad);
    outcome:@[.tst.cleanupAllFixtures;();{[e]e}];
    registry:.tst.fixtures;
    events:.tst.testState.loaderV2PublicFixtureEvents;
    .tst.fixtures:oldFixtures;
    outcome musteq (::);
    events musteq `good`bad;
    registry[`good;`instance] musteq (::);
    registry[`bad;`instance] musteq 20;
  };

  should["refuse a directory symlink without deleting its external target"]{
    if[.utl.isWindows;must[1b;"POSIX symlink regression"];:()];
    oldQueue:.tst.cleanupTasks;
    oldGuard:.tst.cleanupDrainActive;
    .tst.cleanupTasks:();
    item:.tst.tempFile "";
    .utl.ensureDir item;
    token:raze string md5 "c"$((string .z.p),string .z.i);
    external:"/tmp/resq-loader-v2-external-dir-",token;
    .utl.ensureDir external;
    sentinel:external,"/sentinel";
    (.utl.pathToHsym sentinel) 0:enlist "outside";
    link:item,"/escape";
    system "ln -s -- ",.utl.shellQuote[external]," ",.utl.shellQuote[link];
    capsule:.tst.makeExpectationCleanup[];
    outcome:@[capsule;();{[e]e}];
    sentinelSafe:.utl.isFile sentinel;
    retained:count .tst.cleanupTasks;
    @[hdel;.utl.pathToHsym link;{}];
    retryOutcome:@[capsule;();{[e]e}];
    @[hdel;.utl.pathToHsym sentinel;{}];
    @[hdel;.utl.pathToHsym external;{}];
    .tst.cleanupTasks:oldQueue;
    .tst.cleanupDrainActive:oldGuard;
    must[not (::)~outcome;"directory symlink must fail closed"];
    sentinelSafe musteq 1b;
    retained musteq 1;
    retryOutcome musteq (::);
  };

  should["refuse a file symlink and retain cleanup ownership"]{
    if[.utl.isWindows;must[1b;"POSIX symlink regression"];:()];
    oldQueue:.tst.cleanupTasks;
    oldGuard:.tst.cleanupDrainActive;
    .tst.cleanupTasks:();
    item:.tst.tempFile "";
    .utl.ensureDir item;
    token:raze string md5 "c"$((string .z.p),string .z.i);
    external:"/tmp/resq-loader-v2-external-file-",token;
    (.utl.pathToHsym external) 0:enlist "outside";
    link:item,"/escape";
    system "ln -s -- ",.utl.shellQuote[external]," ",.utl.shellQuote[link];
    capsule:.tst.makeExpectationCleanup[];
    outcome:@[capsule;();{[e]e}];
    sentinelSafe:.utl.isFile external;
    retained:count .tst.cleanupTasks;
    @[hdel;.utl.pathToHsym link;{}];
    retryOutcome:@[capsule;();{[e]e}];
    @[hdel;.utl.pathToHsym external;{}];
    .tst.cleanupTasks:oldQueue;
    .tst.cleanupDrainActive:oldGuard;
    must[not (::)~outcome;"file symlink must fail closed"];
    sentinelSafe musteq 1b;
    retained musteq 1;
    retryOutcome musteq (::);
  };

  should["fail before deletion when an enumerated parent is replaced"]{
    .tst.testState.loaderV2RaceInspects:0;
    .tst.testState.loaderV2RaceDeletes:();
    inspect:{[path]
      if[path~"/owned";
        .tst.testState.loaderV2RaceInspects+:1;
        :$[1=.tst.testState.loaderV2RaceInspects;
          `path`exists`kind`identity!("/owned";1b;`dir;"/owned");
          `path`exists`kind`identity!("/owned";1b;`link;"/outside")]];
      `path`exists`kind`identity!(path;1b;`file;path)};
    ops:`inspect`list`delete`within`windows`limit`isLink`rootIdentity!(
      inspect;
      {[p;n;b]`path`entries!(p;enlist "victim")};
      {[p].tst.testState.loaderV2RaceDeletes,:enlist p;1b};
      {[p;r;w]1b};
      0b;
      16;
      {[p]0b};
      "/owned");
    outcome:.[.tst.removeOwnedTree;(ops;"/owned";"/owned");{[e]e}];
    must[not (::)~outcome;"parent replacement must fail closed"];
    .tst.testState.loaderV2RaceDeletes musteq ();
  };

  should["allow flat Windows cleanup through an injected safe classifier"]{
    .tst.testState.loaderV2WindowsDeletes:();
    inspect:{[path]
      $[path~"C:/owned";
        `path`exists`kind`identity!(path;1b;`dir;path);
        `path`exists`kind`identity!(path;1b;`file;path)]};
    ops:`inspect`list`delete`within`windows`limit`isLink`rootIdentity!(
      inspect;
      {[p;n;b]`path`entries!(p;enlist "file")};
      {[p].tst.testState.loaderV2WindowsDeletes,:enlist p;1b};
      .utl.pathWithinRoot;
      1b;
      8;
      {[p]0b};
      "C:/owned");
    outcome:.[.tst.removeOwnedTree;(ops;"C:/owned";"C:/owned");{[e]e}];
    outcome musteq (::);
    .tst.testState.loaderV2WindowsDeletes
      musteq ("C:/owned/file";"C:/owned");
  };

  should["retain recursive Windows cleanup when classification is unavailable"]{
    .tst.testState.loaderV2WindowsDeletes:();
    inspect:{[path]
      `path`exists`kind`identity!(path;1b;`dir;path)};
    ops:`inspect`list`delete`within`windows`limit`isLink`rootIdentity!(
      inspect;
      {[p;n;b]`path`entries!(p;
        $[p~"C:/owned";enlist "child";()])};
      {[p].tst.testState.loaderV2WindowsDeletes,:enlist p;1b};
      .utl.pathWithinRoot;
      1b;
      8;
      {[p]if[p~"C:/owned/child";
        '"reparse-point classification unavailable"];0b};
      "C:/owned");
    outcome:.[.tst.removeOwnedTree;(ops;"C:/owned";"C:/owned");{[e]e}];
    must[not (::)~outcome;
      "ambiguous recursive Windows cleanup must fail closed"];
    .tst.testState.loaderV2WindowsDeletes musteq ();
  };
};

.tst.desc["q-native filesystem load and ownership v2"]{
  should["execute ordinary module paths in the caller CWD"]{
    root:.tst.tempFile "";
    .utl.ensureDir root;
    path:root,"/module.q";
    (.utl.pathToHsym path) 0:
      enlist ".tst.testState.loaderV2ObservedCwd:system \"cd\"";
    fs:.utl.fsSnapshot[];
    read:(fs`readRegular)[path;4096];
    cwd:system "cd";
    (fs`loadNative)[path;read`identity];
    .tst.testState.loaderV2ObservedCwd musteq cwd;
    (system "cd") musteq cwd;
  };

  should["reject a spaced directory without execution or CWD drift"]{
    root:.tst.tempFile "";
    dir:root,"/directory with spaces";
    .utl.ensureDir dir;
    path:dir,"/module.q";
    (.utl.pathToHsym path) 0:
      enlist ".tst.testState.loaderV2SpaceLoad:42";
    fs:.utl.fsSnapshot[];
    read:(fs`readRegular)[path;4096];
    cwd:system "cd";
    outcome:.[fs`loadNative;(path;read`identity);{[e]e}];
    (system "cd") musteq cwd;
    must[not (::)~outcome;"spaced directory must fail closed"];
    must[not `loaderV2SpaceLoad in key `.tst.testState;
      "rejected spaced path must not execute"];
  };

  should["reject a spaced filename before execution and preserve CWD"]{
    root:.tst.tempFile "";
    .utl.ensureDir root;
    path:root,"/module with spaces.q";
    (.utl.pathToHsym path) 0:
      enlist ".tst.testState.loaderV2SpacedName:1";
    fs:.utl.fsSnapshot[];
    read:(fs`readRegular)[path;4096];
    cwd:system "cd";
    err:.[fs`loadNative;(path;read`identity);{[e]e}];
    must[not (::)~err;"spaced filename must fail closed"];
    (system "cd") musteq cwd;
    must[not `loaderV2SpacedName in key `.tst.testState;
      "rejected file must not execute"];
  };

  should["restore CWD when a loaded file signals"]{
    root:.tst.tempFile "";
    .utl.ensureDir root;
    path:root,"/broken.q";
    (.utl.pathToHsym path) 0:enlist "'\"loader v2 failure\"";
    fs:.utl.fsSnapshot[];
    read:(fs`readRegular)[path;4096];
    cwd:system "cd";
    err:.[fs`loadNative;(path;read`identity);{[e]e}];
    must[not (::)~err;"load failure must signal"];
    (system "cd") musteq cwd;
  };

  should["attempt namespace restoration after CWD restoration fails"]{
    .tst.testState.loaderV2ProcessCommands:();
    command:{[text]
      .tst.testState.loaderV2ProcessCommands,:enlist text;
      if[text like "cd *";'"forced CWD failure"];
      (::)};
    outcome:.[.utl.restoreProcessContext;
      (.utl.attempt;command;"/unrestorable";system "d");{[e]e}];
    commands:.tst.testState.loaderV2ProcessCommands;
    must[not (::)~outcome;"CWD restoration failure must signal"];
    count[commands] musteq 2;
    first[commands] musteq "cd /unrestorable";
    last[commands] musteq "d ",string system "d";
  };

  should["seal a filesystem snapshot against helper replacement during load"]{
    root:.tst.tempFile "";
    .utl.ensureDir root;
    path:root,"/poison.q";
    (.utl.pathToHsym path) 0:(
      ".tst.testState.loaderV2SealedLoad:42;";
      ".utl.hardLimit:{[a;b;c]'\"poisoned hard limit\"};";
      ".utl.pathToHsym:{[p]'\"poisoned path handle\"};";
      ".utl.absolutePath:{[p]'\"poisoned absolute path\"};";
      ".utl.attempt:{[f;a]'\"poisoned attempt\"};";
      ".utl.MAX_PATH_CHARACTERS:0;";
      ".utl.MAX_PATH_COMPONENTS:0;";
      ".utl.MAX_PATH_SYMBOLS:0;";
      ".utl.MAX_PATH_SYMBOL_BYTES:0;");
    fs:.utl.fsSnapshot[];
    read:(fs`readRegular)[path;4096];
    oldHardLimit:.utl.hardLimit;
    oldPathToHsym:.utl.pathToHsym;
    oldAbsolutePath:.utl.absolutePath;
    oldAttempt:.utl.attempt;
    oldCharacterLimit:.utl.MAX_PATH_CHARACTERS;
    oldComponentLimit:.utl.MAX_PATH_COMPONENTS;
    oldSymbolLimit:.utl.MAX_PATH_SYMBOLS;
    oldSymbolByteLimit:.utl.MAX_PATH_SYMBOL_BYTES;
    outcome:.[fs`loadNative;(path;read`identity);{[e]e}];
    `.utl.hardLimit set oldHardLimit;
    `.utl.pathToHsym set oldPathToHsym;
    `.utl.absolutePath set oldAbsolutePath;
    `.utl.attempt set oldAttempt;
    `.utl.MAX_PATH_CHARACTERS set oldCharacterLimit;
    `.utl.MAX_PATH_COMPONENTS set oldComponentLimit;
    `.utl.MAX_PATH_SYMBOLS set oldSymbolLimit;
    `.utl.MAX_PATH_SYMBOL_BYTES set oldSymbolByteLimit;
    must[99h=type outcome;
      "sealed load must return its verified source record"];
    must[all `path`identity`bytes in key outcome;
      "sealed load must preserve the verified source schema"];
    .tst.testState.loaderV2SealedLoad musteq 42;
  };

  should["quote metacharacter symlink probes as one non-executing shell word"]{
    if[.utl.isWindows;must[1b;"POSIX link-probe regression"];:()];
    item:.tst.tempFile "";
    .utl.ensureDir item;
    target:item,"/target";
    (.utl.pathToHsym target) 0:enlist "target";
    token:raze string md5 "c"$((string .z.p),string .z.i);
    markerLeaf:".loader-v2-shell-pwn-",token;
    marker:(system "cd"),"/",markerLeaf;
    leaves:(
      "space link";
      "quote'link";
      "dollar$link";
      "tick`link";
      "semi; touch ",markerLeaf,"; #");
    links:{[base;leaf]base,"/",leaf}[item;] each leaves;
    {system "ln -s -- ",.utl.shellQuote[y]," ",.utl.shellQuote[x]}'
      [links;(count links)#enlist target];
    fs:.utl.fsSnapshot[];
    kinds:{[inspectFn;p](inspectFn p)`kind}[fs`inspect;] each links;
    markerCreated:.utl.pathExists marker;
    {@[hdel;x;{}]} each .utl.pathToHsym each links;
    if[markerCreated;@[hdel;.utl.pathToHsym marker;{}]];
    kinds musteq (count links)#`link;
    markerCreated musteq 0b;
  };

  should["treat ambiguous link-probe output and command failure as unknown"]{
    malformed:.utl.qfsLinkState[
      .utl.attempt;
      {[text]enlist "not-a-resq-sentinel"};
      .utl.shellQuoteForHost;
      0b;
      "/tmp/probe"];
    failed:.utl.qfsLinkState[
      .utl.attempt;
      {[text]'"probe command failed"};
      .utl.shellQuoteForHost;
      0b;
      "/tmp/probe"];
    inspectOutcome:.[.utl.qfsInspect;
      ({[p]p};
       .utl.pathToHsym;
       .utl.attempt;
       {[p]p};
       .utl.boundedDiagnostic;
       {[p]`unknown};
       0b;
       "/tmp/resq-loader-v2-ambiguous-probe");
      {[e]e}];
    malformed musteq `unknown;
    failed musteq `unknown;
    must[not (::)~inspectOutcome;
      "ambiguous link classification must fail closed"];
  };

  should["use captured temp cleanup capabilities after helper replacement"]{
    oldFs:.utl.fs;
    oldSnapshot:.utl.fsSnapshot;
    oldWithin:.utl.pathWithinRoot;
    oldRemove:.tst.removeOwnedTree;
    oldCleanup:.tst.cleanupTemp;
    path:.tst.tempFile ".txt";
    (.utl.pathToHsym path) 0:enlist "owned";
    fake:oldFs;
    fake[`delete]:{[p]1b};
    .utl.fs:fake;
    .utl.fsSnapshot:{[].utl.fs};
    .utl.pathWithinRoot:{[a;b;c]1b};
    .tst.removeOwnedTree:{[a;b;c](::)};
    .tst.cleanupTemp:{[a;b;c;d;e](::)};
    err:@[.tst.runCleanupTasks;();{[e]e}];
    `.utl.fs set oldFs;
    `.utl.fsSnapshot set oldSnapshot;
    `.utl.pathWithinRoot set oldWithin;
    `.tst.removeOwnedTree set oldRemove;
    `.tst.cleanupTemp set oldCleanup;
    err musteq (::);
    must[not .utl.pathExists path;
      "captured cleanup must remove the real owned tree"];
  };
};

.tst.desc["Non-following loader discovery v2"]{
  should["skip directory symlinks at and below requested roots"]{
    if[.utl.isWindows;must[1b;"POSIX symlink regression"];:()];
    savedErrors:.tst.app.loadErrors;
    token:raze string md5 "c"$((string .z.p),string .z.i);
    root:"/tmp/resq-loader-v2-discovery-root-",token;
    external:"/tmp/resq-loader-v2-discovery-outside-",token;
    rootLink:"/tmp/resq-loader-v2-discovery-link-",token;
    .utl.ensureDir root;
    .utl.ensureDir external;
    outside:external,"/test_outside.q";
    (.utl.pathToHsym outside) 0:enlist "should[\"outside\"]{1 musteq 1};";
    childLink:root,"/escape";
    system "ln -s -- ",.utl.shellQuote[external]," ",
      .utl.shellQuote[childLink];
    system "ln -s -- ",.utl.shellQuote[external]," ",
      .utl.shellQuote[rootLink];
    childResult:.tst.findTests enlist root;
    childErrors:.tst.app.loadErrors;
    rootResult:.tst.findTests enlist rootLink;
    rootErrors:.tst.app.loadErrors;
    `.tst.app.loadErrors set savedErrors;
    system "unlink -- ",.utl.shellQuote childLink;
    system "unlink -- ",.utl.shellQuote rootLink;
    @[hdel;.utl.pathToHsym outside;{}];
    @[hdel;.utl.pathToHsym external;{}];
    @[hdel;.utl.pathToHsym root;{}];
    childResult musteq ();
    rootResult musteq ();
    (count childErrors) musteq count savedErrors;
    (count rootErrors) musteq 1+count savedErrors;
    rootErrors[(count rootErrors)-1;`type] musteq `missing;
  };

  should["fail discovery when a directory physical identity escapes"]{
    inspect:{[path]
      $[path~"/root";
        `path`exists`kind`identity!("/root";1b;`dir;"/root");
        path~"/root/escape";
        `path`exists`kind`identity!(path;1b;`dir;"/outside");
        `path`exists`kind`identity!(path;1b;`file;path)]};
    adapter:.utl.fsSnapshot[];
    adapter[`inspect]:inspect;
    adapter[`list]:{[path;n;b]
      `path`entries!(path;
        $[path~"/root";enlist "escape";enlist "test_outside.q"])};
    adapter:.utl.fsFactory adapter;
    result:.tst.walkFiles[".q";enlist "/root";adapter];
    (result`files) musteq ();
    (result`failureCount) musteq 1;
    must[(first result`problems) like "*physical identity*";
      "identity escape must be reported as incomplete traversal"];
  };

  should["reject unsafe directory enumeration entries"]{
    adapter:.utl.fsSnapshot[];
    adapter[`inspect]:{[path]
      `path`exists`kind`identity!(path;1b;`dir;path)};
    adapter[`list]:{[path;n;b]
      `path`entries!(path;enlist "../escape")};
    adapter:.utl.fsFactory adapter;
    result:.tst.walkFiles[".q";enlist "/root";adapter];
    (result`files) musteq ();
    (result`failureCount) musteq 1;
    must[(first result`problems) like "*invalid directory enumeration*";
      "unsafe child names must be reported"];
  };

  should["fail closed on corrupted test filename patterns"]{
    oldPatterns:@[get;`.resq.config.testFilePatterns;{::}];
    root:.tst.tempFile "";
    .utl.ensureDir root;
    .resq.config.testFilePatterns:"**.q";
    outcome:@[.tst.findTests;enlist root;{[e]e}];
    $[(::)~oldPatterns;
      ![`.resq.config;();0b;enlist `testFilePatterns];
      `.resq.config.testFilePatterns set oldPatterns];
    must[not (::)~outcome;"corrupted patterns must signal"];
  };
};

.tst.testState.requireV2Snapshot:{[]
  (`loaded`loadedIds`loadingPaths`dependencyText`testDepsSet`testDeps,
    `fileSet`fileValue`cwd`namespace)!(
    .utl.loaded;
    .utl.loadedIds;
    .utl.loadingPaths;
    .utl.dependencyText;
    `testDeps in key `.utl;
    @[get;`.utl.testDeps;{::}];
    `FILELOADING in key `.utl;
    @[get;`.utl.FILELOADING;{::}];
    system "cd";
    system "d")};

.tst.testState.restoreRequireV2:{[saved]
  `.utl.loaded set saved`loaded;
  `.utl.loadedIds set saved`loadedIds;
  `.utl.loadingPaths set saved`loadingPaths;
  `.utl.dependencyText set saved`dependencyText;
  if[saved`testDepsSet;
    `.utl.testDeps set saved`testDeps];
  if[not saved`testDepsSet;
    if[`testDeps in key `.utl;
      ![`.utl;();0b;enlist `testDeps]]];
  if[saved`fileSet;
    `.utl.FILELOADING set saved`fileValue];
  if[not saved`fileSet;
    if[`FILELOADING in key `.utl;
      ![`.utl;();0b;enlist `FILELOADING]]];
  system "cd ",saved`cwd;
  system "d ",string saved`namespace;
  (::)};

.tst.testState.requireV2Child:{[script;arguments]
  qFound:@[system;"command -v q 2>/dev/null";{()}];
  timeoutFound:@[system;"command -v timeout 2>/dev/null";{()}];
  if[(not count qFound) or not count timeoutFound;:"SKIP"];
  scriptPath:.tst.tempFile ".q";
  outputPath:.tst.tempFile ".out";
  logPath:.tst.tempFile ".log";
  (.utl.pathToHsym scriptPath) 0:script;
  argv:arguments,enlist outputPath;
  command:
    .utl.shellQuote[first timeoutFound]," -k 2s 20s ",
    .utl.shellQuote[first qFound]," ",
    .utl.shellQuote[scriptPath]," ",
    " " sv .utl.shellQuote each argv,
    " -q < /dev/null > ",.utl.shellQuote[logPath]," 2>&1";
  run:@[system;command;{[e]enlist e}];
  lines:@[read0;.utl.pathToHsym outputPath;{()}];
  if[count lines;:first lines];
  logLines:@[read0;.utl.pathToHsym logPath;{()}];
  $[count logLines;"NO_OUTPUT: ",first logLines;
    count run;"NO_OUTPUT: ",first run;
    "NO_OUTPUT"]};

.tst.testState.requireV2BaseBootstrap:{[]
  path:.tst.tempFile ".q";
  source:(
    "if[not `utl in key `;.utl:enlist[`]!enlist (::)];";
    "if[not `loaded in key `.utl;.utl.loaded:enlist \"\"];";
    ".utl.pathToString:{[p]$[10h=type p;p;string p]};";
    ".utl.pathToHsym:{[p]hsym `$.utl.pathToString p};";
    ".utl.require:{[path]";
    "  p:.utl.pathToString path;";
    "  if[any p~/:.utl.loaded;:(::)];";
    "  system \"l \",p;";
    "  .utl.loaded,:enlist p;";
    "  (::)};");
  (.utl.pathToHsym path) 0:source;
  path};

.tst.desc["Require context and recursion ownership v2"]{
  should["require explicit repair for unchanged base-bootstrap truth"]{
    module:.tst.tempFile ".q";
    legacyBootstrap:.tst.testState.requireV2BaseBootstrap[];
    if[not count legacyBootstrap;
      must[1b;"base bootstrap unavailable"];:()];
    legacySource:((.utl.fsSnapshot[])`readRegular)[legacyBootstrap;1048576];
    must[count[legacySource`bytes]>100;
      "base bootstrap fixture must contain the historical implementation"];
    (.utl.pathToHsym module) 0:(
      "if[not `legacyRuns in key `;.legacyRuns:0];";
      ".legacyValue:1;";
      ".legacyRuns+:1;");
    script:(
      "args:.z.x;bootstrap:args 0;legacy:args 1;module:args 2;output:args 3;";
      "legacyLoad:@[system;\"l \",legacy;{x}];";
      "if[not `utl in key `;";
      "  (hsym `$output) 0:enlist \"LEGACY: \",$[10h=type legacyLoad;legacyLoad;\"missing\"];";
      "  exit 0];";
      "legacyRequired:@[.utl.require;module;{x}];";
      "hot:@[system;\"l \",bootstrap;{x}];";
      "beforeRepair:(.legacyValue;.legacyRuns);";
      ".utl.loaded:0#enlist \"\";.utl.loadedIds:0#enlist \"\";";
      "repair:@[system;\"l \",bootstrap;{x}];";
      "required:@[.utl.require;module;{x}];";
      "hotSafe:$[10h=type hot;";
      "  hot like \"*trustworthy identities*\";0b];";
      "ok:all ((::)~legacyRequired;hotSafe;beforeRepair~(1;1);(::)~repair;";
      "  (::)~required;1=.legacyValue;2=.legacyRuns);";
      "message:$[ok;\"PASS\";10h=type legacyRequired;";
      "  \"FIRST: \",legacyRequired;\"FAIL\"];";
      "(hsym `$output) 0:enlist message;";
      "exit 0;");
    outcome:.tst.testState.requireV2Child[
      script;(.resq.HOME,"/lib/bootstrap.q";legacyBootstrap;module)];
    if[outcome~"SKIP";must[1b;"q child unavailable"];:()];
    outcome musteq "PASS";
  };

  should["never certify changed disk bytes as already-loaded identity"]{
    module:.tst.tempFile ".q";
    legacyBootstrap:.tst.testState.requireV2BaseBootstrap[];
    if[not count legacyBootstrap;
      must[1b;"base bootstrap unavailable"];:()];
    legacySource:((.utl.fsSnapshot[])`readRegular)[legacyBootstrap;1048576];
    must[count[legacySource`bytes]>100;
      "base bootstrap fixture must contain the historical implementation"];
    (.utl.pathToHsym module) 0:(
      "if[not `legacyRuns in key `;.legacyRuns:0];";
      ".legacyValue:1;";
      ".legacyRuns+:1;");
    script:(
      "args:.z.x;bootstrap:args 0;legacy:args 1;module:args 2;output:args 3;";
      "legacyLoad:@[system;\"l \",legacy;{x}];";
      "if[not `utl in key `;";
      "  (hsym `$output) 0:enlist \"LEGACY: \",$[10h=type legacyLoad;legacyLoad;\"missing\"];";
      "  exit 0];";
      "legacyRequired:@[.utl.require;module;{x}];";
      "(hsym `$module) 0:(\".legacyValue:2;\";\".legacyRuns+:1;\");";
      "hot:@[system;\"l \",bootstrap;{x}];";
      "beforeRepair:(.legacyValue;.legacyRuns);";
      ".utl.loaded:0#enlist \"\";.utl.loadedIds:0#enlist \"\";";
      "repair:@[system;\"l \",bootstrap;{x}];";
      "required:@[.utl.require;module;{x}];";
      "hotSafe:$[10h=type hot;";
      "  hot like \"*trustworthy identities*\";0b];";
      "ok:all ((::)~legacyRequired;hotSafe;beforeRepair~(1;1);(::)~repair;";
      "  (::)~required;2=.legacyValue;2=.legacyRuns);";
      "message:$[ok;\"PASS\";10h=type legacyRequired;";
      "  \"FIRST: \",legacyRequired;\"FAIL\"];";
      "(hsym `$output) 0:enlist message;";
      "exit 0;");
    outcome:.tst.testState.requireV2Child[
      script;(.resq.HOME,"/lib/bootstrap.q";legacyBootstrap;module)];
    if[outcome~"SKIP";must[1b;"q child unavailable"];:()];
    outcome musteq "PASS";
  };

  should["reject malformed legacy truth with a recovery instruction"]{
    script:(
      "args:.z.x;bootstrap:args 0;output:args 1;";
      "if[not `utl in key `;.utl:enlist[`]!enlist (::)];";
      ".utl.loaded:42;";
      "error:@[system;\"l \",bootstrap;{x}];";
      "ok:$[10h=type error;";
      "  all (error like \"*Malformed legacy require state*\";";
      "       error like \"*restart q*\");0b];";
      "(hsym `$output) 0:enlist $[ok;\"PASS\";\"FAIL\"];";
      "exit 0;");
    outcome:.tst.testState.requireV2Child[
      script;enlist .resq.HOME,"/lib/bootstrap.q"];
    if[outcome~"SKIP";must[1b;"q child unavailable"];:()];
    outcome musteq "PASS";
  };

  should["attribute nested dependencies to the executing module"]{
    saved:.tst.testState.requireV2Snapshot[];
    root:.tst.tempFile "";
    .utl.ensureDir root;
    a:root,"/a.q";
    b:root,"/b.q";
    caller:root,"/test_caller.q";
    (.utl.pathToHsym b) 0:
      enlist ".tst.testState.requireV2Nested:42";
    (.utl.pathToHsym a) 0:enlist ".utl.require \"b.q\"";
    `.utl.FILELOADING set .utl.pathToHsym caller;
    outcome:@[.utl.require;a;{[e]e}];
    deps:.utl.dependencyText;
    fileAfter:@[get;`.utl.FILELOADING;{::}];
    guardAfter:.utl.loadingPaths;
    cwdAfter:system "cd";
    namespaceAfter:system "d";
    .tst.testState.restoreRequireV2 saved;
    outcome musteq (::);
    .tst.testState.requireV2Nested musteq 42;
    must[any {[needle;entry]needle~entry}[(caller;a);] each deps;
      "caller must depend on the direct module"];
    must[any {[needle;entry]needle~entry}[(a;b);] each deps;
      "module A must depend on module B"];
    must[not any {[needle;entry]needle~entry}[(caller;b);] each deps;
      "nested dependency must not be attributed to the caller"];
    fileAfter musteq .utl.pathToHsym caller;
    guardAfter musteq saved`loadingPaths;
    cwdAfter musteq saved`cwd;
    namespaceAfter musteq saved`namespace;
  };

  should["restore require context after a nested module failure"]{
    saved:.tst.testState.requireV2Snapshot[];
    root:.tst.tempFile "";
    .utl.ensureDir root;
    a:root,"/a.q";
    b:root,"/broken.q";
    caller:root,"/test_caller.q";
    (.utl.pathToHsym b) 0:(
      ".tst.testState.requireV2FailureTouched:1";
      "'\"nested require failure\"");
    (.utl.pathToHsym a) 0:enlist ".utl.require \"broken.q\"";
    `.utl.FILELOADING set .utl.pathToHsym caller;
    outcome:@[.utl.require;a;{[e]e}];
    loadedAfter:.utl.loaded;
    idsAfter:.utl.loadedIds;
    depsAfter:.utl.dependencyText;
    fileAfter:@[get;`.utl.FILELOADING;{::}];
    guardAfter:.utl.loadingPaths;
    cwdAfter:system "cd";
    namespaceAfter:system "d";
    .tst.testState.restoreRequireV2 saved;
    must[not (::)~outcome;"nested load failure must signal"];
    .tst.testState.requireV2FailureTouched musteq 1;
    must[loadedAfter~saved`loaded;
      "nested require failure must not change the loaded-file registry"];
    idsAfter musteq saved`loadedIds;
    depsAfter musteq saved`dependencyText;
    fileAfter musteq .utl.pathToHsym caller;
    guardAfter musteq saved`loadingPaths;
    cwdAfter musteq saved`cwd;
    namespaceAfter musteq saved`namespace;
  };

  should["retain a successful nested require when its parent fails"]{
    saved:.tst.testState.requireV2Snapshot[];
    root:.tst.tempFile "";
    .utl.ensureDir root;
    a:root,"/a.q";
    b:root,"/b.q";
    caller:root,"/test_caller.q";
    .tst.testState.requireV2OuterRuns:0;
    (.utl.pathToHsym b) 0:(
      ".tst.testState.requireV2OuterTouched:42";
      ".tst.testState.requireV2OuterRuns+:1");
    (.utl.pathToHsym a) 0:(
      ".utl.require \"b.q\"";
      "'\"outer require failure\"");
    `.utl.FILELOADING set .utl.pathToHsym caller;
    outcome:@[.utl.require;a;{[e]e}];
    loadedAfter:.utl.loaded;
    idsAfter:.utl.loadedIds;
    depsAfter:.utl.dependencyText;
    retryOutcome:@[.utl.require;b;{[e]e}];
    runsAfter:.tst.testState.requireV2OuterRuns;
    .tst.testState.restoreRequireV2 saved;
    must[not (::)~outcome;"outer load failure must signal"];
    .tst.testState.requireV2OuterTouched musteq 42;
    retryOutcome musteq (::);
    must[b in loadedAfter;
      "executed child must remain represented in loaded truth"];
    must[not a in loadedAfter;
      "failed parent must not be represented as loaded"];
    (count idsAfter) musteq count loadedAfter;
    must[any {[needle;entry]needle~entry}[(a;b);] each depsAfter;
      "executed nested dependency edge must remain represented"];
    runsAfter musteq 1;
  };

  should["roll back require truth after successful load mutates context"]{
    saved:.tst.testState.requireV2Snapshot[];
    target:.utl.absolutePath ".require-v2-context.q";
    fake:.utl.fsSnapshot[];
    fake[`readRegular]:{[p;n]
      `path`identity`bytes!(p;p,"#fake";0x00)};
    fake[`loadNative]:{[p;i]
      .utl.loadingPaths:enlist "mutated";
      `.utl.FILELOADING set `:mutated;
      (enlist `identity)!enlist i};
    fake:.utl.fsFactory fake;
    beforeState:.utl.requireStateSnapshot[];
    outcome:.[.utl.requireWith;(fake;target);{[e]e}];
    afterState:.utl.requireStateSnapshot[];
    .tst.testState.restoreRequireV2 saved;
    must[not (::)~outcome;"context mutation must signal"];
    must[afterState~beforeState;
      "context failure must restore all require-owned state"];
  };

  should["roll back require truth after final identity mismatch"]{
    saved:.tst.testState.requireV2Snapshot[];
    target:.utl.absolutePath ".require-v2-identity.q";
    fake:.utl.fsSnapshot[];
    fake[`readRegular]:{[p;n]
      `path`identity`bytes!(p;p,"#before";0x00)};
    fake[`loadNative]:{[p;i]
      (enlist `identity)!enlist p,"#after"};
    fake:.utl.fsFactory fake;
    beforeState:.utl.requireStateSnapshot[];
    outcome:.[.utl.requireWith;(fake;target);{[e]e}];
    afterState:.utl.requireStateSnapshot[];
    .tst.testState.restoreRequireV2 saved;
    must[not (::)~outcome;"identity mismatch must signal"];
    must[afterState~beforeState;
      "identity failure must restore all require-owned state"];
  };

  should["retain captured require authority after module execution"]{
    saved:.tst.testState.requireV2Snapshot[];
    oldValidator:.utl.validateRequireStateWith;
    oldRoom:.utl.requireRoomWith;
    oldDependencyRoom:.utl.dependencyRoomWith;
    oldPublisher:.utl.publishDependencyWith;
    oldPathWriter:.utl.pathToHsymWith;
    oldPathValidator:.utl.validatePathSymbolRegistry;
    oldHardLimit:.utl.hardLimit;
    oldPathTexts:.utl.pathSymbolTexts;
    oldPathBytes:.utl.pathSymbolBytes;
    target:.utl.absolutePath ".require-v2-captured-authority.q";
    fake:.utl.fsSnapshot[];
    fake[`readRegular]:{[p;n]
      `path`identity`bytes!(p;p,"#stable";0x00)};
    fake[`loadNative]:{[p;i]
      .utl.validateRequireStateWith:{[x]'"poisoned validator"};
      .utl.requireRoomWith:{[a;b;c;d]'"poisoned room"};
      .utl.dependencyRoomWith:{[a;b;c]'"poisoned dependency room"};
      .utl.publishDependencyWith:{[a;b;c]'"poisoned publisher"};
      .utl.pathToHsymWith:{[a;b;c;d;e;f;g]'"poisoned path writer"};
      .utl.validatePathSymbolRegistry:{[]'"poisoned path registry"};
      .utl.hardLimit:{[a;b;c]'"poisoned hard limit"};
      (enlist `identity)!enlist i};
    fake:.utl.fsFactory fake;
    outcome:.[.utl.requireWith;(fake;target);{[e]e}];
    loadedAfter:.utl.loaded;
    `.utl.validateRequireStateWith set oldValidator;
    `.utl.requireRoomWith set oldRoom;
    `.utl.dependencyRoomWith set oldDependencyRoom;
    `.utl.publishDependencyWith set oldPublisher;
    `.utl.pathToHsymWith set oldPathWriter;
    `.utl.validatePathSymbolRegistry set oldPathValidator;
    `.utl.hardLimit set oldHardLimit;
    .utl.pathSymbolTexts:oldPathTexts;
    .utl.pathSymbolBytes:oldPathBytes;
    .tst.testState.restoreRequireV2 saved;
    outcome musteq (::);
    must[target in loadedAfter;
      "successful execution must remain admitted"];
  };

  should["roll back loaded and dependency truth when publication fails"]{
    saved:.tst.testState.requireV2Snapshot[];
    target:.utl.absolutePath ".require-v2-publish.q";
    caller:.utl.absolutePath ".require-v2-caller.q";
    `.utl.FILELOADING set .utl.pathToHsym caller;
    fake:.utl.fsSnapshot[];
    fake[`readRegular]:{[p;n]
      `path`identity`bytes!(p;p,"#stable";0x00)};
    fake[`loadNative]:{[p;i]
      `.utl.testDeps set 42;
      (enlist `identity)!enlist i};
    fake:.utl.fsFactory fake;
    beforeState:.utl.requireStateSnapshot[];
    outcome:.[.utl.requireWith;(fake;target);{[e]e}];
    afterState:.utl.requireStateSnapshot[];
    .tst.testState.restoreRequireV2 saved;
    must[not (::)~outcome;"dependency publication failure must signal"];
    must[afterState~beforeState;
      "publication failure must restore all require-owned state"];
  };

  should["preflight all dependency path symbols before admission"]{
    saved:.tst.testState.requireV2Snapshot[];
    oldTexts:.utl.pathSymbolTexts;
    oldBytes:.utl.pathSymbolBytes;
    oldLimit:.utl.MAX_PATH_SYMBOLS;
    suffix:string .z.p;
    caller:(system "cd"),"/.require-v2-admission-caller-",suffix;
    target:(system "cd"),"/.require-v2-admission-target-",suffix;
    .utl.MAX_PATH_SYMBOLS:1+count oldTexts;
    beforeState:.utl.requireStateSnapshot[];
    outcome:.[.utl.publishDependency;(caller;target);{[e]e}];
    afterState:.utl.requireStateSnapshot[];
    pathState:(.utl.pathSymbolTexts;.utl.pathSymbolBytes);
    .utl.MAX_PATH_SYMBOLS:oldLimit;
    .utl.pathSymbolTexts:oldTexts;
    .utl.pathSymbolBytes:oldBytes;
    .tst.testState.restoreRequireV2 saved;
    must[not (::)~outcome;"two-path admission overflow must signal"];
    must[afterState~beforeState;
      "failed preflight must not publish dependency truth"];
    must[pathState~(oldTexts;oldBytes);
      "failed preflight must not consume path-symbol budget"];
  };

  should["retain the original require error when rollback also fails"]{
    oldRestore:.utl.restoreRequireState;
    target:.utl.absolutePath ".require-v2-double-failure.q";
    fake:.utl.fsSnapshot[];
    fake[`readRegular]:{[p;n]'"original read failure"};
    fake[`loadNative]:{[p;i]'"unexpected load"};
    fake:.utl.fsFactory fake;
    .utl.restoreRequireState:{[a;b;c;d]'"rollback failure"};
    outcome:.[.utl.requireWith;(fake;target);{[e]e}];
    `.utl.restoreRequireState set oldRestore;
    must[outcome like "*original read failure*";
      "combined diagnostic must retain original failure"];
    must[outcome like "*rollback failure*";
      "combined diagnostic must retain rollback failure"];
  };

  should["reject malformed cyclic and full require guards before I/O"]{
    saved:.tst.testState.requireV2Snapshot[];
    oldDepth:.utl.MAX_REQUIRE_DEPTH;
    .utl.MAX_REQUIRE_DEPTH:64;
    target:.utl.absolutePath ".require-v2-never-read.q";
    fake:.utl.fsSnapshot[];
    .tst.testState.requireV2ReadCalls:0;
    fake[`readRegular]:{[p;n]
      .tst.testState.requireV2ReadCalls+:1;
      '"unexpected read"};
    fake[`loadNative]:{[p;i]'"unexpected load"};
    fake:.utl.fsFactory fake;
    .utl.loadingPaths:42;
    malformed:.[.utl.requireWith;(fake;target);{[e]e}];
    malformedGuard:.utl.loadingPaths;
    .utl.loadingPaths:(target;target);
    duplicate:.[.utl.requireWith;(fake;target);{[e]e}];
    duplicateGuard:.utl.loadingPaths;
    .utl.loadingPaths:enlist target;
    cycle:.[.utl.requireWith;(fake;target);{[e]e}];
    cycleGuard:.utl.loadingPaths;
    depthPaths:{[prefix;i]prefix,"-",string i}[target;] each til 64;
    .utl.loadingPaths:depthPaths;
    depth:.[.utl.requireWith;(fake;target);{[e]e}];
    depthGuard:.utl.loadingPaths;
    truthAfter:(.utl.loaded;.utl.loadedIds;.utl.dependencyText);
    .utl.MAX_REQUIRE_DEPTH:oldDepth;
    .tst.testState.restoreRequireV2 saved;
    must[not (::)~malformed;"malformed guard must signal"];
    must[not (::)~duplicate;"duplicate guard must signal"];
    must[not (::)~cycle;"cycle must signal"];
    must[not (::)~depth;"full-depth guard must signal"];
    malformedGuard musteq 42;
    duplicateGuard musteq (target;target);
    cycleGuard musteq enlist target;
    must[depthGuard~depthPaths;"depth guard must remain unchanged"];
    must[truthAfter~
      (saved`loaded;saved`loadedIds;saved`dependencyText);
      "rejected guards must not publish require truth"];
    .tst.testState.requireV2ReadCalls musteq 0;
  };
};

.tst.testState.loadV2Snapshot:{[]
  `specs`loaded`empty`errors`runtime!(
    .tst.app.allSpecs;
    .tst.app.loadedFiles;
    .tst.app.emptyFiles;
    .tst.app.loadErrors;
    .tst.captureRuntimeContext[])};
.tst.testState.restoreLoadV2:{[saved]
  `.tst.app.allSpecs set saved`specs;
  `.tst.app.loadedFiles set saved`loaded;
  `.tst.app.emptyFiles set saved`empty;
  `.tst.app.loadErrors set saved`errors;
  .tst.restoreRuntimeContext saved`runtime;
  (::)};
.tst.testState.loadV2Read:{[p;n]
  `path`identity`bytes!(
    .tst.testState.loadV2Path;
    .tst.testState.loadV2Path,"#test";
    .tst.testState.loadV2Bytes)};

.tst.desc["Transactional test-source loading v2"]{
  should["use a captured strict restorer after legacy helper replacement"]{
    saved:.tst.captureRuntimeContext[];
    ops:.tst.loaderOps[];
    oldRestore:.tst.restoreRuntimeContext;
    root:.tst.tempFile "";
    .utl.ensureDir root;
    .tst.restoreRuntimeContext:{[ctx]'"replaced legacy restorer"};
    .tst.context:`mutated;
    .tst.tstPath:`:mutated.q;
    .tst.currentNs:`.mutated;
    `.utl.FILELOADING set `:mutated.q;
    system "cd ",root;
    system "d .q";
    outcome:@[ops`restore;saved;{[e]e}];
    observed:.tst.captureRuntimeContext[];
    `.tst.restoreRuntimeContext set oldRestore;
    outcome musteq (::);
    observed musteq saved;
  };

  should["attempt every context field and enforce the full postcondition"]{
    saved:.tst.captureRuntimeContext[];
    .tst.testState.loadV2RestoreAttempts:0;
    fakeAttempt:{[function;arguments]
      .tst.testState.loadV2RestoreAttempts+:1;
      $[1=.tst.testState.loadV2RestoreAttempts;
        (0b;"forced field failure");
        .utl.attempt[function;arguments]]};
    outcome:.[.tst.restoreRuntimeContextStrict;
      (fakeAttempt;.utl.boundedDiagnostic;.utl.pathToString;
       .tst.captureRuntimeContext;saved);{[e]e}];
    attempts:.tst.testState.loadV2RestoreAttempts;
    observed:.tst.captureRuntimeContext[];
    must[not (::)~outcome;"one field failure must signal"];
    attempts musteq 7;
    observed musteq saved;
  };

  should["reject a restoration whose recaptured context mismatches"]{
    saved:.tst.captureRuntimeContext[];
    wrong:saved;
    wrong[`currentNs]:`.wrong;
    .tst.testState.loadV2WrongContext:wrong;
    fakeCapture:{[].tst.testState.loadV2WrongContext};
    outcome:.[.tst.restoreRuntimeContextStrict;
      (.utl.attempt;.utl.boundedDiagnostic;.utl.pathToString;
       fakeCapture;saved);{[e]e}];
    observed:.tst.captureRuntimeContext[];
    must[not (::)~outcome;"postcondition mismatch must signal"];
    observed musteq saved;
  };

  should["reject malformed runtime snapshots before mutating process state"]{
    saved:.tst.captureRuntimeContext[];
    malformed:saved;
    malformed[`currentNs]:42;
    outcome:.[.tst.restoreRuntimeContextStrict;
      (.utl.attempt;.utl.boundedDiagnostic;.utl.pathToString;
       .tst.captureRuntimeContext;malformed);{[e]e}];
    observed:.tst.captureRuntimeContext[];
    .tst.restoreRuntimeContext saved;
    must[not (::)~outcome;"malformed context must signal"];
    observed musteq saved;
  };

  should["reject newline-dense input before preprocessing or context capture"]{
    saved:.tst.testState.loadV2Snapshot[];
    ops:.tst.loaderOps[];
    .tst.testState.loadV2Path:
      .utl.absolutePath ".loader-v2-dense.q";
    .tst.testState.loadV2Bytes:9#0x0a;
    .tst.testState.loadV2PreprocessCalls:0;
    .tst.testState.loadV2EvaluateCalls:0;
    .tst.testState.loadV2CaptureCalls:0;
    ops[`fs]:(enlist `readRegular)!enlist .tst.testState.loadV2Read;
    ops[`lineLimit]:4;
    ops[`preprocess]:{[x]
      .tst.testState.loadV2PreprocessCalls+:1;x};
    ops[`evaluate]:{[x]
      .tst.testState.loadV2EvaluateCalls+:1};
    ops[`capture]:{[]
      .tst.testState.loadV2CaptureCalls+:1;
      .tst.captureRuntimeContext[]};
    outcome:.[.tst.loadOne;
      (ops;.tst.testState.loadV2Path);{[e]e}];
    specsAfter:.tst.app.allSpecs;
    loadedAfter:.tst.app.loadedFiles;
    emptyAfter:.tst.app.emptyFiles;
    runtimeAfter:.tst.captureRuntimeContext[];
    errorRows:(count .tst.app.loadErrors)-count saved`errors;
    errorType:$[errorRows;last[.tst.app.loadErrors]`type;`missing];
    .tst.testState.restoreLoadV2 saved;
    outcome musteq ();
    .tst.testState.loadV2PreprocessCalls musteq 0;
    .tst.testState.loadV2EvaluateCalls musteq 0;
    .tst.testState.loadV2CaptureCalls musteq 0;
    must[specsAfter~saved`specs;"dense source must not change specs"];
    must[loadedAfter~saved`loaded;
      "dense source must not change the loaded-file registry"];
    emptyAfter musteq saved`empty;
    runtimeAfter musteq saved`runtime;
    errorRows musteq 1;
    errorType musteq `read;
  };

  should["contain context acquisition failure as a per-file load error"]{
    saved:.tst.testState.loadV2Snapshot[];
    ops:.tst.loaderOps[];
    .tst.testState.loadV2Path:
      .utl.absolutePath ".loader-v2-context.q";
    .tst.testState.loadV2Bytes:"x"$"x:1;";
    .tst.testState.loadV2PreprocessCalls:0;
    .tst.testState.loadV2EvaluateCalls:0;
    ops[`fs]:(enlist `readRegular)!enlist .tst.testState.loadV2Read;
    ops[`capture]:{[]'"capture failed"};
    ops[`preprocess]:{[x]
      .tst.testState.loadV2PreprocessCalls+:1;x};
    ops[`evaluate]:{[x]
      .tst.testState.loadV2EvaluateCalls+:1};
    outcome:.[.tst.loadOne;
      (ops;.tst.testState.loadV2Path);{[e]e}];
    specsAfter:.tst.app.allSpecs;
    loadedAfter:.tst.app.loadedFiles;
    emptyAfter:.tst.app.emptyFiles;
    runtimeAfter:.tst.captureRuntimeContext[];
    errorRows:(count .tst.app.loadErrors)-count saved`errors;
    errorType:$[errorRows;last[.tst.app.loadErrors]`type;`missing];
    .tst.testState.restoreLoadV2 saved;
    outcome musteq ();
    .tst.testState.loadV2PreprocessCalls musteq 0;
    .tst.testState.loadV2EvaluateCalls musteq 0;
    must[specsAfter~saved`specs;"capture failure must not change specs"];
    must[loadedAfter~saved`loaded;
      "capture failure must not change the loaded-file registry"];
    emptyAfter musteq saved`empty;
    runtimeAfter musteq saved`runtime;
    errorRows musteq 1;
    errorType musteq `context;
  };

  should["retain captured attempt authority after executing test source"]{
    saved:.tst.testState.loadV2Snapshot[];
    ops:.tst.loaderOps[];
    originalAttempt:.utl.attempt;
    .tst.testState.loadV2OriginalAttempt:originalAttempt;
    .tst.testState.loadV2PoisonCalls:0;
    .tst.testState.loadV2Path:
      .utl.absolutePath ".loader-v2-attempt-authority.q";
    .tst.testState.loadV2Bytes:"x"$"ignored";
    ops[`fs]:(enlist `readRegular)!enlist .tst.testState.loadV2Read;
    ops[`capture]:{[]`saved!enlist 1};
    ops[`execute]:{[capsule;p;content;ns]
      .utl.attempt:{[function;arguments]
        .tst.testState.loadV2PoisonCalls+:1;
        .tst.testState.loadV2OriginalAttempt[function;arguments]}};
    ops[`restore]:{[ctx]
      `.utl.attempt set .tst.testState.loadV2OriginalAttempt;
      (::)};
    ops[`strict]:0b;
    outcome:.[.tst.loadOne;
      (ops;.tst.testState.loadV2Path);{[e]e}];
    calls:.tst.testState.loadV2PoisonCalls;
    `.utl.attempt set originalAttempt;
    .tst.testState.restoreLoadV2 saved;
    outcome musteq (::);
    calls musteq 0;
  };

  should["roll back a successful body when context restoration fails"]{
    saved:.tst.testState.loadV2Snapshot[];
    ops:.tst.loaderOps[];
    .tst.testState.loadV2Path:
      .utl.absolutePath ".loader-v2-restore.q";
    .tst.testState.loadV2Bytes:"x"$"ignored";
    spec:.tst.internals.specObj;
    spec[`title]:"transactional";
    spec[`expectations]:();
    spec[`namespace]:`.sandbox_S_transactional;
    spec[`tstPath]:`$":transactional.q";
    spec[`beforeAll]:{};
    spec[`afterAll]:{};
    .tst.testState.loadV2Spec:spec;
    .tst.testState.loadV2Clears:0;
    ops[`fs]:(enlist `readRegular)!enlist .tst.testState.loadV2Read;
    ops[`capture]:{[]`saved!enlist 1};
    ops[`execute]:{[capsule;p;content;ns]
      .tst.app.allSpecs,:enlist .tst.testState.loadV2Spec};
    ops[`restore]:{[ctx]
      .tst.app.loadedFiles:enlist "polluted";
      '"restore failed"};
    ops[`clearSandbox]:{[ns]
      .tst.testState.loadV2Clears+:1};
    outcome:.[.tst.loadOne;
      (ops;.tst.testState.loadV2Path);{[e]e}];
    specsAfter:.tst.app.allSpecs;
    loadedAfter:.tst.app.loadedFiles;
    emptyAfter:.tst.app.emptyFiles;
    errorRows:(count .tst.app.loadErrors)-count saved`errors;
    errorType:$[errorRows;last[.tst.app.loadErrors]`type;`missing];
    .tst.testState.restoreLoadV2 saved;
    outcome musteq ();
    must[specsAfter~saved`specs;
      "restore failure must roll back appended specs"];
    must[loadedAfter~saved`loaded;
      "restore failure must roll back the loaded-file registry"];
    emptyAfter musteq saved`empty;
    .tst.testState.loadV2Clears musteq 1;
    errorRows musteq 1;
    errorType musteq `cleanup;
  };

  should["reject prefix replacement and malformed appended specs"]{
    saved:.tst.testState.loadV2Snapshot[];
    ops:.tst.loaderOps[];
    .tst.testState.loadV2Path:
      .utl.absolutePath ".loader-v2-specs.q";
    .tst.testState.loadV2Bytes:"x"$"ignored";
    .tst.testState.loadV2Clears:0;
    ops[`fs]:(enlist `readRegular)!enlist .tst.testState.loadV2Read;
    ops[`capture]:{[]`saved!enlist 1};
    ops[`restore]:{[ctx](::)};
    ops[`clearSandbox]:{[ns]
      .tst.testState.loadV2Clears+:1};
    ops[`execute]:{[capsule;p;content;ns]
      specs:.tst.app.allSpecs;
      replacement:specs 0;
      replacement[`title]:"replaced prefix";
      specs[0]:replacement;
      .tst.app.allSpecs:specs};
    prefixOutcome:.[.tst.loadOne;
      (ops;.tst.testState.loadV2Path);{[e]e}];
    prefixRestored:.tst.app.allSpecs~saved`specs;
    prefixErrors:(count .tst.app.loadErrors)-count saved`errors;
    `.tst.app.loadErrors set saved`errors;
    ops[`execute]:{[capsule;p;content;ns]
      bad:.tst.app.allSpecs 0;
      bad[`beforeAll]:42;
      .tst.app.allSpecs,:enlist bad};
    appendOutcome:.[.tst.loadOne;
      (ops;.tst.testState.loadV2Path);{[e]e}];
    appendRestored:.tst.app.allSpecs~saved`specs;
    appendErrors:(count .tst.app.loadErrors)-count saved`errors;
    .tst.testState.restoreLoadV2 saved;
    prefixOutcome musteq ();
    appendOutcome musteq ();
    prefixRestored musteq 1b;
    appendRestored musteq 1b;
    prefixErrors musteq 1;
    appendErrors musteq 1;
    .tst.testState.loadV2Clears musteq 2;
  };
};
