if[not `utl in key `; .utl:(enlist `)!enlist (::)];
/ Anchor module loads at the install root if it has been set (by resq.q).
/ Falls back to "lib" for direct `q lib/init.q` usage from inside the repo.
.utl.resqHomeAtBoot: @[get; `.resq.HOME; {""}];
if[not `PKGLOADING in key .utl; .utl.PKGLOADING: $[count .utl.resqHomeAtBoot; .utl.resqHomeAtBoot,"/lib"; "lib"]];
.utl.DEBUG: 0b;

/ Initialize .resq sub-namespaces. Each guarded independently because
/ resq.q sets .resq.HOME before init.q runs, so a coarse `resq in key \``
/ check would skip seeding state/config.
if[not `resq in key `; .resq.tmp:1];
if[not `state in key `.resq; .resq.state.tmp:1];
if[not `config in key `.resq; .resq.config.tmp:1];
.resq.VERSION: "1.0.0";

/ Exit code constants for CI/CD integration. Only codes actually emitted by the
/ dispatcher (resq.q) are defined; 2 (CONFIG_ERROR) and 5 (PARTIAL) had no
/ emitting code path and were removed.
.resq.EXIT.PASS: 0;        / All tests passed
.resq.EXIT.FAIL: 1;        / One or more tests failed
.resq.EXIT.NO_TESTS: 3;    / No tests found (strict mode)
.resq.EXIT.LOAD_ERROR: 4;  / File load/syntax error

.resq.state.results: .resq.state.emptyResults[];
if[not `fmt in key .resq.config; .resq.config.fmt: `text; .resq.config.outDir: ":."];

/ Project Libraries
.utl.require .utl.PKGLOADING,"/mock.q"
.utl.require .utl.PKGLOADING,"/benchmark.q"
.utl.require .utl.PKGLOADING,"/promise.q"
.utl.require .utl.PKGLOADING,"/fixture.q"
.utl.require .utl.PKGLOADING,"/diff.q"
.utl.require .utl.PKGLOADING,"/snapshot.q"
.utl.require .utl.PKGLOADING,"/snapshot_txt.q"
.utl.require .utl.PKGLOADING,"/dsl/internals.q"
.utl.require .utl.PKGLOADING,"/output/sanitize.q"
.utl.require .utl.PKGLOADING,"/benchmark_regression.q"
.utl.require .utl.PKGLOADING,"/snapshot_inventory.q"
.utl.require .utl.PKGLOADING,"/events.q"
.utl.require .utl.PKGLOADING,"/output/text.q"
.utl.require .utl.PKGLOADING,"/dsl/assertions.q"
.utl.require .utl.PKGLOADING,"/deps.q"
.utl.require .utl.PKGLOADING,"/diff_assertions.q"
.utl.require .utl.PKGLOADING,"/watch.q"
.utl.require .utl.PKGLOADING,"/dsl/ui.q"
.utl.require .utl.PKGLOADING,"/dsl/spec.q"
.utl.require .utl.PKGLOADING,"/dsl/expec.q"
.utl.require .utl.PKGLOADING,"/dsl/fuzz.q"
.utl.require .utl.PKGLOADING,"/dsl/generators.q"
.utl.require .utl.PKGLOADING,"/quarantine.q"
.utl.require .utl.PKGLOADING,"/rerun.q"
.utl.require .utl.PKGLOADING,"/loader.q"
.utl.require .utl.PKGLOADING,"/test_finder.q"
.utl.require .utl.PKGLOADING,"/isolate.q"

/ Alias .resq expansion functions to .tst for backward compatibility with example tests
if[`resq in key `;
    / Fix: Use key `.resq to get symbols in namespace
    { if[not x in key `.tst; .[`.tst; (enlist x); :; get ` sv `.resq, x]] } each key `.resq;
 ];

/ The text reporter (lib/output/text.q, loaded above) defines .resq.reportText
/ and aliases .resq.report to it. We just need the bookkeeping state here.
.tst.app.loadErrors: flip `file`error`type!(`symbol$(); (); `symbol$());
/ Benchmark measurements from perf blocks. A perf block used to compute its
/ averages and discard them unless a budget was breached, so a passing
/ benchmark left no record and performance could be gated but never tracked.
.tst.app.emptyPerfResults:{[]
    fields:`benchmarkId`testId`file`suite`description`metric`unit`runs,
        `avgTimeMs`minTimeMs`medTimeMs`maxTimeMs`devTimeMs,
        `avgSpaceBytes`maxSpaceBytes`timeLimitMs`spaceLimitBytes,
        `workload`samples`measurement`environment`comparison;
    values:(
        ();();();`symbol$();`symbol$();`symbol$();();`long$();
        `float$();`float$();`float$();`float$();`float$();
        `float$();`float$();`float$();`float$();();();();();());
    flip fields!values
 };
.tst.app.perfResults: .tst.app.emptyPerfResults[];
if[not `strict in key .tst.app; .tst.app.strict: 0b];

/ Legacy explicit .q snapshot helpers. resQ itself never calls saveOriginalQ:
/ normal framework loading and execution must leave reserved .q untouched.
.tst.saveOriginalQ:{[ks]
    if[not `originalQ in key `.tst; .tst.originalQ:: (`symbol$())!()];
    / Defensive: reset if corrupted by mocks or bad state
    if[not 99h = type .tst.originalQ; .tst.originalQ:: (`symbol$())!()];

    / Default to every current .q key when called without an explicit set.
    qKeys: $[(::) ~ ks; key `.q; ks];
    / Coerce skip set to a symbol vector so `in` never sees a general-empty
    / list (key of an empty general dict is type 0h, which breaks `in`).
    skipKeys: distinct (`symbol$()), (),key .tst.originalQ;
    qKeys: (),qKeys;
    qKeys: qKeys where not qKeys in skipKeys;

    if[0<count qKeys;
        vals: {@[get; ` sv `.q,x; {`NOTFOUND}]} each qKeys;
        mask: not vals ~\: `NOTFOUND;
        if[any mask;
            newItems: (qKeys where mask)!(vals where mask);
            .tst.originalQ:: .tst.originalQ, newItems;
            if[.utl.DEBUG;
                -1 "INFO: resQ captured ", string[count newItems], " new .q original functions."];
        ];
    ];
 };

/ Restore only values captured by an explicit saveOriginalQ call. There is no
/ export-derived neutralization: setting a .q member to :: still reserves the
/ identifier and was the root cause of the old adoption failure.
.tst.restoreOriginalQ:{[]
    transient: $[`originalQ in key `.tst; .tst.originalQ; (`symbol$())!()];
    if[not 99h = type transient; transient: (`symbol$())!()];
    if[0 < count transient;
        {[k;v]
            qName: ` sv `.q,k;
            @[qName set; v; { [name; e] -1 "ERROR: Failed to reset ",string[name],": ",e }[qName]];
        }'[key transient; value transient];
    ];
    if[`originalQ in key `.tst; delete originalQ from `.tst];
    ::
 };

