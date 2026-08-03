/ End-to-end coverage gate: the percentage shown by resQ, the LCOV artifact,
/ the canonical result row, and the process exit code must all agree.

.tst.testState.covgate.canRun:
    (0 < count @[system; "which q 2>/dev/null"; {()}]) and
    (0 < count @[system; "which timeout 2>/dev/null"; {()}]);

/ `extra` appends raw CLI flags so the same fixture can be driven in BOTH coverage
/ modes: default (function-level) and -cov-statements (measured lines).
.tst.testState.covgate.runWith:{[minimum; extra]
    wd: .utl.tempRoot[], "/resq_covgate_", string[.z.i], "_",
        string[`long$.z.p], "_", string[minimum];
    sourcePath: wd, "/source.q";
    fixturePath: wd, "/test_gate.q";
    .utl.ensureDir wd;
    (hsym `$sourcePath) 0: (
        ".gate.hit:{[x] x+1};";
        ".gate.miss:{[x] x-1};");
    (hsym `$fixturePath) 0: (
        "system \"l \", \"",sourcePath,"\";";
        ".tst.desc[\"coverage gate\"]{";
        "  should[\"calls one of two functions\"]{ .gate.hit[1] musteq 2 };";
        "};");
    cmd: "true && timeout -k 2 60 q ", (.utl.shellQuote .resq.HOME, "/resq.q"),
         " cover ", (.utl.shellQuote fixturePath), " -cov-include ",
         (.utl.shellQuote sourcePath), " -cov-min ", string[minimum], " ", extra,
         " -json -outDir ", (.utl.shellQuote wd), " -quiet > ",
         (.utl.shellQuote wd, "/out.txt"), " 2>&1; echo $?";
    exitLines: @[system; cmd; {[err] enlist "-1"}];
    exitCode: "J"$last exitLines;
    output: @[read0; hsym `$wd, "/out.txt"; {()}];
    rawJson: @[read0; hsym `$wd, "/test-results.json"; {()}];
    payload: $[count rawJson; .j.k raze rawJson; ()!()];
    lcov: @[read0; hsym `$wd, "/coverage.lcov"; {()}];
    if[wd like "*/resq_covgate_*"; system "rm -rf -- ", .utl.shellQuote wd];
    `code`output`payload`lcov!(exitCode;output;payload;lcov)
 };

.tst.testState.covgate.run:{[minimum] .tst.testState.covgate.runWith[minimum; ""]};

.tst.desc["Coverage minimum gate #slow"]{
    skipIf[not .tst.testState.covgate.canRun;
           "fail below the measured percentage and pass at the boundary"]{
        / Default mode measures FUNCTIONS, not lines: one of two functions is
        / called, so the gate sees 50% and the artifact must say so in the same
        / terms. Asserting the "functions" wording is what keeps a future derived
        / line record from silently re-inflating this to 100%.
        failed: .tst.testState.covgate.run 51;
        failed[`code] musteq 1;
        outputText: "\n" sv failed`output;
        must[(0 < count ss[outputText;"Coverage: 50"]) and
             (0 < count ss[outputText;"functions (1/2)"]);
             "the console must print the measured percentage and counts"];
        must[0 < count ss[outputText;"Statement/branch execution is NOT measured"];
             "function-level mode must say what it did not measure"];
        failed[`payload;`errorCount] musteq 1f;
        failed[`payload;`coverage;`functionPercent] musteq 50f;
        failed[`payload;`coverage;`basis] musteq "functions";
        failed[`payload;`coverage;`minimum] musteq 51f;
        failed[`payload;`coverage;`passed] musteq 0b;
        errorRows: failed[`payload;`tests] where failed[`payload;`tests;`status] ~\: "error";
        must[0 < count ss[first errorRows`message;"below required minimum 51%"];
             "the JSON error must explain the failed gate"];
        must[any failed[`lcov] like "FNF:2"; "LCOV must expose the same denominator"];
        must[any failed[`lcov] like "FNH:1"; "LCOV must expose the same numerator"];
        must[not any failed[`lcov] like "DA:*";
             "function-level mode must not emit derived line records"];

        passed: .tst.testState.covgate.run 50;
        passed[`code] musteq 0;
        passed[`payload;`passCount] musteq 1f;
        passed[`payload;`errorCount] musteq 0f;
        passed[`payload;`coverage;`passed] musteq 1b;
    };

    skipIf[not .tst.testState.covgate.canRun;
           "gate on MEASURED lines under -cov-statements"]{
        / Same fixture, statement mode: now real line records exist and the gate
        / must switch to them. Both functions are single-statement, so lines and
        / functions agree at 50% here -- what is pinned is that line data is
        / present and drives the verdict, not the specific figure.
        r: .tst.testState.covgate.runWith[51; "-cov-statements"];
        r[`code] musteq 1;
        outputText: "\n" sv r`output;
        must[0 < count ss[outputText;"lines (1/2)"];
             "statement mode must report in lines"];
        r[`payload;`coverage;`basis] musteq "lines";
        r[`payload;`coverage;`linePercent] musteq 50f;
        must[any r[`lcov] like "LF:2"; "LCOV must carry a measured line denominator"];
        must[any r[`lcov] like "LH:1"; "LCOV must carry a measured line numerator"];
    };
};

::
