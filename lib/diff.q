\d .tst

/ Diagnostic seams may be lowered by focused tests. Every read is validated and
/ clamped against a literal ceiling before it controls work or allocation.
.tst.DIFF_MAX_DEPTH:6;
.tst.DIFF_MAX_NODES:64;
.tst.DIFF_MAX_LINES:40;
.tst.DIFF_MAX_CHARS:20000;
.tst.DIFF_SCAN_ITEMS:1048576;
.tst.DIFF_TABLE_CELL_SCAN:2097152;
.tst.DIFF_COLUMN_SCAN:4096;
.tst.DIFF_CHUNK_SIZE:256;
.tst.DIFF_MISMATCH_LIMIT:5;
.tst.DIFF_PROBE_ITEMS:4096;
.tst.DIFF_CALLABLE_MAX_DEPTH:12;
.tst.DIFF_CALLABLE_VECTOR_ITEMS:65536;

/ Color formatting utility.
if[not `fmt in key `.tst; .tst.fmt.init:1b];
if[not `diffColors in key `.tst; .tst.diffColors:1b];

/ Linux is the only supported TTY detector. Unsupported platforms and every
/ malformed/error path fail closed to plain text.
.tst.ttyProbeIsTerminal:{[links]
    if[0h<>type links; :0b];
    if[1<>count links; :0b];
    link:first links;
    if[10h<>type link; :0b];
    if[count[link]>256; :0b];
    (link like "/dev/pts/*") or link like "/dev/tty*"
 };

detectTty:{[]
    @[
        {[ignored]
            linux:@[get;`.utl.isLinux;{[err] 0b}];
            if[not 1b~linux; :0b];
            links:@[
                {
                    system
                        "/usr/bin/timeout -k 1s 1s ",
                        "/usr/bin/readlink /proc/$PPID/fd/1 2>/dev/null ",
                        "| /usr/bin/head -c 256"
                  };
                ::;
                {[err] ()}];
            .tst.ttyProbeIsTerminal links
          };
        ::;
        {[err] 0b}]
 };

/ Compatibility seam retained for tests/mocks. It captures TTY capability at
/ load, while diffColors and NO_COLOR remain dynamic render-time gates.
useColor:.tst.detectTty[];

.tst.colorEnabled:{[]
    @[
        {[ignored]
            if[not 1b~@[get;`.tst.useColor;{[err] 0b}]; :0b];
            if[not 1b~@[get;`.tst.diffColors;{[err] 0b}]; :0b];
            noColor:@[getenv;`NO_COLOR;{[err] "disabled"}];
            (10h=type noColor) and 0=count noColor
          };
        ::;
        {[err] 0b}]
 };

fmt.color:{[c;txt]
    plain:$[type[txt] in -10 10h;txt;"<color text unavailable>"];
    if[not .tst.colorEnabled[]; :plain];
    codes:`red`green`yellow`blue`magenta`cyan`bold!
        (31;32;33;34;35;36;1);
    valid:.[{[color;palette] color in key palette};(c;codes);{[err] 0b}];
    if[not valid; :plain];
    "\033[",string[codes c],"m",plain,"\033[0m"
 };

.tst.diffBudget:{[name;default;hardMax]
    .tst.safeDiagnosticBudget[name;default;hardMax]
 };

.tst.diffDepthLimit:{[]
    .tst.diffBudget[`.tst.DIFF_MAX_DEPTH;6;6]
 };

.tst.diffCallableDepthLimit:{[]
    .tst.diffBudget[`.tst.DIFF_CALLABLE_MAX_DEPTH;12;12]
 };

.tst.diffCallableVectorLimit:{[]
    .tst.diffBudget[
        `.tst.DIFF_CALLABLE_VECTOR_ITEMS;
        65536;
        65536]
 };

.tst.diffNodeLimit:{[]
    .tst.diffBudget[`.tst.DIFF_MAX_NODES;64;64]
 };

.tst.diffLineLimit:{[]
    1 | .tst.diffBudget[`.tst.DIFF_MAX_LINES;40;40]
 };

.tst.diffCharLimit:{[]
    64 | .tst.diffBudget[`.tst.DIFF_MAX_CHARS;20000;20000]
 };

.tst.diffScanLimit:{[]
    .tst.diffBudget[`.tst.DIFF_SCAN_ITEMS;1048576;1048576]
 };

.tst.diffTableScanLimit:{[]
    .tst.diffBudget[
        `.tst.DIFF_TABLE_CELL_SCAN;
        2097152;
        2097152]
 };

.tst.diffColumnScanLimit:{[]
    .tst.diffBudget[`.tst.DIFF_COLUMN_SCAN;4096;4096]
 };

.tst.diffChunkLimit:{[]
    1 | .tst.diffBudget[`.tst.DIFF_CHUNK_SIZE;256;256]
 };

.tst.diffMismatchLimit:{[]
    1 | .tst.diffBudget[`.tst.DIFF_MISMATCH_LIMIT;5;5]
 };

