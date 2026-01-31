/ lib/runner.q - Simplified
.tst.initReporting:{[]
    / Defensive: ensure state exists
    if[not `xmlOutput in key `.tst.app; .tst.app.xmlOutput: 0b];
    if[not `runCoverage in key `.tst.app; .tst.app.runCoverage: 0b];

    / Define XML reporter function
    .resq.reportXml:{[results] 
      / JUnit/XUnit output expects spec objects, not the flat results table
      specs: $[`results in key `.tst.app; .tst.app.results; ()];
      specs: .tst.sanitize specs;
      xmlReport: .tst.output.top specs;
      outDirStr: .tst.toString .resq.config.outDir;
      if[0 = count outDirStr; outDirStr: "."];
      baseDirStr: .tst.toString .tst.app.baseDir;
      if[0 = count baseDirStr; baseDirStr: system "cd"];
      if[not outDirStr like "/*"; outDirStr: baseDirStr, "/", outDirStr];
      outDirStr: .utl.normalizePath outDirStr;
      outFile: outDirStr, "/test-results_", string[.z.i], ".xml";
      system "mkdir -p ", outDirStr;
      hsym[`$outFile] 0: enlist xmlReport;
      -1 "XML Report written to ", outFile;
     };

    / Apply XML reporter if enabled
    if[.tst.app.xmlOutput;
      .tst.loadOutputModule[$[.resq.config.fmt=`xunit; "xunit"; "junit"]];
      .resq.report: .resq.reportXml;
     ];

    / Apply JSON reporter when explicitly requested (non-XML path)
    if[not .tst.app.xmlOutput;
        if[.resq.config.fmt ~ `json;
            .tst.loadOutputModule["json"];
            if[`reportJson in key `.resq; .resq.report: .resq.reportJson];
        ];
    ];
     

    if[.tst.app.runCoverage;
        if[not `coverageLoading in key `.tst; .tst.coverageLoading: 0b];
        .tst.coverageLoading: 1b;
        if[not `initCoverage in key `.tst;
            .utl.require "lib/coverage.q";
        ];
        .tst.coverageLoading: 0b;

        / Fallback: attempt a direct load if the require path did not register coverage.
        if[not `initCoverage in key `.tst;
            @[system; "l lib/coverage.q"; {[e]
                -1 "Coverage module load failed: ", .tst.toString e;
                :()
            }];
        ];

        covInit: @[get; `.tst.initCoverage; {::}];
        .tst._covInitOk: 1b;
        @[covInit; (); {[e]
            .tst._covInitOk: 0b;
            -1 "Coverage init failed: ", .tst.toString e;
            :()
        }];
        if[1b ~ .tst._covInitOk; -1 "Coverage enabled."];
     ];
 };

