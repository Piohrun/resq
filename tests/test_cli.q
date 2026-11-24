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
        .tst.validModes mustmatch `test`cover`discover`watch`mutate;
    };
};

.tst.desc["CLI mutation options"]{
    should["parse the mutate mode, its targets and its options"]{
        r: .tst.parseCLI ("mutate"; "src/a.q:10-40"; "src/lib"; "-tests"; "tests/unit,tests/it";
            "-since"; "main"; "--mutators"; "comparison,statement"; "-max-mutants"; "50";
            "-mutation-min"; "80");
        r[`ok] musteq 1b;
        r[`mode] musteq `mutate;
        r[`args] mustmatch ("src/a.q:10-40"; "src/lib");
        r[`options; `mutationTests] mustmatch "tests/unit,tests/it";
        r[`options; `mutationSince] mustmatch "main";
        r[`options; `mutators] mustmatch "comparison,statement";
        r[`options; `maxMutants] musteq 50;
        r[`options; `mutationMin] musteq 80;
    };

    should["reject a sample of zero and a score above one hundred"]{
        r: .tst.parseCLI ("mutate"; "src"; "-max-mutants"; "0");
        r[`ok] musteq 0b;
        must[r[`error] like "Value must be > 0 for -max-mutants*"; r`error];
        r: .tst.parseCLI ("mutate"; "src"; "-mutation-min"; "101");
        r[`ok] musteq 0b;
        must[r[`error] like "Value must be between 0 and 100 for -mutation-min*"; r`error];
        r: .tst.parseCLI ("mutate"; "src"; "-mutators");
        r[`ok] musteq 0b;
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

    should["accept qutil's --name=value spelling for value options"]{
        / qspec scripts pass options through qutil, e.g. --only=pricing*
        r: .tst.parseCLI ("tests"; "--only=pricing*,risk*"; "--fdl=5"; "-exclude=slow*");
        r[`ok] musteq 1b;
        r[`args] mustmatch enlist "tests";
        r[`options; `only] musteq "pricing*,risk*";
        r[`options; `fuzzLimit] musteq 5;
        r[`options; `exclude] musteq "slow*";
        (.tst.parseCLI ("tests"; "--outDir=a=b"))[`options; `outDir] musteq "a=b";
        .tst.cliParseFails[("test"; "--only="); "Empty value for --only"] musteq 1b;
        .tst.cliParseFails[("test"; "--junit=1"); "Unknown option: --junit=1"] musteq 1b;
        .tst.cliParseFails[("test"; "--bogus=1"); "Unknown option: --bogus=1"] musteq 1b;
        (.tst.parseCLI ("test"; "--"; "-x=1.q"))[`args] mustmatch enlist (system "cd"), "/-x=1.q";
    };

    should["accept only known -junit-names and -xunit-format values"]{
        (.tst.parseCLI ("test"; "tests"; "-junit-names"; "qspec"))[`options; `junitNames] musteq "qspec";
        (.tst.parseCLI ("test"; "tests"; "--junit-names=RESQ"))[`ok] musteq 1b;
        .tst.cliParseFails[("test"; "-junit-names"; "xml"); "junit-names must be one of: resq, qspec"] musteq 1b;
        (.tst.parseCLI ("test"; "tests"; "--xunit-format=qspec"))[`options; `xunitFormat] musteq "qspec";
        .tst.cliParseFails[("test"; "-xunit-format"; "nunit"); "xunit-format must be one of: xunit2, qspec"] musteq 1b;
    };

    should["accept -paths as the separator q lets through"]{
        r: .tst.parseCLI ("test"; "-quiet"; "-paths"; "-suite.q");
        r[`ok] musteq 1b;
        r[`args] mustmatch enlist (system "cd"), "/-suite.q";
        r[`options; `quiet] musteq 1b;
    };

    should["leave everything after -args to the application"]{
        `.resq.appArgs mock ();
        r: .tst.parseCLI ("test"; "tests"; "-quiet"; "-args"; "-env"; "prod"; "--bogus=1"; "-strict");
        r[`ok] musteq 1b;
        r[`args] mustmatch enlist "tests";
        r[`options; `quiet] musteq 1b;
        r[`options; `strict] musteq 0b;
        .resq.appArgs mustmatch ("-env"; "prod"; "--bogus=1"; "-strict");
        (.tst.parseCLI ("test"; "tests"; "--args"))[`ok] musteq 1b;
        .resq.appArgs mustmatch ();
        (.tst.parseCLI ("test"; "tests"))[`ok] musteq 1b;
        .resq.appArgs mustmatch ();
    };

    should["accept -root-load as a flag"]{
        (.tst.parseCLI ("test"; "tests"; "-root-load"))[`options; `rootLoad] musteq 1b;
        (.tst.parseCLI ("test"; "tests"; "--rootLoad"))[`options; `rootLoad] musteq 1b;
        (.tst.parseCLI ("test"; "tests"))[`options; `rootLoad] musteq 0b;
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
         " -state-file ",.utl.shellQuote[wd,"/state.json"],
         " -flake-history ",.utl.shellQuote[wd,"/flake.json"],
         " -quarantine-file ",.utl.shellQuote[wd,"/quarantine.json"],
         " -flake-proposal-file ",.utl.shellQuote[wd,"/proposals.json"],
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
        r: .tst.cliRun[
            "test @FIXTURE@ -quiet -state-file @WD@/state.json ",
            "-flake-history @WD@/flake.json -quarantine-file @WD@/quarantine.json ",
            "-flake-proposal-file @WD@/proposals.json";
            "cli_relative.q"; 1b];
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

/ q rejects single-letter options it does not know before resq.q runs, so the
/ launchers translate the two short flags the help advertises.
.tst.desc["short flags through the launcher"]{
  should["print the version for -v, as --version does"]{
    launcher: .resq.util.shellQuote .resq.HOME, "/bin/resq";
    / through sh -c: q's system captures only the last command of a list
    run: {[launcher;flag] @[system; "sh -c ", .resq.util.shellQuote launcher, " ", flag, " 2>&1; echo exit=$?"; {[e] enlist "failed: ", e}]}[launcher];
    short: run "-v";
    long: run "--version";
    short musteq long;
    (last short) musteq "exit=0";
    (first short) musteq "resQ version ", .resq.VERSION;
  };
  should["print the help for -h"]{
    launcher: .resq.util.shellQuote .resq.HOME, "/bin/resq";
    out: @[system; "sh -c ", .resq.util.shellQuote launcher, " -h 2>&1; echo exit=$?"; {[e] enlist "failed: ", e}];
    (last out) musteq "exit=0";
    (any out like "USAGE*") musteq 1b;
  };
 };

/ -noquit (or "exit": false) tells resQ not to call exit, so an interactive q
/ session stays open. Under the launcher q has no input and simply ended with
/ status 0, whatever the tests did: a failing run came out green.
.tst.desc["the launcher's exit status with -noquit #slow"]{
  should["be the run's verdict"]{
    wd: .resq.util.tempRoot[], "/resq_noquit_", string[.z.i], "_", string `long$.z.p;
    .resq.util.ensureDir wd;
    .tst.registerCleanup[{[d] @[system; "rm -rf -- ", .resq.util.shellQuote d; {}]}; enlist wd];
    (hsym `$wd, "/test_red.q") 0: enlist ".tst.desc[\"red\"]{ should[\"fails\"]{ 1 musteq 2; }; };";
    (hsym `$wd, "/test_green.q") 0: enlist ".tst.desc[\"green\"]{ should[\"passes\"]{ 1 musteq 1; }; };";
    (hsym `$wd, "/resq.json") 0: enlist "{\"exit\": false}";
    status: {[wd;file;flags]
        cmd: "cd ", .resq.util.shellQuote[wd], " && ", .resq.util.shellQuote[.resq.HOME, "/bin/resq"],
            " test ", file, " ", flags, " -outDir out -state-file out/s.json -flake-history out/f.json",
            " -flake-proposal-file out/p.json >/dev/null 2>&1; echo $?";
        "J"$last @[system; "sh -c ", .resq.util.shellQuote cmd; {[e] enlist "-1"}]}[wd];
    status["test_red.q"; "-noquit"] musteq 1;
    status["test_green.q"; "-noquit"] musteq 0;
    status["test_red.q"; "-noquit -isolate"] musteq 1;
    / the same through the config file alone
    status["test_red.q"; ""] musteq 1;
    status["missing.q"; "-noquit"] musteq 4;
  };
 };

/ Mistakes on the command line that ended in a q error and a trace, or were
/ passed over without a word.
.tst.testState.cliEdge.canRun: 0 < count @[system; "which q 2>/dev/null"; {()}];
.tst.testState.cliEdge.run:{[dir;words]
    cmd: "cd ", .resq.util.shellQuote[dir], " && ", (.resq.util.shellQuote .resq.HOME, "/bin/resq"), " ", words,
        " < /dev/null 2>&1; echo exit=$?";
    @[system; "sh -c ", .resq.util.shellQuote cmd; {[e] enlist "exit=-1"}]
 };

.tst.desc["command line: mistakes are named in one line #slow"]{
  before{
    dir: .resq.util.tempRoot[], "/resq_cli_edge_", string[.z.i], "_", string `long$.z.p;
    .resq.util.ensureDir dir, "/tests";
    .tst.registerCleanup[{[d] @[system; "rm -rf -- ", .resq.util.shellQuote d; {}]}; enlist dir];
    (hsym `$dir, "/tests/test_ok.q") 0: enlist ".tst.desc[\"ok\"]{ should[\"a\"]{ 1 musteq 1; }; };";
    `edgeDir mock dir;
    `state mock " -state-file out/s.json -flake-history out/f.json -flake-proposal-file out/p.json";
  };

  should["name a single-letter option q would reject, before q is started"]{
    if[not .tst.testState.cliEdge.canRun; :must[1b; "q unavailable"]];
    out: .tst.testState.cliEdge.run[edgeDir; "test tests -x"];
    (last out) musteq "exit=1";
    ((first out) like "CLI ERROR: unknown option -x.*") musteq 1b;
    (count out) musteq 2;
    / also where q would reject it after -args
    out: .tst.testState.cliEdge.run[edgeDir; "test tests -args -x"];
    (last out) musteq "exit=1";
    ((first out) like "CLI ERROR: q rejects the single-letter option -x*") musteq 1b;
  };

  should["pass q's own single-letter options on, and not -q twice"]{
    if[not .tst.testState.cliEdge.canRun; :must[1b; "q unavailable"]];
    out: .tst.testState.cliEdge.run[edgeDir; "test tests -q -p 0", state];
    (last out) musteq "exit=0";
    (any {[line] 0 < count ss[line; "1 total (1 passed"]} each out) musteq 1b;
  };

  should["say that q is missing, in its own words"]{
    if[not .tst.testState.cliEdge.canRun; :must[1b; "q unavailable"]];
    out: .tst.testState.cliEdge.run[edgeDir; "test tests; true"];
    cmd: "cd ", .resq.util.shellQuote[edgeDir], " && QBIN=/no/such/q ", (.resq.util.shellQuote .resq.HOME, "/bin/resq"),
        " test tests < /dev/null 2>&1; echo exit=$?";
    out: @[system; "sh -c ", .resq.util.shellQuote cmd; {[e] enlist "exit=-1"}];
    (last out) musteq "exit=127";
    ((first out) like "resQ ERROR: QBIN is set to '/no/such/q'*") musteq 1b;
  };

  should["report a plugin that is not there, and an empty path, as CLI errors"]{
    if[not .tst.testState.cliEdge.canRun; :must[1b; "q unavailable"]];
    out: .tst.testState.cliEdge.run[edgeDir; "test tests -plugin nope.q"];
    (last out) musteq "exit=1";
    (out 0) musteq "CLI ERROR: plugin file is not a regular file: nope.q";
    (count out) musteq 2;
    out: .tst.testState.cliEdge.run[edgeDir; "test \"\""];
    (last out) musteq "exit=1";
    ((first out) like "CLI ERROR: an empty path was given.*") musteq 1b;
  };

  should["warn when an isolate option is given without -isolate"]{
    if[not .tst.testState.cliEdge.canRun; :must[1b; "q unavailable"]];
    out: .tst.testState.cliEdge.run[edgeDir; "test tests -isolateTimeout 5 -isolateWorkers 2", state];
    (last out) musteq "exit=0";
    (any out like "CLI WARNING: -isolateTimeout and -isolateWorkers have no effect without -isolate*") musteq 1b;
  };

  should["print help into a pipe that is closed early without a q error"]{
    if[not .tst.testState.cliEdge.canRun; :must[1b; "q unavailable"]];
    cmd: (.resq.util.shellQuote .resq.HOME, "/bin/resq"), " --help 2>&1 < /dev/null | head -1";
    out: @[system; "sh -c ", .resq.util.shellQuote cmd; {[e] enlist "failed"}];
    (count out) musteq 1;
    ((first out) like "resQ *") musteq 1b;
    (0 < count ss[first out; "testing"]) musteq 1b;
    errors: @[system; "sh -c ", .resq.util.shellQuote "{ ", (.resq.util.shellQuote .resq.HOME, "/bin/resq"),
        " --help < /dev/null | head -1 > /dev/null; } 2>&1"; {[e] enlist "failed"}];
    (count errors) musteq 0;
  };
 };

