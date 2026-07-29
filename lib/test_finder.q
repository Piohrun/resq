/ lib/test_finder.q - Enterprise Interactive Test Discovery
/ ============================================================================

/ Load Static Analysis Library
.utl.require .utl.PKGLOADING,"/static_analysis.q"

/ Proxy functions to static analysis library
.tst.exploreFile: .tst.static.exploreFile
.tst.toStr: .tst.static.toStr
.tst.getDir: .tst.static.getDir
.tst.getBase: .tst.static.getBase
.tst.normalizePath: .tst.static.normalizePath
.tst.findSources: .tst.static.findSources

.tst.static.htmlEscape:{[input]
  s0: .tst.static.toStr input;
  s1: ssr[s0; enlist "&"; "&amp;"];
  s2: ssr[s1; enlist "<"; "&lt;"];
  s3: ssr[s2; enlist ">"; "&gt;"];
  s4: ssr[s3; enlist "\""; "&quot;"];
  ssr[s4; enlist "'"; "&#39;"]
 };

/ Generate a stylized HTML coverage report
.tst.genHtmlReport:{[stats;outFile]
  h: enlist "<html><head><title>resQ Coverage Report</title>";
  h,: enlist "<style>";
  h,: enlist "body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 40px; background: #f4f7f6; }";
  h,: enlist ".container { background: white; padding: 30px; border-radius: 8px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }";
  h,: enlist "h1 { color: #333; border-bottom: 2px solid #0078d4; padding-bottom: 10px; }";
  h,: enlist "table { width: 100%; border-collapse: collapse; margin-top: 20px; }";
  h,: enlist "th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }";
  h,: enlist "th { background: #f8f9fa; color: #555; }";
  h,: enlist ".progress-bg { background: #e9ecef; border-radius: 4px; width: 100px; height: 12px; display: inline-block; }";
  h,: enlist ".progress-fill { background: #28a745; height: 100%; border-radius: 4px; }";
  h,: enlist ".low { background: #dc3545 !important; }";
  h,: enlist ".med { background: #ffc107 !important; }";
  h,: enlist "</style></head><body>";
  h,: enlist "<div class='container'>";
  h,: enlist "<h1>Project Coverage Report</h1>";
  h,: enlist "<table><thead><tr><th>Directory</th><th>Coverage (%)</th><th>Stats (Cov/Tot)</th></tr></thead><tbody>";
  
  rows: {[r]
    dStr: $[(string r`dir)~""; "."; string r`dir];
    dStr: .tst.static.htmlEscape dStr;
    pct: floor r`pct;
    cls: $[pct < 50; "low"; pct < 80; "med"; ""];
    row: "<tr><td>", dStr, "</td>";
    row,: "<td><div class='progress-bg'><div class='progress-fill ",cls,"' style='width: ",(string pct),"%'></div></div> ";
    row,: (string pct), "%</td>";
    row,: "<td>", (string r`covered), " / ", (string r`total), "</td></tr>";
    row
  } each stats;
  h,: rows;
  
  h,: enlist "</tbody></table></div></body></html>";
  outPath: .tst.static.toStr outFile;
  wrote: .[{[path;lines]
      (hsym `$path) 0: lines;
      1b
    }; (outPath;h); {[path;e]
      -2 "DISCOVERY ERROR: Unable to write HTML report ",path,": ",e;
      0b
    }[outPath]];
  if[not wrote; '"Unable to write discovery HTML report: ",outPath];
  -1 "HTML Report written to: ", outPath;
 };

