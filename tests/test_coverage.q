/ Tests for the coverage subsystem's pure helpers and accounting.
/ Intentionally avoids the global instrumentation path (initCoverage,
/ wrapFunc) because those rewrite live function definitions and would
/ pollute the rest of the test session.

/ Coverage isn't loaded by default; pull it in here.
.utl.require .utl.PKGLOADING, "/coverage.q";

/ generateLCOV writes coverage_state.txt beside the requested LCOV file. Keep
/ both artifacts in a per-expectation temp directory so the framework's own
/ suite never dirties a checkout.
.tst.coverageTestCounter: 0;
.tst.coverageTestOutput:{[]
    .tst.coverageTestCounter+: 1;
    dir: .utl.tempRoot[], "/resq_coverage_unit_", string[.z.i], "_",
         string[.tst.coverageTestCounter], "_", string `long$.z.p;
    .utl.ensureDir dir;
    .tst.registerCleanup[{[p]
        safePrefix: .utl.tempRoot[], "/resq_coverage_unit_";
        if[p like safePrefix,"*";
            system "rm -rf -- ", .utl.shellQuote p]
    };enlist dir];
    dir, "/coverage.lcov"
 };

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

    should["derive aggregate line and function percentages from LCOV records"]{
        summary: .tst.coverageSummaryFromLines (
            "TN:resq"; "LF:3"; "LH:2"; "FNF:2"; "FNH:1";
            "LF:1"; "LH:1"; "FNF:2"; "FNH:2");
        summary[`linesFound] musteq 4;
        summary[`linesHit] musteq 3;
        summary[`linePercent] musteq 75f;
        summary[`functionsFound] musteq 4;
        summary[`functionsHit] musteq 3;
        summary[`functionPercent] musteq 75f;
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
        .tst.coverageData[`sample.q; `add] musteq 2;
        .tst.coverageData[`sample.q; `sub] musteq 1;
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
        .tst.coverageData: ()!();
        .tst.trackedFiles: ();
        .tst.origFuncs: ()!();
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
        fData: .tst.coverageData[.tst.covSym];
        fData[`.covscratch.expl] musteq 2;
        fData[`.covscratch.impl] musteq 1;
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
    fData1: .tst.coverageData[.tst.relSym];
    fData1[`.relscratch.add] musteq 1;

    / Reload the file: this installs a FRESH, UNWRAPPED `add`. The old guard
    / skipped re-wrapping (name still in origFuncs) so the live fn stayed
    / unwrapped and subsequent hits were lost. Re-instrument must re-wrap.
    system "l ", .tst.relSrc;
    .tst.instrumentFile .tst.relSrc;

    / The reloaded+re-wrapped fn must still compute correctly...
    .relscratch.add[3;4] musteq 7;
    / ...and the call must be counted (cumulative: 1 from before + 1 now).
    fData2: .tst.coverageData[.tst.relSym];
    must[fData2[`.relscratch.add] > 1; "hits must keep accruing after reload+re-instrument"];
  };

  should["not double-count a single call after re-instrument"]{
    / Re-instrument WITHOUT a reload: the live value is still our wrapper, so
    / wrapFunc must skip (no second layer of wrapping -> no double counting).
    .tst.instrumentFile .tst.relSrc;
    .tst.instrumentFile .tst.relSrc;
    hitsBefore: $[`.relscratch.add in key .tst.coverageData[.tst.relSym]; .tst.coverageData[.tst.relSym;`.relscratch.add]; 0];
    .relscratch.add[5;5];
    hitsAfter: .tst.coverageData[.tst.relSym;`.relscratch.add];
    (hitsAfter - hitsBefore) musteq 1;
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
        / Synthesize a tiny source file so exploreFile finds something.
        srcPath: .tst.tempFile ".q";
        (hsym `$srcPath) 0: ("/ sample"; "add:{[x;y] x+y}"; "id:{[v] v}");
        srcSym: `$":", srcPath;
        .tst.ensureCoverageEntry srcSym;
        .tst.coverageData[srcSym; `add]: 5;

        outPath: .tst.coverageTestOutput[];
        .tst.generateLCOV outPath;

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

/ An LCOV report with no records is the one coverage outcome that looks like
/ success while measuring nothing — the usual cause being source loaded through
/ a loader the instrumenting hook never sees (only `\l` / `system "l "` are
/ intercepted). generateLCOV warns in that case; here we pin the structural
/ facts it warns about.
.tst.desc["Coverage: empty report is detectable"]{
    before{
        `.tst.origCovData2 mock .tst.coverageData;
        `.tst.origCovFiles2 mock .tst.trackedFiles;
        `.tst.origCovEnabled2 mock .tst.coverageEnabled;
        / generateLCOV refuses to run unless coverage is on.
        .tst.coverageEnabled: 1b;
    };
    after{
        .tst.coverageData: .tst.origCovData2;
        .tst.trackedFiles: .tst.origCovFiles2;
        .tst.coverageEnabled: .tst.origCovEnabled2;
    };

    should["produce an LCOV with no SF records when nothing was instrumented"]{
        .tst.coverageData: ()!();
        .tst.trackedFiles: ();
        out: .tst.coverageTestOutput[];
        .tst.generateLCOV out;
        txt: "\n" sv read0 hsym `$out;
        must[not txt like "*SF:*";
             "an uninstrumented run must yield no SF records, got: ", txt];
    };

    should["produce SF records once a file has coverage data"]{
        / generateLCOV re-parses the source on disk for function names and line
        / numbers, so the file must really exist -- a recorded hit alone is not
        / enough to make a record.
        src: .tst.tempFile ".q";
        (hsym `$src) 0: (".probe.add:{[a;b] a+b};"; ".probe.sub:{[a;b] a-b};");

        .tst.coverageData: ()!();
        .tst.trackedFiles: ();
        .tst.coverageData[`$src]: (`$(".probe.add"; ".probe.sub"))!(2; 0);

        out: .tst.coverageTestOutput[];
        .tst.generateLCOV out;
        txt: "\n" sv read0 hsym `$out;
        must[txt like "*SF:*";   "an instrumented file must appear as an SF record"];
        must[txt like "*FNF:2*"; "both functions must be counted"];
        must[txt like "*FNH:1*"; "only the called function counts as hit"];
        must[txt like "*FNDA:2,.probe.add*"; "the call count must be reported per function"];
        must[txt like "*FNDA:0,.probe.sub*"; "an uncalled function must report zero hits"];
    };
 };

/ Two stacked bugs made .utl.require-loaded source permanently invisible to
/ coverage, and made instrumentLoadedFiles a no-op:
/   1. both paths were guarded by ``if[`tst in key `.]`` / ``if[`utl in key `.]``,
/      and `key `.` NEVER reports child namespaces (it is empty even when the
/      namespace exists), so the guards were always false;
/   2. behind that, the condition `p like "*.q" and not p like "*coverage.q"`
/      signalled 'type — q is right-to-left with uniform precedence, so it
/      parsed as `p like ("*.q" and (not p like "*coverage.q"))`.
/ Neither had a test, and `resq cover` looked fine because the `\l` path
/ (.tst.sysl) does not go through either of them.
.tst.desc["Coverage: namespace probing and require instrumentation"]{
    should["not use `key \\`.` to detect a namespace"]{
        / The idiom the bugs were built on. Pinning it here so the assumption is
        / recorded rather than rediscovered.
        must[not `tst in key `.;  "`key `.` does not report child namespaces"];
        must[0 < count key `.tst; "`key `.tst` does report its members"];
    };

    should["evaluate the require instrumentation condition without signalling"]{
        p: "/some/where/user_src.q";
        / Unparenthesised this throws 'type; the fix is the parentheses.
        r: @[{[x] (1b) and (x like "*.q") and (not x like "*coverage.q")}; p; {`$"THREW: ",x}];
        r musteq 1b;
        c: @[{[x] (1b) and (x like "*.q") and (not x like "*coverage.q")}; "/l/coverage.q"; {`$"THREW: ",x}];
        c musteq 0b;
    };

    should["skip resQ's own lib by default but not other files under the root"]{
        `.tst.origCovData3 mock .tst.coverageData;
        `.tst.origCovEnabled3 mock .tst.coverageEnabled;
        .tst.coverageEnabled: 1b;
        .tst.coverageData: ()!();

        home: @[get; `.resq.HOME; {""}];
        must[0 < count home; "this test needs .resq.HOME"];

        / A framework module: excluded.
        .tst.instrumentFile home, "/lib/diff.q";
        must[not (`$home, "/lib/diff.q") in key .tst.coverageData;
             "resQ's own lib must not be instrumented by default"];

        / A file under the install root that is NOT the framework: included.
        / (The bundled examples live here; excluding all of HOME hid them.)
        ex: home, "/examples/quickstart/src/gateway/auth.q";
        if[.utl.pathExists ex;
            .tst.instrumentFile ex;
            must[(`$ex) in key .tst.coverageData;
                 "a non-framework file under the install root must still be instrumented"];
        ];

        .tst.coverageData: .tst.origCovData3;
        .tst.coverageEnabled: .tst.origCovEnabled3;
    };
 };

/ LCOV must carry DA/LF/LH line records, not just function records: standard
/ coverage services key off line data and show nothing useful without it. The
/ records are DERIVED (a function's lines inherit its hit count) -- these tests
/ pin that derivation, including that an uncalled function reports zero.
.tst.desc["Coverage: LCOV line records"]{
    before{
        `.tst.origCovData4 mock .tst.coverageData;
        `.tst.origCovFiles4 mock .tst.trackedFiles;
        `.tst.origCovEnabled4 mock .tst.coverageEnabled;
        .tst.coverageEnabled: 1b;
    };
    after{
        .tst.coverageData: .tst.origCovData4;
        .tst.trackedFiles: .tst.origCovFiles4;
        .tst.coverageEnabled: .tst.origCovEnabled4;
    };

    should["emit DA lines spanning each function, with LF/LH totals"]{
        src: .tst.tempFile ".q";
        (hsym `$src) 0: (
            ".calc.add:{[a;b]";
            "    a+b";
            " };";
            "";
            "/ a comment line";
            ".calc.unused:{[a;b]";
            "    a*b";
            " };");

        .tst.coverageData: ()!();
        .tst.trackedFiles: ();
        .tst.coverageData[`$src]: (`$(".calc.add"; ".calc.unused"))!(3; 0);

        out: .tst.coverageTestOutput[];
        .tst.generateLCOV out;
        txt: read0 hsym `$out;

        must[any txt like "DA:1,3";  "the called function's first line must carry its hit count"];
        must[any txt like "DA:2,3";  "its body lines must carry the same count"];
        must[any txt like "DA:6,0";  "an uncalled function's lines must report zero"];
        / Blank and comment lines are not coverable and must not appear.
        must[not any txt like "DA:4,*"; "a blank line must not be a DA record"];
        must[not any txt like "DA:5,*"; "a comment line must not be a DA record"];
        must[any txt like "LF:*"; "a line-found total must be present"];
        must[any txt like "LH:*"; "a line-hit total must be present"];
    };

    should["report fewer hit lines than found when coverage is partial"]{
        src: .tst.tempFile ".q";
        (hsym `$src) 0: (".a.one:{[x] x+1 };"; ".a.two:{[x] x+2 };");
        .tst.coverageData: ()!();
        .tst.trackedFiles: ();
        .tst.coverageData[`$src]: (`$(".a.one"; ".a.two"))!(1; 0);

        out: .tst.coverageTestOutput[];
        .tst.generateLCOV out;
        txt: read0 hsym `$out;
        lf: "J"$ 3 _ first txt where txt like "LF:*";
        lh: "J"$ 3 _ first txt where txt like "LH:*";
        must[lf > 0;  "some lines must be found"];
        must[lh < lf; "an uncalled function must leave lines unhit"];
    };
 };

/ Statement-level instrumentation rewrites function bodies at load time, so the
/ splitter that decides where a probe may go is the safety-critical piece: it
/ must find real statement boundaries and must NOT descend into a conditional
/ EXPRESSION, whose branches are values rather than statements.
.tst.desc["Coverage: statement boundary detection"]{
    should["find top-level statements, ignoring nested and quoted semicolons"]{
        mk: {[lines] flip (1 + til count lines; lines)};
        (.tst.covStatementLines mk ("a: 1;"; "a+1"))                musteq 1 2;
        (.tst.covStatementLines mk ("s: \"a;b\";"; "s"))            musteq 1 2;
        (.tst.covStatementLines mk ("f: {[x] y: x*2; y+1};"; "f 3")) musteq 1 2;
        (.tst.covStatementLines mk ("a: 1;"; "/ note"; "a+1"))      musteq 1 3;
        (.tst.covStatementLines mk (enlist "a: 1; b: 2; a+b"))      musteq enlist 1;
    };

    should["descend into if/do/while bodies, which evaluate every argument"]{
        mk: {[lines] flip (1 + til count lines; lines)};
        (.tst.covStatementLines mk ("if[x<0;"; "  :`neg"; " ];"; "`pos")) musteq 1 2 4;
        (.tst.covStatementLines mk ("do[3;"; "  i+:1"; " ];"; "i"))       musteq 1 2 4;
        (.tst.covStatementLines mk ("while[c;"; "  i+:1"; " ];"; "i"))    musteq 1 2 4;
    };

    should["NOT descend into a conditional expression"]{
        / $[c;a;b] returns one of its branches. A probe inserted among them would
        / change what the expression evaluates to, so it must be left alone.
        mk: {[lines] flip (1 + til count lines; lines)};
        (.tst.covStatementLines mk ("r: $[x>0;"; "   \"pos\";"; "   \"neg\"];"; "r"))
            musteq 1 4;
    };

    should["place a nested statement's probe INSIDE its own construct"]{
        / Regression. Probes were inserted at the START of the line, so a
        / statement nested inside `if[...]` had its probe land in whatever
        / enclosed the line. For `$[c; if[a;b:1]; ...]` that put it in the
        / conditional expression's branch list, shifting every branch and
        / silently changing what the expression returned -- it broke resQ's own
        / loader. The probe must go at the statement's column, inside the if.
        src: (".f:{[x]";
              "    $[x;";
              "        if[x; y: 1];";
              "      z: 2];";
              " };");
        rw: .tst.covRewriteFunction[src; 1; 5; `$"/tmp/p.q"];
        must[2 = count rw; "the rewriter returns (text; probedLines)"];
        lines: "\n" vs rw 0;
        ifLine: first lines where lines like "*if*";
        / The probe must follow "if[x; ", not precede "if". (Two wildcards max:
        / q's `like` signals 'nyi on three or more.)
        trimmed: trim ifLine;
        must["if" ~ 2 # trimmed;
             "the line must still start with the construct, got: ", trimmed];
        must[trimmed like "*covL*";
             "the nested statement must carry a probe, got: ", trimmed];
    };

    should["place probes after the signature, never before the brace"]{
        src: (".f:{[x]"; "    y: x+1;"; "    y*2"; " };");
        rw: .tst.covRewriteFunction[src; 1; 4; `$"/tmp/probe.q"];
        must[2 = count rw; "the rewriter returns (text; probedLines)"];
        (rw 1) musteq 2 3;
        / rw 0 is already one joined string.
        txt: rw 0;
        firstLine: first "\n" vs txt;
        / `like` treats "[" as a char class, so compare the prefix directly.
        must[".f:{" ~ 4 # firstLine;
             "the signature must be untouched, got: ", firstLine];
        must[not (4 # firstLine) like "*covL*";
             "no probe may precede the opening brace"];
        must[any (("\n" vs txt) 1) like "*covL*";
             "the first body statement must carry a probe"];
    };
 };
