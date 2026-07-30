\d .tst
if[not `fixtures in key `.tst;fixtures::(`symbol$())!()];
if[not `cleanupTasks in key `.tst;cleanupTasks::()];
if[not `specCleanupTasks in key `.tst;specCleanupTasks::()];
if[not `cleanupDrainActive in key `.tst;.tst.cleanupDrainActive:0b];
if[not `tempCounter in key `.tst;.tst.tempCounter:0j];
if[not `currentDirFixture in key `.tst;currentDirFixture:`];
if[not `savedDir in key `.tst;
    savedDir:`directory`vars`context`loaded!(
        "";(`symbol$())!();`.;0b)];
.tst.MAX_FIXTURES:1024;
.tst.MAX_FIXTURE_NAME_BYTES:65536;
.tst.MAX_CLEANUP_TASKS:1024;
.tst.MAX_FIXTURE_BYTES:8388608;
.tst.MAX_FIXTURE_ENTRIES:4096;
.tst.MAX_TEMP_ENTRIES:4096;
.tst.isCallable:{[x]type[x] within 100 112h};
.tst.leafText:{[x;allowEmpty;label]
    if[not type[x] in 10 -11h;
        '"Invalid ",label,": expected a string or symbol"]; text:$[10h=type x;x;string x];
    if[(not allowEmpty) and 0=count text;
        '"Invalid ",label,": must not be empty"];
    if[count[text]>255;'"Invalid ",label,": exceeds 255 characters"];
    if[(any text~/:(".";"..")) or any text in "/\\:";
        '"Invalid ",label,": expected one path-safe leaf"]; if[any ("i"$text) in (til 32),127;
        '"Invalid ",label,": contains a control character"]; text};
/ Executes every validated item and retains every malformed/failed item.
.tst.attemptAll:{[items;validator;executor]
    callable:.tst.isCallable; render:.utl.boundedDiagnostic;
    attempt:.utl.attempt;
    if[not callable validator;'"Invalid cleanup validator"];
    if[not callable executor;'"Invalid cleanup executor"];
    sequence:$[type[items] in 0 11 98h;items;enlist items];
    limit:.utl.hardLimit[.tst.MAX_CLEANUP_TASKS;1024;"cleanup task"];
    if[count[sequence]>limit;'"Cleanup task limit exceeded"]; failed:count[sequence]#0b;
    details:(); i:0; while[i<count sequence;
        checked:attempt[validator;enlist sequence i]; result:$[first checked;
            attempt[executor;enlist sequence i]; checked]; if[not first result;
            failed[i]:1b; if[count[details]<8;
                details,:enlist "item ",string[i],": ",
                    render[last result;384]]]; i+:1]; `failed`remaining`failureCount`details!(
        failed;sequence where failed;sum failed;details)};
.tst.noteFailureWith:{[diagnostic;result;text]
    result[`failureCount]+:1; if[count[result`details]<8;
        result[`details],:enlist diagnostic[text;384]]; result};
.tst.noteFailure:{[result;text]
    .tst.noteFailureWith[
        .utl.boundedDiagnostic;result;text]};
.tst.raiseAttemptFailuresWith:{[diagnostic;label;result]
    if[0=result`failureCount;:(::)];
    message:label," failed (",string[result`failureCount]," task(s))";
    if[count result`details;message,:": ","; " sv result`details];
    'diagnostic[message;4096]};
.tst.raiseAttemptFailures:{[label;result]
    .tst.raiseAttemptFailuresWith[
        .utl.boundedDiagnostic;label;result]};
.tst.validateFixtureName:{[name]
    if[not -11h=type name;'"Invalid fixture name: expected a symbol atom"]; text:string name;
    if[(name~`) or 0=count text;'"Invalid fixture name: must not be empty"];
    if[count[text]>128;'"Invalid fixture name: exceeds 128 bytes"]; (::)};
.tst.validateFixtureRecord:{[record]
    if[(not 99h=type record) or
       not `val`scope`setup`teardown`instance~key record;
        '"Invalid fixture record"];
    if[not record[`scope] in `test`session;'"Invalid fixture scope"];
    if[not all .tst.isCallable each record`setup`teardown;
        '"Invalid fixture callable"]; (::)};
.tst.validateFixtureRegistry:{[]
    if[not 99h=type .tst.fixtures;'"Invalid fixture registry"]; names:key .tst.fixtures;
    if[count[names]>.utl.hardLimit[.tst.MAX_FIXTURES;1024;"fixture"];
        '"Fixture registry limit exceeded"]; if[count names;
        if[not 11h=type names;'"Invalid fixture registry names"];
        if[not 98h=type value .tst.fixtures;
            '"Invalid fixture registry storage"];
        if[(sum count each string each names)>
           .utl.hardLimit[.tst.MAX_FIXTURE_NAME_BYTES;65536;"fixture name-byte"];
            '"Fixture registry name-byte limit exceeded"]; .tst.validateFixtureName each names;
        i:0;
        while[i<count names;
            record:.tst.fixtures names i;
            .tst.validateFixtureRecord record;
            i+:1]];
    (::)};
.tst.fixtureDefinition:{[val;opts]
    if[not 99h=type opts;'"Invalid fixture options"];
    if[not all key[opts] in `scope`setup`teardown;'"Invalid fixture option"];
    record:`val`scope`setup`teardown`instance!(val;`test;{};{};(::));
    if[count opts;record:record,opts];
    .tst.validateFixtureRecord record; record};
registerFixture:{[name;val].tst.registerFixtureWithOpts[name;val;()!()]};
registerFixtureWithOpts:{[name;val;opts]
    .tst.validateFixtureName name; .tst.validateFixtureRegistry[];
    if[0=count .tst.fixtures;.tst.fixtures:(`symbol$())!()];
    exists:name in key .tst.fixtures; if[not exists;
        if[count[.tst.fixtures]>=
           .utl.hardLimit[.tst.MAX_FIXTURES;1024;"fixture"];
            '"Fixture registry limit exceeded"];
        if[(sum count each string each (key[.tst.fixtures],name))>
           .utl.hardLimit[.tst.MAX_FIXTURE_NAME_BYTES;65536;"fixture name-byte"];
            '"Fixture registry name-byte limit exceeded"]]; if[exists;
        old:.tst.fixtures name; .tst.validateFixtureRecord old;
    if[not (::)~old`instance;
            '"Cannot replace a fixture with a live session instance"]];
    record:.tst.fixtureDefinition[val;opts];
    registry:.tst.fixtures; names:key registry;
    if[not exists;names,:name];
    if[1=count names;rows:enlist record];
    if[1<count names;
        fields:`val`scope`setup`teardown`instance;
        columns:{[source;fixtureNames;target;replacement;field]
            {[registry;wanted;newRecord;column;fixtureName]
                row:$[fixtureName~wanted;
                    newRecord;
                    registry fixtureName];
                row column}[
                    source;target;replacement;field;]
              each fixtureNames}[
                registry;names;name;record;] each fields;
        rows:flip fields!columns];
    if[(not 98h=type rows) or count[rows]<>count names;
        '"Unable to rebuild fixture registry"];
    `.tst.fixtures set names!rows;
    (::)};
getFixture:{[name]
    .tst.validateFixtureName name; .tst.validateFixtureRegistry[];
    if[not name in key .tst.fixtures;'"Fixture not found: ",string name]; f:.tst.fixtures name;
    if[((f`scope)~`session) and not (::)~f`instance;:f`instance]; v:$[f[`setup]~{};f`val;
        @[f`setup;f`val;{[n;e]
            '"Setup failed for ",string[n],": ",
              .utl.boundedDiagnostic[e;512]}[name]]]; if[(f`scope)~`session;
        if[(not name in key .tst.fixtures) or not f~.tst.fixtures name;
            cleanup:.utl.attempt[
                {[g;x]if[not g~{};g x]};(f`teardown;v)]; if[not first cleanup;
                '"Fixture registry changed during setup; teardown failed: ",
                  .utl.boundedDiagnostic[last cleanup;512]];
            '"Fixture registry changed during setup"];
        .tst.fixtures[name;`instance]:v]; v};
.tst.teardownFixture:{[name;val]
    attempt:.utl.attempt;
    diagnostic:.utl.boundedDiagnostic;
    checkName:.tst.validateFixtureName;
    checkRecord:.tst.validateFixtureRecord;
    read:{[]get `.tst.fixtures};
    selected:attempt[{[reader;validateName;validateRecord;fixtureName]
        validateName fixtureName;
        registry:reader[];
        if[not 99h=type registry;'"Invalid fixture registry"];
        if[not fixtureName in key registry;:(::)];
        record:registry fixtureName;
        validateRecord record;
        record};(read;checkName;checkRecord;name)];
    label:$[-11h=type name;string name;"<invalid>"];
    if[not first selected;
        -1 "ERROR cleaning fixture '",label,"': ",
          diagnostic[last selected;512];
        :(::)];
    record:last selected;
    if[(::)~record;:(::)];
    if[record[`teardown]~{};:(::)];
    outcome:attempt[record`teardown;enlist val];
    if[not first outcome;
        -1 "ERROR cleaning fixture '",label,"': ",
          diagnostic[last outcome;512]];
    (::)};
/ Cleanup builders capture immutable authority before test code can replace helpers.
.tst.cleanupAllFixturesWith:{[dependencies;ignored]
    read:dependencies`read; write:dependencies`write;
    attempt:dependencies`attempt; attemptAll:dependencies`attemptAll;
    note:dependencies`note; finish:dependencies`finish;
    checkName:dependencies`checkName; checkRecord:dependencies`checkRecord;
    captured:attempt[read;()]; if[not first captured;'last captured];
    registry:last captured;
    if[not 99h=type registry;'"Invalid fixture registry"]; if[0=count registry;:()];
    names:key registry;
    result:attemptAll[
        names; {[captured;validateName;validateRecord;name]
            validateName name;
            validateRecord captured name}[registry;checkName;checkRecord;];
        {[captured;name]
            f:captured name; if[(f`scope)~`session;
                if[not (::)~f`instance;
                    if[not f[`teardown]~{};f[`teardown] f`instance]]]}[registry;]];
    current:attempt[read;()];
    changed:(not first current) or not registry~last current;
    canonical:98h=type value registry;
    if[canonical;
        fields:`val`scope`setup`teardown`instance;
        columns:{[captured;fixtureNames;failed;field]
            {[source;names;failures;column;i]
                row:source names i;
                $[(column~`instance) and
                  (not failures i) and row[`scope]~`session;
                    (::);
                    row column]}[
                    captured;fixtureNames;failed;field;]
              each til count fixtureNames}[
                registry;names;result`failed;] each fields;
        restoredRegistry:names!flip fields!columns];
    if[not canonical;
        restoredRegistry:registry; i:0; while[i<count names;
            f:registry names i; if[not result[`failed] i;
                if[(f`scope)~`session;
                    f[`instance]:(::);
                    restoredRegistry[names i]:f]];
            i+:1]];
    written:attempt[write;enlist restoredRegistry];
    if[not first written;result:note[
        result;"fixture ownership restoration failed"]];
    if[changed;result:note[
        result;"fixture registry changed during teardown; restored"]];
    finish["Fixture teardown";result];
    (::)};
.tst.makeFixtureCleanup:{[]
    read:{[]get `.tst.fixtures};
    write:{[registry]`.tst.fixtures set registry;(::)};
    diagnostic:.utl.boundedDiagnostic;
    dependencies:
      `read`write`attempt`attemptAll`note`finish`checkName`checkRecord!(
        read;write;.utl.attempt;.tst.attemptAll;
        .tst.noteFailureWith[diagnostic];
        .tst.raiseAttemptFailuresWith[diagnostic];
        .tst.validateFixtureName;
        .tst.validateFixtureRecord);
    .tst.cleanupAllFixturesWith[dependencies;]};
.tst.runCleanupPublic:{[capsule;prefix]
    attempt:.utl.attempt;
    diagnostic:.utl.boundedDiagnostic;
    outcome:attempt[capsule;()];
    if[not first outcome;
        -1 prefix,diagnostic[last outcome;1024]];
    (::)};
cleanupAllFixtures:{[]
    capsule:.tst.makeFixtureCleanup[];
    .tst.runCleanupPublic[
        capsule;"ERROR cleaning fixtures: "]};
fixtureInDir:{[fname;dir]
    target:.tst.leafText[fname;0b;"fixture name"]; fs:.utl.fsSnapshot[];
    state:@[(fs`inspect);dir;{[e]'"Fixture directory inspection failed: ",e}];
    if[not state[`kind]~`dir;:""]; entries:((fs`list)[state`path;
        .utl.hardLimit[.tst.MAX_FIXTURE_ENTRIES;4096;"fixture entry"]; 1048576])`entries;
    matches:entries where {[wanted;n]
        (n~wanted) or (first["." vs n])~wanted}[target;] each entries; if[0=count matches;:""];
    exact:matches where target~/:matches; if[1<count exact;'"Ambiguous fixture name"];
    if[(0=count exact) and 1<count matches;'"Ambiguous fixture name"];
    state[`path],"/",first $[count exact;exact;matches]};
fixtureAs:{[fixtureName;name]
    path:.utl.pathToString .tst.tstPath; parts:"/" vs path;
    dir:"/" sv -1 _ parts; if[0=count dir;dir:$[(0<count path) and "/"=first path;"/";"."]];
    found:.tst.fixtureInDir[fixtureName;dir]; fixtureDir:dir,"/fixtures";
    if[(0=count found) and .utl.isDir fixtureDir;
        found:.tst.fixtureInDir[fixtureName;fixtureDir]]; if[0=count found;
        '"Error loading fixture ",.tst.toString[fixtureName],
          ", not found in ",dir]; loaded:.tst.loadFixture[found;name]; loaded^name};
fixture:.tst.fixtureAs[;`];
.tst.fixtureSymbol:{[path;stripExtension]
    base:last "/" vs path; parts:"." vs base;
    if[stripExtension and 1<count parts;base:"." sv -1 _ parts]; `$base};
loadFixture:{[path;name]
    p:.utl.absolutePath path; state:((.utl.fsSnapshot[])`inspect) p;
    extension:lower last "." vs last "/" vs p; $[extension in ("txt";"csv";"psv";"tsv");
        .tst.loadFixtureTxt[p;name]; state[`kind]~`file;
        .tst.loadFixtureFile[p;name]; state[`kind]~`dir;
        .tst.loadFixtureDir[p;name]; '"Fixture path does not exist"]};
loadFixtureTxt:{[path;name]
    fs:.utl.fsSnapshot[]; read:(fs`readRegular)[path;
        .utl.hardLimit[.tst.MAX_FIXTURE_BYTES;8388608;"fixture byte"]];
    lines:.utl.textLines read`bytes;
    if[(2>count lines) or 2>count first lines;'"Malformed text fixture"]; content:@[{[rows]
        (raze rows[0;1] vs rows 0;enlist rows[0;1]) 0:1 _ rows};
        lines;{[e]'"Text fixture decode failed: ",
            .utl.boundedDiagnostic[e;512]}]; fname:(.tst.fixtureSymbol[read`path;1b])^name;
    .tst.validateFixtureName fname; mocker:.tst.mock;
    mocker[fname;content]; fname};
loadFixtureFile:{[path;name]
    fs:.utl.fsSnapshot[]; read:(fs`readRegular)[path;
        .utl.hardLimit[.tst.MAX_FIXTURE_BYTES;8388608;"fixture byte"]]; decoded:@[{[bytes]
        serialized:"c"$bytes; -9!serialized};read`bytes; {[e]'"Binary fixture decode failed: ",
          .utl.boundedDiagnostic[e;512]}]; fname:(.tst.fixtureSymbol[read`path;0b])^name;
    .tst.validateFixtureName fname; mocker:.tst.mock;
    mocker[fname;decoded]; fname};
findDirVars:{
    $[0<count where -1h=(type .Q.qp get @) each
        ` sv' `.,'tables `.; [c:distinct @[get;`.Q.pf;()],@[get;`.Q.pt;()],
          pvals where not any (pvals:key `:.) like/:
            (string @[get;`.Q.pv;()]),enlist "par.txt"; c where c in key `.]; ()]};
.tst.clearDirStateWith:{[dependencies;ignored]
    findVars:dependencies`findVars;
    attemptAll:dependencies`attemptAll;
    finish:dependencies`finish;
    context:system "d"; names:distinct tables[],findVars[];
    tasks:{(enlist `name)!enlist x} each names; result:attemptAll[
        tasks; {[task]
            if[(not 99h=type task) or not enlist[`name]~key task;
                '"Invalid directory cleanup task"];
            if[not -11h=type task`name;'"Invalid directory variable"]};
        {[ctx;task]![ctx;();0b;enlist task`name]}[context;]];
    finish["Directory cleanup";result];
    (::)};
.tst.makeDirClear:{[]
    diagnostic:.utl.boundedDiagnostic;
    dependencies:`findVars`attemptAll`finish!(
        .tst.findDirVars;
        .tst.attemptAll;
        .tst.raiseAttemptFailuresWith[diagnostic]);
    .tst.clearDirStateWith[dependencies;]};
.tst.clearDirState:{[]
    capsule:.tst.makeDirClear[];
    capsule[]};
.tst.emptySavedDir:{[]
    `directory`vars`context`loaded!(
        "";(`symbol$())!();`.;0b)};
.tst.validateSavedDir:{[snapshot]
    required:`directory`vars`context`loaded;
    if[not 99h=type snapshot;'"Invalid saved directory state"];
    if[(count[key snapshot]<>count required) or
       (not all required in key snapshot);
        '"Invalid saved directory state"];
    if[(not 10h=type snapshot`directory) or
       (not 99h=type snapshot`vars) or
       (not -11h=type snapshot`context) or
       not -1h=type snapshot`loaded;
        '"Invalid saved directory state"];
    if[not 11h=type key snapshot`vars;
        '"Invalid saved directory variables"];
    (::)};
.tst.restoreSavedDirWith:{
    [attempt;diagnostic;clearState;loader;validate;snapshot]
    validate snapshot;
    original:system "d";
    outcome:attempt[{[clear;loadPath;saved]
        system "d ",string saved`context;
        clear[];
        $[saved`loaded;
            loadPath saved`directory;
            system "cd ",saved`directory];
        if[count saved`vars;
            (key saved`vars) set' value saved`vars];
        (::)};(clearState;loader;snapshot)];
    restored:attempt[system;enlist ("d ",string original)];
    if[(not first outcome) or not first restored;
        problems:();
        if[not first outcome;
            problems,:enlist "state: ",
                diagnostic[last outcome;512]];
        if[not first restored;
            problems,:enlist "namespace: ",
                diagnostic[last restored;512]];
        '"Directory fixture restoration failed: ",
          diagnostic["; " sv problems;1536]];
    (::)};
saveDir:{[]
    attempt:.utl.attempt;
    diagnostic:.utl.boundedDiagnostic;
    clear:.tst.makeDirClear[];
    findVars:.tst.findDirVars;
    emptyState:.tst.emptySavedDir;
    validate:.tst.validateSavedDir;
    adapter:.utl.fsSnapshot[];
    loader:adapter`loadPath;
    restoreSaved:.tst.restoreSavedDirWith[
        attempt;diagnostic;clear;loader;validate];
    original:system "d";
    context:$[`context in key `.tst;.tst.context;original];
    captured:attempt[{[find;ctx]
        system "d ",string ctx;
        dirNames:find[];
        names:distinct tables[],dirNames;
        values:$[
            count names;
            names!get each names;
            (`symbol$())!()];
        `directory`vars`context`loaded!(
            system "cd";values;ctx;0<count dirNames)};
        (findVars;context)];
    contextRestored:attempt[system;enlist ("d ",string original)];
    if[(not first captured) or not first contextRestored;
        problems:();
        if[not first captured;
            problems,:enlist diagnostic[last captured;512]];
        if[not first contextRestored;
            problems,:enlist diagnostic[last contextRestored;512]];
        '"Directory fixture snapshot failed: ",
          diagnostic["; " sv problems;1536]];
    snapshot:last captured;
    validate snapshot;
    `.tst.savedDir set snapshot;
    cleared:attempt[{[clearState;ctx]
        system "d ",string ctx;
        clearState[];
        (::)};(clear;context)];
    contextRestored:attempt[system;enlist ("d ",string original)];
    if[(not first cleared) or not first contextRestored;
        problems:();
        if[not first cleared;
            problems,:enlist "cleanup: ",
                diagnostic[last cleared;512]];
        if[not first contextRestored;
            problems,:enlist "namespace: ",
                diagnostic[last contextRestored;512]];
        rollback:attempt[restoreSaved;enlist snapshot];
        if[first rollback;
            `.tst.savedDir set emptyState[];
            `.tst.currentDirFixture set `];
        if[not first rollback;
            `.tst.currentDirFixture set `restore_pending;
            problems,:enlist "rollback: ",
                diagnostic[last rollback;512]];
        '"Directory fixture snapshot failed: ",
          diagnostic["; " sv problems;2048]];
    (::)};
loadFixtureDir:{[path;name]
    attempt:.utl.attempt;
    diagnostic:.utl.boundedDiagnostic;
    p:.utl.absolutePath path;
    adapter:.utl.fsSnapshot[];
    loadPath:adapter`loadPath;
    clear:.tst.makeDirClear[];
    emptyState:.tst.emptySavedDir;
    validate:.tst.validateSavedDir;
    restoreSaved:.tst.restoreSavedDirWith[
        attempt;diagnostic;clear;loadPath;validate];
    saveState:.tst.saveDir;
    fixtureName:.tst.fixtureSymbol[p;0b];
    if[.tst.currentDirFixture~`;
        saveState[]];
    if[not fixtureName~.tst.currentDirFixture;
        previous:.tst.currentDirFixture;
        saved:.tst.savedDir;
        validate saved;
        original:system "d";
        context:$[`context in key `.tst;.tst.context;original];
        loaded:attempt[{[clearState;loader;ctx;target]
            system "d ",string ctx;
            clearState[];
            loader target;
            (::)};(clear;loadPath;context;p)];
        contextRestored:attempt[
            system;enlist ("d ",string original)];
        currentSaved:@[get;`.tst.savedDir;{::}];
        currentFixture:@[get;`.tst.currentDirFixture;{::}];
        ownershipValid:(saved~currentSaved) and
            (previous~currentFixture);
        if[(not first loaded) or
           (not first contextRestored) or
           not ownershipValid;
            problems:();
            if[not first loaded;
                problems,:enlist "load: ",
                    diagnostic[last loaded;512]];
            if[not first contextRestored;
                problems,:enlist "namespace: ",
                    diagnostic[last contextRestored;512]];
            if[not ownershipValid;
                problems,:enlist
                    "directory fixture ownership changed during load"];
            rollback:attempt[restoreSaved;enlist saved];
            if[first rollback;
                `.tst.currentDirFixture set `;
                `.tst.savedDir set emptyState[]];
            if[not first rollback;
                `.tst.currentDirFixture set `restore_pending;
                problems,:enlist "rollback: ",
                    diagnostic[last rollback;512]];
            '"Directory fixture load failed: ",
              diagnostic["; " sv problems;2048]];
        `.tst.currentDirFixture set fixtureName];
    fixtureName^name};
restoreDir:{[]
    if[.tst.currentDirFixture~`;:()];
    attempt:.utl.attempt;
    diagnostic:.utl.boundedDiagnostic;
    clear:.tst.makeDirClear[];
    emptyState:.tst.emptySavedDir;
    adapter:.utl.fsSnapshot[];
    loader:adapter`loadPath;
    validate:.tst.validateSavedDir;
    restoreSaved:.tst.restoreSavedDirWith[
        attempt;diagnostic;clear;loader;validate];
    snapshot:.tst.savedDir;
    restoreSaved snapshot;
    `.tst.currentDirFixture set `;
    `.tst.savedDir set emptyState[];
    (::)};
.tst.validateCleanupTask:{[task]
    if[(not 99h=type task) or not `func`args~key task;
        '"Invalid cleanup task"]; if[not .tst.isCallable task`func;'"Invalid cleanup callable"];
    if[not (type[task`args] within 0 19h) or 98h=type task`args;
        '"Invalid cleanup arguments"]; if[count[task`args]>64;'"Cleanup argument limit exceeded"];
    (::)};
.tst.registerCleanupIn:{[queueName;func;args]
    if[.tst.cleanupDrainActive;
        '"Cleanup registration is not allowed while draining"]; task:`func`args!(func;args);
    .tst.validateCleanupTask task; queue:get queueName;
    if[count[queue]>=
       .utl.hardLimit[.tst.MAX_CLEANUP_TASKS;1024;"cleanup task"];
        '"Cleanup queue limit exceeded"]; queueName set queue,enlist task; (::)};
registerCleanup:{[func;args]
    .tst.registerCleanupIn[`.tst.cleanupTasks;func;args]};
registerSpecCleanup:{[func;args]
    .tst.registerCleanupIn[`.tst.specCleanupTasks;func;args]};
.tst.drainOwnedCleanupWith:{[dependencies;queueName;label;ignored]
    attempt:dependencies`attempt; taskLimit:dependencies`taskLimit;
    read:dependencies`read; write:dependencies`write;
    setGuard:dependencies`setGuard; run:dependencies`run;
    check:dependencies`check; call:dependencies`call;
    note:dependencies`note; finish:dependencies`finish;
    captured:attempt[read;enlist queueName];
    if[not first captured;'last captured]; tasks:last captured;
    previous:@[get;`.tst.cleanupDrainActive;{::}];
    if[not -1h=type previous;'"Invalid cleanup drain state"];
    if[not first .[write;(queueName;());{[e](0b;e)}];
        '"Unable to clear cleanup queue"]; armed:@[setGuard;1b;{[e]e}]; if[not 1b~armed;
        .[write;(queueName;tasks);{[e](::)}]; 'armed]; execution:attempt[
        {[attemptAll;validator;executor;items]
          attemptAll[items;validator;executor]}; (run;check;call;tasks)];
    result:$[first execution;last execution;
        `failed`remaining`failureCount`details!(
            `boolean$();tasks;1; enlist "cleanup execution failed")];
    mutation:attempt[read;enlist queueName]; if[not first mutation;
        result:note[
            result;"cleanup queue ownership could not be inspected"]]; if[first mutation;
        added:last mutation; validContainer:type[added] in 0 98h;
        if[(not validContainer) or
           (count[result`remaining]+count added)>
             taskLimit; result:note[
                result;"mutated cleanup queue is invalid"]]; if[validContainer;
            if[(count[result`remaining]+count added)<=
               taskLimit;
                if[count added;
                    result[`remaining],:added; result:note[
                        result;"cleanup queue changed while draining"]]]]];
    if[not 1b~@[setGuard;previous;{[e]0b}];
        result:note[
            result;"cleanup drain-state restoration failed"]];
    if[not first .[write;(queueName;result`remaining);{[e](0b;e)}];
        result:note[
            result;"cleanup ownership restoration failed"]]; finish[label;result]; (::)};
.tst.makeCleanupQueueDrain:{[queueName;label]
    if[not queueName in `.tst.cleanupTasks`.tst.specCleanupTasks;
        '"Invalid cleanup queue"];
    read:{[name]get name};
    write:{[name;items]name set items;(1b;"")};
    setGuard:{[flag]`.tst.cleanupDrainActive set flag;1b};
    call:{[task]
        $[count task`args;(task`func) . task`args;(task`func)[]]; (::)};
    taskLimit:.utl.hardLimit[
        .tst.MAX_CLEANUP_TASKS;1024;"cleanup task"];
    diagnostic:.utl.boundedDiagnostic;
    dependencies:
      `attempt`taskLimit`read`write`setGuard`run`check`call`note`finish!(
        .utl.attempt;taskLimit;read;write;setGuard;
        .tst.attemptAll;.tst.validateCleanupTask;call;
        .tst.noteFailureWith[diagnostic];
        .tst.raiseAttemptFailuresWith[diagnostic]);
    .tst.drainOwnedCleanupWith[
        dependencies;queueName;label;]};
.tst.makeExpectationCleanup:{[]
    .tst.makeCleanupQueueDrain[
        `.tst.cleanupTasks;"Expectation cleanup"]};
.tst.makeSpecCleanup:{[]
    .tst.makeCleanupQueueDrain[
        `.tst.specCleanupTasks;"Spec cleanup"]};
runCleanupTasks:{[]
    capsule:.tst.makeExpectationCleanup[];
    .tst.runCleanupPublic[
        capsule;"WARNING: Cleanup task failed: "]};
runSpecCleanupTasks:{[]
    capsule:.tst.makeSpecCleanup[];
    .tst.runCleanupPublic[
        capsule;"WARNING: Cleanup task failed: "]};
containedLeafPath:{[root;fragment;prefix;extension;allowEmpty;label]
    leaf:.tst.leafText[fragment;allowEmpty;label]; base:.utl.absolutePath root;
    target:.utl.absolutePath base,"/",prefix,leaf,
        $[(count extension) and leaf like "*",extension;"";extension];
    if[not .utl.pathWithinRoot[target;base;.utl.isWindows];
        '"Invalid ",label,": resolved path escapes configured root"]; target};
.tst.removeOwnedTree:{[ops;path;root]
    required:`inspect`list`delete`within`windows`limit`isLink`rootIdentity;
    if[(not 99h=type ops) or not all required in key ops;
        '"Invalid temporary cleanup capabilities"];
    if[not (ops`within)[path;root;ops`windows];
        '"Refusing cleanup outside temporary root"];
    sameIdentity:{[withinFn;hostWindows;left;right]
        withinFn[left;right;hostWindows] and
          withinFn[right;left;hostWindows]};
    checkDirectory:{[inspectFn;linkFn;withinFn;hostWindows;ownedRoot;target;expected]
        linked:linkFn target;
        if[not -1h=type linked;
            '"Invalid filesystem link classification"];
        if[linked;'"Refusing to traverse a filesystem link"];
        state:inspectFn target;
        if[(not 99h=type state) or
           not all `path`exists`kind`identity in key state;
            '"Invalid temporary path inspection"];
        if[(not state`exists) or not state[`kind]~`dir;
            '"Owned temporary directory changed"];
        identity:state`identity;
        if[not 10h=type identity;
            '"Invalid temporary directory identity"];
        same:{[withinOp;windows;a;b]
            withinOp[a;b;windows] and
              withinOp[b;a;windows]};
        if[not same[withinFn;hostWindows;identity;expected];
            '"Owned temporary directory identity changed"];
        if[not withinFn[identity;ownedRoot;hostWindows];
            '"Temporary directory escapes physical root"];
        if[not same[withinFn;hostWindows;identity;state`path];
            '"Refusing an aliased temporary directory"];
        state};
    rootIdentity:ops`rootIdentity;
    if[not 10h=type rootIdentity;
        '"Invalid temporary root identity"];
    pending:enlist path;
    parents:enlist "";
    parentIds:enlist "";
    visited:();
    visitedKinds:`symbol$();
    visitedIds:();
    visitedParents:();
    visitedParentIds:();
    while[count pending;
        current:first pending;
        parent:first parents;
        parentIdentity:first parentIds;
        pending:1 _ pending;
        parents:1 _ parents;
        parentIds:1 _ parentIds;
        if[count parent;
            checkDirectory[
                ops`inspect;ops`isLink;ops`within;ops`windows;
                rootIdentity;parent;parentIdentity]];
        linked:(ops`isLink) current;
        if[not -1h=type linked;
            '"Invalid filesystem link classification"];
        if[linked;'"Refusing to remove a filesystem link"];
        state:(ops`inspect) current;
        if[(not 99h=type state) or
           not all `path`exists`kind`identity in key state;
            '"Invalid temporary path inspection"];
        if[state`exists;
            if[not (ops`within)[state`path;root;ops`windows];
                '"Temporary path escapes owned root"];
            if[state[`kind]~`link;
                '"Refusing to remove a filesystem link"];
            if[not state[`kind] in `file`dir;
                '"Unsupported temporary path type"];
            if[state[`kind]~`dir;
                identity:state`identity;
                if[not 10h=type identity;
                    '"Invalid temporary directory identity"];
                if[not (ops`within)[identity;rootIdentity;ops`windows];
                    '"Temporary directory escapes physical root"];
                if[not sameIdentity[
                    ops`within;ops`windows;identity;state`path];
                    '"Refusing an aliased temporary directory"]];
            visited,:enlist state`path;
            visitedKinds,:state`kind;
            visitedIds,:enlist state`identity;
            visitedParents,:enlist parent;
            visitedParentIds,:enlist parentIdentity;
            if[count[visited]>ops`limit;
                '"Temporary cleanup entry limit exceeded"];
            if[state[`kind]~`dir;
                listed:(ops`list)[
                    state`path;1+ops[`limit]-count visited;1048576];
                if[(not 99h=type listed) or
                   not all `path`entries in key listed;
                    '"Invalid temporary directory enumeration"];
                names:listed`entries;
                if[not type[names] in 0 10h;
                    '"Invalid temporary directory entries"];
                if[10h=type names;names:enlist names];
                if[not all 10h=type each names;
                    '"Invalid temporary directory entries"];
                if[any {((x~enlist ".") or x~"..") or
                        (0=count x) or any x in "/\r\n\t"} each names;
                    '"Unsafe temporary directory entry"];
                children:{[p;n]p,"/",n}[state`path;] each names;
                if[(count[visited]+count[pending]+count children)>
                   ops`limit;
                    '"Temporary cleanup entry limit exceeded"];
                if[not all (ops`within)[;root;ops`windows] each children;
                    '"Temporary child escapes owned root"];
                if[count children;
                    childParents:(count children)#enlist state`path;
                    childParentIds:(count children)#enlist state`identity;
                    pending:children,pending;
                    parents:childParents,parents;
                    parentIds:childParentIds,parentIds]]]];
    i:count visited; while[i>0;
        i-:1;
        current:visited i;
        parent:visitedParents i;
        parentIdentity:visitedParentIds i;
        if[count parent;
            checkDirectory[
                ops`inspect;ops`isLink;ops`within;ops`windows;
                rootIdentity;parent;parentIdentity]];
        linked:(ops`isLink) current;
        if[not -1h=type linked;
            '"Invalid filesystem link classification"];
        if[linked;'"Refusing to remove a filesystem link"];
        state:(ops`inspect) current;
        if[state`exists;
            if[not state[`kind]~visitedKinds i;
                '"Temporary path changed before deletion"];
            if[state[`kind]~`dir;
                if[not sameIdentity[
                    ops`within;ops`windows;state`identity;visitedIds i];
                    '"Temporary directory identity changed before deletion"];
                if[not sameIdentity[
                    ops`within;ops`windows;state`identity;state`path];
                    '"Refusing an aliased temporary directory"]];
            if[not (ops`delete) current;
                '"Temporary cleanup failed"]]]; (::)};
.tst.cleanupTemp:{[ops;removeTree;root;marker;token]
    readRegular:ops`read; withinFn:ops`within;
    windows:ops`windows; if[not withinFn[marker;root;windows];
        '"Invalid temporary ownership marker"];
    rootLinked:(ops`isLink) root;
    if[(not -1h=type rootLinked) or rootLinked;
        '"Temporary root link classification failed"];
    rootState:(ops`inspect) root;
    if[(not rootState[`kind]~`dir) or
       not withinFn[rootState`identity;ops`rootIdentity;windows] or
       not withinFn[ops`rootIdentity;rootState`identity;windows];
        '"Temporary root identity changed"];
    markerLinked:(ops`isLink) marker;
    if[(not -1h=type markerLinked) or markerLinked;
        '"Temporary marker link classification failed"];
    read:readRegular[marker;1024];
    if[not ("c"$read`bytes)~token,"\n";
        '"Temporary ownership marker changed"]; removeTree[root;root]};
tempFile:{[suffix]
    suffix:.tst.leafText[suffix;1b;"temporary-file suffix"]; fs:.utl.fsSnapshot[];
    token:raze string md5 "c"$
        ((string .z.i),string[.z.p],string .tst.tempCounter); .tst.tempCounter+:1;
    root:(.utl.absolutePath system "cd"),"/.resq-tmp-",token;
    if[((fs`inspect) root)`exists;'"Temporary root collision"];
    (fs`makeDir) root; marker:root,"/.owner";
    rootState:(fs`inspect) root;
    if[(not rootState[`kind]~`dir) or not 10h=type rootState`identity;
        '"Unable to establish temporary root identity"];
    rootIdentity:rootState`identity;
    (.utl.pathToHsym marker) 0:enlist token; withinOp:.utl.pathWithinRoot;
    windows:.utl.isWindows;
    isLink:{[inspectFn;hostWindows;ownedRoot;p]
        state:inspectFn p;
        if[(not 99h=type state) or not all `path`exists`kind in key state;
            '"Invalid filesystem link inspection"];
        if[not hostWindows;
            if[(not `linkSafe in key state) or
               not (-1h=type state`linkSafe) or
               not state`linkSafe;
                '"Filesystem link classification unavailable"];
            :state[`kind]~`link];
        if[p~ownedRoot;:0b];
        if[state[`kind]~`dir;
            '"Windows recursive cleanup requires reparse-point classification"];
        0b}[fs`inspect;windows;root;];
    limit:.utl.hardLimit[.tst.MAX_TEMP_ENTRIES;4096;"temporary entry"];
    ops:`inspect`list`delete`read`within`windows`limit`isLink`rootIdentity!(
        fs`inspect;fs`list;fs`delete;fs`readRegular;
        withinOp;windows;limit;isLink;rootIdentity);
    remove:.tst.removeOwnedTree[ops]; cleanup:.tst.cleanupTemp[ops;remove];
    registered:.utl.attempt[{[cleanupTask;r;m;t]
        .tst.registerCleanup[cleanupTask;(r;m;t)]; (::)};(cleanup;root;marker;token)];
    if[not first registered;
        .[cleanup;(root;marker;token);{[e](::)}]; 'last registered]; root,"/item",suffix};
\d .
