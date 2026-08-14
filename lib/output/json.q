/ JSON reporter. Shared row/value helpers are loaded from output/sanitize.q.

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
    jsonReport: .tst.output.evidenceJson jsonPayload;

    outDirStr: .tst.toString .tst.runOutputDir[];
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
