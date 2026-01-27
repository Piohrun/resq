\d .tst
fuzzListMaxLength:100

typeNames: `boolean`guid`byte`short`int`long`real`float`char`symbol`timestamp`month`date`datetime`timespan`minute`second`time
typeCodes: 1 2 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19h
typeDefaults:(0b;0Ng;0x00;0h;0;0j;0e;0f;" ";`symbol;0p;2000.01m;2000.01.01;2000.01.01T00:00:00.000;0D00:00:00.000000000;00:00;00:00:00;00:00:00.000)
typeFuzzN: typeNames!typeDefaults
typeFuzzC: typeCodes!typeDefaults

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
  fuzzResults:fuzzRunCollector[expec`code] each pickFuzz[expec`vars;expec`runs];
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
  $[(expec[`failRate]:(count expec`failedFuzz)%expec`runs) >= expec`maxFailRate; 
   expec[`failures`result`assertsRun]:(enlist "Over max failure rate. Shrunk: ", .Q.s1 expec`shrunkFailure;`fuzzFail;assertsRun);
   expec[`failures`result`assertsRun]:(();`pass;assertsRun)];
  .tst.assertState: origState;
  expec
 }

fuzzRunCollector:{[code;fuzz]
 .tst.assertState:.tst.defaultAssertState;
 @[code; fuzz; { [e] .tst.assertState.failures,: enlist "Error during fuzz run: ",e }];
 $[0<count .tst.assertState.failures;
   `failedFuzz`fuzzFailures`assertsRun!(fuzz;.tst.assertState.failures;.tst.assertState.assertsRun);
   `failedFuzz`fuzzFailures`assertsRun!(fuzz;();.tst.assertState.assertsRun)]
 }
