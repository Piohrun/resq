# Snapshot Testing

resQ supports two independent snapshot backends. Choose based on what you need
from `git diff`.

---

## Text Snapshots (`mustmatchst`)

Text snapshots serialise the actual value to a plain `.txt` file using `.Q.s1`
and compare it against the stored text on subsequent runs. The file is human-
readable and produces meaningful `git diff` output.

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
| Git diff | Human-readable plain text | Opaque binary |
| Best for | Tables, reports, large structures | Exact binary round-trip |

Both backends honour `-strict`, `setUpdateSnaps[1b]`, and file-presence existence
checks (an empty list, dict, or table is a valid snapshot value — never confused
with "missing").

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
