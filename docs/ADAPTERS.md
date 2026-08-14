# External report adapters

resQ keeps historical storage and third-party SDKs outside the q test process.
Both checked-in adapters validate JSON report schema v2 before emitting
anything, preserve stable IDs, and require only Python's standard library.

## NDJSON event stream

```bash
tools/resq_to_ndjson.py artifacts/test-results.json \
  --output artifacts/resq-events.ndjson
```

The stream contains one `resq.run` event followed by `resq.test` events and any
`resq.benchmark` events. Every independently consumable record carries `runId`,
hostname, the validated bounded `run.labels`, framework/schema versions, VCS,
and CI context; the run payload retains the same labels. Test payloads retain `testId`, `caseId`, attempts,
typed diagnostics, properties, snapshots, and benchmarks unchanged. Send this
stream to OpenTelemetry collectors, ReportPortal transforms, log pipelines, or
a warehouse without reconstructing identity from display names.
The run record includes `benchmarkAnalysis`; each benchmark event retains raw
samples, stable identity, environment, and its corrected comparison.

The converter writes records incrementally instead of assembling the complete
NDJSON body in memory. Standard-library JSON decoding is not incremental, so it
checks the input size before decoding and defaults to a documented 256 MiB
ceiling. Change it deliberately with `--max-input-bytes`; inputs above the
ceiling fail before allocation. Records carry the source `profile` and
`completeness`; sections omitted by a compact profile are absent from the run
record rather than synthesized as empty evidence.
To keep each record bounded, `resq.run.run.shard` replaces the two unbounded
identity/path arrays with `selectedExecutionIdCount` and
`selectedFilePathCount`. `recordSchema` and `recordOmissions` declare that
adapter-level normalization; individual `resq.test` records retain the join
identity.

## Allure 2 results

```bash
tools/resq_to_allure.py artifacts/test-results.json artifacts/allure-results
allure generate artifacts/allure-results
```

The adapter maps pass/fail/error/skip to Allure status, uses `testId` as
`historyId`/`testCaseId`, derives a run-specific deterministic UUID, preserves
tags and flake state as labels, and writes executor/environment metadata. Use a
fresh output directory per run so files from an older invocation cannot be
mistaken for current results.
Allure `start`/`stop` are emitted only when the test row contains an observed
interval (current event-v2 reports). Legacy event-v1 reports lack per-test
observations, so the adapter omits timeline fields instead of fabricating them
from run boundaries.
Benchmark tests add ID/classification/change/adjusted-p-value parameters, while
`environment.properties` carries comparison/gate state and classification
counts.

## Extension policy

The versioned JSON document is the supported integration boundary. In-process
event observers and end-of-run reporters have a public versioned lifecycle, but
remain trusted code in the application q process. Prefer stateless
post-processors of schema v2 for remote or untrusted integrations. See
[Lifecycle events, execution manifests, and plugins](EVENTS_AND_PLUGINS.md).
