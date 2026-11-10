/ Native child process: the enclosing self-suite must not pre-initialize resQ.
if["qutil"~.z.x 1;
    system "l ",(.z.x 0),"/pilots/vendor/nugend-qutil/lib/bootstrap.q";
    .utl.DEBUG:1b;
    .utl.PKGLOADING:"host-package";
    .utl.FILELOADING:`:host.q];
system "l ",(.z.x 0),"/lib/init.q";
.host.check:{[ok;message]if[not ok;'message]};
.host.write:{[path;lines](hsym `$path) 0: lines};
.host.ok:".tst.desc[\"good\"]{should[\"passes\"]{1 musteq 1}};";
.host.write["test_good.q";enlist .host.ok];
.host.write["test_bad.q";enlist ".tst.desc[\"bad\"]{should[\"fails\"]{1 musteq 2};should[\"later\"]{1 musteq 1}};"];
.host.write["test_empty.q";enlist ".application.empty:1;"];
.host.write["test_load.q";enlist "'\"deliberate load failure\";"];
.host.beforeCwd:system "cd";
setenv[`TMPDIR;.host.beforeCwd];
.host.beforeQ:get `.q;
.host.snapshot:{[]get each `.tst`.resq`.utl};
.host.clean:{[before]
    .host.check[before~.host.snapshot[];"framework state leaked"];
    .host.check[.host.beforeCwd~system "cd";"working directory leaked"];
    .host.check[.host.beforeQ~get `.q;"q namespace changed"];
    .host.check[not .utl.pathExists ".resq";"persistent history leaked"];
    .host.check[not any (string key hsym `$ .host.beforeCwd) like "resq-embedded-*";"temporary history leaked"];
 };
.host.expect:{[path;opts;code;rows]
    before:.host.snapshot[];
    r:.resq.run[path;opts];
    .host.check[code=r`exitCode;"unexpected exit code: ",string r`exitCode];
    .host.check[(0=code)~r`passed;"inconsistent passed flag"];
    .host.check[rows=count r`results;"unexpected result count: ",string count r`results];
    .host.check[1j~r`schemaVersion;"unexpected schema"];
    .host.clean before;
    r
 };

.host.repeated:{[]
    / An existing project's config/history must not configure the API implicitly.
    .host.write["resq.json";enlist "{\"runSpecs\":[\"nothing\"],\"exit\":true}"];
    .tst.app.strict:1b;
    .tst.registerFixtureWithOpts[`host;42;`scope`teardown!(`session;{[x]'"host fixture must not be torn down"})];
    .tst.getFixture `host;
    .tst.registerCleanup[{[x]'"host cleanup must not run"};enlist 1];
    .host.expect["test_bad.q";()!();1;2];
    .host.expect["test_good.q";()!();0;1];
    .host.expect[`test_good.q;()!();0;1];
    .host.expect[("test_good.q";"test_bad.q");()!();1;3];
    .host.expect["test_load.q";()!();4;1];
    .host.expect["test_good.q";()!();0;1];
    .host.expect["missing";()!();4;1];
    .utl.ensureDir "empty";
    .host.expect["empty";()!();3;0];
    .host.expect["test_empty.q";()!();1;0];
    .host.expect["test_empty.q";(enlist `strict)!enlist 1b;4;2];
    .host.expect["test_bad.q";(enlist `failFast)!enlist 1b;1;1];
    .host.expect["test_bad.q";()!();1;2];
    .host.expect["test_good.q";(enlist `runSpecs)!enlist "absent";1;0];
    .host.expect["test_good.q";()!();0;1];
 };

.host.callbacks:{[]
    .z.pg:{[x]`original};
    .z.ts:{[]::};
    system "t 123456";
    .host.originalPg:.z.pg;
    .host.originalTs:.z.ts;
    .host.write["test_callbacks.q";(
        ".z.pg:{[x]`changed};";
        ".z.ps:{[x]::};";
        "system \"t 7\";";
        .host.ok)];
    .host.expect["test_callbacks.q";()!();0;1];
    .host.check[.host.originalPg~.z.pg;"sync callback leaked"];
    .host.check[.host.originalTs~.z.ts;"timer callback leaked"];
    .host.check[123456=system "t";"timer interval leaked"];
    .host.check[@[{get `.z.ps;0b};();{[e]1b}];"new async callback leaked"];
    .host.write["test_callbacks.q";(".z.pg:{[x]`changed};";"system \"cd /\";";"'\"load failure after callback\";")];
    .host.expect["test_callbacks.q";()!();4;1];
    .host.check[.host.originalPg~.z.pg;"load error leaked callback"];
    system "d .host";
    r:.resq.run["test_good.q";()!()];
    .host.check[0=r`exitCode;"non-root invocation failed"];
    .host.check[".host"~string system "d";"namespace leaked"];
    system "d .";
    system "t 0";
 };

.host.cleanup:{[]
    hostHandle:hopen `:host_handle.txt;
    .application.original:{[x]x+1};
    original:.application.original;
    .host.write["test_cleanup.q";(
        ".tst.registerFixtureWithOpts[`owned;42;`scope`teardown!(`session;{[x]`:teardown.txt 0: enlist string x})];";
        ".tst.getFixture `owned;";
        ".tst.mock[`.application.original;{[x]99}];";
        ".tst.registerCleanup[{[]`:cleanup.txt 0: enlist \"cleaned\"};()];";
        ".tst.registerSpecCleanup[{[]'\"deliberate teardown failure\"};()];";
        ".host.leaked:hopen `:leaked.txt;";
        "'\"load failed after setup\";")];
    before:.host.snapshot[];
    r:.resq.run["test_cleanup.q";()!()];
    .host.check[4=r`exitCode;"setup load failure not reflected"];
    .host.check[2=count r`results;"cleanup failure not recorded"];
    .host.check[any `cleanup=r[`results]`kind;"missing cleanup result"];
    .host.check[original~.application.original;"mock leaked"];
    .host.check["42"~first read0 `:teardown.txt;"session fixture not torn down"];
    .host.check["cleaned"~first read0 `:cleanup.txt;"load cleanup not drained"];
    .host.check[@[{x enlist "bad";0b};.host.leaked;{[e]1b}];"load handle leaked"];
    .host.clean before;
    neg[hostHandle] enlist "host still open";
    hclose hostHandle;
    .host.check["host still open"~first read0 `:host_handle.txt;"host handle closed"];
    .host.expect["test_good.q";()!();0;1];
 };

.host.reject:{[opts]
    before:.host.snapshot[];
    e:.[{[o].resq.run["test_forbidden.q";o];"unexpected success"};enlist opts;{[e]e}];
    .host.check[e like "resQ run:*";"invalid call accepted: ",.Q.s1 opts];
    .host.check[not .utl.pathExists "loaded.txt";"invalid call loaded tests"];
    .host.clean before;
 };
.host.validation:{[]
    .host.write["test_forbidden.q";enlist "`:loaded.txt 0: enlist \"loaded\";"];
    .host.reject each (42;enlist 1;("strict";"exit")!11b;
        (enlist `strict)!enlist 1;
        (enlist `isolate)!enlist 1b;
        (enlist `exit)!enlist 0b;
        (enlist `runCoverage)!enlist 1b;
        (enlist `seed)!enlist -1;
        (enlist `outDir)!enlist `a`b;
        (enlist `outDir)!enlist "";
        `strict`strict!01b);
    .host.write["test_nested.q";enlist ".tst.desc[\"nested\"]{should[\"reject nested\"]{e:@[{.resq.run[\"test_good.q\";()!()]};();{[e]e}];must[e like \"resQ run: an execution*\";\"nested call accepted\"]}};"];
    .host.expect["test_nested.q";()!();0;1];
    .tst.mock[`.application.busy;1];
    .host.reject ()!();
    .tst.restore[];
    .tst.coverageEnabled:1b;
    .host.reject ()!();
    .tst.coverageEnabled:0b;
    {[path]
        before:.host.snapshot[];
        e:.[{[p].resq.run[p;()!()];"unexpected success"};enlist path;{[e]e}];
        .host.check[e like "resQ run:*";"invalid paths accepted"];
        .host.clean before;
    } each (();"";42;`;("test_good.q";42));
    .host.expect["test_good.q";()!();0;1];
 };

.host.coverage:{[]
    .host.write["source.q";("\\d .application";"covered:{[x]x+1};";"\\d .")];
    .utl.require (system "cd"),"/source.q";
    original:.application.covered;
    .host.write["test_coverage.q";enlist ".tst.desc[\"coverage\"]{should[\"calls source\"]{.application.covered[1] musteq 2}};"];
    opts:`runCoverage`coverageSources`outDir!(1b;enlist "source.q";"coverage");
    .host.expect["test_coverage.q";opts;0;1];
    .host.check[any (read0 `:coverage/coverage.lcov) like "FNDA:1,*";"coverage hits missing"];
    .host.check[original~.application.covered;"coverage wrapper leaked"];
    .host.check[.utl.pathExists "coverage/coverage.json";"coverage evidence missing"];
    .host.expect["test_coverage.q";opts;0;1];
    .host.check[original~.application.covered;"second coverage wrapper leaked"];
    / A failed coverage helper must not strand a wrapper whose state is removed.
    .resq.require .resq.HOME,"/lib/coverage.q";
    .host.original:original;
    .host.assign:.tst.coverageAssign;
    `.tst.coverageAssign set {[name;definition]
        if[definition~.host.original;:`ok`error!(0b;"deliberate restore failure")];
        .host.assign[name;definition]};
    before:.host.snapshot[];
    r:.resq.run["test_coverage.q";opts];
    .host.check[1=r`exitCode;"coverage cleanup failure passed"];
    .host.check[any `cleanup=r[`results]`kind;"coverage cleanup failure not recorded"];
    .host.check[original~.application.covered;"failed coverage cleanup stranded wrapper"];
    .host.clean before;
    `.tst.coverageAssign set .host.assign;
    .host.expect["test_good.q";()!();0;1];
 };

.host.setupFailure:{[]
    original:.tst.initReporting;
    .tst.initReporting:{[]'"deliberate reporting setup failure"};
    before:.host.snapshot[];
    r:.resq.run["test_good.q";()!()];
    .host.check[1=r`exitCode;"setup failure passed"];
    .host.check[r[`frameworkError] like "*deliberate reporting setup failure*";"setup error missing"];
    .host.check[0=count r`results;"stale results after setup error"];
    .host.clean before;
    `.tst.initReporting set original;
    .host.expect["test_good.q";()!();0;1];
 };

.host.tempFailure:{[]
    old:getenv `TMPDIR;
    before:.host.snapshot[];
    setenv[`TMPDIR;.host.beforeCwd,"/absent"];
    r:.resq.run["test_good.q";()!()];
    setenv[`TMPDIR;old];
    .host.check[1=r`exitCode;"temporary directory failure passed"];
    .host.check[r[`frameworkError] like "temporary directory:*";"temporary directory error missing"];
    .host.check[0=count r`results;"temporary directory failure returned stale rows"];
    .host.clean before;
    .host.expect["test_good.q";()!();0;1];
 };
.host.qutil:{[]
    .host.expect["test_good.q";()!();0;1];
    .host.expect["test_bad.q";()!();1;2];
    .host.expect["test_good.q";()!();0;1];
    .host.write["module.q";enlist ".application.qutilLoaded:42;"];
    .utl.require (system "cd"),"/module.q";
    .host.check[42=.application.qutilLoaded;"host loader broken"];
    .host.check[.utl.DEBUG;"host debug option changed"];
 };

(get `$".host.",.z.x 1)[];
-1 "EMBEDDED_OK";
exit 0;
