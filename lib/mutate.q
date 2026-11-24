/ lib/mutate.q - Mutation testing
/ ============================================================================
/ Coverage says a test ran a line. It cannot say a test would fail if the line
/ were wrong. `resq mutate` plants one small change at a time in a function (a
/ mutant) and reruns the tests that call it. A mutant no test fails on has
/ survived: nothing checks the behaviour it changed.
/ .
/ How a mutant is planted. No source file is edited or copied. Each mutant runs
/ in its own q process: the test file loads exactly as it always does, through
/ whatever loader the project uses, and then the one function is redefined in
/ memory from its mutated text. A mutant that hangs or crashes ends only that
/ process.
/ .
/ What keeps the verdicts honest:
/   - A function is mutated only when the definition in memory is, character
/     for character, the definition in the file. Anything else is reported as
/     unmatched rather than guessed at.
/   - "Killed" needs proof that the mutant was in place: the child records the
/     swap before a test can run. A process that failed for another reason
/     (licence, startup) is retried and then reported as an error, never as a
/     kill.
/   - Every test file is first run on its own, unmutated. A file that fails
/     alone is left out, so a failure under mutation is caused by the mutant.
/ .
/ What it cannot see: code outside named functions, and a function reached only
/ through a value captured at load time (a handler dictionary, a projection).
/ docs/MUTATION.md states the limits for users.
/ ============================================================================

.resq.require .resq.PKGLOADING,"/load_graph.q"

/ ----------------------------------------------------------------------------
/ Mutators
/ ----------------------------------------------------------------------------

.tst.mutate.families: `arithmetic`comparison`logical`keyword`constant`condition`statement;

/ active: this process is a child with a plan. parent: this process is running
/ `resq mutate`, so the children it starts are handed one. Kept across a reload.
if[not `active in key `.tst.mutate; .tst.mutate.active: 0b];
if[not `parent in key `.tst.mutate; .tst.mutate.parent: 0b];

/ Seconds any one child may run, unless -isolateTimeout says otherwise.
.tst.mutate.childLimit: 300;

/ Tokens exchanged pairwise: the first with the second, the third with the
/ fourth, and so on, in both directions.
.tst.mutate.pairs: `arithmetic`comparison`logical`keyword!(
    "+ - * % +: -: *: %:";
    "< <= > >= = <>";
    "& | and or &: |: all any";
    "first last min max mins maxs asc desc iasc idesc xasc xdesc floor ceiling prev next lj ij");

/ Unary keywords that are removed outright (`not x` becomes `x`).
.tst.mutate.removable: ("not";"neg";"abs";"distinct";"reverse");

.tst.mutate.subFrom: ();
.tst.mutate.subTo: ();
.tst.mutate.subFamily: `symbol$();
{[family]
    t: " " vs .tst.mutate.pairs family;
    half: (count t) div 2;
    left: t 2*til half;
    right: t 1+2*til half;
    .tst.mutate.subFrom,: left,right;
    .tst.mutate.subTo,: right,left;
    .tst.mutate.subFamily,: (2*half)#family;
 } each key .tst.mutate.pairs;

/ Words that read their left argument, so `3 sublist x` is arithmetic on 3 and
/ `3 x` is not: the second applies 3 as a handle.
.tst.mutate.words: string .Q.res, key `.q;

/ ----------------------------------------------------------------------------
/ Tokens
/ ----------------------------------------------------------------------------

/ `blank, `comment or `code for one token of q's own tokenizer.
.tst.mutate.tokenKind:{[t]
    k: (t in " \t\r\n")?0b;
    if[k=count t; :`blank];
    / "/" alone is the over adverb and "/:" each-right; anything longer that
    / starts with a slash, after blanks or not, is a comment.
    if[("/"=t k) and (1<count t) and not t~"/:"; :`comment];
    `code
 };

/ 1b for each item of `items` (strings) that is one of `pool` (strings).
.tst.mutate.among:{[items;pool] {[pool;t] any pool~\:t}[pool] each items};

/ Index into `pool` of each item of `items`; count pool when absent.
.tst.mutate.indexIn:{[items;pool] {[pool;t] (pool~\:t)?1b}[pool] each items};

/ One line of at most 60 characters describing a piece of source.
.tst.mutate.brief:{[s]
    s: @[s; where s in "\t\r\n"; :; " "];
    s: " " sv (" " vs s) except enlist "";
    $[60<count s; (57#s),"..."; s]
 };

/ Token ranges of the arguments of the bracket opening at token o:
/ close is the closing bracket, lo/hi the half-open range of each argument.
.tst.mutate.argRanges:{[cx;o]
    d: cx`dAfter;
    D: d o;
    / The text parses, so the bracket closes: at the first token after which
    / the depth is back to what it was before o.
    c: o+1+((o+1) _ d)?D-1;
    s: cx`semi;
    s: s where (s within (o;c)) and D=d s;
    `close`lo`hi!(c; (o+1),s+1; s,c)
 };

/ Code tokens inside the half-open token range [lo;hi).
.tst.mutate.sigIn:{[cx;lo;hi]
    s: cx`sig;
    s where (s>=lo) and s<hi
 };

/ ----------------------------------------------------------------------------
/ Generating mutants of one function
/ ----------------------------------------------------------------------------
/ Every generator returns a list of (family; first token; last token; note;
/ mutated text).

.tst.mutate.genSwaps:{[cx;families]
    toks: cx`toks;
    sig: cx`sig;
    idx: .tst.mutate.indexIn[toks sig; .tst.mutate.subFrom];
    / A token that is in no pair indexes past the end: a null family.
    hit: where .tst.mutate.subFamily[idx] in families;
    {[toks;i;r]
        new: .tst.mutate.subTo r;
        (.tst.mutate.subFamily r; i; i; "`",toks[i],"` replaced with `",new,"`";
            raze @[toks; i; :; new])
    }[toks]'[sig hit; idx hit]
 };

.tst.mutate.genRemovals:{[cx]
    toks: cx`toks;
    sig: cx`sig;
    at: sig where .tst.mutate.among[toks sig; .tst.mutate.removable];
    {[toks;i] (`keyword; i; i; "`",toks[i],"` removed"; raze @[toks; i; :; ""])}[toks] each at
 };

