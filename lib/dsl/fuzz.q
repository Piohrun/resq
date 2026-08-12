\d .tst
fuzzListMaxLength:100

typeNames: `boolean`guid`byte`short`int`long`real`float`char`symbol`timestamp`month`date`datetime`timespan`minute`second`time
typeCodes: 1 2 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19h
typeDefaults:(0b;0Ng;0x00;0h;0;0j;0e;0f;" ";`symbol;0p;2000.01m;2000.01.01;2000.01.01T00:00:00.000;0D00:00:00.000000000;00:00;00:00:00;00:00:00.000)
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
      tc=-4h;"x"$word mod 256;
      tc=-5h;"h"$word mod 32767;
      tc=-6h;"i"$word mod 2000000000;
      tc=-7h;word;
      tc=-8h;"e"$word%4294967296f;
      tc=-9h;word%4294967296f;
      tc=-10h;.Q.a .tst.privateIndex[seed;counter;stream;count .Q.a];
      tc=-11h;`a`b`c`d`e`f`g .tst.privateIndex[seed;counter;stream;7];
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

shrink:{[code;typeCode;val]
  if[(t:type val) within 0 19h;
    if[1 >= count val; :val];
    v1: (floor (count val)%2) # val;
    v2: (floor (count val)%2) _ val;
    if[0<count (fuzzRunCollector[code;v1])`fuzzFailures; :shrink[code;typeCode;v1]];
    if[0<count (fuzzRunCollector[code;v2])`fuzzFailures; :shrink[code;typeCode;v2]];
    :val;
  ];
  val
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
  fuzzValues:.tst.pickFuzzSeeded[expec`vars;expec`runs;seed;"root"];
  fuzzResults:fuzzRunCollector[expec`code] each fuzzValues;
  fails: select from fuzzResults where 0 < count each fuzzFailures;

  expec[`shrunkFailure]: (::);
  if[0<count fails;
    firstFail: (first fails)`failedFuzz;
    -1 "  Fuzz failure detected. Attempting to shrink...";
    shrunk: shrink[expec`code; abs type firstFail; firstFail];
    -1 "  Minimal Reproducible Case: ", .Q.s1 shrunk;
    expec[`shrunkFailure]: shrunk;
  ];

  expec[`failedFuzz]: exec failedFuzz from fuzzResults where 0 < count each fuzzFailures;
  expec[`fuzzFailureMessages]: exec fuzzFailures from fuzzResults where 0 < count each fuzzFailures;

  assertsRun:$[not count fuzzResults;0;max fuzzResults[`assertsRun]];
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
 .tst.assertState:.tst.defaultAssertState;
 @[code; fuzz; { [e] .tst.assertState.failures,: enlist "Error during fuzz run: ",e }];
 $[0<count .tst.assertState.failures;
   `failedFuzz`fuzzFailures`assertsRun!(fuzz;.tst.assertState.failures;.tst.assertState.assertsRun);
   `failedFuzz`fuzzFailures`assertsRun!(fuzz;();.tst.assertState.assertsRun)]
 }
