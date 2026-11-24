/ lib/load_graph.q - Which file loads which, for watch mode
/ ============================================================================
/ Watch mode reruns the tests that load a changed file. q has no hook that
/ reports a load, so the graph is read from source text. Two rules keep it from
/ silently missing a dependency:
/ .
/   1. Any literal naming a .q file is a dependency. A string or symbol literal
/      in executable code whose text ends in ".q" becomes an edge to every
/      tracked file whose path ends with it. This needs no knowledge of the
/      function that consumes the literal, so `\l src/a.q`, `system "l src/a.q"`,
/      `.lib.load "src/a.q"` and `.lib.load each ("src/a.q";"src/b.q")` all
/      resolve. Matching by path suffix over-approximates (a relative path is
/      resolved against a working directory the text does not show), which can
/      only run more tests, never fewer.
/ .
/   2. A load whose target is not such a literal is recorded as unresolved, and
/      the file containing it is `dynamic`. Watch mode reruns every test that
/      reaches a dynamic file on any source change. A computed load inside a
/      NAMED function (`.lib.load:{[p] system "l ",p}`) does not make the file
/      dynamic: the function is treated as a loader and its call sites are
/      judged instead, to a fixed point, so a project's own loader is found
/      without configuration when it is defined in a tracked file.
/ .
/ What this cannot see: a loader defined outside the tracked files and not
/ named in `loaders` (its calls with non-literal targets look like ordinary
/ calls), and loads driven by data rather than code. docs/WATCH.md states the
/ limits for users.
/ ============================================================================

.resq.require .resq.PKGLOADING,"/static_analysis.q"

.tst.loadGraph.idChars: .Q.a,.Q.A,.Q.n,"._";
.tst.loadGraph.symChars: .tst.loadGraph.idChars,":/";

/ Functions that load the path they are given. resQ's own, plus qutil's.
.tst.loadGraph.builtinLoaders: (".utl.require";".resq.require";".tst.loadSource";".tst.sysl";".utl.loadQFile");

/ Line classes: 0 lone "/", 1 lone "\", 2 anything else.
/ Line state: the number of open block comments (q nests them), 0 in code,
/ -1 after the script terminator.
.tst.loadGraph.lineStep:{[state;class]
    $[state < 0; state;
      class = 0; state + 1;
      class = 1; $[state = 0; -1; state - 1];
      state]
 };
/ Character classes: 0 quote, 1 backslash, 2 comment slash, 3 newline, 4 other.
/ Character states: 0 code, 1 string, 2 string after a backslash, 3 comment.
.tst.loadGraph.charTransitions: (1 0 3 0 0;0 2 1 1 1;1 1 1 1 1;3 3 3 0 3);

/ canonical path (symbol) -> (fingerprint; lexed file; literal scan; loader
/ names already scanned for; one call scan per such name). An unchanged file is
/ never lexed twice, and never rescanned for a loader name it has seen.
.tst.loadGraph.cache: (`symbol$())!();

.tst.loadGraph.reset:{[] .tst.loadGraph.cache:: (`symbol$())!(); };

/ ----------------------------------------------------------------------------
/ Lexing
/ ----------------------------------------------------------------------------

