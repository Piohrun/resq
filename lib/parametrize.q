\d .tst

/ Parametrized Test Runner
/ @param data (table) The scenarios to test. Columns must match function arguments.
/ @param func (function) The test logic to execute for each row.
forall:{[data;func]
    if[not 98h=type data; '"forall expects a table as first argument"];
    
    i:0;
    cnt: count data;
    
    do[cnt;
        row: data[i];
        
        / Precompute params for error handler
        params: ", " sv {(.tst.toString x),"=",(-3!y)} ./: flip (key row; value row);
        errHandler: {[params;err] 'err, " (Params: ", params, ")"}[params];

        oldFailList: .tst.assertState.failures;
        @[func .; value row; errHandler];
        if[count .tst.assertState.failures > count oldFailList;
            .tst.assertState.failures: oldFailList;
            '"Assertion failed (Params: ", params, ")"
        ];
        
        i+:1;
    ];
    
    1b
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
    
    / Compute Cartesian product
    allCombos: $[1 = count pValues;
        first pValues;
        {x cross y} over pValues
    ];
    
    / allCombos is now a list of lists, each of length count pNames
    / Convert to table
    data: $[1 = count pNames;
        flip pNames ! enlist allCombos;
        flip pNames ! flip allCombos
    ];
    
    / Pass to existing forall
    if[@[get; `.utl.DEBUG; 0b]; -1 "DEBUG: parametrize data count ", string count data];
    forall[data; func]
 };

\d .
