# Test Reporting

resQ has one human reporter and three machine reporters. Choose the contract
your consumer actually needs; do not parse the colourized console presentation
in CI.

## Selecting output

```bash
resq test tests/                         # final text summary
resq test tests/ -json -outDir reports  # JSON artifact
resq test tests/ -junit -outDir reports # JUnit XML artifact
resq test tests/ -xunit -outDir reports # xUnit v2 XML artifact
resq test tests/ -junit -json -outDir reports
```

Explicit `-junit`, `-xunit`, and `-json` flags compose with one another. Once any
machine reporter is selected, the console text report is **still printed** and
the artifact is written in addition to it: the summary, per-suite failures and
the verdict come first, then the `Report written to ...` lines. A machine
reporter never silences the human channel, so a CI log always shows why a run
failed without downloading an artifact.

Loading lines, run-audit lines, isolation progress, and diagnostics also go to
stdout/stderr. Add `-quiet` when you want quieter CI logs. `-quiet` suppresses
framework loading/audit and passing-suite presentation while keeping failures
and the summary; it cannot suppress output written directly by test code or
benchmark helpers.

To suppress resQ-owned result/report chatter entirely, use the qspec-compatible
`-pass`. It disables console and file reporters plus loading/audit chatter while
preserving the exit status. It does not intercept application/test writes or q
runtime diagnostics. The supported launcher requests quiet q startup, but
runtime/startup failures may still write their own diagnostics.

When no reporter flag is present, `resq.json` key `fmt` selects one default
format (`text`, `junit`, `xunit`, or `json`; legacy `console`/`xml` normalize to
`text`/`junit`). Explicit reporter flags take precedence. The qspec-compatible
`-pass` option suppresses every resQ result reporter and loading/audit chatter
while preserving the process exit status; application/test/runtime output is
outside that contract.

## Artifact names

Paths are relative to the directory from which resQ was invoked unless `outDir`
is absolute. Missing output directories are created.

| Selection | Artifact |
|-----------|----------|
| `-junit` | `test-results.xml` |
| `-xunit` | `test-results.xml` |
| `-json` | `test-results.json` |
| `-junit -json` | `test-results.junit.xml`, `test-results.json` |
| `-xunit -json` | `test-results.xunit.xml`, `test-results.json` |
| `-junit -xunit` | `test-results.junit.xml`, `test-results.xunit.xml` |
| all three | both schema-specific XML files and `test-results.json` |

When several formats are selected, schema-specific XML names prevent JUnit and
xUnit from overwriting each other. If one reporter cannot serialize or write,
resQ still attempts the others and then fails the run. An XML serialization
failure leaves a small parseable diagnostic document when the output file can
still be written.

## Failure detail in the artifacts

A failing comparison records its one-line summary **and** the structural diff:

