# resQ 2.4.0 release notes

resQ 2.4.0 is a hardening release. A full audit of 2.3.0 looked for anything
that could change a verdict, lose a result, leave a process behind or break
under another environment; every finding is fixed here, along with a few
found while fixing them. It keeps the 2.x DSL, the report-v2 contract and the
`resq-test-case-id-v3` identity algorithm. The full list is in the
[changelog](../CHANGELOG.md).

## Runs that can now fail

Several gates were off without saying so. They now apply, so a run that was
green on 2.3.0 can be red on 2.4.0 for a real reason:

- A `resq.json` that cannot be applied as written (invalid JSON, a misspelled
  key, a value of the wrong type) stops the run with `CONFIG ERROR` and exit 1.
  It used to warn and drop the setting, so `{"strict": true,}` ran without
  strict.
- `coverageFunctionMin`, `coverageLineMin` and `coverageCompletenessMin` in
  `resq.json` are enforced; they were stored and never checked.
- `.utl.require` signals when a file cannot be loaded, which is a load error
  for the test file (exit 4). It printed a warning and the test ran without
  the code it asked for.
- An assertion that fails in `after`, `beforeAll`, `afterAll` or while a file
  loads now fails something. It was printed and ignored.
- Under `-strict`, an empty test file and an `-isolate` file that declares no
  tests fail, as a file without tests already did in process.
- `-noquit` and `"exit": false` no longer turn a failing run green through the
  launcher.
- `resq.json` is found from a subdirectory. A run started in `tests/` now
  reads the project's file, with its `strict` and thresholds.

## Interrupts and dead launchers

- Ctrl+C, SIGTERM and a closed terminal stop the run. resQ starts nothing new,
  writes no report and no state, prints `resQ: interrupted.` and exits with the
  signal's status (130, 143, 129, 131). Before, the second before the launcher
  killed q was enough to start the next isolated batch and to write a
  "timeout" row, an `error` flake observation and a `-last-failed` entry.
- A launcher killed outright (SIGKILL, the OOM killer) no longer leaves q and
  its children running. q notices, stops its children, removes the guard
  directory and exits 137; each launcher also removes guard directories left
  by such runs.
- When q dies in the middle of an in-process run, the launcher names the test
  and the file that were running.
- `bin/qspec --junit`, `--xunit` and `--xml` forward signals, and an
  interrupted `-isolate` run stops its children on machines without `setsid`
  and `pkill`.

## Isolation

- `-isolateWorkers N` is a worker pool: the next file starts as soon as one
  ends. Sixteen files, four of them slow, went from 13.2 s to 5.2 s on four
  workers. Output is unchanged and still in file order. (`resq mutate` still
  runs its mutants in groups.)
- A child's captured output is capped while it runs; the start and the end are
  kept and the report says what was dropped. A test that printed in a loop
  wrote 6.3 GB in four seconds before.
- `-isolate` and `resq mutate` work where `timeout` lacks `--verbose` (GNU
  coreutils before 8.29, busybox).

## State: last-run, flake history, quarantine

- The flake history is kept one test to a line, and a run reads only the
  entries it needs: with 9,000 known tests a run of one file takes 0.40 s
  instead of 1.75 s. Schema and file name are unchanged; an old history is
  converted the first time it is saved.
- A run of some files no longer ages or forgets what is known about the
  others: state entries record their file, and a run speaks only for the files
  it looked at.
- A lock left by a killed run is reclaimed, also in containers where its PID
  is reused.
- The quarantine manifest is never moved, and it applies under any q build: a
  team on q 4.0 and q 4.1 shares one committed manifest. A manifest entry with
  an empty expiry is invalid instead of quarantining for ever.
- State problems are said on the console, once, in one line.

## `resq.json` from a subdirectory

resQ reads the nearest `resq.json` from the directory it starts in up to the
top of the checkout. When that file is further up, its directory is the
project directory: the file's own paths, `.resq/`, the default snapshot
directories and test IDs are relative to it, so a run from `tests/` shares
`-last-failed` and the flake history with a run from the top, and resQ says
which file it read. Paths typed on the command line, and the default report
directory, stay relative to where you are.

## Loading test files as qspec does

- resQ words (`it`, `skip`, `pending`, `retry`, `before`, `after`, `fixture`,
  ...) are qualified only where they are applied, so a qSQL column or an
  application variable with such a name works. A symbol that contains one is
  left alone.
- Block comments nest, and a comment that starts at column 1 inside a test
  block no longer fails the file.
- `\l src/app.q` in a test file no longer changes directory while the file
  loads.
- A test file that replaces a resQ function by accident fails by name instead
  of ending the run; a qspec suite may keep its own helpers in `.tst`; a
  repeated test description no longer stops the run.
- resQ's helpers moved from `.utl` to `.resq.util`, so a codebase with its own
  `.utl` namespace works. The old spellings are still offered where the name
  is free.

## Reports

- JUnit, xUnit and JSON stay well-formed whatever bytes a suite contains, and
  JSON is valid whatever values a test uses.
- JSON numbers are written with 17 significant digits instead of q's display
  precision.
- A run removes the reports it is about to write when it starts, so a run that
  dies does not leave the previous green report behind.
- JUnit testcases that would share a classname and name carry their file.

## Messages

- Nulls print as literals (`Got 1 0N 3`), inexact floats as the shortest
  digits that read back (`0.30000000000000004`), and a snapshot mismatch is a
  failed assertion with its diff.
- A statement that signals while a file loads is reported with its line.
- Command-line mistakes give one line instead of a q trace; `resq -v` and
  `resq --help | head` work.

## Also fixed

- A directory fixture could load the project directory as a database, which
  runs the q scripts in it, whenever the test's namespace held an in-memory
  table.
- More of what a suite changes is put back for the next one (deleted
  namespace members, every message handler, the timer, `\P`, `\c`); mocks set
  in `beforeAll` last for the suite; mocking a view is refused.
- `resq mutate` no longer counts an outside SIGKILL as a kill, and
  `-mutation-min` counts unassessed mutants as undetected.
- The Python report tools work on Python 3.8 to 3.10.
- resQ's own suite passes in any order, and the release gate runs its
  isolated lane in random order.

## Upgrading from 2.3.0

No source changes are needed for suites that were correct. Check:

- the gates listed under "Runs that can now fail";
- tooling that parsed JSON numbers at 7 digits, or JUnit classnames of
  same-named tests in different files;
- a project run from below its root, which now reads the project's
  `resq.json` and keeps `.resq/` at the project.
