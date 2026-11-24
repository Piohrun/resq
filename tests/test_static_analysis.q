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
    should["static analysis exact symbols"]{
        source: (".app.runAll[]";
                 "\".app.run\"";
                 "/ .app.run[]";
                 ".app.run[]");
        tokens: .tst.static.symbolTokens source;
        must[".app.run" in tokens; "live fully-qualified symbol must be found"];
        must[".app.runAll" in tokens; "longer symbol must remain distinct"];
        (sum tokens ~\: ".app.run") musteq 1i;

        maskedOnly: ("\".hidden.call[]\""; "/ .hidden.call[]");
        must[not .tst.static.hasExactSymbol[maskedOnly; ".hidden.call"];
             "strings and comments must not create dependencies"];
    };

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

    should["ignore dependencies written only in strings or comments"]{
        body: "{ .live.call[]; \".fake.string[]\"; / .fake.comment[]";
        deps: .tst.static.findDeps[body; ""];
        deps mustmatch enlist `$".live.call";
    };
};

.tst.desc["Static analysis: file walking"]{
    should["findSources accept a single q file path"]{
        tf: .tst.tempFile ".q";
        (hsym `$tf) 0: enlist "show 1+1";
        srcs: .tst.static.findSources tf;
        / Returns absolute symbol; we just need the basename to match.
        must[any (string srcs) like "*", .tst.static.getBase tf;
             "findSources on a single file must return that file"];
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

    should["exploreFile not treat indexing as a lambda argument list"]{
        tf: .tst.tempFile ".q";
        contents: ("indexed:{x[0]+1}"; "declared:{ [x;y] x+y }");
        (hsym `$tf) 0: contents;
        fns: .tst.static.exploreFile tf;
        (exec name from fns) mustmatch `indexed`declared;
        (exec count each args from fns) mustmatch 0 2;
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

.tst.desc["block comments nest, as in q"]{
  should["keep a region commented out around an inner block comment"]{
    src: ("a:1"; "/"; "old"; "/"; "inner"; "\\"; "b:2"; "\\"; "c:3");
    masked: .tst.static.maskLines src;
    (trim each masked) musteq ("a:1"; ""; ""; ""; ""; ""; ""; ""; "c:3");
  };
  should["read the same structure in the load graph lexer"]{
    / "\n" vs gives one-character lines as strings, as read0 does.
    lx: .tst.loadGraph.lex "\n" vs "a:1\n/\n/\n\\\nb:\"x.q\"\n\\\nc:\"y.q\"\n\\\nd:\"z.q\"";
    / b is inside the outer comment; c is live; the last lone backslash ends
    / the script, so d is not read.
    (lx[`txt] like "*x.q*") musteq 0b;
    (lx[`txt] like "*y.q*") musteq 1b;
    (lx[`txt] like "*z.q*") musteq 0b;
  };
  should["drop the nested region when preprocessing a test file"]{
    out: .tst.preprocessScript ("a:1;"; "/"; "/"; "\\"; "b:2;"; "\\"; "c:3;");
    (out where 0 < count each out) musteq ("a:1;"; "c:3;");
  };
 };

.tst.desc["discover follows both ways of entering a namespace"]{
  should["qualify functions defined after system \"d .ns\", as after \\d .ns"]{
    dir: .resq.util.tempRoot[], "/resq_discover_ns_", string[.z.i], "_", string `long$.z.p;
    .resq.util.ensureDir dir;
    .tst.registerCleanup[{[d] @[system; "rm -rf -- ", .resq.util.shellQuote d; {}]}; enlist dir];
    (hsym `$dir, "/a.q") 0: ("system \"d .orders\";"; "create:{[x] x+1};"; "system \"d .\";"; "top:{[x] x};");
    (hsym `$dir, "/b.q") 0: ("\\d .users"; "add:{[x] x+1};"; "\\d ."; "plain:{[x] x};");
    names: {[f] exec name from .tst.exploreFile hsym `$f};
    (asc names dir, "/a.q") musteq asc `.orders.create`top;
    (asc names dir, "/b.q") musteq asc `.users.add`plain;
  };
 };

/ discover from the command line: a path that is not there, and no paths.
.tst.desc["discover refuses a command it cannot answer #slow"]{
  should["fail when the source or the test path does not exist, and when no paths are given"]{
    wd: .resq.util.tempRoot[], "/resq_discover_cli_", string[.z.i], "_", string `long$.z.p;
    .resq.util.ensureDir wd, "/src";
    .resq.util.ensureDir wd, "/tests";
    .tst.registerCleanup[{[d] @[system; "rm -rf -- ", .resq.util.shellQuote d; {}]}; enlist wd];
    (hsym `$wd, "/src/m.q") 0: enlist ".m.f:{[x] x+1};";
    (hsym `$wd, "/tests/test_m.q") 0: enlist ".tst.desc[\"m\"]{ should[\"f\"]{ .m.f[1] musteq 2; }; };";
    run: {[wd;args]
        cmd: "cd ", .resq.util.shellQuote[wd], " && ", .resq.util.shellQuote[.resq.HOME, "/bin/resq"],
            " discover ", args, " -outDir out 2>&1; echo exit=$?";
        @[system; "sh -c ", .resq.util.shellQuote cmd; {[e] enlist "exit=-1"}]}[wd];
    (last run "src tests") musteq "exit=0";
    missing: run "nope tests";
    (last missing) musteq "exit=1";
    (any missing like "*the source path does not exist: nope*") musteq 1b;
    (last run "src nope") musteq "exit=1";
    none: run "";
    (last none) musteq "exit=1";
    (any none like "*discover needs a source path and a test path*") musteq 1b;
    / nothing was written into the project for the commands that failed
    .resq.util.pathExists[wd, "/coverage_report.html"] musteq 0b;
  };
 };