.tst.diffProbeLimit:{[]
    1 | .tst.diffBudget[`.tst.DIFF_PROBE_ITEMS;4096;4096]
 };

/ Outer wrapping distinguishes a successful return from an error even when the
/ returned value itself resembles either tag.
.tst.diffMatchState:{[left;right]
    .[
        {[x;y] (`ok;enlist x~y)};
        (left;right);
        {[err] (`error;enlist err)}]
 };

.tst.diffMatches:{[left;right]
    state:.tst.diffMatchState[left;right];
    (`ok~first state) and 1b~first last state
 };

.tst.diffProbeResult:{[state;used]
    `state`used!(state;used)
 };

.tst.diffNativeMatchProbe:{[left;right]
    matched:.tst.diffMatchState[left;right];
    if[`error~first matched;
        :.tst.diffProbeResult[`unknown;1]];
    .tst.diffProbeResult[
        $[1b~first last matched;`equal;`different];
        1]
 };

.tst.diffBoxedMatchProbe:{[leftBox;rightBox]
    matched:.[
        {[xBox;yBox]
            (`ok;enlist (first xBox)~first yBox)
          };
        (leftBox;rightBox);
        {[err] (`error;enlist err)}];
    if[`error~first matched;
        :.tst.diffProbeResult[`unknown;1]];
    .tst.diffProbeResult[
        $[1b~first last matched;`equal;`different];
        1]
 };

.tst.diffProbeBoxed:{[leftBox;rightBox;depth;work]
    leftType:type first leftBox;
    rightType:type first rightBox;
    if[leftType<>rightType;
        :.tst.diffProbeResult[`different;1]];
    / A projection hole is represented by a type-101 value that turns a direct
    / function call into another projection. Keep it boxed while matching.
    if[101h=leftType;
        :.tst.diffBoxedMatchProbe[leftBox;rightBox]];
    .tst.diffProbe[
        first leftBox;
        first rightBox;
        depth;
        work]
 };

.tst.diffCallableLayoutState:{[callable]
    .[
        {[fn] (`ok;enlist value fn)};
        enlist callable;
        {[err] (`error;enlist err)}]
 };

.tst.diffShapeSeparate:{[leftBox;rightBox;depth;work]
    if[2>work; :.tst.diffProbeResult[`unknown;1]];
    leftWork:work div 2;
    rightWork:work-leftWork;
    leftShape:.tst.diffShapePair[
        leftBox;
        leftBox;
        depth;
        leftWork];
    leftUsed:leftWork & (1 | leftShape`used);
    if[not `safe~leftShape`state;
        :.tst.diffProbeResult[`unknown;leftUsed]];
    rightShape:.tst.diffShapePair[
        rightBox;
        rightBox;
        depth;
        rightWork];
    rightUsed:rightWork & (1 | rightShape`used);
    used:leftUsed+rightUsed;
    if[not `safe~rightShape`state;
        :.tst.diffProbeResult[`unknown;used]];
    .tst.diffProbeResult[`safe;used]
 };

.tst.diffShapeVectorPair:{[leftBox;rightBox;depth;work]
    left:first leftBox;
    right:first rightBox;
    counts:(count left;count right);
    if[(counts 0)<>(counts 1);
        :.tst.diffShapeSeparate[
            leftBox;
            rightBox;
            depth;
            work]];
    n:counts 0;
    if[n>.tst.diffCallableVectorLimit[];
        :.tst.diffProbeResult[`unknown;1]];
    chunkSize:.tst.diffChunkLimit[];
    chunks:$[0=n;0;(n+chunkSize-1) div chunkSize];
    needed:1+chunks;
    if[needed>work;
        :.tst.diffProbeResult[`unknown;work]];
    .tst.diffProbeResult[`safe;needed]
 };

