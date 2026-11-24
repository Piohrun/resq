.tst.testState.tempfilecleanup.inOrder:{[name]
  wd: .utl.tempRoot[], "/resq_tempfilecleanup_order_", string[.z.i], "_", string `long$.z.p;
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
.tst.testState.tempfilecleanup.canQ: 0 < count @[system; "which q 2>/dev/null"; {()}];

.tst.desc["Phase 1 Hardening: a temporary file is gone by the next test, in declaration order #slow"]{
  skipIf[not .tst.testState.tempfilecleanup.canQ; "remove a file made with tempFile when its test ends"]{
    r: .tst.testState.tempfilecleanup.inOrder "tempfile_cleanup.q";
    r[`code] musteq 0;
    statuses: {x`status} each r`rows;
    (count statuses) musteq 2;
    (distinct statuses) musteq enlist "pass";
  };
 };

