/ Strip ANSI/CSI SGR color escapes (e.g. "\033[32m" ... "\033[0m") from a string
/ so junit/xunit/json reports never carry terminal control bytes. diff.q is the
/ only emitter and it always uses the CSI SGR form ESC "[" <digits/;> "m".
/ q has no regex and ssr cannot take an empty replacement, so this char-walks the
/ string. It only drops WELL-FORMED SGR sequences: on ESC, if the next char is
/ "[", it scans over "0123456789;" and requires a terminating "m" within ~16
/ chars; otherwise it drops ONLY the ESC byte and keeps the rest of the string
/ (a lone ESC or a non-SGR sequence like ESC[2J must never swallow the tail).
/ Non-string args pass through untouched.
if[not `MAX_REPORT_BYTES in key `.tst;
    .tst.MAX_REPORT_BYTES:33554432];
if[not `MAX_REPORT_ROWS in key `.tst;
    .tst.MAX_REPORT_ROWS:100000];

.tst.reportByteLimit:{[]
    .utl.hardLimit[
      .tst.MAX_REPORT_BYTES;
      33554432;
      "test report byte"]
 };

.tst.reportRowLimit:{[]
    .utl.hardLimit[
      .tst.MAX_REPORT_ROWS;
      100000;
      "test report row"]
 };

.tst.reportListLimit:{[]
    .tst.safeDiagnosticBudget[
      `.tst.output.reportListLimit;
      1000;
      1000]
 };

.tst.validateReportRowCount:{[countValue]
    if[not type[countValue] in -5 -6 -7h;
      '"Test report row count is invalid"];
    if[(null countValue) or countValue<0;
      '"Test report row count is invalid"];
    if[countValue>.tst.reportRowLimit[];
      '"Test report row limit exceeded"];
    "j"$countValue
 };

/ A line-state carries (completed chunks; bytes-on-disk; limit; current chunk).
/ Fixed-size chunks keep repeated append work bounded while the running byte
/ count rejects overflow before any whole-report concatenation.
.tst.validReportLineChunk:{[chunk]
    if[not 0h=type chunk;:0b];
    if[not count chunk;:0b];
    if[not (::)~first chunk;:0b];
    all 10h=type each 1 _ chunk
 };

.tst.validReportLineBudget:{[used;limit]
    if[not -7h=type used;:0b];
    if[not -7h=type limit;:0b];
    if[(null used) or null limit;:0b];
    if[(used<0) or limit<0;:0b];
    if[(used>limit) or limit>33554432;:0b];
    1b
 };

.tst.reportLineState:{[]
    (();0j;.tst.reportByteLimit[];enlist (::))
 };

.tst.appendReportLine:{[state;line]
    if[(not 0h=type state) or 4<>count state;
      '"Test report line state is invalid"];
    if[-10h=type line;line:enlist line];
    if[not 10h=type line;
      '"Test report line state is invalid"];
    used:state 1;
    limit:state 2;
    if[not .tst.validReportLineBudget[used;limit];
      '"Test report line state is invalid"];
    nextSize:used+1+count line;
    if[nextSize>limit;
      '"Test report byte limit exceeded"];
    chunks:state 0;
    current:state 3;
    if[not 0h=type chunks;
      '"Test report line state is invalid"];
    if[not 0h=type current;
      '"Test report line state is invalid"];
    if[257<count current;
      '"Test report line state is invalid"];
    if[not .tst.validReportLineChunk[current];
      '"Test report line state is invalid"];
    if[257=count current;
      chunks:chunks,enlist current;
      current:enlist (::)];
    current:current,enlist line;
    (chunks;nextSize;limit;current)
 };

.tst.reportLines:{[state]
    if[(not 0h=type state) or 4<>count state;
      '"Test report line state is invalid"];
    used:state 1;
    limit:state 2;
    if[not .tst.validReportLineBudget[used;limit];
      '"Test report line state is invalid"];
    chunks:state 0;
    current:state 3;
    if[not 0h=type chunks;
      '"Test report line state is invalid"];
    if[not 0h=type current;
      '"Test report line state is invalid"];
    if[257<count current;
      '"Test report line state is invalid"];
    if[not .tst.validReportLineChunk[current];
      '"Test report line state is invalid"];
    if[count chunks;
      if[not all .tst.validReportLineChunk each chunks;
        '"Test report line state is invalid"]];
    chunks:chunks,enlist current;
    combined:raze chunks;
    lines:combined where not (::)~/:combined;
    if[(not 0h=type lines) or not all 10h=type each lines;
      '"Test report line state is invalid"];
    actual:$[
      count lines;
        (sum "j"$count each lines)+count lines;
      0j];
    if[actual<>used;
      '"Test report line state is invalid"];
    lines
 };

.tst.finalizeReportLines:{[state]
    lines:.tst.reportLines state;
    $[count lines;"\n" sv lines;""]
 };

/ Resolve report paths from the run's captured base directory, not the mutable
/ process CWD. Only strings/symbols are accepted at this filesystem boundary.
.tst.reportOutputPath:{[leaf]
    if[not 10h=type leaf;
        '"Test report filename is invalid"];
    leafCodes:"i"$leaf;
    if[(not count leaf) or (leaf~".") or (leaf~"..") or
       (any leaf in "/\\") or
       (any (leafCodes<32) or leafCodes=127);
        '"Test report filename is invalid"];
    outDirRaw:@[get;`.resq.config.outDir;{"."}];
    outDirStr:.utl.pathToString outDirRaw;
    if[0=count outDirStr;outDirStr:"."];
    baseDirRaw:@[get;`.tst.app.baseDir;{""}];
    baseDirStr:.utl.pathToString baseDirRaw;
    if[0=count baseDirStr;baseDirStr:system "cd"];
    outDirStr:.utl.absolutePathForHost[
      outDirStr;
      .utl.isWindows;
      baseDirStr];
    .utl.ensureDir outDirStr;
    outDirStr,"/",leaf
 };

.tst.publishReportText:{[path;content]
    .utl.atomicTextWrite[
      path;
      content;
      .tst.reportByteLimit[];
      "Test report"]
 };

.tst.stripAnsi:{[s]
    if[not 10h = type s; :s];
    if[not any s = "\033"; :s];
    esc: "\033";
    / Seed with "" (a char vector) so an all-stripped result is "" not () - the
    / report contract is a char vector even when every byte was a colour code.
    out: "";
    i: 0; n: count s;
    while[i < n;
        $[s[i] = esc;
            [ / Try to match a well-formed SGR sequence ESC "[" <0-9;>* "m".
              j: i + 1;
              matched: 0b;
              if[(j < n) and s[j] = "[";
                  k: j + 1;
                  / Scan over parameter bytes, capped at ~16 chars past "[".
                  while[(k < n) and (k < j + 16) and s[k] in "0123456789;"; k+:1];
                  if[(k < n) and s[k] = "m"; matched: 1b; i: k + 1]
              ];
              / Not a recognised SGR run: drop ONLY the ESC byte, keep the rest.
              if[not matched; i+:1] ];
            [ out,: s[i]; i+:1 ] ] ];
    out
 };

.tst.reportTextLimit:{[]
    raw:$[
      `reportLimit in key `.tst.output;
        .tst.output.reportLimit;
      50000];
    .tst.capLimit raw
 };

/ Normalize one externally-derived report field without serializing an
/ unbounded composite. Plain text retains its natural representation; other
/ values use the bounded diagnostic renderer.
.tst.reportFieldTextWith:{[val;requested]
    cap:.tst.capLimit requested;
    if[(::)~val;:""];
    t:type val;
    text:$[
      10h=t;val;
      -10h=t;enlist val;
      -11h=t;.tst.toString val;
      .tst.renderValue[val;cap]];
    if[not 10h=type text;text:"<unrenderable report value>"];
    .tst.stripAnsi .tst.capString[text;cap]
 };

.tst.reportFieldText:{[val]
    .tst.reportFieldTextWith[
      val;
      .tst.reportTextLimit[]]
 };

/ Canonical bounded list form for JSON fields such as failures and tags. The
/ configured item limit may only lower the private ceiling. Per-item caps share
/ reportLimit across retained items, so a 1000-element list cannot allocate
/ 1000 full-size diagnostic strings.
.tst.sanitizeReportList:{[val]
    if[(::)~val;:()];
    t:type val;
    if[(10h=t) and 0=count val;:()];
    itemLimit:.tst.reportListLimit[];
    if[0=itemLimit;:()];
    rawCount:$[
      10h=t;1;
      t in 0 1 2 4 5 6 7 8 9 11 12 13 14 15 16 17 18 19h;
        count val;
      1];
    if[0=rawCount;:()];
    textLimit:.tst.reportTextLimit[];
    if[0=textLimit;:()];
    takeN:itemLimit & rawCount & textLimit;
    items:$[
      10h=t;enlist val;
      0h=t;takeN sublist val;
      t within 1 19h;takeN sublist val;
      enlist val];
    itemCap:1 | textLimit div takeN;
    / Seed explicit generic slots so multiple one-character strings cannot
    / collapse into one char vector and lose their item boundaries.
    rendered:(1+takeN)#enlist (::);
    itemIndex:0;
    while[itemIndex<takeN;
      rendered[1+itemIndex]:
        .tst.reportFieldTextWith[
          items itemIndex;
          itemCap];
      itemIndex+:1];
    rendered:1 _ rendered;
    omitted:rawCount-takeN;
    if[omitted and count rendered;
      rendered[count[rendered]-1]:
        .tst.capString[
          "... [truncated ",string[omitted]," items]";
          itemCap]];
    rendered
 };

.tst.sanitizeToList:{[x]
    $[0h = type x; x;
      98h = type x; {[tbl; idx] tbl idx}[x] each til count x;
      99h = type x; enlist x;
      enlist x]
 };

.tst.sanitizeExpectations:{[x]
    if[(type[x] in 0 98h) and
       count[x]>.tst.reportRowLimit[];
      '"Test report row limit exceeded"];
    rows: .tst.sanitizeToList x;
    rows: rows where not (::)~/: rows;
    .tst.validateReportRowCount count rows;
    $[0 = count rows; (); rows]
 };

/ Render a failures/error field into a single plain char vector suitable for a
/ report message. Retained list items use the bounded diagnostic renderer and
/ join with "\n"; the complete message is then capped at reportLimit. No q
/ literal artifacts (no leading `,"` from -3! on a 1-element list), no
/ show-style truncation.
/ Empty/`(::)` inputs collapse to "".
.tst.renderReportMessage:{[val]
    limit:.tst.reportTextLimit[];
    items:.tst.sanitizeReportList val;
    text:$[count items;"\n" sv items;""];
    .tst.capString[text;limit]
 };

.tst.reportTimeValue:{[raw]
    candidate:$[
      -16h=type raw;
        raw;
      (16h=type raw) and 1=count raw;
        first raw;
      0Nn];
    if[candidate in (0Wn;-0Wn);:0Nn];
    candidate
 };

.tst.sanitizeExpectationFromFields:{[suite; file; ns; tags; ex]
    if[not 99h = type ex;
        :`suite`description`status`message`time`failures`assertsRun`file`namespace`tags!(
            suite;
            "Unavailable expectation";
            `error;
            "";
            0Nn;
            ();
            0;
            file;
            ns;
            tags)];

    exDesc:     $[
      `desc in key ex;
        .tst.reportFieldText ex`desc;
      "Unnamed expectation"];
    exResult:   .tst.normalizeResultStatus $[`result in key ex; ex`result; `pass];
    rawFailures:$[`failures in key ex; ex`failures; ()];
    exErr:      $[`errorText in key ex; ex`errorText; ()];
    rawTime: $[`time in key ex; ex`time; 0Nn];
    exTime:.tst.reportTimeValue rawTime;
    rawAsserts:$[`assertsRun in key ex;ex`assertsRun;0i];
    exAsserts:$[
      (type rawAsserts) in -5 -6 -7h;
        $[
          (null rawAsserts) or
          rawAsserts in (0Wh;-0Wh;0Wi;-0Wi;0W;-0W) or
          rawAsserts<0;
            0j;
          "j"$rawAsserts];
      0j];
    / Render failure/error fields into a single plain char vector. A LIST of
    / strings must join with "\n" (NOT .tst.toString, which emits the q literal
    / form: a 1-element list comes out as `,"..."`). Single strings pass through;
    / non-string elements use the bounded renderer. The joined string is then
    / length-capped once by the shared string cap.
    exMsg: $[
      (not (::)~rawFailures) and 0<count rawFailures;
        .tst.renderReportMessage rawFailures;
      (not (::)~exErr) and 0<count exErr;
        .tst.renderReportMessage exErr;
                  ""];

    / Strip terminal color escapes so file reporters (junit/xunit/json) never
    / carry \033 control bytes. diff colour only ever reaches stdout, but a
    / failure string could still pick one up, so this is defence in depth.
    exMsg: .tst.stripAnsi exMsg;
    exFailures:.tst.sanitizeReportList rawFailures;

    `suite`description`status`message`time`failures`assertsRun`file`namespace`tags!(
        suite;
        exDesc;
        exResult;
        exMsg;
        exTime;
        exFailures;
        exAsserts;
        file;
        ns;
        tags)
 };

.tst.sanitizeExpectation:{[suite; file; ns; tags; ex]
    .tst.sanitizeExpectationFromFields[
      .tst.reportFieldText suite;
      .tst.reportFieldText file;
      .tst.reportFieldText ns;
      .tst.sanitizeReportList tags;
      ex]
 };

.tst.sanitizeSpec:{[spec]
    if[not 99h=type spec;
      :enlist .tst.sanitizeExpectation[
        "Unavailable suite";
        "";
        "";
        ();
        ::]];
    suite: $[
      `title in key spec;
        .tst.reportFieldText spec`title;
      "Unnamed suite"];
    file:  $[
      `tstPath in key spec;
        .tst.reportFieldText spec`tstPath;
      ""];
    ns:    $[
      `namespace in key spec;
        .tst.reportFieldText spec`namespace;
      ""];
    tags:  $[`tags in key spec; .tst.sanitizeReportList spec`tags; ()];
    exs:   $[`expectations in key spec; .tst.sanitizeExpectations spec`expectations; ()];

    if[0 = count exs;
        :enlist `suite`description`status`message`time`failures`assertsRun`file`namespace`tags!(
            suite;
            "No expectations";
            .tst.normalizeResultStatus $[`result in key spec; spec`result; `pass];
            "";
            0Nn;
            ();
            0i;
            file;
            ns;
            tags)
    ];
    .tst.sanitizeExpectationFromFields[
      suite;
      file;
      ns;
      tags;] each exs
 };

.tst.isResultRow:{[x]
    if[not 99h = type x; :0b];
    all `suite`description`status in key x
 };

/ Count the rows an input will expand to before rendering any of its values.
/ An empty/missing expectation collection becomes one pending result row.
.tst.reportSpecRowCount:{[item;rowLimit]
    if[.tst.isResultRow item;:1j];
    if[not 99h=type item;:1j];
    if[not `expectations in key item;:1j];
    raw:item`expectations;
    rawType:type raw;
    if[98h=rawType;
      if[count[raw]>rowLimit;
        '"Test report row limit exceeded"];
      :1j | "j"$count raw];
    if[0h=rawType;
      if[count[raw]>rowLimit;
        '"Test report row limit exceeded"];
      nonNull:sum not (::)~/:raw;
      :1j | "j"$nonNull];
    1j
 };

.tst.sanitizeResultRow:{[row]
    suite:$[`suite in key row;row`suite;"Unnamed suite"];
    file:$[`file in key row;row`file;""];
    ns:$[`namespace in key row;row`namespace;""];
    tags:$[`tags in key row;row`tags;()];
    ex:
      `desc`result`time`failures`errorText`assertsRun!(
        $[`description in key row;row`description;"Unnamed expectation"];
        $[`status in key row;row`status;`error];
        $[`time in key row;row`time;0Nn];
        $[`failures in key row;row`failures;()];
        $[`message in key row;row`message;""];
        $[`assertsRun in key row;row`assertsRun;0i]);
    normalized:.tst.sanitizeExpectation[
      suite;
      file;
      ns;
      tags;
      ex];
    if[`message in key row;
      normalized[`message]:
        .tst.renderReportMessage row`message];
    normalized
 };

.tst.sanitize:{[specs]
    rowLimit:.tst.reportRowLimit[];
    if[(98h=type specs) and count[specs]>rowLimit;
      '"Test report row limit exceeded"];
    if[0h = type specs;
        if[count[specs]>rowLimit;
          '"Test report row limit exceeded"];
        specs: specs where not (::)~/: specs;
        if[0 = count specs; :()];
    ];
    specs: .tst.sanitizeToList specs;
    if[not count specs; :()];
    specs: specs where not (::)~/: specs;
    if[not count specs; :()];
    if[count[specs]>rowLimit;
      '"Test report row limit exceeded"];
    / Admit the total expansion before rendering the first value. Without this
    / preflight, a later spec could temporarily allocate another full ceiling
    / of rows before the aggregate limit was noticed.
    admitted:0j;
    preflightIndex:0;
    while[preflightIndex<count specs;
      expanded:.tst.reportSpecRowCount[
        specs preflightIndex;
        rowLimit];
      if[expanded>rowLimit-admitted;
        '"Test report row limit exceeded"];
      admitted+:expanded;
      preflightIndex+:1];
    / One fragment slot per admitted input avoids repeated list growth for a
    / large collection of specs while still allowing each spec to expand to
    / multiple expectation rows.
    fragments:(count specs)#enlist (::);
    total:0j;
    index:0;
    while[index<count specs;
      current:$[
        .tst.isResultRow specs index;
          enlist .tst.sanitizeResultRow specs index;
        .tst.sanitizeSpec specs index];
      total+:count current;
      if[total>rowLimit;
        '"Test report row limit exceeded"];
      fragments[index]:current;
      index+:1];
    if[total<>admitted;
      '"Test report row admission invariant failed"];
    raze fragments
 };

.tst.emptyResultTable:{[]
    flip `suite`description`status`message`time`failures`assertsRun`file`namespace`tags!(
        ();
        ();
        `symbol$();
        ();
        `timespan$();
        ();
        `int$();
        ();
        ();
        ())
 };

/ Canonical reporter boundary.
/ accepts: spec objects, expectation rows, flat result tables, or row dictionaries
/ returns: list of result-row dictionaries
.tst.resultRows:{[results]
    rows: $[`sanitize in key `.tst; .tst.sanitize results; results];
    rows:$[0h = type rows; rows;
      98h = type rows; {[tbl; idx] tbl idx}[rows] each til count rows;
      99h = type rows; enlist rows;
      enlist rows];
    .tst.validateReportRowCount count rows;
    rows
 };

/ Assemble already-admitted rows without re-running the sanitizer. Reporters
/ use this after resultRows so custom values are normalized exactly once.
.tst.resultTableFromRows:{[rows]
    if[98h=type rows;
      .tst.validateReportRowCount count rows;
      :rows];
    if[99h=type rows;rows:enlist rows];
    if[not 0h=type rows;
      '"Test report rows are invalid"];
    .tst.validateReportRowCount count rows;
    if[count rows and not all 99h=type each rows;
      '"Test report rows are invalid"];
    if[0 = count rows; :.tst.emptyResultTable[]];
    flip flip rows
 };

.tst.resultTable:{[results]
    .tst.resultTableFromRows .tst.resultRows results
 };

.tst.resultSummaryFromTable:{[t]
    if[not 98h=type t;
      '"Test report table is invalid"];
    / `symbol$ keeps the empty case a TYPED empty vector: an empty GENERIC
    / list here makes the sums below return () instead of 0, which crashes
    / consumers that cond on the counts (e.g. the text reporter's color path).
    statusNorm: `symbol$ .tst.normalizeResultStatus each t`status;
    `suiteCount`testCount`passCount`failCount`errorCount`skipCount`duration`assertsRun!(
        count distinct t`suite;
        count t;
        sum statusNorm = `pass;
        sum statusNorm = `fail;
        sum statusNorm = `error;
        sum (statusNorm in `skip`pending);
        sum t`time;
        sum t`assertsRun)
 };

.tst.resultSummary:{[results]
    .tst.resultSummaryFromTable .tst.resultTable results
 };
