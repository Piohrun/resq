# Embedded execution

Load resQ once in an existing q application, then call `.resq.run[paths;options]`.
The function runs synchronously, returns a dictionary, and does not call `exit`.
It supports repeated calls without requiring the caller to configure private
`.tst.app` variables or invoke runner phases.

```q
system "l /opt/resq/lib/init.q";
r:.resq.run["tests";(enlist `strict)!enlist 1b];
r`exitCode
r`results
/ Your harness decides whether to continue, report, or terminate.
```

Use separate processes for side-by-side qspec comparisons: both implementations
own `.tst`, so loading both into the same process is unsupported. See
[qspec parity](QSPEC_PARITY.md) for migration evidence against workplace suites.

## Inputs

`paths` is a nonempty string, symbol, symbol vector, or list of strings/symbols.
Paths may name files or directories and are resolved from the caller's working
directory. Directory discovery defaults to `test_*.q` and `*_test.q`.

`options` is a symbol-keyed dictionary; use `()!()` for defaults. Every call starts
from resQ defaults. It does **not** read `resq.json`, inherit CLI switches, or
consume existing rerun/quarantine history. Unknown keys, invalid values, and
invalid paths' *types* signal a q error before test files are loaded. A path
that does not exist is a run/discovery failure in the returned result.

| Options | Values / behavior |
| --- | --- |
| `strict`, `qspecCompat`, `failFast`, `runPerformance` | Boolean; default `0b`. `failFast` stops scheduling further expectations while completing cleanup. |
| `runSpecs`, `excludeSpecs` | Suite-name patterns, using the normal config normalization. |
| `testFilePatterns` | Nonempty filename pattern(s), e.g. `enlist "*.q"`. |
| `maxTestTime`, `fuzzLimit` | Nonnegative integers; existing runner semantics. Time checks do not interrupt arbitrary blocking q code. |
| `randomOrder`, `seed` | Boolean and nonnegative seed for reproducible ordering. |
| `runCoverage` | Boolean; default `0b`. Requires an explicit `outDir`. |
| `coverageSources`, `covStatements`, `covBranches` | Existing coverage source/boolean options; require `runCoverage:1b`. |
| `outDir` | Nonempty path string or symbol. Coverage artifacts go here. |

Modes and controls such as `exit`, `failHard`, `isolate`, watch, sharding,
reporter selection, and persistent-history options are unsupported here and are
rejected. Use the launcher for these features. `qspecCompat` selects the
compatibility semantics documented in the [compatibility contract](QSPEC_COMPATIBILITY.md);
it does not select every `bin/qspec` discovery/startup behavior.

## Result contract

The returned dictionary has `schemaVersion:1j` and these fields:

| Field | Meaning |
| --- | --- |
| `exitCode` | `0` success; `1` assertion/runtime/cleanup/framework failure or no result rows after filtering; `3` no discovered files and no result rows; `4` file loading/discovery errors. |
| `passed` | Exactly `0=exitCode`. |
| `results` | Canonical result table, including ordinary tests and synthetic framework/load/cleanup errors. Includes identities, status, messages, assertions, attempts, and diagnostics. |
| `diagnostics` | Run-level typed diagnostics. |
| `loadErrors` | Table with `file`, `error`, and `type` columns. |
| `frameworkError` | String for an exception at the API setup/finalization/restoration boundary; otherwise `""`. Framework phase failures inside the runner appear in `results`/`diagnostics`. |

Load failures take precedence over ordinary failed tests. An API boundary or
restoration exception forces code `1`. Strict mode can classify a file with no
tests as a load failure and add a separate no-execution error. `results` uses the
existing [result-row contract](REPORTING.md); this dictionary is not the full
JSON report envelope. Retain the returned dictionary: the caller's previous
`.resq.state.results` is restored when the call finishes.

The API suppresses the normal end-of-run reporter. Test output, loading/cleanup
warnings, fail-fast diagnostics, and coverage artifact messages may still print.
Existing registered observer/reporter plugins run under the usual runner policy.

## State and cleanup

Each call has its own fixture, mock, deferred, cleanup, and suite registries.
The runner tears down session fixtures, restores mocks and coverage wrappers,
clears deferreds, and releases its sandboxes. The API also drains cleanup tasks
left behind by a failed file load and checks for run-wide leaked handles.
Cleanup failures are returned as failed results; they do not become success
just because the assertions passed.

Afterward resQ restores the caller's `.tst`, `.resq`, and `.utl` namespace state,
working directory, current q namespace, timer interval, and these callbacks,
including removal of callbacks that were originally undefined:

```
.z.ts .z.pg .z.ps .z.pc .z.po .z.ph .z.pp .z.ws .z.exit
```

The host timer is suspended during setup; tests can change it themselves.
Host fixtures and queued cleanup tasks are preserved without executing them.
A nested run, an already-running runner, active/pending coverage, or existing
resQ mocks is rejected before loading tests. Restore mocks/coverage first.
Restoration failures force a failed result and are included in `frameworkError`;
the caller should not treat a failed restoration as a clean host state.
Private history files live in a unique temporary directory removed at return;
the API requires the supported Linux environment with `mktemp` and `rm`.

This is a trusted in-process execution boundary. Tests can still call `exit`,
block indefinitely, delete files, change other process settings, or mutate
application data. It does not roll back database/file writes or arbitrary
application globals. Handle cleanup cannot recreate a host handle closed by a
test. For process containment, use the supervised launcher and `-isolate`.

## Coverage

```q
/ Register preloaded source through the resQ/qutil loader, or load it in tests.
.utl.require "/work/service/src/pricing.q";
opts:`strict`runCoverage`coverageSources`outDir!
    (1b;1b;enlist "/work/service/src";"/tmp/service-coverage");
r:.resq.run["/work/service/tests";opts];
```

A native load performed before resQ started may not be in the loader registry;
`coverageSources` inventories source but does not by itself register prior
native loads for instrumentation. Coverage artifacts intentionally persist in
`outDir`; internal instrumentation and measurement state are restored at return.
See [coverage](COVERAGE.md) for measurement semantics.

The fresh-process regressions in `tests/test_embedded_run.q` exercise repeated
success/failure, missing and empty suites, filtering, fail-fast, callbacks,
non-root namespace calls, load-time resources, teardown failures, nested calls,
coverage (including injected restoration failure), qutil loader preservation,
temporary-directory failures, and setup exceptions followed by recovery.
