.tst.desc["Load Error Test"]{
    should["record syntax errors when loading tests"]{
        code: "1+`a";
        res: @[value; code; {(`err0x; x)}];
        must[(2 = count res) and (first res) ~ `err0x; "Expected error trap to return err0x tuple"];
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
