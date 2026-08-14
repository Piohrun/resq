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
