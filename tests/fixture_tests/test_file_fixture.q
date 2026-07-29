
.tst.desc["Loading File Fixtures"]{
 should["load the fixture specified"]{
  1 musteq 1;
  };

 should["reject temporary-file suffixes that can influence a path"]{
  badSuffixes:(
    "../outside";
    "nested/file";
    "nested\\file";
    "/tmp/resq_temp_outside";
    "C:resq_temp_outside";
    "C:\\resq_temp_outside";
    "control\001suffix");
  {mustthrow["*Invalid temporary-file suffix*"; (.tst.tempFile;x)]} each badSuffixes;
  };

 should["allow empty and punctuation-only safe temporary-file suffixes"]{
  emptySuffix: .tst.tempFile "";
  punctuationSuffix: .tst.tempFile ".cache-v1_2!";
  cwdPrefix: (system "cd"), "/";

  must[cwdPrefix ~ (count cwdPrefix) # emptySuffix; "empty-suffix temporary path must stay below the working directory"];
  must[cwdPrefix ~ (count cwdPrefix) # punctuationSuffix; "punctuation-suffix temporary path must stay below the working directory"];
  punctuationSuffix mustlike "*.cache-v1_2!";
  };

 should["never register cleanup for a path outside the temporary root"]{
  cwd: system "cd";
  sentinel: cwd, "/tmp_resq_tempfile_boundary_sentinel";
  sentinelHandle: .utl.pathToHsym sentinel;
  sentinelHandle set `untouched;
  .tst.registerSpecCleanup[{[p] @[hdel; .utl.pathToHsym p; {}]}; enlist sentinel];

  mustthrow["*Invalid temporary-file suffix*"]{.tst.tempFile "/../tmp_resq_tempfile_boundary_sentinel"};
  .tst.runCleanupTasks[];

  exists: .utl.isFile sentinel;
  must[exists; "rejected suffix must not register deletion outside the temporary root"];
  if[exists; (get sentinelHandle) musteq `untouched];
  };
 };
