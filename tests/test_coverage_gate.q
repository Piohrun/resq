/ End-to-end coverage gate: the percentage shown by resQ, the LCOV artifact,
/ the canonical result row, and the process exit code must all agree.

.utl.require .resq.HOME,"/lib/coverage.q";

.tst.testState.covgate.canRun:
    (0 < count @[system; "which q 2>/dev/null"; {()}]) and
    (0 < count @[system; "which timeout 2>/dev/null"; {()}]);

.tst.testState.covgate.stateFlags:{[wd]
    " -state-file ",.utl.shellQuote[wd,"/state.json"],
    " -flake-history ",.utl.shellQuote[wd,"/flake.json"],
    " -quarantine-file ",.utl.shellQuote[wd,"/quarantine.json"],
    " -flake-proposal-file ",.utl.shellQuote[wd,"/proposals.json"]
 };

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
         " -json -outDir ", (.utl.shellQuote wd),
         .tst.testState.covgate.stateFlags[wd]," -quiet > ",
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

/ A declared source tree is an inventory, not a hint. This fixture loads one
/ function while leaving a second module completely untouched; all four static
/ functions must still be present in LCOV and in the gate denominator.
.tst.testState.covgate.runManifestWith:{[extra]
    wd: .utl.tempRoot[], "/resq_covmanifest_", string[.z.i], "_", string `long$.z.p;
    sourceDir: wd, "/src";
    loadedPath: sourceDir, "/loaded.q";
    missedPath: sourceDir, "/never_loaded.q";
    fixturePath: wd, "/test_manifest.q";
    .utl.ensureDir sourceDir;
    (hsym `$loadedPath) 0: enlist ".manifest.hit:{[x] x+1};";
    (hsym `$missedPath) 0: (
        ".manifest.missA:{[x] x-1};";
        ".manifest.missB:{[x] x*2};";
        ".manifest.missC:{[x] x%2};");
    (hsym `$fixturePath) 0: (
        "system \"l \", \"",loadedPath,"\";";
        ".tst.desc[\"manifest denominator\"]{";
        "  should[\"loads one module\"]{ .manifest.hit[1] musteq 2 };";
        "};");
    cmd: "true && timeout -k 2 60 q ", (.utl.shellQuote .resq.HOME, "/resq.q"),
         " cover ", (.utl.shellQuote fixturePath), " --source ",
         (.utl.shellQuote sourceDir), " ",extra," -json -outDir ",
         (.utl.shellQuote wd),.tst.testState.covgate.stateFlags[wd],
         " -quiet > ",
         (.utl.shellQuote wd, "/out.txt"), " 2>&1; echo $?";
    exitLines: @[system; cmd; {[err] enlist "-1"}];
    exitCode: "J"$last exitLines;
    output: @[read0; hsym `$wd,"/out.txt"; {()}];
    rawJson: @[read0; hsym `$wd,"/test-results.json"; {()}];
    payload: $[count rawJson; .j.k raze rawJson; ()!()];
    lcov: @[read0; hsym `$wd,"/coverage.lcov"; {()}];
    state: @[read0; hsym `$wd,"/coverage_state.txt"; {()}];
    rawCoverage: @[read0; hsym `$wd,"/coverage.json"; {()}];
    coverageJson:$[count rawCoverage;.j.k raze rawCoverage;()!()];
    coverageHtml:"\n" sv @[read0;hsym `$wd,"/coverage.html";{()}];
    if[wd like "*/resq_covmanifest_*"; system "rm -rf -- ", .utl.shellQuote wd];
    `code`output`payload`lcov`state`coverageJson`coverageHtml!(
        exitCode;output;payload;lcov;state;coverageJson;coverageHtml)
 };
.tst.testState.covgate.runManifest:{[]
    .tst.testState.covgate.runManifestWith "-cov-min 26 -cov-statements"};

/ Known-truth branch fixture. Six condition sites yield twelve boolean edges:
/ two ifs, three lazy $ conditions, and one while. The selected calls hit five
/ edges exactly (false,false; true; true,false).
.tst.testState.covgate.runBranchesWith:{[extra;inventory]
    wd:.utl.tempRoot[],"/resq_covbranches_",string[.z.i],"_",string `long$.z.p;
    sourceDir:wd,"/src";
    sourcePath:sourceDir,"/branches.q";
    missedPath:sourceDir,"/never_loaded.q";
    fixturePath:wd,"/test_branches.q";
    .utl.ensureDir sourceDir;
    (hsym `$sourcePath) 0:(
        ".branch.classify:{[x]";
        "  if[x<0; :`negative];";
        "  if[x=0; :`zero];";
        "  `positive";
        " };";
        ".branch.grade:{[s]";
        "  $[s>90; `A;";
        "    s>80; `B;";
        "    s>70; `C;";
        "    `F]";
        " };";
        ".branch.loop:{[n]";
        "  i:0;";
        "  while[i<n; i+:1];";
        "  i";
        " };");
    (hsym `$missedPath) 0:enlist
        ".branch.never:{[x] if[x; :1]; 0};";
    (hsym `$fixturePath) 0:(
        "system \"l \", ",.Q.s1[sourcePath],";";
        ".tst.desc[\"known branch truth\"]{";
        "  should[\"takes selected edges\"]{";
        "    .branch.classify[5] musteq `positive;";
        "    .branch.grade[95] musteq `A;";
        "    .branch.loop[2] musteq 2;";
        "  };";
        "};");
    scope:$[inventory;" --source ",.utl.shellQuote[sourceDir];
        " -cov-include ",.utl.shellQuote[sourcePath]];
    cmd:"true && timeout -k 2 60 q ",(.utl.shellQuote .resq.HOME,"/resq.q"),
        " cover ",(.utl.shellQuote fixturePath),scope,
        " -cov-branches ",extra," -json -outDir ",(.utl.shellQuote wd),
        .tst.testState.covgate.stateFlags[wd],
        " -quiet > ",(.utl.shellQuote wd,"/out.txt")," 2>&1; echo $?";
    exitLines:@[system;cmd;{[err]enlist "-1"}];
    exitCode:"J"$last exitLines;
    output:@[read0;hsym `$wd,"/out.txt";{()}];
    rawReport:@[read0;hsym `$wd,"/test-results.json";{()}];
    report:$[count rawReport;.j.k raze rawReport;()!()];
    rawCoverage:@[read0;hsym `$wd,"/coverage.json";{()}];
    coverage:$[count rawCoverage;.j.k raze rawCoverage;()!()];
    lcov:@[read0;hsym `$wd,"/coverage.lcov";{()}];
    state:@[read0;hsym `$wd,"/coverage_state.txt";{()}];
    html:"\n" sv @[read0;hsym `$wd,"/coverage.html";{()}];
    if[wd like "*/resq_covbranches_*";
        system "rm -rf -- ",.utl.shellQuote wd];
    `code`output`report`coverage`lcov`state`html!(
        exitCode;output;report;coverage;lcov;state;html)
 };

.tst.desc["Coverage gate decision"]{
    should["keep the legacy threshold function-based when partial lines look greener"]{
        / Mirrors the quickstart failure mode: statement data covers only part of
        / the source and reports 88.24%, while complete function reachability is
        / 70%. The legacy gate must use the conservative complete signal.
        summary: `linesFound`linesHit`linePercent`functionsFound`functionsHit`functionPercent!(
            17; 15; 88.23529f; 20; 14; 70f);
        decision: .tst.coverageGateDecision[summary; 85];
        decision[`measurable] musteq 1b;
        decision[`basis] musteq "functions";
        decision[`percent] musteq 70f;
        decision[`hit] musteq 14;
        decision[`found] musteq 20;
        decision[`passed] musteq 0b;
    };
};

.tst.desc["Branch coverage truth and gates #slow"]{
    skipIf[not .tst.testState.covgate.canRun;
           "measure if, while, and lazy conditional edges exactly"]{
        r:.tst.testState.covgate.runBranchesWith["";0b];
        r[`code] musteq 0;
        s:r[`coverage;`summary];
        s[`branchSitesEligible] musteq 6f;
        s[`branchSitesInstrumented] musteq 6f;
        s[`branchInstrumentationComplete] musteq 1b;
        s[`branchesFound] musteq 12f;
        s[`branchesHit] musteq 5f;
        s[`branchPercent] musteq 41.66667f;
        lcovSummary:.tst.coverageSummaryFromLines r`lcov;
        lcovSummary[`branchesFound] musteq 12;
        lcovSummary[`branchesHit] musteq 5;
        ("j"$sum r[`lcov] like "BRDA:*") musteq 12;
        ("j"$sum r[`lcov] like "BRF:12") musteq 1;
        ("j"$sum r[`lcov] like "BRH:5") musteq 1;
        branchRows:raze {x`branches} each r[`coverage;`files];
        kinds:branchRows`kind;
        must[(any "if"~/:kinds) and (any "while"~/:kinds) and
             any (enlist "$")~/:kinds;
             "JSON must expose each supported branch kind"];
        must[0<count ss[r`html;"Branch sites"];
             "HTML must render branch-site detail"];
        must[6=sum r[`state] like "B *";
             "state output must include every eligible branch site"];
        reportCoverage:r[`report;`coverage];
        reportCoverage[`branchesFound] musteq 12f;
        reportCoverage[`branchesHit] musteq 5f;
    };

    skipIf[not .tst.testState.covgate.canRun;
           "gate branch percentage at the exact measured boundary"]{
        pass:.tst.testState.covgate.runBranchesWith[
            "-cov-branches-min 41";0b];
        fail:.tst.testState.covgate.runBranchesWith[
            "-cov-branches-min 42";0b];
        pass[`code] musteq 0;
        pass[`report;`coverage;`gates;`branches;`passed] musteq 1b;
        fail[`code] musteq 1;
        fail[`report;`coverage;`gates;`branches;`passed] musteq 0b;
        failText:"\n" sv fail`output;
        must[0<count ss[failText;"below required minimum 42%"];
             "the failing gate must name the measured edge ratio"];
    };

    skipIf[not .tst.testState.covgate.canRun;
           "fail a branch gate closed when a manifest site is uninstrumented"]{
        r:.tst.testState.covgate.runBranchesWith[
            "-cov-branches-min 1";1b];
        r[`code] musteq 1;
        s:r[`coverage;`summary];
        s[`branchSitesEligible] musteq 7f;
        s[`branchSitesInstrumented] musteq 6f;
        s[`branchInstrumentationComplete] musteq 0b;
        s[`branchesFound] musteq 14f;
        r[`report;`coverage;`partialBranches] musteq 1b;
        outputText:"\n" sv r`output;
        must[0<count ss[outputText;
             "Branch coverage gate refused partial branch instrumentation"];
             "a partial branch denominator must never pass silently"];
        branchRows:raze {x`branches} each r[`coverage;`files];
        fallbacks:branchRows`fallbackReason;
        must[any "source_not_loaded"~/:fallbacks;
             "the unloaded branch site must explain its fallback"];
    };

    skipIf[not .tst.testState.covgate.canRun;
           "gate branch instrumentation completeness independently"]{
        r:.tst.testState.covgate.runBranchesWith[
            "-cov-branch-completeness-min 100";1b];
        r[`code] musteq 1;
        r[`report;`coverage;`gates;`branchCompleteness;`passed] musteq 0b;
        outputText:"\n" sv r`output;
        must[0<count ss[outputText;"below required minimum 100%"];
             "the completeness failure must name instrumented and eligible sites"];
    };
 };

.tst.desc["Coverage minimum gate #slow"]{
    skipIf[not .tst.testState.covgate.canRun;
           "include unloaded modules from an explicit source manifest"]{
        r: .tst.testState.covgate.runManifest[];
        r[`code] musteq 1;
        r[`payload;`coverage;`functionsFound] musteq 4f;
        r[`payload;`coverage;`functionsHit] musteq 1f;
        r[`payload;`coverage;`functionPercent] musteq 25f;
        must[any r[`lcov] like "SF:*/never_loaded.q";
             "LCOV must contain a record for an entirely unloaded module"];
        must[any r[`lcov] like "FNF:3";
             "the unloaded module must contribute all three functions"];
        zeroMisses: {(x like "F *") and (0<count ss[x;"/never_loaded.q "]) and
            0<count ss[x;" 0 "]} each r`state;
        must[3=sum zeroMisses;
             "coverage_state must include each zero-hit function"];
        detailCoverage:r`coverageJson;
        detailCoverage[`summary;`functionsFound] musteq 4f;
        detailCoverage[`summary;`functionsHit] musteq 1f;
        detailCoverage[`summary;`functionPercent] musteq 25f;
        (count detailCoverage`files) musteq 2;
        unloadedRows:detailCoverage[`files] where not detailCoverage[`files;`loaded];
        unloaded:unloadedRows 0;
        unloaded[`functionFound] musteq 3f;
        unloadedFunctions:unloaded`functions;
        fallbackReasons:unloadedFunctions`fallbackReason;
        must[all {x~"source_not_loaded"} each fallbackReasons;
             "detailed JSON must classify every unloaded function: ",
             .Q.s1 fallbackReasons];
        must[0<count ss[r`coverageHtml;"never_loaded.q"];
             "annotated HTML must include the unloaded module"];
        fallbackAt:ss[r`coverageHtml;"source_not_loaded"];
        must[0<count fallbackAt;
             "HTML must show the canonical fallback reason"];
    };

    skipIf[not .tst.testState.covgate.canRun;
           "keep LCOV, JSON, HTML, state, and test JSON totals consistent"]{
        r:.tst.testState.covgate.runManifestWith "-cov-statements";
        lcovSummary:.tst.coverageSummaryFromLines r`lcov;
        detailSummary:r[`coverageJson;`summary];
        reportCoverage:r[`payload;`coverage];
        detailFunctionFound:"j"$detailSummary`functionsFound;
        detailFunctionHit:"j"$detailSummary`functionsHit;
        detailLineFound:"j"$detailSummary`linesFound;
        detailLineHit:"j"$detailSummary`linesHit;
        detailFunctionFound musteq lcovSummary`functionsFound;
        detailFunctionHit musteq lcovSummary`functionsHit;
        detailLineFound musteq lcovSummary`linesFound;
        detailLineHit musteq lcovSummary`linesHit;
        reportCoverage[`functionsFound] musteq detailSummary`functionsFound;
        reportCoverage[`functionsHit] musteq detailSummary`functionsHit;
        reportCoverage[`linesFound] musteq detailSummary`linesFound;
        reportCoverage[`linesHit] musteq detailSummary`linesHit;
        must[0<count ss[r`coverageHtml;
             string[detailSummary`functionsHit]," / ",string[detailSummary`functionsFound]];
             "HTML summary must render the canonical function totals"];
        stateFunctions:r[`state] where r[`state] like "F *";
        stateFunctionCount:"f"$count stateFunctions;
        stateFunctionCount musteq detailSummary`functionsFound;
    };

    skipIf[not .tst.testState.covgate.canRun;
           "refuse a line gate over partial instrumentation by default"]{
        r:.tst.testState.covgate.runManifestWith "-cov-lines-min 100";
        r[`code] musteq 1;
        text:"\n" sv r`output;
        must[0<count ss[text;"Line coverage gate refused partial statement instrumentation"];
             "the console error must explain why the partial line gate was refused"];
        r[`payload;`coverage;`partialLines] musteq 1b;
        r[`payload;`coverage;`allowPartialLines] musteq 0b;
        r[`payload;`coverage;`passed] musteq 0b;
    };

    skipIf[not .tst.testState.covgate.canRun;
           "allow an explicitly acknowledged partial line gate"]{
        r:.tst.testState.covgate.runManifestWith
            "-cov-lines-min 100 -cov-allow-partial";
        r[`code] musteq 0;
        r[`payload;`coverage;`partialLines] musteq 1b;
        r[`payload;`coverage;`allowPartialLines] musteq 1b;
        r[`payload;`coverage;`gates;`lines;`passed] musteq 1b;
        r[`payload;`coverage;`passed] musteq 1b;
    };

    skipIf[not .tst.testState.covgate.canRun;
           "gate statement instrumentation completeness independently"]{
        r:.tst.testState.covgate.runManifestWith "-cov-completeness-min 100";
        r[`code] musteq 1;
        r[`payload;`coverage;`statementFunctionsEligible] musteq 4f;
        r[`payload;`coverage;`statementFunctionsInstrumented] musteq 1f;
        r[`payload;`coverage;`statementInstrumentationPercent] musteq 25f;
        r[`payload;`coverage;`gates;`completeness;`passed] musteq 0b;
    };

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
        failed[`payload;`summary;`errorCount] musteq 1f;
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
        passed[`payload;`summary;`passCount] musteq 1f;
        passed[`payload;`summary;`errorCount] musteq 0f;
        passed[`payload;`coverage;`passed] musteq 1b;
    };

    skipIf[not .tst.testState.covgate.canRun;
           "retain MEASURED lines but gate functions under -cov-statements"]{
        / Same fixture, statement mode: real line records remain available as a
        / diagnostic, but the legacy threshold stays on the complete function
        / inventory. Separate line thresholds require a completeness contract.
        r: .tst.testState.covgate.runWith[51; "-cov-statements"];
        r[`code] musteq 1;
        outputText: "\n" sv r`output;
        must[0 < count ss[outputText;"functions (1/2); measured lines 50% (1/2)"];
             "statement mode must report the gate and measured-line diagnostic"];
        must[0 < count ss[outputText;"-cov-min gates on complete function coverage"];
             "the console must make the legacy threshold basis explicit"];
        r[`payload;`coverage;`basis] musteq "functions";
        r[`payload;`coverage;`linePercent] musteq 50f;
        must[any r[`lcov] like "LF:2"; "LCOV must carry a measured line denominator"];
        must[any r[`lcov] like "LH:1"; "LCOV must carry a measured line numerator"];
    };
};

::