.tst.loadGraph.rstrip:{[s]
    keep: where not s in " \t\r";
    $[count keep; (1+last keep)#s; ""]
 };

.tst.loadGraph.emptyLex:{[]
    `txt`code`opens`closes`lead`starts`nsPos`nsName`loads`unreadable!
        ("";"";`long$();`long$();`boolean$();enlist 0j;`long$();();();0b)
 };

/ Lex a file given as the list of lines read0 returns.
/   txt     source joined by "\n", with block comments, text after the script
/           terminator and "\cmd" lines emptied (line numbers are preserved)
/   code    txt with string contents and comments blanked; both quotes of a
/           string are kept so a literal's extent is visible
/   opens   offsets of opening quotes; closes: offsets of the matching quotes
/   lead    1b at a backslash that escapes the next string character
/   starts  offset of each line's first character
/   nsPos, nsName   offsets where the namespace changes (\d, top-level
/           system "d ns") and the namespace in force from there ("" is root)
/   loads   targets of "\l target" lines
.tst.loadGraph.lex:{[lines]
    lx: .tst.loadGraph.emptyLex[];
    lines: $[10h=type lines; enlist lines; lines];
    if[0=count lines; :lx];
    if["#!"~2 sublist first lines; lines[0]: ""];

    / Whole-line structure first: q decides block comments, the terminator and
    / system commands per line, before it looks at any character.
    stripped: .tst.loadGraph.rstrip each lines;
    lineClass: ?[stripped~\:enlist "/"; 0; ?[stripped~\:enlist "\\"; 1; 2]];
    after: .tst.loadGraph.lineStep\[0; lineClass];
    live: (0=0, -1 _ after) and lineClass=2;
    sys: live and lines like "\\*";
    sysIdx: where sys;
    sysLines: lines sysIdx;
    isLoad: $[count sysIdx; sysLines like "\\l *"; `boolean$()];
    isNs: $[count sysIdx; sysLines like "\\d *"; `boolean$()];
    lx[`loads]: {first " " vs trim 3 _ x} each sysLines where isLoad;
    nsLine: sysIdx where isNs;
    nsName: {n: trim 3 _ x; $[n~enlist "."; ""; n]} each sysLines where isNs;

    dead: where not live and not sys;
    lines[dead,sysIdx]: (count dead,sysIdx)#enlist "";
    txt: "\n" sv lines;
    starts: 0, -1 _ sums 1+count each lines;
    lx[`starts]: starts;
    lx[`nsPos]: starts nsLine;
    lx[`nsName]: nsName;
    if[0=count txt; :lx];

    cls: "\"\\/\n"?txt;
    slashOk: 1b, (-1 _ txt) in " \t\n";
    cls[where (cls=2) and not slashOk]: 4;
    st: 0, -1 _ .tst.loadGraph.charTransitions\[0; cls];
    closes: where (st=1) and cls=0;
    opens: (count closes)#where (st=0) and cls=0;
    keep: ((st=0) and cls<>2) or ((st=1) and cls=0) or (st=3) and cls=3;
    code: ?[keep; txt; " "];
    lx[`txt`code`opens`closes`lead]: (txt; code; opens; closes; (st=1) and cls=1);

    / `system "d .ns"` at top level switches namespace exactly as \d does.
    cand: where ("d"=txt opens+1) and " "=txt opens+2;
    if[count cand;
        / A quote is not a brace, so the depth at it is the depth around it.
        brace: sums (code="{")-code="}";
        cand: cand where (0=brace opens cand) and .tst.loadGraph.afterSystem[code] each opens cand;
        if[count cand;
            names: {n: trim 1 _ x; $[n~enlist "."; ""; n]} each .tst.loadGraph.literal[lx] each cand;
            pos: lx[`nsPos], opens cand;
            order: iasc pos;
            lx[`nsPos]: pos order;
            lx[`nsName]: (lx[`nsName], names) order]];
    lx
 };

/ Unescaped text of the i-th string literal.
.tst.loadGraph.literal:{[lx;i]
    o: lx[`opens] i;
    idx: (o+1)+til -1+lx[`closes][i]-o;
    lx[`txt][idx] where not lx[`lead] idx
 };

/ True when `system` appears shortly before offset p, as in `system "l x"`,
/ `system["l x"]` or `@[system;"l x";handler]`.
.tst.loadGraph.afterSystem:{[code;p]
    lo: 0|p-30;
    0<count (code lo+til p-lo) ss "system"
 };

/ Namespace in force at an offset ("" is root).
.tst.loadGraph.nsAt:{[lx;pos]
    i: lx[`nsPos] bin pos;
    $[i<0; ""; lx[`nsName] i]
 };

/ Source line containing an offset, as "line N: text", for diagnostics.
.tst.loadGraph.lineOf:{[lx;pos]
    starts: lx`starts;
    ln: starts bin pos;
    stop: $[(ln+1)<count starts; -1+starts ln+1; count lx`txt];
    text: trim lx[`txt] starts[ln]+til stop-starts ln;
    "line ", string[ln+1], ": ", $[70<count text; (67#text),"..."; text]
 };

/ Bracket depths and statement boundaries, computed only for a file that has a
/ load site to judge.
.tst.loadGraph.context:{[lx]
    code: lx`code;
    depth: sums (code in "([{")-code in ")]}";
    brace: sums (code="{")-code="}";
    isNl: code="\n";
    / A newline ends a statement unless the next line is indented.
    stmtNl: isNl and not 1 _ (code in " \t"), 0b;
    lx, `dBefore`bBefore`isNl`stops!
        (0i, -1 _ depth; 0i, -1 _ brace; isNl; where (code in ";)]}") or stmtNl)
 };

/ ----------------------------------------------------------------------------
/ Judging one load site
/ ----------------------------------------------------------------------------

/ First offset at or after `lo` that ends the expression opened at bracket
/ depth D: a ";" or a closing bracket at that depth, or at top level a newline
/ that ends the statement. Inside brackets a newline is only whitespace.
.tst.loadGraph.stopAt:{[cx;lo;D]
    c: cx`stops;
    c: c where c>=lo;
    c: c where (D=cx[`dBefore] c) and (D=0) or not cx[`isNl] c;
    $[count c; first c; count cx`code]
 };

/ Offset of the last character before `upto` that is not in `skip`; null when
/ there is none. Indexing with a null gives a blank, so callers can test the
/ character there without a bounds check.
.tst.loadGraph.lastNot:{[code;upto;skip] last where not (upto#code) in skip};

/ Offset of the first character at or after `from` that is not in `skip`; the
/ length of the text when there is none.
.tst.loadGraph.firstNot:{[code;from;skip] from+((from _ code) in skip)?0b};

/ The literal that ends the expression in [lo;stop), if it ends with one.
/ A load's target is whatever its argument evaluates to, and that value ends
/ with the last literal only when nothing but closing brackets follows it.
.tst.loadGraph.finalLiteral:{[cx;lo;stop]
    code: cx`code;
    none: `kind`text`open!(`none;"";0N);
    part: code lo+til stop-lo;
    j: lo+last where not part in " \t\n)]}";
    if[null j; :none];
    if["\""=code j;
        i: cx[`closes]?j;
        if[i=count cx`closes; :none];
        :`kind`text`open!(`str; .tst.loadGraph.literal[cx;i]; cx[`opens] i)];
    / A symbol is a backtick followed by symbol characters up to j.
    k: lo+last where not ((1+j-lo)#part) in .tst.loadGraph.symChars;
    if[not "`"=code k; :none];
    `kind`text`open!(`sym; code (k+1)+til j-k; k)
 };

/ True when the literal opening at offset o is joined onto something before
/ it (`root,"/src/x.q"`), so only the END of the path is known.
.tst.loadGraph.isTail:{[cx;o]
    code: cx`code;
    ","=code .tst.loadGraph.lastNot[code;o;" \t\n"]
 };

/ Verdict on a target literal: (`ok;"") when ordinary literal matching already
/ covers it, (`ok;text) when it must be matched as a raw suffix, (`dyn;"")
/ when the file it names cannot be known. Anything not ending in ".q" is a
/ package or module name whose mapping to a file belongs to the loader; that
/ includes "no literal at all", whose text is empty.
.tst.loadGraph.judgeTarget:{[cx;fin]
    t: trim fin`text;
    if[not t like "*.q"; :(`dyn;"")];
    if[.tst.loadGraph.isTail[cx;fin`open];
        / `prefix,"_impl.q"`: only the end of the name is known, so it is
        / matched as raw characters. A bare ".q" would match every file, which
        / is no knowledge at all.
        :$[2<count t; (`ok;t); (`dyn;"")]];
    (`ok;"")
 };

/ True when the token at offset p is the first argument of @[...] or .[...],
/ the protected-evaluation idiom whose NEXT argument is the load target.
.tst.loadGraph.firstApplyArg:{[cx;p]
    code: cx`code;
    j: .tst.loadGraph.lastNot[code;p;" \t\n"];
    (code[j]="[") and code[j-1] in "@."
 };

/ Judge a loader name occupying [p;e): (`def;"") for its own definition,
/ otherwise judgeTarget's verdict on the argument.
.tst.loadGraph.classifyCall:{[cx;p;e]
    code: cx`code;
    if[":"=code .tst.loadGraph.firstNot[code;e;" \t"]; :(`def;"")];
    D: cx[`dBefore] p;
    stop: .tst.loadGraph.stopAt[cx;e;D];
    / `@[loader; target; handler]`: the name is followed at once by ";", and
    / the target is the next argument.
    if[(all code[e+til stop-e] in " \t\n") and code[stop]=";";
        if[.tst.loadGraph.firstApplyArg[cx;p];
            e: stop+1;
            stop: .tst.loadGraph.stopAt[cx;e;D]]];
    .tst.loadGraph.judgeTarget[cx; .tst.loadGraph.finalLiteral[cx;e;stop]]
 };

/ Qualified name a lambda opening at offset `open` is assigned to, or "" when
/ it is not the right-hand side of a plain `name:{` or `name::{`.
.tst.loadGraph.definedName:{[cx;open]
    code: cx`code;
    j: .tst.loadGraph.lastNot[code;open;" \t"];
    if[not ":"=code j; :""];
    if[":"=code j-1; j-: 1];
    / The name ends at e and starts at b, after the last character before e
    / that cannot be part of a name. If the character at e cannot either, the
    / text taken is not a valid name and is refused below.
    e: .tst.loadGraph.lastNot[code;j;" \t"];
    if[null e; :""];
    b: 0^1+.tst.loadGraph.lastNot[code;e;.tst.loadGraph.idChars];
    name: code b+til 1+e-b;
    if[not .tst.static.validFunctionName name; :""];
    if["`"=code b-1; :""];
    ns: .tst.loadGraph.nsAt[cx;b];
    $["."=first name; name; count ns; ns,".",name; name]
 };

/ True when nothing but a ";" or a comment follows the closing brace at offset
/ `close` on its line: the lambda is then the whole value being assigned.
.tst.loadGraph.endsStatement:{[code;close]
    rest: (close+1) _ code;
    rest: trim (rest?"\n")#rest;
    (0=count rest) or ";"=first rest
 };

/ Qualified name of the function whose body contains offset p, or "" when p is
/ at top level or inside a lambda that is not simply assigned to a name.
/ `name:{...} each x` and `name:{...}[x]` run the lambda where they stand, so
/ a load inside one is a load of this file, not of some later caller.
.tst.loadGraph.enclosingName:{[cx;p]
    if[0>=cx[`bBefore] p; :""];
    code: cx`code;
    tops: where (code="{") and 0=cx`bBefore;
    open: tops tops bin p;
    closes: where (code="}") and 1=cx`bBefore;
    at: closes binr open;
    if[at=count closes; :""];
    if[not .tst.loadGraph.endsStatement[code; closes at]; :""];
    .tst.loadGraph.definedName[cx;open]
 };

/ ----------------------------------------------------------------------------
/ Scanning a file
/ ----------------------------------------------------------------------------

.tst.loadGraph.emptyScan:{[]
    `mentions`rawMentions`dirLoads`dyn`promote!(();();();`long$();())
 };

/ Reduce a path literal to the components a tracked path must END with.
/ Leading "./" and "../" depend on a directory the text does not show, so they
/ are dropped; interior ones are resolved.
.tst.loadGraph.normalize:{[s]
    s: trim s;
    if[(count s) and ":"=first s; s: 1 _ s];
    step: {[acc;p]
        $[p~".."; $[count acc; -1 _ acc; acc];
          (p~enlist ".") or 0=count p; acc;
          acc, enlist p]};
    "/" sv step/[(); "/" vs s]
 };

/ Record an unresolved load at offset `at`: promote the enclosing named
/ function to a loader, or mark the file dynamic when there is none.
.tst.loadGraph.unresolved:{[cx;acc;at]
    name: .tst.loadGraph.enclosingName[cx;at];
    $[count name; acc[`promote],: enlist name; acc[`dyn],: at];
    acc
 };

/ One `system "l ..."` / `value "\l ..."` literal: item is (literal index;
/ unescaped text; 1b for the value form).
.tst.loadGraph.systemLoad:{[cx;acc;item]
    code: cx`code;
    o: cx[`opens] item 0;
    body: trim $[item 2; 3; 1] _ item 1;
    a: .tst.loadGraph.firstNot[code; 1+cx[`closes] item 0; " \t"];
    if[not ","=code a;
        / The whole target is in this literal. A target that is not a .q file
        / may be a directory, whose scripts q runs on load.
        $[body like "*.q"; acc[`mentions],: enlist body;
          count body; acc[`dirLoads],: enlist (body;0b);
          ::];
        :acc];
    / The target is joined together; its last literal is all that is fixed.
    / A tail naming a .q file is matched as raw characters (a tail that begins
    / with "/" then matches whole components). Any other tail may end the name
    / of a directory. No tail, an empty one or a bare ".q" fixes nothing.
    fin: .tst.loadGraph.finalLiteral[cx; a; .tst.loadGraph.stopAt[cx;a;cx[`dBefore] o]];
    t: trim fin`text;
    ok: 1b;
    $[not t like "*.q"; $[count t; acc[`dirLoads],: enlist (t; not "/"=first t); ok: 0b];
      2<count t; acc[`rawMentions],: enlist t;
      ok: 0b];
    $[ok; acc; .tst.loadGraph.unresolved[cx;acc;o]]
 };

/ Everything about a file that does not depend on which names are loaders:
/ path literals, `\l` lines and `system "l ..."` loads.
.tst.loadGraph.scanLiterals:{[lx]
    out: .tst.loadGraph.emptyScan[];
    txt: lx`txt;
    code: lx`code;
    o: lx`opens;
    c: lx`closes;
    / Only a literal naming a .q file is a mention: a tracked file can match
    / nothing else. The bare extension ".q" names no file.
    isQ: {x like "*.q"} each lx`loads;
    mentions: lx[`loads] where isQ;
    if[count o;
        ends: where (3<c-o) and ("q"=txt c-1) and "."=txt c-2;
        mentions,: .tst.loadGraph.literal[lx] each ends];
    tick: where code="`";
    if[count tick;
        stops: (where not code in .tst.loadGraph.symChars), count code;
        last1: stops stops binr tick+1;
        keep: where (3<last1-tick) and ("q"=code last1-1) and "."=code last1-2;
        mentions,: {[code;b;e] code (b+1)+til -1+e-b}[code]'[tick keep; last1 keep]];
    out[`mentions]: mentions;
    / `\l target` where the target is not a .q file may load a directory.
    if[count lx`loads;
        other: lx[`loads] where not isQ;
        out[`dirLoads]: {(x;0b)} each other where 0<count each other];

    if[count o;
        cand: where (txt o+1) in "l\\";
        if[count cand;
            texts: .tst.loadGraph.literal[lx] each cand;
            isValue: texts like "\\l *";
            isSystem: ((texts like "l *") or texts~\:enlist "l") and
                .tst.loadGraph.afterSystem[code] each o cand;
            keep: where isValue or isSystem;
            if[count keep;
                cx: .tst.loadGraph.context lx;
                out: .tst.loadGraph.systemLoad[cx]/[out; flip (cand keep; texts keep; isValue keep)]]]];

    out[`mentions]: distinct .tst.loadGraph.normalize each out`mentions;
    out
 };

/ Offsets where `name` occurs as a whole identifier, not inside a symbol.
.tst.loadGraph.tokenAt:{[code;name]
    ps: "j"$code ss name;
    ps where (not code[ps-1] in .tst.loadGraph.idChars,"`") and
        not code[ps+count name] in .tst.loadGraph.idChars
 };

/ [start;end) extents where a loader is named: its qualified name anywhere,
/ and its bare name where the namespace in force makes that the same function.
.tst.loadGraph.occurrences:{[lx;name]
    code: lx`code;
    ps: .tst.loadGraph.tokenAt[code;name];
    / A name with no namespace is that function only at root.
    if[not "."=first name; ps: ps where 0=count each .tst.loadGraph.nsAt[lx] each ps];
    res: ps,'ps+count name;
    dots: where name=".";
    if[1<count dots;
        ns: (last dots)#name;
        bare: (1+last dots) _ name;
        bs: .tst.loadGraph.tokenAt[code;bare];
        bs: bs where ns~/:.tst.loadGraph.nsAt[lx] each bs;
        res,: bs,'bs+count bare];
    res
 };

/ Judge every call of the named loaders in a file. Returns one scan per name,
/ so a name is scanned once per file however far the loader set later grows.
.tst.loadGraph.scanCalls:{[lx;names]
    none: (count names)#enlist .tst.loadGraph.emptyScan[];
    sites: .tst.loadGraph.occurrences[lx] each names;
    / Most files call no loader: skip the bracket analysis for them.
    if[0=sum count each sites; :none];
    cx: .tst.loadGraph.context lx;
    step: {[cx;acc;site]
        verdict: .tst.loadGraph.classifyCall[cx;site 0;site 1];
        if[`def~first verdict; :acc];
        if[`ok~first verdict;
            if[count last verdict; acc[`rawMentions],: enlist last verdict];
            :acc];
        .tst.loadGraph.unresolved[cx;acc;site 0]};
    {[step;cx;found] step[cx]/[.tst.loadGraph.emptyScan[];found]}[step;cx] each sites
 };

/ ----------------------------------------------------------------------------
/ Building the graph
/ ----------------------------------------------------------------------------

.tst.loadGraph.canonical:{[cwd;p]
    s: .utl.pathToString p;
    .utl.normalizePath $["/"=first s; s; cwd,"/",s]
 };

/ Loader names as a list of strings, from a string, symbol or list of either.
.tst.loadGraph.names:{[v]
    $[10h=type v; enlist v;
      -11h=type v; enlist string v;
      11h=type v; string each v;
      0h=type v; {$[10h=type x; x; string x]} each v;
      ()]
 };

/ Cached (lexed file; literal scan) for a path, re-read when its fingerprint
/ changes. A file that exists but cannot be read is unknown, hence dynamic.
.tst.loadGraph.lexFile:{[path;fingerprint]
    k: `$path;
    if[k in key .tst.loadGraph.cache;
        if[fingerprint~first .tst.loadGraph.cache k; :.tst.loadGraph.cache[k] 1 2]];
    lines: @[read0; hsym k; {[e] `unreadable}];
    lx: $[`unreadable~lines; .tst.loadGraph.emptyLex[]; .tst.loadGraph.lex lines];
    if[`unreadable~lines; lx[`unreadable]: .utl.pathExists path];
    lits: .tst.loadGraph.scanLiterals lx;
    .tst.loadGraph.cache[k]: (fingerprint; lx; lits; (); ());
    (lx; lits)
 };

/ Call scan for a path over the given loader names, as one merged scan. Only
/ names this file has not been scanned for are scanned.
.tst.loadGraph.callsFor:{[names;path]
    k: `$path;
    entry: .tst.loadGraph.cache k;
    missing: names where not names in entry 3;
    if[count missing;
        entry[4]: entry[4], .tst.loadGraph.scanCalls[entry 1; missing];
        entry[3]: entry[3], missing;
        .tst.loadGraph.cache[k]: entry];
    raze each flip entry[4] entry[3]?names
 };

/ True when path p ends with the characters in `need`.
.tst.loadGraph.endsWith:{[need;p] (count[need]<=count p) and need~(neg count need)#p};

/ Indices of paths ending with the path components in m. Only paths with the
/ same file name are compared.
.tst.loadGraph.matchPath:{[paths;byBase;m]
    cand: byBase `$last "/" vs m;
    cand where .tst.loadGraph.endsWith["/",m] each paths cand
 };

/ Indices of paths ending with the characters in m.
.tst.loadGraph.matchSuffix:{[paths;m]
    where .tst.loadGraph.endsWith[m] each paths
 };

/ Build the graph for the tracked files.
/   tracked       paths as the caller knows them (symbols)
/   fingerprints  one value per path that changes when the file does
/   loaders       extra loader function names (strings)
/ Returns:
/   tracked, paths   the input paths and their canonical absolute form
/   deps     per file, indices of the files it loads
/   rev      per file, indices of the files that load it
/   dynamic  per file, 1b when it has a load that could not be resolved
/   why      per file, one line of explanation per unresolved load
/   loaders  the loader names in force, including discovered ones
.tst.loadGraph.build:{[tracked;fingerprints;loaders]
    cwd: system "cd";
    paths: .tst.loadGraph.canonical[cwd] each tracked;
    n: count paths;
    if[0=n;
        :`tracked`paths`deps`rev`dynamic`why`loaders!(tracked;paths;();();`boolean$();();
            distinct .tst.loadGraph.builtinLoaders,loaders)];
    pairs: .tst.loadGraph.lexFile'[paths;fingerprints];
    lexes: pairs[;0];
    scans: pairs[;1];
    / Forget files that are no longer tracked.
    .tst.loadGraph.cache:: (distinct `$paths)#.tst.loadGraph.cache;

    / A computed load inside a named function makes that function a loader,
    / whose own calls are then judged. Names only ever get added and there are
    / finitely many named functions, so this ends.
    names: distinct .tst.loadGraph.builtinLoaders, loaders, raze scans[;`promote];
    calls: .tst.loadGraph.callsFor[names] each paths;
    while[count fresh: (distinct raze calls[;`promote]) except names;
        names,: fresh;
        calls: .tst.loadGraph.callsFor[names] each paths];

    byBase: group `$last each "/" vs/: paths;
    dirs: distinct raze {[p] at: 1 _ where p="/"; at#\:p} each paths;
    resolve: {[paths;byBase;lits;call;i]
        hits: raze .tst.loadGraph.matchPath[paths;byBase] each lits`mentions;
        hits,: raze .tst.loadGraph.matchSuffix[paths] each lits[`rawMentions], call`rawMentions;
        (distinct "j"$hits) except i};
    deps: resolve[paths;byBase]'[scans;calls;til n];

    / A directory load runs the scripts in it, so one that names a tracked
    / directory is a dependency on files this graph cannot enumerate safely.
    / `dirs` above is every directory above a tracked file; `distinct` and
    / dropping the empty prefix only save comparisons.
    dirHit: {[dirs;lits]
        any {[dirs;target]
            d: .tst.loadGraph.normalize first target;
            / "." and ".." name a directory this text cannot place. It may well
            / be the one being watched, so it counts as one.
            if[0=count d; :1b];
            any .tst.loadGraph.endsWith[$[last target; d; "/",d]] each dirs
        }[dirs] each lits`dirLoads}[dirs] each scans;

    why: {[lx;lits;call;dirHit]
        r: distinct .tst.loadGraph.lineOf[lx] each asc lits[`dyn], call`dyn;
        if[lx`unreadable; r,: enlist "file could not be read"];
        if[dirHit; r,: enlist "loads a watched directory"];
        r}'[lexes;scans;calls;dirHit];

    src: raze (count each deps)#'til n;
    rev: @[n#enlist `long$(); raze deps; ,; src];
    `tracked`paths`deps`rev`dynamic`why`loaders!(tracked;paths;deps;rev;0<count each why;why;names)
 };

/ Indices of the files that load any seed, directly or through other files.
/ The seeds themselves are included.
.tst.loadGraph.loadedBy:{[g;seeds]
    seen: frontier: distinct "j"$seeds;
    while[count frontier;
        frontier: (distinct raze g[`rev] frontier) except seen;
        seen,: frontier];
    seen
 };
