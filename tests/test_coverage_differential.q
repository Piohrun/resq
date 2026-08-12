/ ============================================================================
/ Generative differential testing for STATEMENT INSTRUMENTATION.
/ .
/ `-cov-statements` rewrites the user's function bodies at load time to insert
/ probes. That is the riskiest thing resQ does to code it does not own, and
/ reasoning about it by hand has already been wrong once: probes were inserted
/ at the start of the LINE holding a statement, which for a statement nested in
/ `$[c; if[a;b:1]; ...]` landed the probe in the conditional expression's branch
/ list, shifted every branch, and silently changed what the expression returned.
/ It surfaced as a bare 'type deep inside resQ's own loader.
/ .
/ So the property is checked by execution rather than argument:
/ .
/     for a generated function f and generated input x,
/     f[x] and (side effects of f[x]) must be IDENTICAL
/     before and after instrumentation.
/ .
/ Same shape as tests/test_loader_differential.q: a seeded LCG makes each seed
/ reproduce its exact function, so a divergence is a permanent, replayable case.
/ A fixed corpus of constructs known to be dangerous runs on every invocation;
/ random seeds explore combinations of them.
/ .
/ Proven to work: reintroducing the line-start insertion defect makes the corpus
/ case `condExprWithNestedIf` fail with "return values differ". Swept clean to
/ seed 400 during development (400 generated functions, 0 divergences, 0 falling
/ back to uninstrumented); the in-suite run uses seeds 1..75 and exercises the
/ full instrumentation pipeline, not only the low-level source rewrite. Nightly
/ CI raises the deterministic count through RESQ_COVERAGE_DIFF_SEEDS.
/ ============================================================================

.utl.require .utl.PKGLOADING, "/coverage.q";

.tst.testState.cdiff.dir: .utl.tempRoot[], "/resq_cdiff_", string .z.i;
.tst.testState.cdiff.keepDir: 0b;
.tst.testState.cdiff.sideEffects: 0;

