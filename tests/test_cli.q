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

/ End-to-end CLI flag plumbing. Each test writes a 2-suite fixture and spawns a
/ fresh resq process (the arg handling lives in resq.q, which reads .z.x), then
/ greps the run output. The fixture has a "single suite alpha" (tag #fast) and an
/ "other suite beta" (no tag) so -only/-exclude/-tag selection is observable.
.tst.cliFixture: {[dir]
    / Build the fixture from a shell heredoc; returns the leading shell command
    / (mkdir + write) the caller prepends to its resq invocation.
    f: dir, "/cli_flags.q";
    "mkdir -p ", dir, " && printf '%s\\n' ",
      "'.tst.desc[\"single suite alpha #fast\"]{ should[\"one\"]{ 1 musteq 1; }; };' ",
      "'.tst.desc[\"other suite beta\"]{ should[\"two\"]{ 2 musteq 2; }; };' > ", f, " && "
 };

.tst.desc["CLI value-flag plumbing"]{
    should["-only filters suites by title pattern (1 of 2 runs)"]{
        d: "/tmp/p4c/cli_only";
        cmd: .tst.cliFixture[d], .tst.cliQBin[], .tst.cliResqHome[], "/resq.q test ", d, "/cli_flags.q -only \"single*\" -noquit -e 1 < /dev/null 2>&1 | grep -i 'Tests:'";
        out: @[system; cmd; {[e] enlist ""}];
        text: "\n" sv $[10h = type out; enlist out; out];
        (text like "*1 total*") mustmatch 1b;
    };

    should["-exclude drops matching suites"]{
        d: "/tmp/p4c/cli_excl";
        cmd: .tst.cliFixture[d], .tst.cliQBin[], .tst.cliResqHome[], "/resq.q test ", d, "/cli_flags.q -exclude \"single*\" -noquit -e 1 < /dev/null 2>&1 | grep -i 'Tests:'";
        out: @[system; cmd; {[e] enlist ""}];
        text: "\n" sv $[10h = type out; enlist out; out];
        (text like "*1 total*") mustmatch 1b;
    };

    should["-tag filters by suite tag (1 of 2 runs)"]{
        d: "/tmp/p4c/cli_tag";
        cmd: .tst.cliFixture[d], .tst.cliQBin[], .tst.cliResqHome[], "/resq.q test ", d, "/cli_flags.q -tag fast -noquit -e 1 < /dev/null 2>&1 | grep -i 'Tests:'";
        out: @[system; cmd; {[e] enlist ""}];
        text: "\n" sv $[10h = type out; enlist out; out];
        (text like "*1 total*") mustmatch 1b;
    };

    should["a value-flag value does NOT become a positional test path"]{
        / -only's value "single*" must not be treated as a path (old bug reported
        / 'Explicit test path not found: single*').
        d: "/tmp/p4c/cli_noleak";
        cmd: .tst.cliFixture[d], .tst.cliQBin[], .tst.cliResqHome[], "/resq.q test ", d, "/cli_flags.q -only \"single*\" -noquit -e 1 < /dev/null 2>&1 | grep -ci 'Explicit test path not found'";
        out: @[system; cmd; {[e] enlist "0"}];
        cnt: "J"$ $[count out; first out; "0"];
        cnt musteq 0;
    };

    should["a boolean flag does NOT swallow the following path"]{
        / -strict (boolean) before the path must leave the path as a positional.
        d: "/tmp/p4c/cli_bool";
        cmd: .tst.cliFixture[d], .tst.cliQBin[], .tst.cliResqHome[], "/resq.q test -strict ", d, "/cli_flags.q -noquit -e 1 < /dev/null 2>&1 | grep -i 'Tests:'";
        out: @[system; cmd; {[e] enlist ""}];
        text: "\n" sv $[10h = type out; enlist out; out];
        (text like "*2 total*") mustmatch 1b;
    };
};

.tst.desc["CLI describe-only listing"]{
    should["-desc lists both suites with test names and no malformed summary"]{
        d: "/tmp/p4c/cli_desc";
        cmd: .tst.cliFixture[d], .tst.cliQBin[], .tst.cliResqHome[], "/resq.q test ", d, "/cli_flags.q -desc -noquit -e 1 < /dev/null 2>&1";
        out: @[system; cmd; {[e] enlist ""}];
        text: "\n" sv $[10h = type out; enlist out; out];
        (text like "*single suite alpha*") mustmatch 1b;
        (text like "*other suite beta*") mustmatch 1b;
        / The malformed "( passed,  failed," summary must NOT be emitted.
        (text like "*( passed,*") mustmatch 0b;
    };

    should["-desc exits 0 when files load cleanly"]{
        d: "/tmp/p4c/cli_desc_exit";
        / No -noquit: let resq emit its real exit code, captured via echo $?.
        cmd: .tst.cliFixture[d], .tst.cliQBin[], .tst.cliResqHome[], "/resq.q test ", d, "/cli_flags.q -desc -e 1 < /dev/null > /dev/null 2>&1; echo $?";
        out: @[system; cmd; {[e] enlist "99"}];
        code: "J"$ $[count out; last out; "99"];
        code musteq 0;
    };
};
