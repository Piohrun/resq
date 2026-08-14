# Stable test and case identity

Machine consumers and persistent selection/flake state use resQ-generated
identities, not display labels, rendered q values, or sandbox namespaces.

## Algorithm v3 (resQ 2.x)

The execution manifest declares `identityAlgorithm` as
`resq-test-case-id-v3` and records an `identityCodec` envelope. Inputs are byte
framed before hashing:

```text
frame(tag, payload) = "(" + byteLen(tag) + ":" + tag + ":" +
                      byteLen(payload) + ":" + payload + ")"
```

`testId` is:

```text
payload = frame("file", repoRelativeFile) +
          frame("suite", suite) +
          frame("description", description)
"test_" + hex(md5(frame("resq-test-id-v3", payload)))
```

`caseId` is:

```text
payload = frame("testId", testId) +
          frame("caseIndex", decimalZeroBasedIndex) +
          frame("parameters", canonicalTypedBytes(parameters))
"case_" + hex(md5(frame("resq-case-id-v3", payload)))
```

The canonical typed-value codec recursively frames q type, shape, count, list
items, dictionary keys/values, and table structure. Scalar and simple-vector
leaves contain the hexadecimal bytes from q unary IPC serialization (`-8!`).
Consequently `1i`, `1j`, and `1f` are different identities, values with a long
common prefix remain distinguishable, and console width/precision cannot affect
the result. The envelope records codec name/version, q version/release, IPC
serialization mode, and capability level. A mismatch is an explicit migration
event; upgrading q must never silently rewrite identity-bearing state.

Diagnostic IDs use the same length-delimited construction with their parent,
index, and exact public JSON diagnostic bytes. Other textual IDs use an
explicitly framed UTF-8/text byte entry point. Production identity, equality,
snapshot, assertion, and XML paths may not use console display formatters; a
licence-free static gate enforces that boundary.

MD5 is used only as a compact deterministic label. These IDs and manifest
digests are not signatures, secrets, or a security boundary.

## Historical algorithm v2 (resQ 1.x)

Identity v2 joined file/suite/description and case fields with newlines and
rendered case parameters through q's console formatter. It remains the frozen
1.x contract, but its output could depend on console geometry and could collide
after display truncation. Version 2.0 intentionally replaces it rather than
changing IDs inside a 1.x release.

## What remains stable

A v3 test keeps its ID across checkout roots, CI hosts, q processes with the
same recorded codec envelope, normal versus isolated execution, worker counts,
ordering seeds, shards, console widths/precision, and line-number-only edits. A
parameter case keeps its ID when its parent identity, zero-based case position,
typed parameter value, and codec envelope remain unchanged.

`shouldEach` declarative rows are first-class executions: each row is registered
during discovery, emitted as a top-level result carrying both `testId` and
`caseId`, and can therefore be assigned by `-shard-unit case` without running
the body during discovery. Existing `.tst.parametrize` and `.tst.forall` calls
create cases only while their enclosing test body runs; they remain nested in
`parameterCases[]` and shard atomically with that parent test.

## What intentionally changes identity

- moving/renaming the test file relative to the invocation repository root;
- changing suite or test description;
- changing a parameter value, q type/shape, or case index;
- changing the identity algorithm or canonical-value codec envelope;
- invoking an external test file outside the repository from a different
  absolute location (external paths remain absolute rather than fabricated).

Within one run, `(repo-relative file, suite, description)` must be unique.
Duplicate descriptions in the same suite/file deliberately collide and are not
valid observability identities. Parameter cases likewise require deterministic
order.

## Persistent state and migration

Rerun state, flake history, quarantine manifests, and generated quarantine
proposals use state schema v2 and contain both `identityAlgorithm` and
`identityCodec`. A legacy or mismatched cache is never joined to current IDs:
resQ moves it to an adjacent `*.identity-mismatch.<digest>.bak`, names that
archive in a diagnostic, and rebuilds non-authoritative history from new runs.
Quarantine policy remains blocking until explicitly migrated or reviewed.

When old and new full reports describe the same inventory, migrate a state file
with an independently written destination:

```bash
tools/migrate_identity_state.py \
  --old-report artifacts/v1/test-results.json \
  --new-report artifacts/v2/test-results.json \
  --state .resq/last-run.json.identity-mismatch.<digest>.bak \
  --output .resq/last-run.migrated.json
```

The tool maps semantic inventory entries and refuses missing, changed,
duplicate, or ambiguous pairings. It never modifies the source or overwrites an
existing destination. Shard merging likewise rejects mixed identity algorithms
or codec envelopes before attempting a join.

`run.id` identifies one invocation and must never be used for test history.
Generated sandbox `namespace` is suppressed from machine dimensions. For
dashboards use `caseId` as the execution key when non-empty and `testId`
otherwise; retain display fields only as labels.
