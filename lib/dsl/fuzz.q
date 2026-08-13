\d .tst
fuzzListMaxLength:100

typeNames: `boolean`guid`byte`short`int`long`real`float`char`symbol`timestamp`month`date`datetime`timespan`minute`second`time
typeCodes: 1 2 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19h
typeDefaults:(0b;0Ng;0x00;0h;0i;0j;0e;0f;" ";`symbol;0p;2000.01m;2000.01.01;2000.01.01T00:00:00.000;0D00:00:00.000000000;00:00;00:00:00;00:00:00.000)
typeFuzzN: typeNames!typeDefaults
typeFuzzC: typeCodes!typeDefaults

/ Hash-counter generator used by property tests and execution ordering. It is
/ private to resQ: unlike q's `?` / `\S`, it cannot consume or reset the
/ application's global random stream. The first four MD5 bytes form an unsigned
/ 32-bit word in a q long; keyed hashing makes any seed/counter pair replayable.
privateWord:{[seed;counter;stream]
    input:raze (.tst.toString[seed];"/";.tst.toString[counter];"/";.tst.toString stream);
    digest:md5 input;
    sum ("j"$4#digest)*1 256 65536 16777216j
 };

privateIndex:{[seed;counter;stream;bound]
    $[bound<=0;0j;.tst.privateWord[seed;counter;stream] mod "j"$bound]
 };

/ Return a replayable permutation without touching q's process-global random
/ stream. Equal hash words retain their input order through iasc, so even the
/ (vanishingly unlikely) collision case is deterministic.
seededPermutation:{[items;seed;stream]
    n:count items;
    if[2>n;:items];
    ranks:.tst.privateWord["j"$seed;;stream] each til n;
    items iasc ranks
 };

/ Apply execution ordering only when explicitly enabled. Keeping the switch in
/ one helper prevents file, suite and expectation ordering from drifting apart.
orderItems:{[items;stream]
    enabled:1b~@[get;`.tst.app.randomOrder;0b];
    if[not enabled;:items];
    seed:"j"$@[get;`.tst.app.executionSeed;0j];
    .tst.seededPermutation[items;seed;stream]
 };

privateGuid:{[seed;counter;stream]
    hex:raze string md5 raze (
        .tst.toString[seed];"/";.tst.toString[counter];"/";.tst.toString stream);
    text:(8#hex),"-",(4#8 _ hex),"-",(4#12 _ hex),"-",
        (4#16 _ hex),"-",(12#20 _ hex);
    "G"$text
 };

privateScalar:{[default;seed;counter;stream]
    tc:type default;
    word:.tst.privateWord[seed;counter;stream];
    $[tc=-1h;0b+word mod 2;
      tc=-2h;.tst.privateGuid[seed;counter;stream];
      tc=-4h;"x"$(word mod 256);
      tc=-5h;"h"$(word mod 32767);
      tc=-6h;"i"$(word mod 2000000000);
      tc=-7h;word;
      tc=-8h;"e"$word%4294967296f;
      tc=-9h;word%4294967296f;
      tc=-10h;.Q.a .tst.privateIndex[seed;counter;stream;count .Q.a];
      tc=-11h;`a`b`c`d`e`f`g .tst.privateIndex[seed;counter;stream;7];
      tc=-12h;2000.01.01D00:00:00.000000000+word*1000000000;
      tc=-13h;2000.01m+("i"$(word mod 2400));
      tc=-14h;2000.01.01+("i"$(word mod 36525));
      tc=-15h;2000.01.01T00:00:00.000+("f"$(word mod 3155760000j))%86400f;
      tc=-16h;0D00:00:00.000000000+word*1000000;
      tc=-17h;00:00+("i"$(word mod 1440));
      tc=-18h;00:00:00+("i"$(word mod 86400));
      tc=-19h;00:00:00.000+("i"$(word mod 86400000));
      default]
 };

privateVector:{[default;length;seed;counter;stream]
    {[d;s;c;st;j].tst.privateScalar[d;s;c*101+j;st]}[
        default;seed;counter;stream;] each til length
 };

