.tst.desc["Pollution and Sandbox Test"]{
    should["pollute a new namespace"]{
        .polluted.x:1;
        1 musteq 1;
    };
    
    should["change the current namespace"]{
        .escaped.x:1;
        system "d .escaped";
        1 musteq 1;
    };
};

.tst.desc["Dependency Test"]{
    should["require a dependency"]{
        / Use install-root-absolute path so the test passes regardless of CWD.
        .utl.require .utl.PKGLOADING,"/config.q";
        1 musteq 1;
    };
};

.tst.desc["resQ's own start-up leaves no variables in the root namespace"]{
  should["keep config, args and its other working values under .resq"]{
    / An application that sets `config` or `args` only when undefined must not
    / find resQ's there. The root namespace holds resQ's test words and nothing
    / else of its own.
    leaked: `config`args`textReporterLoaded`exitCode`noTestsFound`src`dirs`changes inter key `.;
    leaked musteq `symbol$();
  };
 };

/ What one suite changes in the process must not reach the next: message
/ handlers, the timer, the display precision, and members it deleted.
.tst.testState.suiteLeak.canRun:
    (0 < count @[system; "which q 2>/dev/null"; {()}]) and
    (0 < count @[system; "which timeout 2>/dev/null"; {()}]);

.tst.desc["process state a suite changes is put back for the next #slow"]{
  should["restore handlers, timer, precision and deleted members, and say so"]{
    if[not .tst.testState.suiteLeak.canRun; :must[1b; "q or timeout unavailable"]];
    wd: .resq.util.tempRoot[], "/resq_suiteleak_", string[.z.i], "_", string `long$.z.p;
    .resq.util.ensureDir wd;
    .tst.registerCleanup[{[d] @[system; "rm -rf -- ", .resq.util.shellQuote d; {}]}; enlist wd];
    (hsym `$wd, "/test_leak.q") 0: (
        ".leakapp.keep:1;";
        ".leakapp.gone:2;";
        ".tst.desc[\"a: changes the process\"]{";
        "  should[\"sets handlers and settings, deletes a member\"]{";
        "    .z.ts:{`tick}; system \"t 50\"; .z.pg:{`hijacked}; system \"P 3\";";
        "    delete gone from `.leakapp;";
        "    1 musteq 1;";
        "  };";
        " };";
        ".tst.desc[\"b: the next suite\"]{";
        "  should[\"finds the process as it was\"]{";
        "    (@[get; `.z.ts; `unset]) musteq `unset;";
        "    (@[get; `.z.pg; `unset]) musteq `unset;";
        "    (system \"t\") musteq 0i;";
        "    (system \"P\") musteq 7i;";
        "    .leakapp.gone musteq 2;";
        "  };";
        " };");
    cmd: "cd ", .resq.util.shellQuote[wd], " && ", .resq.util.shellQuote[.resq.HOME, "/bin/resq"],
        " test . -outDir out -state-file out/s.json -flake-history out/f.json",
        " -flake-proposal-file out/p.json 2>&1; echo exit=$?";
    out: @[system; "sh -c ", .resq.util.shellQuote cmd; {[e] enlist "exit=-1"}];
    (last out) musteq "exit=0";
    said: {[out;part] any {[part;line] 0 < count line ss part}[part] each out}[out];
    said["modified .z.ts, .z.pg. Restoring."] musteq 1b;
    said["changed the timer"] musteq 1b;
    said["changed the display precision"] musteq 1b;
    said["deleted members in leakapp"] musteq 1b;
    said["2 total (2 passed"] musteq 1b;
  };
 };
