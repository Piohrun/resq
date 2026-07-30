\d .tst

/ Bounded, transactional dependency graph analysis.
if[not `depGraph in key `.tst; depGraph:()!()];
if[not `dependencies in key `.tst; dependencies:()!()];
if[not `MAX_DEPENDENCY_FILES in key `.tst;
  MAX_DEPENDENCY_FILES:10000];
if[not `MAX_DEPENDENCY_SOURCE_BYTES in key `.tst;
  MAX_DEPENDENCY_SOURCE_BYTES:16777216];
if[not `MAX_DEPENDENCY_TOTAL_SOURCE_BYTES in key `.tst;
  MAX_DEPENDENCY_TOTAL_SOURCE_BYTES:67108864];
if[not `MAX_DEPENDENCY_SOURCE_LINES in key `.tst;
  MAX_DEPENDENCY_SOURCE_LINES:65536];
if[not `MAX_DEPENDENCY_DIRECTIVES in key `.tst;
  MAX_DEPENDENCY_DIRECTIVES:4096];
if[not `MAX_DEPENDENCY_EDGES in key `.tst;
  MAX_DEPENDENCY_EDGES:65536];
if[not `MAX_DEPENDENCY_PATH_BYTES in key `.tst;
  MAX_DEPENDENCY_PATH_BYTES:16777216];
if[not `MAX_DEPENDENCY_MATCH_WORK in key `.tst;
  MAX_DEPENDENCY_MATCH_WORK:1000000];
if[not `MAX_DEPENDENCY_WALK in key `.tst;
  MAX_DEPENDENCY_WALK:100000];

.utl.require .utl.PKGLOADING,"/static_analysis.q"

dependencyLimits:{[]
  `files`sourceBytes`totalSourceBytes`sourceLines`directives`edges`pathBytes`matchWork`walk!(
    .utl.hardLimit[
      .tst.MAX_DEPENDENCY_FILES;10000;"dependency file"];
    .utl.hardLimit[
      .tst.MAX_DEPENDENCY_SOURCE_BYTES;16777216;
      "dependency source byte"];
    .utl.hardLimit[
      .tst.MAX_DEPENDENCY_TOTAL_SOURCE_BYTES;67108864;
      "aggregate dependency source byte"];
    .utl.hardLimit[
      .tst.MAX_DEPENDENCY_SOURCE_LINES;65536;
      "dependency source line"];
    .utl.hardLimit[
      .tst.MAX_DEPENDENCY_DIRECTIVES;4096;
      "dependency directive"];
    .utl.hardLimit[
      .tst.MAX_DEPENDENCY_EDGES;65536;
      "dependency edge"];
    .utl.hardLimit[
      .tst.MAX_DEPENDENCY_PATH_BYTES;16777216;
      "dependency path byte"];
    .utl.hardLimit[
      .tst.MAX_DEPENDENCY_MATCH_WORK;10000000;
      "dependency suffix-match work"];
    .utl.hardLimit[
      .tst.MAX_DEPENDENCY_WALK;100000;
      "dependent traversal"])
 };

dependencyItemBytes:{[items]
  if[not count items;:0j];
  sum "j"$count each string each items
 };

dependencyPathText:{[path;label]
  text:.utl.pathToString path;
  if[not count text;
    'label," is empty"];
  .utl.pathPolicy[
    text;
    label;
    .utl.isWindows];
  text
 };

/ q symbols are process-lifetime allocations. Admit every path through the
/ shared cumulative path registry before creating the plain symbol retained by
/ the compatibility graph API.
dependencyPathSymbol:{[path]
  text:.tst.dependencyPathText[
    path;
    "Dependency path"];
  .utl.pathToHsym text;
  `$text
 };

dependencyRecordState:{[limit]
  `targets`tails`kinds`count`bytes!(
    limit#enlist "";
    limit#0b;
    limit#enlist `;
    0j;
    0j)
 };

