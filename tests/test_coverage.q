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
        .tst.coverageData[`sample.q; `add] musteq 2;
        .tst.coverageData[`sample.q; `sub] musteq 1;
    };

    should["recordExecution be a no-op when coverage is disabled"]{
        .tst.coverageEnabled: 0b;
        .tst.recordExecution[`sample.q; `add];
        must[not `sample.q in key .tst.coverageData; "no entry should be created when disabled"];
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

        outPath: .tst.tempFile ".lcov";
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
