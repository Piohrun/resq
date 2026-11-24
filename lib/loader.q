/ Strip trailing spaces and tabs from a string (no regex; pure char ops).
/ Robust against a single-char (atomic) argument.
.tst.rstrip:{[s]
    s: $[10h = type s; s; enlist s];
    i: where not s in " \t";
    $[0 = count i; ""; (1 + last i) # s]
 };

/ Preprocess a test file (a list of source lines, as read by read0) into a list
/ of lines safe for `value "\n" sv ...`. q's `value` cannot execute lines that
/ start with a backslash system command (\l, \d, \t, ...) - they fail with 'nyi.
/ This rewrites them to the equivalent `system "..."` call, which q treats
/ identically (e.g. system "l x" == \l x, CWD-relative resolution included),
/ and honours the `\` script terminator. Block comments are tracked so a
/ system-command-looking line inside one is never executed.
/ Rules (aligned EXACTLY with q's own `\l` lexer):
/   * A line that rstrips to exactly "/" ALWAYS opens a block comment (trailing
/     whitespace ignored, preceding line irrelevant - real q opens a block here
/     regardless of what came before). The block is terminated by a line that
/     rstrips to exactly "\"; if no such line exists, the block runs to EOF and
/     the rest of the file is comment (matching real q). Blocks NEST: a lone
/     "/" inside a block opens another level, and each lone "\" closes one, so
/     a commented-out region that itself contains a block comment stays
/     commented out. The whole block (the
/     "/", its interior, and the closing "\") is DROPPED: q's own `value` cannot
/     parse block comments, so emitting them verbatim would break loading.
/     Dropping is comment-equivalent and guarantees nothing inside the block -
/     including a fake \l - is executed.
/   * Outside a block comment, a column-1 "\" line:
/       - rstrips to exactly "\"  -> end of script: drop this and all following
/                                    lines.
/       - otherwise                -> rewrite "\cmd rest" to system "cmd rest"
/                                     (backslashes and quotes escaped).
/   * "/"-prefixed line comments ("/ text") and ordinary lines pass through.
/ Check order matters: inside a block we ONLY look for the closing "\".
/ Otherwise we test block-open (lone "/") BEFORE the terminator / system-command
/ rewrite - a lone "/" is never a system command, and a lone "\" outside a block
/ is the terminator, never a block close.
/ Canonical absolute+normalized form of a path. Absolutizes against the current
/ working directory when relative, then resolves "." / ".." segments. Two
/ different spellings of the same file (./x.q vs x.q vs an absolute path) all
/ collapse to one string here, so it is the right key for de-duplication and for
/ deriving a stable sandbox name.
.tst.canonicalPath:{[p]
    s: .resq.util.pathToString p;
    absPath: $["/" = first s; s; (system "cd"), "/", s];
    .resq.util.normalizePath absPath
 };

/ Load a q script the way `\l <path>` does, then (when coverage is enabled)
/ instrument the functions it just defined. preprocessScript rewrites a test
/ file's `\l <path>` to a call to this wrapper so that source-under-test loaded
/ with `\l` becomes visible to coverage (a bare `system "l ..."` is not). The
/ load runs FIRST - the definitions must exist before they can be wrapped - and
/ instrumentation is best-effort: a wrapping failure must never break the load
/ of correct user code. `path` is whatever followed "\l " (relative or
/ absolute); both `system "l"` and instrumentFile resolve it against the CWD the
/ same way, so it is passed through unchanged.
.tst.sysl:{[path]
    .resq.util.loadQFile path;
    if[1b ~ @[get; `.tst.coverageEnabled; 0b];
        if[`instrumentFile in key `.tst;
            @[.tst.instrumentFile; path; {[p;e]
                -1 "Coverage: could not instrument ", p, ": ", .tst.toString e
            }[path]];
        ];
    ];
 };

/ Rewrite an expectation constructor at the start of a source line to its
/ line-aware wrapper. q lambdas evaluated through `value` do not retain source
/ locations, so this lightweight load-time annotation is the only reliable way
/ to give CI reporters the declaration line. Strings/comments and ordinary q
/ expressions are untouched.
/ A desc body is one q lambda and q caps a lambda at ~237 distinct constants.
/ qspec spends two per declaration (description and body). A distinct line
/ number per Entry call made that three, so a desc stopped loading near 78
/ tests instead of qspec's ~118. For the high-volume constructors whose first
/ argument is a string literal, the line rides inside that literal as a
/ "\001<line>\001" prefix (stripped by the Entry wrapper) and the Entry
/ argument is the shared constant 0N. Other constructors keep the integer.
.tst.lineTaggedVerbs:("should";"it");