.tst.static.readExecutableTokens:{[path]
  p: .tst.static.toStr path;
  result: @[{(1b;.tst.static.executableTokens read0 hsym `$x)}; p; {[p;e]
      .tst.static.warn "Cannot read test source ",p,": ",e;
      (0b;())
    }[p]];
  $[first result; last result; ()]
 };

/ Scan tests for coverage
.tst.checkCoverage:{[srcFns;testDir]
  if[not count srcFns; :srcFns];
  testPaths: .tst.findSources[testDir];
  if[not 98h=type srcFns; srcFns: enlist srcFns];
  ns: exec name from srcFns;
  refs:();
  if[count testPaths;
    refs: distinct raze .tst.static.readExecutableTokens each testPaths];
  res: {.tst.static.toStr[x] in y}[;refs] each ns;
  ![srcFns; (); 0b; enlist[`covered]!enlist res]
 };

/ Aggregate coverage stats per directory
.tst.getDirStats:{[cvg;baseDir]
  b: .tst.toStr baseDir;
  b: $[b like ":*"; 1 _ b; b];
  if[(count b) and not "/"=last b; b,: "/"];
  
  cvg: 0!cvg;
  if[not `relPath in cols cvg;
    fns: { $[x like ":*"; 1 _ x; x] } each .tst.toStr each exec srcFile from cvg;
    rs: { [f;b] $[f like b, "*"; (count b) _ f; f] }[;b] each fns;
    cvg: cvg ^ ([] relPath: rs);
  ];
  
  allRel: exec relPath from cvg;
  allCov: exec covered from cvg;
  ds: distinct .tst.getDir each allRel;
  stats: ([] dir: `$ds);
  
  tots: (count stats) # 0j;
  covs: (count stats) # 0j;
  i: 0;
  do[count stats;
    d: .tst.toStr (stats i)`dir;
    m: allRel like d, "*";
    tots[i]: sum m;
    covs[i]: sum m and allCov;
    i+: 1;
  ];
  
  stats: update total: tots, covered: covs from stats;
  update pct: ?[total>0; 100f * covered % total; 0f] from stats
 };

/ ASCII tree display
.tst.drawTree:{[stats]
  -1 "\nProject Coverage Tree:";
  -1 "-----------------------";
  stats: `dir xasc stats;
  {[r] 
    / Use robust string conversion (handles symbol lists and null symbols)
    d: .tst.toString r`dir;
    / Ensure default is a string (not a char atom)
    dStr: $[(count d) and not d~"."; d; "\".\""];
    depth: count dStr ss "/";
    if[dStr like "*/"; depth-: 1];
    if[depth < 0; depth: 0];
    
    indent: (depth * 2) # " ";
    prefix: $[depth <= 0; "DIR "; "|- "];
    pct: floor r`pct;
    bar: (ceiling 15 * pct % 100) # "#";
    bar: 15 # bar, (15 - count bar) # ".";
    -1 indent, prefix, dStr, " [", bar, "] ", (string pct), "% (", (string r`covered), "/", (string r`total), ")";
  } each stats;
 };

.tst.static.safeCommentText:{[input]
  s:.tst.static.toStr input;
  codes:"i"$s;
  @[s; where (codes<32) or (codes=127); :; " "]
 };

.tst.static.qStringEscape:{[input]
  s:.tst.static.safeCommentText input;
  ssr[ssr[s; enlist "\\"; "\\\\"]; enlist "\""; "\\\""]
 };

/ A generated relative path must be a plain descendant path. Reject both POSIX
/ and Windows separators/control forms before any directory or file operation.
.tst.static.validateGeneratedRelative:{[relative]
  rel:.tst.static.toStr relative;
  if[not count rel; '"Unsafe generated relative path: empty"];
  if["/"=first rel; '"Unsafe generated relative path: absolute path"];
  if[any rel in "\\:";
      '"Unsafe generated relative path: alternate separator or drive form"];
  codes:"i"$rel;
  if[any (codes<32) or (codes=127);
      '"Unsafe generated relative path: control character"];
  parts:"/" vs rel;
  if[any parts in ("";".";"..");
      '"Unsafe generated relative path: traversal component"];
  rel
 };

.tst.static.absolutePath:{[path]
  p:.tst.static.toStr path;
  p:$[p like ":*";1_p;p];
  if[not count p; p:"."];
  p:ssr[p;enlist "\\";enlist "/"];
  hasDrive:(1<count p) and ":"=p 1;
  isDrive:hasDrive and ((2<count p) and "/"=p 2);
  if[hasDrive and not isDrive;
      '"Unsafe generated output root: drive-relative path"];
  isUnc:p like "//*";
  isAbsolute:("/"=first p) or isDrive;
  normalized:.utl.normalizePath $[isAbsolute;p;(system "cd"),"/",p];
  $[isUnc and not normalized like "//*";"/",normalized;normalized]
 };

.tst.static.containedGeneratedPath:{[root;relative]
  rel:.tst.static.validateGeneratedRelative relative;
  absoluteRoot:.tst.static.absolutePath root;
  target:.tst.static.absolutePath absoluteRoot,"/",rel;
  compareRoot:$[.utl.isWindows;lower absoluteRoot;absoluteRoot];
  compareTarget:$[.utl.isWindows;lower target;target];
  prefix:$["/"=last compareRoot;compareRoot;compareRoot,"/"];
  contained:(count compareTarget)>=count prefix;
  if[contained; contained:prefix~(count prefix)#compareTarget];
  if[not contained; '"Unsafe generated relative path: escaped output root"];
  target
 };

/ Refuse a pre-existing symlink in the generated directory chain. This keeps a
/ lexical descendant from being redirected outside the requested output root.
.tst.static.ensureGeneratedDir:{[root;relativeDir]
  absoluteRoot:.tst.static.absolutePath root;
  if[.tst.static.isSymlink absoluteRoot;
      '"Unsafe generated output directory: root is a symlink"];
  .utl.ensureDir absoluteRoot;
  if[not .utl.isDir absoluteRoot;
      '"Unable to create generated output directory: ",absoluteRoot];
  if[not count relativeDir; :absoluteRoot];

  rel:.tst.static.validateGeneratedRelative relativeDir;
  parts:"/" vs rel;
  current:absoluteRoot;
  i:0;
  while[i<count parts;
    current:.tst.static.containedGeneratedPath[
      absoluteRoot; "/" sv (i+1)#parts];
    if[.utl.pathExists current;
      if[.tst.static.isSymlink current;
        '"Unsafe generated output directory: symlink component ",current]];
    if[not .utl.pathExists current; .utl.ensureDir current];
    if[not .utl.isDir current;
      '"Unable to create generated output directory: ",current];
    i+:1;
  ];
  current
 };

.tst.static.dependencyHint:{[dependencies]
  deps:$[-11h=type dependencies; enlist dependencies;
         11h=type dependencies; (),dependencies;
         0h=type dependencies; raze dependencies;
         `symbol$()];
  deps:deps where not null deps;
  $[count deps;
      .tst.static.safeCommentText ", " sv string deps;
      ""]
 };

.tst.static.argumentHint:{[arguments]
  args:$[10h=type arguments; enlist arguments;
         0h=type arguments; arguments;
         ()];
  args:args where 0<count each args;
  $[count args;
      ", " sv .tst.static.safeCommentText each args;
      ""]
 };

.tst.static.generatedLines:{[sourceFile;functions]
  lines:(
    "/ Automated pending tests for statically unreferenced functions";
    "/ Target: ",.tst.static.safeCommentText sourceFile;
    "";
    ".tst.desc[\"Generated discovery TODOs\"]{");
  i:0;
  while[i<count functions;
    row:functions i;
    functionName:.tst.static.toStr row`name;
    lines,:enlist "  / Function: ",.tst.static.safeCommentText functionName;
    args:.tst.static.argumentHint row`args;
    if[count args; lines,:enlist "  / Arguments: ",args];
    dependencies:.tst.static.dependencyHint row`dependencies;
    if[count dependencies;
      lines,:enlist "  / Dependencies detected: ",dependencies];
    lines,:enlist "  .tst.pending[\"TODO: add coverage for ",
      .tst.static.qStringEscape[functionName],"\"];";
    lines,:enlist "";
    i+:1;
  ];
  lines,:enlist "};";
  lines
 };

/ Generate Mirrored Boilerplate with dependency/argument hints.
.tst.genMirror:{[untested;baseDir;outDir]
  if[not count untested; :()];
  od: .tst.static.absolutePath outDir;
  -1 "Mirroring structure to: ", od;
  .tst.static.ensureGeneratedDir[od;""];
  b: .tst.toStr baseDir;
  if[(count b) and not "/"=last b; b,: "/"];

  u: 0!untested;
  sourceFiles:asc distinct exec srcFile from u;
  i:0;
  while[i<count sourceFiles;
    f:sourceFiles i;
    fns:select from u where srcFile=f;
    fns:`line`name xasc fns;
    rel: .tst.normalizePath[f;b];
    rel:.tst.static.validateGeneratedRelative rel;
    dirP: .tst.getDir rel;
    baseN: .tst.getBase rel;
    if[baseN like "*.q"; baseN:(-2+count baseN)#baseN];
    targetRel:dirP,"test_",baseN,".q";
    targetRel:.tst.static.validateGeneratedRelative targetRel;
    target:.tst.static.containedGeneratedPath[od;targetRel];
    .tst.static.ensureGeneratedDir[
      od;
      $[count dirP; -1_dirP; ""]];

    if[.utl.pathExists target;
        -1 "  -> Skipped (Exists): ", target;
    ];

    if[not .utl.pathExists target;
        lines:.tst.static.generatedLines[f;fns];
        wrote:.[{[path;content]
            (hsym `$path) 0: content;
            1b
          };(target;lines);{[path;e]
            -2 "DISCOVERY ERROR: Unable to write generated test ",path,": ",e;
            0b
          }[target]];
        if[not wrote; '"Unable to write generated discovery test: ",target];
        -1 "  -> Created: ", target;
    ];
    i+:1;
  ];
  ()
 };

/ --- Interactive Flow ---

.tst.start:{[]
  -1 "\n=== RESQ DISCOVERY ENGINE ===";
  -1 "Enter Source Directory (default: examples/quickstart/src):";
  src: first read0 0; if[not count src; src: "examples/quickstart/src"];
  -1 "Enter Test Directory (default: examples/quickstart/test):";
  tst: first read0 0; if[not count tst; tst: "examples/quickstart/test"];
  
  -1 "\nScanning codebase...";
  f: .tst.findSources src;
  a: raze .tst.exploreFile each hsym each f;
  
  -1 "Analyzing coverage...";
  c: .tst.checkCoverage[a; tst];
  s: .tst.getDirStats[c; src];
  .tst.drawTree s;
  
  u: select from c where not covered;
  if[not count u; -1 "\nSUCCESS: 100% coverage achieved!"; :()];
  
  -1 "\nFound ",(string count u)," untested functions.";
  -1 "Generate mirrored boilerplate and directory structure? (y/n)";
  ans: first first read0 0;
  if[ans in "yY";
    -1 "Target directory (default: missingTests):";
    out: first read0 0; if[not count out; out: "missingTests"];
    .tst.genMirror[u; src; out];
    -1 "\nBoilerplate generated.";
  ];
  -1 "\nDiscovery process complete.";
 };

.tst.main:{[src;tst]
  -1 "--- [resQ Discovery] ---";
  -1 "Scanning: ", .tst.toStr src;
  f: .tst.findSources src;
  -1 "Files found: ",(string count f);
  if[not count f; :()];
  a: raze .tst.exploreFile each hsym each f;
  -1 "Functions: ",(string count a);
  c: .tst.checkCoverage[a; tst];
  -1 "Coverage analyzed.";
  s: .tst.getDirStats[c; src];
  -1 "Stats calculated.";
  .tst.drawTree s;
  
  / Generate HTML Report
  -1 "Generating HTML report...";
  .tst.genHtmlReport[s; "coverage_report.html"];
  
  u: select from c where not covered;
  -1 "Untested: ",(string count u);
  if[0<count u; 
    -1 "Mirroring structure...";
    .tst.genMirror[u; src; "missingTests"];
    exit 1; / Fail CI if coverage is missing
  ];
  -1 "Discovery complete. 100% Coverage.";
  exit 0;
 };
