# resQ 2.2.0 release notes

resQ 2.2.0 halves runner overhead and makes `bin/qspec --xunit` produce
qspec's own report file. It preserves the 2.x DSL, CLI, report-v2 contract,
and the `resq-test-case-id-v3` test/case identity algorithm.

## Faster runs

| Run | 2.1.0 | 2.2.0 | upstream qspec |
|---|---:|---:|---:|
| 3,000 trivial tests in 100 files | about 7 s | about 3 s | about 0.6 s |
| one 30-test file | about 0.5 s | about 0.37 s | about 0.11 s |

Measured on one Linux workstation; timings vary by a few tenths of a second
between runs. Most of the per-test cost was reading the working directory:
`system "cd"` with no argument takes about a millisecond in q because it goes
through a shell, and resQ read it for every test so it could restore the
directory afterwards. resQ now reuses the directory it just restored and reads
it fresh whenever user code may have changed it in between (a `beforeAll`
hook, a spec cleanup), so directory behaviour is unchanged.
[`tests/test_working_directory.q`](../tests/test_working_directory.q) pins that
behaviour.

Smaller savings: the run model is not built twice when no plugin is
registered, the loader's infix-assertion scan skips names absent from a line,
file sharding reuses the execution inventory, and flake history is validated
column-wise.

What remains is mostly resQ's own bookkeeping: loading rewrites each test file
to bind the DSL and record source lines, and every run reads, merges and
rewrites the flake history for all known tests.

## qspec's --xunit file

qspec's `--xunit` report is its own format: a bare `<test-suite>` root, a
`<test-suite>` per spec with `reports`/`skips`/`tests`/`errors`/`failures`/
`test-cases` attributes, and a `<test-case name label errors failures skip
tests>` per test. resQ wrote xUnit.net v2 (`<assemblies>`), so a CI step that
parses qspec's file would have broken on the switch.

`bin/qspec` now writes qspec's format (`-xunit-format qspec`). On the pinned
cryptoq suite the file is byte-identical to upstream qspec's; on qutil's suite
every test verdict and suite attribute matches, including its failures. The
upstream qspec differential compares both `--junit` and `--xunit` runs: 7 runs,
194 testcases. Pass `-xunit-format xunit2` to keep xUnit.net v2.

## Other changes

- `bin/qspec --junit` with the XML on stdout no longer deletes other reports
  requested in the same run (such as `-json`); they land in the working
  directory. The console says the XML went to stdout instead of naming a
  scratch file.
- The licensed q CI jobs run only when the repository variable
  `RESQ_KDB_RUNNER` is `true`. Without a registered runner they show as
  skipped instead of sitting in GitHub's queue for a day; see
  [Continuous Integration](CI.md#runner-requirements).
- [Migrating from qspec](MIGRATION.md) lists the three cases where
  `bin/qspec` exits differently from qspec on purpose: a filter that leaves no
  test, no test files, and a file that fails to load.

## Upgrading from 2.1.0

Only `bin/qspec --xunit` changes output. Pass `-xunit-format xunit2` if a
consumer already reads resQ's xUnit.net v2 file from `bin/qspec`.
