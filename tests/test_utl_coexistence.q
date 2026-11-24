/ `.utl` is qutil's namespace and the name many teams give their own
/ utilities. resQ keeps its helpers in .resq, reads nothing from .utl, and
/ offers .utl names only where they are free. A team .utl that defines the
/ same names with other meanings must neither break resQ nor be replaced.
/ Run in child processes: one loads the team's .utl at q start-up (QINIT),
/ the other from a test file.

.tst.testState.utlco.canRun:
    (0 < count @[system; "which q 2>/dev/null"; {()}]) and
    (0 < count @[system; "which timeout 2>/dev/null"; {()}]);

.tst.testState.utlco.teamUtl: (
    "\\d .utl";
    "isDir:{[p] 0b}";
    "isFile:{[p] `file ~ first p}";
    "pathExists:{[p] not () ~ key hsym p}";
    "require:{[module] module}";
    "loaded:`symbol$()";
    "DEBUG:1b";
    "OS:`linux";
    "normalizePath:{[p] lower p}";
    "ensureDir:{[p] 'notimplemented}";
    "shellQuote:{[p] 'notimplemented}";
    "\\d .";
    "teamAdd:{x+y}");

.tst.testState.utlco.run:{[atStartup]
    wd: .resq.util.tempRoot[], "/resq_utlco_", string[.z.i], "_", string `long$.z.p;
    .resq.util.ensureDir wd, "/src";
    .resq.util.ensureDir wd, "/tests";
    (hsym `$wd, "/src/utl.q") 0: .tst.testState.utlco.teamUtl;
    (hsym `$wd, "/tests/test_a.q") 0: $[atStartup; (); enlist "system \"l src/utl.q\";"],
        (".tst.desc[\"team code\"]{";
         "  should[\"keeps its own .utl\"]{";
         "    .utl.normalizePath[\"/Data/HDB\"] musteq \"/data/hdb\";";
         "    .utl.OS musteq `linux;";
         "    .utl.DEBUG musteq 1b;";
         "    .utl.require[`mod] musteq `mod;";
         "  };";
         "  should[\"fails honestly\"]{ teamAdd[1;2] musteq 4; };";
         " };");
    (hsym `$wd, "/tests/test_b.q") 0: enlist
        ".tst.desc[\"a later file\"]{ should[\"still runs\"]{ 1 musteq 1; }; };";
    env: $[atStartup; "QINIT=", (.resq.util.shellQuote wd, "/src/utl.q"), " "; ""];
    / "true &&" first: q itself takes a command that starts with "cd".
    cmd: "true && cd ", (.resq.util.shellQuote wd), " && ", env, "timeout -k 2 60 q ",
         (.resq.util.shellQuote .resq.HOME, "/resq.q"),
         " test tests -root-load -json -junit -outDir out",
         " -state-file out/state.json -flake-history out/flake.json",
         " -quarantine-file out/quarantine.json -flake-proposal-file out/proposals.json",
         " > out.txt 2>&1; echo $?";
    exitLines: @[system; cmd; {[err] enlist "-1"}];
    output: "\n" sv @[read0; hsym `$wd, "/out.txt"; {()}];
    rawJson: @[read0; hsym `$wd, "/out/test-results.json"; {()}];
    payload: $[count rawJson; .j.k raze rawJson; ()!()];
    junit: .resq.util.isFile wd, "/out/test-results.junit.xml";
    if[wd like "*/resq_utlco_*"; system "rm -rf -- ", .resq.util.shellQuote wd];
    summary: $[`summary in key payload; payload`summary; ()!()];
    `code`output`summary`junit!("J"$last exitLines; output; summary; junit)
 };

.tst.testState.utlco.check:{[r]
    / one deliberately failing test: the run is red for that reason only
    r[`code] musteq 1;
    r[`summary][`testCount] musteq 3f;
    r[`summary][`passCount] musteq 2f;
    r[`summary][`failCount] musteq 1f;
    r[`summary][`errorCount] musteq 0f;
    r[`junit] musteq 1b;
    / the team's DEBUG flag is theirs: it does not switch on resQ's tracing
    (0 < count r[`output] ss "DEBUG: loading") musteq 0b;
    (0 < count r[`output] ss "Framework phase") musteq 0b;
 };

.tst.desc["A team's own .utl namespace #slow"]{
  should["neither break resQ nor be replaced when a test file loads it"]{
    if[not .tst.testState.utlco.canRun; :must[1b; "q or timeout unavailable"]];
    .tst.testState.utlco.check .tst.testState.utlco.run 0b;
  };
  should["neither break resQ nor be replaced when it is loaded at q start-up"]{
    if[not .tst.testState.utlco.canRun; :must[1b; "q or timeout unavailable"]];
    .tst.testState.utlco.check .tst.testState.utlco.run 1b;
  };
 };

.tst.desc["Names resQ offers in .utl"]{
  should["are the .resq.util helpers where the name is free"]{
    .utl.shellQuote["a b"] musteq .resq.util.shellQuote "a b";
    .utl.isDir["."] musteq 1b;
  };
  should["replace only what resQ put there itself"]{
    `.resq.utlOffered mock .resq.utlOffered;
    `.utl.audProbe mock `theirs;
    .resq.offerUtl[`audProbe; `ours] musteq 0b;
    .utl.audProbe musteq `theirs;
    `.utl.audProbe2 mock `first;
    .resq.utlOffered[`audProbe2]: `first;
    .resq.offerUtl[`audProbe2; `second] musteq 1b;
    .utl.audProbe2 musteq `second;
  };
 };
