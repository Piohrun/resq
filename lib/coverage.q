/ coverage.q - runtime coverage instrumentation and LCOV/HTML reporting (load-safe)
.utl.require .utl.PKGLOADING,"/static_analysis.q"

/ Preserve coherent instrumentation ownership across an explicit module reload.
.tst.coverageReloadBootstrap:{[]
    names:
        `coverageData`coverageEnabled`trackedFiles`origFuncs`covWrappers,
        `loadingStack;
    present:names in key `.tst;
    if[not any present;
        .tst.coverageData:()!();
        .tst.coverageEnabled:0b;
        .tst.trackedFiles:`symbol$();
        .tst.origFuncs:()!();
        .tst.covWrappers:()!();
        .tst.loadingStack:();
        :`fresh];
    if[not all present;
        '"Coverage lifecycle state is incomplete during module reload"];
    if[(99h<>type .tst.coverageData) or
       (-1h<>type .tst.coverageEnabled) or
       (99h<>type .tst.origFuncs) or
       (99h<>type .tst.covWrappers);
        '"Coverage lifecycle state is invalid during module reload"];
    files:key .tst.coverageData;
    tracked:.tst.trackedFiles;
    originals:key .tst.origFuncs;
    wrappers:key .tst.covWrappers;
    if[(count files) and 11h<>type files;
        '"Coverage file state is invalid during module reload"];
    if[(count tracked) and 11h<>type tracked;
        '"Coverage tracked-file state is invalid during module reload"];
    if[(count originals) and 11h<>type originals;
        '"Coverage original state is invalid during module reload"];
    if[(count wrappers) and 11h<>type wrappers;
        '"Coverage wrapper state is invalid during module reload"];
    if[(any null originals) or
       ((count originals)<>(count distinct originals)) or
       (any null wrappers) or
       ((count wrappers)<>(count distinct wrappers)) or
       not ((asc originals)~asc wrappers);
        '"Coverage instrumentation state is incoherent during module reload"];
    if[(count originals)>65536;
        '"Coverage instrumentation function limit exceeded during module reload"];
    if[count originals;
        if[not all {type[x] within 100 104h} each
              value .tst.origFuncs;
            '"Coverage originals are invalid during module reload"];
        if[not all {type[x] within 100 104h} each
              value .tst.covWrappers;
            '"Coverage wrappers are invalid during module reload"]];
    normalizedData:()!();
    totalFunctions:0j;
    if[count files;
        if[(any null files) or
           ((count files)<>(count distinct files)) or
           4096<count files;
            '"Coverage file state is invalid during module reload"];
        idx:0;
        while[idx<count files;
            file:files idx;
            fileText:string file;
            fileCodes:"i"$fileText;
            if[(not count fileText) or 32768<count fileText or
               any (fileCodes<32) or fileCodes=127;
                '"Coverage file state is invalid during module reload"];
            raw:.tst.coverageData file;
            functionData:$[
                99h=type raw;raw;
                0=count raw;()!();
                1<>count raw;
                  '"Coverage file state is invalid during module reload";
                99h<>type first raw;
                  '"Coverage file state is invalid during module reload";
                first raw];
            functionNames:key functionData;
            if[(count functionNames) and 11h<>type functionNames;
                '"Coverage function state is invalid during module reload"];
            functionNames:`symbol$functionNames;
            if[(any null functionNames) or
               ((count functionNames)<>
                 (count distinct functionNames));
                '"Coverage function state is invalid during module reload"];
            totalFunctions+:count functionNames;
            if[totalFunctions>65536;
                '"Coverage function limit exceeded during module reload"];
            if[count functionNames;
                invalidNames:{
                    text:string x;
                    codes:"i"$text;
                    (not count text) or 512<count text or
                      any (codes<32) or codes=127
                  } each functionNames;
                if[any invalidNames;
                    '"Coverage function state is invalid during module reload"];
                counts:value functionData;
                if[not all {type[x] in -5 -6 -7h} each counts;
                    '"Coverage hit state is invalid during module reload"];
                if[any {(null x) or (x<0) or not (x<0Wj)} each counts;
                    '"Coverage hit state is invalid during module reload"]];
            normalizedData[file]:enlist functionData;
            idx+:1]];
    files:`symbol$files;
    tracked:`symbol$tracked;
    if[(any null tracked) or 4096<count tracked;
        '"Coverage tracked-file state is invalid during module reload"];
    tracked:distinct tracked;
    if[not ((asc files)~asc tracked);
        '"Coverage tracked-file state is incoherent during module reload"];
    stack:.tst.loadingStack;
    if[(count stack) and
       ((0h<>type stack) or not all 10h=type each stack);
        '"Coverage loading state is invalid during module reload"];
    if[(count stack)<>(count distinct stack);
        '"Coverage loading state is invalid during module reload"];
    if[64<count stack;
        '"Coverage loading depth exceeded during module reload"];
    if[count stack;
        if[any {
            codes:"i"$x;
            (not count x) or 32768<count x or
              any (codes<32) or codes=127
          } each stack;
            '"Coverage loading state is invalid during module reload"]];
    .tst.coverageData:normalizedData;
    .tst.trackedFiles:tracked;
    `preserved
 };
.Q.trp[
    .tst.coverageReloadBootstrap;
    ();
    {[err;backtrace]
      ![`.tst;();0b;enlist `coverageReloadBootstrap];
      '"Coverage module bootstrap failed: ",err,"\n",.Q.sbt backtrace}];
![`.tst;();0b;enlist `coverageReloadBootstrap];

.tst._covMissing: `resqCovMissing;
if[not `MAX_COVERAGE_FUNCTIONS in key `.tst;
    .tst.MAX_COVERAGE_FUNCTIONS:65536];
if[not `MAX_COVERAGE_FILES in key `.tst;
    .tst.MAX_COVERAGE_FILES:4096];
if[not `MAX_COVERAGE_REPORT_BYTES in key `.tst;
    .tst.MAX_COVERAGE_REPORT_BYTES:33554432];

/ Functions that must never be wrapped (avoid recursion/self-instrumentation)
.tst.coverageSkipNames: `$(".tst.initCoverage";".tst.initCoverageWith";".tst.normalizeCoverageFiles";".tst.coverageFunctionData";".tst.validateCoverageFileState";".tst.validateCoverageFunctionData";".tst.validateCoverageData";".tst.validateCoverageCounter";".tst.validateCoverageFunctionName";".tst.coverageFileText";".tst.normalizeCoverageFile";".tst.resolveCoverageFile";".tst.validateCoverageInstrumentationState";".tst.coverageSourceMetadata";".tst.coverageReportLimit";".tst.validateCoverageReportSize";".tst.coveragePublishTextWith";".tst.publishCoverageText";".tst.safeValue";".tst.ensureCoverageEntry";".tst.instrumentLoadedFiles";".tst.coverageSysDNamespaces";".tst.coverageQualifyName";".tst.recordExecution";".tst.resolvePath";".tst.wrapFunc";".tst.instrumentFile";".tst.loadSource";".tst.generateLCOV";".tst.generateHTML";".tst.restoreCoverageInstrumentation";".tst.restoreCoverageInstrumentationWith";".tst.coverageHtmlEscape");

/ Helpers
.tst.resolvePath:{[path]
    s:.utl.pathToString path;
    if[not s like "/*"; s: (system "cd"), "/", s];
    .utl.normalizePath s
 };

.tst._covNameStr:{[x]
    if[-11h<>type x;
        '"Coverage function name must be a symbol"];
    string x
 };

.tst._covNumStr:{[x] string `long$x };

.tst.coverageHtmlEscape:{[input]
    text:$[-10h=type input;enlist input;10h=type input;input;string input];
    text:ssr[text;"&";"&amp;"];
    text:ssr[text;"<";"&lt;"];
    text:ssr[text;">";"&gt;"];
    text:ssr[text;"\"";"&quot;"];
    ssr[text;"'";"&#39;"]
 };

.tst.coverageReportLimit:{[]
    .utl.hardLimit[
        .tst.MAX_COVERAGE_REPORT_BYTES;
        33554432;
        "coverage report byte"]
 };

.tst.validateCoverageReportSize:{[content]
    contentType:type content;
    if[(0h=contentType) and
       not all 10h=type each content;
        '"Coverage report content is invalid"];
    size:$[
        10h=contentType;count content;
        0h=contentType;
          $[count content;
            (sum "j"$count each content)+count content;
            0j];
        '"Coverage report content is invalid"];
    if[size>.tst.coverageReportLimit[];
        '"Coverage report byte limit exceeded"];
    size
 };

.tst.coveragePublishTextWith:{
    [attempt;command;quoteForHost;windows;snapshot;toHsym;path;content]
    .tst.validateCoverageReportSize content;
    adapter:snapshot[];
    target:(adapter`inspect) path;
    if[target`exists;
        if[not target[`kind]~`file;
            '"Coverage report target is not a regular file"]];
    outputPath:target`path;
    / Stable per-process target names avoid unbounded symbol growth across
    / repeated coverage runs while still separating concurrent q processes.
    seed:outputPath,string .z.i;
    suffix:raze string md5 "c"$seed;
    tempPath:outputPath,".resq-publish-",suffix;
    tempState:(adapter`inspect) tempPath;
    if[tempState`exists;
        '"Coverage report temporary path collision"];
    written:attempt[
        {[writer;temporary;body]
          (writer temporary)0:body;
          ::};
        (toHsym;tempPath;content)];
    if[not first written;
        @[(adapter`delete);tempPath;{}];
        'last written];
    observed:(adapter`inspect) tempPath;
    if[not observed[`kind]~`file;
        @[(adapter`delete);tempPath;{}];
        '"Coverage report temporary file postcondition failed"];
    sourceArg:quoteForHost[tempPath;windows];
    targetArg:quoteForHost[outputPath;windows];
    moveCommand:$[
        windows;
          "move /Y ",sourceArg," ",targetArg;
        "mv -f ",sourceArg," ",targetArg];
    moved:attempt[command;enlist moveCommand];
    if[not first moved;
        @[(adapter`delete);tempPath;{}];
        '"Coverage report publication failed: ",
          .utl.boundedDiagnostic[last moved;512]];
    published:(adapter`inspect) outputPath;
    if[not published[`kind]~`file;
        '"Coverage report publication postcondition failed"];
    outputPath
 };

.tst.publishCoverageText:{[path;content]
    .tst.coveragePublishTextWith[
        .utl.attempt;
        system;
        .utl.shellQuoteForHost;
        .utl.isWindows;
        .utl.fsSnapshot;
        .utl.pathToHsym;
        path;
        content]
 };

/ Resolve a (possibly dotted, possibly namespaced) name to its value, returning
/ the `.tst._covMissing` sentinel when the name is unbound. The previous walk
/ gated on `nsSym in key \`.`, which is false for dotted CHILD namespaces
/ (e.g. \`.user.create lives under \`.user, not \`.), so it rejected every
/ \`.ns.func and wrapped nothing. A trapped `get` resolves any bound name -
/ root, namespaced, or nested - and the lambda handler keeps the sentinel
/ contract for unbound names. (\`get\` SIGNALS on an unknown name; the trap is
/ mandatory and its handler MUST be a lambda - \`@[f;x;e]\` requires it.)
.tst.safeValue:{[sym] @[get; sym; {[e] .tst._covMissing}] };

.tst.validateCoverageFunctionName:{[name]
    if[(-11h<>type name) or null name;
        '"Coverage function name must be a non-null symbol"];
    text:string name;
    codes:"i"$text;
    if[(not count text) or 512<count text or
       any (codes<32) or codes=127 or
       not all text in
         "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_." ;
        '"Coverage function name is invalid"];
    offset:$["."=first text;1;0];
    parts:"." vs offset _ text;
    if[(not count parts) or any 0=count each parts or
       any (first each parts) in "0123456789";
        '"Coverage function name is invalid"];
    text
 };

.tst.coverageFileText:{[file]
    inputType:type file;
    text:$[
        -11h=inputType;string file;
        10h=inputType;file;
        -10h=inputType;enlist file;
        '"Coverage file must be a string or symbol"];
    codes:"i"$text;
    if[(not count text) or 32768<count text or
       any (codes<32) or codes=127;
        '"Coverage file name is invalid"];
    text
 };

.tst.normalizeCoverageFile:{[file]
    text:.tst.coverageFileText file;
    $[-11h=type file;file;`$text]
 };

.tst.resolveCoverageFile:{[file;files]
    text:.tst.coverageFileText file;
    if[-11h=type file;
        if[file in files;:file]];
    if[-11h<>type file;
        matches:where text~/:string each files;
        if[count matches;:files first matches]];
    limit:.utl.hardLimit[
        .tst.MAX_COVERAGE_FILES;
        4096;
        "coverage file"];
    if[count[files]>=limit;
        '"Coverage file limit exceeded"];
    $[-11h=type file;file;`$text]
 };

.tst.validateCoverageCounter:{[hits]
    if[not type[hits] in -5 -6 -7h;
        '"Coverage hit count must be an integer"];
    if[(null hits) or (hits<0) or not (hits<0Wj);
        '"Coverage hit count is invalid"];
    "j"$hits
 };

.tst.validateCoverageFunctionData:{[functionData]
    if[99h<>type functionData;
        '"Coverage function state is invalid"];
    names:key functionData;
    if[(count names) and 11h<>type names;
        '"Coverage function names are invalid"];
    names:`symbol$names;
    if[(any null names) or
       ((count names)<>(count distinct names));
        '"Coverage function names are invalid"];
    limit:.utl.hardLimit[
        .tst.MAX_COVERAGE_FUNCTIONS;
        65536;
        "coverage function"];
    if[(count names)>limit;
        '"Coverage function limit exceeded"];
    {.tst.validateCoverageFunctionName x} each names;
    names
 };

.tst.coverageFunctionData:{[fileSym]
    raw:.tst.coverageData fileSym;
    if[99h=type raw; :raw];
    if[1<>count raw;
        '"Coverage file entry is invalid"];
    functionData:first raw;
    if[99h<>type functionData;
        '"Coverage file entry is invalid"];
    functionData
 };

.tst.validateCoverageFileState:{[]
    data:.tst.coverageData;
    if[99h<>type data;
        '"Coverage file state is invalid"];
    files:key data;
    if[(count files) and 11h<>type files;
        '"Coverage file names are invalid"];
    files:`symbol$files;
    if[(any null files) or
       ((count files)<>(count distinct files));
        '"Coverage file names are invalid"];
    limit:.utl.hardLimit[
        .tst.MAX_COVERAGE_FILES;
        4096;
        "coverage file"];
    if[(count files)>limit;
        '"Coverage file limit exceeded"];
    if[count files;
        {.tst.normalizeCoverageFile x} each files;
        {.tst.coverageFunctionData x} each files];
    tracked:.tst.trackedFiles;
    if[(count tracked) and 11h<>type tracked;
        '"Coverage tracked-file state is invalid"];
    tracked:`symbol$tracked;
    if[(any null tracked) or
       ((count tracked)<>(count distinct tracked)) or
       (count tracked)>limit;
        '"Coverage tracked-file state is invalid"];
    if[not ((asc files)~asc tracked);
        '"Coverage tracked-file state is incoherent"];
    files
 };

.tst.validateCoverageData:{[]
    if[-1h<>type .tst.coverageEnabled;
        '"Coverage enabled state is invalid"];
    files:.tst.validateCoverageFileState[];
    limit:.utl.hardLimit[
        .tst.MAX_COVERAGE_FUNCTIONS;
        65536;
        "coverage function"];
    total:0j;
    idx:0;
    while[idx<count files;
        functionData:.tst.coverageFunctionData files idx;
        names:.tst.validateCoverageFunctionData functionData;
        total+:count names;
        if[total>limit;
            '"Coverage function limit exceeded"];
        {.tst.validateCoverageCounter x} each value functionData;
        idx+:1];
    files
 };

.tst.ensureCoverageEntry:{[file]
    files:.tst.validateCoverageFileState[];
    fileSym:.tst.resolveCoverageFile[file;files];
    if[fileSym in files; :()];
    limit:.utl.hardLimit[
        .tst.MAX_COVERAGE_FILES;
        4096;
        "coverage file"];
    if[count[files]>=limit;
        '"Coverage file limit exceeded"];
    beforeData:.tst.coverageData;
    beforeTracked:.tst.trackedFiles;
    added:.utl.attempt[
        {[target]
          .tst.coverageData[target]:enlist (()!());
          .tst.trackedFiles,:target;
          .tst.validateCoverageFileState[];
          ::};
        enlist fileSym];
    if[not first added;
        .tst.coverageData:beforeData;
        .tst.trackedFiles:beforeTracked;
        'last added];
    ::
 };

/ Record execution (called by wrappers)
.tst.recordExecution:{[file;funcName]
    if[-1h<>type .tst.coverageEnabled;
        '"Coverage enabled state is invalid"];
    if[not .tst.coverageEnabled; :()];

    .tst.validateCoverageFunctionName funcName;
    files:.tst.validateCoverageFileState[];
    fileSym:.tst.resolveCoverageFile[file;files];
    exists:fileSym in files;
    functionData:$[exists;.tst.coverageFunctionData[fileSym];()!()];
    names:.tst.validateCoverageFunctionData functionData;

    if[funcName in names;
        current:.tst.validateCoverageCounter functionData funcName;
        if[not current<0Wj-1;
            '"Coverage hit count limit exceeded"];
        recorded:.utl.attempt[
            {[target;name;nextCount]
              rawEntry:.tst.coverageData target;
              if[99h=type rawEntry;
                  .tst.coverageData[target;name]:nextCount];
              if[99h<>type rawEntry;
                  .tst.coverageData[target;0;name]:nextCount];
              observed:
                (.tst.coverageFunctionData target)name;
              if[not observed~nextCount;
                  '"Coverage counter postcondition failed"];
              ::};
            (fileSym;funcName;current+1j)];
        if[not first recorded;'last recorded];
        :()];

    limit:.utl.hardLimit[
        .tst.MAX_COVERAGE_FUNCTIONS;
        65536;
        "coverage function"];
    counts:{count key .tst.coverageFunctionData x} each files;
    total:$[count counts;sum "j"$counts;0j];
    if[total>limit;
        '"Coverage function limit exceeded"];
    if[total>=limit;
        '"Coverage function limit exceeded"];

    if[exists;
        beforeFunctions:functionData;
        recorded:.utl.attempt[
            {[target;name;currentFunctions]
              updatedFunctions:currentFunctions;
              updatedFunctions[name]:1j;
              .tst.coverageData[target]:enlist updatedFunctions;
              .tst.validateCoverageFunctionData
                .tst.coverageFunctionData target;
              ::};
            (fileSym;funcName;functionData)];
        if[not first recorded;
            .tst.coverageData[fileSym]:enlist beforeFunctions;
            'last recorded];
        :()];

    fileLimit:.utl.hardLimit[
        .tst.MAX_COVERAGE_FILES;
        4096;
        "coverage file"];
    if[count[files]>=fileLimit;
        '"Coverage file limit exceeded"];
    beforeData:.tst.coverageData;
    beforeTracked:.tst.trackedFiles;
    recorded:.utl.attempt[
        {[target;name]
          .tst.coverageData[target]:
            enlist ((enlist name)!enlist 1j);
          .tst.trackedFiles,:target;
          .tst.validateCoverageFileState[];
          ::};
        (fileSym;funcName)];
    if[not first recorded;
        .tst.coverageData:beforeData;
        .tst.trackedFiles:beforeTracked;
        'last recorded];
    ::
 };

/ @param name (symbol) Function name (e.g. `.user.create`)
/ @param fileSym (symbol) Source file symbol
.tst.wrapFunc:{[name;fileSym]
    if[(-11h<>type fileSym) or null fileSym;
        '"Coverage file name must be a non-null symbol"];
    nameText:.tst.validateCoverageFunctionName name;
    pathText:.tst.coverageFileText fileSym;
    tracked:.tst.validateCoverageInstrumentationState[];

    / Skip coverage internals.
    if[(name in .tst.coverageSkipNames) or
       nameText like ".tst.coverage*" or
       nameText like ".tst._cov*";
        :()];

    / Already-wrapped guard, RELOAD-AWARE. The old guard skipped on mere name
    / membership in .tst.origFuncs, so after a file reload (which installs a
    / fresh UNWRAPPED definition) re-instrumenting was a no-op: the name was
    / still registered, the live function stayed unwrapped, and hits were zero.
    / Instead compare the LIVE value to the wrapper we installed (kept in
    / covWrappers). `~` on lambdas is structural and each wrapper embeds its own
    / name, so wrappers for different names differ - a true identity test.
    /   - live value IS our wrapper  -> already instrumented, skip.
    /   - name registered but live value differs (reload) -> fall through,
    /     re-capture the fresh live value as orig below, and re-wrap.
    if[name in key .tst.covWrappers;
        if[(.tst.safeValue name) ~ .tst.covWrappers name; :()];
    ];

    orig: .tst.safeValue name;
    if[orig ~ .tst._covMissing; :()];
    if[not type[orig] within (100h;104h); :()];
    if[(not name in tracked) and
       count[tracked]>=.utl.hardLimit[
          .tst.MAX_COVERAGE_FUNCTIONS;
          65536;
          "coverage function"];
        '"Coverage instrumentation function limit exceeded"];

    / Introspect the original to recover its argument names so the wrapper can
    / forward them positionally. `value[f] 1` resolves BOTH explicit ({[x;y]..})
    / and implicit ({x+y} -> `x`y) lambdas to their canonical arg names, so the
    / rebuilt {[x;y] ...} preserves the original rank and call semantics. But it
    / SIGNALS 'type for compiled operators/derived functions (102h/103h), which
    / pass the type guard above; trap it and skip rather than crash. The handler
    / must be a lambda (q's @[f;x;e] requires it).
    args: @[{value[x] 1}; orig; {(::)}];
    if[args ~ (::); :()];

    argStr: $[0 < count args; ";" sv string args; ""];
    callArgs: "[", argStr, "]";

    / The recorded file key MUST equal the symbol ensureCoverageEntry / the LCOV
    / writer use (\`$absPath, NO ":" prefix). recordExecution does `\`$file` for a
    / string arg, so embed the path as an ESCAPED STRING LITERAL and let it
    / symbol-ize - identical to \`$absPath. A backtick-symbol literal can't be
    / used here: a path starts with "/", and `\`/tmp/x` does not parse as a
    / symbol. (The previous code wrote `hsym "..."`, producing \`:absPath, so
    / hits landed under a key the report never read - always-empty coverage.)
    pathLit:"\"",ssr[ssr[pathText;"\\";"\\\\"];"\"";"\\\""],"\"";
    nameLit:"`",nameText;
    wrapperCode: raze ("{"; callArgs;
        " .tst.recordExecution[";pathLit;";";nameLit;"];";
        " (.tst.origFuncs[";nameLit;"])";callArgs;
        " }");

    / Parse the wrapper text; a failure here (exotic arg names, etc.) must leave
    / the original definition untouched, so trap it and bail.
    wrapFn: @[value; wrapperCode; {(::)}];
    if[wrapFn ~ (::); :()];

    beforeOriginals:.tst.origFuncs;
    beforeWrappers:.tst.covWrappers;
    installed:.utl.attempt[
        {[target;wrapper]
          target set wrapper;
          if[not (get target)~wrapper;
            '"coverage wrapper postcondition failed"];
          ::};
        (name;wrapFn)];
    if[not first installed;
        rolledBack:.utl.attempt[
            {[target;original]
              target set original;
              if[not (get target)~original;
                '"coverage rollback postcondition failed"];
              ::};
            (name;orig)];
        if[not first rolledBack;
            '"Coverage wrapper installation and rollback failed for ",
              string name];
        '"Coverage wrapper installation failed for ",string name,": ",
          .utl.boundedDiagnostic[last installed;512]];
    published:.utl.attempt[
        {[target;original;wrapper]
          .tst.origFuncs[target]:original;
          .tst.covWrappers[target]:wrapper;
          .tst.validateCoverageInstrumentationState[];
          ::};
        (name;orig;wrapFn)];
    if[not first published;
        .tst.origFuncs:beforeOriginals;
        .tst.covWrappers:beforeWrappers;
        rolledBack:.utl.attempt[
            {[target;original]
              target set original;
              if[not (get target)~original;
                '"coverage rollback postcondition failed"];
              ::};
            (name;orig)];
        if[not first rolledBack;
            '"Coverage wrapper publication and rollback failed for ",
              string name];
        '"Coverage wrapper publication failed for ",string name,": ",
          .utl.boundedDiagnostic[last published;512]];
    ::
 };

/ Instrument a loaded file (analyze and wrap functions)
/ @param pathStr (string) Absolute normalized path
.tst.instrumentFile:{[pathStr]
    if[-1h<>type .tst.coverageEnabled;
        '"Coverage enabled state is invalid"];
    if[not .tst.coverageEnabled; :()];

    absPath: .tst.resolvePath pathStr;
    
    / Apply --cov-include / --cov-exclude filters.
    if[`coverageInclude in key `.tst.app;
        if[0 < count .tst.app.coverageInclude;
            if[not any absPath like/: .tst.app.coverageInclude; :()]
        ]
    ];
    if[`coverageExclude in key `.tst.app;
        if[any absPath like/: .tst.app.coverageExclude; :()]
    ];
    
    fileSym:`$absPath;
    metadata:.tst.coverageSourceMetadata fileSym;
    .tst.ensureCoverageEntry[fileSym];
    fns:metadata`functions;
    if[0=count fns; :()];

    / exploreFile applies `\d <ns>` namespacing, but NOT the runtime
    / `system "d <ns>"` form some sources use to open a namespace - those
    / functions are returned BARE (e.g. `create` for a fn that actually loaded
    / as `.user.create`), so wrapping the bare name finds nothing. Re-derive the
    / runtime-`d` namespace active at each function's line and qualify any bare
    / name accordingly, so the wrapped (and recorded) name matches the loaded
    / definition and the LCOV report. Names exploreFile already qualified (`.*`)
    / are left as-is.
    nsAt:metadata`namespaces;
    {[fs;nsAt;row]
        nm: row`name;
        nm: .tst.coverageQualifyName[nsAt; row`line; nm];
        .tst.wrapFunc[nm; fs]
    }[fileSym; nsAt] each fns;
 };

/ Build a per-line active-namespace vector from a file's `system "d <ns>"`
/ directives (the runtime equivalent of `\d <ns>`). Returns a list of strings,
/ one per source line, giving the namespace string ("" at root, ".user", ...)
/ in effect ON that line. `system "d ."` / `system "d \`."` resets to root.
.tst.coverageSysDNamespaces:{[lines]
    {[acc;ln]
        cur: last acc;
        t: trim ln;
        / Match a `system "d <ns>"` directive and pull <ns> from between the two
        / double-quotes. "d ." / "d `." reset to root.
        if[t like "system \"d *";
            q1: t ? "\"";
            rest: (q1+1) _ t;
            q2: rest ? "\"";
            arg: trim q2 # rest;                / e.g. "d .user"
            if[arg like "d *";
                ns: trim 2 _ arg;
                ns: $[ns like "`*"; 1 _ ns; ns]; / tolerate `.user spelling
                cur: $[(ns ~ ".") or (0 = count ns); ""; ns];
            ];
        ];
        acc, enlist cur
    }/[enlist ""; lines]
 };

/ Qualify a bare function name with the runtime-`d` namespace active at `line`
/ (1-based, as exploreFile reports). Already-dotted names pass through.
.tst.coverageQualifyName:{[nsAt;line;name]
    s: string name;
    if[s like ".*"; :name];                 / already namespaced
    idx: line - 1;                          / nsAt is 0-based per source line
    if[(idx < 0) or idx >= count nsAt; :name];
    ns: nsAt idx;
    if[0 = count ns; :name];
    `$ns, ".", s
 };

.tst.coverageSourceMetadata:{[fileSym]
    pathStr:string fileSym;
    if[pathStr like ":*";pathStr:1 _ pathStr];
    adapter:.utl.fsSnapshot[];
    sourceBefore:(adapter`readRegular)[pathStr;33554432];
    sourceHandle:.utl.pathToHsym sourceBefore`path;
    explored:.utl.attempt[
        .tst.static.exploreFile;
        enlist sourceHandle];
    if[not first explored;
        '"Unable to inspect coverage source: ",
          .utl.boundedDiagnostic[last explored;512]];
    functions:last explored;
    if[98h<>type functions;
        '"Coverage source function state is invalid"];
    required:`name`line;
    if[not all required in cols functions;
        '"Coverage source function state is invalid"];
    if[(count functions)>.utl.hardLimit[
          .tst.MAX_COVERAGE_FUNCTIONS;
          65536;
          "coverage function"];
        '"Coverage source function limit exceeded"];
    names:exec name from functions;
    lines:exec line from functions;
    if[(count names) and 11h<>type names;
        '"Coverage source function names are invalid"];
    if[(count lines) and not type[lines] in 5 6 7h;
        '"Coverage source function lines are invalid"];
    {.tst.validateCoverageFunctionName x} each names;
    if[count lines;
        if[(any null lines) or any lines<1;
            '"Coverage source function lines are invalid"]];
    sourceLines:.utl.textLinesBounded[sourceBefore`bytes;65536];
    namespaces:.tst.coverageSysDNamespaces sourceLines;
    sourceAfter:(adapter`readRegular)[sourceBefore`path;33554432];
    if[not sourceAfter[`identity]~sourceBefore`identity;
        '"Coverage source changed during report generation"];
    `path`functions`namespaces!(
        sourceBefore`path;functions;namespaces)
 };

/ Load through the hardened native adapter: regular-file and identity checks run
/ before and after execution, unsupported whitespace fails closed, and both CWD
/ and namespace are restored on success and failure.
.tst.coverageLoadFile:{[pathStr]
    adapter:.utl.fsSnapshot[];
    snapshot:(adapter`readRegular)[pathStr;33554432];
    (adapter`loadNative)[snapshot`path;snapshot`identity];
    ::
 };

/ Load and instrument a source file explicitly
.tst.loadSource:{[file]
    pathStr: .tst.resolvePath file;

    stackBefore:.tst.loadingStack;
    if[(count stackBefore) and
       ((0h<>type stackBefore) or not all 10h=type each stackBefore);
        '"Coverage loading state is invalid"];
    if[(count stackBefore)<>(count distinct stackBefore);
        '"Coverage loading state is invalid"];
    if[count stackBefore;
        if[any {
            codes:"i"$x;
            (not count x) or 32768<count x or
              any (codes<32) or codes=127
          } each stackBefore;
            '"Coverage loading state is invalid"]];
    if[64<=count stackBefore;'"Coverage loading depth exceeded"];
    if[pathStr in stackBefore; :()];
    .tst.loadingStack:stackBefore,enlist pathStr;
    outcome:.utl.attempt[
        {[path].tst.coverageLoadFile path;.tst.instrumentFile path;::};
        enlist pathStr];
    .tst.loadingStack:stackBefore;
    if[not first outcome;'last outcome];
    ::
 };

/ Instrument already-loaded .q files once coverage is enabled
.tst.instrumentLoadedFiles:{[]
    if[not `utl in key `.; :()];
    if[not `loaded in key `.utl; :()];

    loaded: .utl.loaded;
    if[0 = count loaded; :()];

    files: loaded where (loaded like "*.q") and not loaded like "*coverage.q";
    files: files where 0 < count each files;

    { .tst.instrumentFile .tst.resolvePath x } each files;
 };

.tst.validateCoverageInstrumentationState:{[]
    originals:.tst.origFuncs;
    wrappers:.tst.covWrappers;
    if[(99h<>type originals) or 99h<>type wrappers;
        '"Coverage instrumentation state is invalid"];
    names:key originals;
    wrapperNames:key wrappers;
    if[(count names) and 11h<>type names;
        '"Coverage instrumentation names are invalid"];
    if[(count wrapperNames) and 11h<>type wrapperNames;
        '"Coverage wrapper names are invalid"];
    limit:.utl.hardLimit[
        .tst.MAX_COVERAGE_FUNCTIONS;
        65536;
        "coverage function"];
    if[(count names)>limit;
        '"Coverage instrumentation function limit exceeded"];
    if[(any null names) or
       ((count names)<>(count distinct names)) or
       (any null wrapperNames) or
       ((count wrapperNames)<>(count distinct wrapperNames));
        '"Coverage instrumentation names are invalid"];
    if[not ((asc names)~asc wrapperNames);
        '"Coverage instrumentation state is incoherent"];
    if[count names;
        if[not all {type[x] within 100 104h} each value originals;
            '"Coverage originals are invalid"];
        if[not all {type[x] within 100 104h} each value wrappers;
            '"Coverage wrappers are invalid"]];
    names
 };

/ Restore only wrappers still owned by the coverage runtime. Caller replacements
/ are preserved, successful entries are retired, and failed entries remain
/ registered so cleanup can be retried.
.tst.restoreCoverageInstrumentationWith:{[setter;reader;missing;tag]
    if[not `coverageRestoreV1~tag;
        '"Coverage restore capsule is invalid"];
    .tst.coverageEnabled:0b;
    originals:.tst.origFuncs;
    wrappers:.tst.covWrappers;
    names:.tst.validateCoverageInstrumentationState[];
    restored:count[names]#0b;
    failures:0;
    idx:0;
    while[idx<count names;
        name:names idx;
        current:reader name;
        success:0b;
        if[current~missing;success:1b];
        if[not current~missing;
            compared:.[
                {[left;right] (`ok;left~right)};
                (current;wrappers name);
                {[err] (`error;err)}];
            if[`ok~first compared;
                if[not first last compared;success:1b];
                if[first last compared;
                    installed:.[
                        {[setValue;target;original]
                            setValue[target;original];
                            `ok};
                        (setter;name;originals name);
                        {[err] (`error;err)}];
                    if[`ok~first installed;
                        observed:reader name;
                        verified:.[
                            {[left;right]left~right};
                            (observed;originals name);
                            {[err]0b}];
                        if[verified;success:1b]]]]];
        restored[idx]:success;
        if[not success;failures+:1];
        idx+:1];
    completed:names where restored;
    if[count completed;
        .tst.origFuncs:![originals;();0b;completed];
        .tst.covWrappers:![wrappers;();0b;completed]];
    if[failures;
        '"Coverage instrumentation restore failed for ",
            string[failures]," function(s)"];
    1b
 };

.tst.restoreCoverageInstrumentation:('[
    .tst.restoreCoverageInstrumentationWith[
        .tst.mockPrimitives`set;
        .tst.safeValue;
        .tst._covMissing;];
    {[]`coverageRestoreV1}]);

.tst.normalizeCoverageFiles:{[files]
    t:type files;
    raw:$[
        10h=t;enlist files;
        -10h=t;enlist enlist files;
        -11h=t;enlist files;
        11h=t;files;
        0h=t;files;
        '"Coverage files must be strings or symbols"];
    if[not count raw;:`symbol$()];
    limit:.utl.hardLimit[
        .tst.MAX_COVERAGE_FILES;
        4096;
        "coverage file"];
    if[(count raw)>limit;
        '"Coverage file limit exceeded"];
    normalized:{.tst.normalizeCoverageFile x} each raw;
    if[11h<>type normalized;
        '"Coverage files must be strings or symbols"];
    if[(any null normalized) or
       ((count normalized)<>(count distinct normalized));
        '"Coverage files must be non-null and unique"];
    normalized
 };

/ Reinitialization first retires any prior owned wrappers. Partial failures are
/ unwound before the error is returned, so a rerun cannot strand instrumentation.
.tst.initCoverageWith:{[restore;instrument;files]
    fs:.tst.normalizeCoverageFiles files;
    .tst.validateCoverageInstrumentationState[];
    retired:.utl.attempt[restore;()];
    if[not first retired;'last retired];
    .tst.trackedFiles:`symbol$();
    .tst.coverageData:()!();
    .tst.origFuncs:()!();
    .tst.covWrappers:()!();
    .tst.loadingStack:();
    .tst.coverageEnabled:1b;
    initialized:.utl.attempt[
        {[initialFiles;instrumenter]
          {[file].tst.ensureCoverageEntry file} each initialFiles;
          instrumenter[];
          ::};
        (fs;instrument)];
    if[not first initialized;
        cleanup:.utl.attempt[restore;()];
        .tst.coverageEnabled:0b;
        .tst.coverageData:()!();
        .tst.trackedFiles:`symbol$();
        .tst.loadingStack:();
        if[not first cleanup;
            '"Coverage initialization failed: ",
              .utl.boundedDiagnostic[last initialized;512],
              "; cleanup failed: ",
              .utl.boundedDiagnostic[last cleanup;512]];
        'last initialized];
    -1 "Coverage tracking initialized.";
    ::
 };

.tst.initCoverage:.tst.initCoverageWith[
    .tst.restoreCoverageInstrumentation;
    .tst.instrumentLoadedFiles;];

/ Generate LCOV Report
.tst.generateLCOV:{[outFile]
    if[not .tst.coverageEnabled; '"Coverage not enabled"];
    files:.tst.validateCoverageData[];

    outPath: .tst.resolvePath outFile;

    / Ultra-defensive LCOV writer: avoid adverbs and build line-by-line.
    txtParts:enlist "TN:resq\n";
    sourceFunctionTotal:0j;
    i: 0;
    do[count files;
        fileSym: files i;
        metadata:.tst.coverageSourceMetadata fileSym;
        pathStr:metadata`path;
        fData:.tst.coverageFunctionData fileSym;
        fns:metadata`functions;

        / exploreFile reports BARE names for functions opened with a runtime
        / `system "d <ns>"` (it only honours `\d`); hits, however, were recorded
        / under the QUALIFIED name (see instrumentFile). Re-derive the same
        / namespace map so the FN:/FNDA: lines and the hit lookup use the loaded
        / name, otherwise every FNDA stays 0 for system-`d` modules.
        nsAt:metadata`namespaces;

        sfLine: "SF:";
        sfLine,: pathStr;
        sfLine,: "\n";
        txtParts,:enlist sfLine;

        fnCount: count fns;
        sourceFunctionTotal+:fnCount;
        if[sourceFunctionTotal>.utl.hardLimit[
              .tst.MAX_COVERAGE_FUNCTIONS;
              65536;
              "coverage function"];
            '"Coverage source function limit exceeded"];
        hitFn: 0;
        j: 0;
        do[fnCount;
            row: fns j;
            nm: .tst.coverageQualifyName[nsAt; row`line; row`name];
            .tst.validateCoverageFunctionName nm;
            ln: row`line;

            hit: 0;
            if[nm in key fData; hit: fData[nm]];
            if[hit > 0; hitFn+: 1];

            nmStr: .tst._covNameStr nm;
            lnStr: .tst._covNumStr ln;
            hitStr: .tst._covNumStr hit;

            fnLine: "FN:";
            fnLine,: lnStr;
            fnLine,: ",";
            fnLine,: nmStr;
            fnLine,: "\n";

            fndaLine: "FNDA:";
            fndaLine,: hitStr;
            fndaLine,: ",";
            fndaLine,: nmStr;
            fndaLine,: "\n";

            txtParts,:(fnLine;fndaLine);

            j+: 1;
        ];

        fnfLine: "FNF:";
        fnfLine,: .tst._covNumStr fnCount;
        fnfLine,: "\n";

        fnhLine: "FNH:";
        fnhLine,: .tst._covNumStr hitFn;
        fnhLine,: "\n";

        txtParts,:(fnfLine;fnhLine;"end_of_record\n");
        .tst.validateCoverageReportSize txtParts;

        i+: 1;
    ];

    / Persist raw coverage state alongside the LCOV file.
    idx: (count outPath) - (reverse outPath) ? "/";
    dir: $[idx=0; "."; idx # outPath];
    stateFile: dir, "/coverage_state.txt";
    if[outPath~stateFile;
        '"LCOV output path collides with coverage state path"];
    / Persist the FULL coverage dict, one "file func count" line per record.
    / `-3!` of the whole dict was truncated by q's display width ("..."), losing
    / data; an explicit per-entry dump is complete and grep-friendly.
    stateLines: ();
    sf: 0;
    do[count files;
        fsym: files sf;
        fpath: string fsym;
        if[fpath like ":*"; fpath: 1 _ fpath];
        fd:.tst.coverageFunctionData fsym;
        fnames: key fd;
        k: 0;
        do[count fnames;
            stateLines,: enlist fpath, " ", (.tst._covNameStr fnames k), " ", .tst._covNumStr fd fnames k;
            k+: 1;
        ];
        sf+: 1;
    ];
    .tst.validateCoverageReportSize stateLines;
    .tst.publishCoverageText[stateFile;stateLines];

    txt:raze txtParts;
    .tst.validateCoverageReportSize txt;
    .tst.publishCoverageText[outPath;enlist txt];
    -1 "LCOV report written to: ", outPath;
    outPath
 };

/ Generate a simple HTML summary
.tst.generateHTML:{[outFile]
    if[not .tst.coverageEnabled; '"Coverage not enabled"];
    files:.tst.validateCoverageData[];

    outPath: .tst.resolvePath outFile;

    htmlParts:(
      "<!DOCTYPE html><html><head><title>resQ Coverage</title></head><body>";
      "<h1>resQ Coverage</h1>");

    / Render a real per-file table of functions and their hit counts (covered =
    / hits>0, otherwise uncovered) rather than a placeholder. Names and lookups
    / use the same `system "d"`/`\d` qualification as the LCOV writer.
    sourceFunctionTotal:0j;
    f: 0;
    do[count files;
        fileSym: files f;
        metadata:.tst.coverageSourceMetadata fileSym;
        pathStr:metadata`path;
        fData:.tst.coverageFunctionData fileSym;
        fns:metadata`functions;
        nsAt:metadata`namespaces;
        sourceFunctionTotal+:count fns;
        if[sourceFunctionTotal>.utl.hardLimit[
              .tst.MAX_COVERAGE_FUNCTIONS;
              65536;
              "coverage function"];
            '"Coverage source function limit exceeded"];

        covered: 0;
        rowsHtml:();
        j: 0;
        do[count fns;
            row: fns j;
            nm: .tst.coverageQualifyName[nsAt; row`line; row`name];
            .tst.validateCoverageFunctionName nm;
            hit: $[nm in key fData; fData[nm]; 0];
            if[hit > 0; covered+: 1];
            cls: $[hit > 0; "covered"; "uncovered"];
            rowsHtml,:enlist (
              "<tr class=\"",cls,"\"><td>",
              (.tst.coverageHtmlEscape .tst._covNameStr nm),
              "</td><td>",(.tst._covNumStr row`line),
              "</td><td>",(.tst._covNumStr hit),"</td></tr>");
            j+: 1;
        ];

        htmlParts,:enlist (
          "<h2>",(.tst.coverageHtmlEscape pathStr),"</h2>");
        htmlParts,:enlist (
          "<p>",(.tst._covNumStr covered),
          " / ",(.tst._covNumStr count fns),
          " functions covered</p>");
        htmlParts,:enlist
          "<table border=\"1\"><thead><tr><th>Function</th><th>Line</th><th>Hits</th></tr></thead><tbody>";
        htmlParts,:rowsHtml;
        htmlParts,:enlist "</tbody></table>";
        .tst.validateCoverageReportSize htmlParts;
        f+: 1;
    ];

    htmlParts,:(
      "<p>Raw coverage state written to coverage_state.txt</p>";
      "</body></html>");
    .tst.validateCoverageReportSize htmlParts;
    html:raze htmlParts;
    .tst.validateCoverageReportSize html;
    .tst.publishCoverageText[outPath;enlist html];
    -1 "HTML report written to: ", outPath;
    outPath
 };
