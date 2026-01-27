/ lib/runner.q - Simplified
.tst.initReporting:{[]
    / Defensive: ensure state exists
    if[not `xmlOutput in key `.tst.app; .tst.app.xmlOutput: 0b];
    if[not `runCoverage in key `.tst.app; .tst.app.runCoverage: 0b];

    / Define XML reporter function
    .resq.reportXml:{[results] 
      / JUnit/XUnit output expects spec objects, not the flat results table
      specs: $[`results in key `.tst.app; .tst.app.results; ()];
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

    if[1b ~ .tst.app.failHard;.tst.app.allSpecs[;`failHard]: 1b];
    
    if[0 <> count .tst.app.excludeSpecs;.tst.app.allSpecs: .tst.app.allSpecs where not (or) over .tst.app.allSpecs[;`title] like/: .tst.app.excludeSpecs];
    if[0 <> count .tst.app.runSpecs;.tst.app.allSpecs: .tst.app.allSpecs where (or) over .tst.app.allSpecs[;`title] like/: .tst.app.runSpecs];

    .tst.app.results: $[not 1b ~ .tst.app.describeOnly;.tst.runSpec each .tst.app.allSpecs;.tst.app.allSpecs];

    .tst.app.passed:all `pass = .tst.app.results[;`result];
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

    if[1b ~ .tst.app.exit; .tst.die `int$not .tst.app.passed];
 };