pickListFuzzSeeded:{[values;runs;seed;stream]
    tc:abs type values;
    if[0=count values;
        default:.tst.typeFuzzC tc;
        :{[d;s;st;i]
            len:.tst.privateIndex[s;i;st,"/length";.tst.fuzzListMaxLength];
            .tst.privateVector[d;len;s;i;st]
        }[default;seed;stream;] each til runs];
    if[(1=count distinct values) and null first values;
        default:.tst.typeFuzzC tc;
        :{[d;limit;s;st;i]
            len:.tst.privateIndex[s;i;st,"/length";limit];
            .tst.privateVector[d;len;s;i;st]
        }[default;count values;seed;stream;] each til runs];
    if[1=count distinct values;
        :{[v;limit;s;st;i]
            len:.tst.privateIndex[s;i;st,"/length";limit];
            len#v
        }[first values;count values;seed;stream;] each til runs];
    { [vals;s;st;i] vals .tst.privateIndex[s;i;st;count vals] }[
        values;seed;stream;] each til runs
 };

pickFuzzSeeded:{[spec;runs;seed;stream]
    tc:type spec;
    if[-11h=tc;
        if[spec in key .tst.typeFuzzN;
            default:.tst.typeFuzzN spec;
            :.tst.privateScalar[default;seed;;stream] each til runs];
        :runs#spec];
    if[11h=tc;
        :{[vals;s;st;i] vals .tst.privateIndex[s;i;st;count vals]}[
            spec;seed;stream;] each til runs];
    if[(abs tc) within 100 104h;
        :{[fn;i] fn[]}[spec] each til runs];
    if[99h=tc;
        names:key spec;
        n:count names;
        columns:{[vals;r;s;name]
            .tst.pickFuzzSeeded[vals;r;s;.tst.toString name]
        }'[value spec;n#enlist runs;n#enlist seed;names];
        :flip names!columns];
    if[tc>=0h;:.tst.pickListFuzzSeeded[spec;runs;seed;stream]];
    runs#spec
 };

pickFuzz:{[x;runs]
    t: type x;

    / Symbol form - lookup type name
    if[-11h = t;
        if[x in key .tst.typeFuzzN;
            :.tst.genFuzzValues[.tst.typeFuzzN[x]; runs]
        ];
        / Unknown type name - return the symbol repeated
        :runs # x
    ];

    / Symbol list form - pick from list
    if[11h = t;
        :runs ? x
    ];

    / Function form - call to generate each value
    if[(abs t) within 100 104h;
        :{[f;i] f[]}[x] each til runs
    ];

    / Dictionary form - generate for each key
    if[99h = t;
        :flip .tst.pickFuzz[;runs] each x
    ];

    / List form - pick from list or generate
    if[t >= 0h;
        :.tst.pickListFuzz[x;runs]
    ];

    / Atom form - use as-is repeated
    runs # x
 };

/ Helper: generate fuzz values of a specific type
.tst.genFuzzValues:{[default;runs]
    t: type default;
    $[t = -1h; runs ? 01b;              / Boolean
      t = -2h; runs ? 0Ng;              / GUID
      t = -4h; runs ? 0x0 + til 256;    / Byte
      t = -5h; runs ? 32767h;           / Short
      t = -6h; runs ? 2000000000i;      / Int
      t = -7h; runs ? 9000000000000j;   / Long
      t = -8h; runs ? 1e10;             / Real
      t = -9h; runs ? 1e15;             / Float
      t = -10h; runs ? .Q.a;            / Char
      t = -11h; runs ? `a`b`c`d`e`f`g;  / Symbol
      runs # default]                   / Default: repeat
 };

pickListFuzz:{[x;runs]
  tc: abs type x;
  $[(count x) = 0;
   { [tc;len] len ? typeFuzzC[tc] }[tc] each runs ? fuzzListMaxLength;
   (1 = count distinct x) and null first x;
   { [tc;len] len ? typeFuzzC[tc] }[tc] each runs ? count x;
   1 = count distinct x;
   { [x;len] len ? x }[first x] each runs ? count x;
   runs ? x
   ]
 }

.tst.fuzzFailureClass:{[message]
  text:.tst.toString message;
  marker:"\n--- diff ---\n";
  positions:ss[text;marker];
  if[count positions;
    tail:((first positions)+count marker)_text;
    :first "\n" vs tail];
  if[text like "Error during fuzz run: *";:text];
  if[count ss[text;"expected it NOT to equal"];:"assertion:not-equal"];
  if[count ss[text;"expected it to be less than"];:"assertion:less-than"];
  if[count ss[text;"expected it to be greater than"];:"assertion:greater-than"];
  if[count ss[text;" to not be in "];:"assertion:not-in"];
  if[count ss[text;" to be within "];:"assertion:within"];
  if[count ss[text;" to be like "];:"assertion:like"];
  if[count ss[text;" to be in "];:"assertion:in"];
  if[(4#text)~"Got ";:"assertion:equal"];
  first "\n" vs text
 };

.tst.fuzzFailureSignature:{[result]
  failures:$[`fuzzFailures in key result;(),result`fuzzFailures;()];
  if[not count failures;:""];
  classes:.tst.fuzzFailureClass each failures;
  "fuzz-failure-v1/",string[count failures],"/",raze string md5 "|" sv classes
 };

.tst.shrinkLimits:{[props]
  steps:"j"$$[`shrinkSteps in key props;props`shrinkSteps;100];
  candidates:"j"$$[`shrinkCandidates in key props;props`shrinkCandidates;1000];
  timeMs:"f"$$[`shrinkTimeMs in key props;props`shrinkTimeMs;1000f];
  if[(steps<0) or candidates<0 or timeMs<0;
    '"property shrink limits must be non-negative"];
  `steps`candidates`timeMs!(steps;candidates;timeMs)
 };

.tst.shrinkElapsedMs:{[started]
  ("f"$.z.p-started)%1000000f
 };

/ Deterministic greedy walk over each node's ordered shrink candidates. Every
/ accepted child must fail with the same stable failure class as the original.
/ Three independent ceilings make pathological custom shrinkers safe in CI.
.tst.shrinkTree:{[code;generator;original;initial;limits]
  current:original;
  signature:.tst.fuzzFailureSignature initial;
  steps:0j;tested:0j;started:.z.p;termination:`minimal;done:0b;
  while[not done;
    if[steps>=limits`steps;termination:`stepLimit;done:1b];
    if[(not done) and tested>=limits`candidates;termination:`candidateLimit;done:1b];
    if[(not done) and .tst.shrinkElapsedMs[started]>=limits`timeMs;
      termination:`timeLimit;done:1b];
    if[not done;
      candidates:.resq.gen.shrinkCandidates[generator;current];
      if[not count candidates;termination:`minimal;done:1b];
    ];
    if[not done;
      accepted:0b;i:0j;
      while[(i<count candidates) and not accepted and not done;
        if[tested>=limits`candidates;termination:`candidateLimit;done:1b];
        if[(not done) and .tst.shrinkElapsedMs[started]>=limits`timeMs;
          termination:`timeLimit;done:1b];
        if[not done;
          candidateResult:.tst.fuzzRunCollector[code;candidates i];
          tested+:1;
          if[(count candidateResult`fuzzFailures) and
             signature~.tst.fuzzFailureSignature candidateResult;
            current:candidates i;steps+:1;accepted:1b];
          i+:1];
      ];
      if[(not done) and not accepted;termination:`minimal;done:1b];
    ];
  ];
  `original`minimal`steps`candidates`termination`failureSignature`durationMs!(
    original;current;steps;tested;termination;signature;.tst.shrinkElapsedMs started)
 };

/ Backward-compatible internal helper. New code should use the public
/ .resq.gen shrink protocol and .tst.shrinkTree telemetry.
shrink:{[code;typeCode;val]
  generator:$[(type val)>=0h;
    element:$[(abs type val) in .tst.typeCodes;
      .tst.typeNames .tst.typeCodes?abs type val;`long];
    .resq.gen.list[.resq.gen.typed element;0;count val];
    .resq.gen.adapt val];
  initial:.tst.fuzzRunCollector[code;val];
  (.tst.shrinkTree[code;generator;val;initial;
    `steps`candidates`timeMs!(100j;1000j;1000f)])`minimal
 }

runners[`fuzz]:{[expec]
  origState: .tst.assertState;
  origSuppress: .tst.suppressAssertionDiff;
  / Quiet per-iteration FAILURE DIFFs; the shrunk repro printed below is the
  / one diagnostic the user actually needs.
  .tst.suppressAssertionDiff: 1b;
  props:$[`props in key expec;expec`props;()!()];
  defaultSeed:.tst.privateWord[
      .tst.toString[.tst.currentContext`file],"/",
      .tst.toString[.tst.currentContext`suite],"/",
      .tst.toString[.tst.currentContext`test];
      0;`property];
  seed:"j"$$[`seed in key props;props`seed;defaultSeed];
  props[`seed]:seed;
  expec[`props]:props;
  expec[`seed]:seed;
  generator:.resq.gen.adapt expec`vars;
  expec[`generatorProtocol]:.resq.gen.PROTOCOL;
  fuzzValues:.resq.gen.sampleList[generator;expec`runs;seed;"root"];
  fuzzResults:{[code;input;idx]
    result:.tst.fuzzRunCollector[code;input];
    result[`fuzzIndex]:idx;
    result
  }'[expec[`runs]#enlist expec`code;fuzzValues;til expec`runs];
  fails: select from fuzzResults where 0 < count each fuzzFailures;

  expec[`shrunkFailure]: (::);
  expec[`originalFailure]: (::);
  expec[`replayToken]:"";
  expec[`replayTokens]:();
  expec[`shrinkSteps]:0j;
  expec[`shrinkCandidates]:0j;
  expec[`shrinkTermination]:`notRun;
  expec[`shrinkFailureSignature]:"";
  expec[`shrinkDurationMs]:0f;
  if[0<count fails;
    firstFailResult:first fails;
    firstFail:firstFailResult`failedFuzz;
    tokens:.resq.gen.replayToken[seed;] each fails`fuzzIndex;
    expec[`originalFailure]:firstFail;
    expec[`replayToken]:first tokens;
    expec[`replayTokens]:tokens;
    -1 "  Fuzz failure detected. Attempting to shrink...";
    -1 "  Replay: ",first tokens;
    shrinkInfo:.tst.shrinkTree[
      expec`code;generator;firstFail;firstFailResult;.tst.shrinkLimits props];
    -1 "  Original failing input: ",.Q.s1 shrinkInfo`original;
    -1 "  Minimal reproducible input: ",.Q.s1 shrinkInfo`minimal;
    -1 "  Shrink: ",string[shrinkInfo`steps]," accepted / ",
       string[shrinkInfo`candidates]," tried (",string[shrinkInfo`termination],")";
    expec[`shrunkFailure]:shrinkInfo`minimal;
    expec[`shrinkSteps]:shrinkInfo`steps;
    expec[`shrinkCandidates]:shrinkInfo`candidates;
    expec[`shrinkTermination]:shrinkInfo`termination;
    expec[`shrinkFailureSignature]:shrinkInfo`failureSignature;
    expec[`shrinkDurationMs]:shrinkInfo`durationMs;
  ];

  expec[`failedFuzz]: exec failedFuzz from fuzzResults where 0 < count each fuzzFailures;
  expec[`fuzzFailureMessages]: exec fuzzFailures from fuzzResults where 0 < count each fuzzFailures;

  / Assertion totals describe executions, not assertion sites. Every generated
  / case owns a fresh assertState, so add those per-case counters. Shrink probes
  / are deliberately absent from fuzzResults and therefore remain diagnostic
  / work rather than inflating the public test/run assertion count.
  assertsRun:$[not count fuzzResults;0;sum fuzzResults[`assertsRun]];
  / Strict '>' so the default maxFailRate 0f means "no failures tolerated":
  / failRate 0 does NOT exceed 0, so an all-passing holds block passes.
  $[(expec[`failRate]:(count expec`failedFuzz)%expec`runs) > expec`maxFailRate;
   expec[`failures`result`assertsRun]:(enlist "Over max failure rate. Shrunk: ", .Q.s1 expec`shrunkFailure;`fuzzFail;assertsRun);
   expec[`failures`result`assertsRun]:(();`pass;assertsRun)];
  .tst.assertState: origState;
  .tst.suppressAssertionDiff: origSuppress;
  expec
 }

fuzzRunCollector:{[code;fuzz]
 origState:.tst.assertState;
 .tst.assertState:.tst.defaultAssertState;
 @[code; fuzz; { [e] .tst.assertState.failures,: enlist "Error during fuzz run: ",e }];
 result:$[0<count .tst.assertState.failures;
   `failedFuzz`fuzzFailures`assertsRun!(fuzz;.tst.assertState.failures;.tst.assertState.assertsRun);
   `failedFuzz`fuzzFailures`assertsRun!(fuzz;();.tst.assertState.assertsRun)];
 .tst.assertState:origState;
 result
 }
