# resQ 2.2.1 release notes

resQ 2.2.1 fixes defects that a qspec suite moving to `bin/qspec` would meet
on its first run. It keeps the 2.x DSL, CLI, report-v2 contract and the
`resq-test-case-id-v3` identity algorithm. The defects were found by running a
work-style qspec suite through upstream qspec and `bin/qspec` and comparing
the results, then generating every pairing of DSL constructors.

## Property tests that failed to load

A `holds` whose `vars` was a dictionary, list or generator function, or whose
`maxFailRate` was an integer, failed its whole test file with a bare `'type`.
This happened whenever it shared a `desc` with any other expectation: a
`should` before it, or, for an integer `maxFailRate`, anything after it.
Across every ordered pair of the 13 DSL constructor forms, 43 of 169 files
failed to load. Upstream qspec runs all of them, and resQ now does too.

Every expectation is a row of one q table. The first row fixes each column's
type, and the in-place append `,:` signals `'type` when a later row does not
fit. The constructors now append through `.tst.appendExpecs`, which promotes
such columns instead. It also fills the before/after columns of rows that
follow an `alt` block, which `,:` used to do implicitly.

## qspec's value domain under bin/qspec

Native `holds` takes one typed sample in four from an edge pool that includes
nulls and infinities. qspec never generated either, so a qspec property with no
guard for them could go red on its first resQ run. Under `bin/qspec` and
`-qspec-compat`, the edge pool now keeps only values qspec's own generator
could produce:
- `-1`, `0` and `1` for `short`/`int`/`long`;
- `0` and a tiny positive value for `real`/`float`.

The 75% of samples drawn from the broad domain already fell inside qspec's
ranges. Native `resq test` keeps the full edge pool.

A typed `boolean` variable is now always a boolean. Three samples in four were
long `0`/`1` (`0b+word mod 2` is a long in q), and generated boolean lists were
long lists.

## Unwritable state no longer fails a run

Rerun and flake history live in `.resq/` under the working directory. When it
could not be written (a read-only checkout, or a `.resq/` owned by another
user), a green suite failed with "Framework phase 'rerunState' failed: type".
The state-write traps used two-argument error handlers. q passes a handler
only the error, so each returned a projection, and the caller's `not` on it
signalled `'type`. These writes are now the warning diagnostics they were
meant to be, and the run passes or fails on its tests alone.

An uncreatable flake-history lock also busy-waited 5 s on every run and then
blamed "another live writer". The run now skips that wait and names the
unwritable state directory. A lock held by a live process behaves as before.

## Upgrading from 2.2.0

No source changes are needed. `-state-file PATH` and `-flake-history PATH`
move the state files out of the working directory. A property-test failure
replay token reproduces only under the mode (native or `-qspec-compat`) that
produced it. [Migrating from qspec](MIGRATION.md) now covers the state
directory and how `holds` samples in each mode.
