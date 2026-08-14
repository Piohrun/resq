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

    / --help and -scaffold were added after the schema's flag/value split, which
    / is positionally coupled; parsing them proves the lists stayed aligned.
    should["parse --help and -scaffold as flags"]{
        h: .tst.parseCLI ("test"; "--help");
        h[`ok] musteq 1b;
        h[`options; `help] musteq 1b;
        / No "h" alias: q claims -h before the script sees .z.x (bin/resq rewrites it).
        must[not "-h" in .tst.cli.optionTokens;
             "a bare -h alias would be shadowed by q itself"];

        sc: .tst.parseCLI ("discover"; "src"; "tests"; "-scaffold");
        sc[`ok] musteq 1b;
        sc[`options; `scaffold] musteq 1b;
        sc[`args] mustmatch ("src"; "tests");

        / Absent by default: discover must not write a scaffold unasked.
        plain: .tst.parseCLI ("discover"; "src"; "tests");
        plain[`options; `scaffold] musteq 0b;
    };

    should["parse the expectation-line annotation kill switch"]{
        single: .tst.parseCLI ("test"; "-no-line-annotations"; "suite.q");
        camel: .tst.parseCLI ("test"; "--noLineAnnotations"; "suite.q");
        single[`ok] musteq 1b;
        single[`options;`noLineAnnotations] musteq 1b;
        camel[`options;`noLineAnnotations] musteq 1b;
        single[`args] musteq enlist "suite.q";
    };

    should["parse declared report profiles and keep sharding on full evidence"]{
        compact: .tst.parseCLI ("test"; "-report-profile"; "telemetry"; "suite.q");
        compact[`ok] musteq 1b;
        compact[`options;`reportProfile] musteq "telemetry";
        alias: .tst.parseCLI ("test"; "--reportProfile"; "results"; "suite.q");
        alias[`ok] musteq 1b;
        invalid: .tst.parseCLI ("test"; "-report-profile"; "tiny"; "suite.q");
        invalid[`ok] musteq 0b;
        must[invalid[`error] like "report-profile must be one of*";
             "unknown profiles must fail at the CLI boundary"];
        sharded: .tst.parseCLI ("test"; "-shard-count"; "2";
            "-report-profile"; "results"; "suite.q");
        sharded[`ok] musteq 0b;
        sharded[`error] musteq "sharded runs require report-profile full";
    };

    should["parse bounded labels without interning rejected keys"]{
        parsed:.tst.parseCLI ("test";"-labels";
            "{\"service\":\"orders\",\"environment\":\"prod\"}";"suite.q");
        parsed[`ok] musteq 1b;
        parsed[`options;`labels;`environment] musteq "prod";
        parsed[`options;`labels;`service] musteq "orders";
        key[parsed[`options;`labels]] musteq `environment`service;

        nonString:.tst.parseCLI ("test";"-labels";"{\"service\":42}";"suite.q");
        nonString[`ok] musteq 0b;
        reserved:.tst.parseCLI ("test";"-labels";"{\"resq.secret\":\"x\"}";"suite.q");
        reserved[`ok] musteq 0b;

        symsBefore:.Q.w[]`syms;
        hostile:"{\"",(65#"x"),"\":\"value\"}";
        rejected:.tst.parseCLI ("test";"-labels";hostile;"suite.q");
        symsAfter:.Q.w[]`syms;
        rejected[`ok] musteq 0b;
        symsAfter musteq symsBefore;
    };

    should["parse the VCS discovery opt-out"]{
        parsed:.tst.parseCLI ("test";"--no-vcs";"suite.q");
        parsed[`ok] musteq 1b;
        parsed[`options;`noVcs] musteq 1b;
    };

    should["parse opt-in bounded final diffs"]{
        parsed:.tst.parseCLI ("test";"--final-diffs";"--final-diff-limit";"256";"suite.q");
        parsed[`ok] musteq 1b;
        parsed[`options;`finalDiffs] musteq 1b;
        parsed[`options;`finalDiffLimit] musteq 256j;
        parsed[`args] musteq enlist "suite.q";
        .tst.cliParseFails[("test";"-final-diff-limit";"-1");
            "Value must be >= 0 for *"] musteq 1b;
    };

    should["validate -isolateWorkers as a positive integer"]{
        ok: .tst.parseCLI ("test"; "-isolateWorkers"; "4"; "suite.q");
        ok[`ok] musteq 1b;
        ok[`options; `isolateWorkers] musteq 4;
        (.tst.parseCLI ("test"; "--isolate-workers"; "4"; "suite.q"))[`options; `isolateWorkers] musteq 4;
        / Zero workers would mean "run nothing"; reject it rather than silently
        / clamping, the same contract -isolateTimeout uses.
        .tst.cliParseFails[("test"; "-isolateWorkers"; "0"); "Value must be > 0 for *"] musteq 1b;
        .tst.cliParseFails[("test"; "-isolateWorkers"; "-2"); "Value must be > 0 for *"] musteq 1b;
        .tst.cliParseFails[("test"; "-isolateWorkers"; "two"); "Invalid integer for *"] musteq 1b;
    };

    should["parse replayable randomized ordering options"]{
        parsed: .tst.parseCLI ("test"; "--random-order"; "--seed"; "4242"; "suite.q");
        parsed[`ok] musteq 1b;
        parsed[`options;`randomOrder] musteq 1b;
        parsed[`options;`seed] musteq 4242j;
        parsed[`args] musteq enlist "suite.q";
        .tst.cliParseFails[("test"; "-seed"; "-1"); "Value must be >= 0 for *"] musteq 1b;
    };

    should["parse stable-ID rerun selection and reject contradictory modes"]{
        lastRun:.tst.parseCLI ("test"; "--last-failed"; "--state-file"; "cache/run.json"; "suite.q");
        firstRun:.tst.parseCLI ("test"; "--failed-first"; "suite.q");
        lastRun[`ok] musteq 1b;
        lastRun[`options;`lastFailed] musteq 1b;
        lastRun[`options;`stateFile] musteq "cache/run.json";
        firstRun[`options;`failedFirst] musteq 1b;
        .tst.cliParseFails[("test"; "-last-failed"; "-failed-first");
            "Options -last-failed and -failed-first cannot be used together*"] musteq 1b;
    };

    should["validate zero-based native file/test/case shards"]{
        parsed:.tst.parseCLI ("test";"--shard-index";"2";"--shard-count";"5";"--shard-unit";"case";"suite.q");
        parsed[`ok] musteq 1b;
        parsed[`options;`shardIndex] musteq 2j;
        parsed[`options;`shardCount] musteq 5j;
        parsed[`options;`shardUnit] musteq "case";
        .tst.cliParseFails[("test";"-shard-count";"0");"Value must be > 0 for *"] musteq 1b;
        .tst.cliParseFails[("test";"-shard-index";"3";"-shard-count";"3");
            "shard-index must be less than shard-count*"] musteq 1b;
        .tst.cliParseFails[("test";"-shard-unit";"process");
            "shard-unit must be one of: file, test, case*"] musteq 1b;
    };

    should["parse trusted plugin files and strict callback policy"]{
        parsed:.tst.parseCLI ("test";"--plugin";"one.q,two.q";"--strict-plugins";"suite.q");
        parsed[`ok] musteq 1b;
        parsed[`options;`pluginFiles] musteq "one.q,two.q";
        parsed[`options;`strictPlugins] musteq 1b;
        parsed[`args] musteq enlist "suite.q";
        (.tst.parseCLI ("test";"--plugins";"one.q";"suite.q"))[`options;`pluginFiles]
            musteq "one.q";
    };

    should["support both spellings for every value option"]{
        single: .tst.parseCLI ("test"; "-maxTestTime"; "0"; "-fuzzLimit"; "4";
            "-isolateTimeout"; "5"; "-cov-include"; "lib/*"; "-cov-exclude"; "tests/*";
            "-cov-min"; "85"; "-cov-functions-min"; "80";
            "-cov-lines-min"; "70"; "-cov-completeness-min"; "90";
            "-cov-branches-min"; "65";
            "-cov-branch-completeness-min"; "95";
            "-source"; "src,shared";
            "-outDir"; "reports"; "-exclude"; "slow*"; "-only"; "fast*";
            "-tag"; "smoke"; "-exclude-tag"; "flaky"; "suite.q");
        longForm: .tst.parseCLI ("test"; "--maxTestTime"; "0"; "--fuzzLimit"; "4";
            "--isolateTimeout"; "5"; "--cov-include"; "lib/*"; "--cov-exclude"; "tests/*";
            "--coverage-min"; "85"; "--cov-functions-min"; "80";
            "--cov-lines-min"; "70"; "--cov-completeness-min"; "90";
            "--cov-branches-min"; "65";
            "--cov-branch-completeness-min"; "95";
            "--coverage-source"; "src,shared";
            "--outDir"; "reports"; "--exclude"; "slow*"; "--only"; "fast*";
            "--tag"; "smoke"; "--exclude-tag"; "flaky"; "suite.q");
        single[`ok] musteq 1b;
        longForm[`ok] musteq 1b;
        single[`options] mustmatch longForm`options;
        single[`args] mustmatch longForm`args;
    };

    should["parse branch measurement and its independent gates"]{
        parsed:.tst.parseCLI ("cover";"suite.q";"--cov-branches";
            "--cov-branches-min";"75";
            "--cov-branch-completeness-min";"100");
        parsed[`ok] musteq 1b;
        parsed[`options;`covBranches] musteq 1b;
        parsed[`options;`coverageBranchMin] musteq 75j;
        parsed[`options;`coverageBranchCompletenessMin] musteq 100j;
        parsed[`args] musteq enlist "suite.q";
    };

    should["parse bounded test and retry-attempt coverage contexts"]{
        parsed:.tst.parseCLI ("cover";"suite.q";"--cov-contexts";
            "--cov-attempt-contexts";"--cov-context-max";"25";
            "--cov-context-entry-max";"500");
        parsed[`ok] musteq 1b;
        parsed[`options;`covContexts] musteq 1b;
        parsed[`options;`covAttemptContexts] musteq 1b;
        parsed[`options;`coverageContextMax] musteq 25j;
        parsed[`options;`coverageContextEntryMax] musteq 500j;
        .tst.cliParseFails[("cover";"suite.q";"-cov-context-max";"0");
            "Value must be > 0 for *"] musteq 1b;
        .tst.cliParseFails[("cover";"suite.q";"-cov-context-entry-max";"-1");
            "Value must be > 0 for *"] musteq 1b;
    };

    should["treat --source as a value option rather than a test path"]{
        parsed: .tst.parseCLI ("cover"; "tests"; "--source"; "src,shared");
        parsed[`ok] musteq 1b;
        parsed[`mode] musteq `cover;
        parsed[`args] mustmatch enlist "tests";
        parsed[`options;`coverageSources] musteq "src,shared";
    };

    should["normalize qspec's legacy runner aliases"]{
        legacy: .tst.parseCLI ("suite.q"; "-performance"; "-pass";
            "-fuzz-display-limt"; "7");
        short: .tst.parseCLI ("suite.q"; "-fdl"; "11");
        legacy[`ok] musteq 1b;
        legacy[`mode] musteq `test;
        legacy[`args] mustmatch enlist "suite.q";
        legacy[`options; `perf] musteq 1b;
        legacy[`options; `passOnly] musteq 1b;
        legacy[`options; `fuzzLimit] musteq 7;
        short[`ok] musteq 1b;
        short[`options; `fuzzLimit] musteq 11;
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
        .tst.cliParseFails[("test"; "-cov-min"; "101"); "Value must be between 0 and 100 for -*"] musteq 1b;
        .tst.cliParseFails[("test"; "-cov-min"; "-1"); "Value must be between 0 and 100 for -*"] musteq 1b;
        .tst.cliParseFails[("test"; "-cov-lines-min"; "101"); "Value must be between 0 and 100 for -*"] musteq 1b;
        .tst.cliParseFails[("test"; "-cov-completeness-min"; "-1"); "Value must be between 0 and 100 for -*"] musteq 1b;
        .tst.cliParseFails[("test"; "-cov-branches-min"; "101"); "Value must be between 0 and 100 for -*"] musteq 1b;
        .tst.cliParseFails[("test"; "-cov-branch-completeness-min"; "-1"); "Value must be between 0 and 100 for -*"] musteq 1b;
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
.tst.cliBase: .utl.tempRoot[], "/resq_cli_test_", string .z.i;
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
    expectedBase: .utl.tempRoot[], "/resq_cli_test_", string .z.i;
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
        ".tst.desc[\"single suite alpha #fast\"]{ should[\"one\"]{ 1 musteq 1; must[not \"/.\" ~ -2 # .resq.HOME; \"HOME must be normalized\"]; }; };";
        ".tst.desc[\"other suite beta\"]{ should[\"two\"]{ 2 musteq 2; }; };"
    );
    (hsym `$file) 0: lines;
    file
};

