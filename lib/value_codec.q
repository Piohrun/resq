/ value_codec.q - geometry-independent value equality and evidence rendering
\d .tst

.tst.VALUE_CODEC_NAME:"resq-value-v1+q-ipc-leaves";
.tst.VALUE_CODEC_VERSION:1j;

/ Lower-case hex of a byte vector. `string` is native over the whole vector;
/ a per-byte lambda made digesting a large value take seconds.
.tst.valueHexBytes:{[bytes]
    if[0=count bytes;:""];
    raze string (),bytes
 };

.tst.valueFrame:{[tag;payload]
    "(",string[count tag],":",tag,":",string[count payload],":",payload,")"
 };

/ resQ owns the recursive type/shape/length framing. Scalar/simple-vector leaf
/ payloads use q IPC bytes as a fidelity oracle, so the snapshot envelope pins
/ the exact q build and serialization mode before any comparison is attempted.
.tst.canonicalValueNode:{[raw]
    valueType:type raw;
    typeText:string valueType;
    if[98h=valueType;
        payload:.tst.canonicalValueNode flip raw;
        :.tst.valueFrame["table/",typeText,"/",string count raw;payload]];
    if[99h=valueType;
        payload:.tst.valueFrame["keys";.tst.canonicalValueNode key raw],
            .tst.valueFrame["values";.tst.canonicalValueNode value raw];
        :.tst.valueFrame["dict/",typeText,"/",string count raw;payload]];
    if[0h=valueType;
        nodes:.tst.canonicalValueNode each raw;
        payload:$[count nodes;raze .tst.valueFrame["item";] each nodes;""];
        :.tst.valueFrame["list/0/",string count raw;payload]];
    payload:.tst.valueHexBytes -8!raw;
    .tst.valueFrame["leaf/",typeText,"/",string count raw;payload]
 };

.tst.canonicalValueBytes:{[raw]
    .tst.valueFrame[.tst.VALUE_CODEC_NAME;.tst.canonicalValueNode raw]
 };

.tst.canonicalValueDigest:{[bytes]
    raze string md5 bytes
 };

/ q's release as text with one decimal. `string .z.K` is "4" on q 4.0 (.z.K
/ is 4f there) but "4.1" on q 4.1; reports, identity envelopes and benchmark
/ fingerprints all use this form.
.tst.formatQVersion:{[release] .Q.f[1;release]};

.tst.valueCodecMetadata:{[]
    `name`version`qVersion`qRelease`ipcSerialization`capabilityLevel!(
        .tst.VALUE_CODEC_NAME;.tst.VALUE_CODEC_VERSION;.tst.formatQVersion .z.K;string .z.k;
        "q unary -8!/-9!";
        "local unary serialization; no negotiated IPC connection capability")
 };

.tst.renderFloatAtom:{[raw;precision]
    if[null raw;:"0n"];
    if[raw=0w;:"0w"];
    if[raw=-0w;:"-0w"];
    / .Q.f overflows its decimal scale above 15 places. Format at the widest
    / safe precision, then attach exact bytes only when that decimal does not
    / reconstruct the value bit-for-bit. The suffix makes the evidence fully
    / distinguishing without consulting the process-wide display precision.
    digits:15&precision;
    rendered:.Q.f[digits;"f"$raw];
    roundTrip:@[{"F"$x};rendered;{0n}];
    / Compare in the operand's own width: "F"$ reparses to a float atom, so a
    / real (-8h) never matched and always carried the [ipc=...] suffix.
    if[-8h=type raw;roundTrip:"e"$roundTrip];
    if[(-8!roundTrip)~-8!raw;:rendered];
    rendered,"[ipc=",.tst.valueHexBytes[-8!raw],"]"
 };

.tst.renderAtomFull:{[raw]
    valueType:type raw;
    if[-10h=valueType;:.j.j enlist raw];
    if[-11h=valueType;:"`",string raw];
    if[-9h=valueType;:.tst.renderFloatAtom[raw;17]];
    if[-8h=valueType;:.tst.renderFloatAtom[raw;9]];
    rendered:string raw;
    $[10h=type rendered;rendered;
      0h=type rendered;"\n" sv rendered;
      .tst.valueHexBytes -8!raw]
 };

/ Rendering takes a character budget so that a failure on a large value costs
/ what is shown, not what the value holds. Every item renders to at least one
/ character, so `budget` leading items of a vector, or container items taken
/ until their text exceeds the budget, always cover the first `budget`
/ characters of the unbounded rendering. Headers keep the real counts. A budget
/ of 0W renders everything.
.tst.renderItemsWithin:{[render;items;budget]
    if[budget=0W;:render each items];
    out:enlist "";
    used:0;
    i:0;
    n:count items;
    while[(i<n) and used<=budget;
        text:render items i;
        out,:enlist text;
        used+:count text;
        i+:1];
    1 _ out
 };

.tst.leadingItems:{[raw;budget] $[budget<count raw;budget sublist raw;raw]};

