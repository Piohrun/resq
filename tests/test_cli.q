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