/ Constructor offsets come from native `ss` over the raw line, then keep only
/ offsets the lexer places in code before the first comment (scanning stops at
/ a comment, so later text is never annotated). The previous per-character
/ walk tested every verb at every offset. Verbs are identifiers followed by
/ "[", so two matches can never overlap and at most one verb fits an offset.
.tst.annotateExpectationLineWith:{[lineNo;line;shadowed]
    verbs: ("should";"it";"shouldEach";"holds";"perf";"skip";"pending";"skipIf";"retry";"testOnly");
    txt: (),line;
    if[0 = count txt; :""];
    lex: .tst.qLexStates txt;
    commentAt: first (where (0 = lex 0) and 2 = lex 1), count txt;
    code: (0 = lex 0) and (til count txt) < commentAt;
    found: raze {[txt;code;shadowed;verb]
        / "[[]" is a literal "[" in ss pattern syntax.
        ps: "j"$txt ss verb,"[[]";
        ps: ps where code ps;
        qualified: {[txt;at] (5 <= at) and ".tst." ~ 5 # (at - 5) _ txt}[txt] each ps;
        boundary: qualified or {[txt;at] (at = 0) or not txt[at - 1] in .Q.a,.Q.A,.Q.n,"_."}[txt] each ps;
        keep: boundary and not {[ctx;name;at] .tst.dslNameShadowed[ctx;name;at]}[shadowed;`$verb] each ps;
        {[verb;at;q] (at;verb;q)}[verb]'[ps where keep; qualified where keep]
      }[txt;code;shadowed] each verbs;
    if[0 = count found; :txt];
    found: found iasc found[;0];
    out: "";
    at: 0;
    k: 0;
    while[k < count found;
        hit: found k;
        verb: hit 1;
        out,: ((hit 0) - at) # at _ txt;
        / Enter through a unary guard before consuming the constructor
        / arguments. If the source supplies too few arguments q returns a
        / projection and silently discards it at the end of desc[]; the
        / entry/finish pair lets desc detect that lost declaration. For an
        / explicit .tst.holds[...] call, `.tst.` is already in the output;
        / preserve it and replace only the constructor name.
        after: (hit 0) + 1 + count verb;
        tagged: (verb in .tst.lineTaggedVerbs) and (after < count txt) and "\"" = txt after;
        out,: $[hit 2; verb; ".tst.",verb],$[tagged;
            "Entry[0N][\"\\001",string[lineNo],"\\001";
            "Entry[",string[lineNo],"]["];
        at: after + tagged;
        k+: 1];
    out, at _ txt
 };

.tst.annotateExpectationLine:{[lineNo;line]
    .tst.annotateExpectationLineWith[lineNo;line;()]
 };

/ Mask strings and inline comments while preserving character offsets. This is
/ intentionally lexical, not a q parser: it only protects the qualification
/ pass from treating prose/symbol literals as executable identifiers.
/ .
/ The lexer is a four-state machine run by q's native index scan, because the
/ loader masks every line several times and a per-character q loop dominated
/ suite load time. States: 0 code, 1 string, 2 string after a backslash,
/ 3 line comment. Character classes: 0 quote, 1 backslash, 2 comment slash
/ (a "/" at offset 0 or after a space, tab or newline), 3 newline, 4 anything
/ else. The newline matters when a whole multi-line statement is masked at
/ once: a "/" at the start of one of its lines is a comment line, as q reads it.
/ Quotes, code and the newline that ends a comment keep their character;
/ string contents and comments become spaces.
.tst.maskTransitions:(1 0 3 0 0;0 2 1 1 1;1 1 1 1 1;3 3 3 0 3);
.tst.maskKeeps:(11011b;10000b;00000b;00010b);
/ Returns (state before each character; character class) for a non-empty line.
.tst.qLexStates:{[txt]
    cls: "\"\\/\n" ? txt;
    slashOk: 1b, (-1 _ txt) in " \t\n";
    cls[where (cls = 2) and not slashOk]: 4;
    (0, -1 _ .tst.maskTransitions\[0; cls]; cls)
 };
.tst.maskQLine:{[line]
    txt: (),line;
    if[0 = count txt; :""];
    lex: .tst.qLexStates txt;
    keep: (raze .tst.maskKeeps) (5 * lex 0) + lex 1;
    .tst.maskSymbolBodies ?[keep; txt; count[txt] # " "]
 };

/ Blank the body of every symbol literal, keeping its backtick, in text whose
/ strings and comments are already blanked. A symbol is data: a resQ word
/ inside one (`:data/fixture/x.csv, `:out/after, `:host:5010:user:must) is
/ not a call. q's rule, checked against its tokenizer: after the backtick come
/ letters, digits, "_", "." and ":"; a "/" belongs to the symbol only once a
/ ":" has appeared in it (`:a/b is one symbol, `a/b is `a then an adverb).
/ Vector operations only: the loader masks whole desc blocks many times.
.tst.symbolBodyChars: .Q.an, ".:/";
.tst.maskSymbolBodies:{[txt]
    if[not "`" in txt; :txt];
    ok: txt in .tst.symbolBodyChars;
    first1: ok and not 0b, -1 _ ok;
    starts: where first1;                        / first character of each run
    anchored: "`" = txt starts - 1;             / runs that directly follow a backtick
    if[not any anchored; :txt];
    run: -1 + sums first1;                       / run index of each character
    inSymbol: ok and anchored run;
    colons: sums txt = ":";
    seenColon: colons > ((0, colons) starts) run;
    breaking: inSymbol and (txt = "/") and not seenColon;
    breaks: sums breaking;
    body: inSymbol and breaks = ((0, breaks) starts) run;
    ?[body; " "; txt]
 };

.tst.bareTokenAt:{[txt;at;name]
    n: count name;
    if[not name ~ n # at _ txt; :0b];
    leftOk: (0 = at) or not txt[at - 1] in .Q.a,.Q.A,.Q.n,"_.`";
    rightAt: at + n;
    rightOk: (rightAt = count txt) or not txt[rightAt] in .Q.a,.Q.A,.Q.n,"_";
    leftOk and rightOk
 };

/ A DSL-shaped identifier declared as a bare assignment or explicit lambda
/ parameter is user code, not framework syntax.
.tst.dslDeclarationPositions:{[masked;name]
    positions: masked ss name;
    if[0 = count positions; :`long$()];
    "j"$positions where {[txt;token;p]
        if[not .tst.bareTokenAt[txt;p;token]; :0b];
        after: p + count token;
        while[(after < count txt) and txt[after] in " \t"; after+: 1];
        if[(after < count txt) and ":" = txt after; :1b];
        if[(after + 1 < count txt) and txt[after] in "+-*%&|<>=~,^#_!?@." and ":" = txt[after + 1]; :1b];
        opens: (0 # 0j), where "{" = txt;
        opens: opens where opens < -1 + count txt;
        opens: opens where "[" = txt[1 + opens];
        relevant: opens where opens < p;
        if[0 = count relevant; :0b];
        openAt: last relevant;
        closes: (0 # 0j), where "]" = txt;
        closes: closes where closes > openAt;
        if[0 = count closes; :0b];
        p < first closes
    }[masked;name;] each positions
 };

.tst.dslLineDeclares:{[masked;name]
    0 < count .tst.dslDeclarationPositions[masked;name]
 };

/ Cheap compatibility scan used to keep the common loader path fast. Only files
/ that actually declare a DSL-shaped name pay for nested lexical scope ranges.
.tst.dslPotentialShadowedNames:{[lines]
    names:string key .tst.dslExports;
    maskedLines:.tst.maskQLine each lines;
    `$names where {[masked;name]
        any .tst.dslLineDeclares[;name] each masked
      }[maskedLines;] each names
 };

/ Mask strings, comments, block comments and text after a script terminator,
/ preserving every remaining character offset for lexical scope analysis.
.tst.dslMaskedSource:{[lines]
    source:.resq.util.pathToString each lines;
    out:enlist ();
    state:0;                   / open block comments; q nests them
    stopped:0b;
    i:0;
    while[i<count source;
        ln:source i;
        trimmed:.tst.rstrip ln;
        blank:count[ln]#" ";
        $[stopped;
            out,:enlist blank;
          state>0;
            [out,:enlist blank;
             state+:$[trimmed~enlist "/";1;trimmed~enlist "\\";-1;0]];
          trimmed~enlist "/";
            [out,:enlist blank;state:1];
          (0<count ln) and ("\\"=first ln) and trimmed~enlist "\\";
            [out,:enlist blank;stopped:1b];
          out,:enlist ln];
        i+:1];
    .tst.maskQLine "\n" sv 1 _ out
 };

/ Return nested lambda ranges. Root scope 0 covers the complete statement/file;
/ every `{...}` owns a child range. Strings/comments were masked beforehand.
.tst.dslScopes:{[masked]
    starts:enlist 0j;
    ends:enlist "j"$count masked;
    parents:enlist -1j;
    stack:enlist 0j;
    i:0;
    while[i<count masked;
        c:masked i;
        if[c="{";
            scopeId:"j"$count starts;
            starts,:i;
            ends,:"j"$count masked;
            parents,:last stack;
            stack,:scopeId];
        if[(c="}") and 1<count stack;
            closeId:last stack;
            ends[closeId]:i+1;
            stack:-1 _ stack];
        i+:1];
    flip `scope`start`end`parent!("j"$til count starts;starts;ends;parents)
 };

.tst.dslScopeAt:{[scopes;position]
    active:where (scopes[`start]<=position) and position<scopes`end;
    $[count active;"j"$last scopes[`scope] active;0j]
 };

/ Map each fixed DSL identifier declaration to the innermost lambda that owns
/ it. q determines locals for the whole lambda, so the complete range is marked
/ even when the assignment appears after an earlier use in that same lambda.
.tst.dslScopeRanges:{[masked;scopes]
    names:string key .tst.dslExports;
    rows:();
    i:0;
    while[i<count names;
        positions:.tst.dslDeclarationPositions[masked;names i];
        j:0;
        while[j<count positions;
            scopeId:.tst.dslScopeAt[scopes;positions j];
            rows,:enlist `name`scope`start`end!(
                `$names i;scopeId;scopes[scopeId;`start];scopes[scopeId;`end]);
            j+:1];
        i+:1];
    $[count rows;flip flip rows;
      ([] name:`symbol$();scope:`long$();start:`long$();end:`long$())]
 };

.tst.dslScopeArgument:{[lines]
    masked:.tst.dslMaskedSource lines;
    scopes:.tst.dslScopes masked;
    ranges:.tst.dslScopeRanges[masked;scopes];
    globals:distinct ranges[`name] where ranges[`scope]=0j;
    `ranges`base`globals!(ranges;0j;globals)
 };

.tst.dslNameShadowed:{[shadowed;name;at]
    nm:$[10h=type name;`$name;name];
    if[11h=type shadowed;:nm in shadowed];
    if[-11h=type shadowed;:nm~shadowed];
    if[not 99h=type shadowed;:0b];
    globals:$[`globals in key shadowed;(`symbol$()),shadowed`globals;`symbol$()];
    if[nm in globals;:1b];
    ranges:$[`ranges in key shadowed;shadowed`ranges;
        ([] name:`symbol$();scope:`long$();start:`long$();end:`long$())];
    if[not 98h=type ranges;:0b];
    position:"j"$at+$[`base in key shadowed;"j"$shadowed`base;0j];
    any 0b,(ranges[`name]=nm) and (ranges[`start]<=position) and position<ranges`end
 };

.tst.dslLineOffsets:{[lines]
    if[0=count lines;:`long$()];
    widths:1j+"j"$count each lines;
    0j,-1 _ sums widths
 };

.tst.dslShadowedNames:{[lines]
    ranges:.tst.dslScopeArgument[lines]`ranges;
    distinct ranges`name
 };

.tst.dslScopeWithGlobals:{[text;globals]
    ctx:.tst.dslScopeArgument "\n" vs text;
    ctx[`globals]:distinct (`symbol$()),ctx`globals,(`symbol$()),globals;
    ctx
 };

/ Enrich the otherwise bare q lookup error produced by source whose binding is
/ too dynamic for the lexical pass. Unrelated load failures retain their text.
.tst.dslLoadErrorHint:{[err;lines]
    message:.tst.toString err;
    bare:$[(count message) and first[message]="'";1 _ message;message];
    names:string key .tst.dslExports;
    matched:where bare~/:names;
    if[0=count matched;:message];
    name:`$names first matched;
    if[not name in .tst.dslShadowedNames lines;:message];
    message," -- local '",string[name],"' shadows a resQ DSL name; qualify the framework call as .tst.",string[name],"[...]"
 };

/ q reports only 'limit when a single lambda exceeds its internal expression
/ capacity. A desc body is one lambda, so make the otherwise opaque compiler
/ boundary actionable. Kept as a pure helper so the message contract is cheap
/ to verify on every run; nightly CI separately exercises the real q boundary.
.tst.limitLoadErrorHint:{[err]
    message:.tst.toString err;
    if[not message like "limit*";:message];
    message," -- a desc block is a single q lambda and this one exceeds q's",
        " per-lambda capacity (roughly 110-120 should blocks).",
        " Split it into several desc blocks, or group with alt{}."
 };

/ Return the source bounds of the expression containing `at`. Semicolons and
/ the nearest unmatched opener/closer delimit q expressions; strings/comments
/ are already blanked in `masked`. The end is exclusive.
.tst.dslExpressionBounds:{[masked;at]
    start: 0;
    depth: 0;
    i: at - 1;
    done: 0b;
    while[(i >= 0) and not done;
        c: masked i;
        $[c in "])}"; depth+: 1;
          c in "[({";
            $[depth > 0; depth-: 1; [start: i + 1; done: 1b]];
          (c = ";") and 0 = depth; [start: i + 1; done: 1b];
          ::];
        i-: 1;
    ];
    finish: count masked;
    depth: 0;
    i: at;
    done: 0b;
    while[(i < count masked) and not done;
        c: masked i;
        $[c in "[({"; depth+: 1;
          c in "])}";
            $[depth > 0; depth-: 1; [finish: i; done: 1b]];
          (c = ";") and 0 = depth; [finish: i; done: 1b];
          ::];
        i+: 1;
    ];
    start,finish
 };

/ Find the argument on the left of a temporary primitive marker in a q parse
/ tree. q is right-to-left and has no precedence hierarchy, so asking q's own
/ parser is materially safer than guessing whether `x+1 musteq y` means
/ `(x+1) musteq y` (it does not: the assertion's left argument is `1`).
.tst.dslMarkerLeft:{[tree;marker]
    if[(0h = type tree) and (3 <= count tree) and marker ~ first tree;
        :(1b;tree 1)];
    if[not 0h = type tree; :(0b;::)];
    found: .tst.dslMarkerLeft[;marker] each tree;
    hits: where first each found;
    $[count hits; found first hits; (0b;::)]
 };

.tst.dslParsedAs:{[source;target]
    parsed: @[{[s](1b;parse s)};source;{[e](0b;::)}];
    (first parsed) and target ~ last parsed
 };

/ Locate the exact source span q binds as the assertion's left argument. The
/ selected marker is a real dyadic primitive, so it has the same parse binding
/ as qspec's .q-hosted assertion functions. Candidate suffixes are then parsed
/ until one reproduces the marker node's left subtree.
.tst.dslAssertionLeftStart:{[txt;masked;at;width;adverb]
    bounds: .tst.dslExpressionBounds[masked;at];
    exprStart: first bounds;
    markers: ("xexp";"binr";"wavg";"wsum");
    available: markers where not {[source;word] any .tst.bareTokenAt[source;;word] each "j"$source ss word}[masked;] each markers;
    if[0 = count available; :0N];
    markerName: first available;
    markerText: markerName,adverb;
    marker: $[count adverb; first parse markerText,"[0;0]"; value markerName];
    / Only the completed source to the LEFT is needed. A constant dummy right
    / operand lets this work when the real operand opens a lambda that continues
    / on later physical lines (a common qspec mock idiom).
    marked: ((at - exprStart) # exprStart _ txt), markerText," 0";
    parsed: @[{[s](1b;parse s)};marked;{[e](0b;::)}];
    if[not first parsed; :0N];
    located: .tst.dslMarkerLeft[last parsed;marker];
    if[not first located; :0N];
    target: last located;
    leftText: .tst.rstrip at # txt;
    leftEnd: count leftText;
    / Widest candidate first; the first that reproduces the subtree wins, so
    / stop there instead of parsing every suffix of the expression.
    start: exprStart;
    while[start < leftEnd;
        if[.tst.dslParsedAs[(leftEnd - start) # start _ txt;target];
            / The widest match can begin with the whitespace that separates the
            / operand from a preceding word (`f each xs musteq ys`), or with
            / comment lines above the operand. Leave both outside the rewrite:
            / the generated call otherwise fuses with the word into one
            / identifier (each.tst.dsl.musteq), and a comment pulled inside
            / the brackets stops being one. The mask blanks comments, so
            / skipping its blanks skips them too.
            while[(start < leftEnd) and masked[start] in " \t\n"; start+: 1];
            :start];
        start+: 1];
    0N
 };

/ Find the rightmost unqualified infix assertion before `limit`. Prefix calls
/ (`musteq[a;b]`) are handled by the ordinary qualifier and are not rewritten.
.tst.rightmostInfixAssertion:{[masked;shadowed;limit]
    names: string key[.tst.asserts],`mock;
    / A name that is not a substring of the line cannot match in either form;
    / drop those before the interpreted per-name loop below.
    names: names where 0 < count each masked ss/: names;
    names: names iasc neg count each names;
    / Search only actual token occurrences. The old implementation walked every
    / character and tested every assertion name at each position. Since this
    / function is called again after each rewrite, one ordinary desc containing
    / dozens of assertions became cubic-looking work and could spend minutes in
    / loadTests. `ss` performs the same substring discovery in native code; the
    / exact boundary, shadow, adverb and RHS checks below preserve classification.
    best:(-1;"";0;"";0b);
    ni:0;
    while[ni<count names;
        name:names ni;
        qualifiedToken:".tst.",name;
        forms:(name;qualifiedToken);
        qualifiedFlags:01b;
        fi:0;
        while[fi<2;
            token:forms fi;
            qualified:qualifiedFlags fi;
            positions:(masked ss token);
            positions:positions where positions<limit;
            pi:0;
            while[pi<count positions;
                at:"j"$positions pi;
                width:count token;
                valid:$[qualified;
                    [rightAt:at+width;
                     leftOk:(0=at) or not masked[at-1] in .Q.a,.Q.A,.Q.n,"_`";
                     rightOk:(rightAt=count masked) or
                         not masked[rightAt] in .Q.a,.Q.A,.Q.n,"_";
                     leftOk and rightOk];
                    .tst.bareTokenAt[masked;at;name] and
                        not .tst.dslNameShadowed[shadowed;`$name;at]];
                if[valid;
                    after:at+width;
                    / An adjacent adverb travels with the name: qspec suites
                    / write `xs musteq' ys` and `x mustin\: y` (each-left).
                    next2:2 sublist after _ masked;
                    adverb:$[any ("\\:";"/:";"':")~\:next2; next2;
                        "'"~first next2; enlist "'"; ""];
                    after+:count adverb;
                    while[(after<count masked) and masked[after] in " \t\n";
                        after+:1];
                    / A qualified helper can also be an ordinary RHS value.
                    if[(after<count masked) and not masked[after] in "[;])}";
                        if[at>first best;
                            best:(at;name;width;adverb;qualified)]]];
                pi+:1];
            fi+:1];
        ni+:1];
    best
 };

/ Fully-qualified q functions cannot be used in infix syntax. Rewrite each
/ assertion as a left-bound projection (`lhs musteq rhs` ->
/ `.tst.musteq[lhs;] rhs`). This leaves the complete right-hand expression in
/ q's hands, works across physical lines, and preserves right-to-left binding.
.tst.rewriteInfixAssertions:{[shadowed;line]
    txt: (),line;
    limit: count txt;
    noScopedNames:shadowed~`resqNoDslShadows;
    globals:$[noScopedNames;`symbol$();99h=type shadowed;
        $[`globals in key shadowed;shadowed`globals;`symbol$()];
        (`symbol$()),shadowed];
    scopeArg:$[noScopedNames;`symbol$();.tst.dslScopeWithGlobals[txt;globals]];
    hasScopedShadows:$[noScopedNames;0b;
        (0<count globals) or 0<count scopeArg`ranges];
    / Keep the mask that located the assertion. The old loop immediately
    / recomputed the same byte-for-byte mask before binding its left operand.
    masked: .tst.maskQLine txt;
    pair: .tst.rightmostInfixAssertion[masked;scopeArg;limit];
    while[0 <= first pair;
        at: first pair;
        name: pair 1;
        width: pair 2;
        adverb: pair 3;
        explicitlyQualified: pair 4;
        leftStart: .tst.dslAssertionLeftStart[txt;masked;at;width;adverb];
        if[0N ~ leftStart;
            / Name the source: the caller reports this against a whole file.
            lineStart: 1 + last -1, where (at # txt) = "\n";
            lineText: (lineStart _ txt) til ((lineStart _ txt) ? "\n");
            '"resQ could not safely bind infix DSL call ",name,
                "; write it in prefix form, .tst.",name,"[actual;expected]. Source: ",
                .tst.lstrip 120 sublist lineText];
        rhsStart: at + width + count adverb;
        lhs: .tst.rstrip leftStart _ at # txt;
        rhs: rhsStart _ txt;
        gap: $[(count rhs) and first rhs in " \t"; ""; " "];
        target: $[explicitlyQualified; ".tst.",name; ".tst.dsl.",name];
        txt: (leftStart # txt), target,adverb,"[",lhs,";]",gap,rhs;
        / Re-scan the complete rewritten line: an assertion may live inside the
        / left operand (for example probe[{1 .tst.musteq 1f}] musteq 1). The
        / generated prefix call is skipped by rightmostInfixAssertion, so this
        / still terminates without maintaining fragile shifted offsets.
        limit: count txt;
        if[hasScopedShadows;scopeArg:.tst.dslScopeWithGlobals[txt;globals]];
        masked: .tst.maskQLine txt;
        pair: .tst.rightmostInfixAssertion[masked;scopeArg;limit];
    ];
    txt
 };

/ Is the resQ word at `at` used as the framework's function? Assertions and
/ mock always are: they are reserved words in qspec too. Every other word
/ (it, skip, pending, retry, before, after, fixture, ...) is an ordinary q
/ identifier that an application may use for a global or a table column, so
/ it is the framework's only where it is applied:
/   should["x"]{..}   before{..}   before ({..})   fixture `name
/   tempFile ".csv"   fixture each names           fixture'[names]
/ Anything else (`retry mustne 0`, `exec max retry from t`, `where pending`,
/ `delete skip from t`, `after-before`) is left for q to resolve.
.tst.dslWordUsedAsCall:{[masked;at;name]
    if[name in (string key .tst.asserts), enlist "mock"; :1b];
    rest: (at + count name) _ masked;
    if[0 = count rest; :0b];
    c: first rest;
    if[c in "[{'"; :1b];
    if[any (2 sublist rest) ~/: ("/:";"\\:"); :1b];
    if[not c in " \t\n"; :0b];
    tail: ((rest in " \t\n") ? 0b) _ rest;
    if[0 = count tail; :0b];
    if[first[tail] in "[{(`\""; :1b];
    (((tail in .Q.an) ? 0b) # tail) in ("each";"peach")
 };

/ Qualify only bare, executable DSL tokens. Symbols, strings, comments,
/ already-qualified names, and file-declared shadows are left byte-for-byte.
/ Candidate offsets come from native `ss`. The previous walk tested every DSL
/ name at every character (~350k bareTokenAt calls for an ordinary 30-test
/ desc), which made loading dominate suite time. DSL names are plain
/ identifiers, so two bare matches can never overlap and at most one name is
/ bare at any offset: qualifying each surviving offset is the same rewrite.
.tst.qualifyDslLine:{[shadowed;line]
    txt: (),line;
    if[0 = count txt; :""];
    masked: .tst.maskQLine txt;
    names: string key .tst.dslExports;
    hits: raze {[masked;shadowed;name]
        ps: "j"$masked ss name;
        ps where {[masked;shadowed;name;at]
            $[not .tst.bareTokenAt[masked;at;name]; 0b;
              .tst.dslNameShadowed[shadowed;`$name;at]; 0b;
              .tst.dslWordUsedAsCall[masked;at;name]]
          }[masked;shadowed;name] each ps
      }[masked;shadowed] each names;
    if[0 = count hits; :txt];
    pieces: (0,asc distinct hits) cut txt;
    raze enlist[first pieces], ".tst.dsl.",/: 1 _ pieces
 };

.tst.preprocessOrdinaryLine:{[lineNo;shadowed;line]
    if[not 1b ~ @[get; `.tst.app.expectationLineAnnotations; 1b];
        :.tst.rewriteSystemLoad line];
    annotated:.tst.annotateExpectationLineWith[lineNo;line;shadowed];
    .tst.rewriteSystemLoad annotated
 };

/ Bind DSL across complete q statements so an operator-leading continuation
/ (`expr` on one line, `musteq expected` on the next) retains its left operand.
/ Annotation already happened per physical line, preserving declaration lines;
/ qualification returns to per-line masking after the infix pass.
.tst.bindDslLines:{[shadowed;lines]
    statements: .tst.groupStatements lines;
    out: enlist ();
    / For each line that comes out, the index of the line it came from: the
    / blank lines between statements do not come out, so the two differ.
    from: `long$();
    i: 0;
    while[i < count statements;
        statementLines:statements[i;1];
        / Most suites have no local whose name collides with the DSL. Rewrite
        / their self-contained physical lines first, then run one statement-wide
        / pass for operator-leading continuations. This preserves multiline q
        / binding while avoiding one whole-desc copy/rescan per ordinary assert.
        / A line that cannot bind by itself is left for the statement-wide pass.
        if[shadowed~`resqNoDslShadows;
            statementLines:{[ln]
                .[.tst.rewriteInfixAssertions;
                  (`resqNoDslShadows;ln);
                  {[source;err]source}[ln;]]
              } each statementLines];
        joined: "\n" sv statementLines;
        rewritten: .tst.rewriteInfixAssertions[shadowed;joined];
        scopeArg:$[shadowed~`resqNoDslShadows;`symbol$();
            .tst.dslScopeWithGlobals[rewritten;shadowed]];
        qualified:.tst.qualifyDslLine[scopeArg;rewritten];
        emitted: "\n" vs qualified;
        out,: emitted;
        firstAt: statements[i;0] - 1;
        from,: firstAt + (count emitted) # (til count statementLines), (count emitted) # -1 + count statementLines;
        i+: 1;
    ];
    .tst.boundLineSources: from;
    1 _ out
 };
.tst.boundLineSources: `long$();
/ The line of the file, counted from 1, that each line of the last
/ preprocessed script came from. Lines are dropped on the way (block
/ comments, blank lines, what follows a lone "\"), so a position in the
/ result is not a position in the file.
.tst.preprocessedLineNumbers: `long$();

.tst.preprocessScript:{[lines]
    lines: .resq.util.pathToString each lines;
    / q skips a "#!" interpreter line at the top of a script. Blank it rather
    / than drop it so every later line keeps its number.
    if[count lines; if["#!" ~ 2 sublist first lines; lines[0]: ""]];
    potential:.tst.dslPotentialShadowedNames lines;
    hasScopedNames:0<count potential;
    sourceScope:$[hasScopedNames;.tst.dslScopeArgument lines;`symbol$()];
    lineOffsets:$[hasScopedNames;.tst.dslLineOffsets lines;`long$()];
    rootShadowed:$[hasScopedNames;
        [rootRanges:sourceScope`ranges;
         distinct rootRanges[`name] where rootRanges[`scope]=0j];
        `resqNoDslShadows];
    state: 0;                  / open block comments; q nests them
    out: enlist ();            / sentinel keeps the accumulator heterogeneous
    origin: `long$();          / the file line of each line in `out`
    i: 0;
    n: count lines;
    while[i < n;
        emittedBefore: count out;
        ln: lines i;
        trimmed: .tst.rstrip ln;
        $[state > 0;
            / Inside a block comment: drop the line. A lone "/" opens another
            / level and a lone "\" closes one.
            state+: $[trimmed ~ enlist "/"; 1; trimmed ~ enlist "\\"; -1; 0];
          trimmed ~ enlist "/";
            / Lone "/" outside a block ALWAYS opens a block comment (drop it).
            state: 1;
          (0 < count ln) and "\\" = first ln;
            / Column-1 backslash: terminator or system command.
            $[trimmed ~ enlist "\\";
                i: n;                              / lone "\": terminate script
                / Rewrite \cmd -> system "cmd"; the trailing ";" terminates the
                / statement so it does not chain into the next line when the whole
                / file is joined and value'd (\cmd was line-terminated; system
                / "..." is not).
                [ body: 1 _ ln;
                  esc: ssr[ssr[body; "\\"; "\\\\"]; "\""; "\\\""];
                  / A `\l <path>` loads the code-under-test. Route it through
                  / .tst.sysl instead of bare `system "l ..."` so coverage can
                  / instrument the freshly-loaded source (system "l" is invisible
                  / to the require/loaded-files hooks). Only the `l` command is
                  / special-cased - the arg is whatever follows "\l " (path,
                  / possibly relative; .tst.sysl resolves it the same way q does).
                  / Every other \cmd keeps the plain system rewrite. Match "l "
                  / (load with an argument) precisely so "\l" alone and unrelated
                  / commands fall through unchanged.
                  $[(body ~ "l") or body like "l *";
                      / strip the leading "l" + following whitespace to get the path
                      [ pathArg: $[body ~ "l"; ""; .tst.loadCommandPath 2 _ body];
                        pEsc: ssr[ssr[pathArg; "\\"; "\\\\"]; "\""; "\\\""];
                        out,: enlist ".tst.sysl \"", pEsc, "\";" ];
                      out,: enlist "system \"", esc, "\";" ] ] ];
            / Ordinary line (includes "/ text" line comments).
            [lineScope:sourceScope;
             if[hasScopedNames;lineScope[`base]:lineOffsets i];
             out,: enlist .tst.preprocessOrdinaryLine[i + 1;lineScope;ln]] ];
        if[emittedBefore < count out; origin,: (i + 1) & n];
        i +: 1;
    ];
    bound: .tst.bindDslLines[rootShadowed;1 _ out];
    .tst.preprocessedLineNumbers: $[(count bound) = count .tst.boundLineSources;
        origin .tst.boundLineSources; `long$()];
    bound
 };

/ The path of a `\l` line. q takes the first word as the path and accepts a
/ comment after it (`\l dep.q / code under test`). Anything else after the
/ first word is kept as part of the path: q would reject it, and resQ loads
/ paths that contain spaces.
.tst.loadCommandPath:{[arg]
    arg: trim arg;
    cut1: (arg in " \t") ? 1b;
    rest: trim cut1 _ arg;
    $[(0 < count rest) and "/" = first rest; cut1 # arg; arg]
 };

/ `system "l src/x.q";` with the path inside the one string literal. It is the
/ same load as `\l src/x.q`, and coverage has to see it the same way: left as
/ a bare system call, the file was loaded but never instrumented, and its
/ functions were reported as 0% covered. Returns "" when the line is not
/ exactly that statement.
.tst.rewriteLiteralSystemLoad:{[ln;lt]
    pfx: "system \"l ";
    if[not lt like pfx, "*"; :""];
    body: (count pfx) _ lt;
    / first quote that is not escaped ends the literal
    escaped: 0b, -1 _ body = "\\";
    closing: first (where (body = "\"") and not escaped), count body;
    if[closing = count body; :""];
    if[any (closing # body) = "\\"; :""];
    rest: trim (closing + 1) _ body;
    if[not any rest ~/: ("";enlist ";"); :""];
    path: .tst.loadCommandPath closing # body;
    if[0 = count path; :""];
    (((count ln) - count lt) # ln), ".tst.sysl \"", path, "\"", rest
 };

/ Rewrite a runtime `system "l ", <expr>` load (the form real suites use to load
/ their code-under-test, e.g. `system "l ", root, "/src/x.q"`) into an
/ equivalent `.tst.sysl (<expr>)` so coverage can instrument it. `system "l "`
/ runs the load command whose argument (the file path) is everything AFTER the
/ "l " prefix; here that prefix lives in the leading string literal and the path
/ is the concatenation that follows the comma, so passing that concatenation to
/ .tst.sysl loads the same file (and then instruments it). Only the exact
/ leading token `system "l ", ` is matched so arbitrary `system` calls and
/ string occurrences mid-line are left untouched; the original line is returned
/ verbatim when it does not match.
.tst.rewriteSystemLoad:{[ln]
    lt: .tst.lstrip ln;
    literal: .tst.rewriteLiteralSystemLoad[ln;lt];
    if[count literal; :literal];
    pfx: "system \"l \", ";
    if[not lt like pfx, "*"; :ln];
    rt: .tst.rstrip lt;
    / Only the clean, single-statement form `... ;` is rewritten. A trailing
    / line comment, a missing terminator, or extra statements on the line are
    / left verbatim rather than risk a malformed rewrite - coverage is
    / best-effort, correctness of the load is not.
    if[(0 = count rt) or ";" <> last rt; :ln];
    / A second statement on the line (`system "l ", f; b:2;`) would end up
    / inside the call. Count semicolons outside strings and brackets.
    body: .tst.maskQLine -1 _ (count pfx) _ rt;
    depth: sums (body in "([{") - body in ")]}";
    if[any (body = ";") and depth = 0; :ln];
    / Preserve leading indentation so column-sensitive checks elsewhere are
    / unaffected, then swap the prefix for the .tst.sysl call. Drop the trailing
    / ";" before wrapping in parens (".tst.sysl (expr;)" would not parse) and
    / re-add it after so the call still terminates cleanly.
    indent: (count ln) - count lt;
    rest: -1 _ (count pfx) _ rt;
    (indent # ln), ".tst.sysl (", rest, ");"
 };

/ Strip leading spaces/tabs (mirror of .tst.rstrip).
.tst.lstrip:{[s]
    s: $[10h = type s; s; enlist s];
    i: where not s in " \t";
    $[0 = count i; ""; (first i) _ s]
 };

/ Count the net bracket-nesting contribution of a line: +1 for each of { ( [
/ and -1 for each } ) ], skipping strings and the remainder of an inline comment.
/ In q, "/" opens a comment at column 1 or after whitespace; operator/adverb uses
/ such as x%y and +/ remain code. Block comments are removed before evaluation.
.tst.bracketDelta:{[ln]
    ln: (),.resq.util.pathToString ln;
    if[0 = count ln; :0];
    / Brackets count only in code: the shared lexer marks strings (with their
    / escapes) and a trailing comment, as the old per-character walk did.
    code: 0 = first .tst.qLexStates ln;
    "j"$(sum code and ln in "{([") - sum code and ln in "})]"
 };

/ Group raw source lines into top-level statements. A new top-level statement
/ begins only when bracket nesting is back to 0 AND the line is a non-blank
/ column-1 line (q's script continuation rule: leading whitespace continues the
/ previous statement). A line inside an unbalanced {([ ... keeps accumulating
/ regardless of its leading column, so a multi-line `desc[...]{ ... };` block
/ stays ONE statement (and thus parses as a unit). Returns (startLineNo; lines)
/ pairs with the 1-based ORIGINAL file line of each statement's first line.
.tst.groupStatements:{[lines]
    lines: .resq.util.pathToString each lines;
    out: ();              / list of (startLineNo; list-of-lines)
    depth: 0;             / current unbalanced bracket depth
    i: 0;
    n: count lines;
    while[i < n;
        ln: lines i;
        blank: 0 = count .tst.rstrip ln;
        leadWs: (0 < count ln) and (first ln) in " \t";
        / Continue the current statement when brackets are still open, or this is
        / a whitespace-led continuation line, or a blank line inside a statement.
        cont: (0 < count out) and ((depth > 0) or leadWs or blank);
        $[blank and 0 = depth;
            ::;                                   / separator between statements
          cont;
            out[(count out)-1; 1]: (out[(count out)-1; 1]), enlist ln;
            out,: enlist (i+1; enlist ln)         / start a new top-level stmt
        ];
        depth +: .tst.bracketDelta ln;
        if[depth < 0; depth: 0];                  / defensive: never go negative
        i +: 1;
    ];
    out
 };

/ Parse-only localization of a load error. Re-grouping the ORIGINAL source into
/ top-level statements and `parse`-ing each (NOT `value`) finds the first
/ statement q cannot PARSE -- i.e. the syntax error -- with ZERO side effects
/ (no re-execution, so already-run statements are never run twice). System
/ commands (\l, \d, ...) and comment/terminator statements are skipped because
/ `parse` cannot handle them and they are not where a user's syntax error lives.
/ Returns the 1-based original line of the first un-parseable statement, or 0N
/ when every statement parses (a RUNTIME error -- caller keeps the plain message).
.tst.localizeSyntaxError:{[content]
    stmts: .tst.groupStatements content;
    if[0 = count stmts; :0N];
    / 1b = "fine / not parseable in isolation" (system command, comment, or a
    / multi-line {} fragment that only parses whole); 0b = genuine parse failure.
    okFlags: {[st]
        joined: "\n" sv @[.tst.preprocessScript; st 1; {()}];
        lt: .tst.lstrip joined;
        if[0 = count lt; :1b];
        if[(lt like "system \"*") or lt like ".tst.sysl*"; :1b];
        @[{parse x; 1b}; joined; {0b}]
    } each stmts;
    bad: where not okFlags;
    $[count bad; stmts[first bad; 0]; 0N]
 };

/ Evaluate a preprocessed script the way q's own `\l` does: line by line, NOT as
/ one `value "\n" sv lines` blob. q's loader is line-buffered - each PHYSICAL
/ line is its own statement, except a leading-whitespace line continues the
/ previous code line (concatenated). `value` of a newline-joined string does NOT
/ honour that: it re-lexes the whole blob, so a complete statement followed by a
/ newline + an operator-led line gets merged by the parser. Two concrete
/ divergences this fixes (both invisible to `\l`, both broke the blob `value`):
/   * Bare continuation:  `r:5` <newline> `  +6`  -> `\l` makes r=11; blob value
/     parses `r:5` then a standalone `+6` and errors ('r / rank).
/   * Bare line comment:   `x:5` <newline> `/ c`  -> `\l` ignores the comment;
/     blob value sees `x:5\n/ c` and parses `5 /` as the over-adverb ('handle).
/ Trailing inline comments (`x:5 / note`) have the same failure mode and are
/ likewise fixed because each line is now value'd alone, exactly as `\l` lexes it.
/ Algorithm (mirrors q): drop standalone comment lines FIRST so a following
/ leading-whitespace line continues the previous CODE line across the comment
/ (this is what `\l` does); regroup with .tst.groupStatements (continuation +
/ blank-transparent); value each statement in source order. A standalone comment
/ is a line whose lstrip begins with "/". Block comments and \-rewrites are
/ already resolved by .tst.preprocessScript, so the only "/"-led lines left here
/ are line comments. Signals on the first failing statement (the caller traps and
/ then localizes with parse, exactly as before).
.tst.evalPreprocessed:{[ppLines]
    kept: where not {lt: .tst.lstrip x; (0 < count lt) and "/" = first lt} each ppLines;
    code: ppLines kept;
    stmts: .tst.groupStatements code;
    / The line of the statement being evaluated, in the file as written. A
    / statement that signals leaves it behind: a runtime error while a file
    / loads then has a line number, as a syntax error has.
    numbers: $[(count ppLines) = count .tst.preprocessedLineNumbers;
        .tst.preprocessedLineNumbers; (count ppLines) # 0N];
    {[numbers;kept;st] .tst.loadingLine: numbers kept (st 0) - 1; value "\n" sv st 1}[numbers;kept] each stmts;
    .tst.loadingLine: 0N;
    (::)
 };
.tst.loadingLine: 0N;

.tst.loadTests:{[paths]
    tests: .tst.selectTestFiles .tst.findTests paths;
    .tst.app.discoveredFiles: tests;
    .tst.app.loadedFiles: ();
    .tst.app.emptyFiles: ();
    / Test identities declared so far in this run; see numberDuplicateTests.
    .tst.app.declaredTestIds: ();
    if[0 = count tests;
        -1 "WARNING: No test files found";
        unmatched: @[get; `.tst.app.unmatchedQFiles; {()}];
        if[count unmatched;
            -1 "  ", string[count unmatched], " .q file(s) did not match the test file patterns ",
                (", " sv @[get; `.tst.app.testFilePatternsUsed; {()}]), ", e.g. ",
                .resq.util.pathToString first unmatched;
            -1 "  Rename them, pass them explicitly, set testFilePatterns in resq.json,";
            -1 "  or run them through bin/qspec, which loads every .q file like qspec does."];
        :()];

    / qspec suites often keep helpers in .tst (qspec's own .tst is small).
    / resQ's is not: a helper named like an internal (.tst.toString,
    / .tst.config, ...) broke the runner with an unrelated error, or with no
    / report at all when the function it replaced was one the error path
    / needs. Snapshot the framework's functions and check after every file.
    / On the qspec path any such assignment is a name clash: the definition is
    / put back and the file fails. A native suite may replace an internal on
    / purpose (resQ's own tests do), so there the definition is put back only
    / when the file then failed to load, which is the accidental case.
    fwNames: {` sv' x,'key[x] except `} `.tst;
    fwNames: fwNames where {(type @[get;x;{::}]) within 100 104h} each fwNames;
    .tst.frameworkFunctionSnapshot: fwNames!get each fwNames;

    {[x]
        / Told to stop: the files not yet loaded are left alone.
        if[.resq.util.runInterrupted[]; :()];

        / Normalize path
        p: .resq.util.pathToString x;

        / Verify file exists. It was there when the tests were discovered:
        / a file that has gone since is a failure of this run, not a note.
        if[not .resq.util.pathExists p;
            -1 "ERROR: Test file not found: ", p;
            `.tst.app.loadErrors upsert `file`error`type!(`$p; "the test file disappeared between discovery and loading"; `load);
            :()];

        if[not .tst.app.quiet; -1 "Loading Test: ", p];
        .tst.app.loadedFiles,: enlist p;

        / Make path absolute to avoid CWD issues when tests change directory.
        / Done first so both the sandbox name and its hash derive from the
        / canonical absolute path - the sandbox is then stable regardless of how
        / the path was passed (relative or absolute).
        absPath: .tst.canonicalPath p;

        / Namespace Sandbox
        / Sanitize path to create unique namespace
        / Replace non-alphanumeric chars with _, then append a short content-
        / independent hash of the absolute path. Without the hash, paths that
        / differ only in non-alphanumeric chars (test_a.q / test-a.q / test a.q)
        / collapse to the same sandbox and clobber each other's globals.
        cleanP: absPath;
        cleanP[where not cleanP in .Q.a,.Q.A,.Q.n]: first "_";
        hashStr: 8 # raze string md5 absPath;
        / qspec loads every file into the root namespace, so a helper file in
        / the test tree (tests/00_helpers.q: mkTrade:{...}) defines names the
        / other files use. bin/qspec keeps that instead of a per-file sandbox.
        / -root-load asks for the same namespace without qspec's discovery.
        helperFiles: 1b~@[get;`.tst.app.qspecDiscovery;0b];
        rootLoad: helperFiles or 1b~@[get;`.tst.app.rootLoad;0b];
        nsName: $[rootLoad; `.; `$".sandbox_S", cleanP, "_", hashStr];
        / Register the sandbox so end-of-run cleanup can delete exactly what this
        / run created. finalCleanup used to remove EVERY root namespace matching
        / `sandbox_*`, which is fine in a dedicated test process but destroys an
        / unrelated user namespace of that name under -noquit, watch mode, or
        / embedded use. Store the bare root name (no leading dot) to match the
        / form `key `.` returns.
        if[not rootLoad;
            .tst.app.sandboxNamespaces: distinct .tst.app.sandboxNamespaces,
                `$1 _ string nsName];

        loadCtx: .tst.captureRuntimeContext[];

        / Track current namespace for DSL capture
        .tst.currentNs: nsName;

        / Set loading context with absolute path
        / qutil's convention, which qspec-era test files read, and resQ's own copy.
        .resq.FILELOADING: .resq.util.pathToHsym absPath;
        .utl.FILELOADING: .resq.FILELOADING;

        / Read content
        unreadable: 0b;
        content: @[read0; .resq.FILELOADING; {[p;e]
            -1 "ERROR reading ", p, ": ", e;
            `.tst.app.loadErrors upsert `file`error`type!(`$p; e; `read);
            `resqUnreadable
        }[p]];
        if[`resqUnreadable ~ content; unreadable: 1b; content: ()];
        if[0 = count content;
            / An empty test file declares no tests, like one that holds only
            / comments. It used to be skipped without the warning, and without
            / the -strict failure, that such a file gets: a file truncated to
            / nothing went unnoticed.
            if[not unreadable;
                helperFile: 1b~@[get;`.tst.app.qspecDiscovery;0b];
                msg: "File ", p, " is empty and added no tests.";
                .tst.app.emptyFiles,: enlist p;
                if[not helperFile; -1 "WARNING: ", msg];
                if[.tst.app.strict and not helperFile;
                    `.tst.app.loadErrors upsert `file`error`type!(`$p; msg; `emptyFile)]];
            .tst.restoreRuntimeContext loadCtx;
            :()
        ];

        / Snapshot spec count
        preCount: count .tst.app.allSpecs;

        / Ensure namespace exists and switch to it
        if[not rootLoad;
            nsInit: string[nsName],".init:0;";
            @[value; nsInit; {[p;e]
                -1 "CRITICAL LOAD ERROR in ", p, ": ", e;
                `.tst.app.loadErrors upsert `file`error`type!(`$p; e; `load);
            }[p]]];

        @[system; "d ", string nsName; {[p;e]
            -1 "CRITICAL LOAD ERROR in ", p, ": ", e;
            `.tst.app.loadErrors upsert `file`error`type!(`$p; e; `load);
        }[p]];

        / Evaluate script content. Preprocess first so q system commands (\l, \d,
        / \t, ...) that `value` cannot execute become equivalent `system "..."`
        / calls, and trailing `\` script terminators are honoured. Then evaluate
        / per-statement (.tst.evalPreprocessed) so q's line-buffered `\l`
        / semantics are reproduced exactly - a blob `value "\n" sv ...` re-lexes
        / the whole file and diverges from `\l` on bare continuations and bare/
        / inline comments (see .tst.evalPreprocessed). Statements still run in
        / source order, so a partial failure rolls back below just as before.
        / Only AFTER a failure do we localize, and we localize with `parse`, not
        / `value`, so no successful statement is ever re-executed (re-running
        / would fire side effects twice). Parse-localization pinpoints the common
        / case (a SYNTAX error); a pure runtime error parses cleanly and keeps the
        / original message.
        / Add the outcome tag outside evalPreprocessed's return value. Ordinary q
        / code can then return any shape without impersonating a loader error.
        / Preprocessing runs inside the trap too. It signals on source it
        / cannot bind safely, and that must fail this file, not the whole run.
        / An assertion written outside any test runs while the file loads.
        / Start from a clean state so its failure is this file's, and take it
        / out again so the first test to run is not blamed for it.
        .tst.assertState: .tst.defaultAssertState;
        .tst.app.numberingTests: 1b;
        .tst.loadingLine: 0N;
        res: @[{[lines] (0b; .tst.evalPreprocessed .tst.preprocessScript lines)};
               content;
               {[err] (1b; err)}];
        .tst.app.numberingTests: 0b;
        / Before anything is formatted or reported: put back any resQ
        / function this file replaced. The messages below go through them.
        qspecPath: any 1b~/:@[get;;0b] each `.tst.app.qspecCompat`.tst.app.qspecDiscovery;
        overridden: $[qspecPath or 1b ~ first res;
            .tst.restoreFrameworkOverrides[p;content];
            `symbol$()];
        loadFailures: .tst.toString each .tst.assertState.failures;
        .tst.assertState: .tst.defaultAssertState;
        / A file that failed to load is reported once, as that. It was also
        / reported as a file that "loaded but added no tests".
        loadFailed: (1b ~ first res) or 0 < count loadFailures;
        if[(not 1b ~ first res) and count loadFailures;
            e: "an assertion outside any test failed while the file was loading: ",
                "; " sv loadFailures;
            -1 "CRITICAL LOAD ERROR in ", p, ": ", e;
            `.tst.app.loadErrors upsert `file`error`type!(`$p; e; `load)];
        if[1b ~ first res;
            e: .tst.dslLoadErrorHint[last res;content];
            / q signals some malformed expressions with a blank error name.
            if[all e in " "; e: "q signalled an unnamed error"];
            / The statement that was being evaluated is the one that
            / signalled, whether q could not parse it or could not run it.
            / Looking for a statement that does not parse found nothing for a
            / runtime error, and found the inside of a block comment before
            / the real one. It is asked only when no statement had started.
            lineNo: $[null .tst.loadingLine;
                @[.tst.localizeSyntaxError; content; {0N}];
                .tst.loadingLine];
            where1: "near line ";
            .tst.loadingLine: 0N;
            if[not null lineNo;
                stmtsForMsg: @[.tst.groupStatements; content; {()}];
                hits: stmtsForMsg where stmtsForMsg[;0] = lineNo;
                stmtTxt: .tst.lstrip $[count hits; "\n" sv (first hits) 1;
                    lineNo <= count content; .resq.util.pathToString content lineNo - 1;
                    ""];
                excerpt: (80 & count stmtTxt) # stmtTxt;
                e: e, " (", where1, string[lineNo], $[count excerpt; ": ", excerpt; ""], ")";
            ];
            e:.tst.limitLoadErrorHint e;
            -1 "CRITICAL LOAD ERROR in ", p, $[not null lineNo; " ", where1, string[lineNo]; ""], ": ", e;
            `.tst.app.loadErrors upsert `file`error`type!(`$p; e; `load);
            if[(count .tst.app.allSpecs) > preCount;
                .tst.app.allSpecs: preCount # .tst.app.allSpecs;
                -1 "  -> Rolled back partial specs from ", p;
            ];
        ];

        / Restore root namespace
        @[system; "d ."; {}];

        .tst.reportFrameworkOverrides[p;overridden];

        / Warn if no tests loaded. On the qspec path a spec-free file is a
        / helper (qspec loads every .q file), so it is only counted.
        if[(not loadFailed) and (count .tst.app.allSpecs) = preCount;
            msg: "File ", p, " loaded but added no tests.";
            .tst.app.emptyFiles,: enlist p;
            if[not helperFiles; -1 "WARNING: ", msg];
            if[.tst.app.strict and not helperFiles;
                `.tst.app.loadErrors upsert `file`error`type!(`$p; msg; `emptyFile);
            ];
        ];

        / Restore loader bookkeeping
        .tst.restoreRuntimeContext loadCtx;
        
    } each tests;
 };

/ Restore framework functions a test file redefined and fail the file with a
/ message that names the helper to rename. Only names the file assigns in its
/ own source count: the framework legitimately swaps some of its functions
/ while a file loads (coverage) and stores user hooks in function slots.
.tst.restoreFrameworkOverrides:{[p;content]
    snapshot: @[get; `.tst.frameworkFunctionSnapshot; {()!()}];
    if[0 = count snapshot; :`symbol$()];
    names: key snapshot;
    changed: names where not snapshot[names] ~' @[get;;{::}] each names;
    if[0 = count changed; :`symbol$()];
    / sourceAssignedTstNames is itself a resQ function the file may have
    / replaced; the snapshot holds the real one.
    finder: $[`.tst.sourceAssignedTstNames in names;
        snapshot `.tst.sourceAssignedTstNames;
        .tst.sourceAssignedTstNames];
    assigned: @[finder; content; {[e] `symbol$()}];
    changed: changed inter assigned;
    if[0 = count changed; :`symbol$()];
    {[snapshot;name] name set snapshot name}[snapshot] each changed;
    changed
 };

/ Fail the file whose source replaced resQ functions, naming them.
.tst.reportFrameworkOverrides:{[p;changed]
    if[0 = count changed; :()];
    shown: ", " sv string changed;
    msg: "redefines resQ internal ", shown, " (resQ's .tst namespace is larger than ",
        "qspec's). The framework definition was restored; rename the helper, e.g. ",
        ".myTests.", last "." vs string first changed;
    -1 "ERROR: ", p, " ", msg;
    `.tst.app.loadErrors upsert `file`error`type!(`$p; msg; `frameworkOverride);
 };

/ `.tst.<name>` targets of `:`/`::` assignments in code (not strings or
/ comments), as fully qualified symbols.
.tst.sourceAssignedTstNames:{[content]
    code: "\n" sv .tst.maskQLine each (),/:content;
    starts: "j"$code ss ".tst.";
    starts: starts where {[code;at] (at = 0) or not code[at - 1] in .Q.an,"."}[code] each starts;
    identChars: .Q.an;
    names: {[code;identChars;at]
        from: at + 5;
        width: (from _ code) ? first (from _ code) except identChars;
        rest: ltrim (from + width) _ code;
        $[(width > 0) and ":" = first rest; `$".tst.", width # from _ code; `]
      }[code;identChars] each starts;
    distinct names except `
 };

/ Canonical file selection boundary. Sharding extends this function later; all
/ callers already share it so normal and isolated execution cannot diverge.
.tst.selectTestFiles:{[files]
    ordered:files iasc .resq.util.pathToString each files;
    .tst.app.allDiscoveredFiles:ordered;
    shardIndex:"j"$@[get;`.tst.app.shardIndex;0j];
    shardCount:"j"$@[get;`.tst.app.shardCount;1j];
    if[1>shardCount;'"shardCount must be > 0"];
    if[(0>shardIndex) or shardIndex>=shardCount;
        '"shardIndex must be >= 0 and less than shardCount"];
    unit:@[get;`.tst.app.shardUnit;`file];
    selected:$[unit~`file;
        ordered where shardIndex=(til count ordered) mod shardCount;
        ordered];
    .tst.app.shardAllFileCount:"j"$count ordered;
    .tst.app.shardSelectedFileCount:"j"$count selected;
    if[unit~`file;
        .tst.app.shardAllUnitCount:"j"$count ordered;
        .tst.app.shardSelectedUnitCount:"j"$count selected];
    .tst.app.emptyShard:(0<count ordered) and 0=count selected;
    .tst.orderItems[selected;"files"]
 };

.tst.findTests:{[paths]
    / Ensure paths is a list
    ps: $[10h = type paths; enlist paths; 0h = type paths; paths; enlist paths];
    / De-dup on the CANONICAL absolute path, not the raw spelling: passing the
    / same file under two spellings (resq test ./x.q x.q) must register and run
    / it ONCE. Raw-string `distinct` saw "./x.q" and "x.q" as different, so the
    / file loaded - and DEFINED - twice. Absolutizing+normalizing first unifies
    / them. loadTests later derives its sandbox from the same canonical form, so
    / making paths absolute here is invariant-preserving.
    ps: distinct .tst.canonicalPath each ps;

    / Explicit q file paths are always honored. Directory scans are filtered
    / to a configurable list of test-file glob patterns so we don't load
    / helper/repro/dependency files. Defaults preserve historical behavior
    / (test_*.q, *_test.q); override via .resq.config.testFilePatterns
    / (a list of strings) or the testFilePatterns key in resq.json.
    patterns: @[get; `.resq.config.testFilePatterns; {("test_*.q"; "*_test.q")}];
    if[10h = type patterns; patterns: enlist patterns];
    / The compatibility launcher targets existing qspec trees, whose pinned
    / public suites use qspec_test_*.q.  Preserve ordinary resQ defaults and do
    / not second-guess an explicit resq.json testFilePatterns override.
    qspecMode:1b~@[get;`.tst.app.qspecCompat;0b];
    patternsExplicit:1b~@[get;`.tst.configTestFilePatternsExplicit;0b];
    if[qspecMode and not patternsExplicit;
        patterns:distinct patterns,enlist "qspec_test_*.q"];
    / qspec's loader takes every *.q file under a directory. bin/qspec asks for
    / the same so an existing tree (tests/pricing.q, tests/specs/fx.q) is found
    / without renaming; an explicit resq.json testFilePatterns still wins.
    if[(1b~@[get;`.tst.app.qspecDiscovery;0b]) and not patternsExplicit;
        patterns:enlist "*.q"];

    directFiles: ps where {(.resq.util.isFile x) and x like "*.q"} each ps;
    dirs: ps where .resq.util.isDir each ps;

    / Any explicit arg that is neither an existing file nor an existing
    / directory is a user mistake (typo, deleted path, ...). Historically these
    / were silently dropped, so a run could "succeed" while quietly skipping the
    / file the user asked for. Record each as a load error so the run fails with
    / EXIT.LOAD_ERROR (4) and the missing path is reported. Guard the table init
    / in case findTests is reached before lib/init.q seeded it.
    missing: ps where not (.resq.util.isFile each ps) or .resq.util.isDir each ps;
    if[0 < count missing;
        if[not `loadErrors in key `.tst.app;
            .tst.app.loadErrors: flip `file`error`type!(`symbol$(); (); `symbol$());
        ];
        {[m]
            -1 "ERROR: Explicit test path not found: ", m;
            `.tst.app.loadErrors upsert `file`error`type!(`$m; "Explicit test path not found"; `missing);
        } each missing;
    ];

    discovered: distinct raze .tst.suffixMatch[".q"] each dirs;
    isNamedTest: {[pats; p]
        base: last "/" vs p;
        any base like/: pats
    }[patterns;];
    files: distinct directFiles, discovered where isNamedTest each discovered;
    / Remembered so "No test files found" can say why, which is the first
    / thing a qspec tree with unprefixed file names hits.
    .tst.app.unmatchedQFiles: discovered where not isNamedTest each discovered;
    .tst.app.testFilePatternsUsed: patterns;

    / Return convention-matching discovered tests plus explicit files.
    files
 };

/ Trapped predicates: .resq.util.isFile/.resq.util.isDir call `key`, which SIGNALS an OS
/ error on a broken symlink or a permission-denied entry. Untrapped, that kills
/ the whole run mid-discovery. These wrappers treat an unreadable entry as
/ "neither file nor dir" so it is simply skipped.
.tst.safeIsFile:{[p] @[.resq.util.isFile; p; {[e] 0b}]};
.tst.safeIsDir:{[p] @[.resq.util.isDir; p; {[e] 0b}]};

/ True when `p` is a symbolic link. q has no native lstat, so we shell out to
/ `test -L <p>; echo $?` - the same exit-code-absorbing idiom the golden harness
/ uses. `test -L` exits 0 for a symlink, 1 otherwise; appending `; echo $?` makes
/ the shell always exit 0 (so q's `system` never signals 'os) and prints the real
/ exit code on the last stdout line, which we read back. The path is shell-quoted
/ (its closing quote must stay attached to the path, so quote in a separate step:
/ q is right-to-left and would otherwise fold the trailing text into the path
/ before quoting).
.tst.isSymlink:{[p]
    q: .resq.util.shellQuote .resq.util.pathToString p;
    out: @[system; "test -L ", q, "; echo $?"; {[e] enlist "1"}];
    / `echo $?` captures as a 1-char string ("0"), so compare as a string and
    / parse it: exit code 0 from `test -L` means the path is a symlink.
    $[0 = count out; 0b; 0 = "J" $ last out]
 };

/ Public entry point - depth starts at 0.
.tst.suffixMatch:{[suffix;path] .tst.suffixMatchDepth[suffix;path;0]};

/ Recursively collect files under `path` whose name ends in `suffix`.
/ `depth` guards against symlink loops: a directory tree that cycles back on
/ itself would otherwise recurse until q dies with an OS error. Above the cap we
/ warn once and stop descending that branch.
.tst.suffixMatchDepth:{[suffix;path;depth]
    / Bail out of pathological recursion (symlink loops, absurdly deep trees).
    if[depth > 32;
        -1 "WARNING: max directory depth exceeded, skipping: ", .resq.util.pathToString path;
        :0#enlist""
    ];

    / Normalize path to string
    p: .resq.util.pathToString path;

    / If path is a file with matching suffix, return it
    if[p like ("*", suffix); if[.tst.safeIsFile p; :(enlist p)]];

    / If path is not a directory, nothing more to find
    if[not .tst.safeIsDir p; :0#enlist""];

    / Get directory contents. `key` can signal on a bad entry; trap to a clean
    / empty so one broken dir does not abort the entire run.
    h: .resq.util.pathToHsym p;
    contents: @[key; h; {[e] ()}];
    if[() ~ contents; :0#enlist""];

    / Filter out hidden files (starting with .)
    contents: contents where not (string contents) like ".*";
    if[0 = count contents; :0#enlist""];

    / Build full paths - ensure we get a list of strings
    fullPaths: {[base;name] b: .resq.util.pathToString base; b: $["/" = last b; b; b, "/"]; b, string name}[p] each contents;

    / Separate files and directories (trapped predicates skip unreadable entries)
    files: fullPaths where .tst.safeIsFile each fullPaths;
    dirs: fullPaths where .tst.safeIsDir each fullPaths;

    / Do NOT follow symlinked directories: a symlink cycle would rediscover the
    / same test file under N loop paths (one file ran 17x before this). Standard
    / tools (find, rg) skip symlinked dirs by default; we match that. Symlinked
    / FILES are fine - only directory symlinks are dropped here.
    dirs: dirs where not .tst.isSymlink each dirs;

    / Find matching files
    matchingFiles: files where files like ("*", suffix);

    / Recurse into directories - use (,/) to join lists without flattening strings
    (,/) (enlist matchingFiles), .tst.suffixMatchDepth[suffix;;depth+1]'[dirs]
 };