/ Validate and retain one literal without interning it. A quoted suffix in a
/ concatenation (for example PKGLOADING,"/module.q") is validated as relative
/ while its original leading separator is retained for the public parser.
appendDependencyRecord:{[state;target;tail;kind;limits]
  if[not -1h=type tail;
    '"Dependency directive metadata is invalid"];
  if[not kind in `load`require;
    '"Dependency directive kind is invalid"];
  if[(kind~`load) and tail;
    '"Load directive metadata is invalid"];
  text:.utl.pathToString target;
  if[not count text;:state];
  validationText:text;
  if[tail and first[validationText] in "/\\";
    validationText:1 _ validationText];
  if[not count validationText;
    '"Dependency target is empty"];
  .utl.pathPolicy[
    validationText;
    "dependency target";
    .utl.isWindows];
  nextBytes:state[`bytes]+count text;
  if[nextBytes>(limits`pathBytes);
    '"Dependency path byte limit exceeded"];
  index:state`count;
  if[index>=(limits`directives);
    '"Dependency directive limit exceeded"];
  targets:state`targets;
  tails:state`tails;
  kinds:state`kinds;
  targets[index]:text;
  tails[index]:tail;
  kinds[index]:kind;
  state[`targets]:targets;
  state[`tails]:tails;
  state[`kinds]:kinds;
  state[`count]:index+1;
  state[`bytes]:nextBytes;
  state
 };

dependencyTokenAt:{[line;start;token]
  if[(start<0) or (start+count token)>count line;:0b];
  if[not token~(count token)#start _ line;:0b];
  identifier:.Q.a,.Q.A,.Q.n,"._";
  if[start>0;
    if[line[start-1] in identifier;:0b]];
  finish:start+count token;
  if[finish<count line;
    if[line[finish] in identifier;:0b]];
  1b
 };

dependencyQuoteMaskLine:{[line;initialInString;initialEscape]
  inString:initialInString;
  escaped:initialEscape;
  inComment:0b;
  markers:(count line)#0b;
  i:0;
  while[i<count line;
    char:line i;
    $[inComment;
        (::);
      inString;
        $[escaped;
            escaped:0b;
          char="\\";
            escaped:1b;
          char="\"";
            inString:0b;
          (::)];
      char="\"";
        [markers[i]:1b;inString:1b];
      (char="/") and
        ((i=0) or line[i-1] in " \t");
        inComment:1b;
      (::)];
    i+:1];
  (markers;inString;escaped)
 };

/ Mark only executable string-opening quotes while preserving line lengths.
/ This parallels static masking so quotes in comments, block comments, and
/ terminated script tails can never become dependency literals.
dependencyQuoteMasks:{[lines]
  output:();
  inBlock:0b;
  terminated:0b;
  inString:0b;
  escaped:0b;
  i:0;
  while[i<count lines;
    raw:lines i;
    rightTrimmed:.tst.static.rstrip raw;
    blank:(count raw)#0b;
    $[terminated;
        output,:enlist blank;
      inBlock;
        [output,:enlist blank;
         if[rightTrimmed~enlist "\\";
           inBlock:0b]];
      (not inString) and
        rightTrimmed~enlist "/";
        [inBlock:1b;output,:enlist blank];
      (not inString) and
        ((count raw)>0) and
        ("\\"=first raw) and
        rightTrimmed~enlist "\\";
        [terminated:1b;output,:enlist blank];
        [marked:.tst.dependencyQuoteMaskLine[
           raw;
           inString;
           escaped];
         output,:enlist marked 0;
         inString:marked 1;
         escaped:marked 2]];
    i+:1];
  output
 };

dependencyDepthsAt:{[codeText;positions]
  depths:(count positions)#0;
  depth:0;
  cursor:0;
  positionIndex:0;
  while[positionIndex<count positions;
    position:positions positionIndex;
    if[(position<cursor) or position>count codeText;
      '"Dependency token positions are invalid"];
    while[cursor<position;
      char:codeText cursor;
      if[char in "{([";
        depth+:1];
      if[char in "})]";
        depth-:1;
        if[depth<0;depth:0]];
      cursor+:1];
    depths[positionIndex]:depth;
    positionIndex+:1];
  depths
 };

dependencyRequireForm:{[between;contextOpen]
  if[not -1h=type contextOpen;
    '"Dependency require context is invalid"];
  lineBreak:between?"\n";
  crossesLine:lineBreak<count between;
  firstLine:trim lineBreak#between;
  prefix:trim ssr[between;"\n";" "];
  / A newline closes a complete q expression. Cross-line parsing is valid
  / only when an enclosing expression is open, or when the token's own line
  / opens a wrapper or ends in a continuation operator.
  if[crossesLine and
     (not contextOpen) and
     not count firstLine;
    :`recognized`tail`closing!(0b;0b;"")];
  if[not count prefix;
    :`recognized`tail`closing!(1b;0b;"")];
  wrapper:$[
    first[prefix]="[";
      enlist "[";
    first[prefix]="(";
      enlist "(";
    ""];
  if[count wrapper;
    body:trim 1_prefix;
    closing:$[
      wrapper~enlist "[";
        enlist "]";
      enlist ")"];
    if[not count body;
      :`recognized`tail`closing!(1b;0b;closing)];
    if[not ","=last body;
      :`recognized`tail`closing!(0b;0b;"")];
    base:trim -1_body;
    if[(not count base) or
       base~enlist "." or
       not .tst.static.validFunctionName base;
      :`recognized`tail`closing!(0b;0b;"")];
    :`recognized`tail`closing!(1b;1b;closing)];
  if[not ","=last prefix;
    :`recognized`tail`closing!(0b;0b;"")];
  base:trim -1_prefix;
  if[(not count base) or
     base~enlist "." or
     not .tst.static.validFunctionName base;
    :`recognized`tail`closing!(0b;0b;"")];
  `recognized`tail`closing!(1b;1b;"")
 };

dependencyQuotedLiteral:{[line;start]
  if[(start>=count line) or not "\""=line start;
    :`ok`text`end!(0b;"";start)];
  output:"";
  closed:0b;
  escapedMode:0b;
  i:start+1;
  while[(i<count line) and not closed;
    char:line i;
    $[escapedMode;
        [supported:(char="\\") or char="\"";
         if[not supported;
           if[char in "nrt";
             '"Control escapes are not allowed in dependency paths"];
           '"Unsupported dependency path escape"];
         output,:enlist char;
         escapedMode:0b];
      char="\\";
        escapedMode:1b;
      char="\"";
        closed:1b;
      output,:enlist char];
    i+:1];
  if[escapedMode;
    '"Unterminated dependency path escape"];
  `ok`text`end!(
    closed;
    output;
    $[closed;i-1;i])
 };

dependencyRequireTailValid:{[codeText;literalEnd;stop;closing]
  if[(literalEnd<0) or
     (stop<literalEnd+1) or
     stop>count codeText;
    '"Dependency require suffix bounds are invalid"];
  tail:((stop-literalEnd)-1)#(literalEnd+1)_codeText;
  cursor:0;
  if[count closing;
    while[(cursor<count tail) and
          tail[cursor] in " \t\r\n";
      cursor+:1];
    if[(cursor>=count tail) or
       not (enlist tail cursor)~closing;
      :0b];
    cursor+:1];
  remainder:cursor _ tail;
  lineEnd:remainder?"\n";
  firstLine:lineEnd#remainder;
  / A call can be nested inside a lambda, conditional, or argument list. Its
  / expression is complete when only outer closing delimiters remain.
  allowed:firstLine in " \t\r})]";
  all allowed
 };

emptyDependencyRecords:{[]
  ([] target:();tail:`boolean$();kind:`symbol$())
 };

/ Parse executable \l and .utl.require forms from a bounded regular-file
/ snapshot. Strings, line comments, block comments, and terminated script tails
/ are masked before token detection, so diagnostic text cannot become an edge.
readDependencyRecordsWith:{[reader;filepath;limits]
  if[not type[reader] within 100 112h;
    '"Dependency reader is unavailable"];
  path:.utl.absolutePath filepath;
  source:reader[path;limits`sourceBytes];
  if[(not 99h=type source) or
     not all `path`identity`bytes in key source or
     not all 10h=type each (source`path;source`identity) or
     not 4h=type source`bytes;
    '"Dependency source read result is invalid"];
  if[(not .utl.pathWithinRoot[
          source`path;
          path;
          .utl.isWindows]) or
     not .utl.pathWithinRoot[
          path;
          source`path;
          .utl.isWindows];
    '"Dependency source read path is inconsistent"];
  if[(not count source`identity) or
     count[source`identity]>65536;
    '"Dependency source identity is invalid"];
  if[count[source`bytes]>(limits`sourceBytes);
    '"Dependency source byte limit exceeded"];
  lines:.utl.textLinesBounded[
    source`bytes;
    limits`sourceLines];
  masked:.tst.static.maskLines lines;
  if[count[masked]<>count lines;
    '"Dependency source mask is invalid"];
  quoteLines:.tst.dependencyQuoteMasks lines;
  if[count[quoteLines]<>count lines;
    '"Dependency quote mask is invalid"];
  state:.tst.dependencyRecordState limits`directives;
  token:".utl.require";
  examined:0j;
  lineIndex:0;
  while[lineIndex<count lines;
    raw:lines lineIndex;
    code:masked lineIndex;
    if[code like "\\l *";
      examined+:1;
      if[examined>(limits`directives);
        '"Dependency directive scan limit exceeded"];
      state:.tst.appendDependencyRecord[
        state;
        trim 3 _ raw;
        0b;
        `load;
        limits]];
    lineIndex+:1];
  rawText:"\n" sv lines;
  codeText:"\n" sv masked;
  quotePieces:{x,0b} each quoteLines;
  quoteText:$[
    count quotePieces;
      -1 _ raze quotePieces;
    `boolean$()];
  if[count[quoteText]<>count rawText;
    '"Dependency quote mask is inconsistent"];
  positions:codeText ss token;
  contextDepths:.tst.dependencyDepthsAt[
    codeText;
    positions];
  examined+:count positions;
  if[examined>(limits`directives);
    '"Dependency directive scan limit exceeded"];
  positionIndex:0;
  while[positionIndex<count positions;
    start:positions positionIndex;
    if[.tst.dependencyTokenAt[codeText;start;token];
      tokenEnd:start+count token;
      stop:count rawText;
      if[(positionIndex+1)<count positions;
        stop:stop & positions positionIndex+1];
      tailCode:(stop-tokenEnd)#tokenEnd _ codeText;
      semicolon:tailCode?";";
      if[semicolon<count tailCode;
        stop:tokenEnd+semicolon];
      segment:(stop-tokenEnd)#tokenEnd _ rawText;
      quoteSegment:(stop-tokenEnd)#tokenEnd _ quoteText;
      quoteOffset:quoteSegment?1b;
      if[quoteOffset<count segment;
        quoteAt:tokenEnd+quoteOffset;
        between:
          (quoteAt-tokenEnd)#tokenEnd _ codeText;
        form:.tst.dependencyRequireForm[
          between;
          0<contextDepths positionIndex];
        if[form`recognized;
          literal:.tst.dependencyQuotedLiteral[
            rawText;
            quoteAt];
          if[not literal`ok;
            '"Unterminated dependency path literal"];
          if[(literal`end)>=stop;
            '"Dependency path literal crosses its statement boundary"];
          if[.tst.dependencyRequireTailValid[
              codeText;
              literal`end;
              stop;
              form`closing];
            state:.tst.appendDependencyRecord[
              state;
              literal`text;
              form`tail;
              `require;
              limits]]]]];
    positionIndex+:1];
  used:state`count;
  records:$[
    0=used;
      .tst.emptyDependencyRecords[];
    ([] target:used#state`targets;
        tail:used#state`tails;
        kind:used#state`kinds)];
  `records`sourceBytes`examined!(
    records;
    count source`bytes;
    examined)
 };

parseDependencyRecordsWith:{[reader;filepath;limits]
  parsed:.tst.readDependencyRecordsWith[
    reader;
    filepath;
    limits];
  parsed`records
 };

parseDependencyRecords:{[filepath]
  adapter:.utl.fsSnapshot[];
  .tst.parseDependencyRecordsWith[
    adapter`readRegular;
    filepath;
    .tst.dependencyLimits[]]
 };

/ Compatibility API: return the literal targets as symbols. Graph construction
/ consumes the richer records above so direct absolute paths and concatenated
/ leading-slash tails remain distinguishable.
parseLoadDirectives:{[filepath]
  records:.tst.parseDependencyRecords filepath;
  if[0=count records;:`symbol$()];
  distinct .tst.dependencyPathSymbol each records`target
 };

dependencyBaseDir:{[file]
  absolute:.utl.absolutePath file;
  directory:.tst.static.getDir absolute;
  $[count directory;directory;"/"]
 };

resolveDepTargetRecordText:{[reqFile;target;tail]
  if[not -1h=type tail;
    '"Dependency directive metadata is invalid"];
  text:.utl.pathToString target;
  if[not count text;
    '"Dependency target is empty"];
  if[tail and first[text] in "/\\";
    text:1 _ text];
  if[tail and count[text] and first[text] in "/\\";
    '"Dependency target tail has ambiguous leading separators"];
  if[not count text;
    '"Dependency target is empty"];
  candidate:.utl.absolutePathForHost[
    text;
    .utl.isWindows;
    .tst.dependencyBaseDir reqFile];
  candidate
 };

resolveDepTargetRecord:{[reqFile;target;tail]
  .tst.dependencyPathSymbol
    .tst.resolveDepTargetRecordText[
      reqFile;
      target;
      tail]
 };

/ Public direct-target resolver: an absolute target remains absolute. Scanner
/ metadata invokes resolveDepTargetRecord with tail=1b only for concatenations.
resolveDepTarget:{[reqFile;target]
  .tst.resolveDepTargetRecord[reqFile;target;0b]
 };

/ A sorted character-vector index keeps dependency resolution free of symbol
/ creation and avoids rescanning the full discovery set for every directive.
dependencyFileSetWith:{[files;windows;limits]
  if[not -1h=type windows;
    '"Dependency file-set host flag is invalid"];
  if[not 0h=type files;
    '"Dependency file set is invalid"];
  if[not all 10h=type each files;
    '"Dependency file set contains invalid entries"];
  if[(not 99h=type limits) or
     not all `files`pathBytes in key limits;
    '"Dependency file-set limits are invalid"];
  if[count[files]>(limits`files);
    '"Dependency file-set limit exceeded"];
  if[.tst.dependencyItemBytes[files]>(limits`pathBytes);
    '"Dependency file-set path byte limit exceeded"];
  files:distinct files;
  fileIndex:0;
  while[fileIndex<count files;
    info:.utl.pathPolicy[
      files fileIndex;
      "dependency file-set path";
      windows];
    if[not info`absolute;
      '"Dependency file-set path is not absolute"];
    if[not (files fileIndex)~info`normalized;
      '"Dependency file-set path is not normalized"];
    fileIndex+:1];
  canonical:$[
    windows;
      lower each files;
    files];
  if[count[canonical]<>count distinct canonical;
    '"Dependency file set contains ambiguous path aliases"];
  order:iasc canonical;
  state:`files`index`paths`windows!(
    files;
    canonical order;
    files order;
    windows);
  .tst.validateDependencyFileSet[
    state;
    limits]
 };

validateDependencyFileSet:{[fileSet;limits]
  if[(not 99h=type fileSet) or
     not `files`index`paths`windows~key fileSet;
    '"Dependency file set is invalid"];
  if[(not 99h=type limits) or
     not all `files`pathBytes in key limits;
    '"Dependency file-set limits are invalid"];
  files:fileSet`files;
  index:fileSet`index;
  paths:fileSet`paths;
  windows:fileSet`windows;
  if[(not -1h=type windows) or
     (not 0h=type files) or
     (not 0h=type index) or
     (not 0h=type paths);
    '"Dependency file set is invalid"];
  if[(not all 10h=type each files) or
     (not all 10h=type each index) or
     not all 10h=type each paths;
    '"Dependency file set contains invalid entries"];
  if[(count[files]<>count index) or
     count[files]<>count paths;
    '"Dependency file set shape is invalid"];
  if[count[files]>(limits`files);
    '"Dependency file-set limit exceeded"];
  if[.tst.dependencyItemBytes[files]>(limits`pathBytes);
    '"Dependency file-set path byte limit exceeded"];
  if[count[files]<>count distinct files;
    '"Dependency file set contains duplicate paths"];
  fileIndex:0;
  while[fileIndex<count files;
    info:.utl.pathPolicy[
      files fileIndex;
      "dependency file-set path";
      windows];
    if[not info`absolute;
      '"Dependency file-set path is not absolute"];
    if[not (files fileIndex)~info`normalized;
      '"Dependency file-set path is not normalized"];
    fileIndex+:1];
  canonical:$[
    windows;
      lower each files;
    files];
  if[count[canonical]<>count distinct canonical;
    '"Dependency file set contains ambiguous path aliases"];
  order:iasc canonical;
  if[not index~canonical order;
    '"Dependency file-set index is inconsistent"];
  if[not paths~files order;
    '"Dependency file-set path mapping is inconsistent"];
  fileSet
 };

dependencyFileSet:{[files;windows]
  .tst.dependencyFileSetWith[
    files;
    windows;
    .tst.dependencyLimits[]]
 };

dependencyFileSetFindTrusted:{[fileSet;path]
  if[(not 99h=type fileSet) or
     not all `index`paths`windows in key fileSet;
    '"Dependency file set is invalid"];
  windows:fileSet`windows;
  index:fileSet`index;
  paths:fileSet`paths;
  if[(not -1h=type windows) or
     (not 0h=type index) or
     (not 0h=type paths) or
     count[index]<>count paths;
    '"Dependency file set is invalid"];
  if[not count index;
    :`found`value!(0b;"")];
  candidate:.utl.normalizePathForHost[
    path;
    windows];
  if[windows;
    candidate:lower candidate];
  position:first index bin enlist candidate;
  if[position<0;
    :`found`value!(0b;"")];
  if[position>=count index;
    :`found`value!(0b;"")];
  if[not candidate~index position;
    :`found`value!(0b;"")];
  `found`value!(1b;paths position)
 };

dependencyFileSetFind:{[fileSet;path]
  validated:.tst.validateDependencyFileSet[
    fileSet;
    .tst.dependencyLimits[]];
  .tst.dependencyFileSetFindTrusted[
    validated;
    path]
 };

dependencyFileSetContainsTrusted:{[fileSet;path]
  (.tst.dependencyFileSetFindTrusted[
    fileSet;
    path])`found
 };

dependencyFileSetContains:{[fileSet;path]
  (.tst.dependencyFileSetFind[
    fileSet;
    path])`found
 };

/ Graph builds resolve native \l targets against their bounded discovery set.
/ This is exact for graph-tracked sources and avoids filesystem probes that
/ would irreversibly intern rejected or unpublished candidate paths.
resolveLoadTargetTextTrusted:{[fileSet;cwd;qhome;target]
  if[(not 99h=type fileSet) or
     not `windows in key fileSet;
    '"Dependency file set is invalid"];
  windows:fileSet`windows;
  if[not -1h=type windows;
    '"Dependency file-set host flag is invalid"];
  text:.utl.pathToString target;
  if[not count text;
    '"Dependency target is empty"];
  info:.utl.pathPolicy[
    text;
    "load dependency target";
    windows];
  if[info`absolute;
    absoluteState:.tst.dependencyFileSetFindTrusted[
      fileSet;
      info`normalized];
    :$[
      absoluteState`found;
        absoluteState`value;
      info`normalized]];
  cwdCandidate:.utl.absolutePathForHost[
    text;
    windows;
    cwd];
  cwdState:.tst.dependencyFileSetFindTrusted[
    fileSet;
    cwdCandidate];
  if[cwdState`found;
    :cwdState`value];
  qhomeText:$[
    type[qhome] in -10 10 -11h;
      .utl.pathToString qhome;
    ""];
  / Native q decides whether to search QHOME from the spelling supplied by
  / the caller. Preserve an explicit "./" even though normalization removes it.
  hasComponent:any text in "/\\";
  if[(not hasComponent) and count qhomeText;
    qhomeInfo:.utl.pathPolicy[
      qhomeText;
      "QHOME";
      windows];
    if[not qhomeInfo`absolute;
      '"QHOME is not absolute"];
    qhomeCandidate:.utl.absolutePathForHost[
      text;
      windows;
      qhomeInfo`normalized];
    qhomeState:.tst.dependencyFileSetFindTrusted[
      fileSet;
      qhomeCandidate];
    if[qhomeState`found;
      :qhomeState`value]];
  cwdCandidate
 };

resolveLoadTargetTextWith:{[fileSet;cwd;qhome;target]
  validated:.tst.validateDependencyFileSet[
    fileSet;
    .tst.dependencyLimits[]];
  .tst.resolveLoadTargetTextTrusted[
    validated;
    cwd;
    qhome;
    target]
 };

resolveLoadTargetWith:{[windows;cwd;qhome;target;fileSymbols]
  files:.utl.pathToString each fileSymbols;
  fileSet:.tst.dependencyFileSet[
    files;
    windows];
  .tst.dependencyPathSymbol
    .tst.resolveLoadTargetTextTrusted[
      fileSet;
      cwd;
      qhome;
      target]
 };

resolveLoadTargetText:{[target;files]
  qhome:@[getenv;`QHOME;{""}];
  fileSet:.tst.dependencyFileSet[
    files;
    .utl.isWindows];
  .tst.resolveLoadTargetTextTrusted[
    fileSet;
    system "cd";
    qhome;
    target]
 };

resolveLoadTarget:{[target;fileSymbols]
  .tst.dependencyPathSymbol
    .tst.resolveLoadTargetText[
      target;
      .utl.pathToString each fileSymbols]
 };

dependencyPathHasSuffix:{[suffix;path;windows]
  candidate:.utl.normalizePathForHost[path;windows];
  expected:suffix;
  if[windows;
    candidate:lower candidate;
    expected:lower expected];
  if[count[expected]>count candidate;:0b];
  expected~neg[count expected]#candidate
 };

/ A simple concatenated suffix usually names a sibling of the requiring file.
/ When its lexical sibling does not exist in the scanned set, use an exact,
/ unique discovered suffix match. This covers package-root variables without
/ guessing when multiple roots contain the same tail.
resolveDepTargetFromFileSetTextTrusted:{[resolved;target;tail;fileSet]
  exactState:.tst.dependencyFileSetFindTrusted[
    fileSet;
    resolved];
  if[exactState`found;
    :exactState`value];
  if[not tail;:resolved];
  files:fileSet`files;
  targetText:.utl.pathToString target;
  if[count[targetText] and first[targetText] in "/\\";
    targetText:1 _ targetText];
  normalized:.utl.normalizePathForHost[
    targetText;
    fileSet`windows];
  suffix:"/",normalized;
  matches:files where
    .tst.dependencyPathHasSuffix[
      suffix;
      ;
      fileSet`windows] each files;
  if[1=count matches;
    :first matches];
  if[1<count matches;
    '"Ambiguous dependency target suffix: ",
      .utl.boundedDiagnostic[targetText;512]];
  resolved
 };

resolveDepTargetFromFileSetText:{[resolved;target;tail;fileSet]
  validated:.tst.validateDependencyFileSet[
    fileSet;
    .tst.dependencyLimits[]];
  .tst.resolveDepTargetFromFileSetTextTrusted[
    resolved;
    target;
    tail;
    validated]
 };

resolveDepTargetFromFiles:{[reqFile;target;tail;files]
  fileTexts:.utl.pathToString each files;
  fileSet:.tst.dependencyFileSet[
    fileTexts;
    .utl.isWindows];
  resolved:.tst.resolveDepTargetRecordText[
    reqFile;
    target;
    tail];
  .tst.dependencyPathSymbol
    .tst.resolveDepTargetFromFileSetTextTrusted[
      resolved;
      target;
      tail;
      fileSet]
 };

dependencyRoots:{[dirs;limits]
  t:type dirs;
  items:$[
    t in -10 10 -11h;
      enlist dirs;
    11h=t;
      dirs;
    0h=t;
      dirs;
    '"Dependency roots are invalid"];
  if[not count items;
    '"Dependency roots are empty"];
  if[count[items]>(limits`files);
    '"Dependency root limit exceeded"];
  if[not all {type[x] in -10 10 -11h} each items;
    '"Dependency roots are invalid"];
  if[any 0=count each .utl.pathToString each items;
    '"Dependency root is empty"];
  if[.tst.dependencyItemBytes[items]>(limits`pathBytes);
    '"Dependency root path byte limit exceeded"];
  roots:.utl.absolutePath each items;
  roots:distinct roots;
  if[.tst.dependencyItemBytes[roots]>(limits`pathBytes);
    '"Dependency root path byte limit exceeded"];
  roots
 };

dependencyFilesWith:{[walker;adapter;dirs;limits]
  if[not type[walker] within 100 112h;
    '"Dependency traversal is unavailable"];
  roots:.tst.dependencyRoots[dirs;limits];
  if[0=count roots;:()];
  walked:walker[".q";roots;adapter];
  if[(not 99h=type walked) or
     not all `files`problems`failureCount in key walked;
    '"Dependency traversal result is invalid"];
  failureCount:walked`failureCount;
  if[not type[failureCount] in -5 -6 -7h;
    '"Dependency traversal result is invalid"];
  if[(null failureCount) or
     failureCount<0 or
     failureCount in
       (0Wh;-0Wh;0Wi;-0Wi;0W;-0W);
    '"Dependency traversal result is invalid"];
  if[failureCount;
    problems:walked`problems;
    problems:$[
      10h=type problems;
        enlist problems;
      0h=type problems;
        (8&count problems)#problems;
      enlist problems];
    details:$[
      count problems;
        "; " sv .utl.boundedDiagnostic[;512] each problems;
      "unknown traversal failure"];
    '"Incomplete dependency traversal: ",details];
  files:walked`files;
  if[10h=type files;files:enlist files];
  if[(not 0h=type files) or
     not all 10h=type each files;
    '"Dependency traversal files are invalid"];
  if[count[files]>(limits`files);
    '"Dependency file limit exceeded"];
  pathBytes:
    .tst.dependencyItemBytes[roots]+
    .tst.dependencyItemBytes[files];
  if[pathBytes>(limits`pathBytes);
    '"Dependency path byte limit exceeded"];
  asc distinct files
 };

dependencySymbols:{[input;label]
  t:type input;
  if[-11h=t;:enlist input];
  if[11h=t;:input];
  if[(0h=t) and 0=count input;:`symbol$()];
  if[0h=t;
    if[not all -11h=type each input;
      'label," contains invalid entries"];
    :`symbol$input];
  'label," is invalid"
 };

validateDependencyRegistry:{[registry;label;limits;keyLimit]
  if[not 99h=type registry;
    'label," is invalid"];
  registryKeys:.tst.dependencySymbols[
    key registry;
    label," keys"];
  if[count[registryKeys]<>count distinct registryKeys;
    'label," contains duplicate keys"];
  if[count[registryKeys]>keyLimit;
    'label," key limit exceeded"];
  edges:0j;
  pathBytes:0j;
  index:0;
  while[index<count registryKeys;
    pathBytes+:count .tst.dependencyPathText[
      registryKeys index;
      label," key"];
    if[pathBytes>(limits`pathBytes);
      'label," path byte limit exceeded"];
    entries:.tst.dependencySymbols[
      registry registryKeys index;
      label," values"];
    if[count[entries]<>count distinct entries;
      'label," contains duplicate edges"];
    edges+:count entries;
    if[edges>(limits`edges);
      'label," edge limit exceeded"];
    entryIndex:0;
    while[entryIndex<count entries;
      pathBytes+:count .tst.dependencyPathText[
        entries entryIndex;
        label," value"];
      if[pathBytes>(limits`pathBytes);
        'label," path byte limit exceeded"];
      entryIndex+:1];
    index+:1];
  registry
 };

reverseDependencyGraph:{[forward;limits]
  forward:.tst.validateDependencyRegistry[
    forward;
    "Dependency registry";
    limits;
    limits`files];
  reverseGraph:()!();
  files:.tst.dependencySymbols[
    key forward;
    "Dependency registry keys"];
  edgeCount:0j;
  fileIndex:0;
  while[fileIndex<count files;
    file:files fileIndex;
    deps:.tst.dependencySymbols[
      forward file;
      "Dependency registry values"];
    edgeCount+:count deps;
    if[edgeCount>(limits`edges);
      '"Dependency edge limit exceeded"];
    depIndex:0;
    while[depIndex<count deps;
      dep:deps depIndex;
      current:$[
        dep in key reverseGraph;
          .tst.dependencySymbols[
            reverseGraph dep;
            "Dependency graph values"];
        `symbol$()];
      reverseGraph[dep]:distinct current,enlist file;
      depIndex+:1];
    fileIndex+:1];
  .tst.validateDependencyRegistry[
    reverseGraph;
    "Dependency graph";
    limits;
    (limits`files)+(limits`edges)]
 };

dependencyTextList:{[input;label]
  if[not 0h=type input;
    'label," is invalid"];
  if[not all 10h=type each input;
    'label," contains invalid entries"];
  input
 };

dependencyAbsoluteText:{[path;label]
  if[not 10h=type path;
    'label," is invalid"];
  if[not count path;
    'label," is empty"];
  info:.utl.pathPolicy[
    path;
    label;
    .utl.isWindows];
  if[not info`absolute;
    'label," is not absolute"];
  if[not path~info`normalized;
    'label," is not normalized"];
  path
 };

/ Validate the character-vector graph completely before any dependency path is
/ interned. The returned path list is the exact batch needed for publication.
validateDependencyTextState:{[state;limits]
  if[not 99h=type state;
    '"Dependency text state is invalid"];
  required:`files`deps;
  present:required in key state;
  if[not all present;
    '"Dependency text state is invalid"];
  files:.tst.dependencyTextList[
    state`files;
    "Dependency text files"];
  depsByFile:state`deps;
  if[not 0h=type depsByFile;
    '"Dependency text dependencies are invalid"];
  if[count[files]<>count depsByFile;
    '"Dependency text state shape is invalid"];
  if[count[files]>(limits`files);
    '"Dependency file limit exceeded"];
  if[count[files]<>count distinct files;
    '"Dependency text files contain duplicates"];
  pathCapacity:(count files)+(limits`edges);
  paths:pathCapacity#enlist "";
  dependencyPaths:(limits`edges)#enlist "";
  pathCount:0;
  dependencyCount:0;
  edgeCount:0j;
  pathBytes:0j;
  reverseValueBytes:0j;
  canonicalDeps:(count files)#enlist ();
  fileIndex:0;
  while[fileIndex<count files;
    file:.tst.dependencyAbsoluteText[
      files fileIndex;
      "Dependency text file"];
    paths[pathCount]:file;
    pathCount+:1;
    pathBytes+:count file;
    if[pathBytes>(limits`pathBytes);
      '"Dependency path byte limit exceeded"];
    entries:.tst.dependencyTextList[
      depsByFile fileIndex;
      "Dependency text values"];
    if[count[entries]<>count distinct entries;
      '"Dependency text values contain duplicates"];
    edgeCount+:count entries;
    if[edgeCount>(limits`edges);
      '"Dependency edge limit exceeded"];
    reverseValueBytes+:
      ("j"$count entries)*count file;
    if[reverseValueBytes>(limits`pathBytes);
      '"Dependency reverse path byte limit exceeded"];
    entryIndex:0;
    while[entryIndex<count entries;
      entry:.tst.dependencyAbsoluteText[
        entries entryIndex;
        "Dependency text value"];
      paths[pathCount]:entry;
      pathCount+:1;
      dependencyPaths[dependencyCount]:entry;
      dependencyCount+:1;
      pathBytes+:count entry;
      if[pathBytes>(limits`pathBytes);
        '"Dependency path byte limit exceeded"];
      entryIndex+:1];
    canonicalDeps[fileIndex]:entries;
    fileIndex+:1];
  uniqueDependencies:
    distinct dependencyCount#dependencyPaths;
  reversePathBytes:reverseValueBytes+
    $[
      count uniqueDependencies;
        sum "j"$count each uniqueDependencies;
      0j];
  if[reversePathBytes>(limits`pathBytes);
    '"Dependency reverse path byte limit exceeded"];
  `files`deps`paths`edges`pathBytes!(
    files;
    canonicalDeps;
    pathCount#paths;
    edgeCount;
    pathBytes)
 };

/ Check the full batch against the shared process-lifetime registry before the
/ first new symbol is created. In q's single-threaded execution, the subsequent
/ admission loop cannot partially exhaust a batch that passed this preflight.
dependencyAdmissionPlan:{[paths]
  paths:.tst.dependencyTextList[
    paths;
    "Dependency admission paths"];
  pathIndex:0;
  while[pathIndex<count paths;
    .tst.dependencyAbsoluteText[
      paths pathIndex;
      "Dependency admission path"];
    pathIndex+:1];
  uniquePaths:distinct paths;
  registryState:.utl.validatePathSymbolRegistry[];
  capabilities:.utl.pathSymbolCapabilities[];
  existing:.utl.pathSymbolTexts;
  combined:distinct existing,uniquePaths;
  newCount:(count combined)-count existing;
  combinedBytes:$[
    count combined;
      sum "j"$count each combined;
    0j];
  newBytes:combinedBytes-registryState`used;
  if[(newCount<0) or newBytes<0;
    '"Dependency admission plan is inconsistent"];
  if[newCount>0;
    if[count[combined]>(capabilities[`limits]`symbols);
      '"Path symbol budget exhausted"];
    if[combinedBytes>(capabilities[`limits]`symbolBytes);
      '"Path symbol byte budget exhausted"]];
  `paths`writer!(
    uniquePaths;
    capabilities`toHsym)
 };

admitDependencyPaths:{[paths]
  plan:.tst.dependencyAdmissionPlan paths;
  writer:plan`writer;
  writer each plan`paths;
  (::)
 };

materializeDependencyTextState:{[state;limits]
  validated:.tst.validateDependencyTextState[
    state;
    limits];
  .tst.admitDependencyPaths validated`paths;
  toSymbol:{`$x};
  files:validated`files;
  fileSymbols:toSymbol each files;
  depsByFile:validated`deps;
  symbolDeps:(count files)#enlist `symbol$();
  fileIndex:0;
  while[fileIndex<count files;
    symbolDeps[fileIndex]:
      toSymbol each depsByFile fileIndex;
    fileIndex+:1];
  forward:$[
    count files;
      fileSymbols!symbolDeps;
    ()!()];
  forward:.tst.validateDependencyRegistry[
    forward;
    "Dependency registry";
    limits;
    limits`files];
  reverseGraph:.tst.reverseDependencyGraph[
    forward;
    limits];
  sourceBytes:$[
    `sourceBytes in key state;
      state`sourceBytes;
    0j];
  examined:$[
    `examined in key state;
      state`examined;
    0j];
  matchWork:$[
    `matchWork in key state;
      state`matchWork;
    0j];
  `forward`reverse`files`edges`sourceBytes`examined`matchWork!(
    forward;
    reverseGraph;
    files;
    validated`edges;
    sourceBytes;
    examined;
    matchWork)
 };

dependencyRegistryTextState:{[registry;limits]
  registry:.tst.validateDependencyRegistry[
    registry;
    "Dependency registry";
    limits;
    limits`files];
  fileSymbols:.tst.dependencySymbols[
    key registry;
    "Dependency registry keys"];
  files:.utl.pathToString each fileSymbols;
  depsByFile:(count files)#enlist ();
  fileIndex:0;
  while[fileIndex<count files;
    entries:.tst.dependencySymbols[
      registry fileSymbols fileIndex;
      "Dependency registry values"];
    depsByFile[fileIndex]:
      .utl.pathToString each entries;
    fileIndex+:1];
  .tst.validateDependencyTextState[
    `files`deps!(files;depsByFile);
    limits]
 };

buildDependencyTextStateWith:{[walker;adapter;reader;dirs;limits]
  windows:.utl.isWindows;
  cwd:system "cd";
  qhome:@[getenv;`QHOME;{""}];
  files:.tst.dependencyFilesWith[
    walker;adapter;dirs;limits];
  fileSet:.tst.dependencyFileSetWith[
    files;
    windows;
    limits];
  depsByFile:(count files)#enlist ();
  edgeCount:0j;
  pathBytes:.tst.dependencyItemBytes files;
  sourceBytes:0j;
  examined:0j;
  matchWork:0j;
  fileIndex:0;
  while[fileIndex<count files;
    file:files fileIndex;
    parsed:.tst.readDependencyRecordsWith[
      reader;file;limits];
    sourceBytes+:parsed`sourceBytes;
    if[sourceBytes>(limits`totalSourceBytes);
      '"Aggregate dependency source byte limit exceeded"];
    examined+:parsed`examined;
    if[examined>(limits`edges);
      '"Aggregate dependency directive scan limit exceeded"];
    records:parsed`records;
    depCount:count records;
    depBuffer:depCount#enlist "";
    depIndex:0;
    while[depIndex<depCount;
      kind:records[depIndex;`kind];
      if[not kind in `load`require;
        '"Dependency directive kind is invalid"];
      if[kind~`load;
        resolved:.tst.resolveLoadTargetTextTrusted[
          fileSet;
          cwd;
          qhome;
          records[depIndex;`target]]];
      if[kind~`require;
        localResolved:.tst.resolveDepTargetRecordText[
          file;
          records[depIndex;`target];
          records[depIndex;`tail]];
        if[records[depIndex;`tail] and
           not .tst.dependencyFileSetContainsTrusted[
             fileSet;
             localResolved];
          nextMatchWork:matchWork+count files;
          if[nextMatchWork>(limits`matchWork);
            '"Dependency suffix-match work limit exceeded"];
          matchWork:nextMatchWork];
        resolved:.tst.resolveDepTargetFromFileSetTextTrusted[
          localResolved;
          records[depIndex;`target];
          records[depIndex;`tail];
          fileSet]];
      depBuffer[depIndex]:resolved;
      pathBytes+:count resolved;
      if[pathBytes>(limits`pathBytes);
        '"Dependency path byte limit exceeded"];
      depIndex+:1];
    fileDeps:distinct depBuffer;
    edgeCount+:count fileDeps;
    if[edgeCount>(limits`edges);
      '"Dependency edge limit exceeded"];
    depsByFile[fileIndex]:fileDeps;
    fileIndex+:1];
  state:`files`deps`edges`sourceBytes`examined`matchWork!(
    files;
    depsByFile;
    edgeCount;
    sourceBytes;
    examined;
    matchWork);
  .tst.validateDependencyTextState[
    state;
    limits];
  state
 };

buildDependencyStateWith:{[walker;adapter;reader;dirs;limits]
  .tst.materializeDependencyTextState[
    .tst.buildDependencyTextStateWith[
      walker;
      adapter;
      reader;
      dirs;
      limits];
    limits]
 };

buildDependencyTextState:{[dirs]
  if[not `walkFiles in key `.tst;
    '"Dependency traversal is unavailable"];
  adapter:.utl.fsSnapshot[];
  .tst.buildDependencyTextStateWith[
    .tst.walkFiles;
    adapter;
    adapter`readRegular;
    dirs;
    .tst.dependencyLimits[]]
 };

buildDependencyState:{[dirs]
  limits:.tst.dependencyLimits[];
  .tst.materializeDependencyTextState[
    .tst.buildDependencyTextState dirs;
    limits]
 };

publishDependencyState:{[state]
  if[(not 99h=type state) or
     not all `forward`reverse in key state;
    '"Dependency build state is invalid"];
  limits:.tst.dependencyLimits[];
  forward:.tst.validateDependencyRegistry[
    state`forward;
    "Dependency registry";
    limits;
    limits`files];
  reverseGraph:.tst.validateDependencyRegistry[
    state`reverse;
    "Dependency graph";
    limits;
    (limits`files)+(limits`edges)];
  expectedReverse:.tst.reverseDependencyGraph[
    forward;
    limits];
  if[not expectedReverse~reverseGraph;
    '"Dependency build state is inconsistent"];
  .tst.dependencies::forward;
  .tst.depGraph::reverseGraph;
  reverseGraph
 };

/ Scan one directory transactionally. Existing files outside that directory
/ remain registered; rescanned files replace their old dependency vectors.
scanDirectory:{[dir]
  limits:.tst.dependencyLimits[];
  existing:.tst.validateDependencyRegistry[
    .tst.dependencies;
    "Dependency registry";
    limits;
    limits`files];
  roots:.tst.dependencyRoots[dir;limits];
  if[1<>count roots;
    '"Dependency scan requires exactly one root"];
  root:first roots;
  existingText:.tst.dependencyRegistryTextState[
    existing;
    limits];
  incoming:.tst.buildDependencyTextState dir;
  existingFiles:existingText`files;
  keptMask:not {
    .utl.pathWithinRoot[
      x;
      y;
      .utl.isWindows]
    }[;root] each existingFiles;
  mergedText:`files`deps!(
    (existingFiles where keptMask),incoming`files;
    (existingText[`deps] where keptMask),incoming`deps);
  state:.tst.materializeDependencyTextState[
    mergedText;
    limits];
  .tst.publishDependencyState state
 };

/ Rebuild every requested root off to the side and publish only after all
/ parsing, path resolution, and limit validation succeeds.
rebuildGraph:{[dirs]
  limits:.tst.dependencyLimits[];
  state:.tst.materializeDependencyTextState[
    .tst.buildDependencyTextState dirs;
    limits];
  .tst.publishDependencyState state;
  -1 "Dependency graph built: ",
    string[count key .tst.dependencies],
    " files tracked";
  (::)
 };

dependencyFileText:{[file]
  .tst.dependencyPathText[
    file;
    "Dependency file"]
 };

dependencyRegistryLookup:{[registryKeys;file]
  text:.tst.dependencyFileText file;
  candidateTexts:.utl.pathToString each registryKeys;
  matches:where text~/:candidateTexts;
  if[1<count matches;
    '"Dependency registry contains ambiguous path keys"];
  if[not count matches;
    :`found`value!(0b;`)];
  `found`value!(1b;registryKeys first matches)
 };

/ Iterative traversal avoids recursive stack growth and schedules every graph
/ node at most once. A cycle can still make the starting file its own dependent,
/ preserving the established graph semantics. Pre-seen nodes are emitted when
/ directly referenced but are not traversed, matching getDependentsAcc's
/ historical accumulator contract.
getDependentsWithSeen:{[file;seen]
  limits:.tst.dependencyLimits[];
  seen:.tst.dependencySymbols[
    seen;
    "Dependent traversal seen set"];
  seen:distinct seen;
  if[count[seen]>(limits`walk);
    '"Dependent traversal seen limit exceeded"];
  seenBytes:0j;
  seenIndex:0;
  while[seenIndex<count seen;
    seenBytes+:count .tst.dependencyPathText[
      seen seenIndex;
      "Dependent traversal seen path"];
    if[seenBytes>(limits`pathBytes);
      '"Dependent traversal seen path byte limit exceeded"];
    seenIndex+:1];
  graph:.tst.validateDependencyRegistry[
    .tst.depGraph;
    "Dependency graph";
    limits;
    (limits`files)+(limits`edges)];
  graphKeys:.tst.dependencySymbols[
    key graph;
    "Dependency graph keys"];
  startState:.tst.dependencyRegistryLookup[
    graphKeys;
    file];
  if[not startState`found;
    :`symbol$()];
  start:startState`value;
  if[start in seen;
    :`symbol$()];
  resultCapacity:limits`walk;
  if[resultCapacity<1;
    '"Dependent traversal limit exceeded"];
  / A node can be pending through more than one path before its first
  / expansion. Every graph edge can add at most one such stack entry, so the
  / validated edge count is a strict allocation bound.
  stackCapacity:1j;
  graphIndex:0;
  while[graphIndex<count graphKeys;
    stackCapacity+:count .tst.dependencySymbols[
      graph graphKeys graphIndex;
      "Dependency graph values"];
    graphIndex+:1];
  stack:stackCapacity#enlist `;
  result:resultCapacity#enlist `;
  stack[0]:start;
  stackCount:1;
  resultCount:0;
  expanded:()!();
  emitted:()!();
  while[stackCount>0;
    stackCount-:1;
    current:stack stackCount;
    if[not current in key expanded;
      expanded[current]:1b;
      direct:$[
        current in key graph;
          .tst.dependencySymbols[
            graph current;
            "Dependency graph values"];
        `symbol$()];
      directIndex:0;
      while[directIndex<count direct;
        dependent:direct directIndex;
        if[not dependent in key emitted;
          if[resultCount>=resultCapacity;
            '"Dependent traversal limit exceeded"];
          result[resultCount]:dependent;
          resultCount+:1;
          emitted[dependent]:1b];
        directIndex+:1];
      / Reverse-push after emitting the whole direct list. A node is marked
      / only when expanded, so an earlier depth-first path can take precedence
      / over a copy already pending from a later sibling.
      directIndex:count direct;
      while[directIndex>0;
        directIndex-:1;
        dependent:direct directIndex;
        if[(not dependent in seen) and
           not dependent in key expanded;
          if[stackCount>=stackCapacity;
            '"Dependent traversal stack limit exceeded"];
          stack[stackCount]:dependent;
          stackCount+:1]];
    ];
  ];
  resultCount#result
 };

/ Get all files that transitively depend on a file.
getDependents:{[file]
  .tst.getDependentsWithSeen[
    file;
    `symbol$()]
 };

/ Compatibility helper for callers that supply an initial seen set.
getDependentsAcc:{[file;seen]
  .tst.getDependentsWithSeen[
    file;
    seen]
 };

getDependencies:{[file]
  limits:.tst.dependencyLimits[];
  registry:.tst.validateDependencyRegistry[
    .tst.dependencies;
    "Dependency registry";
    limits;
    limits`files];
  registryKeys:.tst.dependencySymbols[
    key registry;
    "Dependency registry keys"];
  targetState:.tst.dependencyRegistryLookup[
    registryKeys;
    file];
  if[not targetState`found;
    :()];
  result:.tst.dependencySymbols[
    registry targetState`value;
    "Dependency registry values"];
  $[count result;result;()]
 };

\d .
::
