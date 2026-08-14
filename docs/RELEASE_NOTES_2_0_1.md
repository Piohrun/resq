# resQ 2.0.1 release notes

resQ 2.0.1 is a polish release closing the residual findings from the v2.0.0
cross-review audit. It preserves the 2.x DSL, CLI, report-v2 contract, and the
`resq-test-case-id-v3` test/case identity algorithm.

## Correctness repairs

- Diagnostic IDs (`resq-diagnostic-id-v4`) hash the diagnostic's canonical
  typed value bytes instead of rendered JSON, removing the last
  display-precision (`\P`) dependency from an identity boundary. Test and case
  IDs are unchanged. Diagnostic IDs are run-scoped event identities, not
  cross-run join keys; the shard merger already requires one framework version
  across shards, and it now reuses q-emitted `diagnostic.recorded` event IDs
  for shard-owned diagnostics rather than recomputing them, minting local IDs
  only for merged-run entities that have no q counterpart.
- Coverage recording is guarded by a re-entrancy latch and every probe and
  bookkeeping entry point is excluded from function wrapping, so explicitly
  instrumenting resQ's own framework helpers no longer recurses. The
  lifecycle fixture proves two context-attributed cycles with a wrapped
  recorder-path helper.
- The formatter-boundary gate applies q's real comment rule: an iterator `/`
  glued to code no longer hides the rest of its line, so a console formatter
  after an adverb is detected.

## Evidence hardening

- The Fable findings ledger meta-test runs in the licence-free contracts lane,
  and P0 findings pin their fixed-state source patterns via `closedProbe`, so
  a "closed" status asserts the baseline bug pattern is gone rather than only
  that a regression selector exists.

## Documentation

- Isolation names its GNU coreutils `timeout --verbose` requirement and the
  degraded behavior without it.
- Text snapshots document that a q upgrade (including patch releases) is a
  bulk migration event requiring one explicit update-mode rewrite; binary
  snapshots are unaffected.
- The identity contract documents the diagnostic-ID construction and the
  merger's reuse rule.
