/ Optional coverage of resQ itself through KX Developer's independent .cov
/ engine. The adapter is inert and never loads a provider unless
/ RESQ_SELF_COVERAGE_LIBRARY is set. It deliberately does not use
/ lib/coverage.q: a rewriter cannot safely rewrite the framework code
/ implementing that same rewrite.

.resq.selfCoverageSummary:{[rows]
    required:`name`iterations`lineIterations`blockIterations`lines`blocks`text;
    if[not 98h=type rows;'"external self-coverage provider returned a non-table"];
    missing:required where not required in cols rows;
    if[count missing;
        '"external self-coverage provider omitted columns: "," " sv string missing];
    iterations:"j"$rows`iterations;
    lineIterations:"j"$raze rows`lineIterations;
    blockIterations:"j"$raze rows`blockIterations;
    `functionsMeasured`functionsHit`logicalLinesMeasured`logicalLinesHit`blocksMeasured`blocksHit!(
        "j"$count rows;
        "j"$sum 0j<iterations;
        "j"$count lineIterations;
        "j"$sum 0j<lineIterations;
        "j"$count blockIterations;
        "j"$sum 0j<blockIterations)
 };

.resq.writeSelfCoverage:{[rows;output;namespaces]
    out:.utl.normalizePath output;
    if[not "/"=first out;out:(system "cd"),"/",out];
    .utl.ensureDir out;
    summary:.resq.selfCoverageSummary rows;
    measurement:`provider`basis`complete`gatingSupported`scope`limitations`namespaces!(
        "KX Developer .cov";
        "logical lines and conditional/loop blocks";
        0b;
        0b;
        "loaded lambdas and projections in selected framework namespaces";
        "Compositions, adverb-bound functions, code loaded after instrumentation, and source-file denominator completeness are not measured.";
        string each namespaces);
    payload:`schemaVersion`kind`framework`frameworkVersion`generatedAt`qVersion`measurement`summary`rawResults!(
        1j;
        "resq-self-coverage";
        "resQ";
        .tst.toString @[get;`.resq.VERSION;{"unknown"}];
        .tst.isoTimestamp .z.P;
        .tst.toString .z.K;
        measurement;
        summary;
        rows);
    jsonPath:out,"/self-coverage.json";
    textPath:out,"/self-coverage.txt";
    (hsym `$jsonPath) 0:enlist .tst.output.strictJson payload;
    formatted:.cov.format.go rows;
    header:(
        "resQ self-coverage (optional external evidence; not a release gate)";
        "Provider: KX Developer .cov";
        "Scope: loaded lambdas/projections in .tst, .resq, and .utl";
        "Completeness: partial by construction; see self-coverage.json";
        "");
    (hsym `$textPath) 0:header,formatted;
    -1 "External self-coverage JSON written to: ",jsonPath;
    -1 "External self-coverage text written to: ",textPath;
    ::
 };

.resq.runAllWithOptionalSelfCoverage:{[]
    library:getenv `RESQ_SELF_COVERAGE_LIBRARY;
    if[0=count library;:.tst.runAll[]];
    if[1b~@[get;`.tst.app.runCoverage;0b];
        '"external self-coverage cannot be combined with resQ source coverage"];
    if[1b~@[get;`.tst.app.isolate;0b];
        '"external self-coverage cannot observe isolated child processes"];
    if[not .utl.isFile library;
        '"external self-coverage library is not a regular file: ",library];
    loadOutcome:@[
        {[path].utl.loadQFile path;(0b;"")};
        library;
        {[e](1b;.tst.toString e)}];
    if[first loadOutcome;
        '"failed to load external self-coverage library: ",last loadOutcome];
    covKeys:@[key;`.cov;{`symbol$()}];
    if[not `run in covKeys;'"external coverage library does not export .cov.run"];
    formatKeys:@[key;`.cov.format;{`symbol$()}];
    if[not `go in formatKeys;
        '"external coverage library does not export .cov.format.go"];
    namespaces:`.tst`.resq`.utl;
    settings:(enlist `namespaces)!enlist namespaces;
    rows:.cov.run[.tst.runAll;enlist (::);settings];
    output:getenv `RESQ_SELF_COVERAGE_OUTPUT;
    if[0=count output;output:"artifacts/self-coverage"];
    .resq.writeSelfCoverage[rows;output;namespaces];
    ::
 };
