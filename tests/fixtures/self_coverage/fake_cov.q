/ Contract double for the optional external adapter. It exercises lifecycle and
/ artifact mapping without claiming to implement KX Developer instrumentation.
.cov.run:{[function;parameters;settings]
    function . parameters;
    ([] name:enlist `.tst.runAll;
        iterations:enlist 1j;
        lineIterations:enlist 1 0 2j;
        blockIterations:enlist 1 0j;
        lines:enlist (0 1;2 3;4 5);
        blocks:enlist (6 7;8 9);
        text:enlist "{fake coverage provider}")
 };
.cov.format.go:{[rows]
    ("fake external coverage";"1/1 functions measured")
 };
