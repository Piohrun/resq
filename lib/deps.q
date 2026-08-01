\d .tst

/ Dependency Graph Builder
depGraph: ()!();
dependencies: ()!();

/. Keep parse/scan helpers local and dependency-free by loading static analysis utilities here.
.utl.require .utl.PKGLOADING,"/static_analysis.q"

/ ---------------------------------------------------------------------------
/ Load-directive parsing
/ (no bare "/" line below: on its own a slash opens a q block comment)
/ Directives are located in MASKED source (comments, strings, block comments
/ and terminated tails blanked by .tst.static.maskLines, which preserves line
/ length) and the literal is then read back out of the RAW text at the same
/ offset. The previous scanner matched raw lines with `like` and had to skip
/ any line containing "like" to avoid ingesting its own detection patterns as
/ dependencies; masking removes the need for that heuristic entirely, and stops
/ a require mentioned inside a comment or string from becoming a real edge.
/ ---------------------------------------------------------------------------

/ True when `token` occurs at `start` as a whole identifier, not as the tail of
/ a longer name (so `.my.utl.require` does not match `.utl.require`).
depTokenAt:{[line;start;token]
    if[(start < 0) or (start + count token) > count line; :0b];
    if[not token ~ (count token)#start _ line; :0b];
    identifier: .Q.a, .Q.A, .Q.n, "._";
    if[start > 0; if[line[start-1] in identifier; :0b]];
    finish: start + count token;
    if[finish < count line; if[line[finish] in identifier; :0b]];
    1b
 };

/ Per-line mask marking ONLY the executable quote characters that OPEN a
/ string. Parallel to maskCodeLine, but it records where literals begin
/ instead of erasing them, so the raw literal can be recovered.
depQuoteMaskLine:{[line;initialInString;initialEscape]
    inString: initialInString;
    escaped: initialEscape;
    inComment: 0b;
    markers: (count line)#0b;
    i: 0;
    while[i < count line;
        char: line i;
        $[inComment;
            (::);
          inString;
            $[escaped;    escaped: 0b;
              char="\\";  escaped: 1b;
              char="\"";  inString: 0b;
              (::)];
          char="\"";
            [markers[i]: 1b; inString: 1b];
          (char="/") and ((i=0) or line[i-1] in " \t");
            inComment: 1b;
          (::)];
        i+: 1];
    (markers; inString; escaped)
 };

/ Whole-file quote-open mask, tracking block comments and script termination
/ exactly as maskLines does so the two stay in step line for line.
depQuoteMasks:{[lines]
    output: ();
    inBlock: 0b;
    terminated: 0b;
    inString: 0b;
    escaped: 0b;
    i: 0;
    while[i < count lines;
        raw: lines i;
        rightTrimmed: .tst.static.rstrip raw;
        blank: (count raw)#0b;
        $[terminated;
            output,: enlist blank;
          inBlock;
            [output,: enlist blank;
             if[rightTrimmed ~ enlist "\\"; inBlock: 0b]];
          (not inString) and rightTrimmed ~ enlist "/";
            [inBlock: 1b; output,: enlist blank];
          (not inString) and ((count raw) > 0) and
              ("\\" = first raw) and rightTrimmed ~ enlist "\\";
            [terminated: 1b; output,: enlist blank];
            [marked: .tst.depQuoteMaskLine[raw; inString; escaped];
             output,: enlist marked 0;
             inString: marked 1;
             escaped: marked 2]];
        i+: 1];
    output
 };

/ Bracket depth at each (ascending) position in the masked text. Used to tell
/ a top-level require from one nested inside a lambda or argument list.
depDepthsAt:{[codeText;positions]
    depths: (count positions)#0;
    depth: 0;
    cursor: 0;
    positionIndex: 0;
    while[positionIndex < count positions;
        position: positions positionIndex;
        while[cursor < position;
            char: codeText cursor;
            if[char in "{(["; depth+: 1];
            if[char in "})]"; depth-: 1; if[depth < 0; depth: 0]];
            cursor+: 1];
        depths[positionIndex]: depth;
        positionIndex+: 1];
    depths
 };

/ Classify what sits between the token and its string literal.
/ `tail` means the literal is CONCATENATED onto a prefix (the
/ `.utl.PKGLOADING,"/name.q"` idiom), so it resolves relative to the requiring
/ file rather than as a path in its own right.
depRequireForm:{[between;contextOpen]
    lineBreak: between?"\n";
    crossesLine: lineBreak < count between;
    firstLine: trim lineBreak#between;
    prefix: trim ssr[between; "\n"; " "];
    / A newline ends a complete q expression. Continuing across one is valid
    / only inside an open enclosing expression.
    if[crossesLine and (not contextOpen) and not count firstLine;
        :`recognized`tail`closing!(0b; 0b; "")];
    if[not count prefix; :`recognized`tail`closing!(1b; 0b; "")];
    wrapper: $[first[prefix]="["; enlist "[";
               first[prefix]="("; enlist "(";
               ""];
    if[count wrapper;
        body: trim 1_prefix;
        closing: $[wrapper ~ enlist "["; enlist "]"; enlist ")"];
        if[not count body; :`recognized`tail`closing!(1b; 0b; closing)];
        if[not ","=last body; :`recognized`tail`closing!(0b; 0b; "")];
        base: trim -1_body;
        if[(not count base) or (base ~ enlist ".") or
           not .tst.static.validFunctionName base;
            :`recognized`tail`closing!(0b; 0b; "")];
        :`recognized`tail`closing!(1b; 1b; closing)];
    if[not ","=last prefix; :`recognized`tail`closing!(0b; 0b; "")];
    base: trim -1_prefix;
    if[(not count base) or (base ~ enlist ".") or
       not .tst.static.validFunctionName base;
        :`recognized`tail`closing!(0b; 0b; "")];
    `recognized`tail`closing!(1b; 1b; "")
 };

/ Read the string literal that starts at `start` in the RAW text, resolving
/ the escapes q allows in a path. A control escape would make the value
/ unusable as a filename, so it is rejected rather than silently mangled.
depQuotedLiteral:{[line;start]
    if[(start >= count line) or not "\"" = line start;
        :`ok`text`end!(0b; ""; start)];
    output: "";
    closed: 0b;
    escapedMode: 0b;
    i: start + 1;
    while[(i < count line) and not closed;
        char: line i;
        $[escapedMode;
            [if[not (char="\\") or char="\"";
                '"Unsupported escape in dependency path"];
             output,: enlist char;
             escapedMode: 0b];
          char="\\";  escapedMode: 1b;
          char="\"";  closed: 1b;
          output,: enlist char];
        i+: 1];
    if[escapedMode; '"Unterminated escape in dependency path"];
    `ok`text`end!(closed; output; $[closed; i-1; i])
 };

/ True when nothing but the expected closing delimiter and outer closers follow
/ the literal, i.e. the require really is the whole call and not a fragment of
/ a larger expression that happens to contain a string.
depRequireTailValid:{[codeText;literalEnd;stop;closing]
    if[(literalEnd < 0) or (stop < literalEnd+1) or stop > count codeText; :0b];
    tail: ((stop-literalEnd)-1)#(literalEnd+1)_codeText;
    cursor: 0;
    if[count closing;
        while[(cursor < count tail) and tail[cursor] in " \t\r\n"; cursor+: 1];
        if[(cursor >= count tail) or not (enlist tail cursor) ~ closing; :0b];
        cursor+: 1];
    remainder: cursor _ tail;
    firstLine: (remainder?"\n")#remainder;
    all firstLine in " \t\r})]"
 };

emptyDepRecords:{[] ([] target:(); tail:`boolean$(); kind:`symbol$()) };

/ Parse one file into dependency records: (target; tail; kind).
/ `kind` is `load for "\l x.q" and `require for .utl.require "x.q".
parseDependencyRecords:{[filepath]
    filepath: $[10h = abs type filepath; `$filepath; filepath];
    if[() ~ key hsym filepath; :.tst.emptyDepRecords[]];
    lines: read0 hsym filepath;
    / A file whose only line is a single character (e.g. a lone "/") comes back
    / from read0 as a char VECTOR, not a one-element list of strings. Normalize
    / so line indexing and "\n" sv below always see a list of strings.
    lines: $[10h = type lines; enlist lines; lines];
    if[not count lines; :.tst.emptyDepRecords[]];

    masked: .tst.static.maskLines lines;
    quoteLines: .tst.depQuoteMasks lines;

    targets: ();
    tails: `boolean$();
    kinds: `symbol$();

    / \l directives are line-oriented: the rest of the masked line is the path.
    lineIndex: 0;
    while[lineIndex < count lines;
        if[(masked lineIndex) like "\\l *";
            targets,: enlist trim 3 _ lines lineIndex;
            tails,: 0b;
            kinds,: `load];
        lineIndex+: 1];

    / .utl.require can appear mid-expression, so scan the whole masked text.
    rawText: "\n" sv lines;
    codeText: "\n" sv masked;
    quotePieces: {x, 0b} each quoteLines;
    quoteText: $[count quotePieces; -1 _ raze quotePieces; `boolean$()];
    if[count[quoteText] <> count rawText; :.tst.emptyDepRecords[]];

    token: ".utl.require";
    positions: codeText ss token;
    contextDepths: .tst.depDepthsAt[codeText; positions];

    positionIndex: 0;
    while[positionIndex < count positions;
        start: positions positionIndex;
        if[.tst.depTokenAt[codeText; start; token];
            tokenEnd: start + count token;
            / The statement ends at the next require, the next ";" or EOF.
            stop: count rawText;
            if[(positionIndex+1) < count positions;
                stop: stop & positions positionIndex+1];
            tailCode: (stop-tokenEnd)#tokenEnd _ codeText;
            semicolon: tailCode?";";
            if[semicolon < count tailCode; stop: tokenEnd + semicolon];
            quoteSegment: (stop-tokenEnd)#tokenEnd _ quoteText;
            quoteOffset: quoteSegment?1b;
            if[quoteOffset < stop - tokenEnd;
                quoteAt: tokenEnd + quoteOffset;
                between: (quoteAt-tokenEnd)#tokenEnd _ codeText;
                form: .tst.depRequireForm[between; 0 < contextDepths positionIndex];
                if[form`recognized;
                    literal: .tst.depQuotedLiteral[rawText; quoteAt];
                    if[literal`ok;
                        if[(literal`end) < stop;
                            if[.tst.depRequireTailValid[
                                    codeText; literal`end; stop; form`closing];
                                targets,: enlist literal`text;
                                tails,: form`tail;
                                kinds,: `require]]]]]];
        positionIndex+: 1];

    ([] target: targets; tail: tails; kind: kinds)
 };

/ Compatibility API: the literal targets as symbols. Graph construction uses
/ the richer records above, so a direct absolute path stays distinguishable
/ from a concatenated leading-slash tail.
parseLoadDirectives:{[filepath]
    records: .tst.parseDependencyRecords filepath;
    if[not count records; :()];
    distinct `$records`target
 };

/ Resolve a raw require/load target to the same absolute, normalized form
/ used for graph keys. Targets are captured as quoted strings (often the
/ ".../<name>.q" tail of `.utl.PKGLOADING,"/<name>.q"`), so they are resolved
/ against the requiring file's directory. Falls back to the target as-is when
/ the resolved file does not exist, so unresolvable targets stay honest.
resolveDepTarget:{[reqFile; target] .tst.resolveDepTargetRecord[reqFile; target; 1b] };

/ `isTail` says the literal was concatenated onto a prefix (`.utl.PKGLOADING,
/ "/name.q"`). Only then may a leading "/" be stripped and the remainder joined
/ to the requiring directory. A standalone literal keeps its leading "/", so a
/ genuinely absolute require is not silently rebased onto the requiring file's
/ directory and pointed at the wrong file.
resolveDepTargetRecord:{[reqFile; target; isTail]
    t: .tst.static.toStr target;
    if[0 = count t; :`$t];
    reqDir: .tst.static.getDir .tst.static.toStr reqFile;
    absolute: "/" = first t;
    if[absolute and not isTail;
        :$[not () ~ key hsym `$t; `$t; `$t]];
    rel: $[absolute; 1 _ t; t];
    cand: $[count reqDir; reqDir, rel; rel];
    $[not () ~ key hsym `$cand; `$cand;
      not () ~ key hsym `$t; `$t;
      `$cand]
 };

/ Build dependency graph for directory
scanDirectory:{[dir]
    / Find all .q files recursively using q-native directory traversal.
    rootDir: .tst.static.toStr dir;
    if[0 = count rootDir; :`symbol$()];
    files: .tst.static.findSources rootDir;
    files: files where files like "*.q";

    {[f]
        records: .tst.parseDependencyRecords[f];
        / Resolve each target to the absolute-normalized form used for keys so
        / the reverse graph is actually traversable by path. Masking means no
        / "*"-patterned literals can reach here, so no post-hoc filter is needed.
        fileDeps: distinct $[count records;
            .tst.resolveDepTargetRecord[f;;] .' flip (records`target; records`tail);
            `symbol$()];
        .tst.dependencies[f]: fileDeps;

       / Update reverse graph
        {[dep;dependent]
            if[not dep in key .tst.depGraph; .tst.depGraph[dep]: ()];
            .tst.depGraph[dep],: dependent;
        }[;f] each fileDeps;
    } each files;
    
    .tst.depGraph
 };

/ Get all files that depend on a given file. Threads a `seen` accumulator
/ through the recursion so circular requires (A→B→A) do not blow the stack.
getDependents:{[file] .tst.getDependentsAcc[file; `symbol$()]};

getDependentsAcc:{[file; seen]
    if[file in seen; :`symbol$()];
    seen,: file;
    direct: $[file in key .tst.depGraph; .tst.depGraph[file]; `symbol$()];
    transitive: distinct raze .tst.getDependentsAcc[; seen] each direct;
    distinct direct, transitive
 };

/ Get dependencies of a file  
getDependencies:{[file]
    $[file in key .tst.dependencies; .tst.dependencies[file]; ()]
 };

/ Rebuild dependency graph
rebuildGraph:{[dirs]
    .tst.depGraph:: ()!();
    .tst.dependencies:: ()!();
    {.tst.scanDirectory[x]} each dirs;
    -1 "Dependency graph built: ", string[count .tst.depGraph], " files tracked";
 };

\d .
::
