# resQ 2.4.0 production audit

The sealed candidate qualification passed from a fresh clone at
`f028d034e4b5bc08f13bf0f23f057079cf2096e0` on 2026-11-24. The run used
kdb+/q 4.1 on the supported Linux x86-64 baseline and produced schema-v1
`release-audit.json` naming that exact commit and resQ 2.4.0.

This certification commit adds the audit and compact evidence. It is run
through the same clean-clone gate before the annotated `v2.4.0` tag is created.
A document cannot contain its own Git commit without changing that commit, so
the remote annotated tag and its peeled target are the authoritative final-SHA
record.

## Result

| Contract | Evidence |
|---|---:|
| Strict suite | 1,254 tests; 1,253 pass, 1 documented skip; 4,392 assertions |
| Four-worker isolated suite, random order (seed 505622) | Identical 1,254-test semantic inventory, counts, stable IDs, and verdicts |
| Extended differential corpus | 400 loader seeds and 2,000 coverage seeds |
| Upstream qspec differential | 206 testcases over eight script-style runs (`--junit` and `--xunit`), including resQ's `holds` value-domain probe; names and verdicts match apart from five listed private-API tests |
| Total audit wall time | 743.117 seconds |
| Release-gate steps | 26 / 26 passed |

### Checked quickstart coverage

| Contract | Evidence |
|---|---:|
| Function coverage (gate basis) | 14 / 20 |
| Measured source lines | 48 / 59 |
| Statement sites | 51 / 72 |
| Statement instrumentation completeness | 100% |
| Conditional edges | 19 / 34 |
| Branch instrumentation completeness | 100% |

The self-suite contract now also requires these tests to pass:
- an interrupted `-isolate` run writing no report, no state and no made-up
  timeout, and a run whose launcher was killed stopping itself and removing
  its guard directory;
- the isolation worker pool starting the next file when one ends, and captured
  child output being cut to its start and end;
- a directory fixture refusing a directory that only looks like a database;
- a quarantine manifest written under another q build being applied;
- a run started below the project directory reading the project's
  `resq.json` and keeping state and test IDs with the project.

The gate also passed licence-free contracts, dependency-free Python contracts,
TTY/non-TTY behavior, preprocessing growth, supported execution modes,
distributed merging, property generation and shrinking, flake/quarantine
policy, snapshot-v2 inventory and pruning, benchmark statistics and telemetry,
hostile environments (including INT/TERM/HUP without `setsid` and `pkill`),
bounded labels, normalized ingestion, two checked external pilots, native and
pinned qspec compatibility, repeated-process soak, 10k report/adapter scale
budgets, empty-prefix installation, and correctness/coverage reconciliation.
Its checkout-residue check passed: the run left no new ignored files in the
candidate clone.

The measured preprocessing growth ratios were 1.895 and 2.025 for adjacent
50/100/200-expectation inputs, below the 3.0 fail-closed ceiling. Twenty
post-warm-up same-process soak cycles (including 3 watch cycles) showed zero
growth in used memory, heap, symbols, symbol bytes, namespaces, IPC handles,
and OS handles. The coverage report cost 3,073 ns per entry against its
6,000 ns ceiling. The empty-prefix installation resolved the audited commit,
reported resQ 2.4.0, and passed all 30 quickstart tests and 62 assertions
through installed launchers.

## What the gate caught before this candidate

Three earlier candidates failed the gate and were replaced, not tagged:

- `dadcd8a`: the hostile-environment audit sent SIGINT to an isolated run on a
  machine without `setsid`. The signal reached q while it ran its own code, q
  raised `'stop` in the isolated parent's loop, and the run ended with q's
  trace instead of as an interrupted run. The run is now wrapped so that an
  error while it is marked interrupted ends it as interrupted (`9a580d0`). In
  a stress test the old code failed 1 of 140 signals, the fixed code 0 of 150.
- `fda877d`: the coverage report cost was measured at 6,000.23 ns per entry
  against the 6,000 ns ceiling. The laptop running the gate was on battery
  with a power-saving governor; the same check on the earlier commit varied
  between 3,200 and 6,500 ns there. On mains power it measured about 3,300 ns
  for both, and this candidate measured 3,073 ns.
- `3586025`: the four-worker isolated run in random order failed one test,
  which passed only when another test in its file had run first. The order
  of suites and tests was keyed on each file's absolute path, so the same seed
  gave a different order in each gate clone. The keys now use the path inside
  the project, so a seed replays the same order in any checkout, and the test
  checks what holds in any order (`f028d03`).

## Additional runtime evidence

Outside the release gate, kdb+/q 4.0 (KX build 2023.08.11) ran the complete
26-step gate on the candidate's tree. Only the gate's q-version guards were
relaxed, in a scratch commit on top of the candidate that was not published.
The run reported 1,254 tests, 4,392 assertions and normal/isolated parity in
760.9 seconds. This is compatibility evidence; q 4.0 remains outside the
qualified scope below.

## Scope

Qualified: kdb+/q 4.1.x 64-bit on Linux x86-64. Unqualified and explicitly
out of scope for this audit: other q 4.x releases (q 4.0 is verified, not
release-gated), macOS, Windows, the optional AxLibraries self-coverage
provider, and unlisted external codebases and CI providers.