.tst.diffShapeListPair:{[leftBox;rightBox;depth;work]
    left:first leftBox;
    right:first rightBox;
    counts:(count left;count right);
    if[(counts 0)<>(counts 1);
        :.tst.diffShapeSeparate[
            leftBox;
            rightBox;
            depth;
            work]];
    n:counts 0;
    used:1;
    remaining:work-used;
    if[(0<n) and 0>=depth;
        :.tst.diffProbeResult[`unknown;used]];
    i:0;
    while[(i<n) and 0<remaining;
        child:.tst.diffShapePair[
            enlist left i;
            enlist right i;
            depth-1;
            remaining];
        childUsed:remaining & (1 | child`used);
        used+:childUsed;
        remaining-:childUsed;
        if[not `safe~child`state;
            :.tst.diffProbeResult[`unknown;used]];
        i+:1;
    ];
    if[i<n; :.tst.diffProbeResult[`unknown;used]];
    .tst.diffProbeResult[`safe;used]
 };

.tst.diffShapeDictPair:{[leftBox;rightBox;depth;work]
    if[2>work; :.tst.diffProbeResult[`unknown;1]];
    left:first leftBox;
    right:first rightBox;
    layouts:.[
        {[x;y] ((key x;value x);(key y;value y))};
        (left;right);
        {[err] ()}];
    if[2<>count layouts;
        :.tst.diffProbeResult[`unknown;1]];
    child:.tst.diffShapePair[
        enlist layouts 0;
        enlist layouts 1;
        depth-1;
        work-1];
    used:1+(work-1) & (1 | child`used);
    .tst.diffProbeResult[
        $[`safe~child`state;`safe;`unknown];
        used]
 };

.tst.diffShapeTablePair:{[leftBox;rightBox;depth;work]
    if[2>work; :.tst.diffProbeResult[`unknown;1]];
    layouts:.[
        {[x;y] (flip x;flip y)};
        (first leftBox;first rightBox);
        {[err] ()}];
    if[2<>count layouts;
        :.tst.diffProbeResult[`unknown;1]];
    child:.tst.diffShapePair[
        enlist layouts 0;
        enlist layouts 1;
        depth-1;
        work-1];
    used:1+(work-1) & (1 | child`used);
    .tst.diffProbeResult[
        $[`safe~child`state;`safe;`unknown];
        used]
 };

.tst.diffShapeCallablePair:{[leftBox;rightBox;depth;work]
    if[2>work; :.tst.diffProbeResult[`unknown;1]];
    if[0>=depth; :.tst.diffProbeResult[`unknown;1]];
    leftLayout:.tst.diffCallableLayoutState first leftBox;
    rightLayout:.tst.diffCallableLayoutState first rightBox;
    if[
        (`error~first leftLayout) or
        `error~first rightLayout;
        :.tst.diffProbeResult[`unknown;1]
    ];
    child:.tst.diffShapePair[
        enlist first last leftLayout;
        enlist first last rightLayout;
        depth-1;
        work-1];
    used:1+(work-1) & (1 | child`used);
    .tst.diffProbeResult[
        $[`safe~child`state;`safe;`unknown];
        used]
 };

.tst.diffShapePairUnsafe:{[leftBox;rightBox;depth;work]
    if[0>=work; :.tst.diffProbeResult[`unknown;0]];
    leftType:type first leftBox;
    rightType:type first rightBox;
    if[leftType<>rightType;
        :.tst.diffShapeSeparate[
            leftBox;
            rightBox;
            depth;
            work]];
    t:leftType;
    if[t within -19 -1h;
        :.tst.diffProbeResult[`safe;1]];
    if[t within 101 103h;
        :.tst.diffProbeResult[`safe;1]];
    if[t within 1 19h;
        :.tst.diffShapeVectorPair[
            leftBox;
            rightBox;
            depth;
            work]];
    if[0h=t;
        :.tst.diffShapeListPair[
            leftBox;
            rightBox;
            depth;
            work]];
    if[99h=t;
        :.tst.diffShapeDictPair[
            leftBox;
            rightBox;
            depth;
            work]];
    if[98h=t;
        :.tst.diffShapeTablePair[
            leftBox;
            rightBox;
            depth;
            work]];
    if[t within 100 112h;
        :.tst.diffShapeCallablePair[
            leftBox;
            rightBox;
            depth;
            work]];
    .tst.diffProbeResult[`unknown;1]
 };

.tst.diffShapePair:{[leftBox;rightBox;depth;work]
    safeWork:.tst.diffProbeLimit[] & .tst.capLimit work;
    safeDepth:.tst.diffCallableDepthLimit[] &
        .tst.capLimit depth;
    .[
        .tst.diffShapePairUnsafe;
        (leftBox;rightBox;safeDepth;safeWork);
        {[err] .tst.diffProbeResult[`unknown;1]}]
 };

.tst.diffProbeCallable:{[left;right;depth;work]
    t:type left;
    / Primitive operators have no captured user-state graph.
    if[t within 101 103h;
        :.tst.diffNativeMatchProbe[left;right]];
    if[(0>=depth) or 2>work;
        :.tst.diffProbeResult[`unknown;1]];

    leftLayout:.tst.diffCallableLayoutState left;
    rightLayout:.tst.diffCallableLayoutState right;
    if[
        (`error~first leftLayout) or
        `error~first rightLayout;
        :.tst.diffProbeResult[`unknown;1]
    ];

    shape:.tst.diffShapePair[
        enlist first last leftLayout;
        enlist first last rightLayout;
        .tst.diffCallableDepthLimit[];
        work-1];
    shapeUsed:(work-1) & (1 | shape`used);
    used:1+shapeUsed;
    if[not `safe~shape`state;
        :.tst.diffProbeResult[`unknown;used]];

    matched:.tst.diffNativeMatchProbe[left;right];
    .tst.diffProbeResult[matched`state;used]
 };

.tst.diffProbeList:{[left;right;depth;work]
    n:count left;
    used:1;
    remaining:work-used;
    i:0;
    while[(i<n) and (0<remaining);
        child:.tst.diffProbeBoxed[
            enlist left i;
            enlist right i;
            depth-1;
            remaining];
        childUsed:child`used;
        if[0>=childUsed; childUsed:1];
        childUsed:remaining & childUsed;
        used+:childUsed;
        remaining-:childUsed;
        if[`different~child`state;
            :.tst.diffProbeResult[`different;used]];
        if[`unknown~child`state;
            :.tst.diffProbeResult[`unknown;used]];
        i+:1;
    ];
    if[i<n; :.tst.diffProbeResult[`unknown;used]];
    / q list attributes are storage/performance metadata, not value.
    .tst.diffProbeResult[`equal;used]
 };