.tst.renderValueFullWithin:{[raw;budget]
    valueType:type raw;
    if[98h=valueType;
        :"table[",string[count raw],"](",.tst.renderValueFullWithin[flip raw;budget],")"];
    if[99h=valueType;
        dictKeys:key raw;dictValues:value raw;
        pairs:.tst.renderItemsWithin[{[budget;i;k;v]
                .tst.renderValueFullWithin[k i;budget],"=>",.tst.renderValueFullWithin[v i;budget]
            }[budget;;dictKeys;dictValues];til count dictKeys;budget];
        :"dict[",string[count raw],"]{",$[count pairs;", " sv pairs;""],"}"];
    if[0h=valueType;
        items:.tst.renderItemsWithin[.tst.renderValueFullWithin[;budget];raw;budget];
        :"list[",string[count raw],"](",$[count items;", " sv items;""],")"];
    if[10h=valueType;:.j.j .tst.leadingItems[raw;budget]];
    if[(valueType>0h) and valueType<20h;
        if[0=count raw;:"vector[type=",string[valueType],",count=0]()"];
        items:.tst.renderAtomFull each .tst.leadingItems[raw;budget];
        :$[11h=valueType;"" sv items;" " sv items]];
    .tst.renderAtomFull raw
 };

.tst.renderValueFull:{[raw] .tst.renderValueFullWithin[raw;0W]};

/ Failure messages are read by people (console, JUnit failure text). Tables,
/ keyed tables, dictionaries and general lists render as q literals there.
/ renderValueFull stays the canonical form for toString and identities.
/ A float as a person would type it: q's own short form when that reads back
/ to the same bits, otherwise the exact evidence form. renderFloatAtom always
/ prints 15 or more places (2f as 2.000000000000000); identities depend on
/ that form, so it stays as it is and only failure messages use this one.
.tst.renderFloatHuman:{[raw]
    if[null raw; :$[-8h = type raw; "0Ne"; "0n"]];
    short: string raw;
    back: @[{"F"$x}; short; {[e] 0n}];
    if[-8h = type raw; back: "e"$back];
    $[(-8!back) ~ -8!raw; short; .tst.renderAtomFull raw]
 };

.tst.renderFloatsHuman:{[raw;budget]
    items: .tst.renderFloatHuman each .tst.leadingItems[(),raw;budget];
    text: " " sv items;
    / q needs a type suffix when nothing else marks the literal as a float.
    isReal: 8h = abs type raw;
    suffix: $[any items like "*ipc=*"; "";
        isReal; $["e" = last text; ""; "e"];
        any text in ".enw"; ""; "f"];
    text, suffix
 };

.tst.renderValueHumanWithin:{[raw;budget]
    valueType:type raw;
    / An enumerated value (a sym column of a splayed or partitioned table)
    / reads as the symbols it stands for.
    if[(abs valueType) within 20 76h;
        :.tst.renderValueHumanWithin[value raw;budget]];
    if[(abs valueType) in 8 9h;
        if[(valueType < 0h) or 1 < count raw;
            :.tst.renderFloatsHuman[raw;budget]]];
    columns:{[budget;table]
        names:cols table;
        columnValues:value flip table;
        "; " sv .tst.renderItemsWithin[{[budget;names;columnValues;i]
                string[names i],":",.tst.renderValueHumanWithin[columnValues i;budget]
            }[budget;names;columnValues];til count names;budget]}[budget];
    if[98h=valueType;:"([] ",columns[raw],")"];
    if[99h=valueType;
        if[(98h=type key raw) and 98h=type value raw;
            :"([",columns[key raw],"] ",columns[value raw],")"];
        :.tst.renderValueHumanWithin[key raw;budget],"!",.tst.renderValueHumanWithin[value raw;budget]];
    if[(valueType within 0 20h) and 1=count raw;
        :"enlist ",.tst.renderValueHumanWithin[first raw;budget]];
    if[0h=valueType;
        :"(",("; " sv .tst.renderItemsWithin[.tst.renderValueHumanWithin[;budget];raw;budget]),")"];
    .tst.renderValueFullWithin[raw;budget]
 };

.tst.renderValueHuman:{[raw] .tst.renderValueHumanWithin[raw;0W]};

/ The digest identifies the whole value, so it reads every byte. Above this
/ serialized size it is skipped rather than doubling a large value in memory.
.tst.TRUNCATION_DIGEST_MAX_BYTES:268435456j;

.tst.truncationMarker:{[raw]
    size:@[-22!;raw;{[e] 0W}];
    digest:$[size>.tst.TRUNCATION_DIGEST_MAX_BYTES;"";
        @[{.tst.canonicalValueDigest .tst.canonicalValueBytes x};raw;{[e] ""}]];
    "... [truncated",$[count digest;"; md5=",digest;"; value too large to digest"],"]"
 };

/ A rendering no longer than the limit is complete: the budget is one past the
/ limit, so anything left out would have pushed the text beyond it.
.tst.boundRendering:{[raw;maximum;render]
    limit:0|"j"$maximum;
    text:render[raw;limit+1];
    if[count[text]<=limit;:text];
    marker:.tst.truncationMarker raw;
    if[limit<=count marker;:limit#marker];
    ((limit-count marker)#text),marker
 };

.tst.renderValueHumanBounded:{[raw;maximum]
    .tst.boundRendering[raw;maximum;{[raw;budget]
        @[.tst.renderValueHumanWithin[;budget];raw;
            {[raw;budget;e] .tst.renderValueFullWithin[raw;budget]}[raw;budget]]}]
 };

.tst.renderValueBounded:{[raw;maximum]
    .tst.boundRendering[raw;maximum;.tst.renderValueFullWithin]
 };

\d .
