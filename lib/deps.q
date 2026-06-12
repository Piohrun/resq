\d .tst

/ Dependency Graph Builder
depGraph: ()!();
dependencies: ()!();

/. Keep parse/scan helpers local and dependency-free by loading static analysis utilities here.
.utl.require .utl.PKGLOADING,"/static_analysis.q"

/ Parse a .q file for load directives
parseLoadDirectives:{[filepath]
    filepath: $[10h = abs type filepath; `$filepath; filepath];
    if[() ~ key hsym filepath; :()];

    lines: read0 hsym filepath;

    / Drop comment lines and detection-pattern lines. A line whose trimmed
    / form starts with "/" is a comment; a line containing "like" is the
    / scanner's own pattern code (e.g. lines like "*.utl.require*") and must
    / not be mistaken for an actual require -- ingesting those produced fake
    / "*"-patterned keys.
    lines: lines where not (trim each lines) like "/*";

    / Find \l directives
    loadLines: lines where (lines like "\\l *") and not lines like "*like*";
    loaded: `${x where not x in " \t"} each {3 _ x} each loadLines;

    / Find .utl.require calls. Skip lines that are pattern/detection code
    / (they contain "like") so the scanner does not ingest its own literals.
    m1: lines like "*.utl.require*";
    m2: (lines like "*require*") and (lines like "*\"*");
    requireLines: lines where (m1 or m2) and not lines like "*like*";

    / Extract paths from quotes
    qChar: first "\"";
    required: raze {
        parts: y vs x;
        $[2 <= count parts; enlist `$parts 1; ()]
    }[;qChar] each requireLines;

    distinct loaded, required
 };

/ Resolve a raw require/load target to the same absolute, normalized form
/ used for graph keys. Targets are captured as quoted strings (often the
/ ".../<name>.q" tail of `.utl.PKGLOADING,"/<name>.q"`), so they are resolved
/ against the requiring file's directory. Falls back to the target as-is when
/ the resolved file does not exist, so unresolvable targets stay honest.
resolveDepTarget:{[reqFile; target]
    t: .tst.static.toStr target;
    if[0 = count t; :`$t];
    reqDir: .tst.static.getDir .tst.static.toStr reqFile;
    / Strip a leading "/" so a PKGLOADING-tail like "/static_analysis.q"
    / joins onto the requiring directory rather than the filesystem root.
    rel: $["/" = first t; 1 _ t; t];
    cand: $[count reqDir; reqDir, rel; rel];
    $[not () ~ key hsym `$cand; `$cand;
      not () ~ key hsym `$t; `$t;
      `$cand]
 };

/ Build dependency graph for directory
scanDirectory:{[dir]
    / Find all .q files recursively using q-native directory traversal.
    rootDir: .tst.static.toStr dir;
    if[0 = count rootDir; :`symbol$()];
    files: .tst.static.findSources rootDir;
    files: files where files like "*.q";

    {[f]
        rawDeps: .tst.parseLoadDirectives[f];
        / Resolve each target to the absolute-normalized form used for keys so
        / the reverse graph is actually traversable by path.
        fileDeps: .tst.resolveDepTarget[f;] each rawDeps;
        / Drop any "*"-patterned fake keys that slipped through (e.g. ingested
        / detection literals). Test for a literal "*" char in each symbol.
        if[count fileDeps; fileDeps: fileDeps where not {"*" in x} each string each fileDeps];
        .tst.dependencies[f]: fileDeps;

       / Update reverse graph
        {[dep;dependent]
            if[not dep in key .tst.depGraph; .tst.depGraph[dep]: ()];
            .tst.depGraph[dep],: dependent;
        }[;f] each fileDeps;
    } each files;
    
    .tst.depGraph
 };

/ Get all files that depend on a given file. Threads a `seen` accumulator
/ through the recursion so circular requires (A→B→A) do not blow the stack.
getDependents:{[file] .tst.getDependentsAcc[file; `symbol$()]};

getDependentsAcc:{[file; seen]
    if[file in seen; :`symbol$()];
    seen,: file;
    direct: $[file in key .tst.depGraph; .tst.depGraph[file]; `symbol$()];
    transitive: distinct raze .tst.getDependentsAcc[; seen] each direct;
    distinct direct, transitive
 };

/ Get dependencies of a file  
getDependencies:{[file]
    $[file in key .tst.dependencies; .tst.dependencies[file]; ()]
 };

/ Rebuild dependency graph
rebuildGraph:{[dirs]
    .tst.depGraph:: ()!();
    .tst.dependencies:: ()!();
    {.tst.scanDirectory[x]} each dirs;
    -1 "Dependency graph built: ", string[count .tst.depGraph], " files tracked";
 };

\d .
::
