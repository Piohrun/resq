# Continuous Integration

## Production baseline

The release-gated runtime is q 4.1.x on Linux x86-64. The
[compatibility matrix](COMPATIBILITY_MATRIX.md) defines that support boundary
and verifies normal, isolated, concurrent, randomized, and sharded result
equivalence:

```bash
tools/verify_execution_matrix.py --q q
```

## Licence-free gate

The `static` CI job runs on GitHub-hosted Linux before the licensed q job. It
checks both launcher scripts with `bash -n`, validates the checked-in JSON v2
and JUnit/xUnit contract fixtures, parses the public JSON Schema, resolves every
repository-local documentation link, verifies the distributable file layout
and executable bits, and runs the Python adapter tests. Run the same gate
locally without q:

```bash
bash -n bin/resq bin/qspec
tools/verify_static.py
python3 -m unittest discover -s tools/tests -v
```

This keeps documentation and integration contracts protected on contributors'
ordinary runners. It does not replace the licensed execution suite; the q job
depends on it and remains the authority for runtime behavior and generated
artifacts.

## Nightly differential corpus

The [nightly workflow](../.github/workflows/nightly.yml) runs the two riskiest
source transformations against deterministic extended corpora on the licensed
runner: the resQ test loader is compared with native `\l`, and combined
statement/branch instrumentation is compared with uninstrumented execution,
including return values, errors, side effects, and q's post-call random state.
Scheduled defaults are 400 loader seeds and 2,000 coverage seeds;
manual dispatch can override either count.

Each failure names its exact seed. Reproduce a nightly run locally with:

```bash
RESQ_LOADER_DIFF_SEEDS=400 RESQ_COVERAGE_DIFF_SEEDS=2000 \
  resq test tests/test_loader_differential.q \
    tests/test_coverage_differential.q -strict
```

The normal suite retains 40 and 75 seeds respectively. Values are bounded and
validated (loader 1–5,000; coverage 1–10,000), so a malformed environment value
fails explicitly instead of silently reducing the corpus. The nightly artifact
records both configured counts alongside the versioned JSON result.

## Hostile-environment gate

The licensed CI job also runs `tools/verify_hostile_env.py --q q`. It qualifies
the process/filesystem boundary with a symlinked install and hostile path
characters, verifies the selected q reaches isolated children, checks live
temporary-directory permissions, interrupts concurrent unbounded children,
proves they are reaped, and exercises both successful and failed artifact
writes. See the [hardening audit](HARDENING_AUDIT.md) for the complete contract
and deliberate limits.

The production CI baseline is a strict, process-isolated run with at least one
machine-readable reporter:

```bash
resq test tests/ -strict -isolate -isolateTimeout 120 \
  -junit -json -outDir artifacts/tests
```

`-strict` rejects empty, all-skipped, and assertion-free green runs. `-isolate`
runs every test file in a separate q process, so `exit`, an infinite loop, or a
process-fatal error becomes a per-file error while the remaining files still
run. The `resq` launcher also supervises whole-run completion, so an unexpected
`exit 0` cannot turn a non-isolated CI command green. Add `-isolateWorkers N`
to run N files at once; verdicts, ordering and exit codes are unchanged, only
wall-clock (see [PARALLEL.md](PARALLEL.md)). Use
CI matrix jobs with `-shard-index I -shard-count N` to shard beyond one
machine. The default is one worker; increase it only after accounting for
memory and q licence capacity.

Coverage must run as a separate, non-isolated command because instrumentation
and subprocess isolation cannot be combined truthfully:

```bash
resq cover tests/ --source src/ -strict -cov-statements -cov-branches \
  -cov-functions-min 80 -cov-lines-min 75 -cov-completeness-min 100 \
  -cov-branches-min 70 -cov-branch-completeness-min 100 \
  -junit -json -outDir artifacts/coverage
```

Declare production roots with `--source`; otherwise a module no test loads
cannot enter any denominator. Include `-cov-statements` for measured statement
records and `-cov-branches` for true/false conditional edges. Both rewrite modes
publish instrumentation completeness. Their gates fail closed on partial
denominators (line coverage has an explicit `-cov-allow-partial` escape hatch;
branch coverage deliberately does not).

