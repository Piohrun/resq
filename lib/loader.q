/ Bounded script evaluation and deterministic test discovery.
.tst.MAX_TEST_SOURCE_BYTES:16777216;
.tst.MAX_TEST_FILES:4096;
.tst.MAX_TEST_PATH_BYTES:4194304;
.tst.MAX_DISCOVERY_DEPTH:64;
.tst.MAX_DISCOVERY_ENTRIES:16384;
.tst.MAX_DISCOVERY_BYTES:16777216;
.tst.MAX_SPECS:10000;
.tst.MAX_TEST_SOURCE_LINES:65536;
.tst.MAX_TEST_STATEMENTS:65536;

.tst.rstrip:{[input]
    text:.utl.pathToString input; keep:where not text in " \t";
    $[count keep;(1+last keep)#text;""]};
.tst.lstrip:{[input]
    text:.utl.pathToString input; keep:where not text in " \t"; $[count keep;(first keep)_text;""]};

.tst.sysl:{[path]
    absolute:.utl.absolutePath path; enabled:1b~@[get;`.tst.coverageEnabled;0b]; instrument:$[
        enabled and `instrumentFile in key `.tst; .tst.instrumentFile;
        (::)]; loader:(.utl.fsSnapshot[])`loadPath;
    loader absolute; if[.tst.isCallable instrument;
        @[instrument;absolute;{[p;e]
            -1 "Coverage: could not instrument ",p,": ",
              .utl.boundedDiagnostic[e;512]}[absolute]]]; (::)};

.tst.rewriteSystemLoad:{[line]
    left:.tst.lstrip line; prefix:"system \"l \", ";
    if[not left like prefix,"*";:line]; right:.tst.rstrip left;
    if[(0=count right) or not ";"=last right;:line]; indent:(count line)-count left;
    expression:-1 _ (count prefix)_right; (indent#line),".tst.sysl (",expression,");"};

.tst.preprocessScript:{[input]
    lines:.utl.pathToString each input; rewrite:.tst.rewriteSystemLoad;
    n:count lines; if[n>.utl.hardLimit[
        .tst.MAX_TEST_SOURCE_LINES;65536;"test source line"]; '"Test source line limit exceeded"];
    output:n#enlist ""; used:0;
    inBlock:0b; stopped:0b; i:0; while[(i<n) and not stopped;
        line:lines i; trimmed:.tst.rstrip line; $[inBlock;
            if[trimmed~enlist "\\";inBlock:0b]; trimmed~enlist "/";
            inBlock:1b; (count line) and "\\"=first line;
            $[trimmed~enlist "\\";
                stopped:1b; [body:1_line;
                 escaped:ssr[ssr[body;"\\";"\\\\"];"\"";"\\\""]; $[(body~"l") or body like "l *";
                    [arg:$[body~"l";"";trim 2_body];
                     arg:ssr[ssr[arg;"\\";"\\\\"];"\"";"\\\""];
                     output[used]:".tst.sysl \"",arg,"\";"];
                    output[used]:"system \"",escaped,"\";"]; used+:1]];
            [output[used]:rewrite line;used+:1]]; i+:1];
    used#output};

.tst.bracketDelta:{[line]
    text:.utl.pathToString line; quoted:0b; delta:0; i:0;
    while[i<count text;
        char:text i; $[quoted;
            $[char="\\";i+:1;char="\"";quoted:0b;::]; char="\"";quoted:1b;
          char in "{([";delta+:1; char in "})]";delta-:1;
          ::]; i+:1]; delta};

/ Statements are represented as source spans, so grouping is linear even for
/ one very large multiline expression.
.tst.groupStatements:{[input]
    lines:.utl.pathToString each input; n:count lines; if[n>.utl.hardLimit[
        .tst.MAX_TEST_SOURCE_LINES;65536;"test source line"]; '"Test source line limit exceeded"];
    statementLimit:.utl.hardLimit[
        .tst.MAX_TEST_STATEMENTS;65536;"test statement"]; starts:n#0; ends:n#0; groups:0;
    active:0b; depth:0; i:0; while[i<n;
        line:lines i; blank:0=count .tst.rstrip line;
        indented:(count line) and first[line] in " \t"; if[(not blank) and
           ((not active) or ((0=depth) and not indented));
            if[active;ends[groups-1]:i-1]; if[groups>=statementLimit;
                '"Test statement limit exceeded"]; starts[groups]:i; groups+:1; active:1b];
        if[active;ends[groups-1]:i]; depth+: .tst.bracketDelta line; if[depth<0;depth:0]; i+:1];
    result:groups#enlist (0;()); i:0; while[i<groups;
        span:(starts i)+til 1+ends[i]-starts i; result[i]:(1+starts i;lines span); i+:1]; result};

.tst.evalPreprocessed:{[input]
    lines:input where not {
        left:.tst.lstrip x; (count left) and "/"=first left} each input;
    statements:.tst.groupStatements lines; i:0;
    while[i<count statements;
        value "\n" sv statements[i;1]; i+:1]; (::)};

.tst.localizeSyntaxError:{[content]
    statements:.tst.groupStatements content; i:0; while[i<count statements;
        prepared:@[.tst.preprocessScript;statements[i;1];{()}]; joined:"\n" sv prepared;
        left:.tst.lstrip joined; if[count left;
            if[not ((left like "system \"*") or left like ".tst.sysl*");
                if[not @[{parse x;1b};joined;{0b}];
                    :statements[i;0]]]]; i+:1]; 0N};

.tst.walkFiles:{[suffix;roots;adapter]
    attempt:.utl.attempt;
    diagnostic:.utl.boundedDiagnostic;
    withinFn:.utl.pathWithinRoot;
    windows:.utl.isWindows;
    stableDirectory:{[try;inspectFn;withinOp;hostWindows;p;expected]
        outcome:try[inspectFn;enlist p];
        if[not first outcome;:0b];
        state:last outcome;
        if[(not 99h=type state) or
           not all `path`exists`kind`identity in key state;
            :0b];
        if[(not state`exists) or
           (not state[`kind]~`dir) or
           not (10h=type state`identity);
            :0b];
        same:{[inside;windowsFlag;a;b]
            inside[a;b;windowsFlag] and
              inside[b;a;windowsFlag]};
        same[withinOp;hostWindows;state`identity;expected] and
          same[withinOp;hostWindows;state`identity;state`path]};
    entryLimit:.utl.hardLimit[
        .tst.MAX_DISCOVERY_ENTRIES;16384;"discovery entry"]; depthLimit:.utl.hardLimit[
        .tst.MAX_DISCOVERY_DEPTH;64;"discovery depth"]; byteLimit:.utl.hardLimit[
        .tst.MAX_DISCOVERY_BYTES;16777216;"discovery byte"];
    rootList:$[10h=type roots;enlist roots;roots];
    if[count[rootList]>entryLimit;'"Discovery root limit exceeded"];
    capacity:entryLimit+(count rootList)+1;
    queue:capacity#enlist "";
    depths:capacity#0;
    parents:capacity#enlist "";
    parentIds:capacity#enlist "";
    queue[til count rootList]:rootList;
    head:0;
    tail:count rootList; files:capacity#enlist ""; fileCount:0; identities:capacity#enlist "";
    identityCount:0; consumed:0; problems:8#enlist ""; failureCount:0;
    while[head<tail;
        path:queue head;
        depth:depths head;
        parent:parents head;
        parentIdentity:parentIds head;
        head+:1;
        eligible:$[
            count parent;
            stableDirectory[
                attempt;adapter`inspect;withinFn;windows;
                parent;parentIdentity];
            1b];
        if[not eligible;
            if[failureCount<8;
                problems[failureCount]:
                    "parent directory identity changed before ",path];
            failureCount+:1];
        if[eligible;
            inspected:attempt[adapter`inspect;enlist path];
            if[not first inspected;
                if[failureCount<8;
                    problems[failureCount]:
                        "cannot inspect ",path,": ",
                        diagnostic[last inspected;256]];
                failureCount+:1];
            if[first inspected;
                state:last inspected;
                validState:99h=type state;
                if[validState;
                    validState:all
                        `path`exists`kind`identity in key state];
                if[validState;
                    validState:all (
                        10h=type state`path;
                        -1h=type state`exists;
                        -11h=type state`kind;
                        10h=type state`identity)];
                if[validState;
                    validState:
                        withinFn[state`path;path;windows] and
                        withinFn[path;state`path;windows]];
                if[not validState;
                    if[failureCount<8;
                        problems[failureCount]:
                            "invalid inspection result for ",path];
                    failureCount+:1];
                if[validState and
                   not state[`kind] in `file`dir`missing`link;
                    if[failureCount<8;
                        problems[failureCount]:
                            "unsupported filesystem entry: ",path];
                    failureCount+:1];
                if[validState and state[`kind]~`link;
                    if[0=count parent;
                        if[failureCount<8;
                            problems[failureCount]:
                                "explicit discovery root is a filesystem link: ",
                                path];
                        failureCount+:1]];
                if[validState and state[`kind]~`file;
                    parentStable:$[
                        count parent;
                        stableDirectory[
                            attempt;adapter`inspect;withinFn;windows;
                            parent;parentIdentity];
                        1b];
                    if[parentStable and state[`path] like "*",suffix;
                        files[fileCount]:state`path;
                        fileCount+:1];
                    if[not parentStable;
                        if[failureCount<8;
                            problems[failureCount]:
                                "parent directory identity changed before ",path];
                        failureCount+:1]];
                if[validState and state[`kind]~`missing;
                    if[failureCount<8;
                        problems[failureCount]:"missing path: ",path];
                    failureCount+:1];
                if[validState and state[`kind]~`dir;
                    identity:state`identity;
                    if[not 10h=type identity;
                        if[failureCount<8;
                            problems[failureCount]:
                                "invalid directory identity: ",state`path];
                        failureCount+:1];
                    physical:$[
                        10h=type identity;
                        withinFn[identity;state`path;windows] and
                          withinFn[state`path;identity;windows];
                        0b];
                    seen:$[
                        physical;
                        any identity~/:identityCount#identities;
                        1b];
                    if[(10h=type identity) and not physical;
                        if[failureCount<8;
                            problems[failureCount]:
                                "directory physical identity escaped path: ",
                                state`path];
                        failureCount+:1];
                    if[physical and not seen;
                        identities[identityCount]:identity;
                        identityCount+:1;
                        listed:attempt[adapter`list;
                            (state`path;1+entryLimit-consumed;byteLimit)];
                        if[not first listed;
                            if[failureCount<8;
                                problems[failureCount]:
                                    "cannot enumerate ",state`path,": ",
                                    diagnostic[last listed;256]];
                            failureCount+:1];
                        if[first listed;
                            listing:last listed;
                            stable:0b;
                            validListing:99h=type listing;
                            if[validListing;
                                validListing:all
                                    `path`entries in key listing];
                            if[validListing;
                                validListing:
                                    (10h=type listing`path) and
                                    withinFn[
                                        listing`path;state`path;windows] and
                                    withinFn[
                                        state`path;listing`path;windows]];
                            if[validListing;
                                names:listing`entries;
                                if[10h=type names;
                                    names:enlist names];
                                validListing:(0h=type names) and
                                    all 10h=type each names];
                            if[validListing;
                                validListing:not any {
                                    if[0=count x;:1b];
                                    if[any x~/:(".";"..");:1b];
                                    if[any x in "/\\";:1b];
                                    codes:"i"$x;
                                    (any codes<32) or any codes=127
                                  } each names];
                            if[not validListing;
                                if[failureCount<8;
                                    problems[failureCount]:
                                        "invalid directory enumeration for ",
                                        state`path];
                                failureCount+:1];
                            if[validListing;
                                stable:stableDirectory[
                                    attempt;adapter`inspect;withinFn;windows;
                                    state`path;identity];
                                if[not stable;
                                    if[failureCount<8;
                                        problems[failureCount]:
                                            "directory identity changed during traversal: ",
                                            state`path];
                                    failureCount+:1]];
                            if[validListing and stable;
                                names:asc names;
                                consumed+:count names;
                                names:names where not names like ".*";
                                if[(count names) and depth>=depthLimit;
                                    if[failureCount<8;
                                        problems[failureCount]:
                                            "discovery depth exceeded at ",state`path];
                                    failureCount+:1];
                                if[depth<depthLimit;
                                    if[(tail+count names)>capacity;
                                        '"Discovery queue limit exceeded"];
                                    if[count names;
                                        children:{[base;name]
                                            base,"/",name}[state`path;] each names;
                                        slots:tail+til count names;
                                        queue[slots]:children;
                                        depths[slots]:1+depth;
                                        parents[slots]:(count names)#enlist state`path;
                                        parentIds[slots]:(count names)#enlist identity;
                                        tail+:count names]]]]]]]]];
    found:$[
        fileCount;
        asc distinct fileCount#files;
        ()];
    `files`problems`failureCount!(
        found; (8&failureCount)#problems; failureCount)};

.tst.suffixMatch:{[suffix;path]
    if[not 10h=type suffix;'"Invalid discovery suffix"]; adapter:.utl.fsSnapshot[];
    state:.tst.walkFiles[suffix;enlist .utl.absolutePath path;adapter]; if[state`failureCount;
        '"Incomplete test traversal: ","; " sv state`problems]; state`files};

.tst.addLoadError:{[path;message;kind;admitted]
    if[not `loadErrors in key `.tst.app;
        .tst.app.loadErrors:
            flip `file`error`type!(`symbol$();();`symbol$())];
    if[not 98h=type .tst.app.loadErrors;'"Invalid load-error registry"];
    text:.utl.boundedDiagnostic[message;2048]; if[not admitted;
        text:"Path ",.utl.boundedDiagnostic[path;512],": ",text];
    file:$[admitted;.utl.pathToHsym path;`missing];
    `.tst.app.loadErrors upsert
        `file`error`type!(file;text;kind); (::)};

.tst.discoveryPatternValid:{[pattern]
    if[not 10h=type pattern;:0b];
    if[0=count pattern;:0b];
    if[any pattern in "/\\";:0b];
    codes:"i"$pattern;
    if[(any codes<32) or any codes=127;:0b];
    if[1<count where pattern="*";:0b];
    @[{[p]"" like p;1b};pattern;{[e]0b}]};
.tst.discoveryPatternsValid:{[patterns]
    if[10h=type patterns;
        :.tst.discoveryPatternValid patterns];
    if[(not 0h=type patterns) or 0=count patterns;
        :0b];
    all .tst.discoveryPatternValid each patterns};

.tst.findTests:{[paths]
    raw:$[
        type[paths] in -10 10 -11h;enlist paths; type[paths] in 0 11h;paths;
        enlist paths]; limit:.utl.hardLimit[.tst.MAX_TEST_FILES;4096;"test file"];
    if[count[raw]>limit;'"Test path limit exceeded"];
    normalized:distinct .utl.absolutePath each raw;
    if[(sum count each normalized)>
       .utl.hardLimit[.tst.MAX_TEST_PATH_BYTES;4194304;"test path byte"];
        '"Test path byte limit exceeded"]; adapter:.utl.fsSnapshot[]; states:{[fs;p]
        @[(fs`inspect);p;{[path;e]
            `path`exists`kind!(path;0b;`missing)}[p]]}[adapter;]
        each normalized; direct:normalized where {[state]
        state[`kind]~`file} each states; direct:direct where direct like "*.q";
    dirs:normalized where {[state]state[`kind]~`dir} each states; missing:normalized where {[state]
        not state[`kind] in `file`dir} each states; if[count missing; .tst.addLoadError[
            ;"Explicit test path not found";`missing;0b] each missing];
    patterns:@[get;`.resq.config.testFilePatterns;
        {("test_*.q";"*_test.q")}]; if[10h=type patterns;patterns:enlist patterns];
    if[not .tst.discoveryPatternsValid patterns;
        '"Invalid test file patterns"];
    walked:.tst.walkFiles[".q";dirs;adapter]; discovered:walked`files;
    if[walked`failureCount;
        detail:"Incomplete test traversal: ",
            "; " sv walked`problems; .tst.addLoadError[
            $[count dirs;first dirs;"."];detail;`discovery;1b]; discovered:0#enlist ""];
    named:discovered where {[pats;path]
        any (last "/" vs path) like/:pats}[patterns;] each discovered; distinct direct,named};

.tst.clearSandbox:{[namespace]
    if[(not -11h=type namespace) or
       not (string namespace) like ".sandbox_S_*";
        '"Invalid loader sandbox"]; names:@[key;namespace;{()}]; if[11h=type names;
        names:names where not null names; if[count names;![namespace;();0b;names]]]; (::)};

.tst.executeTestSource:{[ops;path;lines;namespace]
    (ops`clearSandbox) namespace; initName:`$string[namespace],".init";
    initName set 0; .tst.currentNs:namespace;
    .utl.FILELOADING:(ops`toHsym) path; system "d ",string namespace;
    prepared:(ops`preprocess) lines; (ops`evaluate) prepared;
    (::)};

.tst.specAppendValid:{[before;after;limit]
    if[not type[before] in 0 98h;:0b]; if[not type[after] in 0 98h;:0b];
    if[count[after]>limit;:0b]; n:count before;
    if[n>count after;:0b]; if[n;
        if[not all {[a;b;i](a i)~b i}[before;after;] each til n;
            :0b]]; indices:n+til (count after)-n; valid:{[spec]
        if[not 99h=type spec;:0b];
        required:`result`title`expectations`namespace`tstPath`beforeAll`afterAll;
        if[not all required in key spec;:0b]; if[not 10h=type spec`title;:0b];
        if[not type[spec`expectations] in 0 98h;:0b];
        if[not all -11h=type each (spec`namespace;spec`tstPath);:0b];
        all (type spec`beforeAll;type spec`afterAll) within 100 112h};
    all valid each after indices};
.tst.rollbackLoad:{[owned;specs;namespace;clear]
    `.tst.app.allSpecs set specs; `.tst.app.loadedFiles set owned`loaded;
    `.tst.app.emptyFiles set owned`empty; `.tst.app.loadErrors set owned`errors;
    .[{[f;ns]f ns;1b};(clear;namespace);{[e]0b}]};

/ Loader restoration attempts every owned field, then verifies the full snapshot.
.tst.restoreRuntimeContextStrict:{[attempt;diagnostic;pathText;capture;ctx]
    required:`namespace`context`tstPath`currentNs`fileLoadingSet`fileLoading`cwd;
    if[not 99h=type ctx;
        '"Invalid captured runtime context"];
    if[(count[key ctx]<>count required) or
       not all required in key ctx;
        '"Invalid captured runtime context"];
    symbolFields:all -11h=type each
        (ctx`namespace;ctx`context;ctx`tstPath;ctx`currentNs);
    fileLoadingValid:$[
        1b~ctx`fileLoadingSet;
        -11h=type ctx`fileLoading;
        0b~ctx`fileLoadingSet;
        (::)~ctx`fileLoading;
        0b];
    if[(not symbolFields) or
       (not fileLoadingValid) or
       not type[ctx`cwd] in -10 10 -11h;
        '"Invalid captured runtime context"];
    problems:();
    outcome:attempt[{[savedValue]`.tst.context set savedValue};enlist ctx`context];
    if[not first outcome;problems,:enlist
        "context: ",diagnostic[last outcome;256]];
    outcome:attempt[{[savedValue]`.tst.tstPath set savedValue};enlist ctx`tstPath];
    if[not first outcome;problems,:enlist
        "test path: ",diagnostic[last outcome;256]];
    outcome:attempt[{[savedValue]`.tst.currentNs set savedValue};enlist ctx`currentNs];
    if[not first outcome;problems,:enlist
        "current namespace: ",diagnostic[last outcome;256]];
    outcome:attempt[{[wasSet;savedValue]
        $[wasSet;`.utl.FILELOADING set savedValue;
          if[`FILELOADING in key `.utl;
              ![`.utl;();0b;enlist `FILELOADING]]];
        (::)};(ctx`fileLoadingSet;ctx`fileLoading)];
    if[not first outcome;problems,:enlist
        "loading file: ",diagnostic[last outcome;256]];
    outcome:attempt[system;enlist "cd ",pathText ctx`cwd];
    if[not first outcome;problems,:enlist
        "current directory: ",diagnostic[last outcome;256]];
    outcome:attempt[system;enlist "d ",string ctx`namespace];
    if[not first outcome;problems,:enlist
        "namespace: ",diagnostic[last outcome;256]];
    observed:attempt[capture;()];
    if[not first observed;problems,:enlist
        "postcondition capture: ",diagnostic[last observed;256]];
    if[first observed;if[not ctx~last observed;
        problems,:enlist "postcondition mismatch"]];
    if[count problems;
        '"Runtime context restoration failed: ",
          diagnostic["; " sv problems;2048]];
    (::)};

.tst.loadOne:{[ops;path]
    attempt:.utl.attempt;
    reader:(ops`fs)`readRegular; read:attempt[reader;(path;ops`sourceLimit)];
    if[not first read;
        (ops`addError)[path;last read;`read;1b]; :()]; source:last read; if[not 99h=type source;
        (ops`addError)[path;"Invalid source read result";`read;1b]; :()];
    if[not all `path`bytes in key source;
        (ops`addError)[path;"Invalid source read result";`read;1b]; :()];
    decoded:attempt[ops`textLines;
        (source`bytes;ops`lineLimit)]; if[not first decoded;
        (ops`addError)[source`path;last decoded;`read;1b]; :()];
    lines:last decoded; namespace:(ops`sandbox) source`path;
    captured:attempt[ops`capture;()]; if[not first captured;
        (ops`addError)[source`path;last captured;`context;1b]; :()];
    context:last captured; preSpecs:.tst.app.allSpecs;
    if[count[preSpecs]>ops`specLimit;
        '"Spec registry limit exceeded"]; owned:`loaded`empty`errors!(
        .tst.app.loadedFiles; .tst.app.emptyFiles;
        .tst.app.loadErrors); body:attempt[ops`execute;
        (ops;source`path;lines;namespace)]; postSpecs:@[get;`.tst.app.allSpecs;{::}];
    validSpecs:(ops`specsValid)[preSpecs;postSpecs;ops`specLimit]; currentOwned:(
        @[get;`.tst.app.loadedFiles;{::}]; @[get;`.tst.app.emptyFiles;{::}];
        @[get;`.tst.app.loadErrors;{::}]); if[not owned~(`loaded`empty`errors!currentOwned);
        `.tst.app.loadedFiles set owned`loaded; `.tst.app.emptyFiles set owned`empty;
        `.tst.app.loadErrors set owned`errors;
        body:(0b;"loader registry changed during test load")]; if[not validSpecs;
        body:(0b;"spec registry changed during test load")];
    restored:attempt[ops`restore;enlist context];
    if[(not first body) or not first restored;
        rolledBack:(ops`rollback)[
            owned;preSpecs;namespace;ops`clearSandbox]; if[not first body;
        error:(ops`diagnostic)[last body;1024]; line:@[(ops`localize);lines;{0N}];
        if[not null line;
            error,: " (near line ",string[line],")"]; (ops`addError)[source`path;error;`load;1b];
        notice:"CRITICAL LOAD ERROR in ",(source`path),": ",error; if[not ops`quiet;-1 notice]];
      if[not first restored;
        (ops`addError)[
            source`path;"Loader context restoration failed";`cleanup;1b]]; if[not rolledBack;
        (ops`addError)[
            source`path;"Loader rollback failed";`cleanup;1b]]; :()];
    .tst.app.loadedFiles,:enlist source`path; if[count[postSpecs]=count[preSpecs];
        message:"File ",(source`path)," loaded but added no tests."; warning:"WARNING: ",message;
        if[not ops`quiet;-1 warning]; .tst.app.emptyFiles,:enlist source`path;
        if[ops`strict;
            (ops`addError)[source`path;message;`emptyFile;1b]]]; (::)};

.tst.loaderOps:{[]
    adapter:.utl.fsSnapshot[];
    capture:.tst.captureRuntimeContext;
    restore:.tst.restoreRuntimeContextStrict[
        .utl.attempt;.utl.boundedDiagnostic;.utl.pathToString;capture];
    names:`fs`textLines`sandbox`capture`restore`addError`execute`localize,
      `clearSandbox`toHsym`preprocess`evaluate`diagnostic`specsValid`rollback,
      `sourceLimit`lineLimit`specLimit`strict`quiet; names!(
      adapter;.utl.textLinesBounded; {[path]
        base:64#last "/" vs path; base[where not base in .Q.a,.Q.A,.Q.n]:first "_";
        `$".sandbox_S_",base,"_",16#raze string md5 path};
      capture;restore;.tst.addLoadError;
      .tst.executeTestSource;.tst.localizeSyntaxError;.tst.clearSandbox;
      .utl.pathToHsym;.tst.preprocessScript;.tst.evalPreprocessed;
      .utl.boundedDiagnostic;.tst.specAppendValid;.tst.rollbackLoad; .utl.hardLimit[
        .tst.MAX_TEST_SOURCE_BYTES;16777216;"test source byte"]; .utl.hardLimit[
        .tst.MAX_TEST_SOURCE_LINES;65536;"test source line"];
      .utl.hardLimit[.tst.MAX_SPECS;10000;"spec"];
      1b~@[get;`.tst.app.strict;0b]; 1b~@[get;`.tst.app.quiet;0b])};
.tst.loadTests:{[paths]
    find:.tst.findTests; tests:find paths;
    limit:.utl.hardLimit[.tst.MAX_TEST_FILES;4096;"test file"];
    if[count[tests]>limit;'"Test file limit exceeded"];
    .tst.app.discoveredFiles:tests; .tst.app.loadedFiles:0#enlist "";
    .tst.app.emptyFiles:0#enlist ""; if[0=count tests;
        -1 "WARNING: No test files found"; :()]; ops:.tst.loaderOps[]; loadOne:.tst.loadOne;
    i:0; while[i<count tests;
        if[not .tst.app.quiet;-1 "Loading Test: ",tests i]; loadOne[ops;tests i]; i+:1]; (::)};
