# resQ 2.2.2 release notes

resQ 2.2.2 fixes `perf` blocks that passed despite a failing assertion,
reports q 4.0's version correctly, and adds permanent checks for the defect
classes fixed in 2.2.1. It keeps the 2.x DSL, CLI, report-v2 contract and the
`resq-test-case-id-v3` identity algorithm.

## perf blocks report what they check

`perf` blocks run only with `-perf`. The perf runner discarded the measured
body's assertion state, which caused two problems:
- A failing assertion inside a `perf` body reported **pass**.
- Under `-strict`, every `perf` block failed as having asserted nothing, even
  with a `maxTime` budget or assertions in its body.

Now a body failure fails the block. It is reported once, not once per warm-up
and measured iteration. Body assertions and each `maxTime`/`maxSpace` budget
count as checks. Under `-strict`, a block with neither fails with a
perf-specific message.

## q 4.0 is reported as 4.0

`string .z.K` is `"4"` on q 4.0, and that string went into reports,
JUnit/xUnit properties, identity envelopes and benchmark fingerprints. resQ
now writes `4.0` everywhere (`.tst.formatQVersion`); q 4.1 still reads `4.1`.
On q 4.0, rerun and flake state written under `"4"` is archived once on
upgrade, the same as for any identity-envelope change. Benchmark baselines
recorded on q 4.0 report an environment mismatch until they are re-recorded,
or until a run passes `-benchmark-accept-environment`.

## Regression checks for the 2.2.1 defect classes

Each check below fails on 2.2.0:
- **DSL combinations.** `tests/test_dsl_combinations.q` declares every
  ordered pair of 14 constructor forms in one `desc`. Each of the 196 files
  must load and pass, natively and through `bin/qspec`'s loader path.
- **Trap handlers.** `tools/verify_trap_handlers.py` runs inside
  `verify_static.py`. It rejects `@[f;x;h]` and `.[f;x;h]` handlers that take
  more than the error argument without being projected.
- **qspec's value domain.** The upstream qspec differential also runs
  [`pilots/probes/qspec-domain`](../pilots/probes/qspec-domain/README.md), a
  resQ-authored suite. Its `holds` properties hold for every value qspec
  generates, so `bin/qspec` must pass them too. The differential is now 8 runs
  and 206 testcases.

The release gate requires these tests to pass.

## Housekeeping

- The self-suite no longer leaves `resq_isolate_test_*`, `resq_selfcov_*.out`
  and `resq_watch_*` entries in the temp directory. The watch test used to
  delete its work directory while its background watcher was still writing
  there.

## Upgrading from 2.2.1

No source changes are needed. A suite that runs with `-perf` may now go red
where a `perf` body's assertion was already failing unnoticed. On q 4.0,
expect one archived `.resq/*.identity-mismatch.*.bak` per state file after the
first run.
