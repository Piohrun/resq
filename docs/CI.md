# Continuous Integration

The production CI baseline is a strict, process-isolated run with at least one
machine-readable reporter:

```bash
resq test tests/ -strict -isolate -isolateTimeout 120 \
  -junit -json -outDir artifacts/tests
```

`-strict` rejects empty, all-skipped, and assertion-free green runs. `-isolate`
runs every test file in a separate q process, so `exit`, an infinite loop, or a
process-fatal error becomes a per-file error while the remaining files still
run. Local isolation is deliberately sequential; use CI matrix jobs when wall
time matters.

Coverage must run as a separate, non-isolated command because instrumentation
and subprocess isolation cannot be combined truthfully:

```bash
resq cover tests/ -strict -cov-min 80 \
  -junit -json -outDir artifacts/coverage
```

`-cov-min N` accepts an integer from 0 through 100 and exits 1 when the LCOV
line percentage is below the threshold. If no line records exist it falls back
to the function percentage. A run that cannot measure code or write its
coverage reports also fails closed.

## Reporter artifacts

A single XML reporter writes `test-results.xml`. When multiple formats are
selected, resQ uses unambiguous names:

| Selection | Files |
|-----------|-------|
| `-junit` | `test-results.xml` |
| `-xunit` | `test-results.xml` |
| `-json` | `test-results.json` |
| any multi-format selection | `test-results.junit.xml`, `test-results.xunit.xml`, and/or `test-results.json` |

JUnit testcases include `file` and `line`; xUnit v2 tests include `source-file`
and `source-line`. Skip reasons are preserved. JSON schema version 1 keeps
`message` as a string and `failures` as a list on every row, and exposes an
aggregate `assertionCount`. If one reporter fails, resQ still attempts the
others and the overall run exits non-zero.

## GitHub Actions runner

The checked-in [workflow](../.github/workflows/ci.yml) expects a self-hosted
Linux x64 runner labeled `kdb`. The runner needs:

- kdb+/q 4.x on `PATH`, with its valid KX license available through `QHOME` or
  `QLIC`;
- GNU `timeout` with `--kill-after`, plus `mktemp`, `chmod`, `rm`, and `sh` for
  process isolation;
- Python 3 for independent JSON/XML artifact validation.

KX requires a license for every 64-bit q runtime. Provision the interpreter and
license on the runner, or inject the license through your organization’s secret
management; never commit it. See KX's
[installation](https://code.kx.com/q/learn/install/) and
[licensing](https://code.kx.com/q/learn/licensing/) documentation.

Use an immutable runner image or record the q build in job logs. Before upgrading
q, run the same workflow on the old and new builds and compare the JSON results.

## Parallel jobs

For a large project, shard directories across jobs. Give every shard a distinct
artifact directory/name and retain `-strict -isolate` in each job. CI systems
can merge the resulting JUnit documents; resQ does not share mutable q state
between shards.
