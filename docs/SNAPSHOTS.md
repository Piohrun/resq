# Snapshot Testing

resQ supports two independent snapshot backends. Choose based on what you need
from `git diff`.

---

## Text Snapshots (`mustmatchst`)

Text snapshots use a versioned JSON envelope. Equality is decided from a full,
type-and-shape-preserving canonical payload; the envelope also stores a complete
human-readable rendering for meaningful `git diff` output. Neither boundary
uses q's console-width-dependent display formatter.

Schema v2 records the resQ codec version, q version/release, the exact local
unary `-8!/-9!` leaf-fidelity mode (with no negotiated IPC connection
capability), canonical and rendering digests, and the full rendering. A codec
or q-build mismatch is an explicit migration event rather than a silent digest
change.

Because the envelope pins the exact q build, upgrading q (including patch
releases) invalidates every stored text snapshot at once: plan a one-time
update-mode run (`.tst.setUpdateSnaps[1b]`) immediately after a q upgrade and
review that rewrite as its own commit. Binary snapshots are unaffected.

### Usage
```q
.tst.desc["Order Management System"]{
  should["generate correct trade report"]{
    actual: getTradeReport[.z.d];
    / Assert against a text snapshot named "eod_report"
    actual mustmatchst "eod_report";
  };
};
```

### Storage
Text snapshots are stored as `<name>.snap.txt` in `tests/__snapshots__/`
(relative to the current working directory — run from your project root).
Override with `.tst.setSnapTxtDir["path/to/dir"]`.

### First Run and CI Safety
When a snapshot does not yet exist, resQ creates it and prints:
```
NOTE: text snapshot created: eod_report (./tests/__snapshots__) - review and commit it
```
Review the file and commit it before pushing to CI.

Under `-strict`, a **missing** snapshot is treated as a test failure with message
`Snapshot missing under -strict` rather than silently creating the file. This
prevents a missing snapshot from producing a false green in CI.

### Updating
```q
.tst.setUpdateSnaps[1b];
```
Or delete the snapshot file and re-run.

Unversioned text snapshots created before schema v2 may already contain a
console-truncated value and are therefore not trusted as equality evidence.
They fail with `Text snapshot migration required`; only explicit update mode
may replace them with v2. resQ never auto-migrates or silently blesses the old
text.

---

## Binary Snapshots (`mustmatchs`)

Binary snapshots store the actual value verbatim via `set` (q's binary
serialisation) and restore it with `get`. Exact equality is checked with `~`.

### Usage
```q
actual mustmatchs "query_output";
```

### Storage
Binary snapshots are stored as `<name>.snap` in `tests/snapshots/`
(different directory and extension from text snapshots).
Override with `.tst.setSnapDir["path/to/dir"]`.

On first run the framework creates the file and prints:
```
NOTE: snapshot created: query_output (./tests/snapshots) - review and commit it
```
Under `-strict`, the same missing-snapshot policy applies: failure instead of
silent creation.

---

## Which to use?

| | Text (`mustmatchst`) | Binary (`mustmatchs`) |
|--|--|--|
| File | `tests/__snapshots__/<name>.snap.txt` | `tests/snapshots/<name>.snap` |
| Override dir | `.tst.setSnapTxtDir` | `.tst.setSnapDir` |
| Git diff | Versioned JSON with full readable rendering | Opaque binary |
| Best for | Tables, reports, large structures | Exact binary round-trip |

Both backends honour `-strict`, `setUpdateSnaps[1b]`, and file-presence existence
checks (an empty list, dict, or table is a valid snapshot value — never confused
with "missing").

## Inventory, CI gates, and obsolete snapshots

Run a read-only inventory after the selected tests:

```bash
resq test tests -strict -snapshot-audit -json -outDir artifacts
```

This writes `artifacts/snapshot-manifest.json` and embeds the same versioned
object as `snapshotInventory` in `test-results.json`. It classifies both binary
and text snapshots as `referenced`, `missing`, `obsolete`, or `unverified`.

Only an unfiltered, unsharded, successful, completed run is complete. Filters,
last-failed selection, native shards, interrupted/failed runs, describe mode,
and isolate children are explicitly partial, so they never call an unseen file
obsolete. `tools/merge_shards.py` reconstructs a complete inventory only from a
validated complete shard set.

Use `-snapshot-gate` in CI. It implies audit and fails closed when the inventory
is partial or contains missing, obsolete, or unsafe paths. The underlying test
results are not rewritten.

Dynamic snapshot names must be declared next to their generator:

```q
.resq.snapshot.declare[`text; ("region-eu"; "region-us")];
.resq.snapshot.declare[`binary; "risk-grid"];
```

Declarations are references and never create or update files.

Obsolete removal is explicit and recoverable. Preview with
`tools/prune_snapshots.py artifacts/snapshot-manifest.json`, then repeat with
`--write`. Files move beneath `.resq/trash/snapshots/<timestamp>/` with a
`prune.json` audit record. The tool refuses partial manifests, non-obsolete
entries, symlinks, extension mismatches, nested/escaping paths, and trash
overwrites. Repeating a completed prune is safe.

Snapshot roots and existing snapshot leaves may not be symlinks. Runtime reads
and writes enforce the same containment rule as the auditor and pruner.

---

## Semantic Diffing on Mismatch
When a snapshot match fails, resQ provides a **Semantic Diff**:
- **Table Diffs**: Highlights specific rows and columns that differ.
- **Order Agnostic**: Use `mustmatchignoringorder` if row order is irrelevant.

## Best Practices
- **Avoid Dynamic Data**: Don't snapshot values containing timestamps or random
  IDs unless they are masked/mocked.
- **Granularity**: Use snapshots for data-heavy outputs. For simple values,
  `musteq` is clearer.
- **Commit snapshots** alongside the test that creates them. Run from your
  project root so paths are consistent between local and CI.
- **Gate from a complete topology**: merge all native shards before applying an
  obsolete policy; never infer obsolescence from a filtered developer run.
