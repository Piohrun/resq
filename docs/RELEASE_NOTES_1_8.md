# resQ 1.8.0 release notes

resQ 1.8.0 makes test loading, machine evidence, and release qualification
substantially stricter while retaining the documented qspec-compatible public
surface.

## Correct loader semantics

Test-source preprocessing is lexer-aware and bounded. DSL names inside string
literals or comments are data, same-line and nested constructors do not cause
rewrite fall-through, shadowed application locals keep native q resolution,
and application `.q` files remain byte-for-byte equivalent. The release gate
compares 400 deterministic generated scripts with native `\l`, exercises the
real oversized-constructor boundary, and enforces a preprocessing growth
budget.

## Canonical reports and lifecycle events

One canonical model now drives JSON, JUnit/xUnit, NDJSON, Allure, console, and
shard output. Normal and isolated runs must reconcile their mode-independent
summaries, stable identities, assertions, parameters, retry/quarantine state,
and verdicts. Event v2 uses native q observation timestamps and explicit
durations; event v1 remains readable, and wall duration is distinguished from
the sum of test durations. Coverage, snapshot, benchmark, and quarantine gates
remain visible in the canonical verdict instead of being inferred from test
rows alone.

## Operational evidence

Seven CI lanes separate licence-free public-fork checks from licensed runtime
correctness, coverage, compatibility, performance, hostile, and soak/scale
evidence. The release archive contains raw command logs, schemas, SHA-256
checksums, exact commit/runtime metadata, extended differential results,
normal/isolated reports, quickstart coverage reconciliation, pinned qspec and
external-pilot evidence, a 20-cycle resource soak, 10k green/failure-heavy
report budgets, and an install performed in an empty prefix.

Production support remains kdb+/q 4.1.x 64-bit on Linux x86-64. Other q
versions, macOS, Windows, optional AxLibraries self-coverage, and unlisted
external codebases/providers remain explicitly unqualified.

## Upgrade

Install the immutable release tag as shown in the README. Report schema v2 and
event v2 permit additive fields; consumers should ignore unknown fields and
continue accepting the documented event-v1 compatibility input. See the
[migration guide](MIGRATION.md), [reporting contract](REPORTING.md), and
[production audit](PRODUCTION_AUDIT_1_8.md) for details.
