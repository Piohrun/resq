/ ============================================================================
/ Tests for lib/load_graph.q - the load graph watch mode selects tests with.
/ .
/ Each test writes a small project to a scratch directory, builds the graph and
/ asserts on it by RELATIVE path. Two properties matter more than precision:
/   - a load the graph can read is an edge (so the right tests rerun), and
/   - a load it cannot read marks the file dynamic (so tests are rerun rather
/     than silently skipped).
/ Helpers and state live under .tst.testState.lg (the pollution guard skips
/ the `tst` namespace).
/ ============================================================================

/ Write `files` (relative path strings -> list of source lines) under a fresh
/ scratch root and return the root.
.tst.testState.lg.project:{[files]
  root: .utl.tempRoot[], "/resq_lg_", string[.z.i], "_", string `long$.z.p;
  full: (root, "/") ,/: key files;
  system "mkdir -p ", " " sv .utl.shellQuote each distinct .tst.static.getDir each full;
  {[path;lines] (hsym `$path) 0: lines}'[full; value files];
  root
 };

/ Build the graph for a scratch project and return it keyed by relative path:
/ files, deps (per file, sorted), dynamic, why, loaders.
.tst.testState.lg.graph:{[files;loaders]
  root: .tst.testState.lg.project files;
  tracked: .tst.static.findSources root;
  .tst.loadGraph.reset[];
  g: @[{.tst.loadGraph.build . x}; (tracked; (count tracked)#enlist 1; loaders); {[e] `error`text!(1b; e)}];
  system "rm -rf ", .utl.shellQuote root;
  if[`error in key g; '"load graph build failed: ", g`text];
  rel: `${[root;p] (1+count root) _ string p}[root] each g`tracked;
  `files`deps`dynamic`why`loaders`g!(rel; {[rel;d] asc rel d}[rel] each g`deps; g`dynamic; g`why; g`loaders; g)
 };

.tst.testState.lg.at:{[r;f] r[`files]?`$f};
.tst.testState.lg.deps:{[r;f] r[`deps] .tst.testState.lg.at[r;f]};
.tst.testState.lg.dynamic:{[r;f] r[`dynamic] .tst.testState.lg.at[r;f]};
.tst.testState.lg.syms:{[paths] asc `$paths};
.tst.testState.lg.one: enlist "x: 1";

/ ---------------------------------------------------------------------------
.tst.desc["load graph: loads q can express directly"]{
  should["read \\l, system \"l\", protected system and value \"\\l\" loads"]{
    r: .tst.testState.lg.graph[
      ("t.q"; "src/a.q"; "src/b.q"; "src/c.q"; "src/d.q")!(
        ("\\l src/a.q";
         "system \"l src/b.q\";";
         "@[system; \"l src/c.q\"; {[e] e}];";
         "value \"\\\\l src/d.q\";");
        .tst.testState.lg.one; .tst.testState.lg.one; .tst.testState.lg.one; .tst.testState.lg.one);
      ()];
    .tst.testState.lg.deps[r; "t.q"] mustmatch .tst.testState.lg.syms ("src/a.q"; "src/b.q"; "src/c.q"; "src/d.q");
    must[not any r`dynamic; "fixed targets are never dynamic: ", .Q.s1 r`why];
  };

  should["resolve ./ and ../ and interior .. in a target"]{
    r: .tst.testState.lg.graph[
      ("tests/t.q"; "src/a.q"; "src/b.q"; "src/c.q")!(
        ("\\l ../src/a.q"; "\\l ./src/b.q"; "system \"l src/x/../c.q\";");
        .tst.testState.lg.one; .tst.testState.lg.one; .tst.testState.lg.one);
      ()];
    .tst.testState.lg.deps[r; "tests/t.q"] mustmatch .tst.testState.lg.syms ("src/a.q"; "src/b.q"; "src/c.q");
  };

  should["follow loads through intermediate files"]{
    r: .tst.testState.lg.graph[
      ("t.q"; "a.q"; "b.q"; "c.q")!(
        enlist "\\l a.q"; enlist "\\l b.q"; .tst.testState.lg.one; .tst.testState.lg.one);
      ()];
    g: r`g;
    reached: r[`files] .tst.loadGraph.loadedBy[g; enlist .tst.testState.lg.at[r; "b.q"]];
    (asc reached) mustmatch .tst.testState.lg.syms ("a.q"; "b.q"; "t.q");
    untouched: r[`files] .tst.loadGraph.loadedBy[g; enlist .tst.testState.lg.at[r; "c.q"]];
    untouched mustmatch enlist `c.q;
  };

  should["survive a load cycle"]{
    r: .tst.testState.lg.graph[
      ("a.q"; "b.q")!(enlist "\\l b.q"; enlist "\\l a.q");
      ()];
    reached: r[`files] .tst.loadGraph.loadedBy[r`g; enlist .tst.testState.lg.at[r; "a.q"]];
    (asc reached) mustmatch .tst.testState.lg.syms ("a.q"; "b.q");
  };
 };

/ ---------------------------------------------------------------------------
/ A path literal is a dependency whichever function consumes it. This is what
/ makes a project's own loader work without the graph knowing its name.
.tst.desc["load graph: any .q path literal is a dependency"]{
  should["take a literal passed to an unknown function"]{
    r: .tst.testState.lg.graph[
      ("t.q"; "src/a.q"; "src/b.q"; "src/c.q")!(
        (".any.fn \"src/a.q\";";
         "files: (\"src/b.q\"; \"src/c.q\");";
         ".any.fn each files;");
        .tst.testState.lg.one; .tst.testState.lg.one; .tst.testState.lg.one);
      ()];
    .tst.testState.lg.deps[r; "t.q"] mustmatch .tst.testState.lg.syms ("src/a.q"; "src/b.q"; "src/c.q");
    must[not .tst.testState.lg.dynamic[r; "t.q"]; "an unknown function is not assumed to load"];
  };

  should["take a symbol and a file-handle literal"]{
    r: .tst.testState.lg.graph[
      ("t.q"; "src/a.q"; "b.q")!(
        (".any.fn `:src/a.q;"; ".any.fn `b.q;");
        .tst.testState.lg.one; .tst.testState.lg.one);
      ()];
    .tst.testState.lg.deps[r; "t.q"] mustmatch .tst.testState.lg.syms ("b.q"; "src/a.q");
  };

  should["take a literal inside a function body"]{
    r: .tst.testState.lg.graph[
      ("t.q"; "src/a.q")!(
        ("init:{[]"; "  .any.fn \"src/a.q\";"; " };");
        .tst.testState.lg.one);
      ()];
    .tst.testState.lg.deps[r; "t.q"] mustmatch enlist `$"src/a.q";
  };

  should["match a path by its trailing components only"]{
    r: .tst.testState.lg.graph[
      ("exact.q"; "loose.q"; "a/util.q"; "b/util.q")!(
        enlist "\\l a/util.q"; enlist "\\l util.q";
        .tst.testState.lg.one; .tst.testState.lg.one);
      ()];
    .tst.testState.lg.deps[r; "exact.q"] mustmatch enlist `$"a/util.q";
    / A bare name could be either file, so both are kept: more reruns, never fewer.
    .tst.testState.lg.deps[r; "loose.q"] mustmatch .tst.testState.lg.syms ("a/util.q"; "b/util.q");
  };

  should["not match a file or directory whose name merely ends the same way"]{
    r: .tst.testState.lg.graph[
      ("t.q"; "src/util.q"; "src/myutil.q"; "mysrc/util.q")!(
        enlist "\\l src/util.q";
        .tst.testState.lg.one; .tst.testState.lg.one; .tst.testState.lg.one);
      ()];
    .tst.testState.lg.deps[r; "t.q"] mustmatch enlist `$"src/util.q";
  };
 };

/ ---------------------------------------------------------------------------
.tst.desc["load graph: text that is not code is ignored"]{
  should["ignore comments, block comments and text after the terminator"]{
    r: .tst.testState.lg.graph[
      ("t.q"; "src/a.q")!(
        ("/ \\l src/a.q";
         "x: 1 / see \"src/a.q\"";
         enlist "/";
         "\\l src/a.q";
         ".any.fn \"src/a.q\";";
         enlist "\\";
         "y: 2";
         enlist "\\";
         "\\l src/a.q");
        .tst.testState.lg.one);
      ()];
    (count .tst.testState.lg.deps[r; "t.q"]) musteq 0;
  };

  should["tell a divide from a comment and honour string escapes"]{
    r: .tst.testState.lg.graph[
      ("t.q"; "src/a.q"; "src/b.q"; "src/c.q")!(
        ("r: 6%2; s: 10 /\"src/a.q\" is commentary";
         "u: \"ends with a backslash \\\\\"; v: \"src/b.q\";";
         "w: \"quoted \\\"src/c.q\\\" inside\";");
        .tst.testState.lg.one; .tst.testState.lg.one; .tst.testState.lg.one);
      ()];
    .tst.testState.lg.deps[r; "t.q"] mustmatch enlist `$"src/b.q";
  };

  should["build for empty, one-character, shebang and unterminated files"]{
    r: .tst.testState.lg.graph[
      ("empty.q"; "slash.q"; "shebang.q"; "open.q"; "src/a.q")!(
        enlist "";
        enlist enlist "/";
        ("#!/usr/bin/env q"; "\\l src/a.q");
        ("x: \"never closed"; "\\l src/a.q");
        .tst.testState.lg.one);
      ()];
    .tst.testState.lg.deps[r; "shebang.q"] mustmatch enlist `$"src/a.q";
    (count .tst.testState.lg.deps[r; "empty.q"]) musteq 0;
    (count .tst.testState.lg.deps[r; "slash.q"]) musteq 0;
  };
 };

/ ---------------------------------------------------------------------------
/ The safety half: a load with no fixed target must be reported, not dropped.
.tst.desc["load graph: a computed target makes the file dynamic"]{
  should["flag a computed system load and say where"]{
    r: .tst.testState.lg.graph[
      ("t.q"; "u.q"; "src/a.q")!(
        ("name: \"a\";"; "system \"l src/\", name, \".q\";");
        ("path: \"src/a.q\";"; "x: 1"; "system \"l \", path;");
        .tst.testState.lg.one);
      ()];
    must[.tst.testState.lg.dynamic[r; "t.q"]; "a target assembled around a variable is unknown"];
    must[.tst.testState.lg.dynamic[r; "u.q"]; "a target held in a variable is unknown"];
    must[(first r[`why] .tst.testState.lg.at[r; "t.q"]) like "line 2: *"; "the reason names the line"];
    must[(first r[`why] .tst.testState.lg.at[r; "u.q"]) like "line 3: *"; "the reason names the line"];
    must[not .tst.testState.lg.dynamic[r; "src/a.q"]; "an ordinary file is not dynamic"];
  };

  should["resolve a path joined onto a prefix by its literal tail"]{
    r: .tst.testState.lg.graph[
      ("t.q"; "src/a.q"; "src/order_impl.q")!(
        ("root: \"/somewhere\";";
         "system \"l \", root, \"/src/a.q\";";
         "system \"l \", prefix, \"_impl.q\";");
        .tst.testState.lg.one; .tst.testState.lg.one);
      ()];
    .tst.testState.lg.deps[r; "t.q"] mustmatch .tst.testState.lg.syms ("src/a.q"; "src/order_impl.q");
    must[not .tst.testState.lg.dynamic[r; "t.q"]; "a literal tail fixes the file: ", .Q.s1 r`why];
  };

  should["flag a directory load that names a watched directory"]{
    r: .tst.testState.lg.graph[
      ("byline.q"; "bycall.q"; "elsewhere.q"; "src/a.q")!(
        enlist "\\l src";
        enlist "system \"l src\";";
        enlist "\\l /opt/other/db";
        .tst.testState.lg.one);
      ()];
    must[.tst.testState.lg.dynamic[r; "byline.q"]; "\\l of a watched directory runs its scripts"];
    must[.tst.testState.lg.dynamic[r; "bycall.q"]; "system \"l\" of a watched directory runs its scripts"];
    must[not .tst.testState.lg.dynamic[r; "elsewhere.q"]; "a directory outside the watch set is not a dependency"];
  };
 };

/ ---------------------------------------------------------------------------
/ A project's own loader, defined in a watched file, needs no configuration.
.tst.desc["load graph: a named function that loads is a loader"]{
  should["judge the loader's calls instead of its definition"]{
    r: .tst.testState.lg.graph[
      ("lib/boot.q"; "fixed.q"; "computed.q"; "src/a.q")!(
        enlist ".lib.ld:{[p] system \"l \",p};";
        ("\\l lib/boot.q"; ".lib.ld \"src/a.q\";");
        ("\\l lib/boot.q"; ".lib.ld \"src/\", nm, \".q\";");
        .tst.testState.lg.one);
      ()];
    must[any r[`loaders] ~\: ".lib.ld"; "the function is discovered: ", .Q.s1 r`loaders];
    must[not .tst.testState.lg.dynamic[r; "lib/boot.q"]; "defining a loader is not a load"];
    .tst.testState.lg.deps[r; "fixed.q"] mustmatch .tst.testState.lg.syms ("lib/boot.q"; "src/a.q");
    must[not .tst.testState.lg.dynamic[r; "fixed.q"]; "a literal target is known"];
    must[.tst.testState.lg.dynamic[r; "computed.q"]; "a computed target is not"];
  };

  should["follow wrappers around a loader"]{
    r: .tst.testState.lg.graph[
      ("lib/boot.q"; "fixed.q"; "computed.q"; "src/a.q"; "src/b.q")!(
        (".lib.ld:{[p] system \"l \",p};"; ".lib.many:{[ps] .lib.ld each ps};");
        enlist ".lib.many (\"src/a.q\"; \"src/b.q\");";
        enlist ".lib.many modules;";
        .tst.testState.lg.one; .tst.testState.lg.one);
      ()];
    must[any r[`loaders] ~\: ".lib.many"; "the wrapper is discovered: ", .Q.s1 r`loaders];
    must[not .tst.testState.lg.dynamic[r; "lib/boot.q"]; "wrappers are judged at their calls"];
    .tst.testState.lg.deps[r; "fixed.q"] mustmatch .tst.testState.lg.syms ("src/a.q"; "src/b.q");
    must[.tst.testState.lg.dynamic[r; "computed.q"]; "a wrapper called with a variable is unknown"];
  };

  should["recognise a loader's bare name only inside its namespace"]{
    r: .tst.testState.lg.graph[
      ("lib/byd.q"; "lib/bysystem.q"; "root.q"; "src/a.q")!(
        ("\\d .lib"; "ld:{[p] system \"l \",p}"; "many:{[ps] ld each ps}"; "\\d .");
        ("system \"d .lib2\";"; "ld:{[p] system \"l \",p};"; "boot: ld nm;"; "system \"d .\";");
        ("many: {count x};"; "total: many items;");
        .tst.testState.lg.one);
      ()];
    must[all (".lib.ld"; ".lib.many"; ".lib2.ld") in r`loaders; "names are qualified: ", .Q.s1 r`loaders];
    must[not .tst.testState.lg.dynamic[r; "lib/byd.q"]; "bare calls between loaders are not top-level loads"];
    must[.tst.testState.lg.dynamic[r; "lib/bysystem.q"]; "a bare call with a variable, in the namespace, is a load"];
    must[not .tst.testState.lg.dynamic[r; "root.q"]; "the same bare name at root is another function"];
  };

  should["treat a loader passed around as a value as unknown"]{
    r: .tst.testState.lg.graph[
      ("lib/boot.q"; "alias.q")!(
        enlist ".lib.ld:{[p] system \"l \",p};";
        enlist "mine: .lib.ld;");
      ()];
    must[.tst.testState.lg.dynamic[r; "alias.q"]; "what an alias later loads cannot be read"];
  };
 };

/ ---------------------------------------------------------------------------
/ A loader defined outside the watched files has to be named.
.tst.desc["load graph: configured loaders"]{
  should["flag a module name and a computed argument once the loader is named"]{
    files: ("literal.q"; "module.q"; "computed.q"; "guarded.q"; "src/a.q"; "src/b.q")!(
        enlist ".ext.load \"src/a.q\";";
        enlist ".ext.load \"pricing\";";
        enlist ".ext.load each modules;";
        ("@[.ext.load; \"src/b.q\"; {[e] e}];"; "@[.ext.load; nm; {[e] e}];");
        .tst.testState.lg.one; .tst.testState.lg.one);

    named: .tst.testState.lg.graph[files; enlist ".ext.load"];
    .tst.testState.lg.deps[named; "literal.q"] mustmatch enlist `$"src/a.q";
    must[not .tst.testState.lg.dynamic[named; "literal.q"]; "a .q literal is a fixed target"];
    must[.tst.testState.lg.dynamic[named; "module.q"]; "a module name maps to a file only the loader knows"];
    must[.tst.testState.lg.dynamic[named; "computed.q"]; "an argument held in a variable is unknown"];
    .tst.testState.lg.deps[named; "guarded.q"] mustmatch enlist `$"src/b.q";
    must[.tst.testState.lg.dynamic[named; "guarded.q"]; "the protected form is judged by its argument"];

    / Unnamed, the calls are ordinary calls: literals still count, nothing is flagged.
    unnamed: .tst.testState.lg.graph[files; ()];
    .tst.testState.lg.deps[unnamed; "literal.q"] mustmatch enlist `$"src/a.q";
    must[not any unnamed`dynamic; "an unnamed external loader cannot be recognised"];
  };

  should["accept loader names as strings or symbols"]{
    (.tst.loadGraph.names ".ext.load") mustmatch enlist ".ext.load";
    (.tst.loadGraph.names `.ext.load) mustmatch enlist ".ext.load";
    (.tst.loadGraph.names `.a.f`.b.g) mustmatch (".a.f"; ".b.g");
    (.tst.loadGraph.names (".a.f"; `.b.g)) mustmatch (".a.f"; ".b.g");
    (count .tst.loadGraph.names ()) musteq 0;
  };
 };

/ ---------------------------------------------------------------------------
.tst.desc["load graph: rebuilds follow the files"]{
  should["reuse a file until its fingerprint changes"]{
    root: .tst.testState.lg.project ("t.q"; "a.q"; "b.q")!(enlist "\\l a.q"; .tst.testState.lg.one; .tst.testState.lg.one);
    tracked: .tst.static.findSources root;
    rel: `${[root;p] (1+count root) _ string p}[root] each tracked;
    at: rel?`t.q;
    .tst.loadGraph.reset[];
    depsOf: {[tracked;rel;at;fp] rel .tst.loadGraph.build[tracked; (count tracked)#enlist fp; ()][`deps] at}[tracked;rel;at];
    first1: depsOf 1;
    (hsym `$root, "/t.q") 0: enlist "\\l b.q";
    stale: depsOf 1;
    fresh: depsOf 2;
    system "rm -rf ", .utl.shellQuote root;
    first1 mustmatch enlist `a.q;
    stale mustmatch enlist `a.q;
    fresh mustmatch enlist `b.q;
  };

  should["pick up a target that appears after the file naming it"]{
    root: .tst.testState.lg.project (enlist "t.q")!enlist enlist "\\l later.q";
    .tst.loadGraph.reset[];
    build: {[root;unused]
      tracked: .tst.static.findSources root;
      g: .tst.loadGraph.build[tracked; (count tracked)#enlist 1; ()];
      rel: `${[root;p] (1+count root) _ string p}[root] each tracked;
      rel g[`deps] rel?`t.q}[root;];
    before1: build[];
    (hsym `$root, "/later.q") 0: .tst.testState.lg.one;
    after1: build[];
    system "rm -rf ", .utl.shellQuote root;
    (count before1) musteq 0;
    after1 mustmatch enlist `later.q;
  };

  should["return an empty graph for no files"]{
    g: .tst.loadGraph.build[`symbol$(); (); ()];
    (count g`deps) musteq 0;
    (count .tst.loadGraph.loadedBy[g; `long$()]) musteq 0;
  };
 };
