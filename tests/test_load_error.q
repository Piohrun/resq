.tst.desc["Load Error Test"]{
    should["record syntax errors when loading tests"]{
        code: "1+`a";
        res: @[value; code; {(`err0x; x)}];
        must[(2 = count res) and (first res) ~ `err0x; "Expected error trap to return err0x tuple"];
    };

    should["standalone init load"]{
        wd:.utl.tempRoot[],"/resq_standalone_init_",(string .z.i),"_",string["j"$.z.p];
        script:wd,"/probe.q";
        output:wd,"/output.txt";
        .utl.ensureDir wd;
        (hsym `$script) 0:(
            "ok:(0=count .resq.state.results) and all `deferred`resolve`loadFixture`asserts in key `.tst;";
            "-1 \"STANDALONE_INIT=\",string ok;";
            "exit not ok;");
        command:"true && cd ",.utl.shellQuote[.utl.tempRoot[]]," && timeout -k 2 30 q ",
            .utl.shellQuote[.resq.HOME,"/lib/init.q"]," < ",.utl.shellQuote[script],
            " > ",.utl.shellQuote[output]," 2>&1; echo $?";
        status:"J"$last @[system;command;{[error]enlist "-1"}];
        lines:@[read0;hsym `$output;{()}];
        if[wd like "*/resq_standalone_init_*";system "rm -rf -- ",.utl.shellQuote wd];
        status musteq 0;
        must[any lines like "*STANDALONE_INIT=1*";
             "absolute standalone init failed outside the checkout: ","\n" sv lines];
    };
};

.tst.desc["oversized desc block diagnostics"]{
  should["explain a per-lambda limit without a subprocess"]{
    hint:.tst.limitLoadErrorHint "limit (near line 1)";
    hint mustlike "*desc block is a single q lambda*";
    hint mustlike "*Split it into several desc blocks*";
    .tst.limitLoadErrorHint["type"] musteq "type";
  };
 };

/ ---------------------------------------------------------------------------
/ A line containing only "/" opens a q BLOCK COMMENT, closed only by a lone "\".
/ In a library file that silently truncates the module: `system "l"` still
/ reports success, so half the definitions simply never appear. It has bitten
/ this codebase twice — once in deps.q, once in coverage.q, the latter surfacing
/ only as a vague "LCOV generator not available" much later in the run.
/ Cheaper to forbid the pattern than to debug it again.
/ ---------------------------------------------------------------------------
.tst.desc["library sources contain no accidental block comments"]{
  should["have no line consisting solely of a forward slash"]{
    libDir: .resq.HOME, "/lib";
    files: .tst.static.findSources libDir;
    files: files where files like "*.q";
    offenders: raze {[f]
        lines: @[read0; hsym f; {()}];
        hits: where {"/" ~ .tst.rstrip .tst.lstrip x} each lines;
        $[count hits;
            enlist (string f; hits);
            ()]
      } each files;
    must[0 = count offenders;
         "a lone \"/\" opens a block comment and truncates the file: ",
         .Q.s1 offenders];
  };

  should["report an incompletely loaded coverage module by name"]{
    / The runner checks coverage's entry points after loading precisely because
    / a truncated load looks like success. Pin the export list it checks.
    expected: `initCoverage`instrumentFile`generateLCOV`generateHTML;
    .utl.require .utl.PKGLOADING, "/coverage.q";
    missing: expected where not expected in key `.tst;
    must[0 = count missing;
         "coverage.q must export its entry points, missing: ", .Q.s1 missing];
  };
 };

.tst.desc["comments at column 1 inside a test block"]{
  should["leave a commented-out assertion alone"]{
    src: (".tst.desc[\"d\"]{"; "  should[\"a\"]{"; "    r: 1+1;"; "/    r musteq 3;"; "    r musteq 2;"; "  };"; " };");
    out: .tst.preprocessScript src;
    (out 3) musteq "/    r musteq 3;";
    (any out like "*.tst.dsl.musteq?r;? 2;*") musteq 1b;
  };
  should["leave prose that mentions mock, with a lone quote, alone"]{
    src: (".tst.desc[\"d\"]{"; "  should[\"a\"]{"; "/ TODO: mock the feed; the 12\" disk case"; "    1 musteq 1;"; "  };"; " };");
    out: .tst.preprocessScript src;
    (out 2) musteq "/ TODO: mock the feed; the 12\" disk case";
    (any out like "*.tst.dsl.musteq?1;? 1;*") musteq 1b;
  };
 };

/ A test file that replaces a resQ function by accident (a helper named like
/ an internal) used to end the run with a raw q error and no report, because
/ the code that reports errors went through the function it had replaced.
.tst.testState.clobber.canRun:
    (0 < count @[system; "which q 2>/dev/null"; {()}]) and
    (0 < count @[system; "which timeout 2>/dev/null"; {()}]);

.tst.testState.clobber.run:{[]
    wd: .resq.util.tempRoot[], "/resq_clobber_", string[.z.i], "_", string `long$.z.p;
    .resq.util.ensureDir wd;
    (hsym `$wd, "/test_a.q") 0: (
        ".tst.toString:{[x] string x};";
        ".tst.desc[\"uses a helper named like a resQ internal\"]{ should[\"a\"]{ 1 musteq 1; }; };");
    (hsym `$wd, "/test_b.q") 0: enlist
        ".tst.desc[\"an ordinary suite\"]{ should[\"still runs\"]{ 1 musteq 1; }; };";
    cmd: "true && timeout -k 2 60 q ", (.resq.util.shellQuote .resq.HOME, "/resq.q"),
         " test ", (.resq.util.shellQuote wd), " -json -outDir ", (.resq.util.shellQuote wd, "/out"),
         " -state-file ", .resq.util.shellQuote[wd, "/out/state.json"],
         " -flake-history ", .resq.util.shellQuote[wd, "/out/flake.json"],
         " -quarantine-file ", .resq.util.shellQuote[wd, "/out/quarantine.json"],
         " -flake-proposal-file ", .resq.util.shellQuote[wd, "/out/proposals.json"],
         " > ", (.resq.util.shellQuote wd, "/out.txt"), " 2>&1; echo $?";
    exitLines: @[system; cmd; {[err] enlist "-1"}];
    output: "\n" sv @[read0; hsym `$wd, "/out.txt"; {()}];
    rawJson: @[read0; hsym `$wd, "/out/test-results.json"; {()}];
    payload: $[count rawJson; .j.k raze rawJson; ()!()];
    if[wd like "*/resq_clobber_*"; system "rm -rf -- ", .resq.util.shellQuote wd];
    `code`output`rows!("J"$last exitLines; output; $[`tests in key payload; payload`tests; ()])
 };

.tst.desc["a test file that replaces a resQ function by accident #slow"]{
  should["fail that file by name, keep the report, and run the other files"]{
    if[not .tst.testState.clobber.canRun; :must[1b; "q or timeout unavailable"]];
    r: .tst.testState.clobber.run[];
    r[`code] musteq 4;
    (0 < count r[`output] ss "redefines resQ internal .tst.toString") musteq 1b;
    (0 < count r[`output] ss "rename the helper") musteq 1b;
    statuses: {x`status} each r[`rows] where {x[`description] like "still runs"} each r`rows;
    statuses musteq enlist "pass";
  };
 };
