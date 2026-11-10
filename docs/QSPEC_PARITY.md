# Compare a workplace qspec suite with resQ

`tools/qspec_parity.py` runs your existing qspec command and resQ in separate
processes, compares testcase inventories and verdicts, and retains evidence for
an agent or developer to investigate differences. It needs Python 3 and the
runtimes required by your commands. Process supervision targets Linux/POSIX.

## Configure the actual commands

Save a configuration beside your project (relative working directories resolve
beside this file):

```json
{
  "schemaVersion": 1,
  "cwd": ".",
  "timeoutSeconds": 300,
  "env": {
    "QPATH": "/opt/q/packages",
    "QINIT": "/opt/q/startup/qutil-only.q"
  },
  "upstream": {
    "command": ["/opt/legacy/bin/qspec", "--junit", "tests/"]
  },
  "resq": {
    "command": ["/opt/resq/bin/qspec", "--junit", "tests/"]
  },
  "expectedDifferences": []
}
```

Use your real startup paths and flags; omit `env` if inherited settings are
already correct. Use resQ's `bin/qspec` compatibility launcher to preserve
comparison semantics, discovery and testcase names. The tool does not insert
flags, rewrite tests, install packages, or replace the old runner.

```bash
python3 /opt/resq/tools/qspec_parity.py parity.json --out-dir evidence/first-comparison
```

The evidence directory must not exist. Reusing a directory is rejected so a
crashed command cannot accidentally contribute an old report. Commands are argv
arrays, passed directly without a shell. For an existing shell script, invoke
that script explicitly. There is no expansion of `$VARIABLE`, `~`, or globs in
arguments. Prefer absolute executable paths or paths relative to each runner's
working directory.

Both commands inherit one snapshot of the caller's environment plus shared
`env`. Each runner can override `cwd` and `env`; JSON `null` unsets a variable.
For example, use a resQ-specific `QINIT` if the old startup also loads qspec.
Do not load both frameworks into one process. The report records override
names, not environment values; retain the configuration separately to reproduce
it. Its SHA-256 is included in the evidence. Commands and test logs are retained
verbatim, so keep credentials out of command arguments.

Runners execute sequentially, upstream first. They execute trusted test code
with the caller's permissions. The tool does not copy your project or reset
application data. For stateful suites, prepare equivalent disposable workspaces
and set each runner's `cwd` accordingly. Keep source revision, inputs, seeds,
selection and dependencies equivalent; reset external services yourself.
Timeouts terminate the process group, including children that ignore TERM.

## Reports and identities

By default, the command must print JUnit XML or qspec's `--xunit` XML to stdout.
Leading startup chatter is accepted; malformed XML, multiple reports, missing
reports, empty inventories and contradictory exit statuses fail the comparison.
Single `<testsuite>` JUnit roots are accepted. xUnit.net v2 is not supported.
Declared testcase totals, when present, must match the inventory.

For a wrapper that writes a report file, set `"report": "file"` and include
`"{report}"` in its command arguments. The tool replaces that token with a new
absolute report filename in the evidence directory. For example:

```json
{
  "command": ["./run-tests-with-report", "--xml-file", "{report}"],
  "report": "file"
}
```

This requires a wrapper with that argument; the tool does not imply that qspec
has a `--xml-file` option. Arbitrary preexisting report paths are not accepted.

Identity is the exact `(suite, testcase name, occurrence)` tuple. Occurrence
starts at 1 for each repeated suite/name pair in report order. Punctuation and
names ending in `#2` cannot collide with duplicate numbering. Distinct names may
be reordered without changing parity. Duplicate names have no independent
identity in legacy reports: keep their order stable, or give them unique names.

The tool compares `pass`, `fail`, `error`, `skip`, and `absent`. It retains
failure/error/skip messages and captured output for investigation, but does not
require diagnostic wording or timing to match. Use `--junit` on both commands,
or `--xunit` on both, to compare the same reporting surface.

## Known differences

Each allowance identifies one exact transition and needs a reason:

```json
{
  "suite": "Legacy assertions",
  "name": "should accept null",
  "occurrence": 1,
  "upstream": "pass",
  "resq": "fail",
  "reason": "MIG-42: resQ intentionally rejects a null must condition"
}
```

Put entries in `expectedDifferences`. `occurrence` defaults to 1. Wildcard
allowances are not supported. An allowance fails if the difference disappears
or changes status, preventing stale exceptions from silently accumulating.
Duplicate allowances and same-status transitions are invalid. Allowances never
suppress timeouts, missing reports, empty inventories, or exit/report conflicts.

## Results and evidence

| Exit | Meaning |
|---|---|
| 0 | Testcase parity, including any explicitly accepted differences |
| 1 | Unexpected testcase differences or stale allowances |
| 2 | Invalid configuration/output destination or runner/report failure |

**Parity does not mean that both suites passed.** `suitesGreen` is separate: it
requires at least one passing test in each run, no failing/error tests, and no
execution/report problems. Two identically failing suites can have parity with
`suitesGreen: false`; two all-skipped suites are not green either.

The output directory contains:

- `parity.json`: versioned result (`schemaVersion: 1`, kind
  `resq-qspec-parity`), commands/cwds, exit codes, durations, status counts,
  full testcase inventories with diagnostics, accepted/unexpected differences,
  stale allowances, execution problems, configuration digest and artifact hashes.
- `summary.txt`: concise human-readable result and difference list.
- `upstream.stdout`, `upstream.stderr`, `resq.stdout`, `resq.stderr`: raw logs.
- `upstream.xml` / `resq.xml` when configured for file reports.

Both runners are attempted even if one fails. Timeouts and launch failures
retain logs and a failing summary. Invalid configuration is rejected before
commands execute. An interrupted invocation may leave partial logs without a
summary; it is not successful evidence.

This measures reported test behavior. It cannot prove that an omitted test was
intended to exist if both runners omit it, detect a wrapper replaying cached XML,
or prove equivalent database contents, teardown side effects, or live service
behavior. Inspect those separately and treat the actual work-repository run as
the qualification evidence.

## Repository verification

Licence-free behavior tests are part of `tools/verify_python_contracts.py`.
The licensed integration runs the public CLI against all eight pinned qspec
comparison cases (including qutil, cryptoq and the documented private-API
exceptions):

```bash
python3 -m unittest tools.tests.test_qspec_parity_integration -v
```
