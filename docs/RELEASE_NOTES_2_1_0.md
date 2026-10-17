# resQ 2.1.0 release notes

resQ 2.1.0 makes `bin/qspec` a drop-in for qspec suites that CI scripts run
with `q .../qspec/app/spec.q <args>`. It preserves the 2.x DSL, CLI, report-v2
contract, and the `resq-test-case-id-v3` test/case identity algorithm.

Earlier releases compared resQ only with resQ's own reading of qspec. For this
release, real third-party qspec suites ran through upstream qspec and through
`bin/qspec`, and every difference was either fixed or listed with a reason.
That comparison now ships as a release gate.

## Switching a script from qspec

Change the command and keep the arguments:

```bash
q /opt/qspec/app/spec.q --junit --only=pricing* tests > results.xml   # before
/opt/resq/bin/qspec     --junit --only=pricing* tests > results.xml   # after
```

q's own options (`-s`, `-w`, `-q`) can stay. With qutil installed the usual way
(its bootstrap loaded from `q.q`), `.utl.require "mypkg"` keeps working. See
[Migrating from qspec](MIGRATION.md).

## qspec drop-in repairs

- Discovery: `bin/qspec` loads every `.q` file under a directory, as qspec
  does (`-qspec-discovery`). It previously loaded only `test_*.q` and
  `*_test.q`, so an unprefixed qspec tree ran no tests.
- JUnit on stdout: with `--junit`/`--xunit` and no `-outDir`, the XML report
  goes to stdout and the console to stderr, so `> results.xml` captures a
  valid report.
- JUnit testcase names: `bin/qspec` writes qspec's names (`should ...`, no
  `classname`) through the new `-junit-names qspec`, so a CI server's test
  history continues across the switch.
- qutil: resQ no longer replaces qutil's `.utl.require`, `.utl.PKGLOADING` or
  `.utl.DEBUG`; package names go to qutil. `bin/qspec` preloads
  `qutil/opts.q` as qspec's `spec.q` does.
- `--name=value` option spellings from qutil's parser (`--only=pricing*`,
  `--exclude=slow*`, `--fdl=5`) are accepted.
- Infix assertions with `\:`, `/:` or `':` (`x mustin\: y`) keep their adverb;
  they previously failed the whole file with a blank q error.
- Root-namespace loading on the qspec path lets a helper file define names
  that later files use; spec-free helper files are counted, not flagged.
- A `desc` holds about 118 `should` blocks again (it stopped near 78).
- A helper that redefines one of resQ's `.tst` internals is reported by name
  and the framework definition is restored.
- `.tst.testFilePath` is available.

## Upgrading from 2.0.x

These defaults change for `bin/qspec` only; `resq test` is unaffected:

- More files may be discovered. Pin the old behaviour with `testFilePatterns`
  in `resq.json` if a tree holds `.q` files that are not tests.
- JUnit testcases carry qspec's names. Pass `-junit-names resq` to keep
  resQ's suite-title `classname` and bare descriptions.
- Files load into the root namespace rather than a per-file sandbox.

## Other changes

- `.resq/` writes its own `.gitignore` (everything except
  `quarantine.json`), so a first run leaves `git status` clean.
- Failure messages render tables and dictionaries as q literals; durations
  print at a readable scale; a passing suite prints one line.
- Loading and running a 3,000-test suite takes about 6.6 s instead of
  30-34 s.
- A Grafana evidence dashboard over tables v2 adds drill-down, delta and
  alert panels.
- q 4.0 (KX build 2023.08.11) is verified but not release-gated; see the
  [compatibility matrix](COMPATIBILITY_MATRIX.md).

## Evidence

- [`tools/verify_qspec_differential.py`](../tools/verify_qspec_differential.py)
  runs pinned nugend/qspec, nugend/qutil and asatirahul/cryptoq suites (135
  testcases over five script-style runs) through both runners. Names and
  verdicts match apart from five of qspec's own private-API tests, listed with
  reasons in [`pilots/qspec-differential.json`](../pilots/qspec-differential.json).
- The self-suite no longer leaks run settings between files: `-strict` and
  `-qspec-compat` now hold for every file of a run, and the `-qspec-compat`
  self-suite run passes.
