.tst.testState.selfcov.canRun:
    (0<count @[system;"command -v python3 2>/dev/null";{()}]) and
    (0<count @[system;"command -v q 2>/dev/null";{()}]);

.tst.desc["optional external self-coverage evidence"]{
  skipIf[not .tst.testState.selfcov.canRun;
         "wrap the runner through an external provider and label the evidence honestly"]{
    wd:.utl.tempRoot[],"/resq_selfcov_",string[.z.i],"_",string `long$.z.p;
    cmd:"python3 ",.utl.shellQuote[.resq.HOME,"/tools/run_self_coverage.py"],
        " --library ",.utl.shellQuote[.resq.HOME,"/tests/fixtures/self_coverage/fake_cov.q"],
        " --output ",.utl.shellQuote[wd]," --q q -- test ",
        .utl.shellQuote[.resq.HOME,"/tests/fixtures/sharding/shard_a.q"],
        " -strict -quiet -state-file ",.utl.shellQuote[wd,"/state.json"],
        " -flake-history ",.utl.shellQuote[wd,"/flake.json"],
        " -quarantine-file ",.utl.shellQuote[wd,"/quarantine.json"],
        " -flake-proposal-file ",.utl.shellQuote[wd,"/proposals.json"],
        " > ",.utl.shellQuote[wd,".out"]," 2>&1; echo $?";
    code:"J"$last @[system;"sh -c ",.utl.shellQuote cmd;{[e]enlist "-1"}];
    raw:@[read0;hsym `$wd,"/self-coverage.json";{()}];
    text:@[read0;hsym `$wd,"/self-coverage.txt";{()}];
    doc:$[count raw;.j.k "\n" sv raw;()!()];
    if[wd like "*/resq_selfcov_*";system "rm -rf -- ",.utl.shellQuote wd];

    code musteq 0j;
    doc[`schemaVersion] musteq 1f;
    doc[`kind] musteq "resq-self-coverage";
    doc[`measurement;`provider] musteq "KX Developer .cov";
    doc[`measurement;`complete] musteq 0b;
    doc[`measurement;`gatingSupported] musteq 0b;
    doc[`summary;`functionsMeasured] musteq 1f;
    doc[`summary;`logicalLinesHit] musteq 2f;
    doc[`summary;`blocksHit] musteq 1f;
    must[any text like "*not a release gate*";"the human artifact must carry the caveat"];
  };
 };

::
