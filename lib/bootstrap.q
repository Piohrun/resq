/ Core path, filesystem and load invariants.
if[not `utl in key `; .utl: enlist[`]!enlist (::)];
if[not `loaded in key `.utl;.utl.loaded:0#enlist ""];
.utl.resqHomeAtBoot: @[get; `.resq.HOME; {""}];
.utl.DEBUG: 0b;
.utl.OS: $[(string .z.o) like "l*"; `linux; (string .z.o) like "m*"; `macos; `windows];
.utl.isLinux: .utl.OS = `linux;
.utl.isMac: .utl.OS = `macos;
.utl.isWindows: .utl.OS = `windows;
.utl.require:{[path]
    adapter:.utl.fsSnapshot[]; .utl.requireWith[adapter;path]};
/ Path policy
.utl.MAX_PATH_CHARACTERS:32768;
.utl.MAX_PATH_COMPONENTS:1024;
.utl.MAX_PATH_SYMBOLS:8192;
.utl.MAX_PATH_SYMBOL_BYTES:8388608;
.utl.hardLimit:{[configured;hardMaximum;label]
    if[not (type[configured] in -4 -5 -6 -7h);
        '"Invalid ",label," limit"]; if[null configured;'"Invalid ",label," limit"];
    n:"j"$configured; if[n < 0;'"Invalid ",label," limit"];
    n & "j"$hardMaximum};
.utl.attempt:{[function;arguments]
    .[{[f;a](1b;$[count a;f . a;f[]])};
      (function;arguments);{[e](0b;e)}]};
/ Never stringify arbitrary callback values.
.utl.boundedDiagnostic:{[diagnostic;requested]
    cap:$[type[requested] in -4 -5 -6 -7h;
        $[null requested;0;4096 & 0 | "j"$requested]; 0];
    t:type diagnostic; text:$[-10h=t;enlist diagnostic;
        10h=t;diagnostic; -11h=t;"<symbol>";
        t in -1 -2 -3 -4 -5 -6 -7 -8 -9 -12 -13 -14 -15 -16 -17 -18 -19h;
            @[string;diagnostic;{"<unrenderable scalar>"}];
        "Non-text diagnostic (q type ",string[t],")"];
    if[count[text] <= cap;:text]; mark:"... [truncated]";
    $[cap <= count mark;cap sublist mark;
      ((cap-count mark) sublist text),mark]};
.utl.pathToString:{[path]
    t:type path; if[-10h=t;:enlist path];
    if[10h=t;:$[path like ":*";1 _ path;path]]; if[-11h=t;
        s:string path; :$[s like ":*";1 _ s;s]];
    '"Invalid filesystem path: expected a character vector or symbol"};
.utl.pathFoldWith:{[pathText;rooted;minimumDepth;parts]
    out:(); i:0;
    while[i<count parts;
        part:pathText parts i; if[(0<count part) and not (part~enlist ".");
            $[part~"..";
                $[(count out)<=minimumDepth;
                    if[not rooted;out,:enlist part]; last[out]~"..";
                    if[not rooted;out,:enlist part]; out:-1 _ out];
              out,:enlist part]]; i+:1];
    out};
.utl.pathFold:{[rooted;minimumDepth;parts]
    .utl.pathFoldWith[.utl.pathToString;rooted;minimumDepth;parts]};
.utl.windowsComponentSafeWith:{[pathText;component]
    component:pathText component; if[(component~enlist ".") or component~"..";:1b];
    if[0=count component;:0b]; if[" "=first component;:0b];
    if[last[component] in " .";:0b]; if[any component in "<>:\"/\\|?*";:0b];
    base:lower first "." vs component; if[base in ("con";"prn";"aux";"nul";"clock$");:0b];
    if[base in
        ("com1";"com2";"com3";"com4";"com5";"com6";"com7";"com8";"com9";
         "lpt1";"lpt2";"lpt3";"lpt4";"lpt5";"lpt6";"lpt7";"lpt8";"lpt9";
         "com¹";"com²";"com³";"lpt¹";"lpt²";"lpt³");:0b];
    1b};
.utl.windowsComponentSafe:{[component]
    .utl.windowsComponentSafeWith[.utl.pathToString;component]};
/ Explicit host grammar keeps Windows policy testable on every host.
.utl.pathPolicyWith:{[pathText;hardLimit;componentSafe;fold;limits;path;label;windows]
    text:pathText path; limit:hardLimit[
        limits`characters;32768;"path character"]; if[count[text]>limit;
        '"Invalid ",label,": path exceeds ",string[limit]," characters"]; codes:"i"$text;
    if[any (codes<32) or codes=127;
        '"Invalid ",label,": path contains a control character"];
    s:$[windows;ssr[text;"\\";"/"];text];
    n:count s; if[windows and 3<n;
        if[(4#s) in ("//?/";"//./");
            '"Invalid ",label,": Windows device namespaces are not allowed"]]; if[windows and 3<n;
        if[(4#s)~"/??/";
            '"Invalid ",label,": Windows device namespaces are not allowed"]]; drive:$[
        windows and 1<n; all (":"=s 1;first[s] in (.Q.a,.Q.A));
        0b]; driveAbsolute:$[drive and 2<n;"/"=s 2;0b];
    double:$[1<n;(2#s)~"//";0b]; third:$[2<n;"/"=s 2;0b];
    if[windows and double and third;
        '"Invalid ",label,
          ": three or more leading separators are ambiguous"];
    unc:$[windows;double and not third;0b]; rootRelative:$[
        windows and 0<n; ("/"=first s) and not double;
        0b]; if[windows;
        colons:where ":"=s; if[count colons;
            validColon:all
                (1=count colons;
                 1=first colons; 1<n;
                 first[s] in (.Q.a,.Q.A)); if[not validColon;
                '"Invalid ",label,
                  ": Windows alternate streams and extra colons are not allowed"]];
        if[drive and not driveAbsolute;
            '"Invalid ",label,
              ": ambiguous Windows drive-relative paths are not allowed"]; if[rootRelative;
            '"Invalid ",label,
              ": ambiguous Windows root-relative paths are not allowed"]];
    raw:"/" vs $[unc;2 _ s;drive;2 _ s;s];
    if[unc;
        if[2>count raw;
            '"Invalid ",label,": malformed UNC path"]; if[(0=count raw 0) or 0=count raw 1;
            '"Invalid ",label,": malformed UNC path"]; if[((raw 0)~enlist ".") or (raw 0)~"..";
            '"Invalid ",label,": malformed UNC server"]; if[((raw 1)~enlist ".") or (raw 1)~"..";
            '"Invalid ",label,": malformed UNC share"];
        if[not (all componentSafe each 2#raw);
            '"Invalid ",label,": unsafe UNC anchor"]]; parts:raw where 0<count each raw;
    limit:hardLimit[
        limits`components;1024;"path component"]; if[count[parts]>limit;
        '"Invalid ",label,": path exceeds ",string[limit]," components"];
    if[any 255<count each parts;
        '"Invalid ",label,": path component exceeds 255 characters"];
    if[windows and not all componentSafe each parts;
        '"Invalid ",label,": unsafe Windows path component"]; anchorCount:$[unc;2;0];
    parts:fold[
        unc or driveAbsolute or ((0<n) and "/"=first s); anchorCount;
        parts]; joined:"/" sv parts;
    posixDouble:$[windows;0b;double and not third]; normalized:$[
        unc;(2#"/"),joined; driveAbsolute;(2#s),"/",joined;
        posixDouble;(2#"/"),joined; (0<n) and "/"=first s;(enlist "/"),joined;
        count parts;joined; enlist "."];
    if[normalized in ("";"///");normalized:enlist "."]; absolute:$[
        windows; driveAbsolute or unc;
        $[0<n;"/"=first s;0b]]; `text`slash`normalized`absolute`kind!(
        text;s;normalized;absolute; $[unc;`unc;driveAbsolute;`drive;absolute;`root;`relative])};
.utl.pathPolicy:{[path;label;windows]
    pathText:.utl.pathToString;
    limits:`characters`components!(
        .utl.MAX_PATH_CHARACTERS;.utl.MAX_PATH_COMPONENTS);
    .utl.pathPolicyWith[
        pathText;.utl.hardLimit;
        .utl.windowsComponentSafeWith[pathText];
        .utl.pathFoldWith[pathText];
        limits;path;label;windows]};
.utl.normalizePathForHost:{[path;windows]
    (.utl.pathPolicy[path;"path";windows])`normalized};
.utl.normalizePathWith:{[policy;windows;path]
    (policy[path;"path";windows])`normalized};
.utl.normalizePath:{[path].utl.normalizePathForHost[path;.utl.isWindows]};
.utl.isAbsolutePathForHost:{[path;windows]
    (.utl.pathPolicy[path;"path";windows])`absolute};
.utl.absolutePathForHost:{[path;windows;cwd]
    info:.utl.pathPolicy[path;"path";windows]; if[info`absolute;:info`normalized];
    base:.utl.pathPolicy[cwd;"current directory";windows];
    if[not base`absolute;'"Current directory is not absolute"];
    combined:(base`normalized),"/",info`text; .utl.normalizePathForHost[combined;windows]};
.utl.absolutePath:{[path]
    .utl.absolutePathForHost[path;.utl.isWindows;system "cd"]};
.utl.absolutePathWith:{[policy;windows;command;path]
    info:policy[path;"path";windows]; if[info`absolute;:info`normalized];
    base:policy[command "cd";"current directory";windows];
    if[not base`absolute;'"Current directory is not absolute"];
    combined:(base`normalized),"/",info`text;
    (policy[combined;"path";windows])`normalized};
.utl.resolveRequirePath:{[path]
    info:.utl.pathPolicy[path;"required path";.utl.isWindows]; if[info`absolute;:info`normalized];
    if[not `FILELOADING in key `.utl;:.utl.absolutePath path];
    caller:.utl.absolutePath .utl.FILELOADING;
    base:last "/" vs caller; splitAt:(count caller)-(1+count base);
    directory:splitAt#caller; if[0=count directory;directory:"/"];
    if[(2=count directory) and ":"=last directory;
        directory,:enlist "/"]; .utl.absolutePathForHost[path;.utl.isWindows;directory]};
.utl.PKGLOADING:.utl.absolutePath $[
    count .utl.resqHomeAtBoot;.utl.resqHomeAtBoot,"/lib";"lib"];
.utl.pathWithinRoot:{[candidate;root;windows]
    c:.utl.normalizePathForHost[candidate;windows]; r:.utl.normalizePathForHost[root;windows];
    if[windows;c:lower c;r:lower r]; if[c~r;:1b];
    prefix:$["/"=last r;r;r,"/"]; (count[c]>=count prefix) and prefix~count[prefix]#c};
/ Bounded admission for q APIs that require a file symbol.
if[not `pathSymbolTexts in key `.utl;.utl.pathSymbolTexts:0#enlist ""];
if[not `pathSymbolBytes in key `.utl;.utl.pathSymbolBytes:0j];
.utl.validatePathSymbolRegistry:{[]
    if[not 0h=type .utl.pathSymbolTexts;
        '"Invalid path symbol registry"];
    if[count[.utl.pathSymbolTexts]>8192;
        '"Path symbol registry hard limit exceeded"];
    if[not all 10h=type each .utl.pathSymbolTexts;
        '"Invalid path symbol registry entries"];
    if[not -7h=type .utl.pathSymbolBytes;
        '"Invalid path symbol byte count"];
    if[(null .utl.pathSymbolBytes) or
       (.utl.pathSymbolBytes<0) or .utl.pathSymbolBytes>8388608;
        '"Invalid path symbol byte count"];
    lengths:count each .utl.pathSymbolTexts;
    if[any lengths>32768;
        '"Invalid path symbol registry entry"];
    used:$[count lengths;sum lengths;0j];
    if[.utl.pathSymbolBytes<>used;
        '"Path symbol byte count mismatch"];
    if[count[distinct .utl.pathSymbolTexts]<>count .utl.pathSymbolTexts;
        '"Duplicate path symbol registry entry"];
    enlist[`used]!enlist used};
.utl.pathToHsymWith:{[validateRegistry;pathText;policy;hardLimit;limits;windows;path]
    hardState:validateRegistry[];
    text:pathText path; codes:"i"$text;
    if[count[text]>32768;
        '"Invalid filesystem path: path exceeds 32768 characters"];
    if[any (codes<32) or codes=127;
        '"Invalid filesystem path: path contains a control character"];
    if[any text~/:.utl.pathSymbolTexts;:hsym `$text];
    text:(policy[text;"filesystem path";windows])`text;
    symbolLimit:hardLimit[
        limits`symbols;8192;"path symbol"];
    byteLimit:hardLimit[
        limits`symbolBytes;8388608;"path symbol byte"];
    if[count[.utl.pathSymbolTexts]>=symbolLimit;
        '"Path symbol budget exhausted"];
    if[((hardState`used)+count text)>byteLimit;
        '"Path symbol byte budget exhausted"];
    .utl.pathSymbolTexts,:enlist text;
    .utl.pathSymbolBytes+:count text;
    hsym `$text};
.utl.pathSymbolCapabilities:{[]
    pathText:.utl.pathToString;
    hardLimit:.utl.hardLimit;
    policy:.utl.pathPolicyWith[
        pathText;hardLimit;
        .utl.windowsComponentSafeWith[pathText];
        .utl.pathFoldWith[pathText];
        `characters`components!(
            .utl.MAX_PATH_CHARACTERS;.utl.MAX_PATH_COMPONENTS)];
    configured:`symbols`symbolBytes!(
        .utl.MAX_PATH_SYMBOLS;.utl.MAX_PATH_SYMBOL_BYTES);
    limits:`symbols`symbolBytes!(
        hardLimit[configured`symbols;8192;"path symbol"];
        hardLimit[configured`symbolBytes;8388608;"path symbol byte"]);
    writer:.utl.pathToHsymWith[
        .utl.validatePathSymbolRegistry;pathText;policy;
        hardLimit;configured;.utl.isWindows];
    `validate`limits`toHsym!(
        .utl.validatePathSymbolRegistry;limits;writer)};
.utl.pathToHsym:{[path]
    writer:(.utl.pathSymbolCapabilities[])`toHsym;
    writer path};
.utl.shellQuoteForHost:{[path;windows]
    text:.utl.pathToString path; $[windows;
        "\"",ssr[text;"\"";"\\\""],"\""; "'",ssr[text;"'";"'\"'\"'"],"'"]};
.utl.shellQuote:{[path].utl.shellQuoteForHost[path;.utl.isWindows]};
/ resQ executes trusted local q code; it is not a process sandbox. This one
/ q-native boundary prevents accidental shell interpolation, unbounded reads,
/ and broad deletion. Callers snapshot operation values before user code.
.utl.fsFactory:{[operations]
    fields:`backend`inspect`readRegular`list`makeDir`delete`loadPath`loadNative;
    if[(not 99h=type operations) or not fields~key operations;
        '"Invalid filesystem adapter"]; if[(not -11h=type operations`backend) or
       not all ((type each operations 1 _ fields) within 100 112h);
        '"Invalid filesystem adapter"]; operations};
.utl.qfsDirectoryIdentity:{[attempt;normalize;command;path]
    cwd:command "cd"; resolved:attempt[{[run;target]
        run "cd ",target; run "cd"};(command;path)];
    restored:attempt[{[run;target]run "cd ",target};(command;cwd)];
    if[not first restored;'"Directory-probe CWD restoration failed"];
    if[not first resolved;'last resolved]; normalize last resolved};
/.utl.qfsLinkState is the only native-filesystem shell boundary. The path is
/ hard-validated before this call and quoted as one shell word. Exact sentinel
/ output distinguishes a result from shell/tool failure; ambiguity fails closed.
.utl.qfsLinkState:{[attempt;command;quoteForHost;windows;path]
    if[windows;:`unsupported];
    quoted:quoteForHost[path;0b];
    probe:"if test -L ",quoted,
      "; then printf '%s\\n' RESQ_LINK; elif test -e ",quoted,
      "; then printf '%s\\n' RESQ_NOT_LINK; else printf '%s\\n' RESQ_MISSING; fi";
    outcome:attempt[command;enlist probe];
    if[not first outcome;:`unknown];
    output:last outcome;
    if[(not 0h=type output) or 1<>count output;:`unknown];
    line:first output;
    if[not 10h=type line;:`unknown];
    $[line~"RESQ_LINK";`link;
      line~"RESQ_NOT_LINK";`notLink;
      line~"RESQ_MISSING";`missing;
      `unknown]};
.utl.qfsInspect:{[absolute;toHsym;attempt;directoryIdentity;diagnostic;linkState;windows;path]
    p:absolute path; h:toHsym p;
    linkBefore:linkState p;
    result:attempt[key;enlist h]; if[not first result;
        '"Unable to inspect filesystem path: ",
          diagnostic[last result;512]]; entry:last result;
    observedKind:$[
        (-11h=type entry) and entry~h;`file; 11h=type entry;`dir;
        (0h=type entry) and entry~();`missing; `other];
    linkAfter:linkState p;
    if[not windows;
        if[(linkBefore in `unknown`unsupported) or
           linkAfter in `unknown`unsupported;
            '"Unable to classify filesystem link state"];
        if[not linkBefore~linkAfter;
            '"Filesystem path changed during inspection"];
        if[(linkBefore~`missing) and not observedKind~`missing;
            '"Filesystem path changed during inspection"];
        if[(linkBefore~`notLink) and observedKind~`missing;
            '"Filesystem path changed during inspection"]];
    kind:$[
        (not windows) and linkBefore~`link;`link;
        observedKind];
    identity:$[
        kind~`dir;directoryIdentity p; kind in `file`link;p;
        ""];
    `path`exists`kind`identity`linkSafe!(
        p;not kind~`missing;kind;identity;not windows)};
.utl.qfsRead:{[hardLimit;toHsym;inspect;path;maximum]
    limit:hardLimit[maximum;33554432;"filesystem read byte"]; before:inspect path;
    if[not before[`kind]~`file;'"Filesystem path is not a regular file"];
    bytes:read1 (toHsym[before`path];0;1+limit);
    if[(not 4h=type bytes) or count[bytes]>limit;
        '"Filesystem read exceeds byte limit of ",string limit]; after:inspect before`path;
    if[not after[`kind]~`file;'"Filesystem path changed during read"];
    identity:(before`path),"#",raze string md5 "c"$bytes;
    `path`identity`bytes!(before`path;identity;bytes)};
.utl.textLines:{[bytes]
    if[not 4h=type bytes;'"Invalid text bytes"]; lines:"\n" vs "c"$bytes;
    if[count lines;if[0=count last lines;lines:-1 _ lines]];
    {if[(count x) and "\r"=last x;:-1 _ x];x} each lines};
.utl.textLinesBounded:{[bytes;maximum]
    if[not 4h=type bytes;'"Invalid text bytes"]; limit:.utl.hardLimit[maximum;65536;"text line"];
    lineCount:(sum bytes=0x0a)+
      $[(count bytes) and not 0x0a=last bytes;1;0]; if[lineCount>limit;
        '"Text exceeds line limit of ",string limit]; .utl.textLines bytes};
.utl.qfsList:{[hardLimit;toHsym;inspect;path;maximum;maximumBytes]
    entryLimit:hardLimit[maximum;65536;"directory entry"];
    byteLimit:hardLimit[maximumBytes;16777216;"directory entry byte"];
    state:inspect path; if[not state[`kind]~`dir;'"Filesystem path is not a directory"];
    entries:key toHsym state`path;
    if[not 11h=type entries;'"Directory enumeration changed type"];
    if[count[entries]>entryLimit;'"Directory entry limit exceeded"]; names:string each entries;
    used:$[count names;sum count each names;0j];
    if[used>byteLimit;'"Directory entry byte limit exceeded"];
    if[any {any ("i"$x)<32} each names;
        '"Directory contains an unsafe entry name"];
    after:inspect state`path;
    if[(not after[`kind]~`dir) or
       not after[`identity]~state`identity;
        '"Directory changed during enumeration"];
    `path`entries!(state`path;names)};
.utl.qfsMakeDir:{[absolute;toHsym;inspect;path]
    p:absolute path; state:inspect p;
    if[state[`kind]~`dir;:p]; if[state`exists;'"Cannot create directory over an existing path"];
    marker:p,"/.resq-mkdir-",raze string md5
        "c"$((string .z.p),string .z.i);
    opened:@[hopen;":",marker;{[e]'"Unable to create directory: ",e}];
    hclose opened; hdel toHsym marker;
    if[not ((inspect p)`kind)~`dir;'"Unable to create directory"]; p};
.utl.qfsDelete:{[toHsym;inspect;path]
    state:inspect path; if[not state`exists;:1b];
    hdel toHsym state`path; not (inspect[state`path])`exists};
.utl.restoreProcessContextWith:{[attempt;diagnostic;command;cwd;namespace]
    cwdResult:attempt[command;enlist ("cd ",cwd)];
    namespaceResult:attempt[
        command;enlist ("d ",string namespace)];
    if[(not first cwdResult) or not first namespaceResult;
        message:"Process context restoration failed";
        if[not first cwdResult;
            message,:": CWD: ",
                diagnostic[last cwdResult;256]];
        if[not first namespaceResult;
            message,:": namespace: ",
                diagnostic[last namespaceResult;256]];
        'message];
    (::)};
.utl.restoreProcessContext:{[attempt;command;cwd;namespace]
    .utl.restoreProcessContextWith[
        attempt;.utl.boundedDiagnostic;command;cwd;namespace]};
.utl.qfsLoadPath:{[attempt;restoreContext;diagnostic;absolute;command;path]
    p:absolute path;
    if[any p in " \t";
        '"Load paths containing whitespace are not supported"];
    cwd:command "cd"; namespace:command "d";
    loaded:attempt[command;enlist ("l ",p)];
    restored:attempt[restoreContext;(cwd;namespace)];
    if[not first restored;
        message:"Required-file process context restoration failed: ",
          diagnostic[last restored;512];
        if[not first loaded;
            message:"Required-file load failed: ",
              diagnostic[last loaded;512],"; ",message];
        'message];
    if[not first loaded;'last loaded];
    (::)};
.utl.qfsLoad:{[readRegular;loadPath;path;expectedIdentity]
    before:readRegular[path;33554432]; if[not before[`identity]~expectedIdentity;
        '"Required file changed before execution"]; loadPath before`path;
    after:readRegular[before`path;33554432]; if[not after[`identity]~expectedIdentity;
        '"Required file changed during execution"]; after};
.utl.qfs:{[]
    hardLimit:.utl.hardLimit;
    attempt:.utl.attempt;
    diagnostic:.utl.boundedDiagnostic;
    pathText:.utl.pathToString;
    pathLimits:`characters`components!(
        .utl.MAX_PATH_CHARACTERS;.utl.MAX_PATH_COMPONENTS);
    fold:.utl.pathFoldWith[pathText];
    componentSafe:.utl.windowsComponentSafeWith[pathText];
    policy:.utl.pathPolicyWith[
        pathText;hardLimit;componentSafe;fold;pathLimits];
    absolute:.utl.absolutePathWith[
        policy;.utl.isWindows;system];
    symbolCapabilities:.utl.pathSymbolCapabilities[];
    toHsym:symbolCapabilities`toHsym;
    normalize:.utl.normalizePathWith[policy;.utl.isWindows];
    command:system;
    windows:.utl.isWindows;
    directoryIdentity:.utl.qfsDirectoryIdentity[
        attempt;normalize;command];
    linkState:.utl.qfsLinkState[
        attempt;command;.utl.shellQuoteForHost;windows];
    inspect:.utl.qfsInspect[
        absolute;toHsym;attempt;directoryIdentity;
        diagnostic;linkState;windows];
    reader:.utl.qfsRead[hardLimit;toHsym;inspect];
    pathLoader:.utl.qfsLoadPath[
        attempt;.utl.restoreProcessContextWith[
            attempt;diagnostic;command];
        diagnostic;absolute;command];
    `backend`inspect`readRegular`list`makeDir`delete`loadPath`loadNative!(
        `qNative;inspect;reader;.utl.qfsList[
            hardLimit;toHsym;inspect];
        .utl.qfsMakeDir[absolute;toHsym;inspect];
        .utl.qfsDelete[toHsym;inspect];
        pathLoader;.utl.qfsLoad[reader;pathLoader])};
.utl.fs:.utl.fsFactory .utl.qfs[];
.utl.fsSnapshot:{[].utl.fsFactory .utl.fs};
.utl.pathExists:{[path]
    inspected:(.utl.fsSnapshot[]`inspect) path; 1b~inspected`exists};
.utl.isDir:{[path]
    inspected:(.utl.fsSnapshot[]`inspect) path; (1b~inspected`exists) and inspected[`kind]~`dir};
.utl.isFile:{[path]
    inspected:(.utl.fsSnapshot[]`inspect) path; inspected[`kind]~`file};
.utl.ensureDir:{[path]
    adapter:.utl.fsSnapshot[]; (adapter`makeDir) path};
/ Validate and normalize line-oriented text before a bounded write. q's `0:`
/ appends one newline per row, so the byte budget includes those separators.
.utl.textWriteContent:{[content;maximum;label]
    if[not 10h=type label;
        '"Invalid text publication label"];
    labelCodes:"i"$label;
    if[(not count label) or 64<count label or
       any (labelCodes<32) or labelCodes=127;
        '"Invalid text publication label"];
    limit:.utl.hardLimit[
        maximum;33554432;label," byte"];
    contentType:type content;
    if[not contentType in 0 10h;
        'label," content is invalid"];
    lines:$[10h=contentType;enlist content;content];
    if[not all 10h=type each lines;
        'label," content is invalid"];
    size:$[
        count lines;
          (sum "j"$count each lines)+count lines;
        0j];
    if[size>limit;
        'label," byte limit exceeded"];
    `lines`size`limit!(lines;size;limit)
 };
/ Atomic same-directory publication. The final pathname is replaced only after
/ the complete bounded body exists as a regular temporary file. Existing
/ symlinks/directories are rejected, and failed moves clean the temporary file.
/ The capability form keeps failure paths deterministic and directly testable.
.utl.atomicTextWriteWith:{[capabilities;path;content;maximum;label]
    required:
      `attempt`command`quoteForHost`windows`snapshot`toHsym`diagnostic;
    if[(not 99h=type capabilities) or
       not required~key capabilities;
        '"Invalid text publication capabilities"];
    callable:required except `windows;
    callableValues:capabilities callable;
    if[(not all (type each callableValues) within 100 112h) or
       any (::)~/:callableValues;
        '"Invalid text publication capabilities"];
    if[not -1h=type capabilities`windows;
        '"Invalid text publication capabilities"];
    prepared:.utl.textWriteContent[content;maximum;label];
    attemptFn:capabilities`attempt;
    commandFn:capabilities`command;
    quoteFn:capabilities`quoteForHost;
    windows:capabilities`windows;
    snapshotFn:capabilities`snapshot;
    toHsymFn:capabilities`toHsym;
    diagnosticFn:capabilities`diagnostic;
    adapter:.utl.fsFactory snapshotFn[];
    target:(adapter`inspect) path;
    if[target`exists;
        if[not target[`kind]~`file;
            'label," target is not a regular file"]];
    outputPath:target`path;
    / Stable per-process names prevent unbounded symbol interning while still
    / separating independent q processes publishing the same report.
    seed:outputPath,string .z.i;
    suffix:raze string md5 "c"$seed;
    tempPath:outputPath,".resq-publish-",suffix;
    tempState:(adapter`inspect) tempPath;
    if[tempState`exists;
        'label," temporary path collision"];
    written:attemptFn[
        {[writer;temporary;body]
          (writer temporary)0:body;
          ::};
        (toHsymFn;tempPath;prepared`lines)];
    if[not first written;
        @[(adapter`delete);tempPath;{}];
        'last written];
    observed:(adapter`inspect) tempPath;
    if[not observed[`kind]~`file;
        @[(adapter`delete);tempPath;{}];
        'label," temporary file postcondition failed"];
    sourceArg:quoteFn[tempPath;windows];
    targetArg:quoteFn[outputPath;windows];
    moveCommand:$[
        windows;
          "move /Y ",sourceArg," ",targetArg;
        "mv -f ",sourceArg," ",targetArg];
    moved:attemptFn[commandFn;enlist moveCommand];
    if[not first moved;
        @[(adapter`delete);tempPath;{}];
        'label," publication failed: ",
          diagnosticFn[last moved;512]];
    published:(adapter`inspect) outputPath;
    if[not published[`kind]~`file;
        'label," publication postcondition failed"];
    outputPath
 };
.utl.atomicTextCapabilities:{[]
    `attempt`command`quoteForHost`windows`snapshot`toHsym`diagnostic!(
      .utl.attempt;
      system;
      .utl.shellQuoteForHost;
      .utl.isWindows;
      .utl.fsSnapshot;
      .utl.pathToHsym;
      .utl.boundedDiagnostic)
 };
.utl.atomicTextWrite:{[path;content;maximum;label]
    .utl.atomicTextWriteWith[
      .utl.atomicTextCapabilities[];
      path;
      content;
      maximum;
      label]
 };
/ Character truth internally; compatibility symbols publish only on success.
.utl.MAX_LOADED_FILES:4096;
.utl.MAX_LOADED_BYTES:16777216;
.utl.MAX_DEPENDENCY_EDGES:16384;
.utl.MAX_DEPENDENCY_BYTES:16777216;
.utl.MAX_REQUIRE_DEPTH:64;
if[not `loadedIds in key `.utl;.utl.loadedIds:0#enlist ""];
if[not `loadingPaths in key `.utl;.utl.loadingPaths:0#enlist ""];
if[not `dependencyText in key `.utl;.utl.dependencyText:()];
.utl.upgradeLegacyRequireState:{[]
    recovery:
      "; repair .utl.loaded/.utl.loadedIds and reload bootstrap, or restart q";
    if[not 0h=type .utl.loaded;
        '"Malformed legacy require state",recovery];
    if[not all 10h=type each .utl.loaded;
        '"Malformed legacy require state",recovery];
    if[not 0h=type .utl.loadedIds;
        '"Malformed legacy require state",recovery];
    if[not all 10h=type each .utl.loadedIds;
        '"Malformed legacy require state",recovery];
    if[count[.utl.loadedIds]=count .utl.loaded;
        if[count[.utl.loaded];
            if[(any 0=count each .utl.loaded) or
               any 0=count each .utl.loadedIds;
                '"Malformed require truth",recovery]];
        :()];
    if[count .utl.loadedIds;
        '"Partial legacy require state",recovery];
    legacy:.utl.loaded where 0<count each .utl.loaded;
    if[count legacy;
        '"Legacy loaded files have no trustworthy identities; clear .utl.loaded and ",
          ".utl.loadedIds, reload bootstrap, and explicitly require modules again, ",
          "or restart q"];
    `.utl.loaded set 0#enlist "";
    `.utl.loadedIds set 0#enlist "";
    (::)};
.utl.upgradeLegacyRequireState[];
.utl.validateRequireStateWith:{[limits]
    if[not 0h=type .utl.loaded;'"Invalid loaded-file registry"];
    if[not all 10h=type each .utl.loaded;
        '"Invalid loaded-file registry entries"];
    if[not 0h=type .utl.loadedIds;'"Invalid loaded identity registry"];
    if[not all 10h=type each .utl.loadedIds;
        '"Invalid loaded identity registry entries"]; if[count[.utl.loaded]<>count .utl.loadedIds;
        '"Loaded registry shape mismatch"]; fileLimit:limits`files;
    byteLimit:limits`fileBytes;
    if[count[.utl.loaded]>fileLimit;'"Loaded-file registry limit exceeded"];
    used:$[count .utl.loaded;sum count each .utl.loaded;0j]; if[used>byteLimit;
        '"Loaded-file registry byte limit exceeded"];
    if[not 0h=type .utl.loadingPaths;'"Invalid require guard"];
    if[not all 10h=type each .utl.loadingPaths;
        '"Invalid require guard entries"];
    if[count[distinct .utl.loadingPaths]<>count .utl.loadingPaths;
        '"Invalid require guard: duplicate path"]; depthLimit:limits`depth;
    if[count[.utl.loadingPaths]>depthLimit;
        '"Require guard depth limit exceeded"]; guardBytes:$[
        count .utl.loadingPaths; sum count each .utl.loadingPaths;
        0j]; if[guardBytes>2097152;'"Require guard byte limit exceeded"];
    (::)};
.utl.requireLimits:{[]
    hardLimit:.utl.hardLimit;
    `files`fileBytes`edges`dependencyBytes`depth!(
        hardLimit[.utl.MAX_LOADED_FILES;4096;"loaded file"];
        hardLimit[.utl.MAX_LOADED_BYTES;16777216;"loaded-file byte"];
        hardLimit[.utl.MAX_DEPENDENCY_EDGES;16384;"dependency edge"];
        hardLimit[.utl.MAX_DEPENDENCY_BYTES;16777216;"dependency byte"];
        hardLimit[.utl.MAX_REQUIRE_DEPTH;64;"require depth"])};
.utl.validateRequireState:{[]
    .utl.validateRequireStateWith[.utl.requireLimits[]]};
.utl.requireGuardRoomWith:{[depthLimit;path]
    if[any path~/:.utl.loadingPaths;
        '"Recursive require cycle: ",
          .utl.boundedDiagnostic[path;1024]];
    if[count[.utl.loadingPaths]>=depthLimit;
        '"Require depth limit exceeded"]; (::)};
.utl.requireGuardRoom:{[path]
    limits:.utl.requireLimits[];
    .utl.requireGuardRoomWith[limits`depth;path]};
.utl.requireRoomWith:{[validator;limits;path;identity]
    validator limits; fileLimit:limits`files;
    if[count[.utl.loaded]>=fileLimit;'"Loaded-file registry limit exceeded"];
    byteLimit:limits`fileBytes;
    used:$[count .utl.loaded;sum count each .utl.loaded;0j];
    if[(used+count path)>byteLimit;
        '"Loaded-file registry byte limit exceeded"];
    if[(not 10h=type identity) or count[identity]>512;
        '"Invalid loaded-file identity"]; (::)};
.utl.requireRoom:{[path;identity]
    .utl.requireRoomWith[
        .utl.validateRequireStateWith;.utl.requireLimits[];
        path;identity]};
.utl.dependencyRoomWith:{[limits;caller;required]
    if[0=count caller;:1b]; if[not 0h=type .utl.dependencyText;
        '"Invalid dependency truth registry"]; if[count[.utl.dependencyText];
        if[not all {
            (0h=type x) and (2=count x) and
            all 10h=type each x
          } each .utl.dependencyText;
            '"Invalid dependency truth entry"]]; pair:(caller;required);
    duplicate:any {[needle;entry]needle~entry}[pair;]
        each .utl.dependencyText; if[duplicate;:1b];
    edgeLimit:limits`edges;
    if[count[.utl.dependencyText]>=edgeLimit;
        '"Dependency edge limit exceeded"]; byteLimit:limits`dependencyBytes;
    used:$[
        count .utl.dependencyText; sum {sum count each x} each .utl.dependencyText;
        0j]; if[(used+count[caller]+count required)>byteLimit;
        '"Dependency byte limit exceeded"]; 0b};
.utl.dependencyRoom:{[caller;required]
    .utl.dependencyRoomWith[
        .utl.requireLimits[];caller;required]};
.utl.publishDependencyWith:{[dependencies;caller;required]
    if[0=count caller;:(::)];
    room:dependencies`room;
    duplicate:room[caller;required];
    if[duplicate;:(::)];
    registry:$[
        `testDeps in key `.utl;
        .utl.testDeps;
        (`symbol$())!()];
    if[not 99h=type registry;'"Invalid dependency registry"];
    validateRegistry:dependencies`validateRegistry;
    pathState:validateRegistry[];
    symbolLimits:dependencies`symbolLimits;
    candidates:(caller;required);
    missing:distinct candidates where not {
        any x~/:.utl.pathSymbolTexts} each candidates;
    if[count missing;
        if[(count[.utl.pathSymbolTexts]+count missing)>symbolLimits`symbols;
            '"Path symbol budget exhausted"];
        missingBytes:sum count each missing;
        if[((pathState`used)+missingBytes)>symbolLimits`symbolBytes;
            '"Path symbol byte budget exhausted"]];
    toHsym:dependencies`toHsym;
    callerHandle:toHsym caller; requiredHandle:toHsym required;
    previous:$[
        callerHandle in key registry; registry callerHandle;
        `symbol$()]; if[not 11h=type previous;'"Invalid dependency registry edges"];
    updated:registry;
    updated[callerHandle]:previous,requiredHandle;
    dependencyText:.utl.dependencyText,enlist (caller;required);
    `.utl.testDeps set updated;
    `.utl.dependencyText set dependencyText;
    (::)};
.utl.publishDependency:{[caller;required]
    limits:.utl.requireLimits[];
    symbols:.utl.pathSymbolCapabilities[];
    dependencies:`room`validateRegistry`symbolLimits`toHsym!(
        .utl.dependencyRoomWith[limits];
        symbols`validate;
        symbols`limits;
        symbols`toHsym);
    .utl.publishDependencyWith[
        dependencies;caller;required]};
/ Each require owns an outer transaction, including successful nested requires.
.utl.requireStateSnapshot:{[]
    (`loaded`loadedIds`loadingPaths`dependencyText,
      `testDepsSet`testDeps`fileSet`fileValue)!(
        .utl.loaded;
        .utl.loadedIds;
        .utl.loadingPaths;
        .utl.dependencyText;
        `testDeps in key `.utl;
        @[get;`.utl.testDeps;{::}];
        `FILELOADING in key `.utl;
        @[get;`.utl.FILELOADING;{::}])};
.utl.restoreRequireState:{[attempt;diagnostic;snapshotter;snapshot]
    problems:();
    outcome:attempt[set;(`.utl.loaded;snapshot`loaded)];
    if[not first outcome;problems,:enlist
        "loaded paths: ",diagnostic[last outcome;256]];
    outcome:attempt[set;(`.utl.loadedIds;snapshot`loadedIds)];
    if[not first outcome;problems,:enlist
        "loaded identities: ",diagnostic[last outcome;256]];
    outcome:attempt[set;(`.utl.loadingPaths;snapshot`loadingPaths)];
    if[not first outcome;problems,:enlist
        "require guard: ",diagnostic[last outcome;256]];
    outcome:attempt[set;(`.utl.dependencyText;snapshot`dependencyText)];
    if[not first outcome;problems,:enlist
        "dependency truth: ",diagnostic[last outcome;256]];
    outcome:attempt[{[wasSet;savedValue]
        $[wasSet;`.utl.testDeps set savedValue;
          if[`testDeps in key `.utl;
              ![`.utl;();0b;enlist `testDeps]]];
        (::)};(snapshot`testDepsSet;snapshot`testDeps)];
    if[not first outcome;problems,:enlist
        "dependency registry: ",diagnostic[last outcome;256]];
    outcome:attempt[{[wasSet;savedValue]
        $[wasSet;`.utl.FILELOADING set savedValue;
          if[`FILELOADING in key `.utl;
              ![`.utl;();0b;enlist `FILELOADING]]];
        (::)};(snapshot`fileSet;snapshot`fileValue)];
    if[not first outcome;problems,:enlist
        "loading file: ",diagnostic[last outcome;256]];
    observed:attempt[snapshotter;()];
    if[not first observed;problems,:enlist
        "postcondition capture: ",diagnostic[last observed;256]];
    if[first observed;if[not snapshot~last observed;
        problems,:enlist "postcondition mismatch"]];
    if[count problems;
        '"Require rollback failed: ",
          diagnostic["; " sv problems;2048]];
    (::)};
.utl.requireFailureDelta:{[snapshot;current;requested]
    required:`loaded`loadedIds`dependencyText;
    if[(not 99h=type snapshot) or
       (not 99h=type current) or
       (not all required in key snapshot) or
       (not all required in key current);
        :`valid`loaded`loadedIds`dependencies!(
            0b;0#enlist "";0#enlist "";())];
    beforePaths:snapshot`loaded;
    beforeIds:snapshot`loadedIds;
    beforeDeps:snapshot`dependencyText;
    afterPaths:current`loaded;
    afterIds:current`loadedIds;
    afterDeps:current`dependencyText;
    containers:all (
        0h=type beforePaths;
        0h=type beforeIds;
        0h=type beforeDeps;
        0h=type afterPaths;
        0h=type afterIds;
        0h=type afterDeps);
    if[not containers;
        :`valid`loaded`loadedIds`dependencies!(
            0b;0#enlist "";0#enlist "";())];
    beforeCount:count beforePaths;
    beforeDepCount:count beforeDeps;
    prefixValid:all (
        beforeCount=count beforeIds;
        beforeCount<=count afterPaths;
        count[afterPaths]=count afterIds;
        beforeDepCount<=count afterDeps);
    if[prefixValid;
        prefixValid:all (
            beforePaths~beforeCount#afterPaths;
            beforeIds~beforeCount#afterIds;
            beforeDeps~beforeDepCount#afterDeps)];
    if[not prefixValid;
        :`valid`loaded`loadedIds`dependencies!(
            0b;0#enlist "";0#enlist "";())];
    appendedPaths:beforeCount _ afterPaths;
    appendedIds:beforeCount _ afterIds;
    appendedDeps:beforeDepCount _ afterDeps;
    entriesValid:all (
        all 10h=type each appendedPaths;
        all 10h=type each appendedIds;
        all {
            (0h=type x) and (2=count x) and
              all 10h=type each x
          } each appendedDeps);
    if[not entriesValid;
        :`valid`loaded`loadedIds`dependencies!(
            0b;0#enlist "";0#enlist "";())];
    keep:not requested~/:appendedPaths;
    keptPaths:appendedPaths where keep;
    keptIds:appendedIds where keep;
    keptDeps:appendedDeps where
        {[failed;edge]not failed~last edge}[requested;] each appendedDeps;
    valid:all (
        count[distinct keptPaths]=count keptPaths;
        count[distinct keptIds]=count keptIds;
        not any keptPaths in beforePaths;
        not any keptIds in beforeIds);
    `valid`loaded`loadedIds`dependencies!(
        valid;keptPaths;keptIds;keptDeps)};
.utl.restoreRequireFailureState:{
    [dependencies;snapshot;requested]
    attempt:dependencies`attempt;
    diagnostic:dependencies`diagnostic;
    snapshotter:dependencies`snapshotter;
    restoreState:dependencies`restore;
    publisher:dependencies`publisher;
    deltaFn:dependencies`delta;
    validator:dependencies`validator;
    validatorLimits:dependencies`validatorLimits;
    captured:attempt[snapshotter;()];
    if[not first captured;
        fallback:attempt[restoreState;enlist snapshot];
        if[not first fallback;
            '"Require rollback failed: ",
              diagnostic[last fallback;512]];
        '"Require rollback could not inspect failed state: ",
          diagnostic[last captured;512]];
    current:last captured;
    delta:deltaFn[snapshot;current;requested];
    changed:not current~snapshot;
    restored:attempt[restoreState;enlist snapshot];
    if[not first restored;'last restored];
    if[not delta`valid;
        if[changed;
            '"Require rollback discarded unverifiable nested state"];
        :()];
    keptPaths:delta`loaded;
    keptIds:delta`loadedIds;
    keptDeps:delta`dependencies;
    if[count keptPaths;
        admitted:attempt[{[check;limits;paths;identities]
            `.utl.loaded set .utl.loaded,paths;
            `.utl.loadedIds set .utl.loadedIds,identities;
            check limits;
            (::)};(validator;validatorLimits;keptPaths;keptIds)];
        if[not first admitted;
            cleanup:attempt[restoreState;enlist snapshot];
            if[not first cleanup;
                '"Require rollback failed: ",
                  diagnostic[last admitted;512],"; ",
                  diagnostic[last cleanup;512]];
            '"Require rollback could not retain nested modules: ",
              diagnostic[last admitted;512]]];
    i:0;
    while[i<count keptDeps;
        published:attempt[publisher;keptDeps i];
        if[not first published;
            cleanup:attempt[restoreState;enlist snapshot];
            if[not first cleanup;
                '"Require rollback failed: ",
                  diagnostic[last published;512],"; ",
                  diagnostic[last cleanup;512]];
            '"Require rollback could not retain nested dependencies: ",
              diagnostic[last published;512]];
        i+:1];
    observed:attempt[snapshotter;()];
    if[not first observed;
        cleanup:attempt[restoreState;enlist snapshot];
        if[not first cleanup;
            '"Require rollback failed: ",
              diagnostic[last observed;512],"; ",
              diagnostic[last cleanup;512]];
        '"Require rollback postcondition capture failed: ",
          diagnostic[last observed;512]];
    expectedLoaded:(snapshot`loaded),keptPaths;
    expectedIds:(snapshot`loadedIds),keptIds;
    expectedDeps:(snapshot`dependencyText),keptDeps;
    final:last observed;
    loadedValid:expectedLoaded~final`loaded;
    idsValid:expectedIds~final`loadedIds;
    dependenciesValid:expectedDeps~final`dependencyText;
    guardValid:(snapshot`loadingPaths)~final`loadingPaths;
    fileSetValid:(snapshot`fileSet)~final`fileSet;
    fileValueValid:(snapshot`fileValue)~final`fileValue;
    valid:all (
        loadedValid;
        idsValid;
        dependenciesValid;
        guardValid;
        fileSetValid;
        fileValueValid);
    if[not valid;
        cleanup:attempt[restoreState;enlist snapshot];
        if[not first cleanup;
            '"Require rollback failed: postcondition mismatch; ",
              diagnostic[last cleanup;512]];
        '"Require rollback postcondition mismatch"];
    (::)};
.utl.requireCapabilities:{[adapter]
    limits:.utl.requireLimits[];
    symbols:.utl.pathSymbolCapabilities[];
    validator:.utl.validateRequireStateWith;
    room:.utl.requireRoomWith[validator;limits];
    dependencyRoom:.utl.dependencyRoomWith[limits];
    publishDependencies:
      `room`validateRegistry`symbolLimits`toHsym!(
        dependencyRoom;
        symbols`validate;
        symbols`limits;
        symbols`toHsym);
    names:`attempt`diagnostic`pathText`validate`limits`guardRoom,
      `readRegular`nativeLoad`room`dependencyRoom`publisher`toHsym`debug;
    names!(
        .utl.attempt;
        .utl.boundedDiagnostic;
        .utl.pathToString;
        validator;
        limits;
        .utl.requireGuardRoomWith[limits`depth];
        adapter`readRegular;
        adapter`loadNative;
        room;
        dependencyRoom;
        .utl.publishDependencyWith[publishDependencies];
        symbols`toHsym;
        1b~.utl.DEBUG)};
.utl.requireCore:{[capabilities;path]
    attempt:capabilities`attempt;
    requested:path;
    validator:capabilities`validate;
    limits:capabilities`limits;
    validator limits;
    guardRoom:capabilities`guardRoom;
    guardRoom requested;
    readRegular:capabilities`readRegular;
    nativeLoad:capabilities`nativeLoad;
    initial:readRegular[requested;33554432];
    if[(not 99h=type initial) or
       not all `path`identity in key initial;
        '"Invalid required-file read result"]; identity:initial`identity;
    caller:$[
        `FILELOADING in key `.utl;
        (capabilities`pathText) .utl.FILELOADING;
        ""];
    dependencyRoom:capabilities`dependencyRoom;
    dependencyRoom[caller;requested];
    sameIdentity:where identity~/:.utl.loadedIds; if[count sameIdentity;
        (capabilities`publisher)[
            caller;.utl.loaded first sameIdentity];
        :(::)];
    if[any requested~/:.utl.loaded;
        '"Required path identity changed after it was loaded"];
    requireRoom:capabilities`room;
    requireRoom[requested;identity];
    guardBase:.utl.loadingPaths; expectedGuard:guardBase,enlist requested;
    fileWasSet:`FILELOADING in key `.utl; fileBefore:@[get;`.utl.FILELOADING;{::}];
    requiredHandle:(capabilities`toHsym) requested;
    publishDependency:capabilities`publisher;
    `.utl.loadingPaths set expectedGuard; `.utl.FILELOADING set requiredHandle;
    loadOutcome:attempt[nativeLoad;(requested;identity)];
    guardNow:@[get;`.utl.loadingPaths;{::}];
    fileNowSet:`FILELOADING in key `.utl; fileNow:@[get;`.utl.FILELOADING;{::}];
    restored:attempt[{[guard;wasSet;previous]
        `.utl.loadingPaths set guard; $[wasSet;
            `.utl.FILELOADING set previous; if[`FILELOADING in key `.utl;
                ![`.utl;();0b;enlist `FILELOADING]]]; (guard~@[get;`.utl.loadingPaths;{::}]) and
          $[wasSet;
            (`FILELOADING in key `.utl) and
              previous~@[get;`.utl.FILELOADING;{::}]; not `FILELOADING in key `.utl]};
        (guardBase;fileWasSet;fileBefore)];
    if[(not first restored) or not last restored;
        '"Require context restoration failed"]; if[(not expectedGuard~guardNow) or
       (not fileNowSet) or not requiredHandle~fileNow;
        '"Require context changed during module execution"];
    if[not first loadOutcome;'last loadOutcome];
    final:last loadOutcome; if[(not 99h=type final) or not `identity in key final;
        '"Invalid required-file load result"]; if[not identity~final`identity;
        '"Required-file identity changed during module execution"];
    requireRoom[requested;identity];
    dependencyRoom[caller;requested];
    .utl.loadedIds,:enlist identity;
    .utl.loaded,:enlist requested;
    publishDependency[caller;requested];
    if[capabilities`debug;-1 "DEBUG: loaded ",requested];
    (::)};
.utl.requireWith:{[adapter;path]
    capabilities:.utl.requireCapabilities adapter;
    attempt:capabilities`attempt;
    diagnostic:capabilities`diagnostic;
    snapshotter:.utl.requireStateSnapshot;
    restoreState:.utl.restoreRequireState[
        attempt;diagnostic;snapshotter];
    failureDependencies:
      `attempt`diagnostic`snapshotter`restore`publisher`delta`validator`validatorLimits!(
        attempt;
        diagnostic;
        snapshotter;
        restoreState;
        capabilities`publisher;
        .utl.requireFailureDelta;
        capabilities`validate;
        capabilities`limits);
    restoreFailure:.utl.restoreRequireFailureState[
        failureDependencies];
    core:.utl.requireCore;
    requested:.utl.resolveRequirePath path;
    snapshot:snapshotter[];
    outcome:attempt[core;(capabilities;requested)];
    if[first outcome;:(::)];
    rollback:attempt[restoreFailure;(snapshot;requested)];
    if[not first rollback;
        '"Require failed: ",diagnostic[last outcome;1024],
          "; ",diagnostic[last rollback;512]];
    'last outcome};
.tst.die: {[x] exit x};
.resq.state.emptyResults:{[]
    flip `suite`description`status`message`time`failures`assertsRun!(
        `symbol$(); `symbol$(); `symbol$(); (); `timespan$(); (); `int$())};