.tst.die:{[x] 
    exit x
 };

/ Canonical public DSL table. Test-source preprocessing binds these names to
/ their stable .tst spellings while respecting file-declared locals, so reserved
/ .q remains byte-for-byte equivalent.
if[not `dslExports in key `.tst; .tst.dslExports: (`symbol$())!()];

.tst.registerDslExports:{[exports]
    if[not 99h = type exports; '`type];
    .tst.dslExports: .tst.dslExports, exports;
    ::
 };

/ Deprecated configuration shim. Both values are safe and equivalent; true is
/ accepted for migration but can no longer authorize writes to reserved .q.
if[not `qNamespaceExports in key `.tst; .tst.qNamespaceExports: 0b];
.tst.setQNamespaceExports:{[enabled]
    .tst.qNamespaceExports: 0b;
    if[1b ~ enabled;
        -1 "CONFIG WARNING: qNamespaceExports is deprecated and ignored; resQ never writes to reserved .q."];
    ::
 };

.tst.registerDslExports .tst.asserts,
  `mock`fixture`fixtureAs`tempFile`registerCleanup`registerSpecCleanup!(
    .tst.mock;
    .tst.fixture;
    .tst.fixtureAs;
    .tst.tempFile;
    .tst.registerCleanup;
    .tst.registerSpecCleanup);

if[`uiExports in key `.tst; .tst.registerDslExports .tst.uiExports];

/ Give every canonical export an immutable-by-convention binding under
/ .tst.dsl. This preserves qspec's value-copy behavior: mocking `.tst.mock does
/ not also replace a bare `mock` call compiled from test source. Existing direct
/ .tst APIs keep their normal, explicitly mockable spellings.
{[k;v] (` sv `.tst.dsl,k) set v}'[
    key .tst.dslExports; value .tst.dslExports];

/ Root aliases preserve direct/root-context compatibility without reserving q
/ locals (only members of reserved .q have that parser behavior).
(` sv `.,`mock) set .tst.mock;
(` sv `.,`fixture) set .tst.fixture;
(` sv `.,`fixtureAs) set .tst.fixtureAs;
(` sv `.,`tempFile) set .tst.tempFile;
(` sv `.,`registerCleanup) set .tst.registerCleanup;
(` sv `.,`registerSpecCleanup) set .tst.registerSpecCleanup;

.tst.PKGNAME: .utl.PKGLOADING

.tst.loadOutputModule:{[module]
  requestedModule:$[10h = type module; lower `$module; -11h = type module; lower module; 11h = type module; lower module; `text];
  knownModule: requestedModule in `text`console`xml`junit`xunit`json;
  if[not knownModule;
    -1 "WARNING: Unknown output module '",(string requestedModule),"'."
  ];
  if[not knownModule; :0b];
  outputModule:$[requestedModule ~ `console; `text; requestedModule ~ `xml; `junit; requestedModule];

  modulePath: .tst.PKGNAME, "/output/", (string outputModule), ".q";
  .utl.require[modulePath];
  outputLoaded: any modulePath ~/: .utl.loaded;
  if[not outputLoaded; -1 "WARNING: Output module not available: ", string outputModule];
  if[not outputLoaded; :0b];

  / .utl.require is idempotent, so a module loaded earlier in this process
  / would not re-run and .tst.output.top would keep the previous format.
  / Verify the format's named export exists and re-select it explicitly.
  exportValue:$[
    outputModule~`text;
      @[get;`.resq.reportText;{[err]0b}];
    outputModule~`json;
      @[get;`.resq.reportJson;{[err]0b}];
    outputModule~`junit;
      @[get;`.tst.output.junitTop;{[err]0b}];
    outputModule~`xunit;
      @[get;`.tst.output.xunitTop;{[err]0b}];
    0b];
  exportReady:type[exportValue] in 100 104h;
  if[not exportReady;
    -1 "WARNING: Output module export unavailable: ",string outputModule;
    :0b
  ];
  if[outputModule~`junit;
    .tst.output.top:.tst.output.junitTop];
  if[outputModule~`xunit;
    .tst.output.top:.tst.output.xunitTop];
  1b
 }
