# resQ 2.3.0 release notes

resQ 2.3.0 adds mutation testing, makes watch mode follow what tests actually
load, lets a q process run a suite without exiting, and fixes a set of loader,
isolation and failure-output defects found on production-style code. It keeps
the 2.x DSL, the report-v2 contract and the `resq-test-case-id-v3` identity
algorithm. The CLI only gains options.

## Mutation testing

```sh
resq mutate src/pricing.q
```

`resq mutate` plants one small change at a time in a function and re-runs the
tests that call it. A change that no test fails on is reported with its file,
line and column: it marks behaviour nothing checks.

- No source file is edited or copied. Each mutant runs in its own q process,
  which loads the tests as usual and then redefines the one function in
  memory. It therefore works whatever loader a project uses.
- A kill is reported only when the child recorded that the mutant was in
  place. A failure for another reason is retried and then reported as not
  assessed.
- `-since REV` mutates only the lines changed since a git revision, which is
  the quick way to check the tests written for a change.
- In a git checkout the report lists files that were created, changed or
  deleted while mutants ran, with the mutant responsible. A mutant of code
  that writes files can write to the wrong place; resQ reports it and undoes
  nothing.

Options, the JSON report and the limits are in
[the mutation testing guide](MUTATION.md).

## Watch mode follows loads

`resq watch` used to map `src/foo.q` to `test_foo.q` by name. A second test
file that loaded `foo.q` was skipped without a word. Watch now reads which
file loads which from source and re-runs every test that loads what changed,
directly or through other files.

- Any literal naming a `.q` file counts, whatever function consumes it, so a
  project's own loader works. One defined outside the watched directories is
  named with `watchLoaders` in `resq.json`.
- A test that reaches a load with no fixed target (a computed path, a module
  name, a directory) re-runs on every source change. Watch lists those loads
  at startup.
- Two defects are fixed with it. The "run all tests" fallback ran no tests,
  and an edit to a file loaded through `.utl.require` was not re-read.

See [watch mode](WATCH.md).

## Running a suite from a q process

`.resq.run[paths;options]` runs tests inside an existing q process and
returns structured results instead of exiting. It restores the caller's state
afterwards and can be called repeatedly. See [embedded execution](EMBEDDED.md).

## Applications that need root globals or their own arguments

- `-root-load` (`rootLoad` in `resq.json`) loads test files into the root
  namespace instead of a per-file sandbox. An application that returns to
  root with `\d .` defines its globals there, where a sandboxed test cannot
  reach them by bare name.
- `-args` ends resQ's own options. What follows is left for the application
  under test (`.resq.appArgs`, `.z.x`) and passed on to `-isolate` children.
- `resq test -- -name.q` works for a path that starts with a dash.
- A `#!` first line in a test file is skipped, as q does.

## Isolation says what happened

- When a `-isolate` child hangs, exits or is killed, the failure names the
  test that was running, and the tests that had already finished keep their
  results.
- Background processes a test file started and left running are terminated
  when the file finishes, with a warning that names the file.
- `bin/qspec -isolate` loads files into the root namespace, as `bin/qspec`
  does without `-isolate`.

## `-strict` rejects an empty `must` condition

"All of no items hold" is true, so `must[names like "a*"; ...]` passed when
`names` was empty, having checked nothing. Under `-strict` that is now a
failure. Without `-strict` it still passes, as it does in qspec.

The rule is for `must` itself. Assertions that compare lists item by item
(`mustlt`, `mustlike`, `mustin`, ...) still pass on an empty operand, and so
does `must` inside `holds`: empty data is ordinary there.

## Failure output

- A failing assertion on a large value no longer renders the whole value
  before truncating. A failed `musteq` on a 2M-row table took 79 seconds and
  now takes under one. The truncation marker is `... [truncated; md5=<digest>]`.
- A runaway recursion keeps its 20 innermost and 10 outermost frames and says
  how many were left out, instead of adding about 1,800 frames to every report.
- Failure messages show floats as they are typed (`2f`) and enumerated symbols
  as symbols. Report evidence and identities keep their exact form.

## Loader fixes

- An infix assertion whose left operand follows a word, such as
  `count x musteq 3`, was rewritten into one fused name and failed at run time.
- A test file the loader cannot bind is that file's load error. It used to
  abort the whole run, so no other file ran.
- A `.z` callback mocked while unset is unset again after the test.

## qspec migration

- A parity tool compares a workplace qspec command with the `bin/qspec`
  equivalent test by test and keeps the evidence. See
  [qspec migration parity](QSPEC_PARITY.md).
- Library initialization works under nested native and qutil loads, and when
  qutil already supplies `.utl.require`.

## Upgrading from 2.2.2

No source changes are needed. Three things can look different:

- A suite run with `-strict` may go red where the condition given to `must`
  was an empty list. The message says so; write the non-empty check the test
  meant.
- Watch mode may re-run more test files than before, because it now runs
  every test that loads the changed file.
- Anything that parsed the old truncation marker in failure messages needs the
  new text.
