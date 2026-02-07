\d .tst

/ ============================================================================
/ State Initialization - Safe Defaults
/ These ensure variables exist before any module tries to use them
/ Using direct assignment to create namespace structure (like init.q does)
/ ============================================================================

/ Ensure namespaces exist by touching variables
/ This is the safe pattern - setting a variable creates its parent namespaces
if[not `app in key `.tst; .tst.app.init_: 1b];
if[not `output in key `.tst; .tst.output.init_: 1b];

/ App configuration (with safe defaults) - only set if not already defined
if[not `excludeSpecs in key `.tst.app; .tst.app.excludeSpecs: ()];
if[not `runSpecs in key `.tst.app; .tst.app.runSpecs: ()];
if[not `args in key `.tst.app; .tst.app.args: ()];
if[not `describeOnly in key `.tst.app; .tst.app.describeOnly: 0b];
if[not `xmlOutput in key `.tst.app; .tst.app.xmlOutput: 0b];
if[not `runPerformance in key `.tst.app; .tst.app.runPerformance: 0b];
if[not `runCoverage in key `.tst.app; .tst.app.runCoverage: 0b];
if[not `exit in key `.tst.app; .tst.app.exit: 0b];
if[not `failFast in key `.tst.app; .tst.app.failFast: 0b];
if[not `failHard in key `.tst.app; .tst.app.failHard: 0b];
if[not `maxTestTime in key `.tst.app; .tst.app.maxTestTime: 0];
if[not `passOnly in key `.tst.app; .tst.app.passOnly: 0b];
if[not `allSpecs in key `.tst.app; .tst.app.allSpecs: ()];
if[not `passed in key `.tst.app; .tst.app.passed: 1b];

/ Counters (reset on each run)
if[not `expectationsRan in key `.tst.app; .tst.app.expectationsRan: 0];
if[not `expectationsPassed in key `.tst.app; .tst.app.expectationsPassed: 0];
if[not `expectationsFailed in key `.tst.app; .tst.app.expectationsFailed: 0];
if[not `expectationsErrored in key `.tst.app; .tst.app.expectationsErrored: 0];

/ Output configuration
if[not `mode in key `.tst.output; .tst.output.mode: `run];
if[not `fuzzLimit in key `.tst.output; .tst.output.fuzzLimit: 10];
if[not `reportLimit in key `.tst.output; .tst.output.reportLimit: 50000];
if[not `reportListLimit in key `.tst.output; .tst.output.reportListLimit: 1000];

/ Truncation utility for safely outputting large values
/ Prevents memory exhaustion from very large test outputs
.tst.truncate:{[val;maxLen]
    s: -3!val;
    n: count s;
    if[n > maxLen;
        truncLen: maxLen - 30;
        origLen: n;
        s: truncLen # s;
        s,: "... [truncated ", string[origLen - truncLen], " chars]"
    ];
    s
 };

/ Initialize .resq namespace if not exists
if[not `resq in key `.; .resq.state.init_: 1b; .resq.config.init_: 1b];

/ Resq config defaults
if[not `fmt in key `.resq.config; .resq.config.fmt: `text];
if[not `outDir in key `.resq.config; .resq.config.outDir: "."];

/ Resq state - results table
if[not `results in key `.resq.state; .resq.state.results: flip `suite`description`status`message`time`failures`assertsRun!(`symbol$(); `symbol$(); `symbol$(); (); `timespan$(); (); `int$())];

/ Default reporter (can be overridden)
if[not `report in key `.resq; .resq.report: {[x]}];

/ ============================================================================

.tst.defaultAssertState:.tst.assertState:``failures`assertsRun!(::;();0);
.tst.tstPath: `;

/ Type-safe string conversion
/ Handles: symbols, strings, atoms, lists, nulls
/ Use this instead of `string` when concatenating with strings
.tst.toString:{
    t: type x;
    $[10h = t; x;                           / Already a string - return as-is
      -11h = t; string x;                   / Symbol - convert normally
      11h = t; " " sv string x;             / Symbol list - join with spaces
      t within -19 -1h; string x;           / Negative atom types (atoms)
      t within 1 19h; -3!x;                 / Positive simple list types
      0h = t; -3!x;                         / General list - use -3!
      99h = t; -3!x;                        / Dictionary
      98h = t; -3!x;                        / Table
      null x; "";                           / Null - empty string
      -3!x]                                 / Fallback - use -3! (show)
 };

halt:0b
internals:()!()
internals[`]:()!()
internals[`specObj]:`result`title`failHard!(`didNotRun;"";0b)
internals[`defaultExpecObj]:`result`errorText!(`didNotRun;())
internals[`testObj]: internals[`defaultExpecObj], ((),`type)!(),`test
internals[`fuzzObj]: internals[`defaultExpecObj], `type`runs`vars`maxFailRate!(`fuzz;100;`int;0f)
internals[`perfObj]: internals[`defaultExpecObj], ((),`type)!(),`perf

/ Callbacks - must exist before any test loading
if[not `callbacks in key `.tst; .tst.callbacks.descLoaded: {[specObj]}; .tst.callbacks.expecRan: {[spec;expec]}];
