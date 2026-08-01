.tst.desc["Dependency Graph Analysis"]{
  should["parse load directives from file"]{
    testContent: ("\\l lib/mock.q"; ".utl.require \"lib/fixture.q\"; someCode: 1+1");
    tmpFile: .tst.tempFile ".q";
    (hsym `$tmpFile) 0: testContent;
    
    deps: .tst.parseLoadDirectives tmpFile;
    
    expected: (`$"lib/mock.q"; `$"lib/fixture.q");
    mustmatch[deps; expected];
  };

  should["build dependency graph for directory"]{
    / Scan the install-root lib so the test works regardless of CWD.
    .tst.rebuildGraph enlist .utl.PKGLOADING;

    mustgt[count key .tst.depGraph; 0];
    mustgt[count key .tst.dependencies; 0];
  };

  should["find dependents of a file by real resolved path"]{
    .tst.rebuildGraph enlist .utl.PKGLOADING;
    / Require targets are now resolved to the same absolute path form used for
    / graph keys, so the graph is traversable by real path. static_analysis.q
    / is required by loader_discovery.q (among others).
    saPath: `$.utl.PKGLOADING, "/static_analysis.q";
    dependents: .tst.getDependents saPath;
    mustgt[count dependents; 0];
    ldPath: `$.utl.PKGLOADING, "/loader_discovery.q";
    must[ldPath in dependents; "loader_discovery.q must be a dependent of static_analysis.q"];
  };

  should["build a traversable, star-free graph"]{
    .tst.rebuildGraph enlist .utl.PKGLOADING;
    g: .tst.depGraph;
    / Keys and dependency targets share a vocabulary -> non-empty overlap.
    overlap: (key g) inter distinct raze value g;
    mustgt[count overlap; 0];
    / No "*"-patterned fake keys ingested from detection literals.
    starKeys: (key g) where {"*" in x} each string each key g;
    (count starKeys) musteq 0;
  };

  should["survive a circular dep graph without stack overflow"]{
    / Save and restore depGraph so we don't poison later tests.
    .tst.savedGraph: .tst.depGraph;
    .tst.depGraph: `a`b`c!(enlist `b; enlist `c; enlist `a);
    deps: .tst.getDependents `a;
    .tst.depGraph: .tst.savedGraph;
    must[all `a`b`c in deps; "a cycle must still yield every reachable dependent"];
  };
};

/ The scanner locates directives in MASKED source, so a require that is only
/ mentioned -- in a comment, a string, a block comment, or after the script
/ terminator -- is not an edge. The previous `like`-on-raw-lines scanner had to
/ skip any line containing "like" to avoid ingesting its own detection
/ patterns, which also silently dropped real requires from such lines.
.tst.desc["Dependency directive masking"]{
  should["ignore requires that are only mentioned, not executed"]{
    / `enlist` on the one-character lines: in q source "/" and "\\" are char
    / ATOMS, and a list mixing atoms with strings is not writable by `0:`.
    src: (
      "/ a comment naming .utl.require \"ghost_comment.q\"";
      ".utl.require \"real_one.q\"";
      "msg: \".utl.require \\\"ghost_string.q\\\"\"";
      "scanner: {[l] l like \"*.utl.require*\"}";
      enlist "/";
      "block comment with .utl.require \"ghost_block.q\"";
      enlist "\\";
      ".my.utl.require \"ghost_prefixed.q\"";
      "ratio: 6 % 2";
      "if[1b; .utl.require \"real_two.q\"];";
      enlist "\\";
      ".utl.require \"ghost_after_terminator.q\"");
    tmpFile: .tst.tempFile ".q";
    (hsym `$tmpFile) 0: src;

    targets: (.tst.parseDependencyRecords tmpFile)`target;
    (asc targets) musteq asc ("real_one.q"; "real_two.q");
  };

  should["record whether a target was concatenated onto a prefix"]{
    src: (
      ".utl.require .utl.PKGLOADING,\"/tail_form.q\"";
      ".utl.require \"standalone.q\"");
    tmpFile: .tst.tempFile ".q";
    (hsym `$tmpFile) 0: src;

    recs: .tst.parseDependencyRecords tmpFile;
    tailFlags: recs[`tail] recs[`target]?("/tail_form.q"; "standalone.q");
    tailFlags musteq 10b;
  };

  should["keep a standalone absolute target absolute"]{
    / A concatenated tail joins onto the requiring directory; a standalone
    / absolute literal must not be rebased onto it and aimed at another file.
    reqFile: .utl.PKGLOADING, "/deps.q";
    tailResolved: .tst.resolveDepTargetRecord[reqFile; "/static_analysis.q"; 1b];
    (string tailResolved) musteq .utl.PKGLOADING, "/static_analysis.q";
    absResolved: .tst.resolveDepTargetRecord[reqFile; "/etc/hosts"; 0b];
    (string absResolved) musteq "/etc/hosts";
  };

  should["still detect plain \\l directives"]{
    tmpFile: .tst.tempFile ".q";
    (hsym `$tmpFile) 0: ("\\l lib/mock.q"; "/ \\l ghost_commented.q");

    recs: .tst.parseDependencyRecords tmpFile;
    (recs`target) musteq enlist "lib/mock.q";
    (first recs`kind) musteq `load;
  };
};