```
Got +`sym`px!(`a`b`c;1 2 3f) — expected +`sym`px!(`a`b`c;1 2 4f)
--- diff ---
Table content mismatch (showing first 1 mismatches):
  Row 2:
    Col px: Exp=4f Act=3f
```

Both halves reach JSON (`failures`) and the JUnit/xUnit element body, so a CI
consumer sees which row, column or index differed — not just that two values
were unequal. The XML `message` attribute keeps only the summary line, because
XML attribute-value normalization would flatten the newlines.

The console prints the summary line in its end-of-run listing. In a normal run,
the same diff has already streamed at failure time under a
`FAILURE DIFF [suite :: test]` banner. Under `-isolate`, the parent replays the
bounded child transcript beneath the first failed/error result from that file,
so the full diff and output written by the test remain visible after the private
child scratch directory is removed.

## Console output

The text reporter is intended for diagnosis. It includes suite/test status,
timing, assertion counts, errors, and presentation-oriented diffs for mismatched
atoms, lists, dictionaries, and tables. Large values and reports are bounded to
avoid turning one failed comparison into an unbounded log.

The `FAILURE DIFF` block is emitted while an assertion runs; it is not a separate
structured field in JSON or XML. Machine reports retain the canonical assertion
or error message and the `failures` list. Keep the console log when the visual
diff is useful during incident diagnosis.

## JSON schema version 2

`test-results.json` is the most complete resQ-native report. Every format is
rendered from the same in-memory run model. The published schema is
[`schema/resq-report-v2.schema.json`](schema/resq-report-v2.schema.json); the
dependency-free `tools/validate_report.py` command validates artifacts in CI.

Its stable top-level fields are:

| Field | Meaning |
|-------|---------|
| `schemaVersion` | Currently `2` |
| `framework`, `frameworkVersion` | Producer identity |
| `run` | Unique run ID, UTC timestamps, q/resQ/OS/host, VCS/CI context, and effective configuration |
| `summary` | Counts and total duration |
| `tests` | Ordered test-result rows |
| `performance` | Benchmark time/space rows (empty when no benchmark ran) |
| `benchmarkAnalysis` | Versioned method/config/environment, comparisons, classifications, counts, and gate decision |
| `coverage` | Canonical coverage summary (empty outside coverage runs) |
| `diagnostics` | Typed run-level diagnostics |
| `flake` | Evidence thresholds, history/manifest health, policy mode, and state counts |
| `snapshotInventory` | Complete/partial snapshot roots, identities, classifications, counts, and gate decision |

The original schema-v2 core comprises `schemaVersion`, `framework`,
`frameworkVersion`, `run`, `summary`, `tests`, `performance`, `coverage`, and
`diagnostics`. Current 1.8 producers also always emit `flake`,
`snapshotInventory`, `benchmarkAnalysis`, `manifest`, and `events`, but those
post-1.0 additions remain optional to a schema-v2 reader so an artifact produced
by resQ 1.0 is still valid. When a recognized extension is present, the
published validator enforces its complete versioned contract.

Each `tests` row retains those diagnostic fields and additionally contains a
portable `file`, stable `testId`, optional top-level declarative `caseId` and
`parameters`, `kind`, retry flags and `attemptHistory`, independently identified
runtime `parameterCases`, structured `property`, `snapshots`, `benchmark`,
`quarantine` (raw evidence plus owner/reason/issue/creation/expiry), and typed
`diagnostics`. Current producers add nullable `startedAt`/`finishedAt` intervals
to tests, attempts, and runtime parameter cases. The public statuses are `pass`, `fail`,
`error`, `skip`, and `pending`. `message` and `output` are always strings and
`failures` is always a list of strings, including on passing rows. Missing
source lines serialize as JSON null. Paths beneath the invocation directory are
repository-relative; the checkout root appears once as `run.cwd`. Generated
sandbox namespaces are suppressed instead of becoming a noisy dashboard
dimension. `output` is normally empty; under process isolation the first
failed/error row for a file carries that child's bounded combined stdout/stderr.
That transcript is the child's **test** output — `show`, `-1`, library chatter,
and the structural failure diff — and stops where the child's own reporter
begins. The child's per-suite listing, summary and report-file lines are dropped:
the parent re-renders all of that from the merged rows, and the child's report
named a private scratch directory that no longer exists by the time you read it.

For `kind="fuzz"`, `property` carries the deterministic generator protocol,
effective seed, declared runs/tolerance, pass/fail totals, every failed input and
its replay token, first original/minimal input, legacy `shrunkInput`, shrink
step/candidate/duration counters, preserved failure signature, and an explicit
termination reason. Passing properties use an empty replay token/list and
`shrinkTermination="notRun"`; failing properties have exactly one replay token
per failed input. The dependency-free validator checks those invariants.

Consumers should branch on `schemaVersion`, ignore unknown fields, and use the
numeric `durationSeconds` for calculations. Do not derive pass/fail from the
process log; use the process exit code and aggregate counts.

`run.durationSeconds` is retained for compatibility and means elapsed run wall
time; `run.wallDurationSeconds` is its unambiguous alias. Likewise,
`summary.durationSeconds` is the sum of test durations and
`summary.testDurationSumSeconds` is its alias. Summed test time can exceed wall
time when isolated workers overlap and must not be used as elapsed run time.

Optional fields and classifier values may be added within schema v2 in a minor
release. The published schema and dependency-free validator therefore accept
unknown object members while continuing to enforce the original required v2
core and every recognized extension invariant; see the
[versioning policy](VERSIONING.md).

With `-snapshot-audit` or `-snapshot-gate`, the same inventory is also written
as `snapshot-manifest.json`, and lifecycle events include one
`snapshots.audited` event. A complete native shard set is recomputed by the
strict merger; individual shard manifests remain explicitly partial.

Benchmark records use `benchmarkId` as their time-series key and retain the raw
samples, workload, and environment fingerprint needed to replay a comparison.
With baseline comparison enabled, `performance[].comparison`, the owning
`tests[].benchmark.comparison`, `benchmarkAnalysis.comparisons`, the
`benchmark.finished` payload, and the run-level `benchmarks.compared` event
carry the same classification. Chart adjusted p-value and practical median
change together; neither alone represents the gate decision.

Schema v2 intentionally breaks the flat schema-v1 aggregate layout. Consumers
must read counts from `summary`, metadata from `run`, and use non-empty `caseId`
as a declarative execution identity (otherwise `testId`). Suite/description
remain presentation fields. A complete set of file/test/case shard reports can
be validated and combined with `bin/resq-merge`; its output is another valid
schema-v2 artifact with `run.shard.index=-1` and merge provenance. See
[`OBSERVABILITY.md`](OBSERVABILITY.md) for ingestion guidance.

## JUnit XML

JUnit output uses suite titles for `<testsuite name>` and testcase `classname`,
so identity remains useful across checkout directories. Suites carry the run
timestamp/hostname and the root contains resQ/q/run-ID properties. Testcases
include portable `file`/`line`, `resq-test-id`, retry count, and flaky marker.
Failures, runtime errors, skips, and pending tests map to their corresponding
JUnit elements. Property rows add a standard testcase `<properties>` block for
the generator protocol, seed, replay token, original/minimal inputs, shrink
work, termination, signature, and duration. Captured isolated-child output is
written as `<system-out>` on the row that owns the file transcript.
Quarantine rows add `resq.quarantine.*` properties without changing the
testcase failure/error element or its underlying status.

For a multiline failure, the element's `message` attribute contains a one-line
summary while the full newline-preserving message remains in the element body.
This avoids XML attribute normalization flattening the diagnostic.

## xUnit v2 XML

xUnit output uses suite titles for collection names and test `type`, with
`source-file` and `source-line` when known. Because xUnit v2 has no distinct
per-test Error result, resQ maps both assertion failures and runtime errors to
`Fail`; the failure's `exception-type` distinguishes `resQ.AssertionFailure`
from `resQ.Error`. Property telemetry uses standard per-test `<traits>` with the
same values as JUnit's property block. Captured isolated-child output is written
in the test's `<output>` element.

The assembly ID and timestamps come from the canonical run metadata. Test UUIDs
derive from `testId`, so they remain stable across checkout directories. A run
ID identifies one execution and must not be used as a test identity.

## Size limits and sensitive data

`reportLimit` (default 50,000 characters) caps a rendered failure/error message
and the isolated-child transcript retained by the parent. Large child logs keep
both their head and tail with an explicit truncation marker. The full temporary
log is never loaded into parent memory. `reportLimit` can be set in `resq.json`.
`reportListLimit` is also accepted and retained for compatibility, but the
current reporters do not apply a separate list-element cap; rendered list
content is bounded by `reportLimit`.

Failure output can contain actual values, expected values, error text, file
paths, and test-supplied messages. Treat CI artifacts as potentially sensitive;
avoid asserting directly on credentials or production records, and apply the
same retention/access controls as other build logs.
