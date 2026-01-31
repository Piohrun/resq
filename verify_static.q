\l lib/static_analysis.q

-1 "Scanning legacy.q:";
legacy: .tst.static.exploreFile "tests/hardening/repro_deps/legacy.q";
show legacy

-1 "Scanning messy.q:";
messy: .tst.static.exploreFile "tests/hardening/repro_deps/messy.q";
show messy

exit 0