.tst.testState.cdiff.seedCount:{[]
  raw:getenv `RESQ_COVERAGE_DIFF_SEEDS;
  if[0=count raw;:75];
  parsed:@["J"$;raw;{-1j}];
  if[(parsed<1) or parsed>10000;
    '"RESQ_COVERAGE_DIFF_SEEDS must be an integer from 1 through 10000"];
  parsed
 };

/ Snapshot all mutable coverage state: this suite now drives the same public
/ instrumentFile pipeline a real coverage run uses (rewrite + wrapper + model).
.tst.testState.cdiff.coverageKeys:`$((
  ".tst.coverageData";".tst.coverageEnabled";".tst.trackedFiles";
  ".tst.origFuncs";".tst.covWrappers";".tst.coverageLoadedFiles";
  ".tst.lineCoverageData";".tst.stmtInstrumented";".tst.stmtProbeLines";
  ".tst.coverageStatements";".tst.lastCoverageModel"));

.tst.testState.cdiff.resetCoverage:{[]
  .tst.coverageData:()!();
  .tst.coverageEnabled:1b;
  .tst.trackedFiles:`symbol$();
  .tst.origFuncs:()!();
  .tst.covWrappers:()!();
  .tst.coverageLoadedFiles:`symbol$();
  .tst.lineCoverageData:()!();
  .tst.stmtInstrumented:()!();
  .tst.stmtProbeLines:()!();
  .tst.coverageStatements:1b;
  .tst.lastCoverageModel:()!();
 };

/ ---- seeded RNG (same idiom as the loader harness) -------------------------
.tst.testState.cdiff.seedRng:{[s] .tst.testState.cdiff.lcg: "j"$ 1 + s; };
.tst.testState.cdiff.rng:{[]
  st: .tst.testState.cdiff.lcg;
  st: (6364136223846793005 * st) + 1442695040888963407;
  .tst.testState.cdiff.lcg: st;
  (abs (st mod 1000000)) % 1000000
 };
.tst.testState.cdiff.randInt:{[n] "j"$ n * .tst.testState.cdiff.rng[]};
.tst.testState.cdiff.pick:{[xs] xs .tst.testState.cdiff.randInt count xs};

/ ---- statement templates ---------------------------------------------------
/ Each is a body fragment. They mutate `acc` (returned) and a GLOBAL counter, so
/ a rewrite that changes control flow shows up as either a different result or a
/ different number of side effects. Deliberately covers the constructs that make
/ instrumentation hard: guards with early return, loops, conditional
/ EXPRESSIONS (which must never be probed), nested lambdas, strings holding
/ semicolons and braces, trailing comments, and multi-line brackets.
.tst.testState.cdiff.templates: (
  (enlist "    acc: acc + 1;");
  (enlist "    acc: acc + x;");
  ("    if[x > 2;"; "        acc: acc + 10";"    ];");
  ("    if[x < 0;"; "        :`negative";"    ];");
  ("    if[x > 100;"; "        acc: acc + 1;"; "        acc: acc + 2";"    ];");
  ("    do[3;"; "        acc: acc + 1";"    ];");
  ("    i2: 0;"; "    while[i2 < 2;"; "        acc: acc + 1;"; "        i2: i2 + 1";"    ];");
  (enlist "    acc: acc + $[x > 1; 5; 7];");
  ("    acc: acc + $[x > 1;"; "        5;"; "        7];");
  (enlist "    g: {[y] y * 2}; acc: acc + g 1;");
  (enlist "    s: \"a;b{c}\"; acc: acc + count s;");
  (enlist "    acc: acc + 1;  / trailing comment with ; and }");
  ("    / a standalone comment line"; "    acc: acc + 1;");
  ("    acc: acc +"; "        1;");
  (enlist "    acc: acc + 1; acc: acc + 1;");
  ("    $[x > 1;"; "        acc: acc + 3;"; "      x < 0;"; "        acc: acc + 4;"; "        acc: acc + 5];");
  (enlist "    .tst.testState.cdiff.sideEffects: .tst.testState.cdiff.sideEffects + 1;")
 );

/ Build one function's source. Always ends with `acc` so it returns a value.
.tst.testState.cdiff.genBody:{[nStmts]
  raze {[i] .tst.testState.cdiff.pick .tst.testState.cdiff.templates} each til nStmts
 };

.tst.testState.cdiff.genSource:{[name; nStmts]
  (enlist name, ":{[x]"), (enlist "    acc: 0;"),
    .tst.testState.cdiff.genBody[nStmts], (enlist "    acc"), enlist " };"
 };

/ ---- the differential check ------------------------------------------------
/ Load a generated function, exercise it, instrument it, exercise it again, and
/ compare BOTH the returned values and the side-effect count.
.tst.testState.cdiff.checkSource:{[label; src]
  d: .tst.testState.cdiff.dir;
  .utl.ensureDir d;
  path: d, "/", label, ".q";
  (hsym `$path) 0: src;

  name: `$".cdiffgen.f";
  inputs: -1 0 1 2 3 5 200;

  / Baseline: the function as written.
  ok: @[{[p] system "l ", p; 1b}; path; {[e] 0b}];
  if[not ok; :`loadFail];
  .tst.testState.cdiff.sideEffects: 0;
  / NB: not `before`/`after` -- those are DSL verbs exported into .q, and q
  / signals 'assign for a local shadowing a .q name.
  baseVals: @[{[n;xs] {[n;v] @[value n; v; {[e] `$"ERR:", e}]}[n;] each xs}[name;]; inputs; {[e] `callFail}];
  if[baseVals ~ `callFail; :`callFail];
  baseFx: .tst.testState.cdiff.sideEffects;

  / Instrument through the production file pipeline. This verifies namespace
  / qualification, statement rewriting, wrapper installation, hit accounting,
  / and the canonical model as one composed behavior.
  fileSym:`$.tst.resolvePath path;
  applied:@[{[p] .tst.instrumentFile p;1b};path;{[e] 0b}];
  if[not applied; :`notInstrumented];
  measured:$[fileSym in key .tst.stmtInstrumented;
    .tst.stmtInstrumented fileSym;`symbol$()];
  if[(not name in key .tst.covWrappers) or (not name in measured);
    :`notInstrumented];

  .tst.testState.cdiff.sideEffects: 0;
  instVals: @[{[n;xs] {[n;v] @[value n; v; {[e] `$"ERR:", e}]}[n;] each xs}[name;]; inputs; {[e] `callFail}];
  if[instVals ~ `callFail; :`divergeCall];
  instFx: .tst.testState.cdiff.sideEffects;

  if[not baseVals ~ instVals;
      .tst.testState.cdiff.report[label; src; baseVals; instVals; "return values differ"];
      :`divergeValue];
  if[not baseFx ~ instFx;
      .tst.testState.cdiff.report[label; src; baseFx; instFx; "side-effect counts differ"];
      :`divergeEffects];
  fileModel:.tst.coverageFileModel fileSym;
  fnModels:fileModel`functions;
  modelOk:1=count fnModels;
  if[modelOk;modelOk:1b~fnModels[0;`functionInstrumented]];
  if[modelOk;modelOk:1b~fnModels[0;`statementInstrumented]];
  if[modelOk;modelOk:"none"~fnModels[0;`fallbackReason]];
  if[modelOk;modelOk:0<fnModels[0;`statementFound]];
  if[not modelOk;
      .tst.testState.cdiff.report[label;src;"instrumented function";fnModels;
        "canonical model lost instrumentation state"];
      :`divergeModel];
  `pass
 };

.tst.testState.cdiff.report:{[label; src; b; a; why]
  -1 "";
  -1 "==== INSTRUMENTATION DIVERGENCE [", label, "]: ", why, " ====";
  -1 "---- source ----";
  {[i;l] -1 ((-4$string i), ": "), l}'[1 + til count src; src];
  -1 "---- before ----"; -1 .Q.s1 b;
  -1 "---- after  ----"; -1 .Q.s1 a;
  -1 "(source kept at ", .tst.testState.cdiff.dir, "/", label, ".q)";
  -1 "";
  .tst.testState.cdiff.keepDir: 1b;
 };

.tst.testState.cdiff.runSeed:{[seed]
  .tst.testState.cdiff.seedRng seed;
  n: 2 + .tst.testState.cdiff.randInt 5;
  src: .tst.testState.cdiff.genSource[".cdiffgen.f"; n];
  .tst.testState.cdiff.checkSource["seed_", string seed; src]
 };

/ ---- fixed corpus: one function per dangerous construct --------------------
/ Every one of these has a specific reason to exist. The conditional-expression
/ cases are the regression that motivated the harness.
.tst.testState.cdiff.corpus: (
  (`guardEarlyReturn;
    (".cdiffgen.f:{[x]"; "    acc: 0;"; "    if[x < 0;"; "        :`negative"; "    ];";
     "    acc: acc + 1;"; "    acc"; " };"));
  (`condExprInline;
    (".cdiffgen.f:{[x]"; "    acc: $[x > 1; 5; 7];"; "    acc"; " };"));
  (`condExprMultiline;
    (".cdiffgen.f:{[x]"; "    acc: $[x > 1;"; "        5;"; "        7];"; "    acc"; " };"));
  (`condExprWithNestedIf;
    (".cdiffgen.f:{[x]"; "    acc: 0;"; "    $[x > 1;"; "        if[x > 2; acc: acc + 1];";
     "      x < 0;"; "        acc: acc + 2;"; "        acc: acc + 3];"; "    acc"; " };"));
  (`nestedIfMultiStatement;
    (".cdiffgen.f:{[x]"; "    acc: 0;"; "    if[x > 0;"; "        acc: acc + 1;";
     "        acc: acc + 2"; "    ];"; "    acc"; " };"));
  (`whileLoop;
    (".cdiffgen.f:{[x]"; "    acc: 0;"; "    i2: 0;"; "    while[i2 < 3;"; "        acc: acc + x;";
     "        i2: i2 + 1"; "    ];"; "    acc"; " };"));
  (`doLoop;
    (".cdiffgen.f:{[x]"; "    acc: 0;"; "    do[4; acc: acc + 1];"; "    acc"; " };"));
  (`nestedLambda;
    (".cdiffgen.f:{[x]"; "    g: {[y] z: y * 2; z + 1};"; "    acc: g x;"; "    acc"; " };"));
  (`stringWithSemicolon;
    (".cdiffgen.f:{[x]"; "    s: \"a;b;c{}\";"; "    acc: count s;"; "    acc"; " };"));
  (`trailingComments;
    (".cdiffgen.f:{[x]"; "    acc: 1;  / one ; here"; "    / whole-line comment";
     "    acc: acc + 1;"; "    acc"; " };"));
  (`multiStatementLine;
    (".cdiffgen.f:{[x]"; "    acc: 0; acc: acc + 1; acc: acc + 2;"; "    acc"; " };"));
  (`multiLineExpression;
    (".cdiffgen.f:{[x]"; "    acc: 1 +"; "        2 +"; "        3;"; "    acc"; " };"));
  (`signatureOnly;
    (enlist ".cdiffgen.f:{[x] x + 1 };"));
  (`noParams;
    (enlist ".cdiffgen.f:{ 42 };"))
 );

.tst.testState.cdiff.runCorpus:{[]
  {[e] (e 0; .tst.testState.cdiff.checkSource[string e 0; e 1])}
    each .tst.testState.cdiff.corpus
 };

.tst.testState.cdiff.runSeeds:{[seeds]
  {[s] (`$"seed_", string s; .tst.testState.cdiff.runSeed s)} each seeds
 };

