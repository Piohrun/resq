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
        " -state-file ",.utl.shellQuote[state]," ",extra,
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
    types:{x`type} each doc`events;
    types musteq (
        "run.started";"manifest.published";"file.started";"suite.started";
        "test.started";"attempt.started";"attempt.finished";"test.finished";
        "suite.finished";"file.finished";"run.finished");
    sequences:"j"${x`sequence} each doc`events;
    sequences musteq 1j+til count sequences;
    must[all {1f=x`schemaVersion} each doc`events;
         "every event must declare schema version 1"];
    doc[`manifest;`schemaVersion] musteq 1f;
    doc[`manifest;`kind] musteq "resq-execution-manifest";
    doc[`manifest;`digest] mustlike "manifest_*";
    count[doc[`manifest;`files]] musteq 1;
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

::
