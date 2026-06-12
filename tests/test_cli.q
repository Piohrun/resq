/ Unit tests for the CLI mode dispatcher. We only cover the pure helper
/ (parseModeArgs) and the validModes contract; getArg / getFlag read .z.x
/ which is set by the q startup line and not safely mutable here.

.tst.desc["CLI mode parsing"]{
    should["default to test mode when no args supplied"]{
        r: .tst.parseModeArgs ();
        r[`mode] musteq `test;
        r[`args] mustmatch ();
    };

    should["recognise each documented mode"]{
        { [m]
            r: .tst.parseModeArgs enlist string m;
            r[`mode] musteq m;
            r[`args] mustmatch ();
        } each .tst.validModes;
    };

    should["strip the mode token and keep remaining args"]{
        r: .tst.parseModeArgs ("test"; "tests/"; "-junit");
        r[`mode] musteq `test;
        r[`args] mustmatch ("tests/"; "-junit");
    };

    should["treat an unrecognised first token as a path under default mode"]{
        / `mything` is not a mode, so the whole arglist is preserved.
        r: .tst.parseModeArgs ("mything"; "tests/");
        r[`mode] musteq `test;
        r[`args] mustmatch ("mything"; "tests/");
    };

    should["expose the canonical mode list"]{
        .tst.validModes mustmatch `test`cover`discover`watch;
    };
};

/ Subprocess scenarios for the unrecognized-flag WARNING in resq.q. The warning
/ is emitted from the entry script (reads .z.x), so it can only be exercised by
/ spawning a fresh resq process. q's `system` intercepts a leading "cd" and
/ rejects a leading "(", so each pipeline LEADS WITH mkdir.
/ Resolve the install root and a runnable q invocation for the subprocesses.
.tst.cliResqHome: {$[count h:getenv `RESQ_HOME; h; "/home/greg/Code/resq"]};
/ Prefer `q` on PATH (the suite is launched via it); fall back to $QHOME/l64/q.
.tst.cliQBin: {$[0 = "J"$ first @[system; "command -v q >/dev/null 2>&1; echo $?"; {enlist "1"}];
                "q "; (getenv[`QHOME]), "/l64/q "]};

.tst.desc["CLI unrecognized-flag warning"]{
    / NOTE: each nested q reads `< /dev/null`; without it the child contends for
    / the parent's stdin and q's `system` capture comes back empty.
    should["WARN on an unrecognized -flag and not on a path-like one"]{
        cmd: "mkdir -p /tmp/p4c/cli_a && ", .tst.cliQBin[], .tst.cliResqHome[], "/resq.q -bogusflag123 /tmp/p4c/cli_a -noquit -e 1 < /dev/null 2>&1 | grep -i unrecognized";
        out: @[system; cmd; {[e] enlist ""}];
        / `system` returns a list of lines (a general list when 1 row); join to one
        / string so `like` sees a flat char vector. Use ONE contiguous wildcard
        / region: q's `like` is nyi on patterns with two *...*-separated literals.
        text: "\n" sv $[10h = type out; enlist out; out];
        (text like "*unrecognized flag(s): -bogusflag123*") mustmatch 1b;
    };

    should["emit the path hint for a path-like dropped token"]{
        cmd: "mkdir -p /tmp/p4c/cli_b && ", .tst.cliQBin[], .tst.cliResqHome[], "/resq.q -tdir/test_x.q -noquit -e 1 < /dev/null 2>&1 | grep -i 'prefix it with'";
        out: @[system; cmd; {[e] enlist ""}];
        text: "\n" sv $[10h = type out; enlist out; out];
        (text like "*prefix it with ./*") mustmatch 1b;
    };

    should["NOT warn when only recognized flags are passed"]{
        cmd: "mkdir -p /tmp/p4c/cli_c && ", .tst.cliQBin[], .tst.cliResqHome[], "/resq.q /tmp/p4c/cli_c -junit -strict -noquit -e 1 < /dev/null 2>&1 | grep -ci 'unrecognized flag'";
        out: @[system; cmd; {[e] enlist "0"}];
        cnt: "J"$ $[count out; first out; "0"];
        cnt musteq 0;
    };
};
