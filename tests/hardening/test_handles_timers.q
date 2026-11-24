.tst.testState.handlestimers.inOrder:{[name]
  wd: .utl.tempRoot[], "/resq_handlestimers_order_", string[.z.i], "_", string `long$.z.p;
  .utl.ensureDir wd;
  fixture: .resq.HOME, "/tests/fixtures/declaration_order/", name;
  cmd: "cd ", .utl.shellQuote[wd], " && timeout -k 2 60 ", .utl.shellQuote[.resq.HOME, "/bin/resq"],
      " test ", .utl.shellQuote[fixture], " -json -outDir out -state-file out/s.json",
      " -flake-history out/f.json -flake-proposal-file out/p.json < /dev/null > out.txt 2>&1; echo $?";
  code: "J"$last @[system; "sh -c ", .utl.shellQuote cmd; {[e] enlist "-1"}];
  raw: @[read0; hsym `$wd, "/out/test-results.json"; {()}];
  rows: $[count raw; (.j.k raze raw)`tests; ()];
  @[system; "rm -rf -- ", .utl.shellQuote wd; {}];
  `code`rows!(code; rows)
 };
.tst.testState.handlestimers.canQ: 0 < count @[system; "which q 2>/dev/null"; {()}];

/ One suite leaks a handle and sets .z.ts; the next checks that the runner
/ closed and restored them between suites. That holds only in declaration
/ order, so the pair runs in a child resQ.
.tst.desc["Phase 1 Hardening: a leaked handle and .z.ts are put right between suites #slow"]{
  skipIf[not .tst.testState.handlestimers.canQ; "close the handle and restore .z.ts before the next suite"]{
    r: .tst.testState.handlestimers.inOrder "handles_timers.q";
    r[`code] musteq 0;
    statuses: {x`status} each r`rows;
    (count statuses) musteq 4;
    (distinct statuses) musteq enlist "pass";
  };
 };