.tst.diffProbeDict:{[left;right;depth;work]
    layout:.[
        {[x;y] (key x;value x;key y;value y)};
        (left;right);
        {[err] ()}];
    if[4<>count layout;
        :.tst.diffProbeResult[`unknown;1]];
    used:1;
    remaining:work-used;
    keyProbe:.tst.diffProbeBoxed[
        enlist layout 0;
        enlist layout 2;
        depth-1;
        remaining];
    keyUsed:remaining & (1 | keyProbe`used);
    used+:keyUsed;
    remaining-:keyUsed;
    if[`different~keyProbe`state;
        :.tst.diffProbeResult[`different;used]];
    if[`unknown~keyProbe`state;
        :.tst.diffProbeResult[`unknown;used]];
    if[0>=remaining;
        :.tst.diffProbeResult[`unknown;used]];
    valueProbe:.tst.diffProbeBoxed[
        enlist layout 1;
        enlist layout 3;
        depth-1;
        remaining];
    valueUsed:remaining & (1 | valueProbe`used);
    used+:valueUsed;
    if[`different~valueProbe`state;
        :.tst.diffProbeResult[`different;used]];
    if[`unknown~valueProbe`state;
        :.tst.diffProbeResult[`unknown;used]];
    .tst.diffProbeResult[`equal;used]
 };

.tst.diffProbeTable:{[left;right;depth;work]
    columns:.[
        {[x;y] (cols x;cols y)};
        (left;right);
        {[err] ()}];
    if[2<>count columns;
        :.tst.diffProbeResult[`unknown;1]];
    used:1;
    remaining:work-used;
    columnProbe:.tst.diffProbeBoxed[
        enlist columns 0;
        enlist columns 1;
        depth-1;
        remaining];
    columnUsed:remaining & (1 | columnProbe`used);
    used+:columnUsed;
    remaining-:columnUsed;
    if[`different~columnProbe`state;
        :.tst.diffProbeResult[`different;used]];
    if[`unknown~columnProbe`state;
        :.tst.diffProbeResult[`unknown;used]];
    ncols:count columns 0;
    i:0;
    while[(i<ncols) and (0<remaining);
        leftColumn:.[
            {[table;name] table name};
            (left;(columns 0)i);
            {[err] ::}];
        rightColumn:.[
            {[table;name] table name};
            (right;(columns 1)i);
            {[err] ::}];
        cellProbe:.tst.diffProbeBoxed[
            enlist leftColumn;
            enlist rightColumn;
            depth-1;
            remaining];
        cellUsed:remaining & (1 | cellProbe`used);
        used+:cellUsed;
        remaining-:cellUsed;
        if[`different~cellProbe`state;
            :.tst.diffProbeResult[`different;used]];
        if[`unknown~cellProbe`state;
            :.tst.diffProbeResult[`unknown;used]];
        i+:1;
    ];
    if[i<ncols; :.tst.diffProbeResult[`unknown;used]];
    .tst.diffProbeResult[`equal;used]
 };

/ Bounded tri-state comparator for nested diagnostic values. It returns
/ `equal, `different, or `unknown; unknown means the supplied structural work
/ budget could not prove either answer. Fixed-size atoms, callable leaves, and
/ bounded simple-vector prefixes use trapped native match.
.tst.diffProbeUnsafe:{[left;right;depth;work]
    if[0>=work; :.tst.diffProbeResult[`unknown;0]];
    types:(type left;type right);
    if[(types 0)<>(types 1);
        :.tst.diffProbeResult[`different;1]];
    t:types 0;

    if[t within -19 -1h;
        :.tst.diffNativeMatchProbe[left;right]
    ];

    / Variable callables may capture attacker-sized state. Their non-invoking
    / layouts must fit the shared depth/work budget before trapped native match.
    if[t within 100 112h;
        :.tst.diffProbeCallable[left;right;depth;work]
    ];

    counts:.[
        {[x;y] (count x;count y)};
        (left;right);
        {[err] ()}];
    if[2<>count counts; :.tst.diffProbeResult[`unknown;1]];
    if[(counts 0)<>(counts 1);
        :.tst.diffProbeResult[`different;1]];
    n:counts 0;
    if[0>=depth; :.tst.diffProbeResult[`unknown;1]];

    if[t within 1 19h;
        remaining:work-1;
        takeN:n & remaining;
        candidate:$[
            n<=remaining;
            .tst.diffMatchState[left;right];
            .tst.diffMatchState[
                takeN sublist left;
                takeN sublist right]];
        if[`error~first candidate;
            :.tst.diffProbeResult[`unknown;1+takeN]];
        if[not 1b~first last candidate;
            :.tst.diffProbeResult[`different;1+takeN]];
        :.tst.diffProbeResult[
            $[takeN=n;`equal;`unknown];
            1+takeN]
    ];

    if[0h=t;
        :.tst.diffProbeList[left;right;depth;work]];
    if[99h=t;
        :.tst.diffProbeDict[left;right;depth;work]];
    if[98h=t;
        :.tst.diffProbeTable[left;right;depth;work]];

    / Enumerated vectors can hide attacker-sized recursive state. Report
    / unknown instead of invoking full match.
    .tst.diffProbeResult[`unknown;1]
 };

