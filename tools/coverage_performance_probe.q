/ Executable micro-profile for coverage accounting. This file is loaded only by
/ tools/verify_coverage_performance.py; keeping the timed work in q avoids
/ measuring process/IPC overhead while the Python wrapper owns policy/evidence.
.utl.require .utl.PKGLOADING,"/coverage.q";

.tst.coveragePerfCounter:0j;
.tst.coveragePerfControl:{[ignored]
    .tst.coveragePerfCounter+:1j;
    ::
 };

.tst.coveragePerfElapsedNs:{[fn;iterations]
    started:.z.p;
    fn each til iterations;
    ("f"$"j"$.z.p-started)%"f"$iterations
 };

.tst.coveragePerfSamples:{[controlFn;statementFn;contextFn;reportFn;iterations;reportEntries]
    / Warm every path before recording. The regression is repeated-hit cost,
    / not first-use cache construction or q's first lambda invocation.
    controlFn each til 2*iterations;
    statementFn each til 2*iterations;
    contextFn each til 2*iterations;
    reportFn each til 2;
    control:();statement:();context:();report:();
    i:0;
    while[i<7;
        control,:.tst.coveragePerfElapsedNs[controlFn;iterations];
        statement,:.tst.coveragePerfElapsedNs[statementFn;iterations];
        context,:.tst.coveragePerfElapsedNs[contextFn;iterations];
        report,:.tst.coveragePerfElapsedNs[reportFn;1j]%"f"$reportEntries;
        i+:1];
    `controlNsPerHit`statementNsPerHit`contextNsPerHit`reportNsPerEntry!(
        control;statement;context;report)
 };

.tst.desc["Coverage performance probe"]{
    should["coverage context hot path budget"]{
        iterations:5000j;
        reportContexts:160j;
        metricsPerContext:12j;
        reportEntries:reportContexts*metricsPerContext;
        file:`$.tst.resolvePath "src/coverage-performance.q";

        / A realistic per-file line map exposes whole-dictionary copy cost.
        .tst.lineCoverageData:(enlist file)!enlist
            ((1+til 512j)!512#0j);
        statementFn:{[f;ignored].tst.covL[f;257j]}[file;];

        .tst.coverageContexts:1b;
        .tst.coverageContextEntryMax:100000j;
        .tst.coverageContextRegistry:()!();
        .tst.coverageContextMetricMeta:()!();
        .tst.coverageContextMetricHits:(`symbol$())!`long$();
        ctx:.tst.coverageContextMeta[
            "probe_context";"test";"probe_test";0j;
            "coverage performance";"repeated hits";string file];
        .tst.coverageActiveContext:.tst.ensureCoverageContext ctx;
        contextFn:{[f;ignored]
            .tst.recordCoverageContextMetric[
                `statement;f;`.coverage.performance;"probe_site";-1j]
          }[file;];

        / Build a deterministic dense context/metric model once, then measure
        / only report assembly. It intentionally places every metric in one
        / flat map, matching production state before the Step-7 optimization.
        registry:()!();entryIds:reportEntries#`;
        metricRows:reportEntries#enlist (::);
        hitValues:reportEntries#1j;
        i:0;
        while[i<reportContexts;
            contextId:"profile_ctx_",string i;
            registry[`$contextId]:.tst.coverageContextMeta[
                contextId;"test";"profile_test_",string i;0j;
                "profile";"report assembly";string file];
            j:0;
            while[j<metricsPerContext;
                metricId:"profile_metric_",string j;
                entryText:"profile_entry_",((),string i),"_",(),string j;
                entryId:`$entryText;
                position:(i*metricsPerContext)+j;
                entryIds[position]:entryId;
                metricRows[position]:.tst.coverageMetricMeta[
                    contextId;metricId;`statement;file;
                    `.coverage.performance;metricId;-1j];
                j+:1];
            i+:1];
        metricMeta:entryIds!metricRows;
        metricHits:entryIds!hitValues;
        reportFn:{[r;m;h;ignored]
            .tst.coverageContextRowsFrom[r;m;h];::
          }[registry;metricMeta;metricHits;];

        samples:.tst.coveragePerfSamples[
            .tst.coveragePerfControl;statementFn;contextFn;reportFn;
            iterations;reportEntries];
        payload:`schemaVersion`kind`qVersion`iterations`reportContexts`metricsPerContext`samples!(
            1j;"resq-coverage-performance-probe";.tst.toString .z.K;
            iterations;reportContexts;metricsPerContext;samples);
        -1 "RESQ_COVERAGE_PERF=",.j.j payload;
        .tst.coveragePerfCounter musteq 9*iterations;
    };
};
