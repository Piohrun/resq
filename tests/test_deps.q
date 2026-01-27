.tst.desc["Dependency Graph Analysis"]{
  should["parse load directives from file"]{
    testContent: ("\\l lib/mock.q"; ".utl.require \"lib/fixture.q\"; someCode: 1+1");
    (hsym `$"test_deps_tmp.q") 0: testContent;
    
    deps: .tst.parseLoadDirectives "test_deps_tmp.q";
    
    expected: (`$"lib/mock.q"; `$"lib/fixture.q");
    mustmatch[deps; expected];
    
    system "rm test_deps_tmp.q";
  };

  should["build dependency graph for directory"]{
    .tst.rebuildGraph enlist "lib";
    
    mustgt[count key .tst.depGraph; 0];
    mustgt[count key .tst.dependencies; 0];
  };

  should["find dependents of a file"]{
    .tst.rebuildGraph ("lib"; "tests");
    dependents: .tst.getDependents `$"lib/static_analysis.q";
    mustgt[count dependents; 0];
  };
};