`-cov-min N` accepts an integer from 0 through 100 and exits 1 when function
coverage is below the threshold. The JSON report's `coverage.basis` field is
`"functions"`; line counts remain available alongside it when requested. A run
that cannot measure code or write its coverage reports also fails closed.
Prefer the independent gates shown above for new pipelines. Branch coverage is
conditional-edge coverage for eligible `if`, `while`, and `$` conditions, not
path coverage or MC/DC; detailed site/edge identities and fallback reasons are
available in `coverage.json`.

## Reporter artifacts

A single XML reporter writes `test-results.xml`. When multiple formats are
selected, resQ uses unambiguous names:

| Selection | Files |
|-----------|-------|
| `-junit` | `test-results.xml` |
| `-xunit` | `test-results.xml` |
| `-json` | `test-results.json` |
| any multi-format selection | `test-results.junit.xml`, `test-results.xunit.xml`, and/or `test-results.json` |

JUnit testcases include portable `file` and `line`, run metadata, stable resQ
identity, and retry/flaky attributes; xUnit v2 tests include the corresponding
`source-file`/`source-line` and stable UUID. Skip reasons are preserved. JSON
schema version 2 adds a `run` envelope, `summary`, stable tests/cases, attempt
history, property seeds, benchmarks/snapshots, and typed diagnostics. Validate
it with `tools/validate_report.py`. If one reporter fails, resQ still attempts
the others and the overall run exits non-zero.

Machine reporter flags ADD an artifact; they do not replace the console report.
A `-junit -json` run still prints the failure list, summary and verdict, then
the paths it wrote — so a failing job is diagnosable from the log alone. Add
`-quiet` for quieter logs (failures and the summary survive it) and see
[Test reporting](REPORTING.md) for the full output contract.

## Runner requirements

The checked-in [workflow](../.github/workflows/ci.yml) expects a self-hosted
Linux x64 runner labeled `kdb`. The runner needs:

- kdb+/q 4.1.x on `PATH`, with its valid KX license available through `QHOME` or
  `QLIC`;
- Bash, `mktemp`, `chmod`, `rm`, and `rmdir` for the supervised launcher;
- GNU `timeout` with `--kill-after` plus `sh` for process isolation;
- Python 3 for independent JSON/XML artifact validation.

The core in-process test command requires only q. The bundled launchers require
the marker tools above so premature `exit 0` fails closed. Process-isolation
dependencies are checked before child execution and an unavailable tool fails
isolation instead of silently falling back to the shared process.

KX requires a license for every 64-bit q runtime. Provision the interpreter and
license on the runner, or inject the license through your organization’s secret
management; never commit it. See KX's
[installation](https://code.kx.com/q/learn/install/) and
[licensing](https://code.kx.com/q/learn/licensing/) documentation.

Use an immutable runner image or record the q build in job logs. Before upgrading
q, run the same workflow on the old and new builds and compare the JSON results.

### Trust boundary

`-isolate` contains test-process failures; it does **not** sandbox test code.
Each child runs as the invoking user and inherits filesystem access, environment
variables, network access, and credentials. Do not run untrusted pull-request
code on a privileged self-hosted runner, and expose only secrets required by
the tests. Reports can contain actual/expected values and error text, so treat
retained artifacts as potentially sensitive.

`-isolateWorkers N` starts up to N q children simultaneously. Account for the
memory footprint and KX licence capacity of those concurrent runtimes; start at
1 and raise the value only after measuring the runner.

## Parallel jobs

For a large project, use the native zero-based file shard in each matrix job:

```bash
resq test tests/ -strict -isolate \
  -shard-index "$MATRIX_INDEX" -shard-count "$MATRIX_COUNT" \
  -junit -json -outDir "artifacts/tests-$MATRIX_INDEX"
```

Assignment uses canonical sorted paths before optional seeded ordering. Shards
are disjoint and their union is the unsharded file set; an intentionally empty
shard succeeds even under `-strict`. Each shard gets a separate rerun-state
suffix, preventing concurrent cache writers. Give every shard a distinct
artifact directory/name. A shard can also use `-isolateWorkers N`. CI systems
can merge the resulting JUnit documents; resQ does not share mutable q state
between shards. See
[Parallel test execution](PARALLEL.md) for the trade-offs.
