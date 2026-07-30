/ Tests for the coverage subsystem's pure helpers and accounting.
/ Intentionally avoids the global instrumentation path (initCoverage,
/ wrapFunc) because those rewrite live function definitions and would
/ pollute the rest of the test session.

/ Coverage isn't loaded by default; pull it in here.
.utl.require .utl.PKGLOADING, "/coverage.q";

.tst.desc["Coverage: scalar helpers"]{
    should["_covNumStr render a numeric count as a long string"]{
        / Multi-character results so we are unambiguously comparing strings
        / (q's single-char strings vs char atoms have asymmetric `~` semantics).
        .tst._covNumStr[42] musteq "42";
        .tst._covNumStr[1000] musteq "1000";
    };

    should["_covNameStr strip the leading backtick from a symbol's -3! form"]{
        .tst._covNameStr[`hello] musteq "hello";
        .tst._covNameStr[(`$".foo.bar")] musteq ".foo.bar";
    };

    should["resolvePath turn a relative path into an absolute one"]{
        rel: "lib/runner.q";
        / Avoid the name `abs` -- it is a q built-in and shadowing errors in some contexts.
        resolved: .tst.resolvePath rel;
        / Must start with "/" and contain the input as a suffix.
        must["/" = first resolved; "resolvePath should return an absolute path"];
        must[resolved like "*", rel; "resolvePath should preserve the input as a suffix"];
    };

    should["resolvePath strip the hsym ':' prefix"]{
        resolved: .tst.resolvePath ":lib/runner.q";
        / No remaining colons in the absolute path (other than possibly a Windows drive, n/a here).
        must[not ":" in resolved; "':' prefix should be stripped"];
    };
};

.tst.desc["Coverage: accounting"]{
    before{
        / Snapshot and reset state so this suite is hermetic.
        `.tst.origCovData mock .tst.coverageData;
        `.tst.origCovEnabled mock .tst.coverageEnabled;
        `.tst.origCovFiles mock .tst.trackedFiles;
        .tst.coverageData: ()!();
        .tst.trackedFiles: ();
        .tst.coverageEnabled: 1b;
    };
    after{
        .tst.coverageData: .tst.origCovData;
        .tst.coverageEnabled: .tst.origCovEnabled;
        .tst.trackedFiles: .tst.origCovFiles;
    };

    should["ensureCoverageEntry register a file once"]{
        .tst.ensureCoverageEntry `sample.q;
        .tst.ensureCoverageEntry `sample.q;
        (count .tst.trackedFiles) musteq 1;
        `sample.q mustin key .tst.coverageData;
    };

    should["recordExecution count repeated calls per function"]{
        .tst.recordExecution[`sample.q; `add];
        .tst.recordExecution[`sample.q; `add];
        .tst.recordExecution[`sample.q; `sub];
        fData:.tst.coverageFunctionData `sample.q;
        fData[`add] musteq 2j;
        fData[`sub] musteq 1j;
    };

    should["recordExecution be a no-op when coverage is disabled"]{
        .tst.coverageEnabled: 0b;
        .tst.recordExecution[`sample.q; `add];
        must[not `sample.q in key .tst.coverageData; "no entry should be created when disabled"];
    };
};

