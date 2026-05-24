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
    
    / Find \l directives
    loadLines: lines where lines like "\\l *";
    loaded: `${x where not x in " \t"} each {3 _ x} each loadLines;
    
    / Find .utl.require calls
    m1: lines like "*.utl.require*";
    m2: (lines like "*require*") and (lines like "*\"*");
    requireLines: lines where m1 or m2;
    
    / Extract paths from quotes
    qChar: first "\"";
    required: raze {
        parts: y vs x;
        $[2 <= count parts; enlist `$parts 1; ()]
    }[;qChar] each requireLines;
    
    distinct loaded, required
 };

/ Build dependency graph for directory
scanDirectory:{[dir]
    / Find all .q files recursively using q-native directory traversal.
    rootDir: .tst.static.toStr dir;
    if[0 = count rootDir; :`symbol$()];
    files: .tst.static.findSources rootDir;
    files: files where files like "*.q";

    {[f] 
        fileDeps: .tst.parseLoadDirectives[f];
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
