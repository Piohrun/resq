# Lifecycle events, execution manifests, and plugins

Every JSON schema-v2 report produced by resQ includes two additive, independently
versioned contracts:

- `manifest` is execution-manifest schema v1;
- `events[]` is an ordered lifecycle stream whose records use event schema v1.

The report remains the durable artifact. In-process callbacks are for trusted,
run-local integration; historical storage and network export should normally be
performed after the run from `test-results.json`.

## Event protocol v1

Each event contains `schemaVersion`, one-based `sequence`, `type`, `runId`,
`entityId`, `parentId`, `occurredAt`, and an object-valued `payload`. Sequence is
authoritative within one run. Timestamps describe the underlying lifecycle but
are not ordering keys.

The canonical order is:

1. `run.started`, then `manifest.published`;
2. for each selected file: `file.started`; each suite's `suite.started`; each
   test's `test.started`, attempt pairs, parameter-case pairs, optional
   `benchmark.finished`, test diagnostics, and `test.finished`; then
   `suite.finished` and `file.finished`;
3. optional `coverage.finished`, then run diagnostics;
4. `run.finished` with the same summary object as the report.

Attempt and case pairs are `attempt.started`/`attempt.finished` and
`case.started`/`case.finished`. Diagnostics use `diagnostic.recorded`. Files are
ordered by the execution manifest; suites and tests retain canonical result
order. Event projection happens from the final merged model in the aggregate
parent, so normal, repeated, isolated, concurrent-isolated, and file-sharded
runs do not expose child completion races. Shards contain only their selected
entities; the union is the unsharded entity set.

The checked-in validator enforces contiguous sequence numbers, run identity,
manifest linkage, ISO timestamps, and equality between `run.finished.payload`
and the report summary:

```bash
tools/validate_report.py reports/test-results.json
```

Event schema changes follow the public versioning policy. Additive payload
members do not change schema v1; a required-field removal, field-type change,
or semantic reinterpretation requires a new event schema version.

## Execution manifest v1

`manifest.files[]` records a stable `fileId`, repository-relative path,
line-normalized source digest, deterministic assigned shard, whether the file
was selected in this shard, and whether it is shardable. `manifest.tests[]`
records stable test/suite/file identities and display/source metadata for the
tests represented by this artifact. The manifest also carries VCS provenance,
framework version, shard metadata, and the public test-identity algorithm.

`manifest.digest` is deterministic across repeated runs, isolation worker
counts, every member of one shard topology, and relocated checkouts with
identical repository-relative source. It changes when the shard topology
changes because it covers the sorted complete source-file inventory, source
digests, assigned shards, manifest format, and framework version. The MD5-based digest
is a reproducible merge/identity key, not a cryptographic attestation; validate
the separately recorded VCS revision when provenance is security-sensitive.

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