.tst.desc["Coverage: safeValue name resolution"]{
    should["resolve a dotted child-namespace name (the bug-1 regression)"]{
        / safeValue used to gate on `nsSym in key \`.`, which is false for a
        / dotted CHILD namespace, so it rejected EVERY .ns.fn and wrapped
        / nothing. A trapped get must resolve it now.
        `.covtest.fn set {[a;b] a+b};
        v: .tst.safeValue `.covtest.fn;
        must[not v ~ .tst._covMissing; "dotted name must resolve, not return the sentinel"];
        v[3;4] musteq 7;
        delete fn from `.covtest;
    };

    should["resolve a plain root-level name"]{
        `covtestRoot set {[x] x*x};
        v: .tst.safeValue `covtestRoot;
        must[not v ~ .tst._covMissing; "root name must resolve"];
        v[5] musteq 25;
        delete covtestRoot from `.;
    };

    should["return the sentinel for an unbound name"]{
        .tst.safeValue[`.covtest.doesNotExistXYZ] musteq .tst._covMissing;
    };
};

.tst.desc["Coverage: live instrumentation"]{
    before{
        `.tst.origCovData mock .tst.coverageData;
        `.tst.origCovEnabled mock .tst.coverageEnabled;
        `.tst.origCovFiles mock .tst.trackedFiles;
        `.tst.origCovOrig mock .tst.origFuncs;
        `.tst.origCovWrap mock .tst.covWrappers;
        .tst.coverageData: ()!();
        .tst.trackedFiles: ();
        .tst.origFuncs: ()!();
        .tst.covWrappers: ()!();
        .tst.coverageEnabled: 1b;

        / Scratch source: a \d-namespaced module mixing an explicit-arg fn, an
        / implicit-arg fn, a zero-arg fn, plus a non-function global that must be
        / skipped. Written then loaded so the definitions exist before wrapping.
        .tst.covSrc: .tst.tempFile ".q";
        (hsym `$.tst.covSrc) 0: (
            "\\d .covscratch";
            "expl:{[x;y] x+y};";
            "impl:{x*y};";
            "zero:{[] 99};";
            "notAFn: 123;";
            "\\d .");
        system "l ", .tst.covSrc;
        .tst.instrumentFile .tst.covSrc;
        .tst.covSym: `$.tst.resolvePath .tst.covSrc;
    };
    after{
        .tst.coverageData: .tst.origCovData;
        .tst.coverageEnabled: .tst.origCovEnabled;
        .tst.trackedFiles: .tst.origCovFiles;
        .tst.origFuncs: .tst.origCovOrig;
        .tst.covWrappers: .tst.origCovWrap;
        @[{delete covscratch from `.}; ::; {}];
    };

    should["wrap exactly the functions, skipping the non-function global"]{
        wrapped: key .tst.origFuncs;
        `.covscratch.expl mustin wrapped;
        `.covscratch.impl mustin wrapped;
        `.covscratch.zero mustin wrapped;
        must[not `.covscratch.notAFn in wrapped; "a non-function global must NOT be wrapped"];
    };

    should["keep wrapped functions computing the same result (explicit, implicit, zero-arg)"]{
        / Implicit-arg fns ARE wrapped: value[f] 1 resolves their arg names, so
        / the rebuilt {[x;y] ...} preserves rank and behaviour. No skipping.
        .covscratch.expl[3;4] musteq 7;
        .covscratch.impl[5;6] musteq 30;
        .covscratch.zero[] musteq 99;
    };

    should["record a hit per call under the source-file key"]{
        .covscratch.expl[1;1];
        .covscratch.expl[2;2];
        .covscratch.impl[2;3];
        / .covscratch.zero NOT called.
        fData:.tst.coverageFunctionData .tst.covSym;
        fData[`.covscratch.expl] musteq 2j;
        fData[`.covscratch.impl] musteq 1j;
        must[not `.covscratch.zero in key fData; "an uncalled fn records no hit"];
    };
};

.tst.desc["Coverage: reload + re-instrument (bug-1 regression)"]{
  before{
    `.tst.origCovData mock .tst.coverageData;
    `.tst.origCovEnabled mock .tst.coverageEnabled;
    `.tst.origCovFiles mock .tst.trackedFiles;
    `.tst.origCovOrig mock .tst.origFuncs;
    `.tst.origCovWrap mock .tst.covWrappers;
    .tst.coverageData: ()!();
    .tst.trackedFiles: ();
    .tst.origFuncs: ()!();
    .tst.covWrappers: ()!();
    .tst.coverageEnabled: 1b;

    / A simple \d-namespaced source, loaded then instrumented.
    .tst.relSrc: .tst.tempFile ".q";
    (hsym `$.tst.relSrc) 0: (
      "\\d .relscratch";
      "add:{[x;y] x+y};";
      "\\d .");
    system "l ", .tst.relSrc;
    .tst.instrumentFile .tst.relSrc;
    .tst.relSym: `$.tst.resolvePath .tst.relSrc;
  };
  after{
    .tst.coverageData: .tst.origCovData;
    .tst.coverageEnabled: .tst.origCovEnabled;
    .tst.trackedFiles: .tst.origCovFiles;
    .tst.origFuncs: .tst.origCovOrig;
    .tst.covWrappers: .tst.origCovWrap;
    @[{delete relscratch from `.}; ::; {}];
  };

  should["record hits again after a file reload + re-instrument"]{
    / First pass: a call records a hit under the source-file key.
    .relscratch.add[1;2];
    fData1:.tst.coverageFunctionData .tst.relSym;
    fData1[`.relscratch.add] musteq 1j;

    / Reload the file: this installs a FRESH, UNWRAPPED `add`. The old guard
    / skipped re-wrapping (name still in origFuncs) so the live fn stayed
    / unwrapped and subsequent hits were lost. Re-instrument must re-wrap.
    system "l ", .tst.relSrc;
    .tst.instrumentFile .tst.relSrc;

    / The reloaded+re-wrapped fn must still compute correctly...
    .relscratch.add[3;4] musteq 7;
    / ...and the call must be counted (cumulative: 1 from before + 1 now).
    fData2:.tst.coverageFunctionData .tst.relSym;
    must[fData2[`.relscratch.add] > 1; "hits must keep accruing after reload+re-instrument"];
  };

  should["not double-count a single call after re-instrument"]{
    / Re-instrument WITHOUT a reload: the live value is still our wrapper, so
    / wrapFunc must skip (no second layer of wrapping -> no double counting).
    .tst.instrumentFile .tst.relSrc;
    .tst.instrumentFile .tst.relSrc;
    fData:.tst.coverageFunctionData .tst.relSym;
    hitsBefore:$[
      `.relscratch.add in key fData;
      fData`.relscratch.add;
      0j];
    .relscratch.add[5;5];
    hitsAfter:
      (.tst.coverageFunctionData .tst.relSym)`.relscratch.add;
    (hitsAfter - hitsBefore) musteq 1j;
  };
 };

.tst.desc["Coverage: instrumentation restoration"]{
  before{
    `.tst.restoreCovEnabled mock .tst.coverageEnabled;
    `.tst.restoreCovOrigFuncs mock .tst.origFuncs;
    `.tst.restoreCovWrappers mock .tst.covWrappers;
    .tst.coverageEnabled:1b;
    .tst.origFuncs:()!();
    .tst.covWrappers:()!();
    .covrestore.target:{[x]x+1};
  };
  after{
    @[.tst.restoreCoverageInstrumentation;();{}];
    .tst.coverageEnabled:.tst.restoreCovEnabled;
    .tst.origFuncs:.tst.restoreCovOrigFuncs;
    .tst.covWrappers:.tst.restoreCovWrappers;
    @[{delete covrestore from `.};::;{}];
  };

  should["restore an owned wrapper and retire its tracking state"]{
    name:`.covrestore.target;
    original:get name;
    wrapper:{[x]x+10};
    name set wrapper;
    .tst.origFuncs[name]:original;
    .tst.covWrappers[name]:wrapper;

    .tst.restoreCoverageInstrumentation[];

    ((get name)5) musteq 6;
    must[not name in key .tst.origFuncs;
      "restored original remained registered"];
    must[not name in key .tst.covWrappers;
      "restored wrapper remained registered"];
    .tst.coverageEnabled musteq 0b;
  };

  should["preserve a caller replacement installed after instrumentation"]{
    name:`.covrestore.target;
    original:get name;
    wrapper:{[x]x+10};
    replacement:{[x]x*3};
    name set wrapper;
    .tst.origFuncs[name]:original;
    .tst.covWrappers[name]:wrapper;
    name set replacement;

    .tst.restoreCoverageInstrumentation[];

    ((get name)5) musteq 15;
    must[not name in key .tst.origFuncs;
      "caller-owned target remained registered"];
    must[not name in key .tst.covWrappers;
      "caller-owned wrapper remained registered"];
  };

  should["retain a failed owned restoration so cleanup can be retried"]{
    name:`.covrestore.target;
    original:get name;
    wrapper:{[x]x+10};
    name set wrapper;
    .tst.origFuncs[name]:original;
    .tst.covWrappers[name]:wrapper;
    outcome:.tst.mockTry[
      .tst.restoreCoverageInstrumentationWith;
      ({[target;originalValue]::};
       .tst.safeValue;
       .tst._covMissing;
       `coverageRestoreV1)];

    (first outcome) musteq `error;
    name mustin key .tst.origFuncs;
    name mustin key .tst.covWrappers;
    ((get name)5) musteq 15;

    .tst.restoreCoverageInstrumentation[];
    ((get name)5) musteq 6;
    must[not name in key .tst.origFuncs;
      "successful retry left original tracking behind"];
  };
};

.tst.desc["Coverage: LCOV generation"]{
    before{
        `.tst.origCovData mock .tst.coverageData;
        `.tst.origCovEnabled mock .tst.coverageEnabled;
        `.tst.origCovFiles mock .tst.trackedFiles;
        .tst.coverageEnabled: 1b;
        .tst.coverageData: ()!();
        .tst.trackedFiles: ();
    };
    after{
        .tst.coverageData: .tst.origCovData;
        .tst.coverageEnabled: .tst.origCovEnabled;
        .tst.trackedFiles: .tst.origCovFiles;
    };

    should["produce an LCOV file with the expected sections"]{
        / Derive a unique scratch directory from tempFile without creating the
        / seed path. Register cleanup for every known child before creating the
        / directory so partial setup and report failures remain hermetic.
        scratchSeed: .tst.tempFile ".coverage_seed";
        scratchRoot: scratchSeed, "_dir";
        srcPath: scratchRoot, "/source.q";
        outPath: scratchRoot, "/coverage.lcov";
        statePath: scratchRoot, "/coverage_state.txt";
        .tst.registerCleanup[{[paths]
            {[p] @[hdel; .utl.pathToHsym p; {}]} each paths;
          }; enlist (srcPath; outPath; statePath; scratchRoot)];
        .utl.ensureDir scratchRoot;

        / Synthesize a tiny source file so exploreFile finds something.
        (hsym `$srcPath) 0: ("/ sample"; "add:{[x;y] x+y}"; "id:{[v] v}");
        srcSym: `$":", srcPath;
        .tst.ensureCoverageEntry srcSym;
        fData:.tst.coverageFunctionData srcSym;
        fData[`add]:5j;
        .tst.coverageData[srcSym]:enlist fData;

        .tst.generateLCOV outPath;

        must[.utl.pathExists statePath; "coverage state should be written beside the LCOV file"];
        must[
            .tst.resolvePath[statePath] like .tst.resolvePath[scratchRoot], "/*";
            "coverage state should stay inside the per-test scratch directory"];

        lines: read0 hsym `$outPath;
        / Must include the LCOV preamble, an SF: header for our file, and the
        / FN/FNDA records for the function we registered.
        first[lines] musteq "TN:resq";
        must[any lines like "SF:*", srcPath; "SF: line should reference the synth source"];
        must[any lines like "FN:*add"; "FN: line should list the add function"];
        must[any lines like "FNDA:5,*add"; "FNDA: line should record 5 hits for add"];
        must[any lines like "end_of_record"; "record should be terminated"];
    };
};
