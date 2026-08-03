/ tests/hardening/test_stack_trace_phase2.q
/ Runtime backtraces and enhanced assertions.

/ Named helpers are intentional: the contract is that a trapped runtime error
/ retains the nested q frames a user needs to diagnose it.
.tst.stackFixtureLeaf:{[] '"resq_nested_trace_boom"};
.tst.stackFixtureMiddle:{[] .tst.stackFixtureLeaf[]};
.tst.stackFixtureOuter:{[] .tst.stackFixtureMiddle[]};

.tst.desc["Stack Trace Support"]{
    should["return string from stackTrace"]{
        trace: .tst.stackTrace[];
        / stackTrace should return a string (type is 10h for char list)
        t: type trace;
        musteq[1b; t in 10 -10h];
    };
    
    should["return non-error value"]{
        res: @[.tst.stackTrace; (); {[e] e}];
        / Should not throw errors - result type should be string or empty string
        musteq[1b; 10h = abs type res];
    };

    should["retain nested function frames at the real test-body trap boundary"]{
        expec: .tst.internals.testObj,
            `desc`code!("nested runtime error";.tst.stackFixtureOuter);
        outcome: @[
            {[e] (`ok;.tst.runners[`test] e)};
            expec;
            {[err] (`error;err)}];
        musteq[`error; first outcome];
        diagnostic: .tst.pendingBacktrace;
        .tst.pendingBacktrace: "";
        must[0 < count ss[diagnostic;"resq_nested_trace_boom"];
             "the original q error must survive"];
        must[0 < count ss[diagnostic;"Q Backtrace:"];
             "the diagnostic must label the formatted q backtrace"];
        must[0 < count ss[diagnostic;".tst.stackFixtureLeaf"];
             "the leaf frame must survive: ",diagnostic];
        must[0 < count ss[diagnostic;".tst.stackFixtureMiddle"];
             "the middle frame must survive: ",diagnostic];
        must[0 < count ss[diagnostic;".tst.stackFixtureOuter"];
             "the outer frame must survive: ",diagnostic];
        / The runner's own dispatch frames are noise: always the same, never
        / actionable, and long enough (~30 of ~85 lines) to push the frames that
        / matter off the screen. The outermost run of them is dropped, with a
        / visible count. Note this expectation calls the runner from INSIDE the
        / runner, so a few lib frames legitimately remain -- they have this
        / test's own frames outside them, and the trim is deliberately
        / conservative about anything bracketed by user code. The clean-shape
        / case is pinned exactly in "trim the runner tail" below.
        must[0 = count ss[diagnostic; .resq.HOME, "/resq.q:"];
             "the outermost resq.q entry frame must be trimmed: ",diagnostic];
        must[0 < count ss[diagnostic;"resQ runner frame"];
             "the omission must be stated, not silent: ",diagnostic];
    };

    should["trim the runner tail from a real-shaped backtrace"]{
        / The exact layout .Q.sbt produces for an error in a test body: user
        / frames, then the runner's dispatch out to process entry.
        formatted: "\n" sv (
            "  [23] .deep.leaf:{[] '\"BOOM\"}";
            "                      ^";
            "  [22] { .deep.leaf[] }";
            "         ^";
            "  [21] ", .resq.HOME, "/lib/dsl/expec.q:248: .tst.finishFixtureTest:";
            " $[count args; func . args; func[]];";
            "  [20] (.Q.trp)";
            "";
            "  [19] ", .resq.HOME, "/lib/runner.q:291: .tst.runSpec:";
            "  [18] (.q.each)";
            "";
            "  [17] ", .resq.HOME, "/resq.q:159: ");
        trimmed: .tst.trimRunnerFrames formatted;
        must[0 = count ss[trimmed; .resq.HOME];
             "no framework frame may survive a clean tail: ",trimmed];
        must[0 = count ss[trimmed;"(.Q.trp)"];
             "the .Q.trp hop must go with the tail: ",trimmed];
        must[0 < count ss[trimmed;".deep.leaf"];
             "the user's frames must survive: ",trimmed];
        / NB: no "[" or "]" in an `ss` needle -- they are wildcard syntax there,
        / and an empty class signals rather than matching literally.
        must[0 < count ss[trimmed;"22"];
             "the test-body frame must survive: ",trimmed];
        must[0 < count ss[trimmed;"5 resQ runner frames omitted"];
             "the omitted count must be exact: ",trimmed];
    };

    should["keep a q primitive hop that sits between the user's own frames"]{
        expec: .tst.internals.testObj,
            `desc`code!("each in user code";{[] .tst.stackFixtureLeaf each 1 2 3});
        @[{[e] .tst.runners[`test] e}; expec; {[err] err}];
        diagnostic: .tst.pendingBacktrace;
        .tst.pendingBacktrace: "";
        must[0 < count ss[diagnostic;".tst.stackFixtureLeaf"];
             "the user's leaf frame must survive: ",diagnostic];
        / (.q.each) has no source location, so it is transparent to the trim
        / scan -- but only as part of the runner tail. Here it is bracketed by
        / user frames and must be kept.
        must[0 < count ss[diagnostic;"(.q.each)"];
             "a primitive hop inside user code must survive: ",diagnostic];
    };

    should["leave a trace with no user frames untouched"]{
        / An error raised entirely inside resQ is the one case where the runner
        / frames ARE the evidence. Trimming must fail open rather than erase it.
        frames: enlist enlist "  [3]  ", .resq.HOME, "/lib/runner.q:1: .tst.x:";
        formatted: "\n" sv raze frames;
        musteq[formatted; .tst.trimRunnerFrames formatted];
    };

    should["leave an unrecognised backtrace layout untouched"]{
        formatted: "not a backtrace at all";
        musteq[formatted; .tst.trimRunnerFrames formatted];
    };

    should["match install paths literally, including bracket characters"]{
        / The frame test compares filesystem paths, so it must not go through
        / `ss`, where "[" opens a character class. A checkout under a bracketed
        / directory is legal and must still have its runner frames recognised.
        hay: "/home/u/my[proj]/lib/x.q:1: .tst.f:";
        must[.tst.literalIn["my[proj]/lib/"; hay]; "bracketed path must match"];
        must[not .tst.literalIn["my[proj]/nope/"; hay]; "must not over-match"];
        must[.tst.literalIn[""; "abc"]; "an empty needle matches"];
        must[not .tst.literalIn["abcd"; "abc"]; "a needle longer than the text cannot match"];
    };
};

.tst.desc["Enhanced Assertion Messages"]{
    should["musteq exists and is callable"]{
        / Verify musteq is defined in .tst namespace - type 100h is function
        musteq[100h; type .tst.asserts`musteq];
    };
};
