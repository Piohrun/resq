/ ============================================================================
/ tests/test_cli.q - Pure CLI parser and subprocess contract tests.
/ .
/ The parser is exercised directly for precise normalization/validation checks,
/ then end-to-end in fresh q processes to pin exit status, side-effect safety,
/ reporter behavior, and CWD independence.
/ ============================================================================

.tst.desc["CLI mode parsing"]{
    should["default to test mode when no args supplied"]{
        r: .tst.parseModeArgs ();
        r[`mode] musteq `test;
        r[`args] mustmatch ();
    };

    should["recognise each documented mode"]{
        {[m]
            r: .tst.parseModeArgs enlist string m;
            r[`mode] musteq m;
            r[`args] mustmatch ();
        } each .tst.validModes;
    };

    should["strip the mode token and keep remaining args"]{
        r: .tst.parseModeArgs ("test"; "tests/"; "-junit");
        r[`mode] musteq `test;
        r[`args] mustmatch ("tests/"; "-junit");
    };

    should["treat an unrecognised first token as a path under default mode"]{
        r: .tst.parseModeArgs ("mything"; "tests/");
        r[`mode] musteq `test;
        r[`args] mustmatch ("mything"; "tests/");
    };

    should["expose the canonical mode list"]{
        .tst.validModes mustmatch `test`cover`discover`watch;
    };
};

.tst.desc["CLI normalized parser"]{
    should["consume options and dispatch mode from one parse result"]{
        r: .tst.parseCLI ("--strict"; "test"; "suite.q"; "--only"; "single*"; "--quiet");
        r[`ok] musteq 1b;
        r[`mode] musteq `test;
        r[`args] mustmatch enlist "suite.q";
        r[`options; `strict] musteq 1b;
        r[`options; `quiet] musteq 1b;
        r[`options; `only] mustmatch "single*";
    };

    should["give the last duplicate value precedence across dash spellings"]{
        r: .tst.parseCLI ("test"; "-only"; "first*"; "--only"; "last*"; "suite.q");
        r[`ok] musteq 1b;
        r[`options; `only] mustmatch "last*";
        r[`args] mustmatch enlist "suite.q";
    };

    should["support both spellings for flags and aliases"]{
        single: .tst.parseCLI ("test"; "-perf"; "-xml"; "-noquit"; "-strict";
            "-quiet"; "-isolate"; "-cov"; "-desc"; "-ff"; "-fh"; "-debug";
            "-interactive"; "suite.q");
        longForm: .tst.parseCLI ("test"; "--perf"; "--xml"; "--noquit"; "--strict";
            "--quiet"; "--isolate"; "--coverage"; "--describe"; "--fail-fast";
            "--fail-hard"; "--debug"; "--interactive"; "suite.q");
        single[`ok] musteq 1b;
        longForm[`ok] musteq 1b;
        single[`args] mustmatch longForm`args;
        single[`mode] musteq longForm`mode;
        {[leftResult; rightResult; optionName]
            leftResult[`options; optionName] musteq rightResult[`options; optionName]
        }[single; longForm;] each
            `perf`junit`noquit`strict`quiet`isolate`coverage`describe`failFast`failHard`debug`interactive;
    };

    should["support both spellings for every value option"]{
        single: .tst.parseCLI ("test"; "-maxTestTime"; "0"; "-fuzzLimit"; "4";
            "-isolateTimeout"; "5"; "-cov-include"; "lib/*"; "-cov-exclude"; "tests/*";
            "-outDir"; "reports"; "-exclude"; "slow*"; "-only"; "fast*";
            "-tag"; "smoke"; "-exclude-tag"; "flaky"; "suite.q");
        longForm: .tst.parseCLI ("test"; "--maxTestTime"; "0"; "--fuzzLimit"; "4";
            "--isolateTimeout"; "5"; "--cov-include"; "lib/*"; "--cov-exclude"; "tests/*";
            "--outDir"; "reports"; "--exclude"; "slow*"; "--only"; "fast*";
            "--tag"; "smoke"; "--exclude-tag"; "flaky"; "suite.q");
        single[`ok] musteq 1b;
        longForm[`ok] musteq 1b;
        single[`options] mustmatch longForm`options;
        single[`args] mustmatch longForm`args;
    };

    should["treat every token after -- as positional, including dash-prefixed paths"]{
        r: .tst.parseCLI ("test"; "-quiet"; "--"; "-suite.q"; "--not-an-option");
        r[`ok] musteq 1b;
        r[`mode] musteq `test;
        r[`args] mustmatch ((system "cd"), "/-suite.q"; (system "cd"), "/--not-an-option");
        r[`options; `quiet] musteq 1b;
    };
};

.tst.cliParseFails:{[args; pattern]
    r: .tst.parseCLI args;
    (not r`ok) and (r`error) like pattern
};

.tst.desc["CLI fail-closed validation"]{
    should["reject unknown options"]{
        .tst.cliParseFails[("test"; "--bogus"); "Unknown option:*"] musteq 1b;
        .tst.cliParseFails[("test"; "--e"); "Unknown option:*"] musteq 1b;
    };

    should["reject missing, empty, and option-shaped required values"]{
        .tst.cliParseFails[("test"; "-only"); "Missing value for -*"] musteq 1b;
        .tst.cliParseFails[("test"; "-only"; ""); "Empty value for -*"] musteq 1b;
        .tst.cliParseFails[("test"; "-only"; "--quiet"); "Missing value for -*"] musteq 1b;
    };

    should["reject non-integer and null numeric values"]{
        .tst.cliParseFails[("test"; "-maxTestTime"; "nope"); "Invalid integer for -*"] musteq 1b;
        .tst.cliParseFails[("test"; "-maxTestTime"; "1.5"); "Invalid integer for -*"] musteq 1b;
        .tst.cliParseFails[("test"; "-fuzzLimit"; "0N"); "Invalid integer for -*"] musteq 1b;
    };

    should["enforce numeric ranges"]{
        .tst.cliParseFails[("test"; "-maxTestTime"; "-1"); "Value must be >= 0 for -*"] musteq 1b;
        .tst.cliParseFails[("test"; "-fuzzLimit"; "-2"); "Value must be >= 0 for -*"] musteq 1b;
        .tst.cliParseFails[("test"; "-isolateTimeout"; "0"); "Value must be > 0 for -*"] musteq 1b;
        .tst.cliParseFails[("test"; "-isolateTimeout"; "-1"); "Value must be > 0 for -*"] musteq 1b;
    };

    should["reject contradictory process-lifecycle flags"]{
        .tst.cliParseFails[("test"; "-exit"; "--noquit"); "Options -exit and -noquit cannot be used together*"] musteq 1b;
    };
};

/ --- bounded subprocess harness --------------------------------------------

.tst.cliResqHome: .resq.HOME;
.tst.cliQExe: {$[
    count q: @[system; "command -v q 2>/dev/null"; {()}];
        first q;
    (getenv[`QHOME]), "/l64/q"
]};
.tst.cliCanQ: 0 < count .tst.cliQExe[];
.tst.cliCanTimeout: 0 < count @[system; "command -v timeout 2>/dev/null"; {()}];
.tst.cliBase: "/tmp/resq_cli_test_", string .z.i;
.tst.cliCounter: 0;

