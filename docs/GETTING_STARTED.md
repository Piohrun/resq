# Getting Started

This guide takes a project from installation to a CI-ready resQ run. If you are
replacing qspec, start with the compatibility path below; existing test files do
not need to be rewritten first.

## 1. Check the runtime

The supported production baseline is kdb+/q 4.x on Linux. Put `q` on `PATH` and
make its licence available through your normal KX setup (`QHOME` or `QLIC`).

```bash
q -q <<< 'show .z.K; exit 0'
```

The normal in-process runner needs only q. The supplied `resq` and `qspec`
launchers need Bash, `mktemp`, `chmod`, `rm`, and `rmdir` for their private
completion marker. Process isolation additionally needs GNU `timeout` with
`-k` support and `sh`; see
[Continuous Integration](CI.md#runner-requirements).

## 2. Install the launchers

```bash
git clone --branch v0.4.0 https://github.com/Piohrun/resq.git ~/.local/share/resq
ln -s ~/.local/share/resq/bin/resq ~/.local/bin/resq
ln -s ~/.local/share/resq/bin/qspec ~/.local/bin/qspec
resq --version
resq --help
```

Pin the release tag for anything automated; `main` moves. Drop `--branch` only
when you want the development tip.

The launchers preserve the caller's working directory, so relative test paths
and `resq.json` resolve against your project. They also fail closed if test or
application code calls `exit 0` before the runner completes. If you invoke q
directly, set `RESQ_HOME` and use `q "$RESQ_HOME/resq.q" ...`; direct invocation
prints the premature-exit diagnostic, but q does not allow `.z.exit` to replace
the requested status, so use the launcher in CI.

## 3A. Replace qspec without rewriting tests

Keep the command your project already uses:

```bash
qspec tests/
```

The `qspec` launcher selects resQ's test mode and enables `-qspec-compat`. The
public qspec test DSL, assertions, fixtures, mocks, fuzz tests, performance
blocks, and legacy runner flags are source-compatible. resQ deliberately does
not reproduce qspec's private runner/reporter APIs or byte-for-byte console
format.

Before changing the command used in CI:

1. Run the complete existing suite through the `qspec` launcher.
2. Check any scripts that parse qspec's human console text. Prefer resQ's JSON or
   JUnit report instead.
3. Add `-strict` and fix tests that pass without executing an assertion.
4. Adopt native `resq test` only when you want resQ's stricter whole-value
   `musteq`/`mustne` semantics.

The exact compatibility boundary and comparison differences are in
[Migrating from qspec](MIGRATION.md).

## 3B. Write a new resQ test

Create `tests/test_math.q`:

```q
.tst.desc["Math"]{
  should["add two numbers"]{
    (2 + 3) musteq 5;
  };
};
```

Run it:

```bash
resq test tests/
```

Directory discovery matches `test_*.q` and `*_test.q` by default. Explicit `.q`
file paths always run regardless of those patterns. Use `-desc` to list tests
without executing them:

```bash
resq test tests/ -desc
```

## 4. Use strict mode in automation

```bash
resq test tests/ -strict
```

`-strict` prevents three false greens: no executed tests, an all-skipped suite,
or a passing `should` block that made no assertion. A block's return value is not
an assertion; use `must[condition; "message"]` or another assertion helper.

The normal exit codes are:

| Code | Meaning |
|------|---------|
| `0` | All tests passed |
| `1` | A test, hook, cleanup, reporter, strict check, or coverage gate failed |
| `3` | No test files were found without `-strict` |
| `4` | A test file could not be loaded or an explicit path was missing |

## 5. Add resilience and reports

A conservative CI command is:

```bash
resq test tests/ -strict -isolate -isolateTimeout 120 \
  -junit -json -outDir artifacts/tests
```

Isolation runs every test file in a child q process, so `exit`, a hang, or a
process-fatal error becomes a per-file error. It is a resilience boundary, not a
security sandbox: children retain the invoking user's filesystem, environment,
network, and credentials. Only run trusted tests, especially on privileged CI
runners.

The default is one child at a time. After establishing a stable baseline, use
bounded local concurrency if the runner has enough memory and q licences:

```bash
resq test tests/ -strict -isolate -isolateWorkers 4 \
  -isolateTimeout 120 -junit -outDir artifacts/tests
```

Reporter flags select machine reporters instead of the final text summary. Add
`-quiet` to suppress loading/audit chatter, and read
[Test reporting](REPORTING.md) before wiring a parser to the artifacts.

## 6. Add coverage separately

Coverage and process isolation cannot be combined. Run a second command:

```bash
resq cover tests/ -strict -cov-min 80 -json -outDir artifacts/coverage
```

Default coverage measures whether each function was entered and emits no line
records. Add `-cov-statements` only when you need measured statement/line data;
it rewrites q function bodies at load time and should be validated against your
suite. See [Runtime code coverage](COVERAGE.md).

## 7. Optional project configuration

Put `resq.json` in the directory where you invoke resQ:

```json
{
  "strict": true,
  "outDir": "artifacts/tests",
  "testFilePatterns": ["test_*.q", "*_test.q"]
}
```

`qNamespaceExports` defaults to `true` for qspec compatibility. New projects can
set it to `false` after adopting fully qualified `.tst.*` DSL and assertion
names rather than unqualified aliases.

## Where to go next

- [API reference](API_REFERENCE.md) — DSL, assertions, CLI, and configuration
- [Test reporting](REPORTING.md) — console, JSON, JUnit, and xUnit contracts
- [Continuous Integration](CI.md) — runner prerequisites and production gates
- [Fixtures](FIXTURES.md) — setup, injection, teardown, and cleanup
- [Troubleshooting](TROUBLESHOOTING.md) — common failures and diagnostics
