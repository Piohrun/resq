\l lib/bootstrap.q
\l lib/init.q
\l lib/loader_discovery.q
\l lib/coverage.q

/ Initialize coverage
.tst.initCoverage[()];

/ Load the "app"
\l tests/hardening/repro_deps/entry.q

/ Run Auto-Hijack
-1 "Running Auto-Hijack...";
.tst.loader.autoHijack "tests/hardening/repro_deps";

/ Run the load
-1 "Running customLoad...";
customLoad "tests/hardening/repro_deps/some_other.q";

/ Check tracking
t: .tst.trackedFiles;
-1 "Tracked: ",.Q.s1 t;

if[0 = count t; -1 "FAIL: Dependencies not tracked."; exit 1];

-1 "SUCCESS: Dependency tracked.";
exit 0