.tst.testState.cdiff.summarise:{[results]
  bad: results where not (results[;1]) in `pass`notInstrumented`loadFail;
  notInst: results where (results[;1]) = `notInstrumented;
  passed: results where (results[;1]) = `pass;
  `diverged`notInstrumented`passed!(bad; notInst; passed)
 };

/ ============================================================================
.tst.desc["statement instrumentation: differential vs uninstrumented (#slow)"]{
  beforeAll{
    .tst.testState.cdiff.savedCoverage:
      .tst.testState.cdiff.coverageKeys!
      {@[get;x;{[e] ::}]} each .tst.testState.cdiff.coverageKeys;
    .tst.testState.cdiff.resetCoverage[];
  };
  afterAll{
    d: .tst.testState.cdiff.dir;
    $[.tst.testState.cdiff.keepDir;
        -1 "NOTE: differential sources kept for post-mortem: ", d;
        if[(d like "*/resq_cdiff_*") and .utl.pathExists d;
            @[system; "rm -rf -- ", .utl.shellQuote d; {[e] }]]];
    saved:.tst.testState.cdiff.savedCoverage;
    {[n;v] set[n;v]}'[key saved;value saved];
  };

  should["preserve behaviour across the dangerous-construct corpus"]{
    res: .tst.testState.cdiff.summarise .tst.testState.cdiff.runCorpus[];
    bad: $[count res`diverged; -3! (res`diverged)[;0]; ""];
    must[0 = count res`diverged;
         "instrumentation changed behaviour for: ", bad];
    / The corpus must actually be exercising instrumentation, not silently
    / falling back to "could not rewrite" for everything.
    must[8 <= count res`passed;
         "expected most of the corpus to instrument, got ", string count res`passed];
  };

  should["preserve behaviour across seeded random functions"]{
    seedCount:.tst.testState.cdiff.seedCount[];
    -1 "COVERAGE_DIFFERENTIAL_SEEDS=",string seedCount;
    res: .tst.testState.cdiff.summarise .tst.testState.cdiff.runSeeds 1 + til seedCount;
    bad: $[count res`diverged; -3! (res`diverged)[;0]; ""];
    must[0 = count res`diverged;
         "instrumentation changed behaviour for: ", bad];
    must[(2*seedCount) div 3 <= count res`passed;
         "expected most seeds to instrument, got ", string count res`passed];
  };
 };
