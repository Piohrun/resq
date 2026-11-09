/ Every ordered pair of DSL constructors, declared together in one desc, must
/ load and pass, natively and through bin/qspec's loader path. Expectations
/ are rows of one q table, so a constructor whose values do not fit the column
/ types fixed by an earlier row used to fail the whole file at load: in 2.2.0,
/ a holds with dict/list/function vars or an integer maxFailRate did so in 43
/ of 169 pairs. The constructor list is
/ tests/fixtures/dsl_combinations/constructors.txt.

\d .tst

.tst.dslpairs.base:.utl.tempRoot[],"/resq_dslpairs_",string .z.i;

.tst.dslpairs.constructors:{[]
  lines:read0 hsym `$.resq.HOME,"/tests/fixtures/dsl_combinations/constructors.txt";
  lines:lines where (0<count each lines) and not lines like "/*";
  parts:"|" vs' lines;
  `name`rows`code!(`$parts[;0];"J"$parts[;1];"|" sv' 2_' parts)
 };

/ Write one test file per ordered pair; return the expected result-row count.
.tst.dslpairs.write:{[dir]
  c:.tst.dslpairs.constructors[];
  .utl.ensureDir dir;
  n:count c`name;
  {[dir;c;pair]
    i:pair 0; j:pair 1;
    title:string[c[`name] i]," then ",string c[`name] j;
    (hsym `$dir,"/test_",string[c[`name] i],"__",string[c[`name] j],".q") 0: (
      ".tst.desc[\"",title,"\"]{";
      "  ",ssr[c[`code] i;"{n}";"1"];
      "  ",ssr[c[`code] j;"{n}";"2"];
      " };")
  }[dir;c] each (til n) cross til n;
  2*n*sum c`rows
 };

.tst.dslpairs.run:{[dir;flags;label]
  qexe:first @[system;"command -v q 2>/dev/null";{enlist (getenv[`QHOME]),"/l64/q"}];
  report:.tst.dslpairs.base,"/report-",label;
  cmd:"cd ",.utl.shellQuote[dir]," && timeout -k 5 120 ",.utl.shellQuote[qexe]," ",
      .utl.shellQuote[.resq.HOME,"/resq.q"]," test . -perf -strict -json -quiet ",flags,
      " -state-file ",.utl.shellQuote[.tst.dslpairs.base,"/state-",label,".json"],
      " -flake-history ",.utl.shellQuote[.tst.dslpairs.base,"/flake-",label,".json"],
      " -outDir ",.utl.shellQuote[report],
      " < /dev/null > ",.utl.shellQuote[.tst.dslpairs.base,"/out-",label,".txt"]," 2>&1; echo $?";
  code:"J"$last @[system;"sh -c ",.utl.shellQuote cmd;{[err]enlist "-1"}];
  raw:@[read0;hsym `$report,"/test-results.json";{()}];
  tests:$[count raw;(.j.k "\n" sv raw)`tests;()];
  `code`tests!(code;tests)
 };

.tst.dslpairs.check:{[result;expected]
  result[`code] musteq 0j;
  statuses:{`$x`status} each result`tests;
  labels:{(x`suite)," :: ",x`description} each result`tests;
  / Name every broken pairing rather than only counting them.
  (labels where statuses in `fail`error) mustmatch ();
  (count result`tests) musteq expected;
 };

.tst.dslpairs.cleanup:{[]
  expected:.utl.tempRoot[],"/resq_dslpairs_",string .z.i;
  if[not .tst.dslpairs.base~expected;'"refusing unsafe DSL pair cleanup path"];
  if[.utl.pathExists .tst.dslpairs.base;
    system "rm -rf -- ",.utl.shellQuote .tst.dslpairs.base];
 };

\d .

.tst.desc["DSL constructor combinations #slow"]{
  after{ .tst.dslpairs.cleanup[] };

  skipIf[0=count @[system;"command -v timeout 2>/dev/null";{()}];
         "load and pass every ordered pair natively and through the qspec loader"]{
    dir:.tst.dslpairs.base,"/pairs";
    expected:.tst.dslpairs.write dir;
    must[expected>400;"the fixture must generate the full pair matrix"];
    .tst.dslpairs.check[.tst.dslpairs.run[dir;"";"native"];expected];
    .tst.dslpairs.check[.tst.dslpairs.run[dir;"-qspec-compat -qspec-discovery";"qspec"];expected];
  };
 };
