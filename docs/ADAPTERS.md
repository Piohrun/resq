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
`resq.benchmark` events. Every record carries `runId`, framework/schema
versions, VCS and CI context. Test payloads retain `testId`, `caseId`, attempts,
typed diagnostics, properties, snapshots, and benchmarks unchanged. Send this
stream to OpenTelemetry collectors, ReportPortal transforms, log pipelines, or
a warehouse without reconstructing identity from display names.

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

## Extension policy

The versioned JSON document is the supported integration boundary. In-process
event observers and end-of-run reporters have a public versioned lifecycle, but
remain trusted code in the application q process. Prefer stateless
post-processors of schema v2 for remote or untrusted integrations. See
[Lifecycle events, execution manifests, and plugins](EVENTS_AND_PLUGINS.md).
