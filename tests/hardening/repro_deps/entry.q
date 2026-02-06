system "l tests/hardening/repro_deps/legacy.q";
system "l tests/hardening/repro_deps/messy.q";

main:{
    res: legacyFunc[1;2];
    customLoad "tests/hardening/repro_deps/some_other.q";
    :res
 };
