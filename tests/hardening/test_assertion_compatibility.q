\d .tst

.tst.testState.assertionCompatibility.calls:0;
.tst.testState.assertionCompatibility.guarded:{[x;y]
    .tst.testState.assertionCompatibility.calls+:1;
    x+y
 };
.tst.testState.assertionCompatibility.enumDomain:`a`b;

.tst.desc["assertion compatibility: q value semantics"]{
    afterAll{
        @[
            {![`.tst.testState;();0b;enlist `assertionCompatibility]};
            ();
            {}];
    };

    should["ignore list attributes at every structural level"]{
        plainStrings:("a";"b";"c");
        sortedStrings:asc ("c";"b";"a");
        plainVector:1 2 3;
        sortedVector:`s#1 2 3;
        plainTable:([] id:1 2 3;payload:("a";"b";"c"));
        sortedTable:([] id:`s#1 2 3;payload:asc ("c";"b";"a"));
        plainDict:`strings`vector`table!(
            plainStrings;
            plainVector;
            plainTable);
        attributedDict:`strings`vector`table!(
            sortedStrings;
            sortedVector;
            sortedTable);

        must[not (attr plainStrings)~attr sortedStrings;
            "test setup must use different outer-list attributes"];
        plainStrings mustmatch sortedStrings;
        plainVector mustmatch sortedVector;
        plainTable mustmatch sortedTable;
        plainDict mustmatch attributedDict;
        (enlist plainDict) mustmatch enlist attributedDict;
    };

    should["match equal and reject different callable leaves"]{
        lambdaA:{x+1};
        lambdaB:{x+1};
        lambdaDifferent:{x+2};
        lambdaAlias:lambdaA;
        projectionA:+[1;];
        projectionB:+[1;];
        projectionDifferent:+[2;];
        compositionA:('[neg;projectionA]);
        compositionB:('[neg;projectionB]);
        compositionDifferent:('[neg;projectionDifferent]);
        iteratorA:(projectionA');
        iteratorB:(projectionB');
        iteratorDifferent:(projectionDifferent');
        primitiveA:+;
        primitiveAlias:primitiveA;
        primitiveDifferent:-;

        lambdaA mustmatch lambdaB;
        lambdaA mustmatch lambdaAlias;
        lambdaA mustnmatch lambdaDifferent;
        projectionA mustmatch projectionB;
        projectionA mustnmatch projectionDifferent;
        compositionA mustmatch compositionB;
        compositionA mustnmatch compositionDifferent;
        must[(type iteratorA) within 105 112h;
            "test setup must exercise a derived iterator"];
        iteratorA mustmatch iteratorB;
        iteratorA mustnmatch iteratorDifferent;
        primitiveA mustmatch primitiveAlias;
        primitiveA mustnmatch primitiveDifferent;
    };

    should["match callable aliases inside dictionaries without invoking them"]{
        .tst.testState.assertionCompatibility.calls:0;
        guarded:.tst.testState.assertionCompatibility.guarded;
        alias:guarded;
        left:`callback`projection!(guarded;guarded[1;]);
        right:`callback`projection!(alias;alias[1;]);

        left mustmatch right;
        .tst.testState.assertionCompatibility.calls musteq 0;
    };

    should["bound large and deep values captured by projections"]{
        largeLeft:.tst.testState.assertionCompatibility.guarded[til 1000000;];
        largeRight:.tst.testState.assertionCompatibility.guarded[til 1000000;];
        largeAlias:largeLeft;
        deepLeft:.tst.testState.assertionCompatibility.guarded[
            100000 enlist/0;
            ];
        deepRight:.tst.testState.assertionCompatibility.guarded[
            100000 enlist/0;
            ];
        deepCompositionLeft:('[neg;deepLeft]);
        deepCompositionRight:('[neg;deepRight]);
        nestedCompositionLeft:
            20 {[fn] ('[neg;fn])}/+[1;];
        nestedCompositionRight:
            20 {[fn] ('[neg;fn])}/+[1;];
        hugeLambdaSource:
            "{[] .tst.testState.assertionCompatibility.calls+:1;\"",
            (1000000#"x"),
            "\"}";
        hugeLambdaLeft:value hugeLambdaSource;
        hugeLambdaRight:value hugeLambdaSource;
        enumValue:
            `.tst.testState.assertionCompatibility.enumDomain$`a`b`a;
        enumLeft:.tst.testState.assertionCompatibility.guarded[enumValue;];
        enumRight:.tst.testState.assertionCompatibility.guarded[enumValue;];

        started:.z.p;
        largeState:.tst.diffSafeMatchState[largeLeft;largeRight];
        aliasState:.tst.diffSafeMatchState[largeLeft;largeAlias];
        deepState:.tst.diffSafeMatchState[deepLeft;deepRight];
        compositionState:.tst.diffSafeMatchState[
            deepCompositionLeft;
            deepCompositionRight];
        nestedCompositionState:.tst.diffSafeMatchState[
            nestedCompositionLeft;
            nestedCompositionRight];
        hugeLambdaState:.tst.diffSafeMatchState[
            hugeLambdaLeft;
            hugeLambdaRight];
        enumState:.tst.diffSafeMatchState[enumLeft;enumRight];
        elapsed:`long$.z.p-started;

        largeState[`state] musteq `unknown;
        aliasState[`state] musteq `unknown;
        deepState[`state] musteq `unknown;
        compositionState[`state] musteq `unknown;
        nestedCompositionState[`state] musteq `unknown;
        hugeLambdaState[`state] musteq `unknown;
        enumState[`state] musteq `unknown;
        must[largeState[`used]<=.tst.diffProbeLimit[];
            "large callable comparison must respect its work budget"];
        must[deepState[`used]<=.tst.diffProbeLimit[];
            "deep callable comparison must respect its work budget"];
        must[compositionState[`used]<=.tst.diffProbeLimit[];
            "composed callable comparison must respect its work budget"];
        must[nestedCompositionState[`used]<=.tst.diffProbeLimit[];
            "nested composition must respect its work budget"];
        must[hugeLambdaState[`used]<=.tst.diffProbeLimit[];
            "huge lambda comparison must respect its work budget"];
        must[enumState[`used]<=.tst.diffProbeLimit[];
            "enumerated captures must fail closed within their work budget"];
        must[elapsed<1000000000;
            "hostile callable comparison must complete within one second"];
        .tst.testState.assertionCompatibility.calls musteq 0;
    };

    should["retain unknown for hostile equal nested containers"]{
        state:.tst.diffSafeMatchState[
            (til 100000;enlist enlist 0);
            (til 100000;enlist enlist 0)];

        state[`state] musteq `unknown;
        must[state[`used]<=.tst.diffProbeLimit[];
            "nested comparison must respect the structural work budget"];
    };
};

\d .
