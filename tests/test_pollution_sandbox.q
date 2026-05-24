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