.tst.diffProbe:{[left;right;depth;work]
    safeWork:.tst.diffProbeLimit[] & .tst.capLimit work;
    safeDepth:.tst.diffDepthLimit[] &
        .tst.capLimit depth;
    .[
        .tst.diffProbeUnsafe;
        (left;right;safeDepth;safeWork);
        {[err] .tst.diffProbeResult[`unknown;1]}]
 };

.tst.diffFlatSequence:{[input;limit]
    n:@[count;input;{[err] -1}];
    if[(0>n) or n>limit; :0b];
    t:type input;
    if[t within 1 19h; :1b];
    if[0h<>t; :0b];
    chunkSize:.tst.diffChunkLimit[];
    pos:0;
    flat:1b;
    while[(pos<n) and flat;
        takeN:chunkSize & n-pos;
        itemTypes:type each input pos+til takeN;
        if[not all (itemTypes within -19 -1h);
            flat:0b];
        pos+:takeN;
    ];
    flat
 };

.tst.diffFlatTable:{[table]
    columns:@[cols;table;{[err] ()}];
    ncols:count columns;
    if[ncols>.tst.diffColumnScanLimit[]; :0b];
    rows:@[count;table;{[err] -1}];
    if[0>rows; :0b];
    cellLimit:.tst.diffTableScanLimit[];
    if[
        (0<ncols) and
        ncols>cellLimit div (1 | rows);
        :0b];
    i:0;
    flat:1b;
    while[(i<ncols) and flat;
        columnState:.[
            {[source;name] source name};
            (table;columns i);
            {[err] ::}];
        if[not .tst.diffFlatSequence[columnState;rows];
            flat:0b];
        i+:1;
    ];
    flat
 };

.tst.diffFlatDict:{[dictionary]
    layout:@[
        {[input] (key input;value input)};
        dictionary;
        {[err] ()}];
    if[2<>count layout; :0b];
    if[98h=type layout 0;
        :(.tst.diffFlatTable[layout 0]) and
            .tst.diffFlatTable[layout 1]];
    n:count layout 0;
    if[n>.tst.diffScanLimit[] div 2; :0b];
    (.tst.diffFlatSequence[layout 0;n]) and
        .tst.diffFlatSequence[layout 1;n]
 };

.tst.diffFlatValue:{[input]
    t:type input;
    if[t within -19 -1h; :1b];
    if[t within 1 19h;
        :.tst.diffFlatSequence[
            input;
            .tst.diffScanLimit[]]];
    if[0h=t;
        :.tst.diffFlatSequence[
            input;
            .tst.diffScanLimit[]]];
    if[98h=t; :.tst.diffFlatTable input];
    if[99h=t; :.tst.diffFlatDict input];
    if[t within 101 103h; :1b];
    0b
 };

/ Exact match is allowed only after a bounded shape proof establishes that all
/ recursively visited payload is flat and below literal work ceilings.
/ Otherwise the recursive tri-state probe decides or reports `unknown.
.tst.diffSafeMatchState:{[left;right]
    types:(type left;type right);
    if[(types 0)<>(types 1);
        :.tst.diffProbeResult[`different;1]];
    flatState:.[
        {[x;y]
            (.tst.diffFlatValue x;.tst.diffFlatValue y)
          };
        (left;right);
        {[err] 0b 0b}];
    if[all flatState;
        exact:.tst.diffMatchState[left;right];
        if[`error~first exact;
            :.tst.diffProbeResult[`unknown;1]];
        :.tst.diffProbeResult[
            $[1b~first last exact;`equal;`different];
            1]
    ];
    .tst.diffProbe[
        left;
        right;
        .tst.diffDepthLimit[];
        .tst.diffProbeLimit[]]
 };

/ Scan equal-length sequences in fixed-size chunks. At most chunkSize booleans
/ and indices are live at once; nested composite values use the tri-state probe
/ and share one literal-clamped structural budget.
.tst.diffScanMismatches:{[left;right;scanCap;wanted]
    n:count left;
    stop:n & scanCap;
    found:`long$();
    pos:0;
    comparisonRemaining:.tst.diffProbeLimit[];
    comparisonExhausted:0b;
    while[
        ((pos<stop) and
        ((count found)<wanted)) and
        not comparisonExhausted;
        leftType:type left pos;
        rightType:type right pos;
        if[leftType<>rightType;
            found,:pos;
            pos+:1];
        if[
            (leftType=rightType) and
            leftType within -19 -1h;
            matched:.tst.diffMatchState[left pos;right pos];
            if[
                (`ok~first matched) and
                not 1b~first last matched;
                found,:pos];
            if[`error~first matched; comparisonExhausted:1b];
            pos+:1];
        if[
            (leftType=rightType) and
            not leftType within -19 -1h;
            if[0>=comparisonRemaining;
                comparisonExhausted:1b;
                pos+:1];
            if[not comparisonExhausted;
                probe:.tst.diffProbeBoxed[
                    enlist left pos;
                    enlist right pos;
                    .tst.diffDepthLimit[];
                    comparisonRemaining];
                used:probe`used;
                if[0>=used; used:1];
                used:comparisonRemaining & used;
                comparisonRemaining-:used;
                if[`different~probe`state; found,:pos];
                if[`unknown~probe`state;
                    comparisonExhausted:1b];
                pos+:1]];
    ];
    `indices`scanned`scanExhausted`comparisonExhausted`outputLimited!(
        found;
        pos;
        (stop<n) or comparisonExhausted;
        comparisonExhausted;
        (count[found]>=wanted) and pos<n)
 };

.tst.diffPath:{[path;suffix]
    $[count path;path,suffix;suffix]
 };

.tst.fmtVal:{[val;color]
    .tst.fmt.color[color;.tst.renderValue[val;1024]]
 };

.tst.diffBudgetLine:{[path;detail]
    prefix:$[count path;path,": ";""];
    enlist prefix,"Diff budget exhausted (",detail,")"
 };

.tst.diffList:{[path;expected;actual;depth;nodes]
    nExpected:count expected;
    nActual:count actual;
    prefix:$[count path;path,": ";""];
    if[nExpected<>nActual;
        :(
            prefix,"Count mismatch";
            "  Expected len: ",.tst.fmtVal[nExpected;`green];
            "  Actual len:   ",.tst.fmtVal[nActual;`red])
    ];
    scanResult:.tst.diffScanMismatches[
        expected;
        actual;
        .tst.diffScanLimit[];
        .tst.diffMismatchLimit[]];
    bad:scanResult`indices;
    if[0=count bad;
        if[scanResult`scanExhausted;
            :(
                prefix,"List content mismatch";
                "  Deterministic scan budget exhausted after ",
                string[scanResult`scanned]," items")];
        :enlist prefix,"List value mismatch (structural difference)"
    ];
    available:0 | nodes-1;
    detailCount:(count bad) & available;
    lines:enlist prefix,"List content mismatch (showing first ",
        string[detailCount]," mismatches):";
    if[0=detailCount;
        lines,:.tst.diffBudgetLine[path;"node limit"];
        :lines];
    detailBad:detailCount sublist bad;
    childNodes:available div detailCount;
    nested:{
        [base;ex;ac;childDepth;childNodes;i]
        childPath:.tst.diffPath[base;"[",string[i],"]"];
        .tst.diffDeep[
            childPath;
            ex i;
            ac i;
            childDepth;
            childNodes]
      }[path;expected;actual;depth-1;childNodes;] each detailBad;
    lines,:raze nested;
    if[detailCount<count bad;
        lines,:enlist "  Further mismatch detail omitted (node budget)"];
    if[scanResult`scanExhausted;
        lines,:enlist "  Deterministic scan budget exhausted after ",
            string[scanResult`scanned]," items"];
    if[scanResult`outputLimited;
        lines,:enlist "  Further comparison/detail omitted (output budget)"];
    lines
 };

.tst.diffDict:{[path;expected;actual;depth;nodes]
    keysExpected:key expected;
    keysActual:key actual;
    valsExpected:value expected;
    valsActual:value actual;
    prefix:$[count path;path,": ";""];

    / Compare keyed tables through their unkeyed columnar views. This avoids
    / recursively claiming a diff for whichever key/value side is actually equal.
    if[(98h=type keysExpected) or 98h=type keysActual;
        :.tst.diffDeep[
            path;
            0!expected;
            0!actual;
            depth-1;
            nodes-1]
    ];

    nExpected:count keysExpected;
    nActual:count keysActual;
    commonCount:nExpected & nActual;
    keyScan:.tst.diffScanMismatches[
        keysExpected;
        keysActual;
        .tst.diffScanLimit[] & commonCount;
        .tst.diffMismatchLimit[]];
    if[(nExpected<>nActual) or count keyScan`indices;
        lines:enlist prefix,"Dictionary key mismatch";
        if[nExpected<>nActual;
            lines,:(
                "  Expected key count: ",string nExpected;
                "  Actual key count:   ",string nActual)];
        if[count keyScan`indices;
            lines,:{
                [ke;ka;i]
                "  Key position ",string[i],": Expected=",
                .tst.renderValue[ke i;256]," Actual=",
                .tst.renderValue[ka i;256]
              }[keysExpected;keysActual;] each keyScan`indices];
        if[keyScan`scanExhausted;
            lines,:enlist "  Deterministic key scan budget exhausted"];
        :lines
    ];
    if[keyScan`scanExhausted;
        :(
            prefix,"Dictionary mismatch";
            "  Key scan budget exhausted before value alignment was proven")
    ];

    scanResult:.tst.diffScanMismatches[
        valsExpected;
        valsActual;
        .tst.diffScanLimit[];
        .tst.diffMismatchLimit[]];
    bad:scanResult`indices;
    if[0=count bad;
        if[scanResult`scanExhausted;
            :(
                prefix,"Dictionary value mismatch";
                "  Deterministic value scan budget exhausted")];
        :enlist prefix,"Dictionary value mismatch (structural difference)"
    ];
    available:0 | nodes-1;
    detailCount:(count bad) & available;
    if[0=detailCount;
        :.tst.diffBudgetLine[path;"node limit"]];
    detailBad:detailCount sublist bad;
    childNodes:available div detailCount;
    nested:{
        [base;ev;av;childDepth;childNodes;i]
        childPath:.tst.diffPath[base;".value[",string[i],"]"];
        .tst.diffDeep[
            childPath;
            ev i;
            av i;
            childDepth;
            childNodes]
      }[path;valsExpected;valsActual;depth-1;childNodes;] each detailBad;
    lines:raze nested;
    if[detailCount<count bad;
        lines,:enlist "  Further dictionary detail omitted (node budget)"];
    if[scanResult`scanExhausted;
        lines,:enlist "  Deterministic dictionary scan budget exhausted"];
    if[scanResult`outputLimited;
        lines,:enlist "  Dictionary scan stopped at the output limit"];
    lines
 };

/ Scan table columns and their rows incrementally. The comparison budget is
/ shared across columns so hostile row*column shapes have bounded total work.
.tst.diffScanTable:{[expected;actual]
    columns:cols expected;
    rowCount:count expected;
    wanted:.tst.diffMismatchLimit[];
    workCap:.tst.diffTableScanLimit[];
    cells:();
    used:0;
    columnIndex:0;
    exhausted:0b;
    while[
        ((columnIndex<count columns) and
        (count[cells]<wanted)) and
        (used<workCap);
        remaining:workCap-used;
        rowCap:rowCount & remaining;
        leftColumn:expected[columns columnIndex];
        rightColumn:actual[columns columnIndex];
        scanResult:.tst.diffScanMismatches[
            leftColumn;
            rightColumn;
            rowCap;
            wanted-count cells];
        if[count scanResult`indices;
            cells,:{
                [ci;row] (row;ci)
              }[columnIndex;] each scanResult`indices];
        used+:1 | scanResult`scanned;
        if[scanResult`scanExhausted; exhausted:1b];
        if[scanResult`scanExhausted; columnIndex:count columns];
        if[not scanResult`scanExhausted; columnIndex+:1];
    ];
    if[
        (columnIndex<count columns) and count[cells]<wanted;
        exhausted:1b];
    `cells`scanned`scanExhausted`outputLimited!(
        cells;
        used;
        exhausted;
        (count[cells]>=wanted) and
            ((columnIndex<count columns) or used<workCap))
 };

.tst.diffTable:{[path;expected;actual;depth;nodes]
    colsExpected:cols expected;
    colsActual:cols actual;
    prefix:$[count path;path,": ";""];
    commonCount:count[colsExpected] & count colsActual;
    columnScan:.tst.diffScanMismatches[
        colsExpected;
        colsActual;
        .tst.diffColumnScanLimit[] & commonCount;
        .tst.diffMismatchLimit[]];
    if[
        (count[colsExpected]<>count colsActual) or
        count columnScan`indices;
        lines:(
            prefix,"Column mismatch";
            "  Expected: ",.tst.fmtVal[colsExpected;`green];
            "  Actual:   ",.tst.fmtVal[colsActual;`red]);
        if[count columnScan`indices;
            lines,:enlist "  First differing column positions: ",
                .tst.renderValue[columnScan`indices;256]];
        if[columnScan`scanExhausted;
            lines,:enlist "  Deterministic column scan budget exhausted"];
        :lines
    ];
    if[columnScan`scanExhausted;
        :(
            prefix,"Column mismatch";
            "  Column scan budget exhausted before metadata equality was proven")
    ];

    nExpected:count expected;
    nActual:count actual;
    if[nExpected<>nActual;
        :(
            prefix,"Count mismatch (Alignment might be off)";
            "  Expected rows: ",.tst.fmtVal[nExpected;`green];
            "  Actual rows:   ",.tst.fmtVal[nActual;`red])
    ];

    scanResult:.tst.diffScanTable[expected;actual];
    cells:scanResult`cells;
    lines:enlist prefix,"Table content mismatch";
    if[0=count cells;
        if[scanResult`scanExhausted;
            lines,:enlist "  Deterministic cell scan budget exhausted after ",
                string[scanResult`scanned]," comparisons";
            :lines];
        lines,:enlist "  Structural/attribute difference";
        :lines
    ];
    available:0 | nodes-1;
    detailCount:(count cells) & available;
    if[0=detailCount;
        lines,:.tst.diffBudgetLine[path;"node limit"];
        :lines];
    detailCells:detailCount sublist cells;
    childNodes:available div detailCount;
    nested:{
        [base;ex;ac;columns;childDepth;childNodes;cell]
        row:cell 0;
        ci:cell 1;
        leftColumn:ex[columns ci];
        rightColumn:ac[columns ci];
        childPath:.tst.diffPath[
            base;
            ".row[",string[row],"].col[",string[ci],"]"];
        .tst.diffDeep[
            childPath;
            leftColumn row;
            rightColumn row;
            childDepth;
            childNodes]
      }[
        path;
        expected;
        actual;
        colsExpected;
        depth-1;
        childNodes;] each detailCells;
    lines,:raze nested;
    if[detailCount<count cells;
        lines,:enlist "  Further table detail omitted (node budget)"];
    if[scanResult`scanExhausted;
        lines,:enlist "  Deterministic cell scan budget exhausted"];
    if[scanResult`outputLimited;
        lines,:enlist "  Cell scan stopped at the output limit"];
    lines
 };

/ Recursive semantic diff. Equality is always checked first, so an exactly
/ matching value returns no diagnostics regardless of type-specific formatting.
.tst.diffDeep:{[path;expected;actual;depth;nodes]
    if[0>=nodes; :.tst.diffBudgetLine[path;"node limit"]];
    if[0>=depth; :.tst.diffBudgetLine[path;"depth limit"]];

    types:@[
        {[pair] (type pair 0;type pair 1)};
        (expected;actual);
        {[err] ()}];
    if[2<>count types;
        :(
            $[count path;path,": ";""],"Value mismatch";
            "  Type inspection unavailable")];
    typeExpected:types 0;
    typeActual:types 1;
    prefix:$[count path;path,": ";""];
    if[typeExpected<>typeActual;
        :(
            prefix,"Type mismatch";
            "  Expected type: ",.tst.fmtVal[typeExpected;`green];
            "  Actual type:   ",.tst.fmtVal[typeActual;`red])
    ];
    if[99h=typeExpected;
        :.tst.diffDict[path;expected;actual;depth;nodes]];
    if[98h=typeExpected;
        :.tst.diffTable[path;expected;actual;depth;nodes]];
    if[typeExpected within 0 19h;
        :.tst.diffList[path;expected;actual;depth;nodes]];
    (
        prefix,"Value mismatch";
        "  Expected: ",.tst.fmtVal[expected;`green];
        "  Actual:   ",.tst.fmtVal[actual;`red])
 };

/ Flatten only bounded prefixes of arbitrary results. This function is public
/ compatibility surface, so it is defensive even when called with hostile input
/ unrelated to diffDeep.
.tst.flattenDiffBounded:{[res;depth]
    if[10h=type res; :enlist .tst.capString[res;2048]];
    if[(0h<>type res) or 0>=depth;
        :enlist .tst.renderValue[res;512]];
    n:count res;
    takeN:n & 16;
    nested:.tst.flattenDiffBounded[;depth-1] each takeN sublist res;
    lines:raze nested;
    if[n>takeN;
        lines,:enlist "(nested diff input omitted by normalization budget)"];
    lines
 };

.tst.boundDiffLines:{[lines]
    maxLines:.tst.diffLineLimit[];
    maxChars:.tst.diffCharLimit[];
    marker:"(diff output budget exhausted)";
    contentLines:0 | maxLines-1;
    contentChars:0 | ((maxChars-1)-count marker);
    out:();
    used:0;
    i:0;
    exhausted:0b;
    while[
        (i<count lines) and
        (count[out]<contentLines) and
        used<contentChars;
        line:$[10h=type lines i;
            lines i;
            .tst.renderValue[lines i;512]];
        room:(contentChars-used)-$[count out;1;0];
        if[0>=room; exhausted:1b];
        if[0<room;
            capped:.tst.capString[line;2048 & room];
            if[count[capped]<count line; exhausted:1b];
            out,:enlist capped;
            used+:count[capped]+$[1<count out;1;0]];
        i+:1;
    ];
    if[i<count lines; exhausted:1b];
    if[exhausted;
        room:(maxChars-used)-$[count out;1;0];
        if[0<room; out,:enlist .tst.capString[marker;room]];
        if[0=count out; out:enlist .tst.capString[marker;maxChars]]];
    out
 };

/ Normalize into a flat bounded list of plain strings.
.tst.normalizeDiff:{[res]
    lines:.tst.flattenDiffBounded[res;2];
    .tst.boundDiffLines lines
 };

/ Detailed deterministic difference between two objects.
.tst.diffKnownMismatch:{[expected;actual]
    raw:.[
        .tst.diffDeep;
        (
            "";
            expected;
            actual;
            .tst.diffDepthLimit[];
            .tst.diffNodeLimit[]);
        {[err]
            enlist "(diff unavailable: ",
                .tst.capString[err;256],")"}];
    normalized:.tst.normalizeDiff raw;
    if[0=count normalized;
        normalized:enlist "(diff budget exhausted before mismatch detail)"];
    normalized
 };

.tst.diff:{[expected;actual]
    initial:.tst.diffSafeMatchState[expected;actual];
    if[`equal~initial`state; :()];
    if[`unknown~initial`state;
        :.tst.normalizeDiff .tst.diffBudgetLine[
            "";
            "structural comparison limit"]];
    .tst.diffKnownMismatch[expected;actual]
 };

\d .
