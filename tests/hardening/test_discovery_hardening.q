/ Focused end-to-end hardening contracts for static discovery and mirror output.

.tst.testState.discovery.base: "/tmp/resq_discovery_", string .z.i;
.tst.testState.discovery.counter: 0;

.tst.testState.discovery.workDir:{[]
    .tst.testState.discovery.counter+: 1;
    .tst.testState.discovery.base, "/case_", string .tst.testState.discovery.counter
};

.tst.testState.discovery.cleanup:{[path]
    expected: .tst.testState.discovery.base, "/case_";
    if[not path like expected, "*";
        '"refusing unsafe discovery-test cleanup path"];
    if[.utl.pathExists path;
        command:$[.utl.isWindows;
            "if exist ",.utl.shellQuote[path]," rmdir /S /Q ",
                .utl.shellQuote[path];
            "rm -rf -- ",.utl.shellQuote[path]];
        @[system;command;{[p;e]
            -2 "DISCOVERY TEST CLEANUP ERROR: ",p,": ",e
        }[path]]];
    if[.utl.pathExists .tst.testState.discovery.base;
        command:$[.utl.isWindows;
            "rmdir ",.utl.shellQuote[.tst.testState.discovery.base],
                " >NUL 2>&1";
            "rmdir -- ",.utl.shellQuote[.tst.testState.discovery.base],
                " 2>/dev/null || true"];
        @[system;command;{}]];
};

.tst.testState.discovery.setup:{[]
    wd: .tst.testState.discovery.workDir[];
    .utl.ensureDir wd;
    .tst.registerCleanup[.tst.testState.discovery.cleanup; enlist wd];
    wd
};

.tst.testState.discovery.write:{[path;lines]
    (hsym `$path) 0: lines;
    path
};

.tst.testState.discovery.anyLike:{[lines;pattern]
    any lines like ("*", pattern, "*")
};

.tst.testState.discovery.anyContains:{[lines;fragment]
    any {[fragment;line] 0<count line ss fragment}[fragment;] each lines
};

.tst.testState.discovery.containsText:{[text;fragment]
    0<count text ss fragment
};

.tst.testState.discovery.captureCall:{[fn;args]
    .[
        {[callable;arguments] (0b;callable . arguments)};
        (fn;args);
        {[e] (1b;e)}]
};

.tst.testState.discovery.qExe:{[]
    found: @[system; "command -v q 2>/dev/null"; {()}];
    $[count found; first found; ""]
};

.tst.testState.discovery.canTimeout:
    0 < count @[system; "command -v timeout 2>/dev/null"; {()}];

.tst.testState.discovery.canPosixLinks:
    (not .utl.isWindows) and
    0<count @[system;"command -v ln 2>/dev/null";{()}];

.tst.testState.discovery.canPosixModes:
    (not .utl.isWindows) and
    0<count @[system;"command -v chmod 2>/dev/null";{()}];

.tst.testState.discovery.link:{[target;linkPath]
    if[not .tst.testState.discovery.canPosixLinks;
        '"POSIX symbolic links are unavailable"];
    system "ln -s ",.utl.shellQuote[target]," ",.utl.shellQuote[linkPath];
};

.tst.desc["Discovery: deterministic and cycle-safe source traversal #slow"]{
    should["sort q files and skip hidden entries with paths containing spaces"]{
        wd: .tst.testState.discovery.setup[];
        src: wd, "/source tree [safe]";
        nested: src, "/nested dir";
        hidden: src, "/.hidden";
        .utl.ensureDir nested;
        .utl.ensureDir hidden;
        .tst.testState.discovery.write[src, "/z.q"; enlist "z:{[] 1}"];
        .tst.testState.discovery.write[src, "/a.q"; enlist "a:{[] 1}"];
        .tst.testState.discovery.write[nested, "/b.q"; enlist "b:{[] 1}"];
        .tst.testState.discovery.write[hidden, "/hidden.q"; enlist "hidden:{[] 1}"];

        firstScan: string .tst.static.findSources src;
        secondScan: string .tst.static.findSources src;
        firstScan mustmatch asc firstScan;
        firstScan mustmatch secondScan;
        (count firstScan) musteq 3;
        must[not any firstScan like "*/.hidden/*"; "hidden source must be skipped"];
    };

    should["not confuse a harmless sentinel-named file with inspection failure"]{
        wd:.tst.testState.discovery.setup[];
        src:wd, "/sentinel collision";
        .utl.ensureDir src;
        .tst.testState.discovery.write[
            src, "/DISCOVERY_KEY_ERROR";
            enlist "ordinary non-q data"];
        sourceFile:.tst.testState.discovery.write[
            src, "/real.q";
            enlist "real:{[] 1}"];
        string[.tst.static.findSources src] mustmatch enlist sourceFile;
    };

    skipIf[
        not .tst.testState.discovery.canPosixLinks;
        "never follow a POSIX symlink directory cycle"]{
        wd: .tst.testState.discovery.setup[];
        src: wd, "/cycle source";
        nested: src, "/nested";
        .utl.ensureDir nested;
        .tst.testState.discovery.write[src, "/a.q"; enlist "a:{[] 1}"];
        loop: nested, "/loop";
        .tst.testState.discovery.link[src;loop];

        firstScan: string .tst.static.findSources src;
        secondScan: string .tst.static.findSources src;
        firstScan mustmatch secondScan;
        (count firstScan) musteq 1;
        must[not any firstScan like "*/loop/*"; "symlink directory must not be followed"];
    };

    skipIf[
        not .tst.testState.discovery.canPosixLinks;
        "honour an explicitly supplied readable POSIX q-file symlink"]{
        wd: .tst.testState.discovery.setup[];
        real: .tst.testState.discovery.write[wd, "/real file.q"; enlist "f:{[] 1}"];
        link: wd, "/linked file.q";
        .tst.testState.discovery.link[real;link];
        string[.tst.static.findSources link] mustmatch enlist link;
    };

    should["treat an empty directory as a quiet empty result"]{
        wd: .tst.testState.discovery.setup[];
        emptyDir: wd, "/empty";
        .utl.ensureDir emptyDir;
        previousWarn: .tst.static.warn;
        .tst.registerCleanup[
            {[previous] `.tst.static.warn set previous};
            enlist previousWarn];
        .tst.testState.discovery.warnCount:0;
        .tst.static.warn:{
            .tst.testState.discovery.warnCount+::1;
            (::)
        };
        .tst.static.findSources[emptyDir] mustmatch `symbol$();
        .tst.testState.discovery.warnCount musteq 0;
        `.tst.static.warn set previousWarn;
    };

    should["stop deterministically at the total traversal-entry budget"]{
        wd: .tst.testState.discovery.setup[];
        src: wd, "/budget";
        .utl.ensureDir src;
        {[root;name]
            .tst.testState.discovery.write[
                root,"/",name,".q";
                enlist name,":{[] 1}"]
        }[src;] each ("c";"a";"b");
        state:.tst.static.findSourcesDepth[src;0;2;0b];
        found:string state`files;
        (count found) musteq 2;
        (.tst.static.getBase each found) mustmatch ("a.q";"b.q");
        state[`warned] musteq 1b;
        (count state`problems) musteq 1;
        captured:.tst.testState.discovery.captureCall[
            .tst.static.requireCompleteTraversal;enlist state];
        first[captured] musteq 1b;
        must[
            .tst.testState.discovery.containsText[
                last captured;"Incomplete source traversal"];
            "bounded partial traversal must be rejected"];
        must[
            .tst.testState.discovery.containsText[
                last captured;"entry budget exceeded"];
            "bounded traversal error must explain the exhausted budget"];
    };

    should["fail the public walk when the depth limit leaves source unvisited"]{
        wd: .tst.testState.discovery.setup[];
        src: wd, "/deep";
        .utl.ensureDir src;
        current:src;
        i:0;
        while[i<.tst.static.MAX_DEPTH+1;
            current,: "/d";
            .utl.ensureDir current;
            i+:1;
        ];
        .tst.testState.discovery.write[
            current, "/unvisited.q";
            enlist "unvisited:{[] 1}"];
        captured:.tst.testState.discovery.captureCall[
            .tst.static.findSources;enlist src];
        first[captured] musteq 1b;
        must[
            .tst.testState.discovery.containsText[
                last captured;"Incomplete source traversal"];
            "public traversal must reject a depth-limited result"];
        must[
            .tst.testState.discovery.containsText[
                last captured;"depth exceeded"];
            "depth-limited traversal error must explain the limit"];
    };

    should["fail clearly for a missing explicitly requested source root"]{
        wd: .tst.testState.discovery.setup[];
        missing:wd, "/does-not-exist";
        captured:.tst.testState.discovery.captureCall[
            .tst.static.findSources;enlist missing];
        first[captured] musteq 1b;
        must[
            .tst.testState.discovery.containsText[
                last captured;"Incomplete source traversal"];
            "public traversal must reject a missing source root"];
        must[
            .tst.testState.discovery.containsText[
                last captured;"missing or broken"];
            "missing-root traversal error must explain the source problem"];
    };

    skipIf[
        not .tst.testState.discovery.canPosixModes;
        "fail clearly for an unreadable explicitly requested q file"]{
        wd: .tst.testState.discovery.setup[];
        sourceFile:.tst.testState.discovery.write[
            wd, "/unreadable.q";
            enlist "secret:{[] 1}"];
        system "chmod 000 -- ",.utl.shellQuote sourceFile;
        captured:.tst.testState.discovery.captureCall[
            .tst.static.findSources;enlist sourceFile];
        first[captured] musteq 1b;
        must[
            .tst.testState.discovery.containsText[
                last captured;"Incomplete source traversal"];
            "public traversal must reject an unreadable source file"];
        must[
            .tst.testState.discovery.containsText[
                last captured;"Cannot read requested source q file"];
            "unreadable-root traversal error must explain the read failure"];
        system "chmod 600 -- ",.utl.shellQuote sourceFile;
    };

    should["fail source exploration when a discovered file vanishes"]{
        wd:.tst.testState.discovery.setup[];
        missing:wd, "/vanished.q";
        captured:.tst.testState.discovery.captureCall[
            .tst.static.exploreFile;enlist missing];
        first[captured] musteq 1b;
        must[
            .tst.testState.discovery.containsText[
                last captured;"Unable to explore source file"];
            "exploration must signal instead of returning an empty table"];
        must[
            .tst.testState.discovery.containsText[last captured;missing];
            "exploration error must identify the vanished source"];
    };

    skipIf[
        not .tst.testState.discovery.canPosixModes;
        "fail source exploration when a discovered file becomes unreadable"]{
        wd:.tst.testState.discovery.setup[];
        sourceFile:.tst.testState.discovery.write[
            wd, "/became-unreadable.q";
            enlist "sensitive:{[] 1}"];
        system "chmod 000 -- ",.utl.shellQuote sourceFile;
        captured:.tst.testState.discovery.captureCall[
            .tst.static.exploreFile;enlist sourceFile];
        first[captured] musteq 1b;
        must[
            .tst.testState.discovery.containsText[
                last captured;"Unable to explore source file"];
            "unreadable exploration must signal instead of returning empty"];
        must[
            .tst.testState.discovery.containsText[
                last captured;sourceFile];
            "exploration error must identify the unreadable source"];
        system "chmod 600 -- ",.utl.shellQuote sourceFile;
    };
};

.tst.desc["Discovery: safe deterministic generated mirrors #slow"]{
    should["preserve Windows drive and UNC output-root spellings"]{
        .tst.static.absolutePath["C:\\repo\\reports"] musteq
            "C:/repo/reports";
        unc:.tst.static.absolutePath["\\\\server\\share\\reports"];
        unc musteq "//server/share/reports";
        .tst.static.containedGeneratedPath[unc;"nested/test_a.q"] musteq
            "//server/share/reports/nested/test_a.q";
        mustthrow[
            "*drive-relative path*";
            (.tst.static.absolutePath;"C:relative")];
    };

    should["generate valid pending tests deterministically and preserve existing files"]{
        wd: .tst.testState.discovery.setup[];
        src: wd, "/src";
        outA: wd, "/generated a";
        outB: wd, "/generated b";
        .utl.ensureDir src;
        sourceFile: .tst.testState.discovery.write[
            src, "/widget.q";
            (
                ".demo.add:{[x;y]";
                "  .demo.dep[x]+y";
                " }")];
        fns: .tst.static.exploreFile sourceFile;

        .tst.genMirror[fns; src; outA];
        .tst.genMirror[fns; src; outB];
        targetA: outA, "/test_widget.q";
        targetB: outB, "/test_widget.q";
        contentA: read0 hsym `$targetA;
        contentB: read0 hsym `$targetB;
        contentA mustmatch contentB;
        must[.tst.testState.discovery.anyContains[contentA; ".tst.pending"];
            "generated suite must register a TODO as pending"];
        must[not .tst.testState.discovery.anyLike[contentA; "fixture"];
            "generated suite must not contain undefined fixture placeholders"];
        must[not .tst.testState.discovery.anyLike[contentA; "expectedValue"];
            "generated suite must not contain undefined expected-value placeholders"];

        / A second pass must not alter the file that now exists.
        .tst.genMirror[fns; src; outA];
        (read0 hsym `$targetA) mustmatch contentA;

    };

    skipIf[
        .utl.isWindows or
            (0 = count .tst.testState.discovery.qExe[]) or
            not .tst.testState.discovery.canTimeout;
        "execute a generated test in a bounded fresh q process"]{
        wd: .tst.testState.discovery.setup[];
        src: wd, "/src";
        out: wd, "/generated";
        .utl.ensureDir src;
        .tst.testState.discovery.write[
            wd, "/resq.json";
            enlist "{\"qNamespaceExports\":false}"];
        sourceFile: .tst.testState.discovery.write[
            src, "/widget.q";
            enlist ".demo.add:{[x;y] x+y}"];
        fns: .tst.static.exploreFile sourceFile;
        .tst.genMirror[fns; src; out];
        target: out, "/test_widget.q";
        logPath: wd, "/generated-run.log";
        inner: "cd ",.utl.shellQuote[wd]," && timeout -k 5 30 ",
            .utl.shellQuote[.tst.testState.discovery.qExe[]], " ",
            .utl.shellQuote[.resq.HOME, "/resq.q"], " test ",
            .utl.shellQuote[target],
            " < /dev/null > ", .utl.shellQuote[logPath], " 2>&1; echo $?";
        / `cd` is also a q system command, so force this compound command
        / through the shell instead of letting q parse it as `\cd`.
        cmd: "sh -c ",.utl.shellQuote inner;
        runResult: @[
            {[command] (1b;system command)};
            cmd;
            {[e] (0b;enlist e)}];
        if[not first runResult;
            '"generated child process could not start: ",
                first last runResult];
        statusLines: last runResult;
        code: "J"$last statusLines;
        output: @[read0; hsym `$logPath; {()}];
        code musteq 0;
        must[
            .tst.testState.discovery.anyLike[lower each output; "pending"];
            "fresh resQ run must report the generated TODO as pending"];
    };

    should["reject traversal-like mirror paths without writing outside output"]{
        wd: .tst.testState.discovery.setup[];
        out: wd, "/generated";
        escaped: wd, "/escape.q";
        row: ([]
            name: enlist `.demo.escape;
            args: enlist enlist "x";
            line: enlist 1i;
            srcFile: enlist `$"../escape.q";
            dependencies: enlist enlist `symbol$();
            body: enlist enlist "{[x] x}");
        mustthrow[
            "*Unsafe generated relative path*";
            (.tst.genMirror; row; "src"; out)];
        must[not .utl.pathExists escaped; "no file may be written outside output"];
    };
};

.tst.desc["Discovery: HTML output safety"]{
    should["escape dynamic directory text"]{
        wd: .tst.testState.discovery.setup[];
        out: wd, "/coverage.html";
        stats: ([] dir: enlist `$"<unsafe&>"; total: enlist 1j;
            covered: enlist 0j; pct: enlist 0f);
        .tst.genHtmlReport[stats; out];
        html: raze read0 hsym `$out;
        must[not html like "*<unsafe&>*"; "raw dynamic HTML must not be emitted"];
        must[html like "*&lt;unsafe&amp;&gt;*"; "dynamic HTML must be escaped"];
    };

    should["signal clearly when the report cannot be written"]{
        wd: .tst.testState.discovery.setup[];
        impossible: wd;
        stats: ([] dir: enlist `.; total: enlist 1j;
            covered: enlist 1j; pct: enlist 100f);
        mustthrow[
            "*Unable to write discovery HTML report*";
            (.tst.genHtmlReport; stats; impossible)];
    };
};
