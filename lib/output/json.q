/ JSON reporter.

.tst.output.jsonDurationSeconds:{[v]
    raw: $[0h = type v; 0N; 98h = type v; first v; v];
    $[null raw; 0f; -16h = type raw; raw % 1e9; 0f]
 };

/ Stable schema-v2 test row. In particular `message is ALWAYS a string and
/ `failures is ALWAYS a list of strings; q's native values otherwise make the
/ JSON type depend on pass/fail/error status.
.tst.output.jsonRow:{[row]
    out: row;
    rawMsg: $[`message in key row; row`message; ""];
    out[`message]: .tst.renderReportMessage rawMsg;
    rawFailures: $[`failures in key row; row`failures; ()];
    out[`failures]: $[0 = count rawFailures; ();
                      10h = type rawFailures; enlist rawFailures;
                      0h = type rawFailures;
                        {[v] $[10h = type v; v; .tst.toString v]} each rawFailures;
                      enlist .tst.toString rawFailures];
    rawTime: $[`time in key row; row`time; 0Nn];
    out[`time]: string rawTime;
    out[`durationSeconds]: .tst.output.jsonDurationSeconds rawTime;
    if[not `file in key out; out[`file]: ""];
    if[not `line in key out; out[`line]: 0Ni];
    if[not `namespace in key out; out[`namespace]: ""];
    if[not `tags in key out; out[`tags]: `symbol$()];
    if[not `testId in key out;out[`testId]:""];
    if[not `caseId in key out;out[`caseId]:""];
    if[not `kind in key out;out[`kind]:`test];
    if[not `parameters in key out;out[`parameters]:()!()];
    if[not `attempts in key out;out[`attempts]:1i];
    if[not `retried in key out;out[`retried]:0b];
    if[not `flaky in key out;out[`flaky]:0b];
    if[not `attemptHistory in key out;out[`attemptHistory]:()];
    if[not `parameterCases in key out;out[`parameterCases]:()];
    if[not `property in key out;out[`property]:()!()];
    if[not `diagnostics in key out;out[`diagnostics]:()];
    if[not `snapshots in key out;out[`snapshots]:()];
    if[not `benchmark in key out;out[`benchmark]:()!()];
    if[`quarantine in key out;
        qstate:out`quarantine;
        if[(not 99h=type qstate) or 0=count qstate;
            out:(key[out] except enlist `quarantine)#out]];
    rawOutput: $[`output in key out; out`output; ""];
    out[`output]: .tst.stripAnsi .tst.renderReportMessage rawOutput;
    out
 };

/ JSON evidence profiles are projections of the one immutable canonical model.
/ An omitted section is absent and declared below; it is never encoded as an
/ empty object/list that could be mistaken for an observed empty measurement.
.tst.output.profileCompleteness:{[profile]
    omittedSections:$[profile~`full;();
        ("performance";"coverage";"flake";"snapshotInventory";
         "benchmarkAnalysis";"manifest";"events")];
    omittedTestFields:$[profile~`telemetry;
        ("time";"failures";"namespace";"tags";"output";"parameters";
         "attemptHistory";"parameterCases";"property";"diagnostics";
         "snapshots";"benchmark";"quarantine");()];
    boundedFields:$[profile~`telemetry;
        ("tests.message";"diagnostics.message");()];
    `evidenceComplete`omittedSections`omittedTestFields`boundedFields!(
        profile~`full;omittedSections;omittedTestFields;boundedFields)
 };

.tst.output.telemetryRow:{[row]
    fields:`suite`description`status`message`durationSeconds`assertsRun`file`line,
        `testId`caseId`kind`attempts`retried`flaky`startedAt`finishedAt;
    (fields inter key row)#row
 };

.tst.output.profileRunModel:{[model;profile]
    out:model;
    if[profile in `results`telemetry;
        keep:`schemaVersion`framework`frameworkVersion`run`summary`tests`diagnostics;
        out:(keep inter key out)#out];
    if[profile~`telemetry;
        out[`tests]:.tst.output.telemetryRow each .tst.resultRows out];
    out[`profile]:.tst.toString profile;
    out[`completeness]:.tst.output.profileCompleteness profile;
    out
 };

.resq.reportJson:{[results]
    isModel:0b;
    if[99h=type results;isModel:all `run`summary`tests in key results];
    payload:$[isModel;results;.tst.canonicalRunModel results];
    jsonPayload:payload;
    jsonPayload[`tests]:.tst.output.jsonRow each .tst.resultRows payload;
    profile:`$lower .tst.toString @[get;`.tst.app.reportProfile;`full];
    jsonPayload:.tst.output.profileRunModel[jsonPayload;profile];
    jsonReport: .j.j jsonPayload;

    outDirStr: .tst.toString .resq.config.outDir;
    if[0 = count outDirStr; outDirStr: "."];
    baseDirStr: .tst.toString .tst.app.baseDir;
    if[0 = count baseDirStr; baseDirStr: system "cd"];
    if[not outDirStr like "/*"; outDirStr: baseDirStr, "/", outDirStr];
    outDirStr: .utl.normalizePath outDirStr;
    outFile: outDirStr, "/test-results.json";
    .utl.ensureDir outDirStr;
    hsym[`$outFile] 0: enlist jsonReport;
    -1 "JSON Report written to ", outFile;
 };