/ Run resQ in a fresh directory under GNU timeout with SIGKILL escalation.
/ args may contain @FIXTURE@, @REPORT@, and @WD@ placeholders.
/ repoCwd selects a natural invocation from the repository root.
.tst.cliRunConfigured:{[args; fixtureName; repoCwd; configText]
    wd: .tst.cliWorkDir[];
    fixturePath: .tst.cliWriteFixture[wd; fixtureName];
    if[0 < count configText; (hsym `$wd, "/resq.json") 0: enlist configText];
    reportDir: wd, "/reports";
    argLine: ssr[args; "@FIXTURE@"; .utl.shellQuote fixturePath];
    argLine: ssr[argLine; "@REPORT@"; .utl.shellQuote reportDir];
    argLine: ssr[argLine; "@WD@"; .utl.shellQuote wd];
    childCwd: $[repoCwd; .tst.cliResqHome; wd];
    qWd: .utl.shellQuote wd;
    qCwd: .utl.shellQuote childCwd;
    qOut: .utl.shellQuote wd, "/out.txt";
    qExe: .utl.shellQuote .tst.cliQExe[];
    qHome: .utl.shellQuote $[repoCwd; "resq.q"; .tst.cliResqHome, "/resq.q"];
    cmd: "mkdir -p ", qWd, " && cd ", qCwd,
         " && timeout -k 5 20 ", qExe, " ", qHome, " ", argLine,
         " < /dev/null > ", qOut, " 2>&1; echo $?";
    statusLines: @[system; cmd; {[e] enlist "-1"}];
    code: "J"$last statusLines;
    out: @[read0; hsym `$wd, "/out.txt"; {()}];
    loaded: .utl.pathExists wd, "/executed.marker";
    reported: .utl.pathExists reportDir, "/test-results.xml";
    / Also observe the DEFAULT location (outDir "." == the child's cwd) and the
    / "test-results/" subdirectory, so a reporter that quietly relocates its
    / output is visible to a test rather than only to someone running it by hand.
    cwdReport: .utl.pathExists childCwd, "/test-results.xml";
    subdirReport: .utl.pathExists childCwd, "/test-results/test-results.xml";
    junitReport: .utl.pathExists reportDir, "/test-results.junit.xml";
    xunitReport: .utl.pathExists reportDir, "/test-results.xunit.xml";
    jsonReport: .utl.pathExists reportDir, "/test-results.json";
    result: `code`out`loaded`reported`cwdReport`subdirReport`junitReport`xunitReport`jsonReport!(
        code;out;loaded;reported;cwdReport;subdirReport;junitReport;xunitReport;jsonReport);
    .tst.cliCleanup wd;
    result
};

.tst.cliRun:{[args; fixtureName; repoCwd]
    .tst.cliRunConfigured[args; fixtureName; repoCwd; ""]
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

    / -xunit used to force outDir to "test-results", so it alone wrote into a
    / SUBDIRECTORY while -junit and -json wrote to outDir itself -- undocumented,
    / and untested in either direction.
    skipIf[(not .tst.cliCanQ) or not .tst.cliCanTimeout;
           "-xunit writes to outDir itself, not a test-results/ subdirectory"]{
        r: .tst.cliRun["test @FIXTURE@ -xunit"; "cli_flags.q"; 0b];
        r[`code] musteq 0;
        must[r`cwdReport;      "-xunit must write test-results.xml into outDir"];
        must[not r`subdirReport; "-xunit must not create a test-results/ subdirectory"];
    };

    skipIf[(not .tst.cliCanQ) or not .tst.cliCanTimeout;
           "-junit writes to the same default location as -xunit"]{
        r: .tst.cliRun["test @FIXTURE@ -junit"; "cli_flags.q"; 0b];
        r[`code] musteq 0;
        must[r`cwdReport;        "-junit must write test-results.xml into outDir"];
        must[not r`subdirReport; "-junit must not create a test-results/ subdirectory"];
    };

    skipIf[(not .tst.cliCanQ) or not .tst.cliCanTimeout;
           "an explicit -outDir is honoured by both xml reporters"]{
        rj: .tst.cliRun["test @FIXTURE@ -junit -outDir @REPORT@"; "cli_flags.q"; 0b];
        rj[`code] musteq 0;
        must[rj`reported; "-junit -outDir must write into the given directory"];
        rx: .tst.cliRun["test @FIXTURE@ -xunit -outDir @REPORT@"; "cli_flags.q"; 0b];
        rx[`code] musteq 0;
        must[rx`reported; "-xunit -outDir must write into the given directory"];
    };

    skipIf[(not .tst.cliCanQ) or not .tst.cliCanTimeout;
           "multiple reporters coexist without overwriting schemas"]{
        r: .tst.cliRun["test @FIXTURE@ -junit -xunit -json -outDir @REPORT@"; "cli_flags.q"; 0b];
        r[`code] musteq 0;
        must[r`junitReport; "multi-report mode must emit test-results.junit.xml"];
        must[r`xunitReport; "multi-report mode must emit test-results.xunit.xml"];
        must[r`jsonReport; "multi-report mode must emit test-results.json"];
        must[not r`reported; "ambiguous test-results.xml must not be emitted in multi-report mode"];
    };

    skipIf[(not .tst.cliCanQ) or not .tst.cliCanTimeout;
           "double-hyphen options match single-hyphen behavior"]{
        r: .tst.cliRun["test @FIXTURE@ --only \"single*\" --noquit --quiet"; "cli_flags.q"; 0b];
        r[`code] musteq 0;
        .tst.cliAnyLike[r`out; "*1 total*"] musteq 1b;
        r[`loaded] musteq 1b;
    };

    skipIf[(not .tst.cliCanQ) or not .tst.cliCanTimeout;
           "the documented relative resq.q entrypoint keeps HOME canonical"]{
        r: .tst.cliRun["test @FIXTURE@ -quiet"; "cli_relative.q"; 1b];
        r[`code] musteq 0;
        r[`loaded] musteq 1b;
    };

    skipIf[(not .tst.cliCanQ) or not .tst.cliCanTimeout;
           "config exit false suppresses the process exit call"]{
        r: .tst.cliRunConfigured["test @WD@/missing.q -quiet"; "cli_config.q"; 0b;
            "{\"exit\":false}"];
        r[`code] musteq 0;
        .tst.cliAnyLike[r`out; "*FILE_LOAD_ERROR*"] musteq 1b;
    };

    skipIf[(not .tst.cliCanQ) or not .tst.cliCanTimeout;
           "-exit overrides config false and preserves granular load status"]{
        r: .tst.cliRunConfigured["test @WD@/missing.q -quiet -exit"; "cli_config.q"; 0b;
            "{\"exit\":false}"];
        r[`code] musteq 4;
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
