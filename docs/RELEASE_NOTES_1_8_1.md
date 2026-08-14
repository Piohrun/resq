# resQ 1.8.1 release notes

resQ 1.8.1 is the production evidence-integrity hotfix for the superseded
`v1.8.0` release. It preserves the 1.x DSL, CLI, report-v2 compatibility, and
identity-v2 contract while repairing four release-blocking defects and the
backward-compatible evidence/cache findings discovered during cross-review.

## Release-blocking correctness repairs

- The benchmark regression gate now ranks sorted observations and applies the
  correct tie variance. Independent reference cases cover identical, reversed,
  tied, unequal, and practical-boundary distributions, so a statistical false
  green cannot hide behind the median threshold.
- Text snapshots no longer pass values through a console-width formatter.
  Snapshot-v2 records the codec and q serialization version and compares a
  full-fidelity value representation. Because a legacy text snapshot may
  already be truncated, resQ refuses to auto-migrate it: explicit update mode
  is required and the resulting diff must be reviewed. Binary snapshots are
  unchanged.
- JSON configuration now normalizes whole-valued numbers into q integer
  settings, validates list elements individually, and accepts a decimal string
  for seed-class values that cannot be represented exactly as a JSON float.
- Coverage initialization is re-entrant. Previous wrappers are restored and
  stale counters are cleared before each run, including consecutive watch
  cycles, eliminating the second-run recursion failure.

## Evidence and runtime hardening

- Partial, filtered, and sharded runs merge flake observations without erasing
  unrelated history. Only a proven complete inventory ages unseen entries;
  bounded retention and a single-writer lock protect concurrent publication.
- Malformed rerun/history caches are ignored with typed diagnostics rather than
  aborting the run. Malformed quarantine policy never grants non-blocking
  status.
- NDJSON retains run labels and hostname on every independent envelope. XML
  grouping accepts scalar string suites. Strict shard merges preserve member
  snapshot incompleteness and benchmark events carry the owning test timestamp.
- High-resolution watch fingerprints catch same-size same-second edits.
  Concurrent isolation children use private rerun state, and verifier/self-
  coverage subprocesses have deadlines, complete process-group cleanup, and
  staged publication so a timeout cannot leave partial evidence.

## Upgrade

Install the immutable `v1.8.1` tag; do not deploy or qualify against `v1.8.0`.

```sh
git clone --branch v1.8.1 https://github.com/Piohrun/resq.git ~/.local/share/resq
ln -s ~/.local/share/resq/bin/resq ~/.local/bin/resq
ln -s ~/.local/share/resq/bin/qspec ~/.local/bin/qspec
resq --version
```

If a pre-1.8.1 text snapshot reports `Text snapshot migration required`, inspect
the current value, rerun with explicit snapshot update mode, and review the
complete snapshot-v2 diff before committing it. No source change is required
for binary snapshots or existing valid report-v2 consumers.

The supported baseline remains kdb+/q 4.1.x 64-bit on Linux x86-64. The sealed
clean-clone evidence and exact tag target are recorded in the 1.8.1 production
audit shipped with the release.
