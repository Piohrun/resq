/ Tests for the static analysis helpers used by discover/coverage/deps.

.tst.desc["Static analysis: path helpers"]{
    should["toStr return strings unchanged and stringify symbols"]{
        .tst.static.toStr["hello"] musteq "hello";
        .tst.static.toStr[`hello] musteq "hello";
    };

    should["getDir return the directory portion of a path"]{
        .tst.static.getDir["lib/runner.q"] musteq "lib/";
        .tst.static.getDir["a/b/c.q"] musteq "a/b/";
        / no slash means no directory
        .tst.static.getDir["runner.q"] musteq "";
        .tst.static.getDir[""] musteq "";
    };

    should["getBase return the basename of a path"]{
        .tst.static.getBase["lib/runner.q"] musteq "runner.q";
        .tst.static.getBase["a/b/c.q"] musteq "c.q";
        .tst.static.getBase["runner.q"] musteq "runner.q";
    };

    should["normalizePath strip a leading base directory"]{
        .tst.static.normalizePath["lib/runner.q"; "lib"] musteq "runner.q";
        .tst.static.normalizePath["lib/runner.q"; "lib/"] musteq "runner.q";
        / unrelated base leaves path unchanged
        .tst.static.normalizePath["lib/runner.q"; "src"] musteq "lib/runner.q";
        / hsym-style ":" prefixes are stripped before comparison
        .tst.static.normalizePath[":lib/runner.q"; ":lib"] musteq "runner.q";
    };
};

.tst.desc["Static analysis: findDeps"]{
    should["pick out dotted-namespace references"]{
        body: "{ .foo.bar[x] + .baz.qux y }";
        deps: .tst.static.findDeps[body; ""];
        (`$".foo.bar") mustin deps;
        (`$".baz.qux") mustin deps;
    };

    should["skip kdb+ built-in namespaces"]{
        body: "{ .Q.s1 x; .z.p; .j.j y; .h.hu z; .kx.foo[] }";
        deps: .tst.static.findDeps[body; ""];
        / All of these should be filtered out.
        deps mustmatch `symbol$();
    };

    should["exclude the function's own name"]{
        body: "{ .my.helper[x] }";
        deps: .tst.static.findDeps[body; ".my.helper"];
        must[not (`$".my.helper") in deps; "self-name should be excluded"];
    };
};

.tst.desc["Static analysis: file walking"]{
    should["findSources accept a single q file path"]{
        tf: .tst.tempFile ".q";
        (hsym `$tf) 0: enlist "show 1+1";
        srcs: .tst.static.findSources tf;
        / Returns absolute symbol; we just need the basename to match.
        any (string srcs) like "*", .tst.static.getBase tf;
    };

    should["exploreFile pick up function definitions with arities"]{
        tf: .tst.tempFile ".q";
        contents: ("/ sample"; "add:{[x;y] x+y}"; "id:{[v] v}");
        (hsym `$tf) 0: contents;
        fns: .tst.static.exploreFile tf;
        / Two function rows, ordered as in source.
        (count fns) musteq 2;
        / exec returns a list; symbol equality via mustmatch.
        (exec name from fns) mustmatch `add`id;
        (exec count each args from fns) mustmatch 2 1;
    };

    should["exploreFile detect a space after the definition colon"]{
        tf: .tst.tempFile ".q";
        / `f: {` (space after colon) must be detected, same as `f:{`.
        contents: ("f: {[x] x}"; "g:{[y] y}");
        (hsym `$tf) 0: contents;
        fns: .tst.static.exploreFile tf;
        (exec name from fns) mustmatch `f`g;
    };

    should["exploreFile reset namespace on \\d ."]{
        tf: .tst.tempFile ".q";
        / `\d .a` enters namespace, `\d .` resets to root. The reset must
        / produce a bare `g`, never a `..g` (invalid q).
        contents: ("\\d .a"; "f:{[x] x+1}"; "\\d ."; "g:{[y] y}");
        (hsym `$tf) 0: contents;
        fns: .tst.static.exploreFile tf;
        (exec name from fns) mustmatch `.a.f`g;
    };
};
