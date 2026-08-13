/ Loaded through -plugin before discovery. The observer deliberately attempts
/ to corrupt verdict state; the framework must restore it after every callback.
.resq.pluginProbe.types:();
.resq.pluginProbe.output:getenv `RESQ_PLUGIN_OUTPUT;
.resq.pluginProbe.fail: "1"~first getenv `RESQ_PLUGIN_FAIL;

.resq.registerObserver[`contractObserver;{[event]
    if[.resq.pluginProbe.fail;'"observer boom"];
    .resq.pluginProbe.types,:enlist event`type;
    .resq.state.results:.resq.state.emptyResults[];
    .tst.app.passed:0b;
    `ignoredReturn
 }];

.resq.registerReporter[`contractReporter;{[model;events]
    if[count .resq.pluginProbe.output;
        payload:`types`summary`manifestDigest!(
            .resq.pluginProbe.types;model`summary;model[`manifest;`digest]);
        (hsym `$ .resq.pluginProbe.output) 0:enlist .j.j payload];
    .resq.state.results:.resq.state.emptyResults[];
    .tst.app.passed:0b;
    `ignoredReturn
 }];
