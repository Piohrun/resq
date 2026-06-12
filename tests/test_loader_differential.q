/ ============================================================================
/ Generative differential test for the script loader (lib/loader.q).
/ .
/ WHAT IT PROVES
/   For a structurally-varied corpus of q scripts, loading a script two ways
/   yields IDENTICAL global state:
/     (a) native q:   `\l <script>`   (q's own loader, the ground truth)
/     (b) resQ path:  value-ing .tst.preprocessScript / .tst.evalPreprocessed
/                     (what .tst.loadTests does to every test file)
/   Every historical loader bug was a structural case nobody hand-wrote; this
/   harness manufactures thousands of them. ANY difference in the resulting
/   (sorted) name -> value dump is a divergence and fails the test.
/ .
/ HOW
/   Each check writes the script to /tmp and spawns TWO fresh q subprocesses
/   (SEQUENTIALLY - this machine has suffered fork-storms) running a generated
/   "dumper" that prints a canonical state snapshot: every root + non-system
/   namespace variable as "%<fullname>=<.Q.s3 value>", one per line, plus a
/   %LOADERR marker on failure. The two dumps are compared as line sets.
/   The dumpers are generated under /tmp (NOT committed) by .ldiff helpers.
/ .
/   - native dumper: `system "l <script>"` trapped, then dump.
/   - prep dumper:   load the framework (bootstrap + init, with .resq.HOME set so
/                    module paths are absolute regardless of CWD), snapshot
/                    namespaces BEFORE, run .tst.evalPreprocessed on the
/                    preprocessed file trapped, then dump only the NEW state
/                    (framework namespaces excluded by the before/after diff).
/ .
/ ACCEPTED EQUIVALENCES (state-identical, not byte-identical source)
/   The preprocessor DROPS block comments and rewrites \cmd lines; native q
/   ignores block comments and runs the commands. Both produce the same FINAL
/   STATE, which is exactly what the dump compares - so these are not flagged.
/ .
/ DIVERGENCES FOUND & FIXED (see lib/loader.q .tst.evalPreprocessed)
/   The original loader did `value "\n" sv .tst.preprocessScript content` - one
/   blob `value`. That re-lexes the whole file and diverges from q's line-
/   buffered `\l` on:
/     * bare continuation:  `r:5` / `  +6`      (\l: r=11; blob value: 'r error)
/     * bare line comment:  `x:5` / `/ comment` (\l: ignored; blob value: 'handle
/                            - `5 /` parsed as the over-adverb)
/     * trailing inline comment without `;`:    same over-adverb failure.
/   Fix: .tst.evalPreprocessed evaluates per-statement (line-buffered, like \l).
/   The minimized repros are in the fixed nasty corpus below (ldiffCont,
/   ldiffComment, ldiffInline).
/ .
/ EMPIRICALLY-VERIFIED q SEMANTICS the generator encodes (probed against real q)
/   * Block comment opens ONLY on a column-1 line that rstrips to exactly "/"
/     (trailing spaces ignored); an INDENTED "/" does NOT open one.
/   * Block comment closes ONLY on a column-1 line that rstrips to exactly "\";
/     an INDENTED "\" does NOT close it; unclosed -> runs to EOF.
/   * A leading-whitespace line continues the previous CODE line, across
/     intervening blank AND comment lines.
/   * read0 strips a trailing \r (CRLF), so CRLF scripts load identically.
/   * A lone "\" (column 1) terminates the script; the rest is ignored.
/ .
/ MANUAL USE
/   .tst.testState.ldiff.run[seed]   ->  `pass / `skip / `divergeNNN  for one
/   seeded random script (deterministic: same seed => same script). The in-suite
/   test runs the fixed nasty corpus (always) + seeds 1..25. A wider sweep
/   (seeds 1..200) was run during development - clean after the fix above.
/ ============================================================================

/ ---- environment / availability ------------------------------------------
.tst.testState.ldiff.canQ:  0 < count @[system; "which q 2>/dev/null"; {()}];
.tst.testState.ldiff.repo:  .resq.HOME;
.tst.testState.ldiff.dir:   "/tmp/resq_ldiff_", string .z.i;

/ ---- dumper sources (generated to /tmp at setup; NOT committed) ------------
/ Shared tail: walk root + non-system child namespaces, print "%name=value"
/ sorted. .Q.s3 (text repr) is robust for every value type. The native dumper
/ runs it over the WHOLE process (everything a bare q has is system); the prep
/ dumper first subtracts a pre-evaluation snapshot so only user state shows.
.tst.testState.ldiff.dumpTail: (
  ".D.sysns:`q`Q`h`j`o`s`v`z`D;";
  ".D.out:();";
  ".D.rv:(key `.) except .D.baseRoot,`D;";
  "{.D.out,:enlist \"%\",string[x],\"=\",-3!@[get;x;{[e]`ERR}]} each asc .D.rv;";
  ".D.nl:(key `) except .D.baseNs,.D.sysns;";
  ".D.nl:.D.nl where {@[{99h=type get ` sv `,x};x;{0b}]} each .D.nl;";
  "{[ns] fq:` sv `,ns; vrs:key fq; {[fq;v] f:` sv fq,v; .D.out,:enlist \"%\",string[f],\"=\",-3!@[get;f;{[e]`ERR}]}[fq] each asc vrs} each asc .D.nl;",
  "-1 each asc .D.out;",
  / Terminal sentinel: the LAST line written. dumpOf waits until it sees this so
  / it never reads (and compares) a half-flushed file - the dump can legitimately
  / be empty (e.g. an all-comment script), so emptiness alone can't signal "done".
  "-1 \"%%END\";",
  "exit 0;");

/ Native dumper: ground truth via q's own `\l`. baseRoot/baseNs empty so the
/ whole (otherwise bare) process is dumped.
.tst.testState.ldiff.nativeSrc:{[]
  (".D.f:first .z.x;";
   ".D.baseRoot:`symbol$();";
   ".D.baseNs:`symbol$();";
   "@[{system\"l \",x};.D.f;{-1\"%LOADERR:\",x}];"),
  .tst.testState.ldiff.dumpTail
 };

/ Prep dumper: framework loaded (HOME set -> absolute module paths), snapshot
/ taken, then the resQ load path (.tst.evalPreprocessed on the preprocessed
/ file) run trapped. Only NEW state is dumped (framework namespaces subtracted).
.tst.testState.ldiff.prepSrc:{[repo]
  (".D.f:first .z.x;";
   ".D.REPO:\"", repo, "\";";
   ".resq.HOME:.D.REPO;";
   "system \"l \",.D.REPO,\"/lib/bootstrap.q\";";
   ".utl.require .D.REPO,\"/lib/init.q\";";
   ".D.baseRoot:key `.;";
   ".D.baseNs:key `;";
   ".D.content:read0 hsym `$.D.f;";
   "@[.tst.evalPreprocessed; .tst.preprocessScript .D.content; {-1\"%LOADERR:\",x}];"),
  .tst.testState.ldiff.dumpTail
 };

/ ---- subprocess dump (one fresh q) ----------------------------------------
/ Run `q <dumper> <script>` and return the sorted "%"-prefixed dump lines.
/ The child's stdout is redirected to a FILE and read back rather than relying
/ on `system` to capture it: a child q launched from inside an already-loaded q
/ does NOT have its stdout captured by `system` (it leaks to the parent's
/ terminal), so we use the file-redirect idiom the strict/golden harnesses use.
/ `; echo $?` keeps the shell exit 0 so q's `system` never signals 'os.
/ < /dev/null closes the child's stdin (nested q needs it). We keep only "%"
/ lines so framework warnings (a sibling agent's half-written lib/isolate.q
/ emits one) are ignored.
.tst.testState.ldiff.spawnCtr: 0;
/ One spawn attempt: launch the dumper, redirect its stdout to a UNIQUE file (a
/ monotonic counter - the native and prep calls for one script run back-to-back
/ and a timestamp could repeat), then POLL the file until the child's terminal
/ "%%END" sentinel appears. `system` does NOT block until the redirected file is
/ flushed (the child's stdout reaches the file after `system` returns), so only
/ the sentinel - never emptiness, since an all-comment script dumps nothing -
/ can mean "done". Returns (ok; data-lines): ok=0b if the sentinel never showed
/ (a transient spawn failure under heavy load), so the caller can re-spawn rather
/ than compare a truncated dump.
.tst.testState.ldiff.spawnDump:{[dumper; script]
  .tst.testState.ldiff.spawnCtr +: 1;
  outf: script, ".", string[.tst.testState.ldiff.spawnCtr], ".out";
  cmd: "q ", dumper, " ", script, " -q < /dev/null > ", outf, " 2>/dev/null";
  @[system; cmd; {[e] ()}];
  h: hsym `$outf;
  lines: ();
  n: 0;
  while[(n < 400) and not any (lines: @[read0; h; {[e] ()}]) like "%%END";
    system "sleep 0.005";
    n +: 1];
  ok: any lines like "%%END";
  @[hdel; h; {}];                / tidy: these accumulate fast across a sweep
  / keep only "%"-data lines (drop the sentinel and any stray framework warning
  / a sibling agent's half-written module might emit).
  (ok; lines where lines like "%*")
 };
/ Dump robustly: retry the spawn (up to 4x) until the sentinel confirms a clean
/ run, so a transient under-load spawn failure never masquerades as a divergence.
.tst.testState.ldiff.dumpOf:{[dumper; script]
  r: .tst.testState.ldiff.spawnDump[dumper; script];
  n: 0;
  while[(not r 0) and n < 4; r: .tst.testState.ldiff.spawnDump[dumper; script]; n +: 1];
  r 1
 };

/ ---- the differential check for one script --------------------------------
/ Returns `pass (states match), `skip (native q itself errored on the script -
/ generator emitted genuinely invalid q outside a comment; not our bug UNLESS
/ prep succeeded where native failed, which IS flagged), or `diverge.
/ On divergence: print the numbered script + both dumps and save it for repro.
.tst.testState.ldiff.checkScript:{[label; lines]
  d: .tst.testState.ldiff.dir;
  script: d, "/script_", label, ".q";
  / Promote single-char lines (e.g. "/" / "\") from char ATOMS to char VECTORS;
  / `"\n" sv` (and the on-disk write) require uniform string vectors. A literal
  / "/" in q is a char atom, not a 1-element string, which would 'type otherwise.
  lines: {$[10h = type x; x; enlist x]} each lines;
  / write with raw bytes so embedded \r (CRLF cases) survive verbatim
  (hsym `$script) 1: "\n" sv lines;
  natD: .tst.testState.ldiff.dumpOf[d, "/dump_native.q"; script];
  prepD: .tst.testState.ldiff.dumpOf[d, "/dump_prep.q"; script];
  natErr: any natD like "%LOADERR*";
  prepErr: any prepD like "%LOADERR*";
  / Native errored: the generated q is genuinely invalid outside a comment.
  / Skip UNLESS prep "succeeded" (no error) where native failed - that
  / asymmetry (resQ more lenient than real q) is a real finding.
  if[natErr;
    if[prepErr; :`skip];
    .tst.testState.ldiff.report[label; lines; natD; prepD; "prep SUCCEEDED where native q FAILED"];
    :`diverge];
  if[natD ~ prepD; :`pass];
  .tst.testState.ldiff.report[label; lines; natD; prepD; "state dumps differ"];
  `diverge
 };

.tst.testState.ldiff.report:{[label; lines; natD; prepD; why]
  -1 "";
  -1 "==== LOADER DIVERGENCE [", label, "]: ", why, " ====";
  -1 "---- script ----";
  {[i;l] -1 ((-4$string i), ": "), l}'[1 + til count lines; lines];
  -1 "---- native dump ----"; -1 each natD;
  -1 "---- prep dump ----"; -1 each prepD;
  -1 "(script saved at ", .tst.testState.ldiff.dir, "/script_", label, ".q)";
  -1 "";
 };

/ ===========================================================================
/ GENERATOR - seeded, deterministic. A tiny LCG (no global q seed needed) makes
/ the SAME seed always yield the SAME script. Each script is N random blocks.
/ ===========================================================================
/ LCG state lives in .tst.testState.ldiff.lcg; rng[] returns [0,1).
.tst.testState.ldiff.seedRng:{[s] .tst.testState.ldiff.lcg: "j"$ 1 + s; };
.tst.testState.ldiff.rng:{[]
  st: .tst.testState.ldiff.lcg;
  st: (6364136223846793005 * st) + 1442695040888963407;   / 64-bit LCG (overflows, fine)
  .tst.testState.ldiff.lcg: st;
  / fold to a non-negative double in [0,1)
  (abs (st mod 1000000)) % 1000000
 };
.tst.testState.ldiff.randInt:{[n] "j"$ n * .tst.testState.ldiff.rng[]};
.tst.testState.ldiff.pick:{[xs] xs .tst.testState.ldiff.randInt count xs};

/ value literals - kept simple but tricky (strings with / \ quotes; dotted syms)
.tst.testState.ldiff.values:(
  "42"; "-7"; "3.14"; "1 2 3"; "`sym"; "`a.b.c"; "\"plain\"";
  "\"with/slash\""; "\"back\\\\slash\""; "\"q\\\"uote\"";
  "{x+1}"; "{[a;b] a*b}"; "1b"; "0x1f"; "(1;2;3)"; "`a`b!1 2"; "til 5");

/ Build one block. Returns a list of source lines. `k` makes names unique.
.tst.testState.ldiff.block:{[k]
  kind: .tst.testState.ldiff.randInt 11;
  nm: "v", string k;                       / safe name: never a reserved 1-char id
  $[
    kind = 0;
      / plain definition
      enlist nm, ":", .tst.testState.ldiff.pick[.tst.testState.ldiff.values], ";";
    kind = 1;
      / multi-line continuation: complete-looking first line + leading-ws cont
      (nm, ":1"; "    +", string 1 + .tst.testState.ldiff.randInt 9, ";");
    kind = 2;
      / multi-line continuation: trailing operator first line
      (nm, ":2 +"; "    ", string 1 + .tst.testState.ldiff.randInt 9, ";");
    kind = 3;
      / multi-line lambda, inner lines indented
      (nm, ":{[x]"; "    y: x + 1;"; "    y * 2 };");
    kind = 4;
      / line comment (may carry backslashes / a fake \l)
      enlist .tst.testState.ldiff.pick[(
        "/ a plain comment";
        "/ comment with \\ backslash";
        "/ fake \\l /nonexistent/path.q here";
        "/ trailing / slashes // everywhere")];
    kind = 5;
      / block comment: lone "/", 1-5 garbage lines, lone "\"
      (enlist "/"),
        (.tst.testState.ldiff.garbage each til 1 + .tst.testState.ldiff.randInt 5),
        (enlist "\\");
    kind = 6;
      / banner idiom: comment lines, then lone "/" block, garbage, lone "\"
      ("/ Banner ===============";
       "/ module: thing";
       "/"),
        (.tst.testState.ldiff.garbage each til 1 + .tst.testState.ldiff.randInt 3),
        (enlist "\\");
    kind = 7;
      / namespace switch with definitions inside, back to root
      ("\\d .ns", string k;
       "n", string k, ":", .tst.testState.ldiff.pick[.tst.testState.ldiff.values], ";";
       "m", string k, ":99;";
       "\\d .");
    kind = 8;
      / blank lines / spaces-only lines / trailing whitespace
      ((nm, ":7;   "); ""; "    "; (nm, "b:8;"));
    kind = 9;
      / definition with trailing inline comment (no terminating ; first)
      enlist nm, ":", .tst.testState.ldiff.pick[("11";"22";"`z")], " / inline note";
    / kind = 10
      / definition then a leading-ws continuation across a comment line
      (nm, ":5"; "/ comment between"; "    +6;")
   ]
 };

/ One garbage line for inside a block comment (never executed by either path).
.tst.testState.ldiff.garbage:{[i]
  .tst.testState.ldiff.pick[(
    "this is not valid q @#$%";
    "\\l /nope/does/not/exist.q";
    "}{][)(";
    "x:::5";
    "lone token";
    "    indented \\ not a closer";
    "    / indented slash not an opener")]
 };

/ Build a full script for a seed: 8-15 blocks, optionally a trailing terminator
/ + garbage, optionally an unclosed block at EOF.
.tst.testState.ldiff.genScript:{[seed]
  .tst.testState.ldiff.seedRng seed;
  nblocks: 8 + .tst.testState.ldiff.randInt 8;
  blocks: raze .tst.testState.ldiff.block each 1 + til nblocks;
  / sometimes append a lone "\" terminator then garbage (must be ignored)
  if[.tst.testState.ldiff.rng[] < 0.25;
    blocks,: ("\\"; "garbage after terminator !@#"; "more $$$")];
  / sometimes leave an UNCLOSED block comment at EOF
  if[.tst.testState.ldiff.rng[] < 0.25;
    blocks,: ("/"; "trailing garbage in unclosed block"; "x:::nope")];
  / Normalize every line to a FLAT char vector. String-concatenation in `block`
  / (e.g. "n", string k, ":", val, ";") can leave a line as a nested list of
  / char atoms/vectors rather than one string; `"\n" sv` and the on-disk write
  / both require uniform vectors. raze flattens the nesting; the $[...] promotes
  / a single-char atom result (like "/") back to a 1-element vector.
  {[ln] r: raze ln; $[10h = type r; r; enlist r]} each blocks
 };

/ Run one seed end to end.
.tst.testState.ldiff.run:{[seed]
  .tst.testState.ldiff.checkScript["seed", string seed; .tst.testState.ldiff.genScript seed]
 };

/ ---- fixed nasty corpus: every historical bug + the divergences this found ---
/ A line that is exactly "<CR>" is encoded as a 1-char "\r" so we get true CRLF.
.tst.testState.ldiff.cr: enlist "\r";
/ Row builder: each corpus entry is `enlist (label; lines)` so it stays one atom
/ of the outer list. A bare (`sym; list) sibling would flatten into the parent
/ (q can't tell the pair from list nesting); enlist+join keeps the shape clean.
.tst.testState.ldiff.row: {[lbl; lns] enlist (lbl; lns)};
.tst.testState.ldiff.corpus:
  / banner idiom (comment lines, lone /, garbage, lone \)
  (.tst.testState.ldiff.row[`banner; ("/ Banner line 1"; "/ Banner line 2"; "/"; "junk \\l /no.q"; "\\"; "a1:1;")]),
  / mid-file block comment AFTER code
  (.tst.testState.ldiff.row[`midBlock; ("a:1;"; "/"; "garbage here"; "\\"; "b:2;")]),
  / lone "\" terminator then trailing garbage (ignored)
  (.tst.testState.ldiff.row[`terminator; ("a:1;"; "b:2;"; "\\"; "not q !@#"; "x:::1")]),
  / "\" with trailing spaces still terminates / closes
  (.tst.testState.ldiff.row[`backslashSpaces; ("a:1;"; "/"; "junk"; "\\   "; "b:2;")]),
  / "/" with trailing spaces still opens a block
  (.tst.testState.ldiff.row[`slashSpaces; ("a:1;"; "/  "; "junk"; "\\"; "b:2;")]),
  / unclosed block comment at EOF
  (.tst.testState.ldiff.row[`unclosed; ("a:1;"; "/"; "b:2;"; "c:3;")]),
  / namespace switch
  (.tst.testState.ldiff.row[`namespace; ("\\d .myns"; "a:1;"; "b:2;"; "\\d ."; "c:3;")]),
  / namespace + block comment inside
  (.tst.testState.ldiff.row[`nsBlock; ("\\d .nn"; "a:1;"; "/"; "garbage"; "\\"; "b:2;"; "\\d .")]),
  / CRLF line endings (read0 must strip \r identically both ways)
  (.tst.testState.ldiff.row[`crlf; ("a:1;", .tst.testState.ldiff.cr; "b:2;", .tst.testState.ldiff.cr)]),
  / CRLF on the block markers themselves
  (.tst.testState.ldiff.row[`crlfBlock; ("a:1;", .tst.testState.ldiff.cr; "/", .tst.testState.ldiff.cr;
               "junk", .tst.testState.ldiff.cr; "\\", .tst.testState.ldiff.cr;
               "b:2;", .tst.testState.ldiff.cr)]),
  / indented "/" does NOT open a block; both lines run
  (.tst.testState.ldiff.row[`indentSlash; ("a:1;"; "  / indented, not an opener"; "b:2;")]),
  / DIVERGENCE FOUND: bare continuation after a complete statement (r=11 in \l)
  (.tst.testState.ldiff.row[`ldiffCont; ("r:5"; "  +6"; "result:r;")]),
  / DIVERGENCE FOUND: bare line comment after a value (\l ignores; blob value 'handle)
  (.tst.testState.ldiff.row[`ldiffComment; ("zz:5"; "/ standalone comment"; "yy:6;")]),
  / DIVERGENCE FOUND: trailing inline comment with no terminating ; (\l: kk=5)
  (.tst.testState.ldiff.row[`ldiffInline; ("kk:5 / trailing comment"; "mm:6;")]),
  / continuation across a comment line (\l joins across it)
  (.tst.testState.ldiff.row[`contAcrossComment; ("aa:5"; "/ comment"; "    +3;"; "bb:aa;")]),
  / multi-line lambda (brackets keep value joining; must stay equivalent)
  (.tst.testState.ldiff.row[`lambda; ("f:{[x]"; "  y:x+1;"; "  y*2 };"; "fres:f 10;")]),
  / over-adverb (+/) must not be mistaken for a comment
  (.tst.testState.ldiff.row[`overAdverb; ("tot:(+/) 10 20 30;"; "nxt:5 / a real comment")]);

/ ---- one-time setup: make dir + write the two dumpers --------------------
.tst.testState.ldiff.setup:{[]
  d: .tst.testState.ldiff.dir;
  system "mkdir -p ", d;
  (hsym `$d, "/dump_native.q") 0: .tst.testState.ldiff.nativeSrc[];
  (hsym `$d, "/dump_prep.q")   0: .tst.testState.ldiff.prepSrc[.tst.testState.ldiff.repo];
 };

/ Run the whole corpus + a range of seeds; return a result dict for asserts.
.tst.testState.ldiff.runAll:{[seeds]
  .tst.testState.ldiff.setup[];
  cr: {[row] (row 0; .tst.testState.ldiff.checkScript[string row 0; row 1])}
      each .tst.testState.ldiff.corpus;
  sr: {[s] (`$"seed", string s; .tst.testState.ldiff.run s)} each seeds;
  res: cr, sr;
  outcomes: res[;1];
  `diverged`skipped`passed!(
    res where outcomes ~\: `diverge;
    sum outcomes ~\: `skip;
    sum outcomes ~\: `pass)
 };

/ ===========================================================================
/ SUITE
/ ===========================================================================
.tst.desc["loader differential: native q vs preprocessor (#slow)"]{

  skipIf[not .tst.testState.ldiff.canQ;
         "trivial script dumps identically both ways (dumper sanity)"]{
    .tst.testState.ldiff.setup[];
    r: .tst.testState.ldiff.checkScript["sanity"; ("a:1;"; "b:2 3 4;"; "c:`sym;")];
    r musteq `pass;
  };

  skipIf[not .tst.testState.ldiff.canQ;
         "fixed nasty corpus + seeds 1..25 all load-equivalent to native q"]{
    res: .tst.testState.ldiff.runAll 1 + til 25;
    / Labels of any divergences, computed safely (empty -> ""), for triage.
    badLabels: $[count res`diverged; -3! (res`diverged)[;0]; ""];
    must[0 = count res`diverged; "loader divergences: ", badLabels];
    / Sanity: the run actually exercised scripts (not all skipped away).
    must[res[`passed] > 20; "expected many equivalent loads, got ", string res`passed];
  };
 };
