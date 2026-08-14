/ lib/isolate.q - Fail-safe process-per-file execution.
/ ============================================================================
/ The parent discovers files once, launches each in a preemptively bounded q
/ child, consumes a private JSON report, merges rows, reports once, and returns
/ the normal granular exit code. The caller owns process exit policy.
/ ============================================================================

\d .tst

.tst.isolate.commandPath:{[name]
    found: @[system; "command -v ", name, " 2>/dev/null"; {()}];
    $[count found; first found; ""]
 };

.tst.isolate.timeoutExe: .tst.isolate.commandPath "timeout";
.tst.isolate.requestedQ:getenv `QBIN;
.tst.isolate.qExe:$[count .tst.isolate.requestedQ;
    .tst.isolate.requestedQ;
    .tst.isolate.commandPath "q"];
.tst.isolate.mktempExe: .tst.isolate.commandPath "mktemp";
.tst.isolate.chmodExe: .tst.isolate.commandPath "chmod";
.tst.isolate.rmExe: .tst.isolate.commandPath "rm";
.tst.isolate.shExe: .tst.isolate.commandPath "sh";
.tst.isolate.childInventory:();

/ All isolation diagnostics pass through one gate so qspec's -pass contract is
/ silent while the parent still returns the aggregated process status.
.tst.isolate.print:{[message]
    if[1b ~ @[get; `.tst.app.passOnly; 0b]; :()];
    -1 message
 };

/ Require timeout's kill-after form and prove it can preempt a busy process.
.tst.isolate.probeTimeout:{[exe]
    if[(0 = count exe) or 0 = count .tst.isolate.shExe; :0b];
    help: @[system; "LC_ALL=C ",.utl.shellQuote[exe], " --help 2>/dev/null"; {[e] ()}];
    if[not any help like "*--verbose*"; :0b];
    busy: .utl.shellQuote "while :; do :; done";
    cmd:"LC_ALL=C ",.utl.shellQuote[exe], " -k 1 0.05 ",
         .utl.shellQuote[.tst.isolate.shExe], " -c ", busy, " 2>&1; echo $?";
    out: @[system; cmd; {[e] enlist "-1"}];
    if[0 = count out; :0b];
    code: "J"$last out;
    code in 124 137
 };

/ Scratch directories are tracked as strings; only paths returned by mktemp and
/ present in this allocation list may be recursively removed.
.tst.isolate.allocated: ();

