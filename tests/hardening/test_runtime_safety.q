/ Focused regressions for literal ceilings, non-reusable deferred state, bounded
/ callback diagnostics, and direct benchmark entry-point validation.

.tst.testState.runtimeCapture:{[fn]
  (1b;enlist fn[])
 };

.tst.testState.runtimeCaptureError:{[err]
  (0b;enlist err)
 };

.tst.testState.raiseHeartbeat:{[]
  '"heartbeat boom"
 };

.tst.testState.foreignDeferredGuid:{[]
  epochText:string .tst.deferredEpoch;
  firstChar:$["0"=first epochText;"1";"0"];
  "G"$firstChar,1_epochText
 };

.tst.testState.reloadPromise:{[]
  system "l ",.resq.HOME,"/lib/promise.q"
 };

/ Compare q's deterministic RNG output in fresh processes. Each child has its
/ own outer timeout, closed stdin, and a PID-scoped output path.
.tst.testState.promiseRngProbe:{[loadPromise]
  qFound:@[system;"command -v q 2>/dev/null";{()}];
  timeoutFound:@[system;"command -v timeout 2>/dev/null";{()}];
  if[(not count qFound) or (not count timeoutFound); :()];
  suffix:$[loadPromise;"loaded";"baseline"];
  base:"/tmp/resq_runtime_rng_",string[.z.i],"_",suffix;
  scriptPath:base,".q";
  outputPath:base,".out";
  {[path] @[hdel;hsym `$path;{}]} each (scriptPath;outputPath);
  script:(
    ".D.args:.z.x;";
    "system \"S 314159\";";
    "if[2=count .D.args;system \"l \",last .D.args];";
    ".D.sample:32?1000000;";
    "(hsym `$first .D.args) 0: enlist -3!.D.sample;";
    "exit 0;");
  (hsym `$scriptPath) 0:script;
  command:
    .utl.shellQuote[first timeoutFound],
    " -k 2s 15s ",
    .utl.shellQuote[first qFound]," ",
    .utl.shellQuote[scriptPath]," ",
    .utl.shellQuote[outputPath],
    $[
      loadPromise;
      " ",.utl.shellQuote[.resq.HOME,"/lib/promise.q"];
      ""],
    " -q < /dev/null > /dev/null 2>&1";
  spawnOk:@[
    {[cmd] system cmd;1b};
    command;
    {[err] 0b}];
  attempts:0;
  lines:();
  while[
      (attempts<200) and
      (not count lines:@[read0;hsym `$outputPath;{()}]);
    system "sleep 0.005";
    attempts+:1];
  {[path] @[hdel;hsym `$path;{}]} each (scriptPath;outputPath);
  if[not spawnOk;
    '"fresh q RNG probe failed to start"];
  if[not count lines;
    '"fresh q RNG probe produced no output"];
  first lines
 };

.tst.testState.withRuntimeGlobals:{[paths;replacements;body]
  originals:{get x} each paths;
  {[path;replacement] path set replacement}'[paths;replacements];
  outcome:@[
    .tst.testState.runtimeCapture;
    body;
    .tst.testState.runtimeCaptureError];
  {[path;original] path set original}'[paths;originals];
  if[not first outcome; 'first last outcome];
  first last outcome
 };

.tst.testState.withRuntimeEnv:{[name;replacement;body]
  original:getenv name;
  setenv[name;replacement];
  outcome:@[
    .tst.testState.runtimeCapture;
    body;
    .tst.testState.runtimeCaptureError];
  setenv[name;original];
  if[not first outcome; 'first last outcome];
  first last outcome
 };

.tst.testState.withRuntimeEnvs:{[names;replacements;body]
  originals:getenv each names;
  {[name;replacement] setenv[name;replacement]}'[names;replacements];
  outcome:@[
    .tst.testState.runtimeCapture;
    body;
    .tst.testState.runtimeCaptureError];
  {[name;original] setenv[name;original]}'[names;originals];
  if[not first outcome; 'first last outcome];
  first last outcome
 };

.tst.testState.capMutationOutcome:{[
    namespace;
    leaf;
    path;
    replacement;
    missing;
    accessorPath]
  original:get path;
  if[missing; ![namespace;();0b;enlist leaf]];
  if[not missing; path set replacement];
  outcome:@[
    {[fnPath]
      fn:get fnPath;
      (1b;enlist fn[])
    };
    accessorPath;
    .tst.testState.runtimeCaptureError];
  path set original;
  outcome
 };

.tst.testState.assertRejectedCapMutation:{[spec;replacement;missing]
  outcome:.tst.testState.capMutationOutcome[
    spec`ns;
    spec`leaf;
    spec`path;
    replacement;
    missing;
    spec`accessor];
  must[
    not first outcome;
    "missing, corrupt, or raised safety seams must fail closed"];
  if[not first outcome;
    must[
      4096>=count first last outcome;
      "safety-seam diagnostics must remain bounded"]];
  (::)
 };

.tst.testState.assertCapSpec:{[spec]
  .tst.testState.assertRejectedCapMutation[spec;1b;0b];
  .tst.testState.assertRejectedCapMutation[spec;spec`raised;0b];
  .tst.testState.assertRejectedCapMutation[spec;(::);1b];
  (::)
 };

