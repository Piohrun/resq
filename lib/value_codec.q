/ value_codec.q - geometry-independent value equality and evidence rendering
\d .tst

.tst.VALUE_CODEC_NAME:"resq-value-v1+q-ipc-leaves";
.tst.VALUE_CODEC_VERSION:1j;

.tst.valueHexBytes:{[bytes]
    digits:"0123456789abcdef";
    numbers:"j"$bytes;
    if[0=count numbers;:""];
    raze {[alphabet;n]
        (alphabet n div 16),alphabet n mod 16}[digits;] each numbers
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

.tst.valueCodecMetadata:{[]
    `name`version`qVersion`qRelease`ipcSerialization`capabilityLevel!(
        .tst.VALUE_CODEC_NAME;.tst.VALUE_CODEC_VERSION;string .z.K;string .z.k;
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

.tst.renderValueFull:{[raw]
    valueType:type raw;
    if[98h=valueType;
        :"table[",string[count raw],"](",.tst.renderValueFull[flip raw],")"];
    if[99h=valueType;
        dictKeys:key raw;dictValues:value raw;
        pairs:{[k;v].tst.renderValueFull[k],"=>",.tst.renderValueFull[v]}'[dictKeys;dictValues];
        :"dict[",string[count raw],"]{",$[count pairs;", " sv pairs;""],"}"];
    if[0h=valueType;
        items:.tst.renderValueFull each raw;
        :"list[",string[count raw],"](",$[count items;", " sv items;""],")"];
    if[10h=valueType;:.j.j raw];
    if[(valueType>0h) and valueType<20h;
        items:.tst.renderAtomFull each raw;
        if[0=count items;:"vector[type=",string[valueType],",count=0]()"];
        :$[11h=valueType;"" sv items;" " sv items]];
    .tst.renderAtomFull raw
 };

.tst.renderValueBounded:{[raw;maximum]
    full:.tst.renderValueFull raw;
    limit:0|"j"$maximum;
    if[count[full]<=limit;:full];
    digest:.tst.canonicalValueDigest .tst.canonicalValueBytes raw;
    marker:"... [truncated ",string[count full]," chars; md5=",digest,"]";
    if[limit<=count marker;:limit#marker];
    ((limit-count marker)#full),marker
 };

\d .
