\d .tst

/ Run one parametrized case: apply func to args (named by pNames), converting
/ an assertion failure or signal into an error tagged with the parameter values.
runParamCase:{[pNames;args;func]
    params: ", " sv {(.tst.toString x),"=",(-3!y)} ./: flip (pNames; args);
    errHandler: {[params;err] 'err, " (Params: ", params, ")"}[params];
    oldFailList: .tst.assertState.failures;
    @[func .; args; errHandler];
    if[(count .tst.assertState.failures) > count oldFailList;
        .tst.assertState.failures: oldFailList;
        '"Assertion failed (Params: ", params, ")"
    ];
 };

/ Parametrized Test Runner
/ @param data (table) The scenarios to test. Columns must match function arguments.
/ @param func (function) The test logic to execute for each row.
forall:{[data;func]
    if[not 98h=type data; '"forall expects a table as first argument"];
    pNames: cols data;
    i:0;
    do[count data;
        .tst.runParamCase[pNames; value data i; func];
        i+:1;
    ];
    1b
 };

/ Overflow-checked total case count. Empty value sets yield zero cases
/ (matching the historical cross-product behavior).
paramCaseTotal:{[counts]
    if[any 0 = counts; :0j];
    {[total;n]
        if[total > 9223372036854775806 div n;
            '"parametrize Cartesian product cardinality overflows long"];
        total * n
    } over 1j, counts
 };

/ Parametrize: Auto-generate test cases from value lists (Cartesian product)
/ @param paramDict (dict) Dictionary of param names to value lists. e.g. `a`b!(1 2; 10 20)
/ @param func (function) The test logic to execute for each combination
/ @return (boolean) 1b if all tests pass
parametrize:{[paramDict;func]
    / Handle table/keyed input (common when single param)
    pd: $[
        99h = type paramDict; paramDict;                    / dict
        98h = type paramDict; flip paramDict;               / table
        (type paramDict) in -20 20h;                        / single-key form (`x!1 2 3)
            (enlist key paramDict)! enlist value paramDict;
        paramDict
    ];
    if[not 99h = type pd;
        '"parametrize expects a dictionary (e.g., `a`b!(1 2 3; 10 20 30)) or table as first argument"
    ];

    pNames: key pd;
    pValues: value pd;
    / Ensure single-key dicts are treated as lists
    if[-11h = type pNames;
        pNames: enlist pNames;
        pValues: enlist pValues;
    ];

    / Ensure all values are lists
    pValues: {$[0 > type x; enlist x; x]} each pValues;

    counts: "j"$count each pValues;
    total: .tst.paramCaseTotal counts;
    if[@[get; `.utl.DEBUG; 0b]; -1 "DEBUG: parametrize data count ", string total];

    / Stream each combination by mixed-radix decode of the case index (the
    / final parameter varies fastest, matching the old cross-product order).
    / Nothing is materialized: the old `cross over` built every intermediate
    / product in memory and could exhaust the heap on a handful of parameters.
    i: 0;
    while[i < total;
        .tst.runParamCase[pNames; pValues @' counts vs i; func];
        i+:1;
    ];
    1b
 };

\d .