.tst.testState.runtimeCapSpecs:([]
  ns:
    (3#`.tst),
    (8#`.tst),
    (11#`.tst.benchmark);
  leaf:
    `ASYNC_MAX_MILLIS`ASYNC_MAX_ATTEMPTS`ASYNC_MAX_ERROR_CHARS,
    `MAX_ACTIVE_DEFERREDS`MAX_REJECTION_CHARS`MAX_REJECTION_ITEMS,
    `MAX_REJECTION_NODES`MAX_CALLBACK_NAMES`MAX_CALLBACK_CALLS,
    `MAX_CALLBACK_VALUE_ITEMS`MAX_CALLBACK_TEXT_CHARS,
    `MAX_ITERATIONS`MAX_WARMUP`MAX_BUCKETS`MAX_DATA_POINTS,
    `MAX_OPTION_KEYS`MAX_OPTION_KEY_DISPLAY`MEASURE_WARMUP,
    `MAX_PRINT_ROWS`MAX_DISPLAY_WIDTH`MAX_NAME_LENGTH`MAX_FINITE_RATIO;
  path:
    `.tst.ASYNC_MAX_MILLIS,
    `.tst.ASYNC_MAX_ATTEMPTS,
    `.tst.ASYNC_MAX_ERROR_CHARS,
    `.tst.MAX_ACTIVE_DEFERREDS,
    `.tst.MAX_REJECTION_CHARS,
    `.tst.MAX_REJECTION_ITEMS,
    `.tst.MAX_REJECTION_NODES,
    `.tst.MAX_CALLBACK_NAMES,
    `.tst.MAX_CALLBACK_CALLS,
    `.tst.MAX_CALLBACK_VALUE_ITEMS,
    `.tst.MAX_CALLBACK_TEXT_CHARS,
    `.tst.benchmark.MAX_ITERATIONS,
    `.tst.benchmark.MAX_WARMUP,
    `.tst.benchmark.MAX_BUCKETS,
    `.tst.benchmark.MAX_DATA_POINTS,
    `.tst.benchmark.MAX_OPTION_KEYS,
    `.tst.benchmark.MAX_OPTION_KEY_DISPLAY,
    `.tst.benchmark.MEASURE_WARMUP,
    `.tst.benchmark.MAX_PRINT_ROWS,
    `.tst.benchmark.MAX_DISPLAY_WIDTH,
    `.tst.benchmark.MAX_NAME_LENGTH,
    `.tst.benchmark.MAX_FINITE_RATIO;
  raised:(
    3600001;
    10001;
    4097;
    1025;
    4097;
    129;
    1025;
    65;
    257;
    65;
    513;
    1000001;
    100001;
    10001;
    1000001;
    33;
    65;
    100001;
    257;
    257;
    257;
    1000000000001f);
  accessor:
    `.tst._asyncMillisLimit,
    `.tst._asyncAttemptLimit,
    `.tst._asyncErrorLimit,
    `.tst._activeDeferredLimit,
    `.tst._rejectionTextLimit,
    `.tst._rejectionItemLimit,
    `.tst._rejectionNodeLimit,
    `.tst._callbackNameLimit,
    `.tst._callbackCallLimit,
    `.tst._callbackItemLimit,
    `.tst._callbackTextLimit,
    `.tst.benchmark.iterationLimit,
    `.tst.benchmark.warmupLimit,
    `.tst.benchmark.bucketLimit,
    `.tst.benchmark.dataPointLimit,
    `.tst.benchmark.optionKeyLimit,
    `.tst.benchmark.optionDisplayLimit,
    `.tst.benchmark.measureWarmup,
    `.tst.benchmark.printRowLimit,
    `.tst.benchmark.displayWidthLimit,
    `.tst.benchmark.nameLimit,
    `.tst.benchmark.ratioLimit);

.tst.desc["runtime safety seams"]{
  should["treat every mutable runtime cap as a lowerable seam"]{
    .tst.testState.assertCapSpec each
      .tst.testState.runtimeCapSpecs;
  };

  should["reject async validation before invoking user conditions"]{
    .tst.testState.runtimeProbe:0;
    paths:
      `.tst.ASYNC_MAX_MILLIS,
      `.tst.ASYNC_MAX_ATTEMPTS,
      `.tst.ASYNC_MAX_ERROR_CHARS;
    replacements:(10;2;32);
    body:{
      mustthrow[
        "*duration safety limit*";
        (.tst.wait;
          {.tst.testState.runtimeProbe+:1;1b};
          11;
          1)];
      mustthrow[
        "*heartbeat must be a boolean scalar*";
        (.tst.waitEx;
          {.tst.testState.runtimeProbe+:1;1b};
          1;
          1;
          1)];
      .tst.testState.runtimeProbe musteq 0;

      mustthrow[
        "*must return boolean or integer 0/1*";
        (.tst.wait;{2};5;0)];
      mustthrow[
        "*must return boolean or integer 0/1*";
        (.tst.eventually;{2};5;0)];
      mustthrow[
        "*attempt safety limit*";
        (.tst.eventually;{'"not ready"};10;0)];
      (::)
    };
    .tst.testState.withRuntimeGlobals[paths;replacements;body];
    ![`.tst.testState;();0b;enlist `runtimeProbe];
  };

  should["accept compatible niladic lambdas and reject wrong arity"]{
    .tst.wait[{1b};1;0] musteq 1b;
    .tst.wait[{"i"$1};1;0] musteq 1b;
    mustthrow[
      "*must accept 0 argument*";
      (.tst.wait;{[left;right] left~right};1;0)];
    mustthrow[
      "*must accept 0 argument*";
      (.tst.wait;+;1;0)];
    mustthrow[
      "*must accept 0 argument*";
      (.tst.wait;neg;1;0)];
  };

  should["surface a bounded heartbeat failure exactly once"]{
    .tst.testState.runtimeProbe:0;
    body:{
      mustthrow[
        "*heartbeat failed: heartbeat boom*";
        (.tst.waitEx;
          {.tst.testState.runtimeProbe+:1;0b};
          20;
          0;
          1b)];
      .tst.testState.runtimeProbe musteq 1;
      (::)
    };
    .tst.testState.withRuntimeGlobals[
      enlist `.tst._heartbeat;
      enlist .tst.testState.raiseHeartbeat;
      body];
    ![`.tst.testState;();0b;enlist `runtimeProbe];
  };

  should["build Windows sleep commands from an attested absolute executable"]{
    executable:
      "C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe";
    .tst.mock[
      `.utl.isFile;
      {[expected;candidate] candidate~expected}[executable;]];
    body:{
      trustedPath:
        "C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe";
      resolved:.tst._windowsPowerShellPath[];
      resolved mustmatch trustedPath;
      command:.tst._windowsSleepCommand[resolved;7];
      prefix:"\"",trustedPath,"\" ";
      (count[prefix]#command) mustmatch prefix;
      mustthrow[
        "*trusted PowerShell path is invalid*";
        (.tst._windowsSleepCommand;
          "Z:/attacker/powershell.exe";
          7)];
      mustthrow[
        "*literal millisecond ceiling*";
        (.tst._windowsSleepCommand;resolved;3600001)];
      (::)
    };
    .tst.testState.withRuntimeEnvs[
      `SystemRoot`PATH;
      ("Z:\\attacker";"Z:\\attacker-bin");
      body];
  };

};

.tst.desc["deferred state safety"]{
  should["preserve the caller RNG stream during fresh promise initialization"]{
    qAvailable:0<count @[system;"command -v q 2>/dev/null";{()}];
    timeoutAvailable:
      0<count @[system;"command -v timeout 2>/dev/null";{()}];
    if[qAvailable and timeoutAvailable;
      baseline:.tst.testState.promiseRngProbe 0b;
      loaded:.tst.testState.promiseRngProbe 1b;
      loaded mustmatch baseline];
    if[not (qAvailable and timeoutAvailable);
      must[1b;"fresh-process q probe is unavailable"]];
  };

  should["preserve validated live deferred state across module reload"]{
    paths:
      `.tst.deferredStates,
      `.tst.deferredCounter,
      `.tst.deferredEpoch;
    replacements:(()!();1;.tst.deferredEpoch);
    body:{
      id:.tst.deferred[];
      beforeEpoch:.tst.deferredEpoch;
      beforeCounter:.tst.deferredCounter;
      beforeState:.tst.getState id;
      .tst.testState.reloadPromise[];
      .tst.deferredEpoch mustmatch beforeEpoch;
      .tst.deferredCounter musteq beforeCounter;
      .tst.getState[id] mustmatch beforeState;
      .tst.resolve[id;42];
      .tst.await[id;10] musteq 42;
      0 musteq count .tst.deferredStates;
      (::)
    };
    .tst.testState.withRuntimeGlobals[paths;replacements;body];
  };

  should["fail reload closed without replacing partial or corrupt state"]{
    paths:
      `.tst.deferredStates,
      `.tst.deferredCounter,
      `.tst.deferredEpoch,
      `.tst.callbackLogs;
    replacements:(()!();1;.tst.deferredEpoch;()!());
    body:{
      epochBefore:.tst.deferredEpoch;
      storeBefore:.tst.deferredStates;
      logsBefore:.tst.callbackLogs;
      .tst.deferredCounter::"corrupt";
      mustthrow[
        "*Deferred counter is corrupt*";
        .tst.testState.reloadPromise];
      .tst.deferredEpoch mustmatch epochBefore;
      .tst.deferredStates mustmatch storeBefore;
      .tst.deferredCounter mustmatch "corrupt";
      .tst.callbackLogs mustmatch logsBefore;

      .tst.deferredCounter::1;
      ![`.tst;();0b;enlist `deferredCounter];
      mustthrow[
        "*initialization is incomplete*";
        .tst.testState.reloadPromise];
      .tst.deferredEpoch mustmatch epochBefore;
      .tst.deferredStates mustmatch storeBefore;
      must[not `deferredCounter in key `.tst;
        "partial reload failure must not recreate the missing field"];
      .tst.callbackLogs mustmatch logsBefore;
      (::)
    };
    .tst.testState.withRuntimeGlobals[paths;replacements;body];
  };

  should["issue bounded non-reusable GUID handles without symbol growth"]{
    paths:
      `.tst.deferredStates,
      `.tst.deferredCounter,
      `.tst.deferredEpoch,
      `.tst.MAX_ACTIVE_DEFERREDS;
    replacements:(()!();1;.tst.deferredEpoch;3);
    body:{
      ids:{[ignored] .tst.deferred[]} each til 3;
      count[distinct ids] musteq 3;
      all[-2h=type each ids] musteq 1b;
      mustthrow["*capacity exhausted*";.tst.deferred];
      stale:first ids;
      .tst._forgetDeferred stale;
      replacement:.tst.deferred[];
      must[not replacement~stale;
        "a released deferred handle must not be reused"];
      {.tst._forgetDeferred x} each key .tst.deferredStates;
      symbolsBeforeCycle:.Q.w[]`syms;
      cycled:{
        id:.tst.deferred[];
        .tst._forgetDeferred id;
        id
      } each til 4096;
      symbolsAfterCycle:.Q.w[]`syms;
      count[distinct cycled] musteq 4096;
      must[not stale in cycled;
        "stale handles must remain absent under sustained churn"];
      symbolsAfterCycle musteq symbolsBeforeCycle;
      0 musteq count .tst.deferredStates;
      mustthrow["*Unknown deferred*";(.tst.getState;stale)];
      (::)
    };
    .tst.testState.withRuntimeGlobals[paths;replacements;body];
  };

  should["fail closed on generation epoch and exact state corruption"]{
    paths:
      `.tst.deferredStates,
      `.tst.deferredCounter,
      `.tst.deferredEpoch,
      `.tst.MAX_ACTIVE_DEFERREDS;
    replacements:(()!();1;.tst.deferredEpoch;4);
    body:{
      mustthrow[
        "*encoding requires a long scalar*";
        (.tst._deferredCounterHex;65536#1j)];
      {
        previous:.tst.deferredCounter;
        .tst.deferredCounter::x;
        mustthrow["*Deferred counter*";.tst.deferred];
        0 musteq count .tst.deferredStates;
        .tst.deferredCounter::previous
      } each (-1;0;0N;0W;1b;9223372036854775806);

      {
        previous:.tst.deferredEpoch;
        .tst.deferredEpoch::x;
        mustthrow["*Deferred GUID epoch*";.tst.deferred];
        0 musteq count .tst.deferredStates;
        .tst.deferredEpoch::previous
      } each (0Ng;42;"bad epoch");

      id:.tst.deferred[];
      .tst.deferredStates[id]:42;
      mustthrow["*Deferred state registry*";(.tst.await;id;1)];
      must[not id in key .tst.deferredStates;
        "await must clean an identifiable deferred after state corruption"];

      id:.tst.deferred[];
      pendingState:([] state:enlist `pending;
        val:enlist (::);
        err:enlist (::));
      .tst.deferredStates[id;`val]:enlist 42;
      mustthrow[
        "*invalid state*";
        (.tst.await;id;1)];
      must[not id in key .tst.deferredStates;
        "await must clean state that violates the exact pending schema"];

      oversizedIds:1025#enlist id;
      .tst.deferredStates::(
        oversizedIds!1025#enlist pendingState);
      mustthrow[
        "*literal ceiling*";
        (.tst.await;id;1)];
      count[.tst.deferredStates] musteq 1025;

      foreign:.tst.testState.foreignDeferredGuid[];
      .tst.deferredStates::(
        (enlist foreign)!enlist pendingState);
      mustthrow["*invalid GUID epoch*";.tst.deferred];
      count[.tst.deferredStates] musteq 1;

      .tst.deferredStates::(
        (enlist `notAGuid)!enlist pendingState);
      mustthrow["*registry keys are corrupt*";.tst.deferred];
      count[.tst.deferredStates] musteq 1;
      (::)
    };
    .tst.testState.withRuntimeGlobals[paths;replacements;body];
  };

  should["preserve Unknown deferred and clean every valid await exit"]{
    mustthrow["*Unknown deferred*";(.tst.await;`definitelyUnknown;1)];
    paths:
      `.tst.deferredStates,
      `.tst.deferredCounter,
      `.tst.deferredEpoch,
      `.tst.MAX_ACTIVE_DEFERREDS;
    replacements:(()!();1;.tst.deferredEpoch;4);
    body:{
      foreign:.tst.testState.foreignDeferredGuid[];
      mustthrow["*Unknown deferred*";(.tst.getState;foreign)];
      0 musteq count .tst.deferredStates;

      id:.tst.deferred[];
      mustthrow[
        "*finite non-negative numeric scalar*";
        (.tst.await;id;0N)];
      must[not id in key .tst.deferredStates;
        "await validation failures must release valid deferred IDs"];

      id:.tst.deferred[];
      mustthrow["*timed out*";(.tst.await;id;1)];
      must[not id in key .tst.deferredStates;
        "await timeouts must release valid deferred IDs"];
      (::)
    };
    .tst.testState.withRuntimeGlobals[paths;replacements;body];
  };

  should["retain small rejection values and bound hostile diagnostics"]{
    paths:
      `.tst.deferredStates,
      `.tst.deferredCounter,
      `.tst.deferredEpoch,
      `.tst.MAX_ACTIVE_DEFERREDS,
      `.tst.MAX_REJECTION_CHARS,
      `.tst.MAX_REJECTION_ITEMS,
      `.tst.MAX_REJECTION_NODES;
    replacements:(()!();1;.tst.deferredEpoch;8;32;2;16);
    body:{
      small:`code`retry!(503;1b);
      id:.tst.deferred[];
      .tst.reject[id;small];
      state:.tst.getState id;
      state[`err] mustmatch small;
      mustthrow[
        "*rejected value type 99 count 2*";
        (.tst.await;id;10)];
      must[not id in key .tst.deferredStates;
        "dictionary rejection must release deferred state"];

      id:.tst.deferred[];
      .tst.reject[id;42];
      state:.tst.getState id;
      state[`err] musteq 42;
      mustthrow["*42*";(.tst.await;id;10)];
      must[not id in key .tst.deferredStates;
        "numeric rejection must release deferred state"];

      id:.tst.deferred[];
      .tst.reject[id;1 2];
      state:.tst.getState id;
      state[`err] mustmatch 1 2;
      mustthrow[
        "*rejected value type 7 count 2*";
        (.tst.await;id;10)];
      must[not id in key .tst.deferredStates;
        "list rejection must release deferred state"];

      id:.tst.deferred[];
      .tst.reject[id;til 3];
      state:.tst.getState id;
      (10h) musteq type state`err;
      must[count[state`err]<=32;
        "bounded rejection details must honor their text cap"];
      mustthrow["*rejected value type*";(.tst.await;id;10)];
      must[not id in key .tst.deferredStates;
        "bounded composite rejection must release deferred state"];

      id:.tst.deferred[];
      .tst.reject[id;100#"x"];
      count[.tst.getState[id]`err] musteq 32;
      mustthrow["*xxxxxxxx*";(.tst.await;id;10)];

      hugeSymbol:`$65536#"s";
      id:.tst.deferred[];
      .tst.reject[id;hugeSymbol];
      mustthrow[
        "*rejected symbol value*";
        (.tst.await;id;10)];
      (::)
    };
    .tst.testState.withRuntimeGlobals[paths;replacements;body];
  };
};

.tst.desc["callback spy safety"]{
  should["preserve validated callback diagnostics across module reload"]{
    body:{
      spy:.tst.callbackSpy `reloadProbe;
      spy 42;
      callsBefore:.tst.getCallbackCalls `reloadProbe;
      .tst.testState.reloadPromise[];
      .tst.getCallbackCalls[`reloadProbe] mustmatch callsBefore;
      spy 43;
      2 musteq count .tst.getCallbackCalls `reloadProbe;
      (::)
    };
    .tst.testState.withRuntimeGlobals[
      enlist `.tst.callbackLogs;
      enlist (()!());
      body];
  };

  should["saturate deterministically while preserving passthrough"]{
    paths:
      `.tst.callbackLogs,
      `.tst.MAX_CALLBACK_NAMES,
      `.tst.MAX_CALLBACK_CALLS,
      `.tst.MAX_CALLBACK_VALUE_ITEMS,
      `.tst.MAX_CALLBACK_TEXT_CHARS;
    replacements:(()!();2;2;2;32);
    body:{
      cb:.tst.callbackSpy `boundedCallback;
      cb[1 2 3] mustmatch 1 2 3;
      retainedCalls:.tst.getCallbackCalls `boundedCallback;
      (10h) musteq type last[first retainedCalls];
      last[first retainedCalls] mustlike "*callback value type 7 count 3*";
      cb[3 4] mustmatch 3 4;
      cb[5 6] mustmatch 5 6;
      {[spy;argument] spy argument}[cb;] each 10+til 20;
      calls:.tst.getCallbackCalls `boundedCallback;
      count[calls] musteq 2;
      (enlist[`callbackLogSaturated]!enlist 1b)
        mustmatch last[calls]1;

      second:.tst.callbackSpy `secondCallback;
      second[1];
      mustthrow[
        "*name capacity exhausted*";
        (.tst.callbackSpy;`thirdCallback)];
      (::)
    };
    .tst.testState.withRuntimeGlobals[paths;replacements;body];
  };

  should["reject corrupt retained payloads and clear poisoned state"]{
    paths:
      `.tst.callbackLogs,
      `.tst.MAX_CALLBACK_CALLS;
    replacements:(()!();2);
    body:{
      hugeName:`$65536#"c";
      logs:()!();
      logs[hugeName]:enlist (.z.p;1000#0);
      .tst.callbackLogs::logs;
      mustthrow[
        "*Callback call log is corrupt*";
        (.tst.getCallbackCalls;hugeName)];
      .tst.MAX_CALLBACK_CALLS::0N;
      .tst.clearCallbackLogs[];
      0 musteq count .tst.callbackLogs;
      (::)
    };
    .tst.testState.withRuntimeGlobals[paths;replacements;body];
  };
};

.tst.desc["benchmark runtime safety"]{
  should["reject poisoned defaults and direct runBench calls before user code"]{
    .tst.testState.runtimeProbe:0;
    paths:
      `.tst.benchDefaults,
      `.tst.benchmark.MAX_ITERATIONS,
      `.tst.benchmark.MAX_DATA_POINTS,
      `.tst.benchmark.MAX_BUCKETS;
    replacements:(
      `iterations`warmup`gcBefore!(3;0;0b);
      2;
      2;
      10);
    body:{
      callable:{.tst.testState.runtimeProbe+:1};
      mustthrow[
        "*benchmark iterations*";
        (.tst.bench;callable;()!())];
      mustthrow[
        "*benchmark iterations*";
        (.tst.benchmark.runBench;
          callable;
          `iterations`warmup`gcBefore!(3;0;0b))];
      .tst.testState.runtimeProbe musteq 0;
      (::)
    };
    .tst.testState.withRuntimeGlobals[paths;replacements;body];
    ![`.tst.testState;();0b;enlist `runtimeProbe];
  };

  should["validate measurement warmup and comparison ratios before invocation"]{
    .tst.testState.runtimeProbe:0;
    paths:
      `.tst.benchmark.MEASURE_WARMUP,
      `.tst.benchmark.MAX_FINITE_RATIO;
    replacements:(1b;0w);
    body:{
      callable:{.tst.testState.runtimeProbe+:1};
      mustthrow[
        "*measurement warmup*";
        (.tst.benchmark.measureOpts;
          1;
          callable;
          (enlist `gc)!enlist 0b)];
      mustthrow[
        "*ratio safety limit*";
        (.tst.benchCompare;
          "left";
          callable;
          "right";
          callable;
          `iterations`warmup`gcBefore!(1;0;0b))];
      .tst.testState.runtimeProbe musteq 0;
      (::)
    };
    .tst.testState.withRuntimeGlobals[paths;replacements;body];
    ![`.tst.testState;();0b;enlist `runtimeProbe];
  };

  should["harden direct statistics histogram and print entry points"]{
    .tst.testState.runtimeProbe:0;
    paths:
      `.tst.benchmark.MAX_DATA_POINTS,
      `.tst.benchmark.MAX_PRINT_ROWS,
      `.tst.benchmark.MAX_DISPLAY_WIDTH;
    replacements:(2;1;8);
    body:{
      mustthrow[
        "*data-point safety limit*";
        (.tst.benchmark.measureOpts;
          3;
          {.tst.testState.runtimeProbe+:1};
          (enlist `gc)!enlist 0b)];
      .tst.testState.runtimeProbe musteq 0;
      mustthrow[
        "*data*";
        (.tst.benchmark.stats;1 2 3f)];
      mustthrow[
        "*print-row safety limit*";
        (.tst.benchPrintHistogram;
          .tst.benchHistogram[0 1f;2])];
      .tst.benchmark.fixedWidth["abcdef";8] mustmatch "abcdef  ";
      mustthrow[
        "*fixed-width display*";
        (.tst.benchmark.fixedWidth;"xx";9)];
      mustthrow[
        "*exactly the benchmark result fields*";
        (.tst.benchPrint;()!())];

      hugeName:`$65536#"n";
      .tst.benchmark.displayName[hugeName]
        mustmatch "<symbol benchmark>";
      mustthrow[
        "*unknown symbol key*";
        (.tst.bench;
          {.tst.testState.runtimeProbe+:1};
          (enlist hugeName)!enlist 1)];
      .tst.testState.runtimeProbe musteq 0;

      extraHistogram:.tst.benchHistogram[enlist 1f;1];
      .tst.benchmark.validateHistogramTable[extraHistogram]
        mustmatch extraHistogram;
      extraHistogram[`hidden]:enlist 65536#0;
      mustthrow[
        "*must contain exactly*";
        (.tst.benchPrintHistogram;extraHistogram)];

      stats:.tst.bench[
        {::};
        `iterations`warmup`gcBefore!(1;0;0b)];
      .tst.benchmark.validatePrintStats[stats] mustmatch stats;
      malformed:stats;
      malformed[`raw_ns]:65536#0D00:00:00.000000001;
      mustthrow[
        "*raw timings*";
        (.tst.benchPrint;malformed)];
      malformed:stats;
      malformed[`std_us]:enlist 0f;
      mustthrow[
        "*print statistics timing*";
        (.tst.benchPrint;malformed)];
      malformed:stats;
      malformed[`iterations]:2;
      mustthrow[
        "*raw timing count*";
        (.tst.benchPrint;malformed)];
      stats[`hidden]:65536#0;
      mustthrow[
        "*exactly the benchmark result fields*";
        (.tst.benchPrint;stats)];
      (::)
    };
    .tst.testState.withRuntimeGlobals[paths;replacements;body];
    ![`.tst.testState;();0b;enlist `runtimeProbe];
  };
};

::
