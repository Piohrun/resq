/ lib/watch.q - Smart Watch Mode
/ ============================================================================

/ Dependencies
.utl.require "lib/static_analysis.q"

/ Configuration
.tst.watch.watchDirs: enlist "."
.tst.watch.fileStates: ()!()
.tst.watch.lastScan: 0p
/ Phase 4: Debouncing support
.tst.watch.debounceMs: 200;  / Wait 200ms after last change before running
.tst.watch.lastChange: 0Np;
.tst.watch.pendingRun: 0b;
.tst.watch.pendingFiles: ();

/ Default runner command (can be overridden)
.tst.watch.runnerCmd: { 
    files: x;
    / Reload runner state to clear previous runs
    system "l lib/runner.q"; 
    
    / Force no exit for watch mode runner
    .tst.app.exit: 0b;
    
    / Set args for runner
    .tst.app.args: files;
    
    -1 ">> Running tests internally...";
    @[.tst.runAll; ::; {-1 "Error during test run: ", x}];
    -1 ">> Done.";
 };

/ Scan and return dictionary of file->modTime
.tst.watch.scanFiles:{[]
    files: raze { .tst.static.findSources x } each .tst.watch.watchDirs;
    if[0 = count files; :()!()];

    / Get modification times safely
    times: {[f]
        h: .utl.pathToHsym f;
        k: key h;
        $[() ~ k; 0Np; k]  / Return null timestamp if doesn't exist
    } each files;

    files!times
 }

/ Initialize
.tst.watch.init:{[dirs]
    .tst.watch.watchDirs:: dirs;
    .tst.watch.fileStates:: .tst.watch.scanFiles[];
    -1 ">> Watch initialized. Tracking ",string[count .tst.watch.fileStates]," files.";
    -1 ">> Directories: ", ", " sv dirs;
 }

/ Check for changes
.tst.watch.check:{[]
    curr: .tst.watch.scanFiles[];
    
    / New files
    new: (key curr) except key .tst.watch.fileStates;
    
    / Deleted files
    del: (key .tst.watch.fileStates) except key curr;
    
    / Changed files (intersection)
    common: (key curr) inter key .tst.watch.fileStates;
    changed: common where not (curr common) ~' (.tst.watch.fileStates common);
    
    / Update state
    .tst.watch.fileStates:: curr;
    
    / Return list of changed/new files (ignore deletes for now)
    new, changed
 }

/ Run tests for changed files
.tst.watch.onChanges:{[files]
    -1 ">> Changes detected in: ", ", " sv string files;
    
    / Heuristic:
    / 1. Is it a test file? Run it.
    / 2. Is it a source file? Find dependent tests?
    
    testsToRun: distinct raze {[f]
        s: string f;
        $[s like "*test_*.q"; 
            enlist f;
            s like "*/test/*.q";
            enlist f;
            [
                / It's a source file. Find mapping.
                / Simple mapping: src/foo.q -> test/test_foo.q
                base: .tst.static.getBase f;
                name: base;
                if[name like "*.q"; name: (count[name]-2)#name];
                
                / Search for test_NAME.q
                candidates: key .tst.watch.fileStates;
                matches: candidates where (string candidates) like "*test_",name,".q";
                
                $[0<count matches; matches; enlist `ALL]
            ]
        ]
    } each files;
    
    / Run
    $[(`ALL in testsToRun) or (0=count testsToRun);
        [
            -1 ">> Running ALL tests.";
            .tst.watch.runnerCmd[()];
        ];
        [
            -1 ">> Running target tests: ", ", " sv string testsToRun;
            .tst.watch.runnerCmd[testsToRun];
        ]
    ];
 }
