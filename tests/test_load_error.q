.tst.desc["Load Error Test"]{
    should["record syntax errors when loading tests"]{
        code: "1+`a";
        res: @[value; code; {(`err0x; x)}];
        must[(2 = count res) and (first res) ~ `err0x; "Expected error trap to return err0x tuple"];
    };
};

/ ---------------------------------------------------------------------------
/ A desc block is a single q lambda, so a large suite file eventually exceeds
/ q's per-lambda capacity and signals 'limit -- reported against line 1, where
/ the desc opens, which tells the reader nothing about the real cause. The
/ loader appends the explanation and the fix. (q's limit, not resQ's: it cannot
/ be raised, only explained.)
/ ---------------------------------------------------------------------------
.tst.testState.limitchk.canQ: 0 < count @[system; "which q 2>/dev/null"; {()}];

.tst.desc["oversized desc block reports a usable error #slow"]{
  skipIf[not .tst.testState.limitchk.canQ;
         "a desc block past q's lambda capacity explains itself"]{
    wd: .utl.tempRoot[], "/resq_limit_", string[.z.i], "_", string `long$.z.p;
    fix: wd, "/test_big.q";
    system "mkdir -p ", wd;
    body: enlist ".tst.desc[\"too big\"]{";
    body,: {[i] "  should[\"t", string[i], "\"]{ 1 musteq 1 };"} each til 150;
    body,: enlist " };";
    (hsym `$fix) 0: body;

    cmd: "true && timeout 60 q ", (.utl.shellQuote .resq.HOME, "/resq.q"),
         " test ", (.utl.shellQuote fix), " -quiet > ",
         (.utl.shellQuote wd, "/out.txt"), " 2>&1; echo $?";
    code: "J"$ last @[system; cmd; {[e] enlist "-1"}];
    out: @[read0; hsym `$wd, "/out.txt"; {()}];
    system "rm -rf -- ", .utl.shellQuote wd;

    must[0 <> code; "an unloadable file must fail the run"];
    must[any out like "*desc block is a single q lambda*";
         "the error must name the real cause"];
    must[any out like "*Split it into several desc blocks*";
         "the error must state the fix"];
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