.tst.runAll:{[]
    / Defensive: ensure state exists
    if[not `failFast in key `.tst.app; .tst.app.failFast: 0b];
    if[not `failHard in key `.tst.app; .tst.app.failHard: 0b];
    if[not `exit in key `.tst.app; .tst.app.exit: 0b];
    if[not `describeOnly in key `.tst.app; .tst.app.describeOnly: 0b];

    / Reset state for this run
    .tst.app.allSpecs:();
    .tst.app.expectationsRan:0;
    .tst.app.expectationsPassed:0;
    .tst.app.expectationsFailed:0;
    .tst.app.expectationsErrored:0;
    / Capture base directory for output paths before tests may change CWD
    .tst.app.baseDir: system "cd";

    / Reset results table
    .resq.state.results: flip `suite`description`status`message`time`failures`assertsRun!(`symbol$(); `symbol$(); `symbol$(); (); `timespan$(); (); `int$());

    .tst.callbacks.descLoaded:{[specObj] .tst.app.allSpecs,:enlist specObj; };

 .tst.runSpec:{[spec]
    / Deep Snapshot: all top-level namespaces and their keys AND values
    namespaces: key `;
    / Skip system namespaces and .tst/.resq internals
    namespaces: namespaces except `q`Q`j`h`o`s`v`z`tst`resq;
    
    if[any namespaces like "repro"; -1 "DEBUG: Tracking namespace: ", .Q.s1 namespaces where namespaces like "repro"];

    / Helper to snapshot values
    / Returns dict: fullyQualifiedName -> value
    .run.snapValues:{[ns]
        / Force absolute path
        rootNs: ` sv (`; ns);
        ks: key rootNs;
        if[0=count ks; :()!()];
        paths: .Q.dd[rootNs;] each ks;
        / We use error trap on get just in case of weird view/projection states, though unlikely for globals
        vals: { @[get; x; { (`GENERIC_ERROR; x) }] } each paths;
        paths!vals
    };
    
    fullSnapshot: namespaces!.run.snapValues each namespaces;

    / Resource Snapshot (Phase 1 Hardening)
    origHandles: (), "J"$ raze " " vs/: system "ls /proc/self/fd";
    origTs: @[get; `.z.ts; {::}];

    / Switch to spec context if defined
    ctx: $[`namespace in key spec; spec`namespace; `context in key spec; spec`context; `];
    if[not ctx ~ `; .tst.context: ctx; system "d ", string ctx];

    / Run Before Hooks
    if[`before in key spec; .tst.runHook[spec`before]];

    / Run Expectations
    / UI tests store tests in `expectations`, simple tests in `code`
    list: $[`expectations in key spec; spec`expectations; spec`code];
    
    / Clean up list (ensure it is a list of objects)
    t: type list;
    if[not t in 0 98h; list: enlist list];
    
    res: .tst.runExpec[spec] each list;
    
    / Run After Hooks
    if[`after in key spec; .tst.runHook[spec`after]];
    
    / Restore Root Namespace
    system "d .";

    / Check for Global/Deep Pollution
    currentNamespaces: key `;
    currentNamespaces: currentNamespaces except `q`Q`j`h`o`s`v`z`tst`resq;
    
    newNamespaces: currentNamespaces except namespaces;
    if[count newNamespaces;
        -1 "WARNING: Test '", .tst.toString[spec`title], "' leaked new namespaces: ", .tst.toString newNamespaces;
        .tst.deleteVar each newNamespaces;
        -1 "  -> Cleaned up leaked namespaces.";
    ];

    / Check existing namespaces for new keys AND modified values
    / Check existing namespaces for new keys AND modified values
    checkNs: namespaces inter currentNamespaces;
    
    if[count checkNs;
        { [title; ns; originalState]
            currentState: .run.snapValues ns;
            
            / 1. Detect New Keys (Pollution)
            newKeys: (key currentState) except (key originalState);
            if[count newKeys;
                -1 "WARNING: Test '", .tst.toString[title], "' leaked members in ", string[ns], ": ", .tst.toString newKeys;
                .tst.deleteVar each newKeys;
                 -1 "  -> Cleaned up leaked members in ", string[ns], ".";
            ];
            
            / 2. Detect Modified Values (Mutation)
            commonKeys: (key currentState) inter (key originalState);
            / Filter out views or functions that might be tricky? For now check all.
            modifiedKeys: commonKeys where not { x ~ y }'[originalState commonKeys; currentState commonKeys];
            
            if[count modifiedKeys;
                -1 "WARNING: Test '", .tst.toString[title], "' modified globals in ", string[ns], ": ", .tst.toString modifiedKeys;
                 / Restore values
                { [k; v] 
                    / Check if view by attempting to get definition
                    / Wrap result in (isView; result) to distinguish success/fail
                    r: @[{ (1b; view x) }; k; { (0b; x) }];
                    isView: r 0;
                    
                    if[not isView; k set v];
                }'[modifiedKeys; originalState modifiedKeys];
                -1 "  -> Restored modified globals in ", string[ns], ".";
            ];
            
        }[spec`title]'[checkNs; fullSnapshot checkNs];
    ];

    / Resource Teardown (Phase 1 Hardening)
    currentHandles: (), "J"$ raze " " vs/: system "ls /proc/self/fd";
    leaked: currentHandles except origHandles;
    if[count leaked;
        -1 "WARNING: Test Suite '", .tst.toString[spec`title], "' leaked handles: ", .tst.toString leaked;
        { @[hclose; x; {}] } each leaked;
        -1 "  -> Closed leaked handles.";
    ];

    currentTs: @[get; `.z.ts; {::}];
    if[not currentTs ~ origTs;
        -1 "WARNING: Test Suite '", .tst.toString[spec`title], "' modified .z.ts. Restoring.";
        .z.ts: origTs;
    ];

    spec[`expectations]: res;
    spec
 };

    .tst.callbacks.expecRan:{[s;e] 
          .tst.app.expectationsRan+:1;
          r: e[`result];
          if[r ~ `pass; .tst.app.expectationsPassed+:1];
          if[r in `testFail`fuzzFail; .tst.app.expectationsFailed+:1];
          if[r like "*Error"; .tst.app.expectationsErrored+:1];
          
          status: $[r ~ `pass; `pass; r in `testFail`fuzzFail; `fail; `error];
          messageText: $[status ~ `pass; ""; 0 < count e[`failures]; e[`failures]; e[`errorText]];

          / Safe conversion to symbol - handles strings, symbols, and other types
          toSym: {$[-11h = type x; x; 10h = type x; `$x; `$string x]};
          exTime: first e[`time];
          dur: @[{"n"$x}; exTime; { 0Nn }];

          toInsert: flip `suite`description`status`message`time`failures`assertsRun ! (
              enlist toSym s[`title];
              enlist toSym e[`desc];
              enlist status;
              enlist messageText;
              enlist dur;
              enlist $[`failures in key e; e[`failures]; ()];
              enlist $[`assertsRun in key e; e[`assertsRun]; 0i]
          );
          
          `.resq.state.results upsert toInsert;

          / Fix: Ensure boolean atoms for AND/OR
          isFail: not r ~ `pass;
          shouldHalt: (1b ~ .tst.app.failFast) or (1b ~ .tst.app.failHard);
          if[shouldHalt and isFail;
            -1 "!!! HALTING FAILURE !!!";
            -1 "Suite: ", .tst.toString s[`title];
            -1 "Desc:  ", .tst.toString e[`desc];
            -1 "Error: ", .tst.toString messageText;
            if[1b ~ .tst.app.failHard;.tst.halt:1b];
            if[(1b ~ .tst.app.exit) and not 1b ~ .tst.app.failHard;.tst.die 1];
          ];
    };

    .tst.loadTests .tst.app.args;

    if[count .tst.app.allSpecs;
        if[1b ~ .tst.app.failHard;.tst.app.allSpecs[;`failHard]: 1b];
        if[0 <> count .tst.app.excludeSpecs;.tst.app.allSpecs: .tst.app.allSpecs where not (or) over .tst.app.allSpecs[;`title] like/: .tst.app.excludeSpecs];
        if[0 <> count .tst.app.runSpecs;.tst.app.allSpecs: .tst.app.allSpecs where (or) over .tst.app.allSpecs[;`title] like/: .tst.app.runSpecs];
    ];

    if[.utl.DEBUG; -1 "DEBUG: allSpecs count: ", string count .tst.app.allSpecs];
    .tst.app.results: $[not 1b ~ .tst.app.describeOnly; .tst.runSpec each .tst.app.allSpecs; .tst.app.allSpecs];
    if[.utl.DEBUG; -1 "DEBUG: results count: ", string count .tst.app.results];

    / Process Load Errors
    if[0 < count .tst.app.loadErrors;
        { [err]
            toInsert: flip `suite`description`status`message`time`failures`assertsRun ! (
                enlist `FILE_LOAD_ERROR;
                enlist err`file;
                enlist `error;
                enlist err`error;
                enlist 0Nn;
                enlist enlist err`error;
                enlist 0i
            );
            `.resq.state.results upsert toInsert;

            / Synthetic Spec for XML IO
            syntheticExpec: `desc`type`time`result`errorText`failures`code`before`after`assertsRun!(
                "File: ", (string err`file);
                `test;
                0Nn;
                `fileLoadError;
                err`error;
                enlist err`error;
                {}; {}; {};
                0
            );
            syntheticSpec: `title`expectations!(`FILE_LOAD_ERROR; enlist syntheticExpec);
            .tst.app.results,: enlist syntheticSpec;
        } each .tst.app.loadErrors;
    ];

    / STRICT MODE: Fail if no tests run or no expectations executed
    if[.tst.app.strict and (0 = .tst.app.expectationsRan);
        toInsert: flip `suite`description`status`message`time`failures`assertsRun ! (
            enlist `STRICT_MODE_FAILURE;
            enlist `NO_TESTS_FOUND;
            enlist `error;
            enlist "Strict mode enabled but no tests were found/executed.";
            enlist 0Nn;
            enlist enlist "No tests executed.";
            enlist 0i
        );
        `.resq.state.results upsert toInsert;
    ];

    r: raze { $[count x`expectations; x`expectations; ()] } each .tst.app.results;
    allResPass: $[count r; all r[;`result] ~\: `pass; 1b];
    allStatePass: $[count .resq.state.results; all .resq.state.results[`status] = `pass; 1b];

    .tst.app.passed: allResPass and (0 = count .tst.app.loadErrors) and allStatePass and (0 < count .resq.state.results);
    / If we have load errors or strict mode failure, passed should be 0b even if state.results is empty
    if[0 < count .tst.app.loadErrors; .tst.app.passed: 0b];
    
    .resq.report[.resq.state.results];
    
    if[1b ~ .tst.app.runCoverage;
        / Be defensive about outDir types (string/symbol/etc.)
        outDirStr: .tst.toString .resq.config.outDir;
        if[0 = count outDirStr;
            outDirStr: ".";
            -1 "Coverage outDir was empty; defaulting to '.'";
        ];
        / If outDir is relative, anchor it to the original base directory
        baseDirStr: .tst.toString .tst.app.baseDir;
        if[0 = count baseDirStr; baseDirStr: system "cd"];
        if[not outDirStr like "/*";
            outDirStr: baseDirStr, "/", outDirStr;
        ];
        outDirStr: .utl.normalizePath outDirStr;
        -1 "Coverage outDir: ", outDirStr;
        system "mkdir -p ", outDirStr;

        outFile: outDirStr, "/coverage.lcov";
        covLCOV: @[get; `.tst.generateLCOV; {()}];
        if[0 = count covLCOV; -1 "Coverage LCOV generator not available."];
        if[0 < count covLCOV;
            @[covLCOV; outFile; {[e]
                -1 "Coverage LCOV generation failed: ", .tst.toString e;
                :()
            }];
        ];

        htmlFile: outDirStr, "/coverage.html";
        covHTML: @[get; `.tst.generateHTML; {()}];
        if[0 = count covHTML; -1 "Coverage HTML generator not available."];
        if[0 < count covHTML;
            @[covHTML; htmlFile; {[e]
                -1 "Coverage HTML generation failed: ", .tst.toString e;
                :()
            }];
        ];
    ];
    
    .tst.cleanupAllFixtures[];
    .tst.restoreOriginalQ[];
    .tst.restore[];

    / Sandbox Cleanup
    / Delete all namespaces created for suites (flat namespaces .sandbox_*)
    rootKeys: key `.;
    sandboxKeys: rootKeys where (string rootKeys) like "sandbox_*";
    if[0 < count sandboxKeys;
        ![`.; (); 0b; sandboxKeys]
    ];

    if[1b ~ .tst.app.exit; .tst.die `int$not .tst.app.passed];
 };
