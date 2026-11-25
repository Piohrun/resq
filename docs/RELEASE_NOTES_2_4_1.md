# resQ 2.4.1 release notes

resQ 2.4.1 is a patch release. It finishes the follow-ups to the 2.4.0 audit
and fixes what a measurement of resQ's q-source scanners against q's own
tokenizer found, over 3,240 distinct q files (resQ, TorQ, KX's tick and TAQ
scripts, KX's VS Code fixtures and other code). It keeps the 2.x DSL, the
report-v2 contract and the `resq-test-case-id-v3` identity algorithm. The
full list is in the [changelog](../CHANGELOG.md).

## Test files are read as q reads them

- A multi-line string keeps its text. The loader read each line on its own,
  so a line that continued a string looked like code: `should[x]` in it
  became `.tst.shouldEntry[2][x]`, `a musteq b` became
  `.tst.dsl.musteq[a;] b`, a bracket in it made the statements after the
  string run as one, and `it: x` in it made `it` look like a name the file
  defines. On every corpus file that q accepts in full, the loader's
  statements are now q's.
- A system command continued on the next line is one command
  (`\t a:select ... from trade` with an indented ` where ...`).
- A line that starts with `:` is loaded as written; `:x` became `x`.

## resq mutate

- `-isolateWorkers N` runs the baseline and the mutants through the worker
  pool `-isolate` uses: the next child starts as soon as one ends, instead of
  each group of N waiting for its slowest child.
- A `k)` line no longer hides the functions after it (2 of 15 in KX's
  `csvutil.q` were found), and a function followed by a tab
  (`f:{x+1}<tab>/ note`) is no longer left out. k code itself is not mutated.

## Discover, coverage and the dependency graph

- `resq discover` and coverage list only the functions a file defines. A
  function inside a block comment, a value computed by a lambda
  (`x:{...} getenv y`, `x:{...}[]`) and a helper defined inside a `desc`
  block or a lambda kept by index were listed, and counted in the function
  coverage denominator.
- The dependency graph reads `\l dep.q / note` as a load of `dep.q`.

## Runs and processes

- `-last-failed` runs the whole selection, and says so, when none of the
  tests that failed last time is in it. It ran nothing and exited 1, so
  `resq test tests/test_b.q -last-failed` failed whenever last run's
  failures were in another file.
- Ctrl+C prints only `resQ: interrupted. ...`, however early it comes; it
  printed a q trace, a false load error or a failure diff in the first
  half-second, and nothing when q had to be killed.
- An isolated run no longer leaves its output watch behind: a stopped watch
  left its `sleep` running for a moment (reported as a leftover process), and
  a watch whose wrapper ended abnormally looped for ever. A leftover warning
  now names the processes.

## Also fixed

- `.tst.describe` is resQ's `desc`; it was q's `desc` (sort descending).
- The release gate's syntax step checks all three launchers.

## Upgrading from 2.4.0

No source changes are needed. Results can differ where 2.4.0 was wrong:

- function coverage can change, because values and commented-out functions
  no longer count as functions;
- `resq mutate` can report more mutants, from functions after a `k)` line or
  followed by a tab;
- `-last-failed` runs tests where it ran none and exited 1;
- a `\` command followed by indented lines now takes them, as q does: a
  `\d .ns` or `\l` with indented code after it now fails as under native q.
  None of the 3,240 corpus files is written so.
