# 📝 Text-Based Snapshots & Semantic Diffing

Snapshots allow you to assert against large, complex data structures without hard-coding expected values in your test files. `resQ` introduces **Text-Based Snapshots**, which are serialized into human-readable formats for better Git visibility.

## The Problem
Hard-coding a 50-row table as an expected value makes tests unreadable and difficult to maintain. Binary snapshots solve this but are opaque to version control (you can't see what changed in a PR).

## The Solution: `mustmatchst`
The `mustmatchst` assertion (Must Match Snapshot Text) serializes the actual value to a `.txt` file using `.Q.s1` and compares it against a stored reference.

### Usage
```q
.tst.desc["Order Management System"]{
  should["generate correct trade report"]{
    actual: getTradeReport[.z.d];
    / Assert against a snapshot named "eod_report"
    actual mustmatchst "eod_report";
  };
};
```

## Storage & Git
Snapshots are stored in `tests/__snapshots__/` by default (relative to project root).
- **Human Readable**: You can open these files in any text editor.
- **Git Diffs**: When a snapshot changes, your `git diff` or PR view will show exactly which rows or columns modified in plain text.

## Updating Snapshots
If a code change legitimately changes the output, enable updates for the run (or delete the old snapshot file). For example:

```q
.tst.setUpdateSnaps[1b];
```

## Semantic Diffing
When a snapshot match fails, `resQ` doesn't just say "failed". It provides a **Semantic Diff**:
- **Table Diffs**: Highlights specific rows and columns that differ.
- **Order Agnostic**: If you use `mustmatchignoringorder`, the diff engine will only highlight items missing from either set, rather than reporting offset errors.

## Best Practices
- **Avoid Dynamic Data**: Don't snapshot values containing timestamps or random IDs unless they are masked/mocked, as they will cause snapshots to fail every run.
- **Granularity**: Use snapshots for data-heavy outputs (tables/JSON-like dicts). For simple status codes, standard `musteq` is better.
