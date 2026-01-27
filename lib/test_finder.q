/ lib/test_finder.q - Enterprise Interactive Test Discovery
/ ============================================================================

/ Load Static Analysis Library
.utl.require "lib/static_analysis.q"

/ Proxy functions to static analysis library
.tst.exploreFile: .tst.static.exploreFile
.tst.findDeps: .tst.static.findDeps
.tst.toStr: .tst.static.toStr
.tst.getDir: .tst.static.getDir
.tst.getBase: .tst.static.getBase
.tst.normalizePath: .tst.static.normalizePath
.tst.findSources: .tst.static.findSources

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
  
  {[r] 
    dStr: $[(string r`dir)~""; "."; string r`dir];
    pct: floor r`pct;
    cls: $[pct < 50; "low"; pct < 80; "med"; ""];
    row: "<tr><td>", dStr, "</td>";
    row,: "<td><div class='progress-bg'><div class='progress-fill ",cls,"' style='width: ",(string pct),"%'></div></div> ";
    row,: (string pct), "%</td>";
    row,: "<td>", (string r`covered), " / ", (string r`total), "</td></tr>";
    h,: enlist row;
  } each stats;
  
  h,: enlist "</tbody></table></div></body></html>";
  hsym[`$outFile] 0: h;
  -1 "HTML Report written to: ", outFile;
 };

/ Scan tests for coverage
.tst.checkCoverage:{[srcFns;testDir]
  if[not count srcFns; :srcFns];
  testPaths: .tst.findSources[testDir];
  tc: $[0<count testPaths; raze raze read0 each hsym each testPaths; ""];
  if[not 98h=type srcFns; srcFns: enlist srcFns];
  ns: exec name from srcFns;
  res: `boolean$();
  i: 0;
  do[count ns;
    nStr: .tst.toStr ns i;
    match: tc like "*", nStr, "*";
    res,: match;
    i+: 1;
  ];
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
    prefix: $[depth <= 0; "📁 "; "|- "];
    pct: floor r`pct;
    bar: (ceiling 15 * pct % 100) # "#";
    bar: 15 # bar, (15 - count bar) # ".";
    -1 indent, prefix, dStr, " [", bar, "] ", (string pct), "% (", (string r`covered), "/", (string r`total), ")";
  } each stats;
 };

/ Generate Mirrored Boilerplate with Dependency Mocks
.tst.genMirror:{[untested;baseDir;outDir]
  if[not count untested; :()];
  od: .tst.toStr outDir;
  -1 "Mirroring structure to: ", od;
  system "mkdir -p ", od;
  b: .tst.toStr baseDir;
  if[(count b) and not "/"=last b; b,: "/"];

  / Brace characters for template generation
  LB: enlist "c"$123;  / "{"
  RB: enlist "c"$125;  / "}"

  u: 0!untested;
  / Grouping by srcFile name to get indices per file
  idxMap: group exec srcFile from u;
  k: key idxMap;

  do[count k;
    f: k 0;
    fns: u @ idxMap f;
    rel: .tst.normalizePath[f;b];
    dirP: .tst.getDir rel;

    td: od, $[(count dirP) and not dirP~"/"; "/", dirP; ""];
    system "mkdir -p ", td;

    baseN: .tst.getBase rel;
    if[baseN like "*.q"; baseN: ((-2 + count baseN) # baseN)];
    target: td, $[("/"=last td) or "/"=first baseN; ""; "/"], "test_", baseN, ".q";

    if[not () ~ key hsym `$target;
        -1 "  -> Skipped (Exists): ", target;
    ];

    if[() ~ key hsym `$target;
        xml: enlist "/ Automated Boilerplate for Untested Functions";
        xml,: enlist "/ Target: ", .tst.toStr f;
        xml,: enlist "";
        j: 0;
        do[count fns;
          r: fns j;
          xml,: enlist "should[\"work with ",( .tst.toStr r`name),"\"; ", LB, "[]";

          / Add Mock Suggestions - deps is stored as enlist of symbol list
          deps: r`dependencies;
          / Unwrap the enlist and filter empty
          deps: $[0h=type deps; raze deps; deps];
          deps: deps where not null deps;
          if[0<count deps;
              xml,: enlist "  / Dependencies detected: ", ( ", " sv string deps);
              / Build mock lines without lambda to avoid closure issues
              mockLines: {[LB;RB;x] "  .resq.mock[`",string[x],"; ",LB,"[args] (::)",RB,"];"}[LB;RB] each deps;
              xml,: mockLines;
              xml,: enlist "";
          ];

          argsP: $[0<count r`args; ";" sv (count r`args)#enlist "fixture"; ""];
          xml,: enlist "  res: ",( .tst.toStr r`name),"[",argsP,"];";
          xml,: enlist "  res mustmatch expectedValue;";
          xml,: enlist RB, "];\n";
          j+: 1;
        ];
        hsym[`$target] 0: xml;
        -1 "  -> Created: ", target;
    ];
    k: 1 _ k;
  ];
 };

/ --- Interactive Flow ---

.tst.start:{[]
  -1 "\n=== 🛡️ resQ DISCOVERY ENGINE ===";
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
  if[not count u; -1 "\n✅ SUCCESS: 100% coverage achieved!"; :()];
  
  -1 "\nFound ",(string count u)," untested functions.";
  -1 "Generate mirrored boilerplate and directory structure? (y/n)";
  ans: first first read0 0;
  if[ans in "yY";
    -1 "Target directory (default: missingTests):";
    out: first read0 0; if[not count out; out: "missingTests"];
    .tst.genMirror[u; src; out];
    -1 "\n🚀 Boilerplate generated.";
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
  -1 "✅ Discovery complete. 100% Coverage.";
  exit 0;
 };
