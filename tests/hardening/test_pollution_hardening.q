\d .tst

.tst.testState.pollutionHardening.calls:0;
.tst.testState.pollutionHardening.viewCalls:0;
.tst.testState.pollutionHardening.events:`symbol$();
.tst.testState.pollutionHardening.guarded:{[x;y]
    .tst.testState.pollutionHardening.calls+:1;
    x+y
 };

.tst.desc["pollution hardening: bounded namespace restoration"]{
    afterAll{
        @[
            {![`.tst.testState;();0b;enlist `pollutionHardening]};
            ();
            {}];
    };

    should["tag captured values without sentinel collisions"]{
        .pollutionSnapshotCase.value:10;
        .pollutionSnapshotCase.sentinel:
            (`GENERIC_ERROR;`.pollutionSnapshotCase.value);
        snapshot:.tst.snapshotNamespaceValues `pollutionSnapshotCase;
        entries:snapshot`entries;
        sentinelIdx:entries[`member]?`sentinel;
        sentinelRow:entries sentinelIdx;
        lookupError:.tst.pollutionCaptureValue[
            {[ignored] '"lookup boom"};
            `ignored];

        must[
            .tst.pollutionSnapshotValid[
                `pollutionSnapshotCase;
                snapshot];
            "snapshot schema must validate"];
        snapshot[`state] musteq `ok;
        sentinelRow[`state] musteq `ok;
        (first sentinelRow`payload) mustmatch
            (`GENERIC_ERROR;`.pollutionSnapshotCase.value);
        first[lookupError] musteq `error;
        must[1=count lookupError 1;
            "lookup errors must retain a boxed payload"];
        last[lookupError] mustmatch "lookup boom";
        must[count[last lookupError]<=.tst.pollutionErrorLimit[];
            "lookup errors must remain bounded"];

        dirtySymbols:`$(
            "bad.member";
            "bad/member";
            "line\nbreak";
            "1startsNumeric";
            "_startsUnderscore");
        must[
            not any .tst.pollutionMemberValid each dirtySymbols;
            "compound, path-like, control, and invalid-leading names must fail"];
        must[
            .tst.pollutionMemberValid `valid_Name2;
            "legal q simple identifiers must remain supported"];
        mustthrow["*namespace name is invalid*"]{
            .tst.snapshotNamespaceValues `$"bad.root"
        };
        must[
            not .tst.pollutionSnapshotValid[
                `pollutionSnapshotCase;
                (enlist `state)!enlist `ok];
            "malformed snapshot dictionaries must fail validation"];
        `.pollutionSnapshotCase set (::);
    };

    should["restore hostile callables containers missing and new members"]{
        .tst.testState.pollutionHardening.calls:0;
        guarded:.tst.testState.pollutionHardening.guarded;
        .pollutionRestoreCase.value:10;
        .pollutionRestoreCase.fn:guarded;
        .pollutionRestoreCase.projection:guarded[1;];
        .pollutionRestoreCase.composition:
            ('[neg;.pollutionRestoreCase.projection]);
        .pollutionRestoreCase.large:(til 1000000;`original);
        .pollutionRestoreCase.deep:
            (`original;100000 enlist/0);
        .pollutionRestoreCase.sentinel:
            (`GENERIC_ERROR;`.pollutionRestoreCase.value);
        .pollutionRestoreCase.missing:"restore me";
        originalFn:.pollutionRestoreCase.fn;
        originalProjection:.pollutionRestoreCase.projection;
        originalComposition:.pollutionRestoreCase.composition;
        originalSentinel:.pollutionRestoreCase.sentinel;
        snapshot:.tst.snapshotNamespaceValues `pollutionRestoreCase;

        .pollutionRestoreCase.value:999;
        .pollutionRestoreCase.fn:{[x;y]
            .tst.testState.pollutionHardening.calls+:100;
            x-y
        };
        .pollutionRestoreCase.projection:
            .pollutionRestoreCase.fn[2;];
        .pollutionRestoreCase.composition:
            ('[abs;.pollutionRestoreCase.projection]);
        .pollutionRestoreCase.large:(til 1000001;`changed);
        .pollutionRestoreCase.deep:
            (`changed;100000 enlist/1);
        .pollutionRestoreCase.sentinel:
            (`GENERIC_ERROR;`.pollutionRestoreCase.value);
        .tst.pollutionDeleteMember[
            `.pollutionRestoreCase;
            `missing];
        .pollutionRestoreCase.newMember:1;

        state:.tst.restoreSpecNamespaceState[
            `pollutionRestoreCase;
            snapshot;
            .tst.diffProbeLimit[]];

        state[`failures] musteq 0;
        state[`deleted] musteq 1;
        must[state[`restored]>=7;
            "all changed, missing, and unverified originals must be restored"];
        .pollutionRestoreCase.value musteq 10;
        .pollutionRestoreCase.fn mustmatch originalFn;
        .pollutionRestoreCase.projection mustmatch originalProjection;
        .pollutionRestoreCase.composition mustmatch originalComposition;
        (count first .pollutionRestoreCase.large) musteq 1000000;
        (last .pollutionRestoreCase.large) musteq `original;
        (first .pollutionRestoreCase.deep) musteq `original;
        .pollutionRestoreCase.sentinel mustmatch originalSentinel;
        .pollutionRestoreCase.missing mustmatch "restore me";
        must[
            not `newMember in key `.pollutionRestoreCase;
            "new namespace members must be deleted"];
        .tst.testState.pollutionHardening.calls musteq 0;
        `.pollutionRestoreCase set (::);
    };

    should["share one comparison budget across all namespaces"]{
        .tst.testState.pollutionHardening.calls:0;
        guarded:.tst.testState.pollutionHardening.guarded;
        .pollutionBudgetA.large:(til 1000000;`original);
        .pollutionBudgetB.callback:guarded[1;];
        originalCallback:.pollutionBudgetB.callback;
        snapshotA:.tst.snapshotNamespaceValues `pollutionBudgetA;
        snapshotB:.tst.snapshotNamespaceValues `pollutionBudgetB;
        namespaces:`pollutionBudgetA`pollutionBudgetB;
        snapshots:namespaces!(snapshotA;snapshotB);

        .pollutionBudgetA.large:(til 1000000;`original);
        .pollutionBudgetB.callback:guarded[2;];
        state:.tst.restorePollutionNamespacesState[
            namespaces;
            snapshots;
            .tst.diffProbeLimit[]];

        state[`remaining] musteq 0;
        state[`failures] musteq 0;
        state[`restored] musteq 2;
        .pollutionBudgetB.callback mustmatch originalCallback;
        .tst.testState.pollutionHardening.calls musteq 0;
        `.pollutionBudgetA set (::);
        `.pollutionBudgetB set (::);
    };

    should["reconstruct collapsed namespaces without inspecting views"]{
        .tst.testState.pollutionHardening.calls:0;
        .tst.testState.pollutionHardening.viewCalls:0;
        .pollutionCollapsed.value:42;
        .pollutionCollapsed.callback:
            .tst.testState.pollutionHardening.guarded[1;];
        .pollutionCollapsed.view:{[ignored]
            .tst.testState.pollutionHardening.viewCalls+:1;
            '"view probe error"
        };
        original:.tst.snapshotNamespaceValues `pollutionCollapsed;
        originalCallback:.pollutionCollapsed.callback;
        `.pollutionCollapsed set (::);
        outcome:.[
            {[snapshot]
                (`ok;enlist .tst.restoreSpecNamespaceState[
                    `pollutionCollapsed;
                    snapshot;
                    .tst.diffProbeLimit[]])
            };
            enlist original;
            {[err] (`error;enlist err)}];

        first[outcome] musteq `ok;
        restored:first outcome 1;
        restored[`failures] musteq 0;
        restored[`restored] musteq 3;
        .pollutionCollapsed.value musteq 42;
        .pollutionCollapsed.callback mustmatch originalCallback;
        .tst.testState.pollutionHardening.calls musteq 0;
        .tst.testState.pollutionHardening.viewCalls musteq 0;

        `.pollutionCollapsed set (::);
        bare:.tst.snapshotNamespaceValues `pollutionCollapsed;
        bare[`state] musteq `ok;
        (count bare`entries) musteq 0;
    };

    should["surface namespace cleanup errors"]{
        .pollutionFailure.value:10;
        original:.tst.snapshotNamespaceValues `pollutionFailure;
        .pollutionFailure.value:999;
        savedSetter:.tst.pollutionSetMember;
        .tst.pollutionSetMember:{[namespace;member;payload] `error};
        cleanupOutcome:@[
            {[snapshot]
                .tst.restoreSpecNamespace[
                    "failure visibility";
                    `pollutionFailure;
                    snapshot];
                (`ok;"")
            };
            original;
            {[err] (`error;.tst.pollutionBoundedError err)}];
        .tst.pollutionSetMember:savedSetter;
        savedSetter[
            `.pollutionFailure;
            `value;
            enlist 10];

        first[cleanupOutcome] musteq `error;
        last[cleanupOutcome] mustlike
            "*pollution namespace cleanup incomplete*";
        `.pollutionFailure set (::);
    };

    should["restore originals despite omitted or invalid current root listings"]{
        .pollutionCleanupOriginal.value:10;
        original:.tst.snapshotNamespaceValues `pollutionCleanupOriginal;
        snapshots:()!();
        snapshots[`pollutionCleanupOriginal]:original;
        lifecycle:
            `pollutionGuard`namespaces`pollutionSnapshot!(
                1b;
                enlist `pollutionCleanupOriginal;
                snapshots);
        cleanupOutcome:{[state]
            .[
                {[boxed]
                    .tst.cleanupSpecPollution first boxed;
                    (`ok;"")
                };
                enlist enlist state;
                {[err]
                    (`error;.tst.pollutionBoundedError err)}]
        };

        savedNamespaces:.tst.specPollutionNamespaces;
        .pollutionCleanupOriginal.value:20;
        .tst.specPollutionNamespaces:{[enabled] `symbol$()};
        omitted:cleanupOutcome lifecycle;
        .tst.specPollutionNamespaces:savedNamespaces;

        first[omitted] musteq `ok;
        .pollutionCleanupOriginal.value musteq 10;

        savedLimit:.tst.pollutionNamespaceLimit;
        .pollutionCleanupOriginal.value:30;
        .tst.pollutionNamespaceLimit:{[] 0};
        overLimit:cleanupOutcome lifecycle;
        .tst.pollutionNamespaceLimit:savedLimit;

        first[overLimit] musteq `error;
        last[overLimit] mustlike "*pollution cleanup incomplete*";
        .pollutionCleanupOriginal.value musteq 10;

        .pollutionCleanupOriginal.value:40;
        .tst.specPollutionNamespaces:
            {[enabled] '"pollution namespace name is invalid"};
        invalidName:cleanupOutcome lifecycle;
        .tst.specPollutionNamespaces:savedNamespaces;

        first[invalidName] musteq `error;
        last[invalidName] mustlike "*pollution cleanup incomplete*";
        .pollutionCleanupOriginal.value musteq 10;
        `.pollutionCleanupOriginal set (::);
    };

    should["leave failed acquisition state atomic"]{
        savedSnapshot:.tst.snapshotNamespaceValues;
        .tst.snapshotNamespaceValues:{[namespace] ()!()};
        lifecycle:.tst.captureSpecLifecycle
            (enlist `title)!enlist "atomic acquisition probe";
        .tst.snapshotNamespaceValues:savedSnapshot;

        lifecycle[`errorPhase] musteq `pollution;
        lifecycle[`pollutionSet] musteq 0b;
        lifecycle[`runContextSet] musteq 1b;
        lifecycle[`handlesSet] musteq 1b;
    };

    should["continue finalizer steps after a cleanup error"]{
        .tst.testState.pollutionHardening.events:`symbol$();
        firstErrors:.tst.runSpecFinalizeStep[
            `pollution;
            {[ignored]
                .tst.testState.pollutionHardening.events,:enlist `pollution;
                '"cleanup boom"
            };
            ()];
        laterErrors:.tst.runSpecFinalizeStep[
            `later;
            {[ignored]
                .tst.testState.pollutionHardening.events,:enlist `later;
                ::
            };
            ()];
        must[0<count firstErrors;
            "cleanup failure must remain visible"];
        laterErrors mustmatch ();
        .tst.testState.pollutionHardening.events mustmatch
            `pollution`later;
    };
};

.tst.desc["pollution hardening: retained bare namespace names"]{
    should["ignore the exact populated and cleared root metadata marker"]{
        .f:{x+y};
        populatedKeys:key `.f;
        populated:.tst.snapshotNamespaceValues `f;
        `.f set (::);
        clearedKeys:key `.f;
        cleared:.tst.snapshotNamespaceValues `f;

        must[`.f in populatedKeys;
            "populated roots must expose q's fully-qualified marker"];
        must[`.f in clearedKeys;
            "cleared roots must retain q's fully-qualified marker"];
        populated[`state] musteq `ok;
        (count populated`entries) musteq 0;
        cleared[`state] musteq `ok;
        (count cleared`entries) musteq 0;
    };

    should["treat cleared top-level names as empty namespaces"]{
        names:
            `pollutionSnapshotCase`pollutionRestoreCase,
            `pollutionBudgetA`pollutionBudgetB,
            `pollutionCollapsed`pollutionFailure;
        snapshots:.tst.snapshotNamespaceValues each names;

        must[all {`ok~x`state} each snapshots;
            "bare namespace snapshots must remain readable"];
        must[all {0=count x`entries} each snapshots;
            "bare namespace snapshots must stay empty"];
    };
};

\d .
