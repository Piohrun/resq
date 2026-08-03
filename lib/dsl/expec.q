\d .tst

runners:()!()

/ Context tracking for better error diagnostics
.tst.currentContext: `file`suite`test!(""; ""; "");
/ A test-body error must cross fixture teardown before the outer runner can turn
/ it into a result. q truncates long signalled strings, so retain the original
/ formatted trace out-of-band for that immediate outer trap.
.tst.pendingBacktrace: "";

/ Test context retained even when no q backtrace object is available.
.tst.stackTrace:{[]
    / Build context string from current test context
    ctx: "";
    fileCtx: .tst.toString .tst.currentContext`file;
    suiteCtx: .tst.toString .tst.currentContext`suite;
    testCtx: .tst.toString .tst.currentContext`test;
    if[0 < count fileCtx; ctx,: "File: ", fileCtx, "\n"];
    if[0 < count suiteCtx; ctx,: "Suite: ", suiteCtx, "\n"];
    if[0 < count testCtx; ctx,: "Test: ", testCtx, "\n"];
    
    / Return empty if no context available
    $[0 < count ctx; "\n", ctx; ""]
 };

/ True when a .Q.sbt line opens a frame: two spaces, "[", digits, "]".
.tst.btIsFrameHead:{[ln]
    if[not 10h = abs type ln; :0b];
    if[3 > count ln; :0b];
    if[not "  [" ~ 3 # ln; :0b];
    rest: 3 _ ln;
    at: rest ? "]";
    if[at >= count rest; :0b];
    digits: at # rest;
    (0 < count digits) and all digits in .Q.n
 };

/ Group .Q.sbt's flat text into frames. A frame is its head line plus the
/ continuation lines (source excerpt, caret) that follow it.
.tst.btFrames:{[lines]
    heads: where .tst.btIsFrameHead each lines;
    if[0 = count heads; :()];
    starts: distinct 0, heads;
    bounds: starts, count lines;
    {[lines; lo; hi] lines lo + til hi - lo}[lines]'[-1 _ bounds; 1 _ bounds]
 };

/ Literal substring test. NOT `ss`: `ss` reads "[", "]", "*" and "?" as pattern
/ syntax, so an install path containing a bracket -- entirely legal on disk --
/ turns into a character class and either mismatches or signals. The needles here
/ are filesystem paths, so they must be compared as bytes.
.tst.literalIn:{[needle; hay]
    n: count needle;
    if[0 = n; :1b];
    if[n > count hay; :0b];
    any {[h; nd; i] nd ~ h i + til count nd}[hay; needle] each til 1 + (count hay) - n
 };

/ True when a frame belongs to resQ's own runner rather than to the code under
/ test. Matched on the SOURCE PATH, not on a `.tst.*` name: a test may legally
/ call framework helpers, and those frames are the user's business. Scoped to
/ <HOME>/lib and <HOME>/resq.q rather than all of <HOME>, for the same reason
/ coverage scopes its self-exclusion that way -- a project can live under the
/ install root (the bundled examples do) and must keep its frames.
.tst.btIsRunnerFrame:{[frame]
    head: $[count frame; first frame; ""];
    if[not 10h = abs type head; :0b];
    home: @[get; `.resq.HOME; {""}];
    if[0 = count home; :0b];
    .tst.literalIn[home, "/lib/"; head] or .tst.literalIn[home, "/resq.q:"; head]
 };

/ The text of a frame's head after its "[N]" marker, left-trimmed.
.tst.btFrameBody:{[head]
    if[not 10h = abs type head; :""];
    at: head ? "]";
    if[at >= count head; :""];
    body: (at + 1) _ head;
    while[(0 < count body) and (first body) in " \t"; body: 1 _ body];
    body
 };

/ A frame that is only a dispatch hop through a q primitive -- "(.Q.trp)",
/ "(.q.each)", "(.q.over)". q emits these with no source location, so they carry
/ no information on their own; they are transparent to the tail scan rather than
/ anchors for it. The distinguishing mark is the surrounding parentheses: the
/ test body's own frame is a bare lambda ("{ .deep.outer[] }") and so still stops
/ the scan, which is exactly where trimming must end.
.tst.btIsTransparentFrame:{[frame]
    body: .tst.btFrameBody $[count frame; first frame; ""];
    (body like "(*)") and not any body = "/"
 };

/ Drop the runner frames between the test body and process entry.
/ .
/ A nested error in user code produced ~85 lines, of which ~30 were resQ's own
/ dispatch (.tst.finishFixtureTest, the .Q.trp hop, .tst.runners, runAll, resq.q)
/ -- always the same frames, never actionable, and long enough that the four
/ frames that matter scrolled away. Only the OUTERMOST CONTIGUOUS run is removed,
/ so anything between user frames survives; scanning stops at the first frame
/ that is not the runner's.
/ .
/ Fails open twice over: an unrecognised layout, or a trace that is entirely
/ framework (a genuine resQ bug, where those frames ARE the evidence), returns
/ the trace untouched. A count of what was dropped is appended so the omission is
/ visible rather than silent.
.tst.trimRunnerFrames:{[formatted]
    lines: "\n" vs formatted;
    frames: .tst.btFrames lines;
    if[0 = count frames; :formatted];
    isRunner: .tst.btIsRunnerFrame each frames;
    droppable: isRunner or .tst.btIsTransparentFrame each frames;
    keep: count frames;
    while[(keep > 0) and droppable keep - 1; keep-: 1];
    if[keep in (0; count frames); :formatted];
    / Never trim a tail of bare dispatch hops that contains no runner frame:
    / without one there is no evidence this is the framework's boundary.
    if[not any isRunner keep + til (count frames) - keep; :formatted];
    omitted: (count frames) - keep;
    "\n" sv (raze keep # frames), enlist "  ... (", string[omitted],
        " resQ runner frame", $[1 = omitted; ""; "s"], " omitted)"
 };

/ Format the backtrace object supplied by .Q.trp while the original failing
/ frames still exist. Formatting is defensive: a formatter problem must never
/ replace the test's original error.
.tst.stackTraceFor:{[bt]
    ctx: .tst.stackTrace[];
    formatted: @[.Q.sbt; bt; {[err] ""}];
    if[not 10h = type formatted; formatted: .tst.toString formatted];
    if[count formatted;
        formatted: @[.tst.trimRunnerFrames; formatted; {[orig; err] orig}[formatted;]]];
    if[count formatted;
        ctx,: $[count ctx; "\n"; ""], "Q Backtrace:\n", formatted];
    ctx
 };

.tst.trapExpecError:{[expec;errorType;err;bt]
    pending: @[get; `.tst.pendingBacktrace; ""];
    .tst.pendingBacktrace: "";
    errorText: $[count pending; pending;
        .tst.toString[err],.tst.stackTraceFor bt];
    .tst.expecError[expec;errorType;errorText]
 };

/ Run a before/after hook through one unary entry point so .Q.trp can preserve
/ nested hook frames and still return the expectation dictionary on success.
.tst.runExpecHook:{[state]
    expec: state`expec;
    code: state`code;
    expec[state`field]: code;
    code[];
    expec
 };

runners[`perf]:{[expec];
  opts: `runs`gc!(10;1b);
  if[0<count expec`props; opts: opts, expec`props];
  runs: $[`runs in key opts; opts`runs; 100];
  / Pass the gc flag through so measure can skip per-iteration .Q.gc[] when off.
  / NOTE: timings are wall-clock ms (float); maxTime asserts in CI need generous
  / headroom - a loaded runner can be 10-100x slower than a quiet local machine.
  res: .tst.benchmark.measureOpts[runs; expec`code; enlist[`gc]!enlist opts`gc];
  expec[`perf]: res;
  expec[`result]: `pass;
  / perfObj carries no `failures key by default; seed an empty string list so the
  / threshold branches below can `,:` onto it without a 'type error.
  if[not `failures in key expec; expec[`failures]: ()];
  if[`maxTime in key opts;
      avgTime: res[`time;`avg];
      if[avgTime > opts`maxTime;
          expec[`result]: `testFail;
          expec[`failures],: enlist "Performance Failure: Avg Time ",string[avgTime],"ms > Limit ",string[opts`maxTime],"ms";
      ];
  ];
  if[`maxSpace in key opts;
      avgSpace: res[`space;`avg];
      if[avgSpace > opts`maxSpace;
          expec[`result]: `testFail;
          expec[`failures],: enlist "Performance Failure: Avg Space ",string[avgSpace]," bytes > Limit ",string[opts`maxSpace]," bytes";
      ];
  ];
  expec
 }

/ Return the explicit fixture parameters for a test lambda.
/ The implicit x on an argument-free lambda is not a fixture dependency.
testFixtureParams:{[func]
 params:`symbol$();
 if[not 100h=type func; :params];
 params:(),(value func) 1;
 isDefaultX:(params~enlist `x) and not `x in key .tst.fixtures;
 params:params where not (null params) or params~\:(::);
 $[isDefaultX; `symbol$(); params]
 }

/ Fail before setup when one or more requested fixtures are unregistered.
validateTestFixtures:{[params;description]
 if[0=count params; :()];
 missing:params where not params in key .tst.fixtures;
 if[0=count missing; :()];
 availFix:", " sv string key .tst.fixtures;
 err:"Fixture Injection Error:\n",
     "  Test: ",.Q.s1[description],"\n",
     "  Missing fixture(s): ",.Q.s1[missing],"\n",
     "  Available fixtures: [",availFix,"]\n",
     "  Hint: Register missing fixtures in a before{} block or .tst.registerFixture";
 'err
 }

/ Tear down one captured test-scoped fixture. Capturing the fixture definition
/ at setup time makes teardown resilient if the test mutates the registry.
teardownInstalledFixture:{[entry]
 fixtureDef:entry`fixture;
 if[not 99h=type fixtureDef; :()];
 if[not ((fixtureDef`scope)~`test); :()];
 teardown:fixtureDef`teardown;
 if[teardown~{}; :()];
 @[teardown; entry`value; {[name;e]
   .tst.recordCleanupError[`testFixture;
       "Fixture '",string[name],"' teardown failed: ",e];
   :()
  }[entry`name;]]
 }

/ Unwind successfully-installed fixtures exactly once, in LIFO order.
teardownInstalledFixtures:{[installed]
 if[0=count installed; :()];
 .tst.teardownInstalledFixture each reverse installed;
 }

/ Install fixtures from left to right. A later setup failure first unwinds the
/ successfully-installed prefix, then re-signals with fixture/test context.
installTestFixtures:{[params;description]
 installed:();
 i:0;
 while[i<count params;
   name:params i;
   fixtureDef:.tst.fixtures name;
   got:@[{[n] (`ok;.tst.getFixture n)}; name; {[n;d;e]
     (`error;"Failed to inject fixture '",string[n],"' for test '",string[d],"': ",e)
    }[name;description;]];
   if[`error~first got;
     .tst.teardownInstalledFixtures installed;
     'last got
    ];
   installed,:enlist `name`value`fixture!(name;last got;fixtureDef);
   i+:1;
  ];
 installed
 }

/ Execute the body and extract assertion results as one protected region.
/ The caller owns fixture teardown whether any statement here throws.
finishFixtureTest:{[state]
 args:{x`value} each state`installed;
 func:state`func;
 $[count args; func . args; func[]];
 expec:state`expec;
 expec[`failures]:.tst.assertState.failures;
 expec[`assertsRun]:.tst.assertState.assertsRun;
 expec[`result]:$[count expec`failures;`testFail;`pass];
 (`ok;expec)
 }

runners[`test]:{[expec]
 .tst.pendingBacktrace: "";
 func:expec`code;
 params:.tst.testFixtureParams func;
 .tst.validateTestFixtures[params;expec`desc];
 installed:.tst.installTestFixtures[params;expec`desc];
 state:`func`expec`installed!(func;expec;installed);
 / This inner trap is required because fixture teardown must happen after a
 / throwing body. Keep the original .Q.trp backtrace object until teardown has
 / completed, then turn it into the ordinary test-error result.
 outcome:.Q.trp[.tst.finishFixtureTest; state; {[err;bt] (`error;err;bt)}];
 .tst.teardownInstalledFixtures installed;
 if[`error~first outcome;
     .tst.pendingBacktrace: (outcome 1), .tst.stackTraceFor outcome 2;
     'outcome 1];
 .tst.pendingBacktrace: "";
 last outcome
 }

expecError:{[expec;errorType;errorText];
 expec[`result]: `$errorType,"Error";
 expec[`errorText]: (),errorText;
 expec[`failures]:.tst.assertState.failures;
 expec[`assertsRun]:.tst.assertState.assertsRun;
 expec
 }

callExpec:{[expec];
 $[expec[`type] in  key .tst.runners;
 .tst.runners[expec`type] expec;
 '`badExpecType]
 }

runExpec:{[spec;expec];
 time:.z.p;
 startExpec:expec;
 / Record the current test name for stack-trace context.
 .tst.currentContext[`test]: $[`desc in key expec; .tst.toString expec`desc; ""];
 expec:.tst.setupExpec[spec;expec];

 / Skip and pending expectations are terminal states. Do not run hooks or code.
 exStatus: .tst.normalizeResultStatus expec`result;
 if[exStatus in `skip`pending;
    expec[`result]: exStatus;
    expec[`failures]: ();
    expec[`assertsRun]: 0i;
    expec[`time]: .z.p - time;
    expec:.tst.teardownExpec[spec;expec];
    :expec
 ];
 
 / Retry support: an expectation with `retries:n` (n>0) gets up to n+1 total
 / attempts. Each attempt re-runs the full before+test+after cycle (so flaky
 / state is reset). The FIRST attempt whose result normalizes to `pass wins.
 / Only the FINAL attempt is recorded (teardownExpec fires exactly once, below).
 / retries=0 (every normal test) collapses to a single pass through the loop.
 maxAttempts: 1 + $[`retries in key expec; 0 | `long$expec`retries; 0];
 / Pristine snapshot of the post-setup expec. q dicts are values, so this copies
 / semantically; restoring `expec:pristine` between attempts also resets the
 / accumulated result/failures/errorText/assertsRun and leaves before/after/code
 / keys untouched.
 pristine: expec;
 attempt: 0;
 / `do`-style loop via while; `attempt`-guarded break on pass or halt.
 done: 0b;
 while[(attempt < maxAttempts) and not done;
   attempt+: 1;
   res: .tst.runExpecAttempt[spec; expec];
   expec: res`expec;
   beforeBad: res`beforeBad;
   passed: `pass ~ .tst.normalizeResultStatus expec`result;
   / Stop if passed, if halt fired, or if no attempts remain.
   done: passed or .tst.halt or (attempt >= maxAttempts);
   / Between attempts: replicate teardownExpec's per-attempt cleanup, then
   / restore the pristine post-setup expec so the flaky test starts clean.
   if[not done;
      .tst.restore[];
      @[.tst.runCleanupTasks; (); {}];
      .tst.assertState: .tst.defaultAssertState;
      expec: pristine;
   ];
 ];

 / Annotate retry outcomes so flake debt is visible, not hidden.
 if[maxAttempts > 1;
    descStr: .tst.toString expec`desc;
    $[`pass ~ .tst.normalizeResultStatus expec`result;
      if[attempt > 1;
         note: "passed on attempt ", string[attempt], " of ", string maxAttempts;
         expec[`retryNote]: note;
         -1 "NOTE: '", descStr, "' ", note, ".";
      ];
      / Failed every attempt: surface the attempt count on the failures list.
      expec[`failures]: (enlist "failed after ", string[maxAttempts], " attempts"), (),expec`failures
    ];
 ];

 expec[`time]:.z.p - time;
 expec:.tst.teardownExpec[spec;expec];
 if[.tst.halt; .tst.stageBadExpec[spec;startExpec;beforeBad]];
 expec
 }

/ One retry attempt: the full before-block + main-test + after-block cycle.
/ Returns `expec`beforeBad!(attemptedExpec; lastStageSym). Does NOT teardown or
/ record - the caller (runExpec) owns the single teardownExpec / expecRan call.
runExpecAttempt:{[spec;expec];
 / Before Block
 beforeBad:`before;
 if[`before in key expec;
    c: expec`before;
    if[type[c] within 100 104h;
        hookState: `expec`code`field!(expec;c;`before);
        expec: .Q.trp[.tst.runExpecHook;hookState;
            .tst.trapExpecError[expec;"before";;]];
    ];
 ];

  / Main Test
  beforeBad:`test;
  if[not count expec[`result];
     budgetMs: "f"$first .tst.app.maxTestTime;
     testStart: .z.p;
     / Execute test with a backtrace-aware trap (no session-killing \T command).
     / The ordinary test runner catches body errors one level deeper so it can
     / unwind fixtures without losing the original frames; this outer trap owns
     / setup errors and the other expectation runner types.
     res: .Q.trp[.tst.callExpec;expec;
         .tst.trapExpecError[expec;.tst.toString expec`type;;]];
     / Post-execution duration budget (milliseconds). This deliberately cannot
     / preempt q code; process isolation owns hard hang termination.
     if[budgetMs > 0;
         elapsedMs: ("f"$.z.p - testStart) % 1000000;
         if[elapsedMs > budgetMs;
             timedExpec: $[99h = type res; res; expec];
             res: .tst.expecError[timedExpec; "timeout";
                 "Test exceeded duration budget of ", string[budgetMs], "ms (took ",
                 string[elapsedMs], "ms). This check is post-execution; use -isolate",
                 " -isolateTimeout N to terminate hung test files."];
         ];
     ];
     $[99h=type res; expec:res; @[{[e;r] e[`result]:`error; e[`errorText]:r; e}; expec; res]];
  ];

 / After Block
 beforeBad:`after;
 if[`after in key expec;
    c: expec`after;
    if[type[c] within 100 104h;
        hookState: `expec`code`field!(expec;c;`after);
        expec: .Q.trp[.tst.runExpecHook;hookState;
            .tst.trapExpecError[expec;"after";;]];
    ];
 ];

 `expec`beforeBad!(expec; beforeBad)
 }

stageBadExpec:{[spec;expec;beforeBad]
 expec:.tst.setupExpec[spec;expec];
 if[beforeBad ~ `before;:(::)];
 if[`before in key expec; c: expec`before; if[type[c] within 100 104h; @[c; (); {}]]];
 if[beforeBad ~ `test;:(::)];
 @[.tst.callExpec;expec;{.tst.expecError[x;string x`type;y]}[expec]];
 }

setupExpec:{[spec;expec];
  if[not `result in key expec; expec[`result]:()];
  if[expec[`result] ~ `didNotRun; expec[`result]:()];
  if[not `runtimeContext in key expec; expec[`runtimeContext]: .tst.captureRuntimeContext[]];
  / Mirror fixture/fixtureAs/mock into .q so unqualified names resolve via the
  / .q fallback inside sandbox namespaces. Gated by qNamespaceExports (default
  / on); when off, tests must use the fully-qualified .tst.mock etc.
  if[1b ~ @[get; `.tst.qNamespaceExports; 1b];
    ((` sv `.q,) each .tst.uiRuntimeNames) .tst.mock' .tst.uiRuntimeCode];
  
  / Safe context switch - if no context defined (e.g. unit tests), stay in current
  if[`context in key .tst; system "d ", string .tst.context];
  
  expec
 }

teardownExpec:{[spec;expec];
 ctx: $[`runtimeContext in key expec; expec`runtimeContext; ()!()];
 system "d .tst";
  .tst.restore[];
  @[.tst.runCleanupTasks; (); {}];
  .tst.assertState:.tst.defaultAssertState;
 .tst.callbacks.expecRan[spec;expec];
 if[99h = type ctx; .tst.restoreRuntimeContext ctx];
 expec
 }
