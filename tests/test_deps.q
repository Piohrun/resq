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

  should["find dependents of a file"]{
    .tst.rebuildGraph enlist .utl.PKGLOADING;
    / parseLoadDirectives stores the literal string from quoted load calls.
    / Framework modules use `.utl.PKGLOADING,"/<name>.q"`, so the parsed key
    / is just "/<name>.q" -- look up by that form.
    dependents: .tst.getDependents `$"/static_analysis.q";
    mustgt[count dependents; 0];
  };

  should["survive a circular dep graph without stack overflow"]{
    / Save and restore depGraph so we don't poison later tests.
    .tst.savedGraph: .tst.depGraph;
    .tst.depGraph: `a`b`c!(enlist `b; enlist `c; enlist `a);
    deps: .tst.getDependents `a;
    .tst.depGraph: .tst.savedGraph;
    all (`a`b`c) in deps;
  };
};
