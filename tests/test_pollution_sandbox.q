.tst.desc["Pollution and Sandbox Test"]{
    should["pollute a new namespace"]{
        .polluted.x:1;
        1 musteq 1;
    };
    
    should["change the current namespace"]{
        .escaped.x:1;
        system "d .escaped";
        1 musteq 1;
    };
};

.tst.desc["Dependency Test"]{
    should["require a dependency"]{
        / Use install-root-absolute path so the test passes regardless of CWD.
        .utl.require .utl.PKGLOADING,"/config.q";
        1 musteq 1;
    };
};

.tst.desc["resQ's own start-up leaves no variables in the root namespace"]{
  should["keep config, args and its other working values under .resq"]{
    / An application that sets `config` or `args` only when undefined must not
    / find resQ's there. The root namespace holds resQ's test words and nothing
    / else of its own.
    leaked: `config`args`textReporterLoaded`exitCode`noTestsFound`src`dirs`changes inter key `.;
    leaked musteq `symbol$();
  };
 };
