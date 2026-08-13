.tst.desc["Deterministic property generators"]{
  should["sample every built-in generator without touching q's random stream"]{
    scalar:.resq.gen.scalar[`int;-10;10];
    choices:.resq.gen.weightedChoice[`cold`warm`hot;1 2 7];
    record:.resq.gen.dictionary[
      `id`status!(scalar;choices)];
    tuple:.resq.gen.tuple[(scalar;.resq.gen.nullable[choices;0.25])];
    rows:.resq.gen.table[`id`status!(scalar;choices);2;5];
    mapped:.resq.gen.map[scalar;{x*2}];
    filtered:.resq.gen.filter[scalar;{0=x mod 2};100];

    firstRun:.resq.gen.sampleList[record;25;4242;"record"];
    secondRun:.resq.gen.sampleList[record;25;4242;"record"];
    firstRun mustmatch secondRun;
    count[firstRun] musteq 25;
    must[all {`id`status~key x} each firstRun;"record keys must be stable"];

    tupleValue:.resq.gen.sample[tuple;4242;0;"tuple"];
    count[tupleValue] musteq 2;
    tableValue:.resq.gen.sample[rows;4242;0;"table"];
    type[tableValue] musteq 98h;
    count[tableValue] mustwithin 2 5;
    0 musteq (.resq.gen.sample[filtered;4242;0;"filter"]) mod 2;
    0 musteq (.resq.gen.sample[mapped;4242;0;"map"]) mod 2;

    oldSeed:system "S";
    system "S 991";
    expected:20?1000000;
    system "S 991";
    ignored:.resq.gen.sampleList[rows;100;77;"private"];
    actual:20?1000000;
    system "S ",string oldSeed;
    actual mustmatch expected;
  };

  should["cover boundary, collection, nullable, tuple, table, map and filter shapes"]{
    bounds:.resq.gen.boundary (0N;0;1;0W);
    must[all {[g;x].resq.gen.sample[g;7;x;"boundary"] in (0N;0;1;0W)}[bounds;] each til 20;
      "boundary samples must come from the declared values"];

    lists:.resq.gen.list[.resq.gen.scalar[`short;-3h;3h];1;6];
    samples:.resq.gen.sampleList[lists;30;7;"lists"];
    must[all (count each samples) within 1 6;"collection lengths must be bounded"];
    must[all {-5h=type x} each raze samples;"collection element types must be preserved"];

    nulls:.resq.gen.sampleList[.resq.gen.nullable[`int;1f];5;7;"nullable"];
    must[all null nulls;"nullable rate 1 must always produce null"];
    type[nulls] musteq 6h;

    temporal:`timestamp`month`date`datetime`timespan`minute`second`time;
    temporalGenerators:.resq.gen.typed each temporal;
    values:.resq.gen.sample[;7;0;"temporal"] each temporalGenerators;
    typeCodes:type each values;
    typeCodes mustmatch neg 12 13 14 15 16 17 18 19h;
  };

  should["adapt legacy vars forms and keep generated symbols bounded"]{
    specs:(`int;`a`b`c;`int$();`a`b!(`int;`float);{42});
    generators:.resq.gen.adapt each specs;
    must[all .resq.gen.isGenerator each generators;"all legacy vars forms must adapt"];
    type[.resq.gen.sample[first generators;9;0;"legacy"]] musteq -6h;
    .resq.gen.sample[generators 1;9;0;"legacy"] mustin `a`b`c;
    type[.resq.gen.sample[generators 2;9;0;"legacy"]] musteq 6h;
    `a`b mustmatch key .resq.gen.sample[generators 3;9;0;"legacy"];
    .resq.gen.sample[last generators;9;0;"legacy"] musteq 42;

    symbolValues:.resq.gen.sampleList[.resq.gen.typed `symbol;1000;9;"symbols"];
    must[all symbolValues in `a`b`c`d`e`f`g;
      "built-in symbol generation must use the bounded symbol pool"];
  };

  should["replay an exact sample from its portable token"]{
    generator:.resq.gen.table[
      `x`flag!(.resq.gen.scalar[`long;-100;100];.resq.gen.typed `boolean);1;4];
    token:.resq.gen.replayToken[12345;17];
    token musteq "resq-pbt-v1/12345/17";
    .resq.gen.replay[generator;token]
      mustmatch .resq.gen.sample[generator;12345;17;"root"];
    mustthrow["invalid resQ property replay token";
      ({[g].resq.gen.replay[g;"bad-token"]};generator)];
  };
};

.tst.desc["Property shrink protocol"]{
  should["preserve the failure class and report deterministic shrink telemetry"]{
    code:{[x].tst.asserts[`musteq][count x;0]};
    generator:.resq.gen.list[.resq.gen.scalar[`int;0;100];1;10];
    original:10 20 30 40 50i;
    savedAssertCount:.tst.assertState`assertsRun;
    savedSuppress:.tst.suppressAssertionDiff;
    .tst.suppressAssertionDiff:1b;
    initial:.tst.fuzzRunCollector[code;original];
    limits:`steps`candidates`timeMs!(50j;200j;1000f);
    a:.tst.shrinkTree[code;generator;original;initial;limits];
    b:.tst.shrinkTree[code;generator;original;initial;limits];
    .tst.suppressAssertionDiff:savedSuppress;
    .tst.assertState:``failures`assertsRun!(::;();savedAssertCount);
    a[`minimal`steps`candidates`termination`failureSignature]
      mustmatch b[`minimal`steps`candidates`termination`failureSignature];
    (a`minimal) mustmatch enlist 0i;
    (a`termination) musteq `minimal;
    (a`failureSignature) musteq .tst.fuzzFailureSignature initial;
  };

  should["obey independent step, candidate and time ceilings"]{
    code:{[x].tst.asserts[`musteq][count x;0]};
    generator:.resq.gen.list[.resq.gen.scalar[`int;0;100];1;10];
    original:10 20 30 40 50i;
    savedAssertCount:.tst.assertState`assertsRun;
    savedSuppress:.tst.suppressAssertionDiff;
    .tst.suppressAssertionDiff:1b;
    initial:.tst.fuzzRunCollector[code;original];

    byStep:.tst.shrinkTree[code;generator;original;initial;
      `steps`candidates`timeMs!(0j;100j;1000f)];
    (byStep`termination) musteq `stepLimit;
    (byStep`candidates) musteq 0;

    byCandidate:.tst.shrinkTree[code;generator;original;initial;
      `steps`candidates`timeMs!(100j;0j;1000f)];
    (byCandidate`termination) musteq `candidateLimit;
    (byCandidate`candidates) musteq 0;

    byTime:.tst.shrinkTree[code;generator;original;initial;
      `steps`candidates`timeMs!(100j;100j;0f)];
    .tst.suppressAssertionDiff:savedSuppress;
    .tst.assertState:``failures`assertsRun!(::;();savedAssertCount);
    (byTime`termination) musteq `timeLimit;
    (byTime`candidates) musteq 0;
  };

  should["export replay, original, minimal and termination telemetry"]{
    .tst.currentContext:`file`suite`test!(
      "tests/test_generators.q";"Property shrink protocol";"telemetry");
    expec:.tst.internals.fuzzObj;
    expec[`runs]:3;
    expec[`vars]:.resq.gen.list[.resq.gen.scalar[`int;0;20];2;5];
    expec[`props]:`seed`shrinkSteps`shrinkCandidates`shrinkTimeMs!(99j;20j;100j;1000f);
    expec[`code]:{[x].tst.asserts[`musteq][count x;0]};
    result:.tst.runners[`fuzz] expec;
    telemetry:.tst.expectationTelemetry[
      `title`file!("Property shrink protocol";"tests/test_generators.q");
      result;"tests/test_generators.q"]`property;

    (telemetry`generatorProtocol) musteq "resq-generator-v1";
    (telemetry`replayToken) musteq first telemetry`replayTokens;
    count[telemetry`replayTokens] musteq telemetry`failCount;
    (telemetry`originalInput) mustmatch result`originalFailure;
    (telemetry`minimalInput) mustmatch result`shrunkFailure;
    (telemetry`shrunkInput) mustmatch telemetry`minimalInput;
    (telemetry`shrinkSteps) musteq result`shrinkSteps;
    (telemetry`shrinkCandidates) musteq result`shrinkCandidates;
    (telemetry`shrinkTermination) musteq string result`shrinkTermination;
    count[telemetry`failureSignature] mustgt 0;
  };
};

.tst.desc["Public generator integration"]{
  holds["accepts protocol generators in vars";
    `runs`seed`vars!(20;2026j;.resq.gen.dictionary[
      `left`right!(.resq.gen.scalar[`int;-100;100];.resq.gen.scalar[`int;-100;100])])]{[x]
    ((x`left)+(x`right)) musteq ((x`right)+(x`left));
  };
};
