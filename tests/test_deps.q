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
    all (`a`b`c) in deps;
  };
};
