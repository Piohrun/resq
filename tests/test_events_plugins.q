.tst.testState.plugins.canRun:
    (0<count @[system;"command -v q 2>/dev/null";{()}]) and
    (0<count @[system;"command -v python3 2>/dev/null";{()}]);
.tst.testState.plugins.counter:0;

.tst.testState.plugins.run:{[extra;failPlugin]
    .tst.testState.plugins.counter+:1;
    wd:.utl.tempRoot[],"/resq_plugins_",string[.z.i],"_",
        string[.tst.testState.plugins.counter],"_",string `long$.z.p;
    .utl.ensureDir wd;
    report:wd,"/report";
    pluginOut:wd,"/plugin.json";
    state:wd,"/state.json";
    fixture:.resq.HOME,"/tests/fixtures/sharding/shard_a.q";
    plugin:.resq.HOME,"/tests/fixtures/plugins/contract_plugin.q";
    prefix:$[failPlugin;"RESQ_PLUGIN_FAIL=1 ";""];
    cmd:prefix,"RESQ_PLUGIN_OUTPUT=",.utl.shellQuote[pluginOut],
        " timeout -k 2 30 q ",.utl.shellQuote[.resq.HOME,"/resq.q"],
        " test ",.utl.shellQuote[fixture]," -plugin ",.utl.shellQuote[plugin],
        " -json -quiet -outDir ",.utl.shellQuote[report],
        " -state-file ",.utl.shellQuote[state],
        " -flake-history ",.utl.shellQuote[wd,"/flake.json"],
        " -quarantine-file ",.utl.shellQuote[wd,"/quarantine.json"],
        " -flake-proposal-file ",.utl.shellQuote[wd,"/proposals.json"]," ",extra,
        " > ",.utl.shellQuote[wd,"/out.txt"]," 2>&1; echo $?";
    code:"J"$last @[system;"sh -c ",.utl.shellQuote cmd;{[e]enlist "-1"}];
    raw:@[read0;hsym `$report,"/test-results.json";{()}];
    pluginRaw:@[read0;hsym `$pluginOut;{()}];
    validationCode:"J"$last @[system;
        "python3 ",.utl.shellQuote[.resq.HOME,"/tools/validate_report.py"]," ",
        .utl.shellQuote[report,"/test-results.json"]," >/dev/null 2>&1; echo $?";
        {[e]enlist "-1"}];
    doc:$[count raw;.j.k "\n" sv raw;()!()];
    pluginDoc:$[count pluginRaw;.j.k "\n" sv pluginRaw;()!()];
    if[wd like "*/resq_plugins_*";system "rm -rf -- ",.utl.shellQuote wd];
    `code`validationCode`doc`plugin!(code;validationCode;doc;pluginDoc)
 };

.tst.desc["public events, manifest and plugin lifecycle #slow"]{
  skipIf[not .tst.testState.plugins.canRun;
         "emit ordered lifecycle events and protect verdict state from plugins"]{
    result:.tst.testState.plugins.run["";0b];
    result[`code] musteq 0j;
    result[`validationCode] musteq 0j;
    doc:result`doc;
    doc[`summary;`passCount] musteq 1f;
    lifecycleGolden:.j.k "\n" sv read0 hsym `$ .resq.HOME,
        "/tests/contracts/lifecycle-v2-golden.json";
    types:{x`type} each doc`events;
    types musteq lifecycleGolden`singleTestTypes;
    sequences:"j"${x`sequence} each doc`events;
    sequences musteq 1j+til count sequences;
    must[all {2f=x`schemaVersion} each doc`events;
         "every new event must declare observed-time schema version 2"];
    testRow:first doc`tests;
    must[all `startedAt`finishedAt in key testRow;
         "test rows must carry their observed interval"];
    must[not (testRow`startedAt)~testRow`finishedAt;
         "a real test interval must retain distinct observations"];
    testStarted:first (doc`events) where {"test.started"~x`type} each doc`events;
    testFinished:first (doc`events) where {"test.finished"~x`type} each doc`events;
    testStarted[`occurredAt] musteq testRow`startedAt;
    testFinished[`occurredAt] musteq testRow`finishedAt;
    manifestEvent:first (doc`events) where {"manifest.published"~x`type} each doc`events;
    manifestKeys:asc key manifestEvent`payload;
    expectedManifestKeys:asc `$lifecycleGolden`manifestPublishedPayloadKeys;
    manifestKeys musteq expectedManifestKeys;
    doc[`run;`wallDurationSeconds] musteq doc[`run;`durationSeconds];
    doc[`summary;`testDurationSumSeconds] musteq doc[`summary;`durationSeconds];
    doc[`manifest;`schemaVersion] musteq 2f;
    doc[`manifest;`kind] musteq "resq-execution-manifest";
    doc[`manifest;`digest] mustlike "manifest_*";
    count[doc[`manifest;`files]] musteq 1;
    count[doc[`manifest;`tests]] musteq 1;
    first[doc[`manifest;`tests]][`executionId]
        musteq first[doc[`manifest;`tests]][`testId];
    result[`plugin;`types] musteq types;
    result[`plugin;`summary;`passCount] musteq 1f;
    result[`plugin;`manifestDigest] musteq doc[`manifest;`digest];

    isolated:.tst.testState.plugins.run[
        "-isolate -isolateTimeout 10 -isolateWorkers 2";0b];
    isolated[`code] musteq 0j;
    isolated[`validationCode] musteq 0j;
    ({x`type} each isolated[`doc;`events]) musteq types;
    isolated[`plugin;`types] musteq types;
    isolated[`plugin;`manifestDigest] musteq doc[`manifest;`digest];
  };

  skipIf[not .tst.testState.plugins.canRun;
         "trap plugin failures and make strict policy explicit"]{
    lenient:.tst.testState.plugins.run["";1b];
    lenient[`code] musteq 0j;
    lenient[`validationCode] musteq 0j;
    lenient[`doc;`summary;`passCount] musteq 1f;
    lenientDiags:lenient[`doc;`diagnostics];
    must[any {"plugin"~x`type} each lenientDiags;
         "a lenient plugin error must remain observable"];
    not any {"PLUGIN_FAILURE"~x`suite} each lenient[`doc;`tests];

    strict:.tst.testState.plugins.run["-strict-plugins";1b];
    strict[`code] musteq 1j;
    strict[`validationCode] musteq 0j;
    strict[`doc;`summary;`errorCount] musteq 1f;
    any {"PLUGIN_FAILURE"~x`suite} each strict[`doc;`tests];
    strictDiags:strict[`doc;`diagnostics];
    must[any {("plugin"~x`type) and "error"~x`severity} each strictDiags;
         "strict plugin failure must be an error diagnostic"];
  };
 };

.tst.desc["benchmark event uses test finish"]{
  should["timestamp benchmark.finished with its owning test observation"]{
    golden:.j.k "\n" sv read0 hsym `$ .resq.HOME,
        "/tests/contracts/lifecycle-v2-golden.json";
    golden[`observedTiming;`$"benchmark.finished"] musteq "test.finishedAt";
    doc:.j.k "\n" sv read0 hsym `$ .resq.HOME,
        "/tests/contracts/report-v2.json";
    rows:.tst.eventRows doc`tests;
    row:first rows;
    row[`time]:"N"$row`time;
    row[`finishedAt]:"2026-08-12T12:00:00.123456789Z";
    row[`benchmark]:enlist[`benchmarkId]!enlist
        "benchmark_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    doc[`tests]:enlist row;
    events:.tst.lifecycleEvents[doc;doc`manifest];
    benchmarkEvent:first events where {"benchmark.finished"~x`type} each events;
    benchmarkEvent[`occurredAt] musteq row`finishedAt;
  };
 };

::
