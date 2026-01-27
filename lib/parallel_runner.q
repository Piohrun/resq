\d .tst

/ Parallel Runner Configuration
nWorkers: abs system "s"
if[nWorkers=0; nWorkers: 1]

/ Check if a test file needs sequential execution
isSequential:{[f]
  any read0[hsym f] like "*#sequential*"
 }

/ Run a single test file and return results
runFile:{[f]
  -1 "Process ",(string .z.i)," -> ",(string f);
  .tst.specs: ();
  .tst.callbacks.descLoaded:{.tst.specs,:enlist x};
  
  @[{system "l ",string x}; f; {-1 "Error loading ",(string x),": ",y} [f]];
  
  res: .tst.runSpec each .tst.specs;
  res
 }

/ Main parallel execution entry point
runParallel:{[paths]
  allFiles: findTests paths;
  
  / Filter files that MUST be run sequentially
  seqFiles: allFiles where isSequential each allFiles;
  parFiles: allFiles except seqFiles;
  
  -1 "Execution Plan:";
  -1 "  Parallel:   ", (string count parFiles), " files (Workers: ",(string nWorkers),")";
  -1 "  Sequential: ", (string count seqFiles), " files";
  
  / Run Parallel
  results: $[(nWorkers > 1) and count parFiles;
    raze runFile peach parFiles;
    raze runFile each parFiles
  ];
  
  / Run Sequential
  if[0<count seqFiles;
    results,: raze runFile each seqFiles;
  ];
  
  results
 }

\d .