/ (digits with sign; type suffix) of a plain integer literal, else ().
.tst.mutate.intParts:{[t]
    typed: last[t] in "hij";
    body: $[typed; -1 _ t; t];
    digits: $["-"=first body; 1 _ body; body];
    $[(0<count digits) and (16>count digits) and all digits in .Q.n; (body; $[typed; -1#t; ""]); ()]
 };

/ 1b when token t begins a value, so that a number written before it is applied
/ to it (`-1 "text"`, `h x`) or belongs to the same vector literal (`1 2 3`).
.tst.mutate.startsNoun:{[t]
    c: t 0;
    if[c in "\"`({",.Q.n; :1b];
    if[(c="-") and 1<count t; :1b];
    if[not c in .Q.a,.Q.A,"."; :0b];
    not any .tst.mutate.words~\:t
 };

.tst.mutate.genConstants:{[cx]
    toks: cx`toks;
    sig: cx`sig;
    n: count sig;
    raze {[toks;sig;n;p]
        i: sig p;
        t: toks i;
        if[any t~/:("0b";"1b");
            new: $[t~"0b"; "1b"; "0b"];
            :enlist (`constant; i; i; "`",t,"` replaced with `",new,"`"; raze @[toks; i; :; new])];
        parts: .tst.mutate.intParts t;
        if[0=count parts; :()];
        / An element of a vector literal, or a handle applied to what follows.
        / A number is never the first or the last token of a function, so
        / there is always a token on each side.
        if[first[toks sig p-1] in .Q.n; :()];
        nxt: toks sig p+1;
        if[.tst.mutate.startsNoun nxt; :()];
        / -4!x and its relatives are internal functions, not arithmetic.
        if[("-"=first t) and nxt~enlist "!"; :()];
        v: "J"$first parts;
        new: string[$[v=0; 1; v=1; 0; v+1]],last parts;
        enlist (`constant; i; i; "`",t,"` replaced with `",new,"`"; raze @[toks; i; :; new])
    }[toks;sig;n] each til n
 };

/ Token indexes of `name[` for the given names.
.tst.mutate.bracketHeads:{[cx;names]
    toks: cx`toks;
    sig: cx`sig;
    sig: sig where .tst.mutate.among[toks sig; names];
    sig where (toks sig+1)~\:enlist "["
 };

.tst.mutate.genConditions:{[cx]
    heads: .tst.mutate.bracketHeads[cx; ("if";enlist "$";enlist "?")];
    raze {[cx;i]
        toks: cx`toks;
        r: .tst.mutate.argRanges[cx;i+1];
        nargs: count r`lo;
        / if[c;...]: the first argument. $[c;a;c;a;default]: every other one
        / (a bracketed cast has two). ?[c;a;b]: the first of exactly three.
        which: $[toks[i]~"if"; $[nargs>1; enlist 0; `long$()];
                 toks[i]~enlist "$"; $[nargs>2; 2*til nargs div 2; `long$()];
                 $[nargs=3; enlist 0; `long$()]];
        raze {[cx;r;k]
            s: .tst.mutate.sigIn[cx; r[`lo] k; r[`hi] k];
            if[0=count s; :()];
            toks: cx`toks;
            a: first s;
            b: last s;
            / `not c` is already covered by removing the `not`.
            if[toks[a]~"not"; :()];
            enlist (`condition; a; b;
                "condition negated: ",.tst.mutate.brief raze toks a+til 1+b-a;
                raze @[toks; a; :; "not ",toks a])
        }[cx;r] each which
    }[cx] each heads
 };

.tst.mutate.statementAt:{[cx;lo;hi]
    s: .tst.mutate.sigIn[cx;lo;hi];
    if[0=count s; :()];
    toks: cx`toks;
    a: first s;
    b: last s;
    k: a+til 1+b-a;
    enlist (`statement; a; b;
        "statement removed: ",.tst.mutate.brief raze toks k;
        raze @[toks; k; :; (count k)#enlist ""])
 };

.tst.mutate.genStatements:{[cx]
    toks: cx`toks;
    sig: cx`sig;
    body: .tst.mutate.argRanges[cx;0];
    lo: body`lo;
    hi: body`hi;
    / Skip a declared parameter list: {[a;b] ...}.
    if[toks[sig 1]~enlist "["; lo[0]: 1+.tst.mutate.argRanges[cx; sig 1]`close];
    outer: raze .tst.mutate.statementAt[cx] ./: flip (lo;hi);
    / Statements of if/do/while. A block with a single statement is already
    / covered by removing the block itself.
    heads: .tst.mutate.bracketHeads[cx; ("if";"do";"while")];
    inner: raze {[cx;i]
        r: .tst.mutate.argRanges[cx;i+1];
        if[3>count r`lo; :()];
        raze .tst.mutate.statementAt[cx] ./: 1 _ flip (r`lo;r`hi)
    }[cx] each heads;
    outer,inner
 };

.tst.mutate.emptyMutants:{[]
    ([] family:`symbol$(); at:`long$(); upto:`long$(); note:(); text:())
 };

/ q's own tokenizer: every token of the text, blanks and comments included.
.tst.mutate.tokens:{[text] -4!text};

/ Mutants of one function's source text. `at` and `upto` are character offsets
/ of the changed span within that text.
.tst.mutate.generate:{[text;families]
    out: .tst.mutate.emptyMutants[];
    original: @[value; text; {[e] ::}];
    if[not 100h=type original; :out];
    / Every change is made to one token and the rest are joined back, so the
    / tokens must add up to the text exactly, and start with the lambda.
    toks: @[.tst.mutate.tokens; text; {[e] ()}];
    if[not text~raze toks; :out];
    if[not (first toks)~enlist "{"; :out];
    len: count each toks;
    offs: sums[len]-len;
    kind: .tst.mutate.tokenKind each toks;
    c0: toks[;0];
    one: len=1;
    delta: (one and c0 in "([{")-one and c0 in ")]}";
    cx: `toks`n`sig`dAfter`semi!(toks; count toks; where kind=`code; sums delta; where one and c0=";");

    rows: ();
    if[any families in `arithmetic`comparison`logical`keyword; rows,: .tst.mutate.genSwaps[cx;families]];
    if[`keyword in families; rows,: .tst.mutate.genRemovals cx];
    if[`constant in families; rows,: .tst.mutate.genConstants cx];
    if[`condition in families; rows,: .tst.mutate.genConditions cx];
    if[`statement in families; rows,: .tst.mutate.genStatements cx];

    txt: rows[;4];
    / A change that leaves the text as it was, or repeats another, is no mutant.
    keep: where (not txt~\:text) and (til count txt)=.tst.mutate.indexIn[txt;txt];
    / Nor is one that no longer parses, or that changes the parameters.
    params: (value original) 1;
    valid: {[params;t]
        f: @[value; t; {[e] ::}];
        $[100h=type f; params~(value f) 1; 0b]
    }[params] each txt keep;
    keep: keep where valid;
    / Token indexes, as longs even when nothing is left.
    a: "j"$rows[keep;1];
    b: "j"$rows[keep;2];
    order: iasc a;
    ([] family:`$string rows[keep;0]; at:offs a; upto:offs[b]+len b; note:rows[keep;3]; text:txt keep) order
 };

/ ----------------------------------------------------------------------------
/ Finding functions in a file
/ ----------------------------------------------------------------------------

.tst.mutate.emptyFunctions:{[]
    ([] name:`symbol$(); file:(); line:`long$(); col:`long$(); text:())
 };

/ Named functions defined at the top level of a file: `name:{...}` on its own,
/ optionally closed with ";". `line` and `col` locate the opening brace.
.tst.mutate.functionsIn:{[path]
    out: .tst.mutate.emptyFunctions[];
    lines: @[read0; hsym `$path; {[e] ()}];
    cx: .tst.loadGraph.context .tst.loadGraph.lex lines;
    code: cx`code;
    if[0=count code; :out];
    opens: where (code="{") and 0=cx`dBefore;
    closes: where (code="}") and 1=cx`dBefore;
    ci: closes binr opens;
    opens: opens where ci<count closes;
    ends: closes ci where ci<count closes;
    names: .tst.loadGraph.definedName[cx] each opens;
    / Anything after the closing brace but ";" makes the value something other
    / than this lambda: a projection, an application, a derived function.
    plain: .tst.loadGraph.endsStatement[code] each ends;
    keep: where plain and 0<count each names;
    opens: opens keep;
    ends: ends keep;
    starts: cx`starts;
    ln: starts bin opens;
    ([] name:`$names keep; file:(count keep)#enlist path; line:1+ln; col:1+opens-starts ln;
        text:{[txt;o;e] txt o+til 1+e-o}[cx`txt]'[opens;ends])
 };

/ (line; column) in the file of character offset `at` within a function's text.
.tst.mutate.position:{[fn;at]
    nl: where (at#fn`text)="\n";
    $[count nl; (fn[`line]+count nl; at-last nl); (fn`line; fn[`col]+at)]
 };

/ ----------------------------------------------------------------------------
/ Inside a child process
/ ----------------------------------------------------------------------------
/ A child is an ordinary `resq test <file>` run that was handed a plan. A probe
/ plan lists every target function and records which of them the file calls. A
/ mutant plan names one function and the text to replace it with.
/ .
/ Everything a child knows is one dictionary held in a global, and each
/ function here takes the name of that global. The process's own state is
/ .tst.mutate.child. Taking the name, rather than assuming it, lets a test
/ drive these functions on a state of its own even while the test process is
/ itself a mutation child.

.tst.mutate.planPath:{[wd] wd,"/mutation.plan"};
.tst.mutate.statusPath:{[wd] wd,"/mutation.status"};

.tst.mutate.child: ()!();
.tst.mutate.missing: `resqMutateMissing;

/ Read a plan file into the state named `st`. 0b when it cannot be read.
.tst.mutate.loadPlan:{[st;path]
    plan: @[get; hsym `$path; {[e] ()}];
    if[not 99h=type plan; :0b];
    n: count plan`names;
    st set `plan`orig`wrap`matched`differs`hits`mutantFn`applied!(
        plan; n#(::); n#(::); n#0b; n#0b; n#0b; (::); 0b);
    1b
 };

/ Make the state named `st` that of a mutation child and switch the runner's
/ hooks on. 0b, with nothing changed, when the plan cannot be read.
.tst.mutate.startChild:{[st;path]
    ok: .tst.mutate.loadPlan[st;path];
    if[ok; .tst.mutate.active: 1b];
    ok
 };

/ Append one line to the status file the parent reads.
.tst.mutate.note:{[st;line]
    @[{[a] h: hopen hsym `$a 0; neg[h] a 1; hclose h;}; (get[st][`plan]`status; line); {[e] ::}];
 };

.tst.mutate.live:{[name] @[get; name; {[e] .tst.mutate.missing}]};

/ Compile function text in the namespace the original was defined in, so its
/ unqualified names resolve as before. Returns (1b; function) or (0b; error).
.tst.mutate.compile:{[ns;text]
    restore: string system "d";
    target: $[null ns; "."; ".",string ns];
    r: @[{[a] system "d ",a 0; (1b; value a 1)}; (target;text); {[e] (0b; e)}];
    system "d ",restore;
    r
 };

/ Text of the function that stands in for target i while probing: it records
/ the call in the state named `st` and passes its arguments to the original.
.tst.mutate.wrapperText:{[st;i;args]
    at: "`",string[st];
    "{[",args,"] .[",at,"; (`hits;",string[i],"); :; 1b]; (get[",at,"][`orig] ",string[i],")[",args,"]}"
 };

/ Wrap target i so a call through its name is recorded, when the definition in
/ memory is the one the file holds.
.tst.mutate.probe:{[st;i]
    s: get st;
    name: s[`plan;`names] i;
    live: .tst.mutate.live name;
    if[live~s[`wrap] i; :()];
    if[not 100h=type live; :()];
    if[not (last value live)~s[`plan;`texts] i;
        .[st; (`differs;i); :; 1b];
        :()];
    wrapper: @[value; .tst.mutate.wrapperText[st; i; ";" sv string (value live) 1]; {[e] ::}];
    if[not 100h=type wrapper; :()];
    .[st; (`orig;i); :; live];
    .[st; (`wrap;i); :; wrapper];
    name set wrapper;
    .[st; (`matched;i); :; 1b];
 };

/ Put the mutant in place of the one target, when the definition in memory is
/ the one the file holds. "applied" is written before any test can run on it:
/ the parent counts a kill only with that proof.
.tst.mutate.applyMutant:{[st]
    s: get st;
    name: s[`plan;`names] 0;
    live: .tst.mutate.live name;
    / Once the mutant is in place its text is no longer the file's, so this
    / also returns when there is nothing left to do.
    if[not 100h=type live; :()];
    if[not (last value live)~s[`plan;`texts] 0; :()];
    if[(::)~s`mutantFn;
        r: .tst.mutate.compile[first (value live) 3; s[`plan]`mutated];
        if[not first r;
            .tst.mutate.note[st; "error could not compile the mutant: ",last r];
            :()];
        @[st; `mutantFn; :; last r]];
    if[not s`applied;
        .tst.mutate.note[st; "applied"];
        @[st; `applied; :; 1b]];
    name set get[st]`mutantFn;
 };

/ Called once test files have loaded and again before each test body, because
/ a hook may reload the source. Never signals: an error here must not look
/ like a failing test.
.tst.mutate.install:{[st]
    @[{[st]
        $[`probe~get[st][`plan]`mode;
            .tst.mutate.probe[st] each til count get[st][`plan]`names;
            .tst.mutate.applyMutant st];
      }; st; {[st;e] .tst.mutate.note[st; "error ",e]}[st]];
 };

/ Called when the run is over: a probe child reports what it saw. Like every
/ write to the status file this appends, so nothing already recorded there,
/ above all that a mutant was applied, can be lost.
.tst.mutate.finish:{[st]
    s: get st;
    if[not `probe~s[`plan]`mode; :()];
    lines: ("matched ",/:string where s`matched),
        ("differs ",/:string where s[`differs] and not s`matched),
        "hit ",/:string where s`hits;
    .tst.mutate.note[st; "\n" sv lines,enlist "done"];
 };

/ ----------------------------------------------------------------------------
/ Choosing what to mutate
/ ----------------------------------------------------------------------------

/ "path", "path:12" or "path:10-40" as path, lo and hi (0N 0N for the whole file).
.tst.mutate.parseTarget:{[arg]
    whole: `path`lo`hi!(arg; 0N; 0N);
    colons: where arg=":";
    if[0=count colons; :whole];
    k: last colons;
    parts: "-" vs (k+1) _ arg;
    ok: (count[parts] in 1 2) and all {(0<count x) and all x in .Q.n} each parts;
    if[not ok; :whole];
    `path`lo`hi!(k#arg; "J"$first parts; "J"$last parts)
 };

/ Path as the user would type it: relative to the working directory if inside it.
.tst.mutate.display:{[path]
    p: .resq.util.pathToString path;
    cwd: (system "cd"),"/";
    $[cwd~(count cwd)#p; (count cwd) _ p; p]
 };

/ Files a target stands for, as a table of path, lo and hi. A directory gives
/ every .q file under it that is not a test file. Every path comes back in one
/ spelling, so a file named twice ("src/a.q", "./src/a.q") is one file.
.tst.mutate.expandTarget:{[testFiles;target]
    path: target`path;
    spell: {[p] .tst.mutate.display .tst.canonicalPath p};
    if[.resq.util.isFile path;
        :([] path:enlist spell path; lo:enlist target`lo; hi:enlist target`hi)];
    if[not .resq.util.isDir path; '"no such file or directory: ",path];
    if[not null target`lo; '"a line range needs a file, not a directory: ",path];
    canon: .tst.canonicalPath each .resq.util.pathToString each .tst.static.findSources path;
    isTest: .tst.mutate.among[canon; testFiles] or .tst.watch.runnable each `$canon;
    files: .tst.mutate.display each canon where not isTest;
    ([] path:files; lo:(count files)#0N; hi:(count files)#0N)
 };

/ Signals unless `ref` names a commit in the repository we are in.
.tst.mutate.requireRevision:{[ref]
    / The subshell matters: q captures the output of the command it is given
    / as a whole, and a bare list would hand it only the last command's.
    cmd: "(git rev-parse --verify --quiet ",.resq.util.shellQuote[ref,"^{commit}"]," >/dev/null 2>&1 && echo ok; true)";
    out: @[system; cmd; {[e] ()}];
    if[not any out~\:"ok"; '"-since needs a git revision; this is not one here: ",ref];
 };

/ Line ranges of `path` changed since git revision `ref`, as a list of (lo;hi)
/ pairs. A file git does not track yet is new, so every line counts.
.tst.mutate.changedLines:{[ref;path]
    quoted: .resq.util.shellQuote path;
    tracked: @[system; "(git ls-files --error-unmatch -- ",quoted," >/dev/null 2>&1 && echo ok; true)"; {[e] ()}];
    if[not any tracked~\:"ok"; :enlist 1 0W];
    .tst.mutate.hunkRanges @[system; "(git diff -U0 --no-color --no-ext-diff --no-textconv ",.resq.util.shellQuote[ref]," -- ",quoted," 2>&1; true)"; {[e] ()}]
 };

/ New-side line ranges of the hunks in `git diff -U0` output. A hunk header
/ reads "@@ -a,b +c,d @@": c is the first new line and d how many (1 when
/ absent, 0 for a pure deletion, which leaves an empty range).
.tst.mutate.hunkRanges:{[lines]
    {[h]
        words: " " vs h;
        plus: first words where words like "+*";
        nums: "J"$"," vs plus;
        n: $[1<count nums; nums 1; 1];
        (nums 0; -1+nums[0]+n)
    } each lines where lines like "@@ *"
 };

/ The families named by -mutators, or all of them.
.tst.mutate.chosenFamilies:{[spec]
    if[0=count spec; :.tst.mutate.families];
    names: trim each "," vs spec;
    bad: names where not .tst.mutate.among[names; string .tst.mutate.families];
    if[count bad;
        '"unknown mutator: ",(", " sv bad),". Known: ",", " sv string .tst.mutate.families];
    `$names
 };

/ Every mutant of the targets, one row each, with the index of its function.
/ `since` maps a path (symbol) to the line ranges changed, or is () for all.
.tst.mutate.gather:{[sources;families;since]
    fns: raze .tst.mutate.functionsIn each distinct sources`path;
    touches: {[lo;hi;ranges] any {[lo;hi;r] (lo<=r 1) and hi>=r 0}[lo;hi] each ranges};
    mutants: raze {[sources;families;since;touches;fnIdx;f]
        m: .tst.mutate.generate[f`text; families];
        if[0=count m; :()];
        pos: .tst.mutate.position[f] each m`at;
        lo: pos[;0];
        hi: first each .tst.mutate.position[f] each m`upto;
        / Keep a mutant whose changed span touches a requested line range.
        rows: sources where sources[`path]~\:f`file;
        wanted: {[r] $[null r`lo; 1 0W; (r`lo; r`hi)]} each rows;
        keep: touches[;;wanted]'[lo;hi];
        if[count since; keep: keep and touches[;;since `$f`file]'[lo;hi]];
        if[not any keep; :()];
        k: where keep;
        update fnIdx:fnIdx, line:lo k, col:pos[k;1] from m k
    }[sources;families;since;touches]'[til count fns; fns];
    `functions`mutants!(fns; mutants)
 };

/ ----------------------------------------------------------------------------
/ Running children
/ ----------------------------------------------------------------------------

.tst.mutate.requireTools:{[]
    ok: (.tst.isolate.probeTimeout .tst.isolate.timeoutExe) and
        all 0<count each (.tst.isolate.qExe; .tst.isolate.mktempExe; .tst.isolate.chmodExe;
            .tst.isolate.rmExe; .tst.isolate.shExe);
    if[not ok;
        '"mutation testing needs a timeout command with -k support and the q, mktemp, chmod, rm and sh executables"];
 };

.tst.mutate.noChild:{[]
    `code`valid`ran`failed`firstFailure`timedOut`licence`status`tail!(
        -1; 0b; 0; 0; ""; 0b; 0b; (); "could not prepare a scratch directory for the child")
 };

/ What one finished child left behind.
.tst.mutate.readChild:{[wd]
    code: .tst.isolate.readExitCode wd;
    decoded: .tst.isolate.decodeReport @[read0; hsym `$wd,"/test-results.json"; {[e] ()}];
    rows: $[decoded`valid; .tst.eventRows decoded[`report]`tests; ()];
    statuses: {[r] lower .tst.toString r`status} each rows;
    bad: where not .tst.mutate.among[statuses; ("pass";"skip";"pending")];
    captured: .tst.isolate.readCaptured wd;
    firstFailure: $[count bad;
        {[r] .tst.toString[r`suite]," / ",.tst.toString r`description} rows first bad;
        ""];
    `code`valid`ran`failed`firstFailure`timedOut`licence`status`tail!(
        code; decoded`valid; count rows; count bad; firstFailure;
        / The supervisor says when it is the one that stopped the child. Exit
        / 137 alone (SIGKILL) can also come from outside: the kernel's
        / out-of-memory killer or a CI agent. That is not a timeout.
        (code = 124) or 0<count ss[captured; "timeout: sending signal "];
        / q reports this on a line of its own that starts with a quote. Looking
        / for that, rather than the phrase anywhere, keeps test output that
        / merely mentions it from being taken for a licence failure.
        any {("'"=first x) and 0<count ss[x; "couldn't connect to license daemon"]} each "\n" vs lower captured;
        @[read0; hsym `$.tst.mutate.statusPath wd; {[e] ()}];
        .tst.isolate.tail[wd; 12])
 };

/ Run one child per (test file; plan; timeout) at the same time and return a
/ table with one row of readChild per child.
.tst.mutate.runBatch:{[files;plans;timeouts]
    wds: {[unused] @[.tst.isolate.createScratch; ::; {[e] ""}]} each files;
    ready: {[wd;plan]
        if[0=count wd; :0b];
        .tst.isolate.resetScratch wd;
        if[not 1b~@[.tst.isolate.preparePrivateRerunState; wd; {[e] 0b}]; :0b];
        plan[`status]: .tst.mutate.statusPath wd;
        @[{[a] (hsym `$a 0) set a 1; 1b}; (.tst.mutate.planPath wd; plan); {[e] 0b}]
    }'[wds;plans];
    cmds: {[ok;wd;file;secs] $[ok; .tst.isolate.processCommand[wd;file;secs]; ""]}'[ready;wds;files;timeouts];
    at: where ready;
    .tst.isolate.launchGroup[at; cmds at; wds at];
    results: {[ok;wd] $[ok; .tst.mutate.readChild wd; .tst.mutate.noChild[]]}'[ready;wds];
    {[wd] if[count wd; @[.tst.isolate.cleanupScratch; wd; {[e] ::}]];} each wds;
    results
 };

/ Everything the command prints goes through these, so it can be checked.
.tst.mutate.out:{[line] -1 line;};
.tst.mutate.err:{[line] -2 line;};
.tst.mutate.mark:{[text] 1 text;};
/ The time, through a function so that a test can decide what time it is.
.tst.mutate.clock:{[] .z.p};
/ Progress marks, written without a newline; silent under -quiet.
.tst.mutate.tick:{[text] if[not 1b~.tst.app.quiet; .tst.mutate.mark (),text];};

/ ----------------------------------------------------------------------------
/ Baseline: every test file on its own, unmutated, with probes
/ ----------------------------------------------------------------------------

/ Function indexes named by status lines such as "hit 12".
.tst.mutate.statusIndexes:{[lines;word]
    hit: lines where lines like word," *";
    "J"${[word;l] (count word) _ l}[word] each hit
 };

.tst.mutate.baselineReason:{[r]
    done: any r[`status]~\:"done";
    $[r`timedOut; "timed out";
      not r`valid; "left no report (exit code ",string[r`code],")";
      0<r`failed; "fails on its own: ",r`firstFailure;
      not 0=r`code; "exit code ",string r`code;
      0=r`ran; "ran no tests";
      not done; "did not finish the run";
      ""]
 };

/ One row per test file: whether it can be used, how long it took, and which
/ target functions it matched, found different, and called.
.tst.mutate.baseline:{[testFiles;fns;workers;cap]
    plan: `mode`names`texts`mutated`status!(`probe; fns`name; fns`text; ""; "");
    groups: workers cut til count testFiles;
    raze {[testFiles;plan;cap;idx]
        started: .tst.mutate.clock[];
        res: .tst.mutate.runBatch[testFiles idx; (count idx)#enlist plan; (count idx)#cap];
        secs: ("f"$.tst.mutate.clock[]-started)%1e9;
        why: .tst.mutate.baselineReason each res;
        .tst.mutate.tick raze ?[0=count each why; "."; "x"];
        ([] file:testFiles idx; usable:0=count each why; why:why; secs:(count idx)#secs;
            matched:.tst.mutate.statusIndexes[;"matched"] each res`status;
            differs:.tst.mutate.statusIndexes[;"differs"] each res`status;
            hits:.tst.mutate.statusIndexes[;"hit"] each res`status;
            tail:res`tail)
    }[testFiles;plan;cap] each groups
 };

/ ----------------------------------------------------------------------------
/ Files changed while mutants ran
/ ----------------------------------------------------------------------------
/ A mutant is the code under test with one thing changed, and that code may
/ write or delete files. Short of a sandbox nothing can stop a mutant doing so
/ in the wrong place, but what it did can be found. In a git checkout the
/ working directory is looked at before the mutants run and after each batch.

/ 1b when the working directory is inside a git checkout.
.tst.mutate.inGit:{[]
    out: @[system; "(git rev-parse --is-inside-work-tree 2>/dev/null; true)"; {[e] ()}];
    any out~\:"true"
 };

.tst.mutate.noFiles:{[] ([] path:`symbol$(); untracked:`boolean$(); print:())};

/ The files named by `git ls-files -t` lines, each once: "C path" is a tracked
/ file and "? path" an untracked one.
.tst.mutate.listedFiles:{[lines]
    syms: `$2 _' lines;
    keep: where (til count syms)=syms?syms;
    ([] path:syms keep; untracked:"?"=lines[keep;0])
 };

/ Every file under the working directory that git sees as modified, deleted or
/ untracked (ignored files are left out), with a fingerprint of its state.
/ Empty outside a git checkout.
.tst.mutate.snapshot:{[]
    lines: @[system; "(git -c core.quotepath=off ls-files -t -m -o --exclude-standard -- . 2>/dev/null; true)"; {[e] ()}];
    if[0=count lines; :.tst.mutate.noFiles[]];
    found: .tst.mutate.listedFiles lines;
    paths: string found`path;
    update print:.tst.watch.fingerprintWith[.tst.watch.statAll paths] each paths from found
 };

.tst.mutate.noChanges:{[] ([] path:(); change:`symbol$(); mutants:())};

/ What differs between two snapshots, one row per file: created, modified,
/ deleted, or restored (a changed tracked file is back as git has it).
.tst.mutate.changes:{[before;after]
    absent: (-1;"";"");
    at: before[`path]?after`path;
    isNew: at=count before;
    same: (not isNew) and after[`print]~'before[`print] at;
    k: where not same;
    kind: {[absent;isNew;untracked;print]
        $[print~absent; `deleted; isNew and untracked; `created; `modified]
    }[absent]'[isNew k; after[`untracked] k; after[`print] k];
    / No longer listed: an untracked file is gone, or a tracked one is clean.
    lost: where not before[`path] in after`path;
    ([] path:string (after[`path] k),before[`path] lost;
        change:kind,?[before[`untracked] lost; `deleted; `restored])
 };

/ Above this, looking at the working directory after every batch would slow
/ the run noticeably, so it is looked at once, at the end.
.tst.mutate.snapshotBudget: 0D00:00:00.5;

/ ----------------------------------------------------------------------------
/ Mutant runs
/ ----------------------------------------------------------------------------

/ What one mutant run shows. `retry means the run proves nothing either way:
/ it failed without evidence that the mutant was in place. An error the child
/ recorded while placing the mutant makes a passing run worthless, but not a
/ failing one: the mutant was in place and the tests did fail.
.tst.mutate.verdict:{[r]
    st: r`status;
    applied: any st like "applied*";
    errored: any st like "error*";
    if[r`licence; :`retry];
    if[r`timedOut; :$[applied; `timeout; errored; `error; `retry]];
    / Killed by something other than resQ's own timeout: no evidence either
    / way about the mutant. Run it again; it ends as not assessed.
    if[137 = r`code; :`retry];
    bad: (not r`valid) or (0<r`failed) or not 0=r`code;
    $[bad and applied; `killed; errored; `error; bad; `retry; applied; `survived; `unapplied]
 };

.tst.mutate.marks: `killed`timeout`survived`unapplied`error!".TS-E";

/ Run every pending mutant against the test files that call its function,
/ quickest file first, until one kills it. Returns `mutants, with a status and
/ for a kill the test file responsible, and `changes: the files changed in the
/ working directory meanwhile, each with the mutants that were running.
.tst.mutate.execute:{[mutants;fns;base;workers;cap]
    n: count mutants;
    usable: where base`usable;
    usable: usable iasc base[`secs] usable;
    nf: count fns;
    calledBy: {[base;usable;f] usable where {[f;h] f in h}[f] each base[`hits] usable}[base;usable] each til nf;
    matched: {[base;usable;f] any {[f;h] f in h}[f] each base[`matched] usable}[base;usable] each til nf;
    differs: {[base;usable;f] any {[f;h] f in h}[f] each base[`differs] usable}[base;usable] each til nf;
    fnStatus: ?[0<count each calledBy; `pending; ?[matched; `uncovered; ?[differs; `unmatched; `unloaded]]];

    status: fnStatus mutants`fnIdx;
    killedBy: n#enlist "";
    step: n#0;
    tries: n#0;
    everApplied: n#0b;
    changes: .tst.mutate.noChanges[];
    started: .tst.mutate.clock[];
    seen: .tst.mutate.snapshot[];
    eachBatch: .tst.mutate.snapshotBudget>.tst.mutate.clock[]-started;
    while[count active: where status=`pending;
        batch: workers sublist active;
        fileIdx: {[calledBy;f;k] calledBy[f] k}[calledBy]'[mutants[`fnIdx] batch; step batch];
        plans: {[fns;m]
            f: fns m`fnIdx;
            `mode`names`texts`mutated`status!(`mutant; enlist f`name; enlist f`text; m`text; "")
        }[fns] each mutants batch;
        / Generous next to the unmutated run, so only a real hang times out.
        timeouts: cap&"j"$ceiling 5+3*base[`secs] fileIdx;
        res: .tst.mutate.runBatch[base[`file] fileIdx; plans; timeouts];
        if[eachBatch;
            now: .tst.mutate.snapshot[];
            delta: .tst.mutate.changes[seen;now];
            changes,: update mutants:(count delta)#enlist batch from delta;
            seen: now];
        verdicts: .tst.mutate.verdict each res;
        i: 0;
        while[i<count batch;
            m: batch i;
            v: verdicts i;
            if[v in `killed`timeout; killedBy[m]: base[`file] fileIdx i; status[m]: v];
            if[v~`error; status[m]: `error];
            if[v~`retry;
                tries[m]+: 1;
                if[tries[m]>=3; status[m]: `error]];
            if[v in `survived`unapplied;
                everApplied[m]: everApplied[m] or v~`survived;
                step[m]+: 1;
                tries[m]: 0;
                if[step[m]>=count calledBy mutants[`fnIdx] m;
                    status[m]: $[everApplied m; `survived; `unapplied]]];
            if[not status[m]~`pending;
                .tst.mutate.tick .tst.mutate.marks status m;
                if[0=(sum status in key .tst.mutate.marks) mod 60; .tst.mutate.tick "\n"]];
            i+: 1];
    ];
    / Looked at once: which mutant it was cannot be told.
    if[not eachBatch;
        delta: .tst.mutate.changes[seen; .tst.mutate.snapshot[]];
        changes,: update mutants:(count delta)#enlist `long$() from delta];
    `mutants`changes!(update status:status, killedBy:killedBy from mutants; changes)
 };

/ ----------------------------------------------------------------------------
/ Report
/ ----------------------------------------------------------------------------

/ To one decimal place; null when there is nothing to divide by.
.tst.mutate.percent:{[num;den] 0.1*"j"$1000*num%den};
.tst.mutate.showPercent:{[p] $[null p; "n/a"; .Q.f[1;p],"%"]};

/ Counts and scores. Detected is killed plus timed out. A mutant in a function
/ no test calls counts against the score; one that could not be assessed
/ (unmatched, never applied, error) is left out of it.
.tst.mutate.summary:{[mutants]
    st: mutants`status;
    c: {[st;names] "j"$sum st in names}[st];
    detected: c `killed`timeout;
    survived: c enlist `survived;
    notCovered: c `uncovered`unloaded;
    `mutants`killed`timedOut`survived`notCovered`notAssessed`score`coveredScore!(
        count mutants; c enlist `killed; c enlist `timeout; survived; notCovered;
        c `unmatched`unapplied`error;
        .tst.mutate.percent[detected; detected+survived+notCovered];
        .tst.mutate.percent[detected; detected+survived])
 };

.tst.mutate.pad:{[width;text] (width|count text)#text,width#" "};

/ "file" heading followed by one line per mutant.
.tst.mutate.listMutants:{[fns;rows]
    files: fns[`file] rows`fnIdx;
    raze {[fns;rows;files;file]
        r: `line`col xasc rows where files~\:file;
        where_: {[r] string[r`line],":",string r`col} each r;
        names: string fns[`name] r`fnIdx;
        w: max count each where_;
        wn: max count each names;
        enlist["  ",.tst.mutate.display file],
            {[w;wn;at;name;note] "    ",.tst.mutate.pad[w;at],"  ",.tst.mutate.pad[wn;name],"  ",note}[w;wn]'[where_;names;r`note]
    }[fns;rows;files] each distinct files
 };

/ One line per function for mutants that were never run, with how many.
.tst.mutate.listFunctions:{[fns;rows]
    idx: distinct rows`fnIdx;
    {[fns;rows;f]
        "    ",.tst.mutate.display[fns[`file] f],":",string[fns[`line] f],"  ",string[fns[`name] f],
            "  (",string[sum f=rows`fnIdx]," mutant(s))"
    }[fns;rows] each idx
 };

/ Where and what one mutant is, for a line of the report.
.tst.mutate.whereIs:{[fns;m] .tst.mutate.display[fns[`file] m`fnIdx],":",string m`line};

/ One line per changed file: what happened to it and which mutants were running.
.tst.mutate.listChanges:{[mutants;fns;changes]
    w: max count each string changes`change;
    {[mutants;fns;w;c]
        ids: c`mutants;
        during: $[0=count ids; "at some point in the run";
            1=count ids; "during ",.tst.mutate.whereIs[fns; mutants ids 0]," ",mutants[ids 0]`note;
            "during one of: ",(", " sv .tst.mutate.whereIs[fns] each mutants 3 sublist ids),$[3<count ids; ", ..."; ""]];
        "    ",.tst.mutate.pad[w; string c`change],"  ",c[`path],"  (",during,")"
    }[mutants;fns;w] each changes
 };

.tst.mutate.report:{[mutants;fns;base;changes]
    s: .tst.mutate.summary mutants;
    st: mutants`status;
    .tst.mutate.out "";
    .tst.mutate.out "RESULT";
    .tst.mutate.out "  killed        ",string s`killed;
    .tst.mutate.out "  timed out     ",string s`timedOut;
    .tst.mutate.out "  survived      ",string s`survived;
    .tst.mutate.out "  not covered   ",string s`notCovered;
    .tst.mutate.out "  not assessed  ",string s`notAssessed;
    .tst.mutate.out "";
    .tst.mutate.out "  Mutation score: ",.tst.mutate.showPercent[s`score],
        " (",string[s[`killed]+s`timedOut]," of ",string[s[`killed]+s[`timedOut]+s[`survived]+s`notCovered]," mutants detected)";
    if[0<s`notCovered;
        .tst.mutate.out "  In functions the tests call: ",.tst.mutate.showPercent s`coveredScore];

    if[count rows: mutants where st=`survived;
        .tst.mutate.out "";
        .tst.mutate.out "SURVIVED (",string[count rows],"): the tests pass with this change in place";
        .tst.mutate.out each .tst.mutate.listMutants[fns;rows]];
    if[count rows: mutants where st=`timeout;
        .tst.mutate.out "";
        .tst.mutate.out "TIMED OUT (",string[count rows],"): counted as detected; the change made a test run far longer";
        .tst.mutate.out each .tst.mutate.listMutants[fns;rows]];
    if[count rows: mutants where st in `uncovered`unloaded;
        .tst.mutate.out "";
        .tst.mutate.out "NOT COVERED (",string[count rows],"): no usable test file calls these functions by name";
        .tst.mutate.out each .tst.mutate.listFunctions[fns;rows]];
    if[count rows: mutants where st=`unmatched;
        .tst.mutate.out "";
        .tst.mutate.out "NOT ASSESSED (",string[count rows],"): the function in memory is not the definition in the file";
        .tst.mutate.out each .tst.mutate.listFunctions[fns;rows]];
    if[count rows: mutants where st=`unapplied;
        .tst.mutate.out "";
        .tst.mutate.out "NOT ASSESSED (",string[count rows],"): the function was not in place when the tests ran";
        .tst.mutate.out each .tst.mutate.listFunctions[fns;rows]];
    if[count rows: mutants where st=`error;
        .tst.mutate.out "";
        .tst.mutate.out "NOT ASSESSED (",string[count rows],"): the run failed without the mutant in place (unstable test or environment)";
        .tst.mutate.out each .tst.mutate.listMutants[fns;rows]];
    if[count changes;
        .tst.mutate.out "";
        .tst.mutate.out "FILES CHANGED (",string[count changes],"): in the working directory while mutants ran; nothing was undone";
        .tst.mutate.out each .tst.mutate.listChanges[mutants;fns;changes]];
    s
 };

.tst.mutate.writeJson:{[mutants;fns;base;summary;changes]
    / q creates the directory when it writes the file.
    out: .resq.util.normalizePath @[get; `.resq.config.outDir; "."];
    doc: `schemaVersion`kind`framework`frameworkVersion`generatedAt`summary`testFiles`filesChanged`mutants!(
        1j; "resq-mutation-report"; "resQ"; .tst.toString @[get; `.resq.VERSION; {"unknown"}];
        .tst.isoTimestamp .z.P; summary;
        {[r] `file`usable`reason!(.tst.mutate.display r`file; r`usable; r`why)} each base;
        {[c] `path`change`mutants!(c`path; string c`change; c`mutants)} each changes;
        {[fns;i;m]
            `id`file`line`column`function`mutator`description`status`killedBy!(
                i; .tst.mutate.display fns[`file] m`fnIdx; m`line; m`col; string fns[`name] m`fnIdx;
                string m`family; m`note; string m`status; .tst.mutate.display m`killedBy)
        }[fns]'[til count mutants; mutants]);
    path: out,"/mutation-report.json";
    (hsym `$path) 0: enlist .tst.output.strictJson doc;
    .tst.mutate.out "Mutation report written to: ",path;
 };

/ ----------------------------------------------------------------------------
/ Entry point
/ ----------------------------------------------------------------------------

/ The test files to run: those under `paths`, or under tests/ when none are
/ named. A path that does not exist is an error, not an empty result.
.tst.mutate.testFiles:{[paths]
    if[0=count paths;
        if[not .resq.util.isDir "tests"; '"there is no tests/ directory here; name the tests with -tests PATHS"];
        paths: enlist "tests"];
    missing: paths where not (.resq.util.isFile each paths) or .resq.util.isDir each paths;
    if[count missing; '"test path not found: ",", " sv missing];
    files: asc .resq.util.pathToString each .tst.findTests paths;
    if[0=count files; '"no test files found under: ",", " sv paths];
    files
 };

/ What a command line selects: the functions, their mutants, how many mutants
/ there were before -max-mutants, and the test files to run them against.
.tst.mutate.select:{[args]
    if[0=count args; '"name the source to mutate, for example: resq mutate src/pricing.q"];
    families: .tst.mutate.chosenFamilies .tst.app.mutators;
    testFiles: .tst.mutate.testFiles .tst.app.mutationTests;
    sources: raze .tst.mutate.expandTarget[testFiles] each .tst.mutate.parseTarget each args;
    if[0=count sources; '"no source files to mutate under: ",", " sv args];
    ref: .tst.app.mutationSince;
    since: $[count ref;
        [.tst.mutate.requireRevision ref;
         (`$sources`path)!.tst.mutate.changedLines[ref] each sources`path];
        ()];
    found: .tst.mutate.gather[sources;families;since];
    fns: found`functions;
    mutants: found`mutants;
    total: count mutants;
    / -max-mutants: that many, evenly spaced, and never more than there are.
    limit: .tst.app.maxMutants;
    n: $[limit>0; limit&total; total];
    mutants: mutants "j"$floor (til n)*total%n;
    / Only the functions that still have a mutant are probed and reported.
    if[count mutants;
        used: asc distinct mutants`fnIdx;
        fns: fns used;
        mutants: update fnIdx:used?fnIdx from mutants];
    `functions`mutants`total`testFiles!(fns; mutants; total; testFiles)
 };

.tst.mutate.run:{[args]
    chosen: .tst.mutate.select args;
    fns: chosen`functions;
    mutants: chosen`mutants;
    testFiles: chosen`testFiles;
    ref: .tst.app.mutationSince;
    .tst.mutate.out "Mutation testing";
    if[0=count mutants;
        .tst.mutate.out "  Nothing to mutate: no named function with a mutable construct in ",
            $[count ref; "the lines changed since ",ref; "the selected source"],".";
        :.resq.EXIT.PASS];
    .tst.mutate.out "  Source: ",string[count distinct fns`file]," file(s), ",string[count fns],
        " function(s), ",string[count mutants]," mutant(s)",
        $[count ref; " on lines changed since ",ref; ""],
        $[chosen[`total]>count mutants; ", an even sample of ",string[chosen`total]," (-max-mutants)"; ""];
    .tst.mutate.requireTools[];
    .tst.mutate.parent: 1b;
    cap: "j"$@[get; `.tst.app.isolateTimeout; .tst.mutate.childLimit];

    .tst.mutate.out "  Tests:  ",string[count testFiles]," file(s), each first run on its own without a mutant";
    .tst.mutate.tick "  ";
    base: .tst.mutate.baseline[testFiles;fns;.tst.isolate.workerCount count testFiles;cap];
    .tst.mutate.tick "\n";
    unusable: base where not base`usable;
    if[count unusable;
        .tst.mutate.out "  ",string[count unusable]," test file(s) left out, because a failure there would not be the mutant's doing:";
        {[r] .tst.mutate.out "    ",.tst.mutate.display[r`file],": ",r`why;} each unusable];
    if[not any base`usable;
        .tst.mutate.out "";
        .tst.mutate.out (last unusable)`tail;
        '"no test file passes on its own, so nothing can be assessed"];

    / A failing test ends a mutant run: one failure is all a kill needs. A
    / mutant stuck in a loop ignores the first signal, so follow it up quickly.
    .tst.app.failFast: 1b;
    .tst.isolate.killAfter: 1;
    if[not .tst.mutate.inGit[];
        .tst.mutate.out "  Not a git checkout: files a mutant writes or deletes here cannot be listed"];
    .tst.mutate.out "  Running mutants (. killed, S survived, T timed out, - not applied, E error)";
    .tst.mutate.tick "  ";
    ran: .tst.mutate.execute[mutants;fns;base;.tst.isolate.workerCount count mutants;cap];
    mutants: ran`mutants;
    .tst.mutate.tick "\n";

    summary: .tst.mutate.report[mutants;fns;base;ran`changes];
    if[`json in .tst.app.reportFormats; .tst.mutate.writeJson[mutants;fns;base;summary;ran`changes]];
    minimum: .tst.app.mutationMin;
    if[not null minimum;
        if[(null summary`score) or minimum>summary`score;
            .tst.mutate.out "";
            .tst.mutate.out "Mutation score ",.tst.mutate.showPercent[summary`score]," is below the required ",string[minimum],"%.";
            :.resq.EXIT.FAIL];
        / The score leaves out mutants that could not be assessed. A gate
        / must not pass on what is missing: with 11 of 12 mutants unassessed,
        / "100% (1 of 1)" is no evidence about the other eleven. For the gate
        / they count as undetected.
        detected: summary[`killed]+summary`timedOut;
        worstCase: .tst.mutate.percent[detected; summary[`mutants]];
        if[(0<summary`notAssessed) and minimum>worstCase;
            .tst.mutate.out "";
            .tst.mutate.out "Mutation score ",.tst.mutate.showPercent[summary`score],
                " leaves out ",string[summary`notAssessed]," mutant(s) that could not be assessed.",
                " Counting them as undetected gives ",.tst.mutate.showPercent[worstCase],
                ", below the required ",string[minimum],"%.";
            :.resq.EXIT.FAIL]];
    .resq.EXIT.PASS
 };

.tst.mutate.main:{[args]
    outcome: @[{[a] (1b; .tst.mutate.run a)}; args; {[e] (0b; e)}];
    if[first outcome; :last outcome];
    .tst.mutate.err "MUTATION ERROR: ",last outcome;
    .resq.EXIT.FAIL
 };
