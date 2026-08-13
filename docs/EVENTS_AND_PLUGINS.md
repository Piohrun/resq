# Lifecycle events, execution manifests, and plugins

Every JSON schema-v2 report produced by resQ includes two additive, independently
versioned contracts:

- `manifest` is execution-manifest schema v2;
- `events[]` is an ordered lifecycle stream whose current records use event
  schema v2; event v1 remains readable for compatibility.

The report remains the durable artifact. In-process callbacks are for trusted,
run-local integration; historical storage and network export should normally be
performed after the run from `test-results.json`.

## Event protocols v1 and v2

Each event contains `schemaVersion`, one-based `sequence`, `type`, `runId`,
`entityId`, `parentId`, `occurredAt`, and an object-valued `payload`. Sequence is
authoritative within one run. Timestamps describe the underlying lifecycle but
are not ordering keys.

Event v1 projected entity timestamps onto the run start/finish boundaries. Its
sequence and relationships remain valid, but consumers must not interpret those
timestamps as an observed test timeline. Event v2 records nullable
`startedAt`/`finishedAt` on test, attempt, and runtime parameter-case evidence,
then projects test/attempt/case events from those intervals. File and suite
boundaries are the minimum/maximum observed child intervals. Concurrent
isolated files can overlap, so v2 `occurredAt` values are intentionally not
globally monotonic; `sequence` remains the logical order.

The canonical order is:

1. `run.started`, then `manifest.published`;
2. for each selected file: `file.started`; each suite's `suite.started`; each
   test's `test.started`, attempt pairs, parameter-case pairs, optional
   `benchmark.finished`, test diagnostics, and `test.finished`; then
   `suite.finished` and `file.finished`;
3. optional `coverage.finished`, `snapshots.audited`, and
   `benchmarks.compared`, then run diagnostics;
4. `run.finished` with the same summary object as the report.

Attempt and case pairs are `attempt.started`/`attempt.finished` and
`case.started`/`case.finished`. Diagnostics use `diagnostic.recorded`. Files are
ordered by the execution manifest; suites and tests retain canonical result
order. Event projection happens from the final merged model in the aggregate
parent, so normal, repeated, isolated, concurrent-isolated, and all shard units
do not expose child completion races. Shards contain only their selected result
entities; the manifest retains the topology needed to prove that their union is
the unsharded entity set.

The checked-in validator enforces contiguous sequence numbers, run identity,
manifest linkage, ISO timestamps, and equality between `run.finished.payload`
and the report summary:

When snapshot audit is enabled, the validator also requires exactly one
`snapshots.audited` event whose payload equals the top-level
`snapshotInventory`. Individual native shards remain partial; a strict complete
merge recomputes the aggregate classifications and event.
When benchmark comparison is enabled, it likewise requires exactly one
`benchmarks.compared` event equal to top-level `benchmarkAnalysis`; individual
`benchmark.finished` events carry the owning measurement and comparison.

```bash
tools/validate_report.py reports/test-results.json
```

Event schema changes follow the public versioning policy. Additive payload
members do not change the current version; a required-field removal, field-type change,
or semantic reinterpretation requires a new event schema version.

## Execution manifest v2

`manifest.files[]` records a stable `fileId`, repository-relative path,
line-normalized source digest, deterministic assigned shard, whether the file
was selected in this shard, and whether it is shardable. `manifest.tests[]` is
the execution inventory: each entry has an `executionId`, parent `testId`,
optional declarative `caseId` and parameters, stable suite/file identities,
display/source metadata, deterministic `assignedShard`, and selection state.
For test/case sharding the complete inventory appears in every member; file
shards retain the complete source inventory and their selected test inventory.
The manifest also carries VCS provenance, framework version, shard metadata,
and the public test/case identity algorithm.

`manifest.digest` is deterministic across repeated runs, isolation worker
counts, every member of one shard topology, and relocated checkouts with
identical repository-relative source. It changes when the shard topology or
case-declaring source changes because it covers the sorted complete source-file
inventory, source digests, assignments, manifest format, and framework version.
The strict merger separately validates the execution-inventory union. The MD5-based digest
is a reproducible merge/identity key, not a cryptographic attestation; validate
the separately recorded VCS revision when provenance is security-sensitive.

`run.shard.unit` is `file`, `test`, or `case`. `test` keeps all declarative
cases under their parent test; `case` assigns each declarative row separately.
Ordinary tests and runtime-created `parametrize`/`forall` cases remain atomic.
`selectedExecutionIds` states the exact result set a complete shard must emit.

Merge a complete topology with the fail-closed companion tool:

```bash
bin/resq-merge artifacts/*/test-results.json --out-dir artifacts/merged
```

It validates manifest schema/digest, VCS revision, q/framework/configuration,
all shard indices, source digests, assignments, duplicate/missing result IDs,
snapshot and benchmark ownership, then merges result rows, diagnostics,
coverage, bounded coverage contexts, snapshot inventory, raw benchmark samples,
and benchmark comparisons. Holm correction and the benchmark gate are
recomputed over the complete union. A missing/aborted/fail-fast shard is
rejected with exit 2 rather than represented as a complete run. Exit 1 means a
valid merged run has a failing test or coverage verdict; exit 0 is green.
Framework results created after discovery (for example a strict plugin error)
are marked non-shardable. Every shard remains independently truthful, while the
merger coalesces identical run-level rows once and rejects inconsistent copies.

## Trusted in-process plugins

Plugin files are ordinary q source loaded before test discovery:

```bash
resq test tests -plugin tools/my_resq_plugin.q -json
resq test tests -plugin first.q,second.q -strict-plugins
```

Configuration equivalents are `"pluginFiles": [...]` and
`"strictPlugins": true`. Files load in declared order. Registration by the same
name replaces the prior callback, which keeps repeated/watch bootstrap
idempotent.

The public API is:

```q
.resq.registerObserver[`name; {[event] / called once per canonical event }];
.resq.registerReporter[`name; {[model;events] / called once after the run }];
.resq.unregisterObserver `name;
.resq.unregisterReporter `name;
.resq.clearPlugins[];
.resq.setStrictPlugins 1b;
```

Observer and reporter return values are ignored. Around each invocation resQ
restores the canonical result table, pass bit, and diagnostic list, so a return
value or direct mutation of those verdict structures is not authoritative.
Callback exceptions are trapped. By default they emit a `plugin` warning and
the test verdict remains unchanged; strict policy records a canonical
`PLUGIN_FAILURE` error row and makes the process fail. One failing observer
stops delivery only to that observer; other observers/reporters are still
attempted. Only the aggregate parent dispatches callbacks under process
isolation.

### Trust boundary

This is resilience, not a security sandbox. A plugin executes arbitrary q in
the application process and can mutate other globals, access the filesystem or
network, replace framework functions, or terminate q before a trap can recover.
Load only reviewed plugin files from the same trust domain as the test suite.
Use the JSON artifact and external adapters for untrusted or remote
integrations. Plugin loading failure is fatal because the requested integration
was never installed; callback failure follows the lenient/strict policy above.