/ Shares .utl.tempRoot (which honours TMPDIR) and then enforces the stricter
/ requirements isolation has: the root must exist and be a real directory,
/ because child processes are about to write scratch into it.
.tst.isolate.tempRoot:{[]
    private:getenv `RESQ_ISOLATE_ROOT;
    root:$[count private;.utl.normalizePath private;.utl.tempRoot[]];
    if[(0 = count root) or not "/" = first root;
        '"TMPDIR must be an absolute directory: ", root];
    if[not .utl.isDir root;
        '"TMPDIR does not exist or is not a directory: ", root];
    root
 };

.tst.isolate.scratchPrefix:{[root]
    root, $["/" = last root; ""; "/"], "resq_isolate."
 };

.tst.isolate.validScratch:{[wd]
    root: .tst.isolate.tempRoot[];
    prefix: .tst.isolate.scratchPrefix root;
    suffix: (count prefix) _ wd;
    (prefix ~ (count prefix) # wd) and
        (0 < count suffix) and
        (not any "/" = suffix) and
        any wd ~/: .tst.isolate.allocated
 };

.tst.isolate.createScratch:{[]
    if[0 = count .tst.isolate.mktempExe; '"mktemp executable is required for isolation"];
    if[0 = count .tst.isolate.chmodExe; '"chmod executable is required for isolation"];
    root: .tst.isolate.tempRoot[];
    template: (.tst.isolate.scratchPrefix root), "XXXXXXXX";
    cmd: .utl.shellQuote[.tst.isolate.mktempExe], " -d ", .utl.shellQuote template;
    made: @[system; cmd; {[e] '"mktemp failed: ", e}];
    if[0 = count made; '"mktemp returned no scratch directory"];
    wd: first made;
    prefix: .tst.isolate.scratchPrefix root;
    suffix: (count prefix) _ wd;
    if[(not prefix ~ (count prefix) # wd) or (0 = count suffix) or any "/" = suffix;
        '"mktemp returned an unsafe scratch path: ", wd];
    if[not .utl.isDir wd; '"mktemp scratch directory does not exist: ", wd];
    .tst.isolate.allocated,: enlist wd;
    secured: @[
        {system x; 1b};
        .utl.shellQuote[.tst.isolate.chmodExe], " 700 -- ", .utl.shellQuote wd;
        {[e] 0b}];
    if[not secured;
        .tst.isolate.cleanupScratch wd;
        '"failed to restrict isolation scratch permissions: ", wd;
    ];
    wd
 };

.tst.isolate.cleanupScratch:{[wd]
    if[not .tst.isolate.validScratch wd;
        .tst.isolate.print "ERROR: refusing unsafe isolation scratch cleanup: ", wd;
        :0b];
    if[0 = count .tst.isolate.rmExe;
        .tst.isolate.print "ERROR: rm executable unavailable; cannot clean isolation scratch: ", wd;
        :0b];
    cmd: .utl.shellQuote[.tst.isolate.rmExe], " -rf -- ", .utl.shellQuote wd;
    ok: @[{system x; 1b}; cmd; {[e] 0b}];
    inspected: @[
        {[path] `ok`exists!(1b; .utl.pathExists path)};
        wd;
        {[e] `ok`exists!(0b; 1b)}];
    if[not inspected`ok;
        .tst.isolate.print "ERROR: unable to inspect isolation scratch after cleanup: ", wd;
        :0b];
    if[inspected`exists; ok: 0b];
    if[ok;
        .tst.isolate.allocated:
            .tst.isolate.allocated where not wd ~/: .tst.isolate.allocated];
    ok
 };

.tst.isolate.toStrList:{[v]
    $[10h = type v; enlist v;
      0h = type v; v;
      (::) ~ v; ();
      enlist .tst.toString v]
 };

/ Preserve the schema-v2 telemetry emitted by an isolated child. The parent
/ still normalizes the legacy/core columns below, but it must not collapse a
/ retry, parameter/property case, diagnostic, snapshot, or benchmark back to
/ the pre-v2 row shape while merging processes.
.tst.isolate.telemetryFromJson:{[t;base]
    fields:`startedAt`finishedAt`testId`caseId`kind`parameters`attempts`retried`flaky`attemptHistory`parameterCases`property`diagnostics`snapshots`benchmark`quarantine;
    out:.tst.completeResultRow base;
    present:fields inter key t;
    if[count present;out[present]:t present];
    if[`startedAt in present;
        out[`startedAt]:$[-9h=type out`startedAt;(::);.tst.toString out`startedAt]];
    if[`finishedAt in present;
        out[`finishedAt]:$[-9h=type out`finishedAt;(::);.tst.toString out`finishedAt]];
    if[`kind in present;out[`kind]:`$.tst.toString out`kind];
    if[`attempts in present;out[`attempts]:"i"$out`attempts];
    if[`retried in present;out[`retried]:1b~out`retried];
    if[`flaky in present;out[`flaky]:1b~out`flaky];
    out
 };

.tst.isolate.rowWithMeta:{[suite;dsc;status;message;tm;failures;asserts;rowMeta]
    flip `suite`description`status`message`time`startedAt`finishedAt`failures`assertsRun`file`line`namespace`tags`output!(
        enlist suite;
        enlist dsc;
        enlist status;
        enlist message;
        enlist tm;
        enlist $[`startedAt in key rowMeta;rowMeta`startedAt;(::)];
        enlist $[`finishedAt in key rowMeta;rowMeta`finishedAt;(::)];
        enlist failures;
        enlist `int$asserts;
        enlist $[`file in key rowMeta; rowMeta`file; ""];
        enlist $[`line in key rowMeta; "i"$rowMeta`line; 0Ni];
        enlist $[`namespace in key rowMeta; rowMeta`namespace; ""];
        enlist $[`tags in key rowMeta; rowMeta`tags; `symbol$()];
        enlist $[`output in key rowMeta; .tst.toString rowMeta`output; ""])
 };

.tst.isolate.row:{[suite; dsc; status; message; tm; failures; asserts]
    .tst.isolate.rowWithMeta[suite;dsc;status;message;tm;failures;asserts;()!()]
 };

.tst.isolate.errorRow:{[suiteSym; file; msg]
    stamp:.tst.isoTimestamp .z.p;
    timingMeta:`startedAt`finishedAt!(stamp;stamp);
    base:first .tst.isolate.rowWithMeta[
        suiteSym;`$file;`error;msg;0Nn;enlist msg;0i;timingMeta];
    .tst.oneResultTable base
 };

.tst.isolate.processExitRow:{[file; code; unexpected]
    msg: $[unexpected;
        "child produced a valid report but exited with unexpected code ",
            string[code], "; process status and report disagree";
        "child produced a valid report with no failing rows but exited with code ",
            string[code], "; refusing inconsistent success"];
    .tst.isolate.errorRow[`ISOLATED_PROCESS_EXIT; file; msg]
 };

.tst.isolate.tail:{[wd; n]
    lines: "\n" vs .tst.isolate.readCaptured wd;
    lines: (neg n) sublist lines;
    $[count lines; "\n" sv lines; ""]
 };

/ GNU timeout's verbose line is evidence that the supervisor actually sent a
/ deadline signal. Exit 124/137 alone is ambiguous: a child may return 124
/ itself, and SIGKILL/OOM conventionally appears as 137 without any timeout.
.tst.isolate.supervisorTimedOut:{[wd]
    captured:.tst.isolate.readCaptured wd;
    0 < count ss[captured; "timeout: sending signal "]
 };

/ Read at most reportLimit bytes from a child's combined stdout/stderr. For a
/ large log keep both ends: setup/user diagnostics tend to be near the front,
/ while the framework verdict and runtime fatal text are near the back.
.tst.isolate.readCaptured:{[wd]
    path: hsym `$wd, "/out.txt";
    size: @[hcount; path; {[err] 0}];
    if[size <= 0; :""];
    limit: "j"$@[get; `.tst.output.reportLimit; 50000];
    if[(null limit) or limit <= 0; :""];
    if[size <= limit;
        :.tst.isolate.trimChildReport "c"$@[read1; (path;0;size); {[err] `byte$()}]];

    marker: "\n... [captured child output truncated ",
        string[size - limit], " bytes] ...\n";
    if[limit <= count marker;
        :.tst.isolate.trimChildReport "c"$@[read1; (path;size - limit;limit); {[err] `byte$()}]];
    keep: limit - count marker;
    headCount: keep div 2;
    tailCount: keep - headCount;
    head: "c"$@[read1; (path;0;headCount); {[err] `byte$()}];
    tail: "c"$@[read1; (path;size - tailCount;tailCount); {[err] `byte$()}];
    .tst.isolate.trimChildReport head,marker,tail
 };

/ Drop the child's own report from its captured stdout, keeping everything the
/ TEST produced. Cuts at the sentinel the child emits immediately before
/ reporting (see .tst.isolatedReportSentinel in lib/runner.q).
/ .
/ Fails open: an absent sentinel -- an old child, a child that died before
/ reporting, or a sentinel split by the head/tail truncation above -- returns the
/ text unchanged, because losing a duplicate summary matters far less than losing
/ a diagnostic. Trailing blank lines go too, so the forwarded transcript does not
/ end in whitespace the reporters would have to trim again.
.tst.isolate.trimChildReport:{[text]
    if[0 = count text; :text];
    sentinel: @[get; `.tst.isolatedReportSentinel; {""}];
    if[0 = count sentinel; :text];
    at: ss[text; sentinel];
    if[0 = count at; :text];
    kept: (first at) # text;
    while[(0 < count kept) and (last kept) in " \t\r\n"; kept: -1 _ kept];
    kept
 };

/ Attach one bounded per-file transcript to the first failing/error row. This
/ avoids repeating a file's log for every failed test while keeping it in the
/ canonical result table for console, JSON, JUnit and xUnit reporters.
.tst.isolate.attachCaptured:{[wd;rows]
    if[(not 98h = type rows) or 0 = count rows; :rows];
    statuses: .tst.normalizeResultStatus each rows`status;
    failing: where statuses in `fail`error;
    if[0 = count failing; :rows];
    captured: .tst.stripAnsi .tst.isolate.readCaptured wd;
    if[0 = count captured; :rows];
    outputs: $[`output in cols rows; rows`output; (count rows) # enlist ""];
    outputs[first failing]: captured;
    rows[`output]: outputs;
    rows
 };

/ A child that dies before JSON exists may have called exit, but its captured
/ tail can identify a fatal q/runtime condition. Prefer that evidence over the
/ old blanket "did a test call exit?" guess.
.tst.isolate.fatalHint:{[detail]
    if[0 = count detail; :""];
    normalized: lower detail;
    needles: ("couldn't connect to license daemon";"wsfull";"stack overflow";"segmentation fault";"segfault";
              "out of memory";"cannot allocate memory";"aborted";"core dumped");
    hits: needles where {[txt;needle] 0 < count ss[txt;needle]}[normalized;] each needles;
    $[count hits; first hits; ""]
 };

.tst.isolate.noReportMessage:{[code;detail]
    hint: .tst.isolate.fatalHint detail;
    prefix: $[hint~"couldn't connect to license daemon";
        "q child could not start because its licence allocation was unavailable; provision one q runtime/licence per concurrent worker or reduce -isolateWorkers";
        count hint;
        "child terminated before producing results; output identifies a q runtime/startup failure (",
            hint,")";
        "process exited (code ",string[code],
            ") without producing results - did a test call exit?"];
    prefix, $[count detail; "\n",detail; ""]
 };

/ Retry only a q process that demonstrably failed before startup because the KX
/ license daemon was temporarily unavailable. Never retry user test failures.
.tst.isolate.retryableStartupFailure:{[rows]
    if[0 = count rows; :0b];
    needle: "couldn't connect to license daemon";
    any {[target;row]
        msg: lower .tst.toString first row`message;
        0 < count ss[msg;target]
    }[needle;] each rows
 };

.tst.isolate.rowsFromJson:{[tests]
    tests: $[98h = type tests; {[t;i] t i}[tests] each til count tests;
             99h = type tests; enlist tests;
             0h = type tests; tests;
             enlist tests];
    raze {[t]
        suite: `$ .tst.toString t`suite;
        dsc: `$ .tst.toString t`description;
        status: `$ .tst.toString t`status;
        msg: $[`message in key t; t`message; ""];
        msg: $[0h = type msg; .tst.isolate.toStrList msg; msg];
        tmText: $[`time in key t; .tst.toString t`time; ""];
        tm: $[count tmText; @["N"$; tmText; 0Nn]; 0Nn];
        fails: .tst.isolate.toStrList $[`failures in key t; t`failures; ()];
        asserts: $[`assertsRun in key t; t`assertsRun; 0];
        sourcePath: $[`file in key t; .tst.toString t`file; ""];
        sourceNs: $[`namespace in key t; .tst.toString t`namespace; ""];
        rowTags: $[`tags in key t; `$(),t`tags; `symbol$()];
        sourceLine: $[`line in key t; "i"$t`line; 0Ni];
        sourceOutput: $[`output in key t; .tst.toString t`output; ""];
        rowMeta: `file`line`namespace`tags`output`startedAt`finishedAt!(
            sourcePath;sourceLine;sourceNs;rowTags;sourceOutput;
            $[`startedAt in key t;t`startedAt;(::)];
            $[`finishedAt in key t;t`finishedAt;(::)]);
        base:first .tst.isolate.rowWithMeta[suite;dsc;status;msg;tm;fails;asserts;rowMeta];
        .tst.oneResultTable .tst.isolate.telemetryFromJson[t;base]
    } each tests
 };

.tst.isolate.decodeReport:{[raw]
    if[0 = count raw; :`valid`report`error!(0b; ()!(); "report missing")];
    attempt: @[
        {[text] `ok`value!(1b; .j.k text)};
        "\n" sv raw;
        {[e] `ok`value!(0b; ()!())}];
    report: attempt`value;
    valid: (1b ~ attempt`ok) and (99h = type report) and `tests in key report;
    error: $[valid; ""; $[1b ~ attempt`ok; "JSON report missing tests"; "malformed JSON report"]];
    `valid`report`error!(valid; report; error)
 };

.tst.isolate.appendValue:{[argv; flag; val]
    $[0 < count val; argv, (flag; .tst.toString val); argv]
 };

.tst.isolate.appendFlag:{[argv; flag; enabled]
    $[1b ~ enabled; argv, enlist flag; argv]
 };

.tst.isolate.serializeValues:{[values]
    if[() ~ values; :""];
    if[10h = type values; :values];
    if[-11h = type values; :string values];
    if[0 = count values; :""];
    "," sv .tst.toString each (),values
 };

.tst.isolate.privateRerunPath:{[wd]wd,"/last-run.json"};

/ Copy the parent's already-validated selection cache into each private child
/ scratch. Children may then apply last-failed/failed-first consistently, but
/ any state they publish is disposable and can never race the durable parent.
.tst.isolate.preparePrivateRerunState:{[wd]
    state:@[get;`.tst.app.rerunState;{.tst.emptyRerunState `missing}];
    ids:$[`ok~state`status;state`failedTestIds;()];
    doc:`schemaVersion`identityAlgorithm`identityCodec`framework`runId`updatedAt`testCount`failedCount`failedTestIds!(
        .tst.rerunStateVersion;.tst.IDENTITY_ALGORITHM;.tst.identityCodecMetadata[];"resQ";
        $[`runId in key state;.tst.toString state`runId;""];
        $[`updatedAt in key state;.tst.toString state`updatedAt;""];
        "j"$count ids;"j"$count ids;ids);
    .tst.atomicWriteJson[.tst.isolate.privateRerunPath wd;doc;`isolation]
 };

/ A child owns one file, while suite/tag selection is global to the parent run.
/ Therefore a valid empty child report is neutral when any selector is active;
/ the parent still applies the ordinary no-results failure after all files have
/ been aggregated, so a filter that matches nowhere remains non-zero.
.tst.isolate.filtersActive:{[]
    (1b~@[get;`.tst.app.lastFailed;0b]) or any 0 < count each (
        @[get; `.tst.app.runSpecs; ()];
        @[get; `.tst.app.excludeSpecs; ()];
        @[get; `.tst.app.tagFilter; ()];
        @[get; `.tst.app.excludeTagFilter; ()])
 };

/ Child argv derives from normalized CLI values plus effective parent settings.
/ Parent reporter/lifecycle/isolation options are deliberately absent.
.tst.isolate.childArgv:{[file; wd]
    argv: (.tst.isolate.qExe; .resq.HOME, "/resq.q"; "-q"; "test"; file);
    argv: .tst.isolate.appendValue[argv; "-only";
        .tst.isolate.serializeValues @[get; `.tst.app.runSpecs; ()]];
    argv: .tst.isolate.appendValue[argv; "-exclude";
        .tst.isolate.serializeValues @[get; `.tst.app.excludeSpecs; ()]];
    argv: .tst.isolate.appendValue[argv; "-tag";
        .tst.isolate.serializeValues @[get; `.tst.app.tagFilter; ()]];
    argv: .tst.isolate.appendValue[argv; "-exclude-tag";
        .tst.isolate.serializeValues @[get; `.tst.app.excludeTagFilter; ()]];
    argv: .tst.isolate.appendFlag[argv; "-strict"; @[get; `.tst.app.strict; 0b]];
    argv: .tst.isolate.appendFlag[argv; "-perf"; @[get; `.tst.app.runPerformance; 0b]];
    argv: .tst.isolate.appendFlag[argv; "-fail-fast"; @[get; `.tst.app.failFast; 0b]];
    argv: .tst.isolate.appendFlag[argv; "-fail-hard"; @[get; `.tst.app.failHard; 0b]];
    argv: .tst.isolate.appendFlag[argv; "-qspec-compat"; @[get; `.tst.app.qspecCompat; 0b]];
    argv: .tst.isolate.appendFlag[argv; "-no-line-annotations";
        not @[get; `.tst.app.expectationLineAnnotations; 1b]];
    argv: .tst.isolate.appendValue[argv; "-maxTestTime"; @[get; `.tst.app.maxTestTime; 0]];
    argv: .tst.isolate.appendValue[argv; "-fuzzLimit"; @[get; `.tst.output.fuzzLimit; 0]];
    argv: .tst.isolate.appendFlag[argv; "-quiet"; @[get; `.tst.app.quiet; 0b]];
    argv: .tst.isolate.appendFlag[argv; "-random-order"; @[get; `.tst.app.randomOrder; 0b]];
    if[1b~@[get;`.tst.app.randomOrder;0b];
        argv:.tst.isolate.appendValue[argv;"-seed";@[get;`.tst.app.executionSeed;0j]]];
    argv:.tst.isolate.appendFlag[argv;"-last-failed";@[get;`.tst.app.lastFailed;0b]];
    argv:.tst.isolate.appendFlag[argv;"-failed-first";@[get;`.tst.app.failedFirst;0b]];
    argv:.tst.isolate.appendValue[argv;"-state-file";.tst.isolate.privateRerunPath wd];
    / The parent is the sole durable flake-history writer. Give every child
    / private scratch paths so concurrent workers cannot race, while propagating
    / the reviewed manifest and policy needed to keep fail-fast from stopping on
    / a known quarantine. The parent reclassifies every merged raw row.
    argv:.tst.isolate.appendValue[argv;"-flake-history";wd,"/flake-history.json"];
    argv:.tst.isolate.appendValue[argv;"-flake-proposal-file";wd,"/quarantine-proposals.json"];
    argv:.tst.isolate.appendValue[argv;"-quarantine-file";.tst.quarantineManifestPath[]];
    argv:.tst.isolate.appendFlag[argv;"-quarantine-non-blocking";
        @[get;`.tst.app.quarantineNonBlocking;0b]];
    / Children publish reference/declaration fragments, but never gate their
    / necessarily partial per-file inventories. The aggregate parent gates.
    argv:.tst.isolate.appendFlag[argv;"-snapshot-audit";
        (1b~@[get;`.tst.app.snapshotAudit;0b]) or 1b~@[get;`.tst.app.snapshotGate;0b]];
    / File sharding is complete in the parent. Test/case sharding uses stable-ID
    / hashing, so every per-file child can apply the same global topology
    / independently and obtain exactly the parent's selected subset.
    unit:@[get;`.tst.app.shardUnit;`file];
    childIndex:$[unit~`file;0;@[get;`.tst.app.shardIndex;0j]];
    childCount:$[unit~`file;1;@[get;`.tst.app.shardCount;1j]];
    argv:.tst.isolate.appendValue[argv;"-shard-index";childIndex];
    argv:.tst.isolate.appendValue[argv;"-shard-count";childCount];
    argv:.tst.isolate.appendValue[argv;"-shard-unit";string unit];
    / The child JSON is an internal merge protocol and must retain detailed rows
    / even when the parent will publish a compact external profile.
    argv:.tst.isolate.appendValue[argv;"-report-profile";"full"];
    / Only the aggregate parent publishes repository context. Avoid one Git
    / traversal per isolated file, especially in large worktrees.
    argv,:enlist "-no-vcs";
    / Marks where the child's own report starts so readCaptured can forward the
    / test output without the child's duplicate summary and scratch-path
    / reporter lines. See .tst.isolatedReportSentinel in lib/runner.q.
    argv,: enlist "-isolate-child";
    argv, ("-json"; "-outDir"; wd)
 };

.tst.isolate.shellCommand:{[argv]
    " " sv .utl.shellQuote each argv
 };

/ Clear artifacts a previous attempt may have left, so a retry (or a reused
/ scratch) can never decode a stale report.
.tst.isolate.resetScratch:{[wd]
    @[hdel; hsym `$wd, "/out.txt"; {}];
    @[hdel; hsym `$wd, "/test-results.json"; {}];
    @[hdel; hsym `$wd, "/rc.txt"; {}];
    ::
 };

/ The direct shell command for ONE child. It intentionally contains no trailing
/ shell list: runGroup backgrounds this exact timeout process, records its PID
/ (also its process-group ID under GNU timeout), and can therefore terminate the
/ complete child tree if the foreground run is interrupted.
.tst.isolate.processCommand:{[wd; file; timeoutSecs]
    childArgv: .tst.isolate.childArgv[file; wd];
    timedArgv: (.tst.isolate.timeoutExe; "--verbose"; "-k";
        .tst.toString 5; string timeoutSecs), childArgv;
    / The parent launcher owns its completion marker. Isolated q children are
    / already supervised by this module and must not complete the parent's run.
    "LC_ALL=C RESQ_RUN_GUARD_DIR='' ", .tst.isolate.shellCommand[timedArgv],
        " < /dev/null > ", .utl.shellQuote[wd, "/out.txt"], " 2>&1"
 };

/ The sequential retry helper also needs the exit code in rc.txt. Keeping it in
/ the child's own scratch prevents concurrent stdout from becoming ambiguous.
/ The trailing `; true` is load-bearing. q's `system` swallows a redirection that
/ ENDS the command string -- `... ; echo $? > rc.txt` runs with the redirect
/ stripped, so the code lands on q's stdout and rc.txt is created but left empty.
/ Any command after the redirect restores normal shell behaviour. Verified: with
/ the trailing `; true` removed, every file reports "exit -1".
.tst.isolate.fileCommand:{[wd; file; timeoutSecs]
    .tst.isolate.processCommand[wd;file;timeoutSecs],"; ",
        "echo $? > ", .utl.shellQuote[wd, "/rc.txt"], "; true"
 };

.tst.isolate.groupStart:{[index;command]
    name:"p",string index;
    command," & ",name,"=$!; pids=\"$pids $",name,"\";"
 };

.tst.isolate.groupWait:{[index;wd]
    name:"p",string index;
    "wait \"$",name,"\"; echo $? > ",.utl.shellQuote[wd,"/rc.txt"],";"
 };

/ Exit code recorded by fileCommand. A missing or unparseable rc.txt means the
/ child never got far enough to write one, which is itself a failure (-1), not a
/ success -- defaulting to 0 here would turn a dead child into a green file.
.tst.isolate.readExitCode:{[wd]
    lines: @[read0; hsym `$wd, "/rc.txt"; {()}];
    if[0 = count lines; :-1];
    text: last lines;
    if[not .tst.cli.isIntegerText text; :-1];
    "J"$text
 };

.tst.isolate.runFileBody:{[wd; file; timeoutSecs; k; n]
    .tst.isolate.resetScratch wd;
    if[not .tst.isolate.preparePrivateRerunState wd;
        '"unable to prepare private rerun state"];
    @[system; .tst.isolate.fileCommand[wd; file; timeoutSecs]; {[e] ()}];
    .tst.isolate.interpretFile[wd; file; timeoutSecs; k; n; .tst.isolate.readExitCode wd]
 };

/ Turn one finished child's artifacts into result rows. Pure with respect to
/ subprocesses -- it only reads what the child left behind -- so it is shared by
/ the sequential and parallel paths and both classify a file identically.
.tst.isolate.interpretFile:{[wd; file; timeoutSecs; k; n; code]
    raw: @[read0; hsym `$wd, "/test-results.json"; {()}];
    decoded: .tst.isolate.decodeReport raw;
    valid: decoded`valid;
    report: decoded`report;
    if[valid and `manifest in key report;
        childManifest:report`manifest;
        if[(99h=type childManifest) and `tests in key childManifest;
            .tst.isolate.childInventory,:.tst.eventRows childManifest`tests]];
    if[valid and `snapshotInventory in key report;
        childSnapshots:report`snapshotInventory;
        if[(99h=type childSnapshots) and `entries in key childSnapshots;
            declared:.tst.snapshotRows childSnapshots`entries;
            declared:declared where {1b~x`declared} each declared;
            if[count declared;
                .tst.app.snapshotDeclarations,:{[entry]
                    `backend`name`path`root`absolutePath`executionId`observedStatus`declared`dynamic!(
                        `$entry`backend;.tst.toString entry`name;.tst.toString entry`path;
                        .tst.toString entry`root;.tst.toString entry`absolutePath;"";"declared";
                        1b;$[`dynamic in key entry;1b~entry`dynamic;1b])
                  } each declared]]];
    tests: $[valid; report`tests; ()];
    rows: $[valid; .tst.isolate.rowsFromJson tests; ()];
    rowStatus: $[count rows;
        .tst.normalizeResultStatus each {first x`status} each rows;
        `symbol$()];
    hasFailingRows: any rowStatus in `fail`error;
    progress: "[", string[k], "/", string[n], "] ", file, " ... ";

    timedOut:.tst.isolate.supervisorTimedOut wd;
    if[timedOut;
        msg: "file exceeded isolateTimeout (", string[timeoutSecs], "s); killed",
             $[count detail: .tst.isolate.tail[wd; 20]; "\n", detail; ""];
        .tst.isolate.print progress, "TIMEOUT";
        :.tst.isolate.attachCaptured[wd;
            enlist .tst.isolate.errorRow[`ISOLATED_FILE_TIMEOUT; file; msg]]];

    if[code = .resq.EXIT.LOAD_ERROR;
        hasLoadRow: $[count rows;
            any ({first x`suite} each rows) = `FILE_LOAD_ERROR;
            0b];
        if[hasLoadRow;
            .tst.isolate.print progress, "LOAD ERROR (", string[count rows], " rows)";
            :.tst.isolate.attachCaptured[wd;rows]];
        msg: "file failed to load (exit 4)",
             $[count detail: .tst.isolate.tail[wd; 20]; "\n", detail; ""];
        .tst.isolate.print progress, "LOAD ERROR";
        :.tst.isolate.attachCaptured[wd;
            rows, enlist .tst.isolate.errorRow[`FILE_LOAD_ERROR; file; msg]]];

    if[valid;
        if[code = .resq.EXIT.PASS;
            .tst.isolate.print progress, "ok (", string[count rows], " tests)";
            :rows];
        if[(code = .resq.EXIT.FAIL) and (0 = count rows) and .tst.isolate.filtersActive[];
            .tst.isolate.print progress, "filtered (0 tests)";
            :rows];
        if[(code = .resq.EXIT.FAIL) and hasFailingRows;
            .tst.isolate.print progress, "FAILED (", string[count rows], " tests)";
            :.tst.isolate.attachCaptured[wd;rows]];
        expectedCodes: (.resq.EXIT.PASS; .resq.EXIT.FAIL; .resq.EXIT.LOAD_ERROR);
        unexpected: not code in expectedCodes;
        processRow: .tst.isolate.processExitRow[file; code; unexpected];
        .tst.isolate.print progress, "PROCESS ERROR (exit ", string[code], ")";
        :.tst.isolate.attachCaptured[wd;rows, enlist processRow]];

    detail: .tst.isolate.tail[wd; 20];
    if[0 = count raw;
        if[code=137;
            msg:"child exited 137 (SIGKILL; possible OOM or external kill); ",
                "the isolate supervisor did not initiate a timeout",
                $[count detail;"\n",detail;""];
            .tst.isolate.print progress,"KILLED (exit 137, no results)";
            :.tst.isolate.attachCaptured[wd;
                enlist .tst.isolate.errorRow[`ISOLATED_PROCESS_KILLED;file;msg]]];
        if[code=-1;
            msg:"isolation infrastructure did not record a child exit status",
                $[count detail;"\n",detail;""];
            .tst.isolate.print progress,"INFRASTRUCTURE ERROR";
            :.tst.isolate.attachCaptured[wd;
                enlist .tst.isolate.errorRow[`ISOLATED_INFRASTRUCTURE_ERROR;file;msg]]];
        msg: .tst.isolate.noReportMessage[code;detail];
        licenseFailure:.tst.isolate.fatalHint[detail]~"couldn't connect to license daemon";
        suite:$[licenseFailure;`ISOLATED_Q_STARTUP_ERROR;`ISOLATED_PROCESS_EXIT];
        .tst.isolate.print progress,
            $[licenseFailure;"Q STARTUP ERROR";"DIED (exit ", string[code], ", no results)"];
        :.tst.isolate.attachCaptured[wd;
            enlist .tst.isolate.errorRow[suite; file; msg]]];

    msg: decoded`error, " (exit ", string[code], ")",
         $[count detail; "\n", detail; ""];
    .tst.isolate.print progress, "INVALID REPORT";
    .tst.isolate.attachCaptured[wd;
        enlist .tst.isolate.errorRow[`ISOLATED_REPORT_ERROR; file; msg]]
 };

.tst.isolate.runFile:{[file; timeoutSecs; k; n]
    scratchAttempt: @[
        {[ignored] `ok`wd!(1b; .tst.isolate.createScratch[])};
        ();
        {[e] `ok`wd!(0b; e)}];
    if[not scratchAttempt`ok;
        msg: "unable to create private isolation scratch: ", .tst.toString scratchAttempt`wd;
        :enlist .tst.isolate.errorRow[`ISOLATED_SETUP_ERROR; file; msg]];

    wd: scratchAttempt`wd;
    result: ();
    retryStartup: 1b;
    attempt: 0;
    while[retryStartup and attempt < 3;
        attempt+: 1;
        result: .[
            .tst.isolate.runFileBody;
            (wd; file; timeoutSecs; k; n);
            {[file; e]
                msg: "isolation helper failed: ", e;
                enlist .tst.isolate.errorRow[`ISOLATED_HELPER_ERROR; file; msg]
            }[file;]];
        retryStartup: .tst.isolate.retryableStartupFailure result;
        if[retryStartup and attempt < 3;
            .tst.isolate.print "  transient q license startup failure; retrying file (attempt ",
                string[attempt + 1], "/3)";
            system "sleep 1"];
    ];
    cleaned: @[
        .tst.isolate.cleanupScratch;
        wd;
        {[file; e]
            .tst.isolate.print "ERROR: isolation scratch cleanup failed for ", file, ": ", e;
            0b
        }[file;]];
    if[not cleaned;
        result,: enlist .tst.isolate.errorRow[
            `ISOLATED_CLEANUP_ERROR; file; "failed to remove private isolation scratch"]];
    result
 };

.tst.isolate.parentLoadRows:{[]
    errors: $[`loadErrors in key `.tst.app;
        .tst.app.loadErrors;
        flip `file`error`type!(`symbol$(); (); `symbol$())];
    if[0 = count errors; :()];
    records: {[table; i] table i}[errors] each til count errors;
    {[record]
        file: .tst.toString record`file;
        msg: "Explicit test path failed discovery: ", file, " (", .tst.toString[record`error], ")";
        .tst.isolate.errorRow[`FILE_LOAD_ERROR; file; msg]
    } each records
 };

.tst.isolate.upsertRows:{[rows]
    if[0 = count rows; :()];
    {[row] .resq.state.results: .resq.state.results upsert row} each rows;
 };

.tst.isolate.dropChildStrict:{[]
    if[0 = count .resq.state.results; :()];
    .resq.state.results:
        select from .resq.state.results where suite <> `STRICT_MODE_FAILURE;
 };

.tst.isolate.executedCount:{[]
    if[0 = count .resq.state.results; :0];
    status: .tst.normalizeResultStatus each .resq.state.results`status;
    synthetic:`STRICT_MODE_FAILURE`FILE_LOAD_ERROR`ISOLATED_FILE_TIMEOUT`ISOLATED_FILE_DIED`ISOLATED_Q_STARTUP_ERROR`ISOLATED_REPORT_ERROR`ISOLATED_PROCESS_EXIT`ISOLATED_SETUP_ERROR`ISOLATED_HELPER_ERROR`ISOLATED_CLEANUP_ERROR`ISOLATION_UNAVAILABLE;
    executed: status in `pass`fail`error;
    generated: (.resq.state.results`suite) in synthetic;
    sum executed where not generated
 };

.tst.isolate.addGlobalStrict:{[]
    if[not 1b ~ @[get; `.tst.app.strict; 0b]; :()];
    if[1b~@[get;`.tst.app.emptyShard;0b];:()];
    if[0 < .tst.app.expectationsRan; :()];
    .tst.isolate.upsertRows enlist .tst.isolate.errorRow[
        `STRICT_MODE_FAILURE;
        "NO_TESTS_FOUND";
        "Strict mode enabled but no tests were executed (skipped tests do not count under -strict)."]
 };

/ Run ONE group of files concurrently and return their rows in file order.
/ .
/ q cannot do this in-process -- secondary threads cannot write globals, which is
/ why in-process parallelism was removed (docs/PARALLEL.md). But isolation has
/ already paid for separate processes: each child owns a private scratch and
/ communicates only through files in it, so running several at once needs no
/ shared state at all. The shell does the waiting; q stays single-threaded.
/ .
/ Determinism is preserved deliberately: children start together, but their
/ artifacts are interpreted and PRINTED strictly in file order once the whole
/ group has finished. Two runs of the same suite produce byte-identical output.
/ `files` and `ks` are PARALLEL LISTS, not a list of dicts: q silently collapses a
/ list of same-keyed dicts into a table, after which `@\:` and per-row indexing
/ change meaning and this function fails with 'type. Plain lists keep it obvious.
.tst.isolate.runGroup:{[files; ks; timeoutSecs; n]
    wds: {[ignored]
        @[{[i] .tst.isolate.createScratch[]}; 0; {[err] ""}]
    } each files;
    okFlags: 0 < count each wds;
    {[wd] if[count wd; .tst.isolate.resetScratch wd]} each wds;
    prepared:{[wd]$[count wd;.tst.isolate.preparePrivateRerunState wd;0b]} each wds;
    okFlags:okFlags and prepared;

    cmds: {[timeoutSecs; wd; file]
        $[count wd; .tst.isolate.processCommand[wd; file; timeoutSecs]; ""]
    }[timeoutSecs]'[wds; files];

    runnableAt:where okFlags;
    if[count runnableAt;
        / Background timeout itself (not a wrapper subshell), retain each PID,
        / then wait and write the corresponding rc file in deterministic order.
        starts:" " sv .tst.isolate.groupStart'[runnableAt;cmds runnableAt];
        waits:" " sv .tst.isolate.groupWait'[runnableAt;wds runnableAt];
        batch:"true; pids=''; cleanup(){ trap - INT TERM HUP EXIT; ",
            "if [ -n \"$pids\" ]; then for p in $pids; do kill -TERM -$p 2>/dev/null || kill -TERM $p 2>/dev/null || true; done; ",
            "sleep 1; for p in $pids; do kill -KILL -$p 2>/dev/null || kill -KILL $p 2>/dev/null || true; done; ",
            "wait $pids 2>/dev/null || true; fi; }; ",
            "trap cleanup INT TERM HUP EXIT; ",starts,
            " ",waits," trap - INT TERM HUP EXIT";
        @[system; batch; {[e] ()}];
    ];

    raze {[timeoutSecs; n; wd; file; k]
        if[0 = count wd;
            :enlist .tst.isolate.errorRow[`ISOLATED_SETUP_ERROR; file;
                "unable to create private isolation scratch"]];
        rows: .[
            .tst.isolate.interpretFile;
            (wd; file; timeoutSecs; k; n; .tst.isolate.readExitCode wd);
            {[file; err]
                enlist .tst.isolate.errorRow[`ISOLATED_HELPER_ERROR; file;
                    "isolation helper failed: ", err]
            }[file;]];
        cleaned: @[.tst.isolate.cleanupScratch; wd;
            {[file; err]
                .tst.isolate.print "ERROR: isolation scratch cleanup failed for ", file, ": ", err;
                0b
            }[file;]];
        if[not cleaned;
            rows,: enlist .tst.isolate.errorRow[
                `ISOLATED_CLEANUP_ERROR; file; "failed to remove private isolation scratch"]];
        / A q licence-startup blip is transient and retryable. Rather than
        / complicate the batch, hand that one file back to the sequential path,
        / which already owns the retry loop. This is rare enough that losing its
        / parallelism costs nothing.
        $[.tst.isolate.retryableStartupFailure rows;
            [ .tst.isolate.print "  transient q license startup failure; re-running file serially";
              .tst.isolate.runFile[file; timeoutSecs; k; n] ];
            rows]
    }[timeoutSecs; n]'[wds; files; ks]
 };

/ Effective worker count: >= 1, and never more than the number of files.
.tst.isolate.workerCount:{[fileCount]
    requested: "j"$ @[get; `.tst.app.isolateWorkers; 1];
    if[null requested; requested: 1];
    1 | requested & fileCount
 };

/ Discover, execute, merge, report, and return one granular exit code.
.tst.isolate.runAll:{[paths]
    timeoutSecs: @[get; `.tst.app.isolateTimeout; 300];
    .resq.state.results: .resq.state.emptyResults[];
    .tst.app.baseDir: system "cd";
    .tst.app.loadErrors: flip `file`error`type!(`symbol$(); (); `symbol$());
    .tst.app.executionIncompleteReason:"";
    .tst.app.canonicalRunSnapshot:()!();
    .tst.beginRunMetadata[];
    .tst.loadFlakeState[];
    .tst.loadRerunState[];
    .tst.isolate.childInventory:();
    .tst.app.snapshotDeclarations:();
    .tst.app.snapshotInventory:.tst.emptySnapshotInventory 0b;
    .tst.app.benchmarkEnvironment:()!();
    .tst.app.benchmarkAnalysis:.tst.emptyBenchmarkAnalysis 0b;

    files: .tst.selectTestFiles .tst.findTests paths;
    n: count files;
    .tst.app.discoveredFiles: files;
    .tst.isolate.upsertRows .tst.isolate.parentLoadRows[];

    unavailable: 0b;
    if[0 < n;
        unavailable: (not .tst.isolate.probeTimeout .tst.isolate.timeoutExe) or
            (0 = count .tst.isolate.qExe) or
            (0 = count .tst.isolate.mktempExe) or
            (0 = count .tst.isolate.chmodExe) or
            (0 = count .tst.isolate.rmExe) or
            (0 = count .tst.isolate.shExe);
    ];
    if[unavailable;
        msg: "Process isolation requires a working timeout with -k support and q/mktemp/chmod/rm/sh executables.";
        .tst.isolate.print "ERROR: ", msg;
        .tst.isolate.upsertRows enlist .tst.isolate.errorRow[
            `ISOLATION_UNAVAILABLE; "isolation"; msg];
    ];

    if[(not unavailable) and 0 < n;
        workers: .tst.isolate.workerCount n;
        .tst.isolate.print "Running ", string[n], " test file(s) in isolated subprocesses (timeout ",
            string[timeoutSecs], "s each",
            $[workers > 1; ", ", string[workers], " at a time"; ""], ")";
        / Fixed-size groups are also used for a one-worker run, so sequential
        / and concurrent isolation share the same interrupt/reaping boundary.
        fileGroups: workers cut files;
        kGroups: workers cut 1 + til n;
        {[timeoutSecs; n; fg; kg]
            .tst.isolate.upsertRows .tst.isolate.runGroup[fg; kg; timeoutSecs; n]
        }[timeoutSecs; n]'[fileGroups; kGroups];
    ];

    / Child manifests describe the full post-filter inventory of their file,
    / including tests a fail-fast child never reached. Normalize those durable
    / entries back to the parent inventory shape so its final manifest can
    / assign the global file/test/case topology consistently.
    childRows:.tst.eventRows .tst.isolate.childInventory;
    if[count childRows;
        .tst.app.executionInventory:{[row]
            `executionId`testId`caseId`file`suite`description`line`kind`parameters`tags`testShardKey`caseShardKey`shardable!(
                .tst.toString row`executionId;.tst.toString row`testId;
                .tst.toString row`caseId;.tst.toString row`file;
                .tst.toString row`suite;.tst.toString row`description;
                "j"$row`line;`$.tst.toString row`kind;
                $[`parameters in key row;row`parameters;()!()];
                `$string each (),$[`tags in key row;row`tags;()];
                .tst.toString row`testId;
                .tst.toString row`executionId;
                $[`shardable in key row;1b~row`shardable;1b])
        } each childRows];
    unit:@[get;`.tst.app.shardUnit;`file];
    invRows:.tst.eventRows @[get;`.tst.app.executionInventory;{()}];
    unitKeys:$[unit~`file;
        .tst.repoRelativePath each @[get;`.tst.app.allDiscoveredFiles;{()}];
        unit~`test;
          distinct .tst.toString each {x`testShardKey} each invRows;
          distinct .tst.toString each {x`caseShardKey} each invRows];
    selectedUnitKeys:$[unit~`file;
        .tst.repoRelativePath each files;
        unitKeys where @[get;`.tst.app.shardIndex;0j]=
            .tst.shardBucket[;@[get;`.tst.app.shardCount;1j]] each unitKeys];
    .tst.app.shardAllUnitCount:"j"$count unitKeys;
    .tst.app.shardSelectedUnitCount:"j"$count selectedUnitKeys;
    selectedInv:$[unit~`file;invRows;
        invRows where @[get;`.tst.app.shardIndex;0j]=
          .tst.shardBucket[;@[get;`.tst.app.shardCount;1j]] each
            {[u;x]$[u~`test;x`testShardKey;x`caseShardKey]}[unit;] each invRows];
    .tst.app.selectedExecutionIds:distinct .tst.toString each
        {x`executionId} each selectedInv;
    .tst.app.selectedTestCount:"j"$count selectedInv;

    .tst.isolate.dropChildStrict[];
    if[not `file~@[get;`.tst.app.shardUnit;`file];
        .tst.app.emptyShard:(0<count files) and 0=count .resq.state.results];
    .tst.app.expectationsRan: .tst.isolate.executedCount[];
    .tst.isolate.addGlobalStrict[];
    / Isolation children emit raw result rows. Apply evidence and quarantine
    / policy once, after all files have been merged, so the parent has one
    / denominator, one verdict, and one atomic history update.
    .tst.restoreRunPersistenceConfig[];
    .tst.applyFlakeState[];

    status: .tst.normalizeResultStatus each .resq.state.results`status;
    hasLoadError: any (.resq.state.results`suite) in `FILE_LOAD_ERROR;
    resultRows:.tst.resultRows .resq.state.results;
    anyFailure:$[count resultRows;any .tst.rowBlocksRun each resultRows;0b];
    noResults: 0 = count .resq.state.results;
    exitCode: $[hasLoadError; .resq.EXIT.LOAD_ERROR;
                (0=n) and 1b~@[get;`.tst.app.emptyShard;0b]; .resq.EXIT.PASS;
                0 = n; .resq.EXIT.NO_TESTS;
                unavailable; .resq.EXIT.FAIL;
                noResults; .resq.EXIT.FAIL;
                anyFailure; .resq.EXIT.FAIL;
                .resq.EXIT.PASS];
    .tst.app.passed: exitCode = .resq.EXIT.PASS;
    .tst.finalizeRerunSelectionMetadata count .resq.state.results;
    .tst.captureCanonicalRunSnapshot[];
    .tst.runAllPhase.runSafely[`plugins;.tst.runRegisteredPlugins];
    resultRows:.tst.resultRows .resq.state.results;
    anyFailure:$[count resultRows;any .tst.rowBlocksRun each resultRows;0b];
    / A strict plugin can turn an otherwise-green aggregate red, but must not
    / erase the more specific load/no-tests exit classification already chosen.
    if[(exitCode=.resq.EXIT.PASS) and anyFailure;
        exitCode:.resq.EXIT.FAIL;
        .tst.app.passed:0b];
    .tst.app.executionState:`completed;
    .tst.runAllPhase.runSafely[`benchmarkRegression;.tst.applyBenchmarkRegression];
    .tst.applySnapshotAudit[];
    .tst.writeSnapshotInventory[];
    if[(exitCode=.resq.EXIT.PASS) and not 1b~.tst.app.passed;
        exitCode:.resq.EXIT.FAIL];
    .tst.persistFlakeState[];
    .tst.persistRerunState[];
    .resq.report .resq.state.results;
    exitCode
 };

\d .