.tst.cliWorkDir:{[]
    .tst.cliCounter+: 1;
    .tst.cliBase, "/run_", string[.z.i], "_", string .tst.cliCounter
};

.tst.cliCleanup:{[wd]
    expectedPrefix: .tst.cliBase, "/run_";
    if[not wd like expectedPrefix, "*";
        '"refusing unsafe CLI test cleanup path"];
    system "rm -rf -- ", .utl.shellQuote wd;
};

.tst.cliCleanupBase:{[]
    expectedBase: "/tmp/resq_cli_test_", string .z.i;
    if[not .tst.cliBase ~ expectedBase;
        '"refusing unsafe CLI test base cleanup path"];
    if[.utl.pathExists .tst.cliBase;
        system "rm -rf -- ", .utl.shellQuote .tst.cliBase];
};

.tst.cliWriteFixture:{[wd; name]
    .utl.ensureDir wd;
    marker: wd, "/executed.marker";
    file: wd, "/", name;
    lines: (
        "(hsym `$\"", marker, "\") 0: enlist \"loaded\";";
        ".tst.desc[\"single suite alpha #fast\"]{ should[\"one\"]{ 1 musteq 1; }; };";
        ".tst.desc[\"other suite beta\"]{ should[\"two\"]{ 2 musteq 2; }; };"
    );
    (hsym `$file) 0: lines;
    file
};

/ Run resQ in a fresh directory under GNU timeout with SIGKILL escalation.
/ args may contain @FIXTURE@, @REPORT@, and @WD@ placeholders.
/ repoCwd selects a natural invocation from the repository root.
.tst.cliRun:{[args; fixtureName; repoCwd]
    wd: .tst.cliWorkDir[];
    fixturePath: .tst.cliWriteFixture[wd; fixtureName];
    reportDir: wd, "/reports";
    argLine: ssr[args; "@FIXTURE@"; .utl.shellQuote fixturePath];
    argLine: ssr[argLine; "@REPORT@"; .utl.shellQuote reportDir];
    argLine: ssr[argLine; "@WD@"; .utl.shellQuote wd];
    childCwd: $[repoCwd; .tst.cliResqHome; wd];
    qWd: .utl.shellQuote wd;
    qCwd: .utl.shellQuote childCwd;
    qOut: .utl.shellQuote wd, "/out.txt";
    qExe: .utl.shellQuote .tst.cliQExe[];
    qHome: .utl.shellQuote .tst.cliResqHome, "/resq.q";
    cmd: "mkdir -p ", qWd, " && cd ", qCwd,
         " && timeout -k 5 20 ", qExe, " ", qHome, " ", argLine,
         " < /dev/null > ", qOut, " 2>&1; echo $?";
    statusLines: @[system; cmd; {[e] enlist "-1"}];
    code: "J"$last statusLines;
    out: @[read0; hsym `$wd, "/out.txt"; {()}];
    loaded: .utl.pathExists wd, "/executed.marker";
    reported: .utl.pathExists reportDir, "/test-results.xml";
    result: `code`out`loaded`reported!(code; out; loaded; reported);
    .tst.cliCleanup wd;
    result
};

.tst.cliAnyLike:{[lines; pattern] any lines like pattern};

.tst.desc["CLI subprocess safety #slow"]{
    after{.tst.cliCleanupBase[]};

    skipIf[(not .tst.cliCanQ) or not .tst.cliCanTimeout;
           "unknown option exits 1 before loading tests"]{
        r: .tst.cliRun["test @FIXTURE@ --bogus"; "cli_flags.q"; 0b];
        r[`code] musteq 1;
        .tst.cliAnyLike[r`out; "CLI ERROR: Unknown option:*"] musteq 1b;
        r[`loaded] musteq 0b;
    };

    skipIf[(not .tst.cliCanQ) or not .tst.cliCanTimeout;
           "invalid value creates no reporter artifact"]{
        r: .tst.cliRun["test @FIXTURE@ -junit -outDir @REPORT@ -only"; "cli_flags.q"; 0b];
        r[`code] musteq 1;
        .tst.cliAnyLike[r`out; "CLI ERROR: Missing value for -*"] musteq 1b;
        r[`loaded] musteq 0b;
        r[`reported] musteq 0b;
    };

    skipIf[(not .tst.cliCanQ) or not .tst.cliCanTimeout;
           "double-hyphen options match single-hyphen behavior"]{
        r: .tst.cliRun["test @FIXTURE@ --only \"single*\" --noquit --quiet"; "cli_flags.q"; 0b];
        r[`code] musteq 0;
        .tst.cliAnyLike[r`out; "*1 total*"] musteq 1b;
        r[`loaded] musteq 1b;
    };

    skipIf[(not .tst.cliCanQ) or not .tst.cliCanTimeout;
           "contradictory exit flags fail before test loading"]{
        r: .tst.cliRun["test @FIXTURE@ -exit --noquit"; "cli_flags.q"; 0b];
        r[`code] musteq 1;
        .tst.cliAnyLike[r`out; "CLI ERROR: Options -exit and -noquit cannot be used together*"] musteq 1b;
        r[`loaded] musteq 0b;
    };

    skipIf[(not .tst.cliCanQ) or not .tst.cliCanTimeout;
           "repo-root malformed path fails once without recursive discovery"]{
        r: .tst.cliRun["test -tdir/test_x.q"; "cli_flags.q"; 1b];
        r[`code] musteq 1;
        must[1 = sum (r`out) like "CLI ERROR:*"; "must emit exactly one CLI error"];
        .tst.cliAnyLike[r`out; "*SUMMARY*"] musteq 0b;
        r[`loaded] musteq 0b;
    };
};
