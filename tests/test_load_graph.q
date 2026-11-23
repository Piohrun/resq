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
.tst.testState.lg.why:{[r;f] r[`why] .tst.testState.lg.at[r;f]};
.tst.testState.lg.has:{[strings;s] any strings~\:s};

/ For tests of the helpers themselves: source lines lexed, with bracket context.
.tst.testState.lg.cx:{[lines] .tst.loadGraph.context .tst.loadGraph.lex lines};
/ Offset of the first place `s` occurs in the lexed text, taken literally.
.tst.testState.lg.off:{[cx;s]
  txt: cx`txt;
  first where s~/:(count s)#/:(til count txt)_\:txt
 };

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
      ("t.q"; "src/a.q"; "src/order_impl.q"; "src/unrelated.q")!(
        ("root: \"/somewhere\";";
         "system \"l \", root, \"/src/a.q\";";
         "system \"l \", prefix, \"_impl.q\";");
        .tst.testState.lg.one; .tst.testState.lg.one; .tst.testState.lg.one);
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
        ("helper:{x+1};"; "system \"d .lib2\";"; "ld:{[p] system \"l \",p};"; "boot: ld nm;"; "system \"d .\";");
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
    files: ("literal.q"; "module.q"; "computed.q"; "guarded.q"; "guardedvar.q"; "src/a.q"; "src/b.q")!(
        enlist ".ext.load \"src/a.q\";";
        enlist ".ext.load \"pricing\";";
        enlist ".ext.load each modules;";
        enlist "@[.ext.load; \"src/b.q\"; {[e] e}];";
        enlist "@[.ext.load; nm; {[e] e}];";
        .tst.testState.lg.one; .tst.testState.lg.one);

    named: .tst.testState.lg.graph[files; enlist ".ext.load"];
    .tst.testState.lg.deps[named; "literal.q"] mustmatch enlist `$"src/a.q";
    must[not .tst.testState.lg.dynamic[named; "literal.q"]; "a .q literal is a fixed target"];
    must[.tst.testState.lg.dynamic[named; "module.q"]; "a module name maps to a file only the loader knows"];
    must[.tst.testState.lg.dynamic[named; "computed.q"]; "an argument held in a variable is unknown"];
    .tst.testState.lg.deps[named; "guarded.q"] mustmatch enlist `$"src/b.q";
    must[not .tst.testState.lg.dynamic[named; "guarded.q"]; "the protected form with a literal is a fixed target"];
    must[.tst.testState.lg.dynamic[named; "guardedvar.q"]; "the protected form is judged by its argument"];

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
    cached: count .tst.loadGraph.cache;
    .tst.loadGraph.reset[];
    emptied: count .tst.loadGraph.cache;
    afterReset: depsOf 1;
    (hsym `$root, "/t.q") 0: enlist "\\l a.q";
    fresh: depsOf 2;
    system "rm -rf ", .utl.shellQuote root;
    first1 mustmatch enlist `a.q;
    stale mustmatch enlist `a.q;
    cached musteq 3;
    emptied musteq 0;
    / Same fingerprint, but nothing is remembered after a reset.
    afterReset mustmatch enlist `b.q;
    fresh mustmatch enlist `a.q;
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
    g: .tst.loadGraph.build[`symbol$(); (); (".x.load"; ".x.load")];
    must[(count g`loaders)=count distinct g`loaders; "each loader once: ", .Q.s1 g`loaders];
    (count g`deps) musteq 0;
    (g`dynamic) mustmatch `boolean$();
    must[.tst.testState.lg.has[g`loaders; ".x.load"]; "configured loaders are in force: ", .Q.s1 g`loaders];
    must[.tst.testState.lg.has[g`loaders; ".utl.require"]; "and so are the built-in ones: ", .Q.s1 g`loaders];
    (count .tst.loadGraph.loadedBy[g; `long$()]) musteq 0;
  };

  should["build a graph of one file"]{
    r: .tst.testState.lg.graph[(enlist "only.q")!enlist enlist "system \"l \", path;"; ()];
    (r`dynamic) mustmatch enlist 1b;
    (r`deps) mustmatch enlist `symbol$();
  };
 };

/ ===========================================================================
/ The helpers, tested directly. The graph-level tests above show that loads
/ are found; these pin the exact text handling they depend on.
/ ===========================================================================

.tst.desc["load graph: lexing a file"]{
  should["take one line given as a string, and no lines at all"]{
    (.tst.loadGraph.lex "\\l a.q")[`loads] mustmatch enlist "a.q";
    .tst.loadGraph.lex[()] mustmatch .tst.loadGraph.emptyLex[];
    (.tst.loadGraph.emptyLex[]`starts) mustmatch enlist 0;
    .tst.loadGraph.lineOf[.tst.loadGraph.lex (); 0] mustmatch "line 1: ";
  };

  should["blank string contents and comments, and keep quotes and line breaks"]{
    lx: .tst.loadGraph.lex ("a: \"x/y\" , `s / c \"z\""; "b: 1");
    (lx`txt) mustmatch "a: \"x/y\" , `s / c \"z\"\nb: 1";
    (lx`code) mustmatch "a: \"   \" , `s", (8#" "), "\nb: 1";
    (lx`opens) mustmatch enlist 3;
    (lx`closes) mustmatch enlist 7;
  };

  should["record where lines start, \\l targets and namespace changes"]{
    lx: .tst.loadGraph.lex ("\\l src/a.q  / why"; "\\d .lib"; "x: 1"; "\\d ."; "y: 2");
    (lx`loads) mustmatch enlist "src/a.q";
    / System command lines are emptied, so the text is two empty lines first.
    (lx`txt) mustmatch "\n\nx: 1\n\ny: 2";
    (lx`starts) mustmatch 0 1 2 7 8;
    (lx`nsPos) mustmatch 1 7;
    (lx`nsName) mustmatch (".lib"; "");
    .tst.loadGraph.nsAt[lx; 0] mustmatch "";
    .tst.loadGraph.nsAt[lx; 2] mustmatch ".lib";
    .tst.loadGraph.nsAt[lx; 8] mustmatch "";
  };

  should["unescape a string literal"]{
    lx: .tst.loadGraph.lex enlist "x: \"a\\\"b\\\\c\";";
    .tst.loadGraph.literal[lx; 0] mustmatch "a\"b\\c";
  };

  should["strip trailing blanks from a line"]{
    .tst.loadGraph.rstrip["ab \t\r"] mustmatch "ab";
    .tst.loadGraph.rstrip["x/  "] mustmatch "x/";
    .tst.loadGraph.rstrip["/ "] mustmatch enlist "/";
    .tst.loadGraph.rstrip["   "] mustmatch "";
    .tst.loadGraph.rstrip[""] mustmatch "";
  };

  should["treat code after a block comment as live again"]{
    r: .tst.testState.lg.graph[
      ("t.q"; "src/a.q"; "src/b.q")!(
        (enlist "/"; "\\l src/b.q"; enlist "\\"; "\\l src/a.q");
        .tst.testState.lg.one; .tst.testState.lg.one);
      ()];
    .tst.testState.lg.deps[r; "t.q"] mustmatch enlist `$"src/a.q";
  };

  should["ignore a shebang line and a comment that opens the file"]{
    r: .tst.testState.lg.graph[
      ("shebang.q"; "comment.q"; "src/a.q"; "src/b.q")!(
        ("#!/bin/sh -c 'q \"src/b.q\"'"; "\\l src/a.q");
        ("/ see \"src/a.q\""; "x: 1");
        .tst.testState.lg.one; .tst.testState.lg.one);
      ()];
    .tst.testState.lg.deps[r; "shebang.q"] mustmatch enlist `$"src/a.q";
    (count .tst.testState.lg.deps[r; "comment.q"]) musteq 0;
  };

  should["not read a symbol out of a string or a comment"]{
    r: .tst.testState.lg.graph[
      ("t.q"; "src/a.q"; "src/b.q")!(
        ("note: \"see `src/a.q here\";"; "x: 1 / `src/b.q");
        .tst.testState.lg.one; .tst.testState.lg.one);
      ()];
    (count .tst.testState.lg.deps[r; "t.q"]) musteq 0;
  };

  should["build for a file of zero bytes"]{
    r: .tst.testState.lg.graph[("zero.q"; "t.q")!((); enlist "x: 1"); ()];
    (count .tst.testState.lg.deps[r; "zero.q"]) musteq 0;
    must[not any r`dynamic; "an empty file loads nothing: ", .Q.s1 r`why];
  };
 };

/ ---------------------------------------------------------------------------
.tst.desc["load graph: namespaces set with system \"d\""]{
  should["switch only for a top-level system call"]{
    r: .tst.testState.lg.graph[
      ("infn.q"; "plain.q"; "afterload.q"; "src/a.q")!(
        ("setup:{[] system \"d .other\"; };"; "ld:{[p] system \"l \",p};");
        ("note: \"d .fake\";"; "ld2:{[p] system \"l \",p};");
        ("ld3:{[p] system \"l \",p};"; "system \"l src/a.q\";"; "ld3 nm;");
        .tst.testState.lg.one);
      ()];
    l: r`loaders;
    must[.tst.testState.lg.has[l; "ld"]; "a switch inside a function does not rename what follows: ", .Q.s1 l];
    must[.tst.testState.lg.has[l; "ld2"]; "a string that only looks like the command is not one: ", .Q.s1 l];
    must[not any l like ".other*"; .Q.s1 l];
    must[not any l like ".fake*"; .Q.s1 l];
    / A system load is not a namespace change: the bare call is still at root.
    must[.tst.testState.lg.dynamic[r; "afterload.q"]; "the call after a system load is still seen"];
  };

  should["keep \\d and system \"d\" changes in file order"]{
    r: .tst.testState.lg.graph[
      (enlist "mixed.q")!enlist (
        "\\d .a"; "ld:{[p] system \"l \",p}"; "system \"d .b\";"; "ld:{[p] system \"l \",p};");
      ()];
    l: r`loaders;
    must[.tst.testState.lg.has[l; ".a.ld"]; .Q.s1 l];
    must[.tst.testState.lg.has[l; ".b.ld"]; .Q.s1 l];
  };
 };

/ ---------------------------------------------------------------------------
.tst.desc["load graph: is a string an argument of system?"]{
  should["look only at the thirty characters before the string"]{
    / "system" starts exactly thirty characters before the quote: inside.
    .tst.loadGraph.afterSystem["system", (24#" "), "\"l x\""; 30] musteq 1b;
    / One further away, and only "ystem" is left in view.
    .tst.loadGraph.afterSystem["system", (25#" "), "\"l x\""; 31] musteq 0b;
    .tst.loadGraph.afterSystem["system \"l y\""; 7] musteq 1b;
    .tst.loadGraph.afterSystem["x: \"l y\""; 3] musteq 0b;
  };

  should["not count what follows the string"]{
    .tst.loadGraph.afterSystem[(40#" "), "\"l x\"; system 1"; 40] musteq 0b;
  };

  should["not take a string that merely starts with l for a load"]{
    r: .tst.testState.lg.graph[
      ("note.q"; "far.q"; "src/a.q")!(
        enlist "note: \"l \", name;";
        ("d: system \"pwd\";"; "padding: 1+2+3+4+5+6+7+8+9+10+11;"; "note: \"l src\";");
        .tst.testState.lg.one);
      ()];
    must[not .tst.testState.lg.dynamic[r; "note.q"]; "no system call, no load: ", .Q.s1 r`why];
    must[not .tst.testState.lg.dynamic[r; "far.q"]; "a system call two statements back is another call: ", .Q.s1 r`why];
  };
 };

/ ---------------------------------------------------------------------------
.tst.desc["load graph: naming the line of an unresolved load"]{
  should["give the line number and its trimmed text"]{
    lx: .tst.loadGraph.lex ("first: 1"; "  second: 2  "; "third");
    .tst.loadGraph.lineOf[lx; 0] mustmatch "line 1: first: 1";
    .tst.loadGraph.lineOf[lx; 12] mustmatch "line 2: second: 2";
    .tst.loadGraph.lineOf[lx; -1+count lx`txt] mustmatch "line 3: third";
  };

  should["cut a line longer than seventy characters"]{
    long: 71#"abcdefghij";
    .tst.loadGraph.lineOf[.tst.loadGraph.lex enlist long; 0] mustmatch "line 1: ", (67#long), "...";
    .tst.loadGraph.lineOf[.tst.loadGraph.lex enlist 70#long; 0] mustmatch "line 1: ", 70#long;
  };

  should["list unresolved loads in line order, once per line"]{
    r: .tst.testState.lg.graph[
      (enlist "t.q")!enlist (
        "a: 1;";
        "system \"l \", p1; system \"l \", p2;";
        "x: 2";
        "system \"l \", p3;");
      ()];
    .tst.testState.lg.why[r; "t.q"] mustmatch (
      "line 2: system \"l \", p1; system \"l \", p2;";
      "line 4: system \"l \", p3;");
  };
 };

/ ---------------------------------------------------------------------------
.tst.desc["load graph: bracket depth and statement ends"]{
  should["count the depth before each character"]{
    cx: .tst.testState.lg.cx enlist "a(b[c]{d})";
    (cx`dBefore) mustmatch 0 0 1 1 2 2 1 2 2 1i;
    (cx`bBefore) mustmatch 0 0 0 0 0 0 0 1 1 0i;
    (cx`stops) mustmatch 5 8 9;
  };

  should["end a statement at a line break unless the next line is indented"]{
    cx: .tst.testState.lg.cx ("f a"; "  b"; enlist "g"; "");
    (cx`txt) mustmatch "f a\n  b\ng\n";
    (cx`stops) mustmatch 7 9;
  };

  should["find where an argument ends"]{
    cx: .tst.testState.lg.cx enlist "f[g[1;2]; \"a.q\"]; h";
    / From inside f[...] the ";" inside g[...] is deeper and does not count.
    .tst.loadGraph.stopAt[cx; 2; 1] musteq 8;
    / A closing bracket at the same depth ends it too.
    .tst.loadGraph.stopAt[cx; 9; 1] musteq 15;
    / A stop exactly where the search starts counts.
    .tst.loadGraph.stopAt[cx; 16; 0] musteq 16;
    .tst.loadGraph.stopAt[cx; 17; 0] musteq 19;
  };

  should["end at a line break at top level but not inside brackets"]{
    top: .tst.testState.lg.cx ("f a"; "g b");
    .tst.loadGraph.stopAt[top; 1; 0] musteq 3;
    inside: .tst.testState.lg.cx ("f[a"; "b; c]");
    .tst.loadGraph.stopAt[inside; 2; 1] musteq 5;
  };

  should["tell a load after closed brackets from the statement on the next line"]{
    r: .tst.testState.lg.graph[
      ("t.q"; "cont.q"; "src/a.q")!(
        ("cfg: (1;2)"; ".ext.load nm"; "other: \"src/a.q\"");
        (".ext.load"; "  \"src/a.q\"");
        .tst.testState.lg.one);
      enlist ".ext.load"];
    must[.tst.testState.lg.dynamic[r; "t.q"]; "the literal on the next line belongs to another statement"];
    must[not .tst.testState.lg.dynamic[r; "cont.q"]; "an indented line continues the call: ", .Q.s1 r`why];
  };
 };

/ ---------------------------------------------------------------------------
.tst.testState.lg.fin:{[line;lo;stop]
  cx: .tst.testState.lg.cx enlist line;
  .tst.loadGraph.finalLiteral[cx; lo; stop]
 };

.tst.desc["load graph: the literal an argument ends with"]{
  should["find a string through closing brackets and blanks"]{
    .tst.testState.lg.fin["x: ( \"src/a.q\" ) ;"; 2; 17] mustmatch `kind`text`open!(`str; "src/a.q"; 5);
  };

  should["find a symbol, also when it starts where the argument does"]{
    .tst.testState.lg.fin["f `:src/a.q;"; 1; 11] mustmatch `kind`text`open!(`sym; ":src/a.q"; 2);
    .tst.testState.lg.fin["f`a.q;"; 1; 5] mustmatch `kind`text`open!(`sym; "a.q"; 1);
    / An empty symbol is still a symbol; it names nothing.
    .tst.testState.lg.fin["f `;"; 1; 3] mustmatch `kind`text`open!(`sym; ""; 2);
  };

  should["find nothing when the argument ends in a name or an operator"]{
    (.tst.testState.lg.fin["f nm;"; 1; 4]`kind) musteq `none;
    (.tst.testState.lg.fin["f a+;"; 1; 4]`kind) musteq `none;
    (.tst.testState.lg.fin["f abc.q;"; 1; 7]`kind) musteq `none;
  };

  should["not reach back before the argument"]{
    / The range is the blank after the string, not the string.
    (.tst.testState.lg.fin["\"a.q\" ;"; 5; 6]`kind) musteq `none;
  };

  should["find nothing in a string that is never closed"]{
    cx: .tst.testState.lg.cx enlist "f \"abc";
    (.tst.loadGraph.finalLiteral[cx; 1; count cx`code]`kind) musteq `none;
  };
 };

/ ---------------------------------------------------------------------------
.tst.testState.lg.tail:{[lines;s]
  cx: .tst.testState.lg.cx lines;
  .tst.loadGraph.isTail[cx; .tst.testState.lg.off[cx;s]]
 };
.tst.testState.lg.apply:{[line;s]
  cx: .tst.testState.lg.cx enlist line;
  .tst.loadGraph.firstApplyArg[cx; .tst.testState.lg.off[cx;s]]
 };
.tst.testState.lg.call:{[line]
  cx: .tst.testState.lg.cx enlist line;
  p: .tst.testState.lg.off[cx; "ld"];
  .tst.loadGraph.classifyCall[cx; p; p+2]
 };

.tst.desc["load graph: judging one call of a loader"]{
  should["tell a literal joined onto something from one standing alone"]{
    .tst.testState.lg.tail[enlist "f \"a.q\""; "\"a.q"] musteq 0b;
    .tst.testState.lg.tail[enlist "r,\"a.q\""; "\"a.q"] musteq 1b;
    .tst.testState.lg.tail[enlist "r , \"a.q\""; "\"a.q"] musteq 1b;
    .tst.testState.lg.tail[("r,"; "  \"a.q\""); "\"a.q"] musteq 1b;
    .tst.testState.lg.tail[enlist "\"a.q\""; "\"a.q"] musteq 0b;
    .tst.testState.lg.tail[enlist ",\"a.q\""; "\"a.q"] musteq 1b;
  };

  should["recognise the first argument of a protected call"]{
    .tst.testState.lg.apply["@[ld; x; h]"; "ld"] musteq 1b;
    .tst.testState.lg.apply["r: .[ld; (x;y); h]"; "ld"] musteq 1b;
    .tst.testState.lg.apply["r: @[ ld; x; h]"; "ld"] musteq 1b;
    .tst.testState.lg.apply["g[ld; x]"; "ld"] musteq 0b;
    .tst.testState.lg.apply["r: ld x"; "ld"] musteq 0b;
    .tst.testState.lg.apply["ld x"; "ld"] musteq 0b;
    .tst.testState.lg.apply["[ld;x]"; "ld"] musteq 0b;
    .tst.testState.lg.apply["x: @. ld"; "ld"] musteq 0b;
  };

  should["see a definition, a fixed target and a computed one"]{
    .tst.testState.lg.call["ld:{[p] system \"l \",p};"] mustmatch (`def; "");
    .tst.testState.lg.call["ld :{[p] system \"l \",p};"] mustmatch (`def; "");
    .tst.testState.lg.call["ld \"src/a.q\";"] mustmatch (`ok; "");
    .tst.testState.lg.call["ld `:src/a.q;"] mustmatch (`ok; "");
    .tst.testState.lg.call["ld`:src/a.q;"] mustmatch (`ok; "");
    .tst.testState.lg.call["ld nm;"] mustmatch (`dyn; "");
    .tst.testState.lg.call["ld \"pricing\";"] mustmatch (`dyn; "");
  };

  should["match a joined literal by its characters, and refuse a bare extension"]{
    .tst.testState.lg.call["ld dir,\"a.q\";"] mustmatch (`ok; "a.q");
    .tst.testState.lg.call["ld root,\"/src/a.q\";"] mustmatch (`ok; "/src/a.q");
    .tst.testState.lg.call["ld dir,\".q\";"] mustmatch (`dyn; "");
  };

  should["look at the next argument only in the protected form"]{
    .tst.testState.lg.call["@[ld; \"src/a.q\"; h];"] mustmatch (`ok; "");
    .tst.testState.lg.call["@[ld  ; \"src/a.q\"; h];"] mustmatch (`ok; "");
    .tst.testState.lg.call["@[ld; nm; h];"] mustmatch (`dyn; "");
    / Applied to a variable inside the brackets: that variable is the target.
    .tst.testState.lg.call["@[ld x; \"src/a.q\"; h];"] mustmatch (`dyn; "");
    / Only a ";" moves on to the next argument.
    .tst.testState.lg.call["@[ld] \"src/a.q\""] mustmatch (`dyn; "");
    / Handed to some other function as a value: what it then loads is unknown.
    .tst.testState.lg.call["g[ld; \"src/a.q\"];"] mustmatch (`dyn; "");
  };
 };

/ ---------------------------------------------------------------------------
.tst.testState.lg.defined:{[lines]
  cx: .tst.testState.lg.cx lines;
  .tst.loadGraph.definedName[cx] each where (cx[`code]="{") and 0=cx`bBefore
 };
.tst.testState.lg.enclosing:{[lines]
  cx: .tst.testState.lg.cx lines;
  .tst.loadGraph.enclosingName[cx; .tst.testState.lg.off[cx; "system"]]
 };

.tst.desc["load graph: the function a load sits in"]{
  should["read the name a lambda is assigned to, however it is spaced"]{
    .tst.testState.lg.defined[enlist "f:{x}"] mustmatch enlist enlist "f";
    .tst.testState.lg.defined[enlist "f: {x}"] mustmatch enlist enlist "f";
    .tst.testState.lg.defined[enlist "f :{x}"] mustmatch enlist enlist "f";
    .tst.testState.lg.defined[enlist "f::{x}"] mustmatch enlist enlist "f";
    .tst.testState.lg.defined[enlist "f :: {x}"] mustmatch enlist enlist "f";
    .tst.testState.lg.defined[enlist ".a.b:{x}"] mustmatch enlist ".a.b";
    .tst.testState.lg.defined[enlist "x: 1; ff:{x}"] mustmatch enlist "ff";
  };

  should["give no name to a lambda that is not simply assigned"]{
    .tst.testState.lg.defined[enlist "g each {x}"] mustmatch enlist "";
    .tst.testState.lg.defined[enlist "{x}"] mustmatch enlist "";
    .tst.testState.lg.defined[enlist "d[`k]:{x}"] mustmatch enlist "";
    .tst.testState.lg.defined[enlist "d[0]:{x}"] mustmatch enlist "";
    .tst.testState.lg.defined[enlist "`f:{x}"] mustmatch enlist "";
    .tst.testState.lg.defined[enlist ":{x}"] mustmatch enlist "";
    .tst.testState.lg.defined[enlist "  {x}"] mustmatch enlist "";
  };

  should["qualify a bare name with the namespace, and leave a full one alone"]{
    names: .tst.testState.lg.defined ("\\d .lib"; "f:{x}"; ".abs.g:{x}"; "d[`k]:{x}");
    names mustmatch (".lib.f"; ".abs.g"; "");
  };

  should["name the outermost function around a load"]{
    .tst.testState.lg.enclosing[enlist "f:{[p] system \"l \",p};"] mustmatch enlist "f";
    .tst.testState.lg.enclosing[enlist "ff:{[ps] {system \"l \",x} each ps};"] mustmatch "ff";
    .tst.testState.lg.enclosing[("ff:{[p]"; "  system \"l \",p"; " };")] mustmatch "ff";
    .tst.testState.lg.enclosing[enlist "ff:{system \"l \",x}   / a loader"] mustmatch "ff";
  };

  should["name none when the lambda runs where it stands"]{
    .tst.testState.lg.enclosing[enlist "system \"l \",p;"] mustmatch "";
    .tst.testState.lg.enclosing[enlist "r: {system \"l \",x} each ps;"] mustmatch "";
    .tst.testState.lg.enclosing[enlist "r:{system \"l \",x}[p];"] mustmatch "";
    .tst.testState.lg.enclosing[enlist "r:{system \"l \",x}'[ps];"] mustmatch "";
    .tst.testState.lg.enclosing[enlist "ff:{system \"l \",x"] mustmatch "";
  };
 };

/ ===========================================================================
/ Behaviour of the whole graph that the tests above did not reach.
/ ===========================================================================

.tst.desc["load graph: loaders, however they are written"]{
  should["discover a loader whatever the spacing of its definition"]{
    r: .tst.testState.lg.graph[
      (enlist "lib/boot.q")!enlist (
        ".lib.a :{[p] system \"l \",p};";
        ".lib.b: {[p] system \"l \",p};";
        ".lib.c::{[p] system \"l \",p};";
        ".lib.d:{[ps] {system \"l \",x} each ps};");
      ()];
    l: r`loaders;
    must[all .tst.testState.lg.has[l] each (".lib.a"; ".lib.b"; ".lib.c"; ".lib.d"); .Q.s1 l];
    must[not .tst.testState.lg.dynamic[r; "lib/boot.q"]; "definitions are not loads: ", .Q.s1 r`why];
  };

  should["flag a lambda that loads where it stands, named or not"]{
    r: .tst.testState.lg.graph[
      ("now.q"; "anon.q"; "indexed.q"; "projected.q")!(
        enlist "loaded: {system \"l \",x} each paths;";
        enlist "{system \"l \",x} each paths;";
        ("\\d .lib"; "handlers[`load]:{[p] system \"l \",p};"; "\\d .");
        enlist "ld:{[root;p] system \"l \",root,p}[base];");
      ()];
    must[.tst.testState.lg.dynamic[r; "now.q"]; "the lambda is applied at once, so this file loads"];
    must[.tst.testState.lg.dynamic[r; "anon.q"]; "an unnamed lambda has no call sites to judge"];
    must[.tst.testState.lg.dynamic[r; "indexed.q"]; "nor has one stored in a dictionary"];
    must[.tst.testState.lg.dynamic[r; "projected.q"]; "what a projection was given cannot be read"];
    must[not any (r`loaders) like "loaded"; .Q.s1 r`loaders];
    must[not any (r`loaders) like ".lib.*"; .Q.s1 r`loaders];
  };

  should["keep a fully qualified name defined inside another namespace"]{
    r: .tst.testState.lg.graph[
      (enlist "lib/boot.q")!enlist ("\\d .lib"; ".abs.ld:{[p] system \"l \",p}"; "\\d .");
      ()];
    must[.tst.testState.lg.has[r`loaders; ".abs.ld"]; .Q.s1 r`loaders];
    must[not any (r`loaders) like ".lib.*"; .Q.s1 r`loaders];
  };

  should["recognise a root loader by its bare name only at root"]{
    r: .tst.testState.lg.graph[
      ("boot.q"; "use.q"; "ns.q")!(
        enlist "ld:{[p] system \"l \",p};";
        enlist "ld nm;";
        ("\\d .other"; "ld nm"; "\\d ."));
      ()];
    must[.tst.testState.lg.has[r`loaders; "ld"]; .Q.s1 r`loaders];
    must[.tst.testState.lg.dynamic[r; "use.q"]; "a root call with a variable is a load"];
    must[not .tst.testState.lg.dynamic[r; "ns.q"]; "inside a namespace the bare name is another function"];
  };

  should["not confuse .ld with a root function called ld"]{
    r: .tst.testState.lg.graph[
      ("boot.q"; "use.q"; "other.q")!(
        enlist ".ld:{[p] system \"l \",p};";
        enlist ".ld nm;";
        ("ld: {count x};"; "n: ld items;"));
      ()];
    must[.tst.testState.lg.dynamic[r; "use.q"]; "the loader called with a variable"];
    must[not .tst.testState.lg.dynamic[r; "other.q"]; "ld at root is not .ld: ", .Q.s1 r`why];
  };

  should["see a qualified loader called from inside another namespace"]{
    r: .tst.testState.lg.graph[
      (enlist "ns.q")!enlist ("\\d .other"; ".ext.load nm"; "\\d .");
      enlist ".ext.load"];
    must[.tst.testState.lg.dynamic[r; "ns.q"]; "a full name means the same function everywhere"];
  };

  should["match a loader's name only as a whole name"]{
    r: .tst.testState.lg.graph[
      ("longer.q"; "prefixed.q"; "symbol.q"; "real.q")!(
        enlist ".ext.loadAll nm;";
        enlist "my.ext.load nm;";
        enlist "names: `.ext.load`other;";
        enlist ".ext.load nm;");
      enlist ".ext.load"];
    must[not .tst.testState.lg.dynamic[r; "longer.q"]; "a longer name is another function"];
    must[not .tst.testState.lg.dynamic[r; "prefixed.q"]; "so is one it only ends"];
    must[not .tst.testState.lg.dynamic[r; "symbol.q"]; "a symbol spelling the name is not a call"];
    must[.tst.testState.lg.dynamic[r; "real.q"]; "the name itself is"];
  };

  should["take a symbol or a file handle as a fixed target"]{
    r: .tst.testState.lg.graph[
      ("spaced.q"; "tight.q"; "src/a.q")!(
        enlist ".ext.load `:src/a.q;";
        enlist ".ext.load`:src/a.q;";
        .tst.testState.lg.one);
      enlist ".ext.load"];
    must[not any r`dynamic; "a symbol naming a .q file is a fixed target: ", .Q.s1 r`why];
    .tst.testState.lg.deps[r; "spaced.q"] mustmatch enlist `$"src/a.q";
    .tst.testState.lg.deps[r; "tight.q"] mustmatch enlist `$"src/a.q";
  };

  should["resolve a loader's joined argument by its tail, and nothing more"]{
    r: .tst.testState.lg.graph[
      ("suffix.q"; "three.q"; "plain.q"; "src/order_impl.q"; "src/a.q"; "mysrc/a.q"; "src/unrelated.q")!(
        enlist ".ext.load prefix,\"_impl.q\";";
        enlist ".ext.load dir,\"a.q\";";
        enlist ".ext.load \"src/a.q\";";
        .tst.testState.lg.one; .tst.testState.lg.one; .tst.testState.lg.one; .tst.testState.lg.one);
      enlist ".ext.load"];
    must[not any r`dynamic; "a .q tail fixes the end of the name: ", .Q.s1 r`why];
    .tst.testState.lg.deps[r; "suffix.q"] mustmatch enlist `$"src/order_impl.q";
    / "a.q" joined onto a directory: every file whose path ends in a.q.
    .tst.testState.lg.deps[r; "three.q"] mustmatch .tst.testState.lg.syms ("mysrc/a.q"; "src/a.q");
    / A whole literal is a path: it ends at a component, so mysrc/ is not src/.
    .tst.testState.lg.deps[r; "plain.q"] mustmatch enlist `$"src/a.q";
  };

  should["list each loader once"]{
    r: .tst.testState.lg.graph[
      (enlist "lib/boot.q")!enlist (
        ".lib.ld:{[p] system \"l \",p};";
        ".lib.two:{[a;b] .lib.ld a; .lib.ld b};");
      (".lib.ld"; ".lib.ld")];
    l: r`loaders;
    must[(count l)=count distinct l; "no name twice: ", .Q.s1 l];
    must[.tst.testState.lg.has[l; ".lib.two"]; .Q.s1 l];
  };
 };

/ ---------------------------------------------------------------------------
.tst.desc["load graph: system loads assembled from parts"]{
  should["flag what has no fixed tail"]{
    r: .tst.testState.lg.graph[
      ("spaced.q"; "emptytail.q"; "three.q"; "src/a.q")!(
        enlist "system \"l \" , path;";
        enlist "system \"l \", path, \"\";";
        enlist "system \"l \", dir, \"a.q\";";
        .tst.testState.lg.one);
      ()];
    must[.tst.testState.lg.dynamic[r; "spaced.q"]; "a blank before the comma changes nothing"];
    must[.tst.testState.lg.dynamic[r; "emptytail.q"]; "an empty tail fixes nothing"];
    must[not .tst.testState.lg.dynamic[r; "three.q"]; "three characters ending in .q do: ", .Q.s1 r`why];
  };

  should["treat a tail that is not a .q file as a possible directory"]{
    r: .tst.testState.lg.graph[
      ("watched.q"; "elsewhere.q"; "src/a.q")!(
        enlist "system \"l \", root, \"/src\";";
        enlist "system \"l \", root, \"/other\";";
        .tst.testState.lg.one);
      ()];
    must[.tst.testState.lg.dynamic[r; "watched.q"]; "the tail names a watched directory"];
    .tst.testState.lg.why[r; "watched.q"] mustmatch enlist "loads a watched directory";
    must[not .tst.testState.lg.dynamic[r; "elsewhere.q"]; "a directory that is not watched is no dependency"];
  };

  should["match a directory by whole components unless only its end is known"]{
    / The only watched directory is mysrc/. "src" names it only as raw characters.
    r: .tst.testState.lg.graph[
      ("whole.q"; "byline.q"; "slashtail.q"; "rawtail.q"; "mysrc/a.q")!(
        enlist "system \"l src\";";
        enlist "\\l src";
        enlist "system \"l \", root, \"/src\";";
        enlist "system \"l \", prefix, \"src\";";
        .tst.testState.lg.one);
      ()];
    must[not .tst.testState.lg.dynamic[r; "whole.q"]; "src is not mysrc"];
    must[not .tst.testState.lg.dynamic[r; "byline.q"]; "src is not mysrc"];
    must[not .tst.testState.lg.dynamic[r; "slashtail.q"]; "/src is a whole component"];
    must[.tst.testState.lg.dynamic[r; "rawtail.q"]; "prefix,\"src\" could end in mysrc"];
  };

  should["flag a load of a one-letter directory and of the current one"]{
    r: .tst.testState.lg.graph[
      ("letter.q"; "here.q"; "bare.q"; "d/a.q")!(
        enlist "\\l d"; enlist "\\l ."; enlist "\\l "; .tst.testState.lg.one);
      ()];
    must[.tst.testState.lg.dynamic[r; "letter.q"]; "d is a watched directory"];
    must[.tst.testState.lg.dynamic[r; "here.q"]; "the current directory cannot be placed, so it counts"];
    must[not .tst.testState.lg.dynamic[r; "bare.q"]; "\\l with no target loads nothing"];
  };
 };

/ ---------------------------------------------------------------------------
.tst.desc["load graph: paths"]{
  should["reduce a literal to the components a path must end with"]{
    .tst.loadGraph.normalize[" src/a.q "] mustmatch "src/a.q";
    .tst.loadGraph.normalize[":src/a.q"] mustmatch "src/a.q";
    .tst.loadGraph.normalize["./a/../b/x.q"] mustmatch "b/x.q";
    .tst.loadGraph.normalize["../x.q"] mustmatch "x.q";
    .tst.loadGraph.normalize[enlist "."] mustmatch "";
  };

  should["test the end of a path"]{
    .tst.loadGraph.endsWith["/a.q"; "/x/a.q"] musteq 1b;
    .tst.loadGraph.endsWith["/a.q"; "/a.q"] musteq 1b;
    .tst.loadGraph.endsWith["/a.q"; "a.q"] musteq 0b;
    .tst.loadGraph.endsWith["b.q"; "/x/a.q"] musteq 0b;
  };

  should["match by components, and by raw characters"]{
    paths: ("/r/src/util.q"; "/r/mysrc/util.q"; "/r/src/myutil.q"; "/r/src/order_impl.q");
    byBase: group `$last each "/" vs/: paths;
    .tst.loadGraph.matchPath[paths; byBase; "src/util.q"] mustmatch enlist 0;
    .tst.loadGraph.matchPath[paths; byBase; "util.q"] mustmatch 0 1;
    (count .tst.loadGraph.matchPath[paths; byBase; "nothere.q"]) musteq 0;
    .tst.loadGraph.matchSuffix[paths; "_impl.q"] mustmatch enlist 3;
    .tst.loadGraph.matchSuffix[paths; "util.q"] mustmatch 0 1 2;
    .tst.loadGraph.matchSuffix[enlist "x.q"; "x.q"] mustmatch enlist 0;
  };

  should["collect the literals that name a .q file, each once"]{
    lx: .tst.loadGraph.lex (
      "\\l boot.q"; "\\l db";
      "a: \"pricing\"; b: \"x.q\"; c: \".q\"; d: \"x.q\"; i: \"seq\"; j: \"a.k\";";
      "e: `sym; f: `y.q; g: `.q; h: `:./lib/z.q; k: `seq; l: `a.k;");
    found: .tst.loadGraph.scanLiterals lx;
    (found`mentions) mustmatch ("boot.q"; "x.q"; "y.q"; "lib/z.q");
    (found`dirLoads) mustmatch enlist ("db"; 0b);
  };

  should["report the offset of each unresolved call"]{
    lx: .tst.loadGraph.lex enlist "x: 1; .ext.load nm; .ext.load \"a.q\";";
    found: first .tst.loadGraph.scanCalls[lx; enlist ".ext.load"];
    (found`dyn) mustmatch enlist 6;
    (count found`rawMentions) musteq 0;
  };
 };

/ ---------------------------------------------------------------------------
.tst.desc["load graph: what it remembers"]{
  should["flag a file that exists but cannot be read, and not one that is gone"]{
    root: .tst.testState.lg.project (enlist "t.q")!enlist .tst.testState.lg.one;
    system "mkdir -p ", .utl.shellQuote root, "/odd.q";
    tracked: `$(root, "/t.q"; root, "/odd.q"; root, "/gone.q");
    .tst.loadGraph.reset[];
    g: .tst.loadGraph.build[tracked; 1 1 1; ()];
    system "rm -rf ", .utl.shellQuote root;
    (g`dynamic) mustmatch 010b;
    (g[`why] 1) mustmatch enlist "file could not be read";
  };

  should["forget a file that is no longer tracked, and hold one entry per file"]{
    root: .tst.testState.lg.project ("a.q"; "b.q")!(.tst.testState.lg.one; .tst.testState.lg.one);
    both: `$(root, "/a.q"; root, "/b.q");
    .tst.loadGraph.reset[];
    .tst.loadGraph.build[both; 1 1; ()];
    two: count .tst.loadGraph.cache;
    .tst.loadGraph.build[1#both; enlist 1; ()];
    one: key .tst.loadGraph.cache;
    .tst.loadGraph.build[both 0 0; 1 1; ()];
    twice: count .tst.loadGraph.cache;
    system "rm -rf ", .utl.shellQuote root;
    two musteq 2;
    one mustmatch enlist `$root, "/a.q";
    twice musteq 1;
  };

  should["remember which loader names a file has been scanned for"]{
    root: .tst.testState.lg.project (enlist "a.q")!enlist enlist ".ext.load nm;";
    path: root, "/a.q";
    .tst.loadGraph.reset[];
    .tst.loadGraph.build[enlist `$path; enlist 1; enlist ".ext.load"];
    scanned: .tst.loadGraph.cache[`$path] 3;
    system "rm -rf ", .utl.shellQuote root;
    must[.tst.testState.lg.has[scanned; ".ext.load"]; .Q.s1 scanned];
    must[(count scanned)=count distinct scanned; "each name once: ", .Q.s1 scanned];
  };

  should["reach each file once through a diamond, whatever the seeds"]{
    r: .tst.testState.lg.graph[
      ("t.q"; "a.q"; "b.q"; "c.q"; "lone.q")!(
        ("\\l a.q"; "\\l b.q"); enlist "\\l c.q"; enlist "\\l c.q";
        .tst.testState.lg.one; .tst.testState.lg.one);
      ()];
    c: .tst.testState.lg.at[r; "c.q"];
    reached: .tst.loadGraph.loadedBy[r`g; (c; c)];
    (asc r[`files] reached) mustmatch .tst.testState.lg.syms ("a.q"; "b.q"; "c.q"; "t.q");
    (count reached) musteq 4;
  };
 };
