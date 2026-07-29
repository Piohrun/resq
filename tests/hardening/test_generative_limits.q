.tst.genhard.expec:{[runs;vars;rate;code]
    expec:.tst.internals.fuzzObj;
    expec[`runs]:runs;
    expec[`vars]:vars;
    expec[`maxFailRate]:rate;
    expec[`code]:code;
    expec
 };

.tst.genhard.captureCall:{[func;args]
    .[{[f;a] (`ok;f . a)};(func;args);{[e] (`error;e)}]
 };

.tst.genhard.capture:{[code]
    @[{[f] (`ok;f[])};code;{[e] (`error;e)}]
 };

.tst.desc["Bounded fuzz execution"]{
    should["cap retained failures without changing totals or rate"]{
        `.tst.output.fuzzLimit mock 2;
        expec:.tst.genhard.expec[5;42;0f;{[x] 1 musteq 2}];
        result:.tst.runners[`fuzz] expec;
        result[`result] musteq `fuzzFail;
        result[`fuzzFailureCount] musteq 5;
        result[`failRate] musteq 1f;
        count[result`failedFuzz] musteq 2;
        count[result`fuzzFailureMessages] musteq 2;
        result[`assertsRun] musteq 5;
    };

    should["retain no per-case diagnostics when fuzzLimit is zero"]{
        `.tst.output.fuzzLimit mock 0;
        result:.tst.runners[`fuzz]
            .tst.genhard.expec[3;42;0f;{[x] 1 musteq 2}];
        result[`fuzzFailureCount] musteq 3;
        result[`failRate] musteq 1f;
        count[result`failedFuzz] musteq 0;
        count[result`fuzzFailureMessages] musteq 0;
    };

    should["bound diagnostics by both runs and a hard retention cap"]{
        `.tst.output.fuzzLimit mock 1000000;
        `.tst.fuzzDiagnosticHardLimit mock 2;
        result:.tst.runners[`fuzz]
            .tst.genhard.expec[3;42;0f;{[x] 1 musteq 2}];
        count[result`failedFuzz] musteq 2;
        count[result`fuzzFailureMessages] musteq 2;

        `.tst.fuzzDiagnosticHardLimit mock 100;
        result:.tst.runners[`fuzz]
            .tst.genhard.expec[3;42;0f;{[x] 1 musteq 2}];
        count[result`failedFuzz] musteq 3;
        count[result`fuzzFailureMessages] musteq 3;
    };

    should["allow assertion failures at the inclusive maximum rate"]{
        result:.tst.runners[`fuzz]
            .tst.genhard.expec[2;42;1f;{[x] 1 musteq 2}];
        result[`result] musteq `pass;
        result[`fuzzFailureCount] musteq 2;
        result[`failRate] musteq 1f;
        result[`assertsRun] musteq 2;
    };

    should["reject a failure rate exactly above a near-equal threshold"]{
        `.tst.genhard.calls mock 0;
        result:.tst.runners[`fuzz]
            .tst.genhard.expec[2;42;0.5f-1e-15;{[x]
                .tst.genhard.calls+:1;
                if[1=.tst.genhard.calls;1 musteq 2];
            }];
        result[`result] musteq `fuzzFail;
        result[`fuzzFailureCount] musteq 1;
        result[`failRate] musteq 0.5f;
    };

    should["bound retained messages within each failing case"]{
        `.tst.output.fuzzLimit mock 1;
        `.tst.fuzzFailureItemLimit mock 2;
        result:.tst.runners[`fuzz]
            .tst.genhard.expec[1;42;0f;{[x]
                1 musteq 2;
                3 musteq 4;
                5 musteq 6;
            }];
        messages:first result`fuzzFailureMessages;
        count[messages] musteq 3;
        last[messages] mustlike "*more failure(s)*";
        result[`assertsRun] musteq 3;
    };

    should["sum assertion counts across every iteration"]{
        result:.tst.runners[`fuzz]
            .tst.genhard.expec[4;42;0f;{[x]
                x musteq 42;
                x mustgt 0;
            }];
        result[`result] musteq `pass;
        result[`assertsRun] musteq 8;
        result[`fuzzFailureCount] musteq 0;
    };

    should["reject invalid run and failure-rate options contextually"]{
        mustthrow["*must be positive"]{
            .tst.runners[`fuzz]
                .tst.genhard.expec[0;42;0f;{[x]}]
        };
        mustthrow["*integer scalar"]{
            .tst.runners[`fuzz]
                .tst.genhard.expec[1.5;42;0f;{[x]}]
        };
        mustthrow["*must be finite"]{
            .tst.runners[`fuzz]
                .tst.genhard.expec[0N;42;0f;{[x]}]
        };
        mustthrow["*must be finite"]{
            .tst.runners[`fuzz]
                .tst.genhard.expec[0W;42;0f;{[x]}]
        };
        `.tst.fuzzRunHardLimit mock 3;
        mustthrow["*exceeds safety limit 3"]{
            .tst.runners[`fuzz]
                .tst.genhard.expec[4;42;0f;{[x]}]
        };
        mustthrow["*between 0 and 1"]{
            .tst.runners[`fuzz]
                .tst.genhard.expec[1;42;-0.1;{[x]}]
        };
        mustthrow["*between 0 and 1"]{
            .tst.runners[`fuzz]
                .tst.genhard.expec[1;42;-1e-20;{[x]}]
        };
        mustthrow["*between 0 and 1"]{
            .tst.runners[`fuzz]
                .tst.genhard.expec[1;42;1.1;{[x]}]
        };
        mustthrow["*between 0 and 1"]{
            .tst.runners[`fuzz]
                .tst.genhard.expec[1;42;1f+1e-15;{[x]}]
        };
        mustthrow["*must be finite"]{
            .tst.runners[`fuzz]
                .tst.genhard.expec[1;42;0n;{[x]}]
        };
        mustthrow["*must be finite"]{
            .tst.runners[`fuzz]
                .tst.genhard.expec[1;42;0w;{[x]}]
        };
        mustthrow["*numeric scalar"]{
            .tst.runners[`fuzz]
                .tst.genhard.expec[1;42;"bad";{[x]}]
        };
    };

    should["reject empty and malformed generator shapes with context"]{
        mustthrow["*must not be empty"]{
            .tst.pickFuzz[`symbol$();1]
        };
        mustthrow["*must not be empty"]{
            .tst.pickFuzz[();1]
        };
        mustthrow["*must not be empty"]{
            .tst.validateFuzzVars[()!();"vars"]
        };
        mustthrow["*dictionary keys must be symbols*"]{
            .tst.validateFuzzVars[(enlist "bad")!enlist `int;"vars"]
        };
        literal:.tst.pickFuzz[`notAType;3];
        literal mustmatch 3#`notAType;
    };

    should["bound typed symbol and general generator choices before work"]{
        `.tst.fuzzGeneratorChoiceHardLimit mock 3;
        `.tst.genhard.generatorCalls mock 0;
        `.tst.genhard.calls mock 0;
        savedState:.tst.assertState;
        savedSuppress:.tst.suppressAssertionDiff;
        property:{[x] .tst.genhard.calls+:1};

        typed:.tst.genhard.captureCall[
            .tst.runners`fuzz;
            enlist .tst.genhard.expec[1;1 2 3 4;0f;property]];
        symbols:.tst.genhard.captureCall[
            .tst.runners`fuzz;
            enlist .tst.genhard.expec[1;`a`b`c`d;0f;property]];
        general:.tst.genhard.captureCall[
            .tst.runners`fuzz;
            enlist .tst.genhard.expec[1;(1;`a;"x";0b);0f;property]];
        nested:.tst.genhard.captureCall[
            .tst.runners`fuzz;
            enlist .tst.genhard.expec[
                1;
                `choices`generated!(
                    1 2 3 4;
                    {.tst.genhard.generatorCalls+:1;42});
                0f;
                property]];

        stateRestored:savedState~.tst.assertState;
        suppressRestored:savedSuppress~.tst.suppressAssertionDiff;
        (first each (typed;symbols;general;nested))
            mustmatch 4#`error;
        must[all (last each (typed;symbols;general;nested))
                like "*choice safety limit 3*";
            "all oversized choice shapes must fail validation"];
        .tst.genhard.generatorCalls musteq 0;
        .tst.genhard.calls musteq 0;
        stateRestored musteq 1b;
        suppressRestored musteq 1b;
    };

    should["bound nested generator validation by depth and node count"]{
        nested:(enlist `a)!enlist
            ((enlist `b)!enlist
                ((enlist `c)!enlist `int));
        `.tst.fuzzGeneratorDepthLimit mock 1;
        got:.tst.genhard.captureCall[
            .tst.validateFuzzVars;(nested;"vars")];
        (first got) musteq `error;
        last[got] mustlike "*depth limit*";

        `.tst.fuzzGeneratorDepthLimit mock 16;
        `.tst.fuzzGeneratorNodeLimit mock 2;
        wide:`a`b!(`int;`long);
        got:.tst.genhard.captureCall[
            .tst.validateFuzzVars;(wide;"vars")];
        (first got) musteq `error;
        last[got] mustlike "*node limit*";
    };

    should["bound direct bulk generation and random list lengths"]{
        `.tst.pickFuzzBulkRunLimit mock 2;
        mustthrow["*bulk safety limit*"]{
            .tst.pickFuzz[`int;3]
        };
        `.tst.pickFuzzBulkNodeLimit mock 100;
        mustthrow["*bulk safety budget 100"]{
            .tst.pickFuzz[`int$();2]
        };

        `.tst.pickFuzzBulkNodeLimit mock 1000000;
        `.tst.fuzzListLengthHardLimit mock 3;
        `.tst.fuzzListMaxLength mock 100;
        lists:.tst.pickFuzz[`float$();2];
        must[all (count each lists)<3;
            "generated list lengths must honor the hard cap"];
    };

    should["reject oversized generated values before property invocation"]{
        `.tst.genhard.calls mock 0;
        `.tst.fuzzGeneratedValueHardLimit mock 8;

        vectorResult:.tst.runners[`fuzz]
            .tst.genhard.expec[1;{til 9};1f;{[x]
                .tst.genhard.calls+:1;
            }];
        vectorResult[`result] musteq `fuzzFail;
        first[vectorResult`failures] mustlike "*value safety limit 8*";

        tableResult:.tst.runners[`fuzz]
            .tst.genhard.expec[1;{([]a:til 3;b:til 3;c:til 3)};1f;{[x]
                .tst.genhard.calls+:1;
            }];
        tableResult[`result] musteq `fuzzFail;
        first[tableResult`failures] mustlike "*table cell count*";
        .tst.genhard.calls musteq 0;
    };

    should["reject wide and deep generated nesting before invocation"]{
        `.tst.genhard.calls mock 0;
        `.tst.fuzzGeneratedNodeHardLimit mock 4;
        wideResult:.tst.runners[`fuzz]
            .tst.genhard.expec[1;{(1;`a;"x";0b)};1f;{[x]
                .tst.genhard.calls+:1;
            }];
        wideResult[`result] musteq `fuzzFail;
        first[wideResult`failures] mustlike "*structural node safety limit 4*";

        .tst.fuzzGeneratedNodeHardLimit:10000;
        `.tst.fuzzGeneratedDepthHardLimit mock 1;
        deep:(enlist `a)!enlist
            ((enlist `b)!enlist
                ((enlist `c)!enlist 1));
        deepResult:.tst.runners[`fuzz]
            .tst.genhard.expec[1;deep;1f;{[x]
                .tst.genhard.calls+:1;
            }];
        deepResult[`result] musteq `fuzzFail;
        first[deepResult`failures] mustlike "*value depth safety limit*";
        .tst.genhard.calls musteq 0;
    };

    should["force generator exceptions even at maxFailRate one and restore state"]{
        `.tst.output.fuzzLimit mock 2;
        savedState:.tst.assertState;
        savedSuppress:.tst.suppressAssertionDiff;
        result:.tst.runners[`fuzz]
            .tst.genhard.expec[2;{'"gen-root"};1f;{[x]}];
        stateRestored:savedState~.tst.assertState;
        suppressRestored:savedSuppress~.tst.suppressAssertionDiff;
        result[`result] musteq `fuzzFail;
        result[`fuzzFailureCount] musteq 2;
        first[result`failures] mustlike "*gen-root*";
        stateRestored musteq 1b;
        suppressRestored musteq 1b;
    };

    should["force generator assertion-state corruption and restore state"]{
        savedState:.tst.assertState;
        savedSuppress:.tst.suppressAssertionDiff;
        result:.tst.runners[`fuzz]
            .tst.genhard.expec[1;{
                .tst.assertState:`corrupt;
                42
            };1f;{[x]}];
        stateRestored:savedState~.tst.assertState;
        suppressRestored:savedSuppress~.tst.suppressAssertionDiff;
        result[`result] musteq `fuzzFail;
        first[result`failures] mustlike
            "*assertion state modified during fuzz generation*";
        stateRestored musteq 1b;
        suppressRestored musteq 1b;
    };

    should["force property exceptions even at maxFailRate one and restore state"]{
        `.tst.output.fuzzLimit mock 2;
        savedState:.tst.assertState;
        savedSuppress:.tst.suppressAssertionDiff;
        result:.tst.runners[`fuzz]
            .tst.genhard.expec[2;42;1f;{[x] '"property-root"}];
        stateRestored:savedState~.tst.assertState;
        suppressRestored:savedSuppress~.tst.suppressAssertionDiff;
        result[`result] musteq `fuzzFail;
        result[`fuzzFailureCount] musteq 2;
        first[result`failures] mustlike "*property-root*";
        stateRestored musteq 1b;
        suppressRestored musteq 1b;
    };

    should["force assertion-state corruption even at maxFailRate one"]{
        savedState:.tst.assertState;
        result:.tst.runners[`fuzz]
            .tst.genhard.expec[1;42;1f;{[x]
                .tst.assertState:`corrupt;
            }];
        stateRestored:savedState~.tst.assertState;
        result[`result] musteq `fuzzFail;
        first[result`failures] mustlike "*assertion state became invalid";
        stateRestored musteq 1b;
    };

    should["force and bound oversized injected fuzz failure state"]{
        `.tst.output.fuzzLimit mock 1;
        `.tst.fuzzStateFailureHardLimit mock 3;
        savedState:.tst.assertState;
        savedSuppress:.tst.suppressAssertionDiff;
        result:.tst.runners[`fuzz]
            .tst.genhard.expec[1;42;1f;{[x]
                .tst.assertState.failures:100#enlist "hostile";
            }];
        stateRestored:savedState~.tst.assertState;
        suppressRestored:savedSuppress~.tst.suppressAssertionDiff;
        result[`result] musteq `fuzzFail;
        first[result`failures] mustlike "*failure state exceeded safety limit*";
        count[first result`fuzzFailureMessages] musteq 3;
        stateRestored musteq 1b;
        suppressRestored musteq 1b;
    };

    should["force shrink exceptions and exercise dyadic protected apply"]{
        `.tst.shrink mock {[code;typeCode;val] '"shrink-root"};
        savedState:.tst.assertState;
        result:.tst.runners[`fuzz]
            .tst.genhard.expec[1;42;1f;{[x] 1 musteq 2}];
        stateRestored:savedState~.tst.assertState;
        result[`result] musteq `fuzzFail;
        first[result`failures] mustlike "*shrink-root*";
        stateRestored musteq 1b;
    };

    should["shrink deterministically within the configured step budget"]{
        `.tst.fuzzShrinkStepLimit mock 2;
        `.tst.fuzzShrinkTimeLimitMs mock 10000;
        `.tst.genhard.calls mock 0;
        expec:.tst.genhard.expec[1;{til 64};0f;{[x]
            .tst.genhard.calls+:1;
            (count x) mustlt 2;
        }];
        firstRun:.tst.runners[`fuzz] expec;
        firstCalls:.tst.genhard.calls;
        .tst.genhard.calls:0;
        secondRun:.tst.runners[`fuzz] expec;
        secondCalls:.tst.genhard.calls;
        firstRun[`shrunkFailure] mustmatch secondRun`shrunkFailure;
        count[firstRun`shrunkFailure] musteq 16;
        firstCalls musteq 3;
        secondCalls musteq 3;
    };

    should["render repros from bounded prefixes without calling truncate"]{
        `.tst.fuzzRenderLimit mock 64;
        `.tst.truncate mock {[x;n] '"truncate-must-not-run"};
        text:.tst.fuzzFailureText til 1000;
        must[(count text)<=64;"fuzz rendering must honor its cap"];
        text mustlike "*more*";
        result:.tst.runners[`fuzz]
            .tst.genhard.expec[1;til 1000;0f;{[x] 1 musteq 2}];
        must[(count first result`failures)<=64;
            "final fuzz failure text must honor its cap"];
        boundedError:.tst.fuzzErrorText[
            "Error during fuzz run: ";"FUZZ-ROOT-",10000#"x"];
        must[(count boundedError)<=64;
            "trapped fuzz errors must honor their cap"];
        boundedError mustlike "FUZZ-ROOT-*";
        tiny:.tst.boundedValueText[(enlist `a)!enlist til 1000;5];
        must[(count tiny)<=5;"tiny fuzz render cap must hold"];
        longSymbol:`$10000#"x";
        .tst.boundedValueText[longSymbol;64] musteq "<symbol>";
        .tst.boundedValueText[2#longSymbol;64]
            musteq "<symbol list count=2>";
    };

    should["clamp poisoned and raised fuzz limits to literal ceilings"]{
        huge:9223372036854775806;
        `.tst.fuzzRunHardLimit mock 0W;
        .tst.fuzzRunLimit[] musteq 1000000;
        .tst.fuzzRunHardLimit:huge;
        .tst.fuzzRunLimit[] musteq 1000000;

        `.tst.pickFuzzBulkRunLimit mock huge;
        `.tst.pickFuzzBulkNodeLimit mock huge;
        `.tst.fuzzListLengthHardLimit mock huge;
        `.tst.fuzzListMaxLength mock huge;
        `.tst.fuzzGeneratorDepthLimit mock huge;
        `.tst.fuzzGeneratorNodeLimit mock huge;
        `.tst.fuzzShrinkStepLimit mock huge;
        `.tst.fuzzShrinkTimeLimitMs mock huge;
        `.tst.fuzzRenderLimit mock huge;
        `.tst.fuzzDiagnosticHardLimit mock huge;
        `.tst.fuzzFailureItemLimit mock huge;
        `.tst.fuzzAssertionHardLimit mock huge;
        `.tst.boundedRenderItemLimit mock huge;
        `.tst.boundedRenderDepthLimit mock huge;
        `.tst.fuzzGeneratedValueHardLimit mock huge;
        `.tst.fuzzGeneratedNodeHardLimit mock huge;
        `.tst.fuzzGeneratedDepthHardLimit mock huge;
        `.tst.fuzzGeneratorChoiceHardLimit mock huge;
        `.tst.fuzzStateFailureHardLimit mock huge;

        .tst.pickFuzzRunLimit[] musteq 10000;
        .tst.pickFuzzNodeLimit[] musteq 1000000;
        .tst.fuzzListHardLimit[] musteq 10000;
        .tst.fuzzListLengthLimit[] musteq 10000;
        .tst.fuzzGeneratorDepth[] musteq 16;
        .tst.fuzzGeneratorNodes[] musteq 1024;
        .tst.fuzzShrinkSteps[] musteq 64;
        .tst.fuzzShrinkMillis[] musteq 1000;
        .tst.fuzzReproLimit[] musteq 2048;
        .tst.fuzzDiagnosticCap[] musteq 1000;
        .tst.fuzzFailureItems[] musteq 16;
        .tst.fuzzAssertionLimit[] musteq 1000000;
        .tst.boundedRenderItems[] musteq 16;
        .tst.boundedRenderDepth[] musteq 4;
        .tst.fuzzGeneratedValueLimit[] musteq 10000;
        .tst.fuzzGeneratedNodeLimit[] musteq 10000;
        .tst.fuzzGeneratedDepthLimit[] musteq 16;
        .tst.fuzzGeneratorChoiceLimit[] musteq 10000;
        .tst.fuzzStateFailureLimit[] musteq 1000;
    };
 };

.tst.desc["Bounded parametrized execution"]{
    should["preserve exact one two and three parameter product order"]{
        `.tst.genhard.results mock ();
        .tst.parametrize[(enlist `x)!enlist 1 2 3;{[x]
            .tst.genhard.results,:x;
        }];
        .tst.genhard.results mustmatch 1 2 3;

        .tst.genhard.results:();
        .tst.parametrize[`a`b!(1 2;10 20);{[a;b]
            .tst.genhard.results,:enlist (a;b);
        }];
        .tst.genhard.results mustmatch
            (1 10;1 20;2 10;2 20);

        .tst.genhard.results:();
        .tst.parametrize[`a`b`c!(1 2;10 20;100 200);{[a;b;c]
            .tst.genhard.results,:enlist (a;b;c);
        }];
        .tst.genhard.results mustmatch
            (1 10 100;1 10 200;1 20 100;1 20 200;
             2 10 100;2 10 200;2 20 100;2 20 200);
    };

    should["reject empty inputs and invalid parameter names"]{
        mustthrow["*at least one row*"]{
            .tst.forall[([]x:`long$());{[x]}]
        };
        mustthrow["*must not be empty*"]{
            .tst.parametrize[
                (enlist `x)!enlist `long$();{[x]}]
        };
        mustthrow["*at least one parameter*"]{
            .tst.parametrize[()!();{}]
        };
        mustthrow["*must be unique*"]{
            .tst.parametrize[
                `x`x!(enlist 1;enlist 2);{[x;y]}]
        };
        mustthrow["*names must be symbols*"]{
            .tst.parametrize[
                (enlist "x")!enlist 1 2;{[x]}]
        };
        mustthrow["*must not be null*"]{
            .tst.parametrize[
                (enlist `)!enlist 1 2;{[x]}]
        };
        mustthrow["*control characters*"]{
            .tst.parametrize[
                (enlist `$"bad\nname")!enlist 1 2;{[x]}]
        };
        `.tst.parametrizeNameLengthLimit mock 8;
        mustthrow["*length limit*"]{
            .tst.parametrize[
                (enlist `$"123456789")!enlist 1 2;{[x]}]
        };
    };

    should["reject non-functions and incompatible arity before execution"]{
        mustthrow["*callable function*"]{
            .tst.parametrize[(enlist `x)!enlist 1 2;42]
        };
        mustthrow["*does not match 1 parameter(s)"]{
            .tst.parametrize[
                (enlist `x)!enlist 1 2;{[x;y]}]
        };
        mustthrow["*does not match 2 parameter(s)"]{
            .tst.forall[([]x:1 2;y:3 4);{[x]}]
        };
        .tst.parametrize[`x`y!(1 2;10 20);+]
            musteq 1b;
    };

    should["enforce product row and parameter caps before invocation"]{
        `.tst.parametrizeCaseHardLimit mock 3;
        `.tst.genhard.calls mock 0;
        got:.tst.genhard.capture {
            .tst.parametrize[`x`y!(1 2;10 20);{[x;y]
                .tst.genhard.calls+:1;
            }]
        };
        (first got) musteq `error;
        last[got] mustlike "*safety limit*";
        .tst.genhard.calls musteq 0;

        got:.tst.genhard.capture {
            .tst.forall[([]x:1 2 3 4);{[x]
                .tst.genhard.calls+:1;
            }]
        };
        (first got) musteq `error;
        last[got] mustlike "*row count exceeds safety limit 3";
        .tst.genhard.calls musteq 0;

        `.tst.parametrizeCaseHardLimit mock 100;
        `.tst.parametrizeParamHardLimit mock 2;
        got:.tst.genhard.capture {
            .tst.parametrize[
                `a`b`c!(enlist 1;enlist 2;enlist 3);
                {[a;b;c] .tst.genhard.calls+:1}]
        };
        (first got) musteq `error;
        last[got] mustlike "*parameter count exceeds safety limit 2";
        .tst.genhard.calls musteq 0;

        got:.tst.genhard.capture {
            .tst.checkedParamProduct[
                3037000500 3037000500;
                9223372036854775806]
        };
        (first got) musteq `error;
        last[got] mustlike "*overflows long*";
    };

    should["preserve the root assertion failure and parameter context"]{
        base:.tst.assertState;
        .tst.assertState.failures,:enlist "outer";
        .tst.assertState.assertsRun+:5;
        savedState:.tst.assertState;
        got:.tst.genhard.capture {
            .tst.parametrize[(enlist `x)!enlist 99;{[x]
                x mustlt 10;
            }]
        };
        afterState:.tst.assertState;
        failuresPreserved:savedState[`failures]~afterState`failures;
        countPreserved:afterState[`assertsRun]=1+savedState`assertsRun;
        .tst.assertState:base;
        (first got) musteq `error;
        last[got] mustlike "*Got 99*";
        last[got] mustlike "*Params: x=99)";
        failuresPreserved musteq 1b;
        countPreserved musteq 1b;
    };

    should["preserve executed assertion counts when a case function throws"]{
        base:.tst.assertState;
        savedState:.tst.assertState;
        got:.tst.genhard.capture {
            .tst.parametrize[(enlist `x)!enlist 1;{[x]
                x musteq 1;
                '"call-root";
            }]
        };
        afterState:.tst.assertState;
        failuresPreserved:savedState[`failures]~afterState`failures;
        countPreserved:afterState[`assertsRun]=1+savedState`assertsRun;
        .tst.assertState:base;
        (first got) musteq `error;
        last[got] mustlike "*call-root*";
        last[got] mustlike "*Params: x=1)";
        failuresPreserved musteq 1b;
        countPreserved musteq 1b;
    };

    should["restore exact state and skip invocation when formatting throws"]{
        `.tst.paramValueText mock {[val] '"format-root"};
        `.tst.genhard.calls mock 0;
        savedState:.tst.assertState;
        got:.tst.genhard.capture {
            .tst.parametrize[(enlist `x)!enlist 1;{[x]
                .tst.genhard.calls+:1;
            }]
        };
        stateRestored:savedState~.tst.assertState;
        (first got) musteq `error;
        last[got] mustlike "*format-root*";
        last[got] mustlike "*Params:*";
        .tst.genhard.calls musteq 0;
        stateRestored musteq 1b;
    };

    should["reject oversized injected parameter failure state exactly"]{
        `.tst.parametrizeStateFailureHardLimit mock 3;
        savedState:.tst.assertState;
        got:.tst.genhard.capture {
            .tst.parametrize[(enlist `x)!enlist 1;{[x]
                .tst.assertState.failures:100#enlist "hostile";
            }]
        };
        stateRestored:savedState~.tst.assertState;
        (first got) musteq `error;
        last[got] mustlike "*assertion state became invalid*";
        stateRestored musteq 1b;
    };

    should["cap final error text and render only bounded value prefixes"]{
        `.tst.parametrizeRenderLimit mock 24;
        msg:.tst.paramErrorText[
            "root-cause-abcdefghijklmnopqrstuvwxyz";
            "detail-abcdefghijklmnopqrstuvwxyz";
            "x=abcdefghijklmnopqrstuvwxyz"];
        must[(count msg)<=24;"final parameter error must honor its cap"];
        msg mustlike "detail-*";

        `.tst.parametrizeRenderLimit mock 32;
        msg:.tst.paramErrorText[
            "generic-prefix-that-may-be-dropped: ";
            "ROOT-MARKER";
            "x=context-that-may-be-truncated"];
        msg mustlike "*ROOT-MARKER*";
        must[(count msg)<=32;
            "bounded parameter errors must preserve their root cause"];

        `.tst.parametrizeRenderLimit mock 64;
        `.tst.truncate mock {[x;n] '"truncate-must-not-run"};
        valueText:.tst.paramValueText til 1000;
        must[(count valueText)<=64;"parameter rendering must honor its cap"];
        valueText mustlike "*more*";
        tiny:.tst.paramValueTextBody[(enlist `x)!enlist til 1000;5;0];
        must[(count tiny)<=5;"tiny parameter render cap must hold"];
        longSymbol:`$10000#"y";
        (.tst.paramValueText longSymbol) musteq "<symbol>";
        (.tst.paramValueText 2#longSymbol)
            musteq "<symbol list count=2>";
    };

    should["clamp poisoned and raised parameter limits to literal ceilings"]{
        huge:9223372036854775806;
        `.tst.parametrizeCaseHardLimit mock 0W;
        .tst.parametrizeCaseLimit[] musteq 1000000;
        .tst.parametrizeCaseHardLimit:huge;
        .tst.parametrizeCaseLimit[] musteq 1000000;

        `.tst.parametrizeRenderLimit mock huge;
        `.tst.parametrizeFailureItemLimit mock huge;
        `.tst.parametrizeParamHardLimit mock huge;
        `.tst.parametrizeNameLengthLimit mock huge;
        `.tst.parametrizeAssertionHardLimit mock huge;
        `.tst.parametrizeRenderDepthLimit mock huge;
        `.tst.parametrizeStateFailureHardLimit mock huge;
        .tst.parametrizeTextLimit[] musteq 1024;
        .tst.parametrizeFailureLimit[] musteq 16;
        .tst.parametrizeParamLimit[] musteq 8;
        .tst.parametrizeNameLimit[] musteq 128;
        .tst.parametrizeAssertionLimit[] musteq 1000000;
        .tst.parametrizeRenderDepth[] musteq 4;
        .tst.parametrizeStateFailureLimit[] musteq 1000;
    };
 };

::
