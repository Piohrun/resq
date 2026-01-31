\l lib/bootstrap.q
.utl.require "lib/init.q"
.utl.require "lib/loader.q"

p: "tests/hardening/test_resource_cleanup.q"
content: read0 hsym `$p
cleanP: p
cleanP[where not cleanP in .Q.a,.Q.A,.Q.n]: first "_"
nsName: `$".sandbox_S", cleanP
nsInit: string[nsName],".init:0;"
nsSwitch: "@[system; \"d ", string[nsName], "\"; { -1 \"FAIL FULL namespace switch \", x }];"
nsRestore: "system \"d .\";"
fullContent: enlist[nsInit], enlist[nsSwitch], content, enlist[nsRestore]
-1 "Evaluating...";
r: @[{value "\n" sv x}; fullContent; { "ERROR: ", x }];
-1 "Result: ", $[10h=abs type r; r; -3!r];
exit 0
